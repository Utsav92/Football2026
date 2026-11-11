import simd

public typealias Vec3 = SIMD3<Float>
public typealias Vec2 = SIMD2<Float>

/// Regulation (IFAB / FIFA Laws of the Game) dimensions in metres.
/// World axes: +X along the pitch (towards the "home" attacking goal), +Y up, +Z across the pitch.
/// Origin is the centre spot.
public enum PitchSpec {
    public static let length: Float = 105
    public static let width: Float = 68
    public static let halfLength: Float = length / 2
    public static let halfWidth: Float = width / 2

    public static let goalWidth: Float = 7.32
    public static let goalHeight: Float = 2.44
    public static let goalDepth: Float = 2.0
    public static let postRadius: Float = 0.06

    public static let penaltyAreaDepth: Float = 16.5
    public static let penaltyAreaWidth: Float = 40.32
    public static let goalAreaDepth: Float = 5.5
    public static let goalAreaWidth: Float = 18.32
    public static let penaltySpotDistance: Float = 11
    public static let centreCircleRadius: Float = 9.15
    public static let cornerArcRadius: Float = 1.0

    public static let ballRadius: Float = 0.11   // FIFA size 5 (circumference ~69 cm)
    public static let ballMass: Float = 0.43
    public static let gravity: Float = 9.81
}
