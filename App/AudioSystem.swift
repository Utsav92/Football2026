import AVFoundation
import FootballAudio
import FootballGame
import simd

/// Match audio: procedural sounds (FootballAudio.Synth) through AVAudioEngine with 3D-positioned effects (AVAudioEnvironmentNode).
/// Crowd intensity follows the match; one-shots are triggered from simulation events. Optional system TTS announcements.
@MainActor
final class AudioSystem {
    private let engine = AVAudioEngine()
    private let env = AVAudioEnvironmentNode()
    private let crowd = AVAudioPlayerNode()
    private let music = AVAudioPlayerNode()
    private var voices: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: Synth.sampleRate, channels: 1)!
    private let speech = AVSpeechSynthesizer()
    private(set) var isRunning = false
    private var crowdTarget: Float = 0.3, crowdLevel: Float = 0.3
    var sfxVolume: Float = 0.9
    var announcements = false
    private(set) var lastStartError: String?
    private(set) var voicesPlayed = 0

    private func buf(_ name: String, _ samples: [Float]) -> AVAudioPCMBuffer {
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        b.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { b.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        buffers[name] = b
        return b
    }

    func start(master: Float, music musicVol: Float, crowdVol: Float, sfx: Float) {
        guard !isRunning else { return }
        sfxVolume = sfx
        engine.attach(env); engine.attach(crowd); engine.attach(music)
        let out = engine.outputNode.inputFormat(forBus: 0)
        engine.connect(env, to: engine.mainMixerNode, format: nil)
        engine.connect(crowd, to: engine.mainMixerNode, format: format)
        engine.connect(music, to: engine.mainMixerNode, format: format)
        env.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        env.distanceAttenuationParameters.referenceDistance = 8; env.distanceAttenuationParameters.maximumDistance = 160
        env.distanceAttenuationParameters.rolloffFactor = 1.2
        for _ in 0..<8 {
            let n = AVAudioPlayerNode(); engine.attach(n); engine.connect(n, to: env, format: format)
            n.renderingAlgorithm = .equalPowerPanning; voices.append(n)
        }
        _ = out
        engine.mainMixerNode.outputVolume = master
        crowd.volume = crowdVol * 0.5; music.volume = musicVol * 0.25
        for (k, s) in [("kick", Synth.kick(power: 0.8)), ("kickSoft", Synth.kick(power: 0.3)), ("bounce", Synth.bounce(speed: 6)), ("whistle", Synth.whistle()),
                       ("whistle3", Synth.whistle(blasts: 3)), ("cheer", Synth.cheer()), ("net", Synth.netRustle()), ("step", Synth.footstep())] { _ = buf(k, s) }
        let crowdBuf = buf("crowd", Synth.crowdLoop()), musicBuf = buf("music", Synth.musicLoop())
        do {
            try engine.start()
            crowd.scheduleBuffer(crowdBuf, at: nil, options: .loops); crowd.play()
            music.scheduleBuffer(musicBuf, at: nil, options: .loops); music.play()
            for v in voices { v.play() }
            isRunning = true
        } catch { lastStartError = "\(error)" }
    }

    func stop() { guard isRunning else { return }; engine.stop(); isRunning = false }
    func setVolumes(master: Float, music m: Float, crowd c: Float, sfx: Float) {
        engine.mainMixerNode.outputVolume = master; music.volume = m * 0.25; crowd.volume = c * 0.5; sfxVolume = sfx
    }

    /// Play a one-shot at a world position (metres; listener = camera).
    func play(_ name: String, at p: SIMD3<Float>? = nil, volume: Float = 1) {
        guard isRunning, let b = buffers[name] else { return }
        let v = voices[nextVoice]; nextVoice = (nextVoice + 1) % voices.count
        if let p { v.position = AVAudio3DPoint(x: p.x, y: p.y, z: p.z) } else { v.position = AVAudio3DPoint(x: 0, y: 0, z: 0) }
        v.volume = volume * sfxVolume
        v.scheduleBuffer(b, at: nil, options: .interrupts)
        voicesPlayed += 1
    }

    func setListener(_ p: SIMD3<Float>) { env.listenerPosition = AVAudio3DPoint(x: p.x, y: p.y, z: p.z) }
    func setCrowd(target: Float) { crowdTarget = max(0.1, min(1, target)) }
    func tick(dt: Float) {
        crowdLevel += (crowdTarget - crowdLevel) * min(1, dt * 1.5)
        crowd.volume = crowdLevel * 0.55 * (engine.mainMixerNode.outputVolume > 0 ? 1 : 0)
    }

    func announce(_ text: String) {
        guard announcements else { return }
        let u = AVSpeechUtterance(string: text); u.rate = 0.5; u.volume = 0.7
        speech.speak(u)                         // generic system voice: deliberately not imitating any commentator
    }

    func handle(_ e: GameEvent, sim: MatchSimulation, names: (String, String)) {
        func pos(_ i: Int) -> SIMD3<Float> { SIMD3(sim.players[i].pos.x, 0.3, sim.players[i].pos.y) }
        switch e {
        case .kick(let p, _, let power): play(power > 0.6 ? "kick" : "kickSoft", at: pos(p), volume: 0.5 + 0.5 * power)
        case .ball(.bounce(let s)): play("bounce", at: sim.ball.position, volume: min(1, s / 8))
        case .ball(.woodwork): play("kick", at: sim.ball.position, volume: 0.9)
        case .ball(.net): play("net", at: sim.ball.position)
        case .goal(let side, _): play("cheer", volume: 1); play("whistle"); crowdTarget = 1
            announce("Goal for \(side == .home ? names.0 : names.1)!")
        case .foul, .offside: play("whistle")
        case .restart(let k, _): if k == .kickoff { play("whistle") }
        case .halfTime, .fullTime: play("whistle3"); announce(e == .halfTime ? "Half time." : "Full time.")
        case .save: play("kickSoft", at: sim.ball.position); crowdTarget = max(crowdTarget, 0.75)
        case .tackle(_, _, let won): if won { play("step", volume: 1) }
        default: break
        }
    }
}
