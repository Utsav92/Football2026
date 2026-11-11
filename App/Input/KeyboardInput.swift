import AppKit
import FootballPhysics
import FootballInput

/// Development keyboard mapping.
///   WASD / arrows move · Shift sprint · E pass · Space shoot · F lob/cross · G through ball
///   Z finesse (with Space) · Ctrl jockey/shield · I/J/K/L skill moves · Q switch player · X tackle · V slide tackle · C camera · B AI debug overlay · Esc pause · R restart
final class KeyboardInput {
    private var down = Set<UInt16>()
    private var edges = Set<UInt16>()
    private var shift = false
    private var control = false
    private var monitor: Any?

    private enum K {
        static let w: UInt16 = 13, a: UInt16 = 0, s: UInt16 = 1, d: UInt16 = 2
        static let up: UInt16 = 126, downA: UInt16 = 125, left: UInt16 = 123, right: UInt16 = 124
        static let e: UInt16 = 14, space: UInt16 = 49, f: UInt16 = 3, g: UInt16 = 5, q: UInt16 = 12
        static let t: UInt16 = 17, ret: UInt16 = 36, z: UInt16 = 6, i: UInt16 = 34, k: UInt16 = 40, j: UInt16 = 38, l: UInt16 = 37, x: UInt16 = 7, v: UInt16 = 9, c: UInt16 = 8, b: UInt16 = 11, esc: UInt16 = 53, r: UInt16 = 15, tab: UInt16 = 48
        static let handled: Set<UInt16> = [w, a, s, d, up, downA, left, right, e, space, f, g, q, x, v, c, b, esc, r, tab, t, ret, z, i, k, j, l]
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .flagsChanged: self.shift = event.modifierFlags.contains(.shift); self.control = event.modifierFlags.contains(.control); return event
            case .keyDown:
                guard K.handled.contains(event.keyCode), !event.modifierFlags.contains(.command) else { return event }
                if !event.isARepeat { self.down.insert(event.keyCode); self.edges.insert(event.keyCode) }
                return nil
            case .keyUp:
                guard K.handled.contains(event.keyCode) else { return event }
                self.down.remove(event.keyCode); return nil
            default: return event
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.down.removeAll(); self?.shift = false
        }
    }

    func poll() -> ControlState {
        var s = ControlState()
        if down.contains(K.w) || down.contains(K.up) { s.stick.y += 1 }
        if down.contains(K.s) || down.contains(K.downA) { s.stick.y -= 1 }
        if down.contains(K.d) || down.contains(K.right) { s.stick.x += 1 }
        if down.contains(K.a) || down.contains(K.left) { s.stick.x -= 1 }
        s.sprint = shift
        s.pass = down.contains(K.e); s.shoot = down.contains(K.space); s.lob = down.contains(K.f); s.through = down.contains(K.g)
        s.tackle = down.contains(K.x); s.slide = down.contains(K.v)
        s.switchPlayer = down.contains(K.q) || down.contains(K.tab)
        s.cameraCycle = edges.contains(K.c); s.debugToggle = edges.contains(K.b)
        s.pauseToggle = edges.contains(K.esc); s.restart = edges.contains(K.r)
        s.replay = edges.contains(K.t); s.confirm = edges.contains(K.ret)
        s.finesse = down.contains(K.z); s.jockey = control
        if down.contains(K.i) { s.skillStick.y += 1 }; if down.contains(K.k) { s.skillStick.y -= 1 }
        if down.contains(K.l) { s.skillStick.x += 1 }; if down.contains(K.j) { s.skillStick.x -= 1 }
        edges.removeAll()
        return s
    }
}
