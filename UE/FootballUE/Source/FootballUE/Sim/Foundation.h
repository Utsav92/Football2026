#pragma once
// C++ port of FootballGame: RNG, Attributes, Laws, MatchClock, core enums.
#include "BallPhysics.h"
#include <cstdint>
#include <string>
#include <vector>
#include <algorithm>
namespace FB {

struct SplitMix64 {
    uint64_t state;
    explicit SplitMix64(uint64_t seed) : state(seed + 0x9E3779B97F4A7C15ULL) {}
    uint64_t Next() {
        state += 0x9E3779B97F4A7C15ULL;
        uint64_t z = state;
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
        return z ^ (z >> 31);
    }
    float Float() { return float(Next() >> 40) / float(1 << 24); }
    float Range(float a, float b) { return a + (b - a) * Float(); }
    int Int(int n) { return int(Next() % uint64_t(std::max(1, n))); }
    float Gaussian() {
        float u1 = std::max(Float(), 1e-6f), u2 = Float();
        return std::sqrt(-2 * std::log(u1)) * std::cos(2 * 3.14159265358979323846f * u2);
    }
};

enum class Role { GK, CB, LB, RB, DM, CM, AM, LM, RM, LW, RW, ST };
enum class Line { Goalkeeper, Defender, Midfielder, Forward };
inline Line LineOf(Role r) {
    switch (r) {
    case Role::GK: return Line::Goalkeeper;
    case Role::CB: case Role::LB: case Role::RB: return Line::Defender;
    case Role::DM: case Role::CM: case Role::AM: case Role::LM: case Role::RM: return Line::Midfielder;
    default: return Line::Forward;
    }
}
inline bool IsWide(Role r) { return r==Role::LB||r==Role::RB||r==Role::LM||r==Role::RM||r==Role::LW||r==Role::RW; }

enum class TeamSide { Home = 0, Away = 1 };
inline TeamSide Opponent(TeamSide s) { return s == TeamSide::Home ? TeamSide::Away : TeamSide::Home; }
inline float AttackSign(TeamSide s) { return s == TeamSide::Home ? 1.f : -1.f; }
enum class KickKind { Pass, Through, Lob, Shot, Header, Volley };
enum class Card { None, Yellow, Red };
enum class RestartKind { Kickoff, ThrowIn, GoalKick, Corner, FreeKick, IndirectFreeKick, Penalty };

struct PlayerAttributes {
    int sprintSpeed=60, acceleration=60, stamina=60, strength=60, agility=60, balance=60;
    int dribbling=60, ballControl=60, shortPassing=60, longPassing=60, shootingAccuracy=60, shotPower=60;
    int defensiveAwareness=60, tackling=60, goalkeeping=20, positioning=60, reactionTime=60;
    int Overall() const {
        int v[] = {sprintSpeed,acceleration,stamina,strength,agility,balance,dribbling,ballControl,shortPassing,longPassing,
                   shootingAccuracy,shotPower,defensiveAwareness,tackling,positioning,reactionTime};
        int s = 0; for (int x : v) s += x; return s / 16;
    }
    float SprintMS() const { return 7.4f + 0.026f * float(sprintSpeed); }
    float JogMS() const { return SprintMS() * 0.68f; }
    float AccelMS2() const { return 9 + 0.1f * float(acceleration); }
    float TurnRate() const { return 8 + 0.08f * float(agility); }
    float SprintDrain() const { return std::max(0.03f, 0.15f - 0.0009f * float(stamina)); }
    float StaminaRecovery() const { return 0.03f + 0.0004f * float(stamina); }
    float DecisionDelay() const { return std::max(0.08f, 0.5f - 0.0035f * float(reactionTime)); }
    float TrapLimit() const { return 7 + 0.09f * float(ballControl); }
    float DribbleFactor() const { return 0.86f + 0.0014f * float(dribbling); }
    float DribbleGain() const { return 9 + 0.07f * float(ballControl); }
    float MaxShotSpeed() const { return 22 + 0.14f * float(shotPower); }
    float MaxPassSpeed() const { return 18 + 0.1f * float(longPassing); }
    float PassError(bool lng) const { return 0.02f + 0.0009f * float(100 - (lng ? longPassing : shortPassing)); }
    float ShotError() const { return 0.015f + 0.0007f * float(100 - shootingAccuracy); }

    static PlayerAttributes Generated(Role role, int q, SplitMix64& rng) {
        PlayerAttributes a;
        auto g = [&](int bias) { return std::max(25, std::min(97, q + bias + int(std::round(rng.Gaussian() * 6)))); };
        Line line = LineOf(role);
        bool d = line==Line::Defender, m = line==Line::Midfielder, f = line==Line::Forward, k = line==Line::Goalkeeper;
        a.sprintSpeed = g(f?6:d?-2:0); a.acceleration = g(f?5:0); a.stamina = g(m?6:0);
        a.strength = g(d?6:f?0:-2); a.agility = g(f?4:0); a.balance = g(0);
        a.dribbling = g(f?6:m?3:-8); a.ballControl = g(f?4:m?4:-4);
        a.shortPassing = g(m?6:d?-2:0); a.longPassing = g(m?3:d?0:-4);
        a.shootingAccuracy = g(f?8:m?-2:-15); a.shotPower = g(f?6:m?0:-8);
        a.defensiveAwareness = g(d?8:m?0:-15); a.tackling = g(d?8:m?0:-15);
        a.positioning = g(0); a.reactionTime = g(0);
        a.goalkeeping = k ? g(8) : std::max(15, std::min(40, 25 + int(rng.Gaussian() * 5)));
        if (k) { a.sprintSpeed = g(-10); a.dribbling = g(-20); a.shootingAccuracy = g(-25); }
        return a;
    }
};

namespace Laws {
inline bool IsOffside(float receiverX, float ballX, const std::vector<float>& opponentXs, float attackSign) {
    float a = receiverX * attackSign;
    if (!(a > 0 && a > ballX * attackSign)) return false;
    std::vector<float> s; for (float x : opponentXs) s.push_back(x * attackSign);
    std::sort(s.begin(), s.end(), std::greater<float>());
    if (s.size() < 2) return false;
    return a > s[1];
}
inline bool InPenaltyArea(Vec2 p, TeamSide defending) {
    float s = defending == TeamSide::Home ? -1.f : 1.f, line = s * Pitch::HalfLength;
    return std::fabs(p.y) <= 40.32f / 2 && (p.x - line) * -s <= 16.5f && (p.x - line) * -s >= -0.01f;
}
inline Vec2 PenaltySpot(TeamSide defending) {
    float s = defending == TeamSide::Home ? -1.f : 1.f; return {s * (Pitch::HalfLength - 11.f), 0};
}
struct Restart { RestartKind kind; TeamSide team; Vec2 spot; };
inline Restart RestartAfterBallOut(Vec3 p, TeamSide lastTouch) {
    float r = Pitch::BallRadius;
    if (std::fabs(p.z) > Pitch::HalfWidth + r) {
        float x = std::max(-Pitch::HalfLength + 1, std::min(Pitch::HalfLength - 1, p.x));
        return {RestartKind::ThrowIn, Opponent(lastTouch), {x, p.z > 0 ? Pitch::HalfWidth : -Pitch::HalfWidth}};
    }
    float s = p.x > 0 ? 1.f : -1.f;
    TeamSide defending = s > 0 ? TeamSide::Away : TeamSide::Home;
    if (lastTouch == defending)
        return {RestartKind::Corner, Opponent(defending), {s * Pitch::HalfLength, p.z >= 0 ? Pitch::HalfWidth : -Pitch::HalfWidth}};
    float gz = 18.32f / 2;
    return {RestartKind::GoalKick, defending, {s * (Pitch::HalfLength - 5.5f), std::max(-gz, std::min(gz, p.z))}};
}
constexpr float WallDistance = 9.15f;
}

struct MatchClock {
    static constexpr float HalfSeconds = 45 * 60;
    float matchLengthSeconds = 360, gameSeconds = 0, addedSeconds = 0; int half = 1;
    float TimeScale() const { return 5400 / matchLengthSeconds; }
    float NominalEnd() const { return half <= 2 ? HalfSeconds * float(half) : (half == 3 ? 6300.f : 7200.f); }
    bool InAddedTime() const { return gameSeconds >= NominalEnd(); }
    bool IsHalfOver() const { return gameSeconds >= NominalEnd() + addedSeconds; }
    int Minutes() const { return int(gameSeconds) / 60; }
    void Tick(float dt) { gameSeconds += dt * TimeScale(); }
    void StartSecondHalf() { half = 2; gameSeconds = HalfSeconds; addedSeconds = 0; }
    void StartNextPeriod() { half += 1; gameSeconds = half == 3 ? 5400.f : 6300.f; addedSeconds = 0; }
};
struct FixedStepper {
    float step = 1.f/120.f, maxFrameTime = 0.25f, accumulator = 0;
    int Advance(float frameTime) {
        accumulator += std::min(std::max(frameTime, 0.f), maxFrameTime);
        int n = int(accumulator / step + 1e-4f);
        accumulator = std::max(0.f, accumulator - float(n) * step); return n;
    }
};
}
