import CoreGraphics
import FootballPhysics

/// Procedural top-down pitch texture: mowing stripes + regulation markings.
/// Covers the pitch plus a grass margin; `ppm` pixels per metre.
enum PitchTexture {
    static let margin: Float = 6
    static let ppm: Float = 32
    static var totalLength: Float { PitchSpec.length + 2 * margin }
    static var totalWidth: Float { PitchSpec.width + 2 * margin }

    static func make() -> CGImage? {
        let w = Int(totalLength * ppm), h = Int(totalWidth * ppm)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let P = CGFloat(ppm)
        // World (x,z) metres -> pixel. u = (x + totalLength/2)*ppm ; v = (z + totalWidth/2)*ppm
        func px(_ x: Float) -> CGFloat { CGFloat(x + totalLength / 2) * P }
        func pz(_ z: Float) -> CGFloat { CGFloat(z + totalWidth / 2) * P }

        // Mowing stripes across the length (20 bands of 5.25 m), plus a darker margin.
        let bands = 20
        let bandLen = PitchSpec.length / Float(bands)
        ctx.setFillColor(CGColor(red: 0.12, green: 0.36, blue: 0.13, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        for i in 0..<bands {
            let x0 = -PitchSpec.halfLength + Float(i) * bandLen
            let c: CGFloat = i % 2 == 0 ? 0.0 : 0.045
            ctx.setFillColor(CGColor(red: 0.16 + c, green: 0.46 + c * 1.4, blue: 0.17 + c, alpha: 1))
            ctx.fill(CGRect(x: px(x0), y: pz(-PitchSpec.halfWidth),
                            width: CGFloat(bandLen) * P, height: CGFloat(PitchSpec.width) * P))
        }

        // Markings
        ctx.setStrokeColor(CGColor(red: 0.96, green: 0.97, blue: 0.95, alpha: 1))
        ctx.setFillColor(CGColor(red: 0.96, green: 0.97, blue: 0.95, alpha: 1))
        ctx.setLineWidth(CGFloat(0.12) * P)
        ctx.setLineCap(.square)
        let hl = PitchSpec.halfLength, hw = PitchSpec.halfWidth
        func rect(_ x0: Float, _ z0: Float, _ x1: Float, _ z1: Float) {
            ctx.stroke(CGRect(x: px(min(x0, x1)), y: pz(min(z0, z1)),
                              width: CGFloat(abs(x1 - x0)) * P, height: CGFloat(abs(z1 - z0)) * P))
        }
        func line(_ x0: Float, _ z0: Float, _ x1: Float, _ z1: Float) {
            ctx.move(to: CGPoint(x: px(x0), y: pz(z0))); ctx.addLine(to: CGPoint(x: px(x1), y: pz(z1))); ctx.strokePath()
        }
        func arc(_ cx: Float, _ cz: Float, _ r: Float, _ a0: CGFloat, _ a1: CGFloat) {
            ctx.addArc(center: CGPoint(x: px(cx), y: pz(cz)), radius: CGFloat(r) * P,
                       startAngle: a0, endAngle: a1, clockwise: false)
            ctx.strokePath()
        }
        func dot(_ x: Float, _ z: Float) {
            let r = CGFloat(0.22) * P
            ctx.fillEllipse(in: CGRect(x: px(x) - r, y: pz(z) - r, width: 2 * r, height: 2 * r))
        }

        rect(-hl, -hw, hl, hw)
        line(0, -hw, 0, hw)
        arc(0, 0, PitchSpec.centreCircleRadius, 0, .pi * 2)
        dot(0, 0)

        for s: Float in [-1, 1] {
            let gx = s * hl
            let paD = PitchSpec.penaltyAreaDepth, paW = PitchSpec.penaltyAreaWidth / 2
            rect(gx, -paW, gx - s * paD, paW)
            let gaD = PitchSpec.goalAreaDepth, gaW = PitchSpec.goalAreaWidth / 2
            rect(gx, -gaW, gx - s * gaD, gaW)
            let spotX = gx - s * PitchSpec.penaltySpotDistance
            dot(spotX, 0)
            // Penalty arc: the part of the 9.15 m circle outside the area.
            let d = paD - PitchSpec.penaltySpotDistance
            let a = acos(d / PitchSpec.centreCircleRadius)
            if s > 0 { arc(spotX, 0, PitchSpec.centreCircleRadius, .pi - CGFloat(a), .pi + CGFloat(a)) }
            else { arc(spotX, 0, PitchSpec.centreCircleRadius, -CGFloat(a), CGFloat(a)) }
            // Corner arcs
            for cz: Float in [-1, 1] {
                let cx = gx, czz = cz * hw
                let start: CGFloat, end: CGFloat
                switch (s, cz) {
                case (1, 1): start = .pi; end = 1.5 * .pi
                case (1, -1): start = 0.5 * .pi; end = .pi
                case (-1, 1): start = 1.5 * .pi; end = 2 * .pi
                default: start = 0; end = 0.5 * .pi
                }
                arc(cx, czz, PitchSpec.cornerArcRadius, start, end)
            }
        }
        return ctx.makeImage()
    }

    /// White size-5-ish ball with dark panels (equirectangular).
    static func makeBall() -> CGImage? {
        let w = 512, h = 256
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 1))
        for row in 0..<3 {
            let n = row == 1 ? 6 : 5
            for i in 0..<n {
                let cx = (CGFloat(i) + (row == 1 ? 0.5 : 0)) / CGFloat(n) * CGFloat(w)
                let cy = CGFloat(row == 0 ? 45 : row == 1 ? 128 : 211)
                let r: CGFloat = 26
                ctx.beginPath()
                for k in 0..<5 {
                    let a = CGFloat(k) * 2 * .pi / 5 + .pi / 2
                    let p = CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
                    k == 0 ? ctx.move(to: p) : ctx.addLine(to: p)
                }
                ctx.closePath(); ctx.fillPath()
            }
        }
        return ctx.makeImage()
    }
}
