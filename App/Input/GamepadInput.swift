import GameController
import FootballInput
import FootballPhysics

/// GameController adapter: DualShock/DualSense (and any extended gamepad) -> `PadState`. Handles hot-plug and reconnection.
@MainActor
final class GamepadInput {
    private(set) var controllers: [GCController] = []
    var onChange: ((String) -> Void)?
    private var tokens: [NSObjectProtocol] = []
    private var prevOptions: [Int: Bool] = [:]

    init() {
        let nc = NotificationCenter.default
        tokens.append(nc.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] n in
            MainActor.assumeIsolated { if let c = n.object as? GCController { self?.add(c) } }
        })
        tokens.append(nc.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] n in
            MainActor.assumeIsolated { if let c = n.object as? GCController { self?.remove(c) } }
        })
        GCController.shouldMonitorBackgroundEvents = false
        for c in GCController.controllers() { add(c, silent: true) }
        GCController.startWirelessControllerDiscovery {}
    }

    private func add(_ c: GCController, silent: Bool = false) {
        guard !controllers.contains(c), c.extendedGamepad != nil else { return }
        controllers.append(c)
        c.playerIndex = GCControllerPlayerIndex(rawValue: min(controllers.count - 1, 3)) ?? .indexUnset
        if !silent { onChange?("Controller connected: \(c.vendorName ?? "Gamepad") (player \(controllers.count))") }
    }
    private func remove(_ c: GCController) {
        controllers.removeAll { $0 == c }
        onChange?("Controller disconnected: \(c.vendorName ?? "Gamepad")")
    }

    var count: Int { controllers.count }
    var names: [String] { controllers.map { $0.vendorName ?? "Gamepad" } }

    /// Current state of the controller in `slot` (nil if absent). PlayStation naming: A=Cross, B=Circle, X=Square, Y=Triangle.
    func pad(slot: Int) -> PadState? {
        guard slot < controllers.count, let g = controllers[slot].extendedGamepad else { return nil }
        var p = PadState()
        p.leftStick = Vec2(g.leftThumbstick.xAxis.value, g.leftThumbstick.yAxis.value)
        p.rightStick = Vec2(g.rightThumbstick.xAxis.value, g.rightThumbstick.yAxis.value)
        p.l2 = g.leftTrigger.value; p.r2 = g.rightTrigger.value
        func add(_ b: GCControllerButtonInput?, _ k: PadButton) { if b?.isPressed == true { p.pressed.insert(k) } }
        add(g.buttonA, .cross); add(g.buttonB, .circle); add(g.buttonX, .square); add(g.buttonY, .triangle)
        add(g.leftShoulder, .l1); add(g.rightShoulder, .r1); add(g.buttonMenu, .options)
        add(g.leftThumbstickButton, .l3); add(g.rightThumbstickButton, .r3)
        if g.dpad.up.isPressed { p.pressed.insert(.dpadUp) }; if g.dpad.down.isPressed { p.pressed.insert(.dpadDown) }
        if g.dpad.left.isPressed { p.pressed.insert(.dpadLeft) }; if g.dpad.right.isPressed { p.pressed.insert(.dpadRight) }
        return p
    }

    /// Edge detector for the Options (pause) button.
    func optionsPressedEdge(slot: Int) -> Bool {
        let now = pad(slot: slot)?.pressed.contains(.options) ?? false
        defer { prevOptions[slot] = now }
        return now && !(prevOptions[slot] ?? false)
    }
}
