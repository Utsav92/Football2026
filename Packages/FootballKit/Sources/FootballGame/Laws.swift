import Foundation
import simd
import FootballPhysics

/// Pure functions implementing the supported subset of the Laws of the Game.
/// Versioned so tests and docs can state exactly which rules are implemented.
public enum Laws {
    public static let version = "IFAB Laws of the Game (subset) v1 — offside, throw-in, corner, goal kick, free kick, penalty, cards"

    /// Offside position (Law 11) at the moment the ball is played.
    /// `attackSign` is the attacking direction of the receiver's team; `opponentXs` includes the goalkeeper.
    public static func isOffside(receiverX: Float, ballX: Float, opponentXs: [Float], attackSign: Float) -> Bool {
        let a = receiverX * attackSign
        guard a > 0, a > ballX * attackSign else { return false }   // own half or level/behind the ball: onside
        let sorted = opponentXs.map { $0 * attackSign }.sorted(by: >)
        guard sorted.count >= 2 else { return false }
        return a > sorted[1]   // beyond the second-last opponent
    }

    /// Is `p` inside `defending`'s penalty area?
    public static func inPenaltyArea(_ p: Vec2, defending: TeamSide) -> Bool {
        let s: Float = defending == .home ? -1 : 1     // home defends the -X goal
        let line = s * PitchSpec.halfLength
        return abs(p.y) <= PitchSpec.penaltyAreaWidth / 2 && (p.x - line) * -s <= PitchSpec.penaltyAreaDepth && (p.x - line) * -s >= -0.01
    }

    public static func penaltySpot(defending: TeamSide) -> Vec2 {
        let s: Float = defending == .home ? -1 : 1
        return Vec2(s * (PitchSpec.halfLength - PitchSpec.penaltySpotDistance), 0)
    }

    /// Restart awarded when the ball wholly leaves the pitch. `exit` is the ball position, `lastTouch` the team that touched it last.
    public static func restartAfterBallOut(exit p: Vec3, lastTouch: TeamSide) -> (kind: RestartKind, team: TeamSide, spot: Vec2) {
        let r = PitchSpec.ballRadius
        if abs(p.z) > PitchSpec.halfWidth + r {
            let x = max(-PitchSpec.halfLength + 1, min(PitchSpec.halfLength - 1, p.x))
            return (.throwIn, lastTouch.opponent, Vec2(x, p.z > 0 ? PitchSpec.halfWidth : -PitchSpec.halfWidth))
        }
        let s: Float = p.x > 0 ? 1 : -1
        let defending: TeamSide = s > 0 ? .away : .home          // away defends the +X goal
        if lastTouch == defending {
            return (.corner, defending.opponent, Vec2(s * PitchSpec.halfLength, p.z >= 0 ? PitchSpec.halfWidth : -PitchSpec.halfWidth))
        }
        let gz = PitchSpec.goalAreaWidth / 2
        return (.goalKick, defending, Vec2(s * (PitchSpec.halfLength - PitchSpec.goalAreaDepth), max(-gz, min(gz, p.z))))
    }

    /// Distance opponents must keep at free kicks and corners.
    public static let wallDistance: Float = 9.15
}
