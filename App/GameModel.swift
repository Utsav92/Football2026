import SwiftUI
import RealityKit
import Darwin.Mach
import FootballGame
import FootballPhysics
import FootballInput

struct MiniDot: Identifiable { let id: Int; var x: Float; var z: Float; var team: TeamSide; var controlled: Bool; var isBall: Bool }
struct SummaryRow: Identifiable { let id = UUID(); let label: String; let home: String; let away: String }
struct SubCandidate: Identifiable { let id: Int; let slot: Int; let label: String; let stamina: Float }

/// One match: glue between the render-independent simulation and RealityKit scene / HUD / audio / input.
@MainActor @Observable
final class GameModel {
    // HUD state (written only when changed)
    var homeName = "HOME"
    var awayName = "AWAY"
    var homeColor = Color.red
    var awayColor = Color.blue
    var homeScore = 0
    var awayScore = 0
    var clockText = "00:00"
    var banner: String?
    var subBanner: String?
    var toast: String?
    var chargeLevel: Float = 0
    var charging = false
    var chargeKind = "PASS"
    var playerName = ""
    var playerNumber = 0
    var playerRole = ""
    var playerStamina: Float = 1
    var possessionHome = 50
    var shotsText = "0 – 0"
    var fps = 0
    var cameraName = "Broadcast"
    var debugOn = false
    var paused = false
    var minimap: [MiniDot] = []
    var debugCounts: [(String, Int)] = []
    var lodText = ""
    var frameMS: Float = 0
    var replayActive = false
    var summaryVisible = false
    var summaryTitle = ""
    var summaryRows: [SummaryRow] = []
    var subsLeft = 5
    var subPrompt = false
    var onPitch: [SubCandidate] = []
    var bench: [SubCandidate] = []
    var controllerText = "Keyboard"
    var trainingText = ""
    var finished = false
    var shootoutText = ""

    @ObservationIgnored let session: MatchSession
    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored var sim: MatchSimulation
    @ObservationIgnored var training: TrainingSession?
    @ObservationIgnored private var viewer: MatchSimulation
    @ObservationIgnored private var stepper = FixedStepper(step: MatchSimulation.dt)
    @ObservationIgnored let keyboard: KeyboardInput
    @ObservationIgnored let gamepad: GamepadInput
    @ObservationIgnored let audio: AudioSystem
    @ObservationIgnored let world = PitchScene()
    @ObservationIgnored var cameraRig = CameraRig()
    @ObservationIgnored private var updateSub: EventSubscription?
    @ObservationIgnored private var recorder = ReplayRecorder(seconds: 14)
    @ObservationIgnored private var replay: ReplayPlayer?
    @ObservationIgnored private var savedCamera: CameraMode = .broadcast
    @ObservationIgnored private var fpsAccum: Float = 0
    @ObservationIgnored private var fpsFrames = 0
    @ObservationIgnored private var frameAccum: Float = 0
    @ObservationIgnored private var bannerTimer: Float = 0
    @ObservationIgnored private var miniTimer: Float = 0
    @ObservationIgnored private var toastTimer: Float = 0
    @ObservationIgnored private var buttonBuffer = ButtonBuffer()
    @ObservationIgnored private var assignments = PlayerAssignments()
    @ObservationIgnored private var aiSubsDone: [TeamSide: Int] = [.home: 0, .away: 0]
    @ObservationIgnored private var usedBench: [TeamSide: Set<Int>] = [.home: [], .away: []]
    @ObservationIgnored private var lastAISubMinute = -1
    @ObservationIgnored private var crowd: Float = 0.3
    @ObservationIgnored private var outcomeSent = false
    @ObservationIgnored let autoplay = CommandLine.arguments.contains("--autoplay")
    @ObservationIgnored let perfLogging = CommandLine.arguments.contains("--perf")
    @ObservationIgnored private var perfClock: Float = 0
    @ObservationIgnored private var perfFrames = 0
    @ObservationIgnored private var perfCPU: [Float] = []
    @ObservationIgnored var onFinish: ((MatchOutcome) -> Void)?
    @ObservationIgnored let humans: Set<TeamSide>
    @ObservationIgnored var humanSide: TeamSide? { humans.contains(.home) ? .home : humans.first }
    @ObservationIgnored private var perfLog: [Float] = []
    @ObservationIgnored private var mirroredNow = false
    @ObservationIgnored var cameraOverride: (SIMD3<Float>, SIMD3<Float>)?       // verification only
    /// Teams change ends for the second half and the second extra-time period: shown as a 180° rotation of the world (engine unchanged).
    private var shouldMirror: Bool { training == nil && (sim.clock.half == 2 || sim.clock.half == 4) }

    init(session: MatchSession, settings: AppSettings, keyboard: KeyboardInput, gamepad: GamepadInput, audio: AudioSystem) {
        var cfg = session.config
        if CommandLine.arguments.contains("--autoplay") { cfg.humanTeams = [] }
        cfg.wetPitch = session.weather == .rain
        cfg.knockout = session.knockout
        self.session = session; self.settings = settings; self.keyboard = keyboard; self.gamepad = gamepad; self.audio = audio
        if case .training(let kind) = session.mode {
            let t = TrainingSession(kind: kind, home: cfg.home, away: cfg.away, seed: cfg.seed)
            training = t; sim = t.sim
        } else { sim = MatchSimulation(config: cfg) }
        viewer = MatchSimulation(config: cfg)
        humans = sim.config.humanTeams
        homeName = cfg.home.shortName; awayName = cfg.away.shortName
        func col(_ c: ColorRGB) -> Color { Color(red: Double(c.r), green: Double(c.g), blue: Double(c.b)) }
        homeColor = col(cfg.home.primary); awayColor = col(cfg.away.primary)
        cameraRig.autoSetPiece = settings.value.autoSetPieceCamera
        if let m = CameraMode(rawValue: settings.value.defaultCamera) { cameraRig.mode = m; cameraName = m.name }
        refreshSubLists()
    }

    func start(content: inout RealityViewCameraContent) async {
        keyboard.start()
        await CharacterAssets.shared.load()
        func ns(_ c: ColorRGB) -> NSColor { NSColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: 1) }
        var o = PitchScene.SceneOptions()
        o.preset = settings.value.graphics; o.timeOfDay = session.timeOfDay; o.weather = session.weather
        o.home = ns(sim.config.home.primary); o.away = ns(sim.config.away.primary); o.homeName = homeName; o.awayName = awayName
        await world.build(sim: sim, options: o)
        content.camera = .virtual
        content.add(world.root); content.add(world.cameraEntity)
        if CommandLine.arguments.contains("--debug") { debugOn = true; world.debugEnabled = true }
        if let i = CommandLine.arguments.firstIndex(of: "--camera"), i + 1 < CommandLine.arguments.count,
           let n = Int(CommandLine.arguments[i + 1]), let m = CameraMode(rawValue: n) { cameraRig.mode = m; cameraName = m.name }
        cameraRig.snap(sim, side: humanSide)
        let s = settings.value
        audio.announcements = s.announcements
        audio.start(master: s.masterVolume, music: s.musicVolume, crowdVol: s.crowdVolume, sfx: s.sfxVolume)
        gamepad.onChange = { [weak self] msg in self?.flashToast(msg); if msg.contains("disconnected"), self?.humans.isEmpty == false { self?.paused = true } }
        for i in 0..<gamepad.count { assignments.connect(slot: i, versus: humans.count > 1) }
        updateSub = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            MainActor.assumeIsolated { self?.frame(dt: Float(event.deltaTime)) }
        }
    }

    func teardown() { audio.stop(); updateSub?.cancel(); updateSub = nil }

    // MARK: Input

    private func merged(_ kb: ControlState, _ pad: ControlState?) -> ControlState {
        guard var p = pad else { return kb }
        if simd_length(p.stick) < 0.01 { p.stick = kb.stick }
        p.sprint = p.sprint || kb.sprint; p.pass = p.pass || kb.pass; p.shoot = p.shoot || kb.shoot; p.lob = p.lob || kb.lob; p.through = p.through || kb.through
        p.finesse = p.finesse || kb.finesse; p.jockey = p.jockey || kb.jockey; if simd_length(p.skillStick) < 0.01 { p.skillStick = kb.skillStick }
        p.tackle = p.tackle || kb.tackle; p.slide = p.slide || kb.slide; p.switchPlayer = p.switchPlayer || kb.switchPlayer
        p.cameraCycle = kb.cameraCycle; p.debugToggle = kb.debugToggle; p.restart = kb.restart; p.pauseToggle = p.pauseToggle || kb.pauseToggle
        return p
    }

    private func context(for side: TeamSide) -> ControlContext {
        if let o = sim.ballOwner { return sim.players[o].team == side ? .attack : .defense }
        if let l = sim.lastTouch { return sim.players[l].team == side ? .attack : .defense }
        return .attack
    }

    private func controlStates() -> (ControlState, [TeamSide: ControlState]) {
        let kb = keyboard.poll()
        var out: [TeamSide: ControlState] = [:]
        let s = settings.value
        for side in humans {
            let slot: Int? = humans.count > 1 ? (side == .home ? 0 : 1) : 0
            var pad: ControlState?
            if let slot, let ps = gamepad.pad(slot: slot) { pad = ControlMapper.map(ps, context: context(for: side), bindings: s.bindings, settings: s.controller) }
            let useKB = humans.count == 1 || side == .home && gamepad.count < 2 || (gamepad.count == 0 && side == .home)
            out[side] = merged(useKB ? kb : ControlState(), pad)
        }
        return (kb, out)
    }

    // MARK: Frame

    private func frame(dt: Float) {
        let t0 = DispatchTime.now().uptimeNanoseconds
        let (kb, states) = controlStates()
        var pauseEdge = kb.pauseToggle
        for i in 0..<min(2, gamepad.count) where gamepad.optionsPressedEdge(slot: i) { pauseEdge = true }
        if pauseEdge, !summaryVisible || sim.phase != .fullTime { paused.toggle(); if paused { refreshSubLists() } }
        if kb.cameraCycle { cameraRig.cycle(); cameraName = cameraRig.mode.name }
        if kb.debugToggle { debugOn.toggle(); world.debugEnabled = debugOn }
        if kb.replay, replay == nil { startReplay() } else if kb.replay, replay != nil { stopReplay() }
        if kb.restart, sim.phase == .fullTime, training == nil { sim.restartMatch(); summaryVisible = false }
        if kb.confirm { if replay != nil { stopReplay() } else if summaryVisible, sim.phase == .fullTime { finishMatch() } }
        controllerText = gamepad.count == 0 ? "Keyboard" : gamepad.names.joined(separator: " · ")

        if replay != nil {
            replayStep(dt)
        } else if !paused {
            var inputs: [TeamSide: PlayerInput] = [:]
            for (side, st) in states {
                var pi = st.playerInput(right: cameraRig.inputRight, up: cameraRig.inputUp)
                if mirroredNow { pi.move = -pi.move; pi.skill = -pi.skill }
                inputs[side] = pi
            }
            let n = stepper.advance(frameTime: dt)
            for _ in 0..<n {
                if let tr = training { tr.step(inputs[.home] ?? PlayerInput()) } else { sim.step(inputs) }
                recorder.record(sim)
            }
            for e in sim.drainEvents() { handle(e) }
            aiSubstitutions()
        }
        mirroredNow = shouldMirror
        if replay == nil, mirroredNow { viewer.mirrorPresentation(from: sim, mirrored: true) }
        let renderSim = (replay != nil || mirroredNow) ? viewer : sim
        var controlled: [TeamSide: Int] = [:]
        if replay == nil { for s in humans { if let i = sim.controlled(s) { controlled[s] = i } } }
        updateCrowd(dt: dt)
        world.sync(sim: renderSim, dt: paused ? 0 : dt, cameraPos: cameraRig.position, controlled: controlled, crowd: crowd)
        var restart: RestartInfo?
        if case .restart(var r) = sim.phase, replay == nil { if mirroredNow { r.spot = -r.spot }; restart = r }
        cameraRig.update(renderSim, side: humanSide, dt: dt, restart: restart, flip: mirroredNow)
        world.applyCamera(cameraRig)
        audio.setListener(cameraRig.position); audio.tick(dt: dt)
        publishHUD(dt: dt)
        let ms = Float(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
        frameAccum += ms
        if perfLog.count < 600 { perfLog.append(ms) }
        if perfLogging {
            perfClock += dt; perfFrames += 1; perfCPU.append(ms)
            if perfClock >= 5 {
                let sorted = perfCPU.sorted()
                var info = mach_task_basic_info(); var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
                _ = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) } }
                print(String(format: "LIVEPERF fps %.1f | main-thread frame work mean %.2f ms p95 %.2f ms max %.2f ms | rss %.0f MB | match clock %@ | window %@",
                             Double(perfFrames) / Double(perfClock), Double(perfCPU.reduce(0, +)) / Double(perfCPU.count), Double(sorted[Int(Double(sorted.count - 1) * 0.95)]), Double(sorted.last!),
                             Double(info.resident_size) / 1e6, sim.clock.display, NSApp.windows.first.map { "\(Int($0.frame.width))x\(Int($0.frame.height))" } ?? "?"))
                fflush(stdout); perfClock = 0; perfFrames = 0; perfCPU.removeAll()
            }
        }
        if autoplay, sim.phase == .fullTime, !outcomeSent { finishMatch() }
    }

    /// Offscreen verification path: advance the simulation and keep the scene/camera in sync without the RealityView update loop.
    func headlessAdvance(_ dt: Float) {
        let n = stepper.advance(frameTime: dt)
        for _ in 0..<n { if let tr = training { tr.step(PlayerInput()) } else { sim.step([:]) }; recorder.record(sim) }
        for e in sim.drainEvents() { handle(e) }
        updateCrowd(dt: dt)
        mirroredNow = shouldMirror
        if mirroredNow { viewer.mirrorPresentation(from: sim, mirrored: true) }
        let rs = mirroredNow ? viewer : sim
        world.sync(sim: rs, dt: dt, cameraPos: cameraRig.position, controlled: [:], crowd: crowd)
        var restart: RestartInfo?
        if case .restart(var r) = sim.phase { if mirroredNow { r.spot = -r.spot }; restart = r }
        cameraRig.update(rs, side: humanSide, dt: dt, restart: restart, flip: mirroredNow)
        world.applyCamera(cameraRig)
        if let o = cameraOverride { world.cameraEntity.look(at: o.1, from: o.0, relativeTo: nil) }
        world.stadium.updateScoreboard(hs: sim.score.home, aw: sim.score.away, seconds: sim.clock.gameSeconds)
    }

    private func updateCrowd(dt: Float) {
        let bx = abs(sim.ball.position.x) / PitchSpec.halfLength
        var target: Float = 0.25 + 0.35 * bx * bx
        if case .goalCelebration = sim.phase { target = 1 }
        if case .restart(let r) = sim.phase, r.kind == .penalty { target = 0.7 }
        crowd += (target - crowd) * min(1, dt * 1.2)
        audio.setCrowd(target: crowd)
    }

    // MARK: Events

    private func flash(_ text: String, sub: String? = nil, seconds: Float = 2.2) { banner = text; subBanner = sub; bannerTimer = seconds }
    private func flashToast(_ text: String) { toast = text; toastTimer = 3 }
    private func name(_ i: Int) -> String { "#\(sim.players[i].number) \(sim.players[i].name)" }

    private func handle(_ e: GameEvent) {
        audio.handle(e, sim: sim, names: (sim.config.home.name, sim.config.away.name))
        switch e {
        case .goal(let side, let scorer):
            flash("GOAL!", sub: scorer.map { name($0) } ?? (side == .home ? homeName : awayName), seconds: 3.5)
            if training == nil { startReplay(delay: true) }
        case .foul(let by, _, let card, let pen):
            let c = card == .red ? "RED CARD" : (card == .yellow ? "YELLOW CARD" : "FOUL")
            flash(pen ? "PENALTY" : c, sub: pen && card != nil ? c + " · " + name(by) : name(by), seconds: 2.4)
        case .offside(let p): flash("OFFSIDE", sub: name(p))
        case .restart(let kind, _):
            if kind == .kickoff, sim.clock.half == 2 || sim.clock.half == 4 { flashToast("Teams change ends") }
            switch kind { case .throwIn: flash("THROW-IN", seconds: 1.3); case .corner: flash("CORNER", seconds: 1.3); case .goalKick: flash("GOAL KICK", seconds: 1.3); default: break }
        case .save(_, let caught): if !caught { flash("SAVE!", seconds: 1.0) }
        case .halfTime:
            let t = sim.clock.half == 1 ? "HALF TIME" : (sim.clock.half == 2 ? "FULL TIME · EXTRA TIME" : "EXTRA TIME · HALF TIME")
            flash(t, sub: "\(homeName) \(sim.score.home) – \(sim.score.away) \(awayName)", seconds: 6)
            showSummary(t)
        case .extraTimeStart: flash("EXTRA TIME", seconds: 3); summaryVisible = false
        case .shootoutStart: flash("PENALTY SHOOTOUT", seconds: 3); summaryVisible = false
        case .shootoutKick(let team, let scored):
            flash(scored ? "SCORED" : "MISSED", sub: "\(team == .home ? homeName : awayName)", seconds: 1.8)
            let s = sim.shootout; shootoutText = "\(homeName) \(s.scored[0]) – \(s.scored[1]) \(awayName)  (\(s.taken[0] + s.taken[1]) kicks)"
        case .advantage: flash("ADVANTAGE", seconds: 1.5)
        case .fullTime:
            flash("FULL TIME", sub: "\(homeName) \(sim.score.home) – \(sim.score.away) \(awayName)", seconds: 3600)
            showSummary("FULL TIME")
        case .substitution(let side, _, let inn): flashToast("\(side == .home ? homeName : awayName): substitution (#\(inn) on)")
        default: break
        }
        if case .restart = sim.phase, summaryVisible, sim.phase != .fullTime { summaryVisible = false }
    }

    // MARK: Summary / finish

    private func pct(_ a: Int, _ b: Int) -> String { b == 0 ? "–" : "\(a * 100 / b)%" }
    private func showSummary(_ title: String) {
        summaryTitle = title
        let h = sim.stats[0], a = sim.stats[1]
        let pp = sim.possessionPercent
        summaryRows = [
            SummaryRow(label: "Possession", home: "\(pp.home)%", away: "\(pp.away)%"),
            SummaryRow(label: "Shots", home: "\(h.shots)", away: "\(a.shots)"),
            SummaryRow(label: "On target", home: "\(h.shotsOnTarget)", away: "\(a.shotsOnTarget)"),
            SummaryRow(label: "Passes (completed)", home: "\(h.passes) (\(pct(h.passesCompleted, h.passes)))", away: "\(a.passes) (\(pct(a.passesCompleted, a.passes)))"),
            SummaryRow(label: "Tackles won", home: "\(h.tacklesWon)/\(h.tackles)", away: "\(a.tacklesWon)/\(a.tackles)"),
            SummaryRow(label: "Saves", home: "\(h.saves)", away: "\(a.saves)"),
            SummaryRow(label: "Fouls", home: "\(h.fouls)", away: "\(a.fouls)"),
            SummaryRow(label: "Yellow / red", home: "\(h.yellowCards) / \(h.redCards)", away: "\(a.yellowCards) / \(a.redCards)"),
            SummaryRow(label: "Corners", home: "\(h.corners)", away: "\(a.corners)"),
            SummaryRow(label: "Offsides", home: "\(h.offsides)", away: "\(a.offsides)"),
        ]
        summaryVisible = true
    }

    func finishMatch() {
        guard !outcomeSent else { return }
        outcomeSent = true; finished = true
        teardown()
        onFinish?(MatchOutcome(homeGoals: sim.score.home, awayGoals: sim.score.away, stats: sim.stats, shootoutWinner: sim.shootoutWinner, extraTime: sim.clock.half >= 3))
    }

    // MARK: Replay

    private func startReplay(delay: Bool = false) {
        let frames = recorder.clip(lastSeconds: 6)
        guard frames.count > 20 else { return }
        savedCamera = cameraRig.mode
        cameraRig.mode = .replay; cameraName = CameraMode.replay.name
        replay = ReplayPlayer(frames: frames, speed: 0.5)
        replayActive = true
    }
    private func stopReplay() {
        replay = nil; replayActive = false
        cameraRig.mode = savedCamera; cameraName = savedCamera.name
    }
    private func replayStep(_ dt: Float) {
        guard var r = replay else { return }
        r.advance(dt); replay = r
        if let f = r.sample() { viewer.apply(f, mirrored: mirroredNow) }
        if r.isFinished { stopReplay() }
    }

    // MARK: Substitutions

    func refreshSubLists() {
        guard let side = humanSide else { return }
        let setup = sim.teamSetup(side)
        subsLeft = 5 - sim.substitutionsUsed(side)
        onPitch = sim.players.filter { $0.team == side && $0.slot > 0 && $0.onPitch }.map { SubCandidate(id: $0.id, slot: $0.slot, label: "#\($0.number) \($0.name) (\($0.role.rawValue.uppercased()))", stamina: $0.stamina) }
        bench = setup.players.dropFirst(11).enumerated().filter { !usedBench[side, default: []].contains($0.offset) }
            .map { SubCandidate(id: $0.offset, slot: $0.offset, label: "#\($0.element.number) \($0.element.name) (\($0.element.role.rawValue.uppercased()))", stamina: 1) }
    }

    func substitute(slot: Int, bench b: Int) {
        guard let side = humanSide, sim.substitute(side, slot: slot, with: b) else { flashToast("Substitution not allowed"); return }
        usedBench[side, default: []].insert(b); refreshSubLists()
    }

    /// AI teams change tired outfielders at 60', 75' and 85' (one swap per window, same-line replacement from the bench).
    private func aiSubstitutions() {
        guard training == nil else { return }
        let minute = Int(sim.clock.gameSeconds / 60)
        guard [60, 75, 85].contains(minute), minute != lastAISubMinute else { return }
        lastAISubMinute = minute
        for side in TeamSide.allCases where !humans.contains(side) {
            guard sim.substitutionsUsed(side) < 5 else { continue }
            let tired = sim.players.filter { $0.team == side && $0.slot > 0 && $0.onPitch }.min { $0.stamina < $1.stamina }
            let bench = sim.teamSetup(side).players.dropFirst(11).enumerated().filter { !usedBench[side, default: []].contains($0.offset) && $0.element.role != .gk }
            guard let t = tired, let b = bench.first(where: { $0.element.role.line == t.role.line }) ?? bench.first else { continue }
            if sim.substitute(side, slot: t.slot, with: b.offset) { usedBench[side, default: []].insert(b.offset) }
        }
    }

    // MARK: HUD

    private func publishHUD(dt: Float) {
        if homeScore != sim.score.home { homeScore = sim.score.home }
        if awayScore != sim.score.away { awayScore = sim.score.away }
        let c = sim.clock.display + (sim.clock.half == 1 ? "  1H" : "  2H")
        if clockText != c { clockText = c }
        if bannerTimer > 0 { bannerTimer -= dt; if bannerTimer <= 0 { banner = nil; subBanner = nil } }
        if toastTimer > 0 { toastTimer -= dt; if toastTimer <= 0 { toast = nil } }
        if let side = humanSide, let ci = sim.controlled(side) {
            let p = sim.players[ci]
            if playerName != p.name { playerName = p.name }
            if playerNumber != p.number { playerNumber = p.number }
            if playerRole != p.role.rawValue.uppercased() { playerRole = p.role.rawValue.uppercased() }
            if abs(playerStamina - p.stamina) > 0.005 { playerStamina = p.stamina }
            let low = p.stamina < 0.2 && sim.substitutionsUsed(side) < 5
            if subPrompt != low { subPrompt = low }
            let ch = sim.charge(side)
            if charging != (ch != nil) { charging = ch != nil }
            let lvl = ch?.level ?? 0
            if abs(chargeLevel - lvl) > 0.01 { chargeLevel = lvl }
            if let k = ch?.kind {
                let t: String
                switch k { case .pass: t = "PASS"; case .through: t = "THROUGH BALL"; case .lob: t = "CROSS / LOB"; case .shot, .volley: t = "SHOT"; case .header: t = "HEADER" }
                if chargeKind != t { chargeKind = t }
            }
        }
        let pp = sim.possessionPercent.home
        if possessionHome != pp { possessionHome = pp }
        let st = "\(sim.stats[0].shots) – \(sim.stats[1].shots)"
        if shotsText != st { shotsText = st }
        if let tr = training {
            let t: String
            switch tr.kind {
            case .passing: t = "Completed passes: \(tr.passesCompleted)"
            case .freePractice: t = "Free practice"
            default: t = "Attempts \(tr.attempts) · Goals \(tr.goals) · Saved \(tr.saves) · Streak \(tr.streak)"
            }
            if trainingText != t { trainingText = t }
        }
        miniTimer += dt
        if miniTimer > 0.08 {
            miniTimer = 0
            var dots = sim.players.filter { $0.onPitch }.map { MiniDot(id: $0.id, x: $0.pos.x * (mirroredNow ? -1 : 1), z: $0.pos.y * (mirroredNow ? -1 : 1), team: $0.team, controlled: humans.contains($0.team) && sim.controlled($0.team) == $0.id, isBall: false) }
            dots.append(MiniDot(id: 99, x: sim.ball.position.x * (mirroredNow ? -1 : 1), z: sim.ball.position.z * (mirroredNow ? -1 : 1), team: .home, controlled: false, isBall: true))
            minimap = dots
            if debugOn {
                var counts: [AIState: Int] = [:]
                for p in sim.players where p.onPitch { counts[p.state, default: 0] += 1 }
                debugCounts = counts.sorted { $0.value > $1.value }.map { ($0.key.label, $0.value) }
            }
            let l = world.lodSummary; lodText = "LOD near \(l.near) / far \(l.far)"
            world.stadium.updateScoreboard(hs: sim.score.home, aw: sim.score.away, seconds: sim.clock.gameSeconds)
        }
        fpsAccum += dt; fpsFrames += 1
        if fpsAccum >= 0.5 {
            fps = Int(Float(fpsFrames) / fpsAccum); frameMS = frameAccum / Float(max(fpsFrames, 1)); fpsAccum = 0; fpsFrames = 0; frameAccum = 0
        }
    }

    /// Mean / 95th percentile CPU frame time (ms) over the first ~600 frames; used for the performance report.
    var perfSummary: (mean: Float, p95: Float, frames: Int) {
        guard !perfLog.isEmpty else { return (0, 0, 0) }
        let s = perfLog.sorted()
        return (perfLog.reduce(0, +) / Float(perfLog.count), s[Int(Float(s.count - 1) * 0.95)], perfLog.count)
    }
}
