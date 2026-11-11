#pragma once
// C++ port of FootballGame/MatchSimulation + Kicking + AI + Shootout. Mirrors the Swift engine's rule order and RNG draw order.
#include "Formation.h"
#include <map>
#include <optional>
#include <array>
#include <functional>
namespace FB {

inline float Distance(Vec3 a, Vec3 b) { return Length(a-b); }
inline Vec2 Rot(Vec2 v, float a) { float c=std::cos(a), s=std::sin(a); return {c*v.x-s*v.y, s*v.x+c*v.y}; }
inline Vec2 Unit(Vec2 v) { float l=Length(v); return l>1e-5f ? v/l : Vec2(1,0); }
inline float WrapPi(float d) { const float pi=3.14159265358979323846f; while (d>pi) d-=2*pi; while (d<-pi) d+=2*pi; return d; }
constexpr float FB_PI = 3.14159265358979323846f;

struct PlayerInput {
    Vec2 move; bool sprint=false, passHeld=false, throughHeld=false, lobHeld=false, shootHeld=false, tackleHeld=false, slideHeld=false,
         switchPressed=false, finesseHeld=false, jockeyHeld=false; Vec2 skill;
};
struct KickCharge { KickKind kind; float time, level; };
struct KickTuning { float chargeTime=0.9f, minPower=0.25f, range=1.7f, lockout=0.3f, bufferWindow=0.18f; };
struct Score { int home=0, away=0; int& operator[](TeamSide s){return s==TeamSide::Home?home:away;} };
struct ShootoutState { int taken[2]={0,0}, scored[2]={0,0}; TeamSide next=TeamSide::Home; int winner=-1; bool inFlight=false; float timer=0; };
struct TeamStats { float possessionSeconds=0; int shots=0,shotsOnTarget=0,passes=0,passesCompleted=0,tackles=0,tacklesWon=0,fouls=0,yellowCards=0,redCards=0,corners=0,offsides=0,saves=0; };
enum class AIState : uint8_t { Idle, Positioning, Supporting, Pressing, Marking, Intercepting, Dribbling, Passing, Shooting, Tackling, Recovering, Goalkeeping, Controlled, SetPiece };

struct Footballer {
    int id; TeamSide team; int slot; Role role; std::string name; int number; PlayerAttributes attributes; Appearance appearance;
    Vec2 pos, vel; float heading=0, stamina=1; bool isSprinting=false, onPitch=true; int yellowCards=0; bool sentOff=false; AIState state=AIState::Idle;
    Vec2 target; float kickAnim=0, tackleAnim=0, celebrate=0, diveTime=0; Vec2 diveDir; float fallenTime=0; bool holdingBall=false; float headAnim=0, skillAnim=0;
    Vec2 desiredDir; bool wantSprint=false, sprintLocked=false; float kickLock=0, tackleCooldown=0, stun=0, slideTime=0; Vec2 slideDir;
    int thinkOffset=0; float holdTimer=0, reactTimer=0, saveCooldown=0, possessionTime=0; int markTarget=-1; bool jockey=false; Vec2 skillOffset; float evade=0, skillCooldown=0;
    Vec2 Facing() const { return {std::cos(heading), std::sin(heading)}; }
    float Speed() const { return Length(vel); }
    bool IsSliding() const { return slideTime>0; } bool IsDiving() const { return diveTime>0; } bool isDown() const { return fallenTime>0; }
};
struct RestartInfo { RestartKind kind=RestartKind::Kickoff; TeamSide team=TeamSide::Home; Vec2 spot; int taker=0; float elapsed=0, minWait=0; };
struct Phase { enum Kind { Playing, GoalCelebration, Restart, HalfTime, Shootout, FullTime } kind=Playing; float remaining=0; TeamSide scoredBy=TeamSide::Home; RestartInfo info; };
struct GameEvent {
    enum Kind { Kick, Possession, PassCompleted, Tackle, Foul, Offside, Save, Goal, Ball, Restart, HalfTime, FullTime, ExtraTimeStart, ShootoutStart, Advantage, SkillMove, ShootoutKick, Switched, Substitution } kind;
    int a=0, b=0; float f=0;
};
struct MatchConfig {
    TeamSetup home, away; float matchLengthSeconds=360; Difficulty difficulty{3}; int difficultyOverride[2]={-1,-1}; bool humanTeams[2]={true,false};
    uint64_t seed=1; bool wetPitch=false, knockout=false;
};
struct TeamContext { bool inPossession=false; float ballDepth=0.5f, ballLat=0; int chaser=-1, second=-1; float offsideLine=0; int carrier=-1; };
struct AdvantageState { TeamSide victim; Vec2 spot; float remaining; };
struct PendingKick { KickKind kind; float power; PlayerInput input; float remaining; };
struct TeamRuntime {
    std::optional<PendingKick> pendingKick; TeamSetup setup; bool human; int controlled; float skill; TeamContext ctx; PlayerInput prevInput;
    std::optional<KickCharge> charge; int subsUsed=0; float sinceSwitch=10;
};
struct PassOption { int target; KickKind kind; float utility; };
struct Crossing { float t, z, y; };

class MatchSimulation {
public:
    static constexpr float DT = 1.f/120.f;
    MatchConfig config; std::vector<Footballer> players; BallState ball; int ballOwner=-1, lastTouch=-1, intendedReceiver=-1;
    Score score; MatchClock clock; Phase phase; TeamStats stats[2]; KickTuning kickTuning;
    std::vector<TeamRuntime> teams; SplitMix64 rng; BallPhysics physics; std::vector<GameEvent> events; int tick=0;
    std::map<int,Vec2> pendingOffside; TeamSide pendingTeam=TeamSide::Home; float overtimeReal=0, stoppageCredit=0;
    std::optional<AdvantageState> advantage; ShootoutState shootout; bool shootoutActive=false; int forcedTaker=-1; TeamSide lastKickTeam=TeamSide::Home;

    explicit MatchSimulation(const MatchConfig& cfg) : config(cfg), rng(cfg.seed) {
        clock.matchLengthSeconds = cfg.matchLengthSeconds;
        for (int si=0; si<2; ++si) {
            TeamSide side = (TeamSide)si; const TeamSetup& setup = si==0 ? cfg.home : cfg.away;
            bool human = cfg.humanTeams[si];
            float skill = human ? 0.85f : (cfg.difficultyOverride[si] >= 0 ? Difficulty{cfg.difficultyOverride[si]} : cfg.difficulty).Skill();
            auto slots = Slots(setup.formation); int fwd = 10; for (int k=(int)slots.size()-1;k>=0;--k) if (slots[k].role==Role::ST){fwd=k;break;}
            TeamRuntime tr; tr.setup=setup; tr.human=human; tr.controlled = human ? si*11+fwd : -1; tr.skill=skill; teams.push_back(tr);
            for (int s=0;s<11;++s) {
                const PlayerProfile& pr = setup.players[s]; Footballer f; f.id=si*11+s; f.team=side; f.slot=s; f.role=slots[s].role;
                f.name=pr.name; f.number=pr.number; f.attributes=pr.attributes; f.appearance=pr.appearance; f.thinkOffset=s; players.push_back(f);
            }
        }
        if (cfg.wetPitch) { physics.Config.rollingDecel *= 0.82f; physics.Config.groundRestitution += 0.03f; }
        BeginMatch();
    }
    std::vector<GameEvent> DrainEvents() { auto e=events; events.clear(); return e; }
    void Emit(GameEvent::Kind k,int a=0,int b=0,float f=0){ events.push_back({k,a,b,f}); }

    void BeginMatch() { for (auto& p : players) ResetPlayerState(p); SetupRestart(RestartKind::Kickoff, TeamSide::Home, Vec2(0,0)); }
    void ResetPlayerState(Footballer& p) { p.vel=Vec2(); p.kickLock=0; p.stun=0; p.slideTime=0; p.diveTime=0; p.fallenTime=0; p.holdingBall=false; p.tackleCooldown=0; }
    void Place(int i, Vec2 p) { players[i].pos=p; players[i].vel=Vec2(); }
    void PlaceBall(Vec3 p, Vec3 v=Vec3()) { ball=BallState(); ball.position=p; ball.velocity=v; ballOwner=-1; }

    Vec2 ClampToPitch(Vec2 p, float margin=1) const {
        return {std::max(-Pitch::HalfLength+margin, std::min(Pitch::HalfLength-margin, p.x)), std::max(-Pitch::HalfWidth+margin, std::min(Pitch::HalfWidth-margin, p.y))};
    }
    static Vec2 BallXZ(const BallState& b) { return {b.position.x, b.position.z}; }
    Vec2 BXZ() const { return BallXZ(ball); }
    static Vec2 HVel(const BallState& b) { return {b.velocity.x, b.velocity.z}; }
    static float BallSpeed(const BallState& b) { return Length(b.velocity); }
    int TeamOf(int i) const { return (int)players[i].team; }

    Vec2 AnchorWorld(int slot, TeamSide side, float ballDepth, bool inPossession, float ballLat) const {
        const TeamRuntime& team = teams[(int)side]; auto slots = Slots(team.setup.formation); const FormationSlot& s = slots[slot];
        float sign = AttackSign(side); Line line = LineOf(s.role);
        if (line == Line::Goalkeeper) return Vec2(sign * (-Pitch::HalfLength + 2.5f), 0);
        const TeamTactics& tac = team.setup.tactics;
        float bx = (ballDepth - 0.5f) * Pitch::Length;
        float cx = (inPossession ? TacticalPriors::CentroidInterceptInPossession : TacticalPriors::CentroidInterceptOutOfPossession) + TacticalPriors::CentroidSlope * bx;
        cx += (tac.defensiveLine - 0.5f) * 8;
        float keepL = inPossession ? TacticalPriors::LengthKeepInPossession : TacticalPriors::LengthKeepOutOfPossession;
        if (!inPossession) keepL -= 0.06f * (tac.pressing - 0.5f);
        float off = (s.depth - OutfieldMeanDepth(team.setup.formation)) * Pitch::Length * keepL;
        float x = cx + off; x = std::max(-Pitch::HalfLength + 6, std::min(Pitch::HalfLength - 3.5f, x));
        float keepW = (inPossession ? TacticalPriors::WidthKeepInPossession : TacticalPriors::WidthKeepOutOfPossession) * (0.85f + 0.3f * tac.width);
        float lat = s.lateral * keepW; lat += ballLat * (1 - std::fabs(s.lateral) * 0.6f) * 0.30f;
        return Vec2(sign * x, sign * lat * Pitch::HalfWidth * 0.92f);
    }

    // ---- restarts
    template<class F> int BestOf(const std::vector<int>& ids, F scoreFn) const { int best=ids[0]; float bs=scoreFn(players[ids[0]]); for (size_t k=1;k<ids.size();++k){ float s=scoreFn(players[ids[k]]); if (bs<s){bs=s;best=ids[k];} } return best; }
    int ChooseTaker(RestartKind kind, TeamSide team, Vec2 spot) {
        std::vector<int> mine; for (int i=0;i<(int)players.size();++i) if (players[i].team==team && players[i].onPitch) mine.push_back(i);
        auto filt=[&](auto pred){ std::vector<int> r; for (int i : mine) if (pred(players[i])) r.push_back(i); return r; };
        switch (kind) {
        case RestartKind::GoalKick: for (int i : mine) if (players[i].role==Role::GK) return i; return mine[0];
        case RestartKind::Penalty: { if (forcedTaker>=0) { int f=forcedTaker; forcedTaker=-1; return f; }
            return BestOf(filt([](const Footballer& p){return p.role!=Role::GK;}), [](const Footballer& p){return float(p.attributes.shootingAccuracy+p.attributes.shotPower);}); }
        case RestartKind::Kickoff: { auto fw=filt([](const Footballer& p){return LineOf(p.role)==Line::Forward||p.role==Role::AM;});
            return BestOf(fw.empty()?mine:fw, [&](const Footballer& p){return -Distance(p.pos,spot);}); }
        case RestartKind::Corner: { auto m=filt([](const Footballer& p){return LineOf(p.role)==Line::Midfielder||LineOf(p.role)==Line::Forward;});
            return BestOf(m.empty()?mine:m, [&](const Footballer& p){return float(p.attributes.longPassing)-Distance(p.pos,spot)*0.8f;}); }
        case RestartKind::ThrowIn: return BestOf(filt([](const Footballer& p){return p.role!=Role::GK;}), [&](const Footballer& p){return -Distance(p.pos,spot);});
        default: { auto o=filt([](const Footballer& p){return p.role!=Role::GK;});
            std::stable_sort(o.begin(),o.end(),[&](int a,int b){return Distance(players[a].pos,spot)<Distance(players[b].pos,spot);}); if (o.size()>4) o.resize(4);
            return BestOf(o,[](const Footballer& p){return float(p.attributes.shootingAccuracy+p.attributes.longPassing);}); }
        }
    }
    void SetupRestart(RestartKind kind, TeamSide team, Vec2 rawSpot) {
        Vec2 spot=rawSpot; spot.x=std::max(-Pitch::HalfLength,std::min(Pitch::HalfLength,spot.x)); spot.y=std::max(-Pitch::HalfWidth,std::min(Pitch::HalfWidth,spot.y));
        ballOwner=-1; intendedReceiver=-1; pendingOffside.clear(); advantage.reset();
        for (auto& p : players) { p.holdingBall=false; p.diveTime=0; p.slideTime=0; }
        if (kind==RestartKind::Kickoff) PlaceKickoffFormation(team);
        int taker=ChooseTaker(kind,team,spot); float sign=AttackSign(team); Vec2 tp=spot; float heading = sign>0?0.f:FB_PI;
        switch (kind) {
        case RestartKind::ThrowIn: tp=Vec2(spot.x, spot.y+(spot.y>0?-0.2f:0.2f)); heading = spot.y>0 ? -FB_PI/2 : FB_PI/2; break;
        case RestartKind::Corner: { tp=Vec2(spot.x-(spot.x>0?0.6f:-0.6f), spot.y-(spot.y>0?0.6f:-0.6f)); Vec2 tgt=Vec2(spot.x*0.88f,0)-tp; heading=std::atan2(tgt.y,tgt.x); break; }
        default: tp=spot-Vec2(sign*0.8f,0);
        }
        players[taker].pos=tp; players[taker].vel=Vec2(); players[taker].heading=heading;
        ball=BallState(); ball.position=Vec3(spot.x,Pitch::BallRadius,spot.y);
        float wait = kind==RestartKind::Kickoff?1.5f:(kind==RestartKind::Penalty?2.0f:1.2f);
        phase=Phase(); phase.kind=Phase::Restart; phase.info={kind,team,spot,taker,0,wait};
        if (teams[(int)team].human) teams[(int)team].controlled=taker;
        if (kind==RestartKind::Corner) stats[(int)team].corners += 1;
        Emit(GameEvent::Restart,(int)kind,(int)team);
    }
    void PlaceKickoffFormation(TeamSide kickoffTeam) {
        for (auto& p : players) { if (!p.onPitch) continue;
            Vec2 a=AnchorWorld(p.slot,p.team,0.5f,false,0); float sign=AttackSign(p.team);
            if (a.x*sign > -0.5f) a.x=-0.5f*sign;
            if (p.team!=kickoffTeam && Length(a) < Pitch::CentreCircleRadius()+0.5f) {
                Vec2 q=a+Vec2(-sign*0.01f,0); a=(q/Length(q))*(Pitch::CentreCircleRadius()+0.6f); if (a.x*sign > -0.5f) a.x=-0.6f*sign; }
            p.pos=a; p.vel=Vec2(); p.heading = sign>0?0.f:FB_PI; }
    }

    // ---- stepping
    void Step(const std::array<PlayerInput,2>& inputs) {
        tick += 1; float dt=DT;
        for (int t=0;t<2;++t) teams[t].sinceSwitch += dt;
        switch (phase.kind) {
        case Phase::Playing: if (shootoutActive) ShootoutPlayStep(dt); else PlayStep(inputs,dt); break;
        case Phase::Shootout: ShootoutPause(dt); break;
        case Phase::Restart: RestartStep(phase.info,inputs,dt); break;
        case Phase::GoalCelebration: { IdleStep(dt); float r=phase.remaining-dt; TeamSide by=phase.scoredBy;
            if (r<=0) { if (clock.IsHalfOver()) EndHalfOrMatch(); else SetupRestart(RestartKind::Kickoff,Opponent(by),Vec2(0,0)); }
            else phase.remaining=r; break; }
        case Phase::HalfTime: { float r=phase.remaining-dt; if (r<=0) StartNextPeriod(); else phase.remaining=r; break; }
        case Phase::FullTime: IdleStep(dt); break;
        }
    }
    void IdleStep(float dt) {
        for (int i=0;i<(int)players.size();++i) { players[i].desiredDir=Vec2(); players[i].wantSprint=false; Integrate(i,dt); if (players[i].celebrate>0) players[i].celebrate-=dt; }
        UpdateBallControl(dt); StepBall(dt);
    }
    void PlayStep(const std::array<PlayerInput,2>& inputs, float dt) {
        clock.Tick(dt);
        if (clock.addedSeconds==0 && clock.gameSeconds >= clock.NominalEnd()-8)
            clock.addedSeconds = (clock.half>=3) ? 30.f : std::max(60.f, std::min(300.f, std::round(60*(0.5f+stoppageCredit))));
        if (clock.IsHalfOver()) { overtimeReal += dt; if (overtimeReal>8 || ballOwner<0 || std::fabs(ball.position.x)<28) { EndHalfOrMatch(); return; } }
        if (tick%6==0) UpdateContexts();
        for (int s=0;s<2;++s) if (teams[s].human) HumanControl((TeamSide)s, inputs[s], dt);
        RunAI(dt);
        for (int i=0;i<(int)players.size();++i) Integrate(i,dt);
        SeparatePlayers(); GoalkeepersStep(dt); UpdateBallControl(dt); AutoAerial(); StepBall(dt); UpdateAdvantage(dt);
        if (phase.kind==Phase::Playing) CheckBallState();
        if (ballOwner>=0) stats[TeamOf(ballOwner)].possessionSeconds += dt*clock.TimeScale()/15;
    }
    void EndHalfOrMatch() {
        overtimeReal=0; stoppageCredit=0; advantage.reset(); bool level = score.home==score.away;
        auto setPhase=[&](Phase::Kind k,float rem){ phase=Phase(); phase.kind=k; phase.remaining=rem; };
        switch (clock.half) {
        case 1: setPhase(Phase::HalfTime,10); Emit(GameEvent::HalfTime); break;
        case 2: if (config.knockout && level) { setPhase(Phase::HalfTime,6); Emit(GameEvent::HalfTime);} else { setPhase(Phase::FullTime,0); Emit(GameEvent::FullTime);} break;
        case 3: setPhase(Phase::HalfTime,3); Emit(GameEvent::HalfTime); break;
        default: if (config.knockout && level) StartShootout(); else { setPhase(Phase::FullTime,0); Emit(GameEvent::FullTime);} }
        ballOwner=-1;
    }
    void StartNextPeriod() {
        if (clock.half==1) { clock.StartSecondHalf(); SetupRestart(RestartKind::Kickoff,TeamSide::Away,Vec2(0,0)); return; }
        clock.StartNextPeriod(); if (clock.half==3) Emit(GameEvent::ExtraTimeStart);
        SetupRestart(RestartKind::Kickoff, clock.half==3?TeamSide::Home:TeamSide::Away, Vec2(0,0));
    }
    float TeamSpeedScale(TeamSide s) const { return 0.90f + 0.10f*teams[(int)s].skill; }

    void Integrate(int i, float dt) {
        if (!players[i].onPitch) return;
        Footballer p=players[i];
        p.kickLock=std::max(0.f,p.kickLock-dt); p.tackleCooldown=std::max(0.f,p.tackleCooldown-dt);
        p.stun=std::max(0.f,p.stun-dt); p.kickAnim=std::max(0.f,p.kickAnim-dt); p.tackleAnim=std::max(0.f,p.tackleAnim-dt);
        p.fallenTime=std::max(0.f,p.fallenTime-dt); p.saveCooldown=std::max(0.f,p.saveCooldown-dt);
        p.headAnim=std::max(0.f,p.headAnim-dt); p.skillAnim=std::max(0.f,p.skillAnim-dt); p.evade=std::max(0.f,p.evade-dt); p.skillCooldown=std::max(0.f,p.skillCooldown-dt);
        if (p.skillAnim<=0) p.skillOffset=Vec2();
        const PlayerAttributes a=p.attributes;
        if (p.diveTime>0) {
            p.diveTime-=dt; p.pos+=p.vel*dt; p.vel*=std::max(0.f,1-1.8f*dt); if (p.diveTime<=0) p.fallenTime=0.5f;
        } else if (p.slideTime>0) {
            p.slideTime-=dt; p.vel=p.slideDir*(9*std::max(0.f,p.slideTime/0.55f)+1); p.pos+=p.vel*dt;
            if (p.slideTime<=0) { p.stun=0.6f; p.fallenTime=0.6f; p.vel*=0.3f; }
        } else {
            float len=Length(p.desiredDir); bool hasInput = len>0.05f && p.stun<=0 && p.fallenTime<=0;
            if (p.stamina<=0) p.sprintLocked=true; if (p.stamina>0.25f) p.sprintLocked=false;
            bool sprinting = p.wantSprint && hasInput && !p.sprintLocked; p.isSprinting=sprinting;
            float maxS = sprinting ? a.SprintMS() : a.JogMS();
            if (ballOwner==i) maxS*=a.DribbleFactor();
            if (p.role==Role::GK) maxS*=0.85f;
            if (p.jockey) maxS*=(ballOwner==i?0.75f:0.62f);
            maxS*=TeamSpeedScale(p.team);
            Vec2 dir = hasInput ? p.desiredDir/std::max(1.f,len) : Vec2();
            Vec2 desired = dir*maxS*std::min(1.f,len); Vec2 dv=desired-p.vel;
            bool accelerating = Length(desired) >= Length(p.vel)-0.01f;
            float maxDV=(accelerating?a.AccelMS2():22.f)*dt*(p.stun>0?0.3f:1.f); float dl=Length(dv);
            p.vel += dl>maxDV ? dv/dl*maxDV : dv;
            if (p.jockey && ballOwner!=i) { Vec2 tb=BXZ()-p.pos; float d=WrapPi(std::atan2(tb.y,tb.x)-p.heading); float m=a.TurnRate()*dt; p.heading+=std::max(-m,std::min(m,d)); }
            else if (hasInput || Length(p.vel) > 2.0f) {
                // Face the direction of travel once moving at speed (velocity lags the desired direction, so facing the *desired* direction made players run
                // one way while facing another, and put the dribbled ball beside/behind them). Below ~2 m/s the player turns toward their input as before.
                Vec2 faceDir = Length(p.vel) > 2.0f ? p.vel / Length(p.vel) : dir;
                float d=WrapPi(std::atan2(faceDir.y,faceDir.x)-p.heading); float m=a.TurnRate()*dt; p.heading+=std::max(-m,std::min(m,d)); }
            p.pos+=p.vel*dt;
            if (sprinting && Length(p.vel)>1) p.stamina=std::max(0.f,p.stamina-a.SprintDrain()*dt); else p.stamina=std::min(1.f,p.stamina+a.StaminaRecovery()*dt);
        }
        float lx=Pitch::HalfLength+4, lz=Pitch::HalfWidth+4;
        p.pos.x=std::clamp(p.pos.x,-lx,lx); p.pos.y=std::clamp(p.pos.y,-lz,lz);
        players[i]=p;
    }
    void SeparatePlayers() {
        int n=(int)players.size();
        for (int i=0;i<n;++i) { if (!players[i].onPitch) continue;
            for (int j=i+1;j<n;++j) { if (!players[j].onPitch) continue;
                Vec2 d=players[j].pos-players[i].pos; float l=Length(d);
                if (l<0.7f && l>1e-4f) { Vec2 push=d/l*((0.7f-l)*0.5f);
                    bool si=players[i].IsSliding()||players[i].IsDiving(), sj=players[j].IsSliding()||players[j].IsDiving();
                    if (!si && !sj) { players[i].pos-=push; players[j].pos+=push; } } } }
    }

    void UpdateBallControl(float dt) {
        float r=Pitch::BallRadius; Vec2 bxz=BXZ();
        if (ballOwner>=0) { int o=ballOwner; Footballer& p=players[o];
            if (p.holdingBall) { Vec2 f=p.Facing(); ball.position=Vec3(p.pos.x+f.x*0.3f,1.0f,p.pos.y+f.y*0.3f); ball.velocity=Vec3(); return; }
            if (!p.onPitch || p.kickLock>0 || p.stun>0 || p.fallenTime>0 || ball.position.y>0.75f || Distance(bxz,p.pos)>1.9f) ballOwner=-1; }
        if (ballOwner<0) {
            int best=-1; float bestD=INFINITY;
            for (int i=0;i<(int)players.size();++i) { const Footballer& p=players[i];
                if (!(p.onPitch && p.kickLock<=0 && p.stun<=0 && p.fallenTime<=0 && p.diveTime<=0 && ball.position.y<0.55f)) continue;
                if (phase.kind==Phase::Restart) continue;
                float d=Distance(bxz,p.pos); float limit=0.9f+0.002f*float(p.attributes.ballControl)+(p.IsSliding()?0.5f:0.f);
                float rel=Length(HVel(ball)-p.vel);
                if (d<limit && rel<p.attributes.TrapLimit() && d<bestD) { best=i; bestD=d; } }
            if (best>=0) TakeOwnership(best);
        }
        if (ballOwner>=0) { int o=ballOwner; const Footballer& p=players[o];
            float ahead=0.8f+0.04f*p.Speed(); Vec2 f=p.Facing(); Vec2 right(-f.y,f.x);
            Vec2 target=p.pos+f*ahead+right*0.3f+p.skillOffset*std::min(1.f,p.skillAnim/0.25f);
            Vec2 desired=p.vel+(target-bxz)*9; Vec2 rel=desired-p.vel; float rl=Length(rel);
            if (rl>7) desired=p.vel+rel/rl*7;
            float k=std::min(1.f,p.attributes.DribbleGain()*dt); Vec2 cur=HVel(ball); Vec2 nv=cur+(desired-cur)*k;
            ball.velocity.x=nv.x; ball.velocity.z=nv.y; players[o].possessionTime+=dt; }
        for (int i=0;i<(int)players.size();++i) { if (i==ballOwner || !players[i].onPitch) continue; const Footballer& p=players[i];
            if (p.role==Role::GK && p.diveTime>0) continue;
            Vec2 toBall=bxz-p.pos; float dist=Length(toBall); float minDist=0.42f+r+(p.IsSliding()?0.5f:0.f);
            if (dist<minDist && ball.position.y<1.8f && dist>1e-4f) { Vec2 n=toBall/dist;
                ball.position.x+=n.x*(minDist-dist); ball.position.z+=n.y*(minDist-dist);
                float rel=Dot(HVel(ball)-p.vel,n);
                if (rel<0) { float j=-(1+0.35f)*rel; ball.velocity.x+=n.x*j; ball.velocity.z+=n.y*j; if (rel<-1.5f) NoteTouch(i); } } }
    }
    void NoteTouch(int i) { if (lastTouch>=0 && players[lastTouch].team!=players[i].team) { intendedReceiver=-1; pendingOffside.clear(); } lastTouch=i; }
    void TakeOwnership(int i) {
        const Footballer& p=players[i];
        if (pendingTeam==p.team) { auto it=pendingOffside.find(i); if (it!=pendingOffside.end()) { Vec2 pos=it->second; pendingOffside.clear(); CallOffside(i,pos); return; } }
        int prev=lastTouch; bool prevIsOther = prev<0 || players[prev].team!=p.team;
        if (prev>=0 && players[prev].team==p.team) {
            if (intendedReceiver>=0 && (prev!=i || intendedReceiver==i) && lastKickTeam==p.team) {
                stats[(int)p.team].passesCompleted += 1; Emit(GameEvent::PassCompleted,prev,i);
                if (teams[(int)p.team].human && teams[(int)p.team].controlled==prev && players[i].role!=Role::GK) SwitchControl(p.team,i); } }
        if (prevIsOther) Emit(GameEvent::Possession,(int)p.team);
        ballOwner=i; lastTouch=i; intendedReceiver=-1; pendingOffside.clear(); players[i].possessionTime=0;
    }
    void SwitchControl(TeamSide side, int i) {
        if (!teams[(int)side].human || teams[(int)side].controlled==i) return;
        teams[(int)side].controlled=i; teams[(int)side].sinceSwitch=0; Emit(GameEvent::Switched,(int)side,i);
    }
    void StepBall(float dt) { std::vector<BallEvent> ev; physics.Step(ball,dt,&ev); for (auto& e : ev) Emit(GameEvent::Ball,(int)e.kind,0,e.impactSpeed); }
    void CheckBallState() {
        int side=GoalSide(ball);
        if (side!=0) { TeamSide scorer = side>0 ? TeamSide::Home : TeamSide::Away; score[scorer]+=1; advantage.reset(); stoppageCredit+=0.5f;
            phase=Phase(); phase.kind=Phase::GoalCelebration; phase.remaining=4; phase.scoredBy=scorer;
            if (lastTouch>=0 && players[lastTouch].team==scorer) players[lastTouch].celebrate=3.5f;
            Emit(GameEvent::Goal,(int)scorer,lastTouch); ballOwner=-1; }
        else if (IsOutOfPlay(ball)) { TeamSide team = lastTouch>=0 ? players[lastTouch].team : TeamSide::Home;
            auto r=Laws::RestartAfterBallOut(ball.position,team); SetupRestart(r.kind,r.team,r.spot); }
    }
    void CallOffside(int i, Vec2 pos) { stats[TeamOf(i)].offsides+=1; Emit(GameEvent::Offside,i); SetupRestart(RestartKind::IndirectFreeKick,Opponent(players[i].team),pos); }
    void CallFoul(int i, int o, float severity, bool fromBehind) {
        TeamSide fouler=players[i].team; Vec2 spot=players[o].pos; stats[(int)fouler].fouls+=1; stoppageCredit+=0.25f;
        Card card=Card::None;
        float yellowP=0.05f+0.35f*severity*(fromBehind?1.3f:1.f), redP=0.005f+0.05f*severity*(fromBehind?1.5f:1.f); float roll=rng.Float();
        if (roll<redP) card=Card::Red; else if (roll<yellowP) card=Card::Yellow;
        if (card==Card::Yellow) { players[i].yellowCards+=1; stats[(int)fouler].yellowCards+=1; if (players[i].yellowCards>=2) card=Card::Red; }
        if (card==Card::Red) { SendOff(i); stats[(int)fouler].redCards+=1; }
        stoppageCredit += card==Card::None ? 0.f : 0.5f;
        bool inBox=Laws::InPenaltyArea(spot,fouler); TeamSide victim=Opponent(fouler);
        if (!inBox && card!=Card::Red && !advantage && ballOwner>=0 && players[ballOwner].team==victim) {
            advantage=AdvantageState{victim,spot,2.2f}; Emit(GameEvent::Foul,i,o,float(card)); Emit(GameEvent::Advantage,(int)victim); return; }
        players[o].fallenTime=1.0f; Emit(GameEvent::Foul,i,o,float(card)+(inBox?10.f:0.f));
        if (inBox) SetupRestart(RestartKind::Penalty,Opponent(fouler),Laws::PenaltySpot(fouler)); else SetupRestart(RestartKind::FreeKick,Opponent(fouler),spot);
    }
    void ReplaceKeeper(TeamSide side) {
        std::vector<int> cands; for (int i=0;i<(int)players.size();++i) if (players[i].team==side && players[i].onPitch && players[i].role!=Role::GK) cands.push_back(i);
        auto minBy=[&](const std::vector<int>& v){ int b=-1; for (int i : v) if (b<0 || players[i].attributes.Overall()<players[b].attributes.Overall()) b=i; return b; };
        std::vector<int> fw; for (int i : cands) if (LineOf(players[i].role)==Line::Forward) fw.push_back(i);
        int off = !fw.empty()? minBy(fw) : minBy(cands); if (off<0) return;
        const PlayerProfile* bench=nullptr; const auto& sp=teams[(int)side].setup.players;
        for (size_t k=11;k<sp.size();++k) if (sp[k].role==Role::GK){bench=&sp[k];break;}
        int oldNumber=players[off].number;
        if (bench) { players[off].name=bench->name; players[off].number=bench->number; players[off].attributes=bench->attributes; players[off].appearance=bench->appearance; }
        else players[off].attributes.goalkeeping=std::max(players[off].attributes.goalkeeping,40);
        players[off].role=Role::GK; players[off].stamina=1; Emit(GameEvent::Substitution,(int)side,oldNumber,float(players[off].number));
    }
    void SendOff(int i) {
        bool keeper=players[i].role==Role::GK; TeamSide team=players[i].team;
        players[i].onPitch=false; players[i].sentOff=true; players[i].pos=Vec2(0,Pitch::HalfWidth+8); players[i].vel=Vec2();
        if (teams[(int)team].controlled==i) teams[(int)team].controlled=NearestOutfield(team,BXZ());
        if (keeper) ReplaceKeeper(team);
    }
    int NearestOutfield(TeamSide side, Vec2 p, int excluding=-1) const {
        int b=-1; float bd=0; for (int i=0;i<(int)players.size();++i) { if (!(players[i].team==side && players[i].onPitch && players[i].role!=Role::GK && i!=excluding)) continue;
            float d=Distance(players[i].pos,p); if (b<0 || d<bd){b=i;bd=d;} } return b;
    }
    bool Substitute(TeamSide side, int slot, int bench) {
        int t=(int)side; if (!(teams[t].subsUsed<5 && slot>0 && slot<11 && 11+bench<(int)teams[t].setup.players.size())) return false;
        const PlayerProfile& prof=teams[t].setup.players[11+bench]; int i=t*11+slot; int old=players[i].number;
        players[i].name=prof.name; players[i].number=prof.number; players[i].attributes=prof.attributes; players[i].appearance=prof.appearance; players[i].stamina=1;
        teams[t].subsUsed+=1; Emit(GameEvent::Substitution,t,old,float(prof.number)); return true;
    }

    // ---- kicking
    float GroundPassSpeed(float d, float arrive) const {
        const auto& cfg=physics.Config; float v=arrive, x=0, h=0.01f;
        while (x<d && v<45) { v+=(cfg.rollingDecel+cfg.airDragK*v*v)*h; x+=v*h; } return v;
    }
    std::optional<Crossing> PredictGoalCrossing(float sign, float maxT=2.5f) const {
        BallState b=ball; float dt=1.f/60, lineX=sign*Pitch::HalfLength, t=0;
        while (t<maxT) { physics.Step(b,dt); t+=dt; if ((b.position.x-lineX)*sign>=0) return Crossing{t,b.position.z,b.position.y};
            if (BallSpeed(b)<0.3f && b.position.y<0.2f) break; }
        return std::nullopt;
    }
    void KickBall(int i, Vec3 v, Vec3 spin, KickKind kind, float power, int target, bool countsAsShot=false) {
        Footballer& p=players[i]; bool hadRestart=false; RestartKind rk=RestartKind::Kickoff;
        if (phase.kind==Phase::Restart) { hadRestart=true; rk=phase.info.kind; phase=Phase(); phase.kind=Phase::Playing; }
        ball.velocity=v; ball.curveSpin=spin;
        if (hadRestart && rk==RestartKind::ThrowIn) ball.position.y=2.0f;
        p.kickLock=kickTuning.lockout; p.kickAnim=0.3f; p.holdingBall=false;
        ballOwner=-1; lastTouch=i; intendedReceiver=target; lastKickTeam=p.team; pendingOffside.clear(); pendingTeam=p.team;
        bool freeRestart = hadRestart && (rk==RestartKind::ThrowIn||rk==RestartKind::GoalKick||rk==RestartKind::Corner);
        if (!freeRestart && !(kind==KickKind::Shot||countsAsShot)) {
            std::vector<float> opp; for (auto& q : players) if (q.team==Opponent(p.team) && q.onPitch) opp.push_back(q.pos.x);
            for (int j=0;j<(int)players.size();++j) if (players[j].team==p.team && j!=i && players[j].onPitch)
                if (Laws::IsOffside(players[j].pos.x,ball.position.x,opp,AttackSign(p.team))) pendingOffside[j]=players[j].pos; }
        int t=(int)p.team;
        if (kind==KickKind::Shot||countsAsShot) { stats[t].shots+=1; auto c=PredictGoalCrossing(AttackSign(p.team));
            if (c && std::fabs(c->z)<Pitch::GoalWidth/2 && c->y<Pitch::GoalHeight) stats[t].shotsOnTarget+=1; }
        else if (target>=0) stats[t].passes+=1;
        Emit(GameEvent::Kick,i,(int)kind,power);
    }
    void ExecutePass(int i, int j, KickKind kind, std::optional<float> power, bool human) {
        const Footballer p=players[i], r=players[j]; const auto& a=p.attributes; float sign=AttackSign(p.team);
        float t=Distance(r.pos,p.pos)/14; Vec2 tgt=r.pos+r.vel*t;
        if (kind==KickKind::Through) tgt=r.pos+Vec2(sign*6,0)+r.vel*(t+0.4f);
        tgt=ClampToPitch(tgt,0.5f); float d=Distance(tgt,p.pos); t=d/14;
        float arrive = kind==KickKind::Through ? 9.f : (power ? 6+8*(*power) : 7.5f);
        if (kind==KickKind::Lob) { ExecuteLob(i,tgt,j,human,power?*power:0.6f); return; }
        float speed=std::min(GroundPassSpeed(d,arrive),a.MaxPassSpeed()); Vec2 dir=Unit(tgt-p.pos);
        float errMul = human ? 0.7f : (2.5f-1.7f*teams[(int)p.team].skill);
        dir=Rot(dir, rng.Gaussian()*a.PassError(d>25)*(1+d/30)*errMul);
        speed*=1+rng.Gaussian()*0.03f;
        Vec3 v(dir.x*speed,0,dir.y*speed);
        if (phase.kind==Phase::Restart && phase.info.kind==RestartKind::ThrowIn) { float s=std::min(speed,16.f); v=Vec3(dir.x*s,4.0f,dir.y*s); }
        KickBall(i,v,Vec3(),kind,power?*power:0.5f,j);
    }
    void ExecuteLob(int i, Vec2 point, int target, bool human, float power, float loft=0.62f) {
        const Footballer p=players[i]; float d=std::max(2.f,Distance(point,p.pos));
        float v=std::sqrt(d*Pitch::Gravity/std::sin(2*loft))*(1.06f+d*0.0018f); v=std::min(v,p.attributes.MaxPassSpeed()+8);
        Vec2 dir=Unit(point-p.pos); float errMul = human ? 0.8f : (2.5f-1.7f*teams[(int)p.team].skill);
        dir=Rot(dir, rng.Gaussian()*p.attributes.PassError(true)*(1+d/25)*errMul);
        Vec3 vel(dir.x*v*std::cos(loft), v*std::sin(loft), dir.y*v*std::cos(loft));
        if (phase.kind==Phase::Restart && phase.info.kind==RestartKind::ThrowIn) vel=Vec3(dir.x*std::min(v,15.f)*0.8f,4,dir.y*std::min(v,15.f)*0.8f);
        KickBall(i,vel,Vec3(),KickKind::Lob,power,target);
    }
    void ExecuteShot(int i, float power, std::optional<Vec2> aim, bool human, bool finesse=false) {
        const Footballer p=players[i]; const auto& a=p.attributes; float sign=AttackSign(p.team); float goalX=sign*Pitch::HalfLength;
        float speed=13+(a.MaxShotSpeed()-13)*power; Vec2 dirXZ; float vy; float distGoal=std::fabs(goalX-p.pos.x); Vec2 facing = aim ? *aim : p.Facing();
        if (human) {
            dirXZ=Unit(facing);
            if (dirXZ.x*sign>0.05f) { float t=(goalX-p.pos.x)/dirXZ.x; float zLine=p.pos.y+dirXZ.y*t;
                if (std::fabs(zLine)<Pitch::GoalWidth/2+5) { float aimZ=std::max(-3.f,std::min(3.f,zLine)); dirXZ=Unit(dirXZ*0.15f+Unit(Vec2(goalX-p.pos.x,aimZ-p.pos.y))*0.85f); } }
            float loft=0.04f+0.13f*power; vy=speed*std::sin(loft); speed*=std::cos(loft);
        } else {
            const Footballer* gk=nullptr; for (auto& q : players) if (q.team==Opponent(p.team) && q.role==Role::GK){gk=&q;break;}
            float side = (gk?gk->pos.y:0.f)>=0 ? -1.f : 1.f;
            float aimZ=side*rng.Range(2.2f,3.4f); float aimY=rng.Range(0.25f, distGoal>18?1.0f:1.7f);
            float hd=Distance(Vec2(goalX,aimZ),p.pos); float vh=speed; float tt=hd/vh;
            for (int k=0;k<2;++k) { vh=speed-0.5f*physics.Config.airDragK*speed*speed*tt; tt=hd/std::max(vh,5.f); }
            dirXZ=Unit(Vec2(goalX,aimZ)-p.pos); vy=(aimY-Pitch::BallRadius)/tt+0.5f*Pitch::Gravity*tt; vy=std::min(vy,11.f);
        }
        bool volley = ball.position.y>0.3f && BallSpeed(ball)>5; if (volley) speed*=1.06f;
        float errMul = human ? 0.8f : (3.2f-2.2f*teams[(int)p.team].skill); if (volley) errMul*=1.8f;
        float err=a.ShotError()*(1+distGoal/25)*errMul; Vec3 spin;
        if (finesse && human && distGoal>8 && dirXZ.x*sign>0.05f) {
            float t=(goalX-p.pos.x)/dirXZ.x; float zLine=p.pos.y+dirXZ.y*t; float curlSide = zLine>=0?1.f:-1.f;
            dirXZ=Unit(Vec2(goalX-p.pos.x, curlSide*(Pitch::GoalWidth/2+1.1f)-p.pos.y)); spin=Vec3(0,curlSide*sign*42,0); speed*=0.88f; }
        dirXZ=Rot(dirXZ,rng.Gaussian()*err); vy*=1+rng.Gaussian()*err*2;
        KickBall(i,Vec3(dirXZ.x*speed,vy,dirXZ.y*speed),spin,volley?KickKind::Volley:KickKind::Shot,power,-1,true);
    }
    void AttemptTackle(int i, bool slide) {
        Footballer& p=players[i];
        if (!(p.tackleCooldown<=0 && p.stun<=0 && !p.IsSliding() && p.fallenTime<=0 && p.role!=Role::GK)) return;
        p.tackleAnim=0.4f;
        if (slide) { p.tackleCooldown=1.6f; p.slideDir=p.Facing(); p.slideTime=0.55f; p.vel=p.Facing()*8; return; }
        p.tackleCooldown=0.7f;
        if (ballOwner>=0 && players[ballOwner].team!=p.team && Distance(players[ballOwner].pos,p.pos)<1.35f) { p.tackleCooldown=1.1f; ResolveTackle(i,ballOwner,false); }
    }
    void SlideContact(int i) {
        if (!players[i].IsSliding()) return;
        if (ballOwner>=0 && players[ballOwner].team!=players[i].team && Distance(players[ballOwner].pos,players[i].pos)<1.4f) {
            players[i].slideTime=std::min(players[i].slideTime,0.25f); ResolveTackle(i,ballOwner,true); }
        else if (ballOwner<0 && ball.position.y<0.4f && Distance(BXZ(),players[i].pos)<1.2f && players[i].kickLock<=0) {
            ball.velocity=Vec3(players[i].slideDir.x*8,0.5f,players[i].slideDir.y*8); NoteTouch(i); players[i].kickLock=0.3f; }
    }
    void ResolveTackle(int i, int o, bool slide) {
        const auto a=players[i].attributes, d=players[o].attributes;
        float atk=0.55f*float(a.tackling)+0.2f*float(a.strength)+0.25f*float(a.defensiveAwareness);
        float def=0.5f*float(d.dribbling)+0.25f*float(d.balance)+0.25f*float(d.strength);
        float pWin=std::max(0.12f,std::min(0.85f,0.45f+0.012f*(atk-def-(players[o].jockey?18.f:0.f))-(slide?0.05f:0.f)));
        if (players[o].evade>0) pWin*=0.35f;
        Vec2 toTackler=Unit(players[i].pos-players[o].pos); bool fromBehind=Dot(players[o].Facing(),toTackler)<-0.3f; int t=TeamOf(i);
        stats[t].tackles+=1;
        if (rng.Float()<pWin) { stats[t].tacklesWon+=1; Vec2 f=players[i].Facing(); ball.velocity=Vec3(f.x*4,0.6f,f.y*4);
            ballOwner=-1; lastTouch=i; players[o].stun=0.45f; players[o].kickLock=0.5f; Emit(GameEvent::Tackle,i,o,1); }
        else { float foulP=(slide?0.5f:0.16f)*(1-0.003f*float(a.defensiveAwareness))*(fromBehind?1.7f:1.f); Emit(GameEvent::Tackle,i,o,0);
            if (rng.Float()<foulP) CallFoul(i,o,slide?1.f:0.5f,fromBehind); else players[i].stun=std::max(players[i].stun,0.4f); }
    }

    // ---- human control
    void HumanControl(TeamSide side, const PlayerInput& input, float dt) {
        int ti=(int)side; int c=teams[ti].controlled; Vec2 bxz=BXZ();
        if (c<0 || !players[c].onPitch || players[c].role==Role::GK) { int n=NearestOutfield(side,bxz); if (n>=0) c=n; teams[ti].controlled=c; }
        if (c<0) return;
        PlayerInput prev=teams[ti].prevInput;
        if (input.switchPressed && !prev.switchPressed && PickSwitch(side,input.move)>=0) { int n=PickSwitch(side,input.move); SwitchControl(side,n); c=n; }
        else if (teams[ti].sinceSwitch>0.8f && (ballOwner<0 || players[ballOwner].team!=side)) {
            int n=NearestOutfield(side,bxz); if (n>=0 && n!=c && Distance(players[n].pos,bxz)+4<Distance(players[c].pos,bxz)) { SwitchControl(side,n); c=n; } }
        bool frozen = phase.kind==Phase::Restart && phase.info.taker==c;
        for (int k=0;k<(int)players.size();++k) if (players[k].team==side && k!=c && players[k].state==AIState::Controlled) players[k].state=AIState::Idle;
        players[c].state=AIState::Controlled; players[c].jockey=input.jockeyHeld; HumanSkill(c,input);
        float len=Length(input.move);
        if (frozen) { players[c].desiredDir=Vec2(); if (len>0.2f) players[c].heading=std::atan2(input.move.y,input.move.x); }
        else { players[c].desiredDir=input.move; players[c].wantSprint=input.sprint; }
        if (input.tackleHeld && !prev.tackleHeld) AttemptTackle(c,false);
        if (input.slideHeld && !prev.slideHeld) AttemptTackle(c,true);
        if (players[c].IsSliding()) SlideContact(c);
        if (teams[ti].pendingKick) { PendingKick pk=*teams[ti].pendingKick; pk.remaining-=dt;
            if (Distance(BXZ(),players[c].pos)<kickTuning.range && ball.position.y<1.0f) { teams[ti].pendingKick.reset(); HumanKick(c,pk.kind,pk.power,pk.input); }
            else if (pk.remaining<=0) teams[ti].pendingKick.reset(); else teams[ti].pendingKick=pk; }
        const KickTuning k=kickTuning;
        if (!teams[ti].charge) {
            if (input.passHeld && !prev.passHeld) teams[ti].charge=KickCharge{KickKind::Pass,0,0};
            else if (input.throughHeld && !prev.throughHeld) teams[ti].charge=KickCharge{KickKind::Through,0,0};
            else if (input.lobHeld && !prev.lobHeld) teams[ti].charge=KickCharge{KickKind::Lob,0,0};
            else if (input.shootHeld && !prev.shootHeld) teams[ti].charge=KickCharge{KickKind::Shot,0,0};
        } else { KickCharge ch=*teams[ti].charge; ch.time+=dt; ch.level=std::min(1.f,ch.time/k.chargeTime); bool held=false;
            switch (ch.kind) { case KickKind::Pass: held=input.passHeld; break; case KickKind::Through: held=input.throughHeld; break; case KickKind::Lob: held=input.lobHeld; break; case KickKind::Shot: held=input.shootHeld; break; default: break; }
            if (held) teams[ti].charge=ch; else { teams[ti].charge.reset(); HumanKick(c,ch.kind,k.minPower+(1-k.minPower)*ch.level,input); } }
        teams[ti].prevInput=input;
    }
    int PickSwitch(TeamSide side, Vec2 stick) const {
        int cur=teams[(int)side].controlled; Vec2 bxz=BXZ(); int best=-1; float bs=0;
        for (int k=0;k<(int)players.size();++k) { if (!(players[k].team==side && players[k].onPitch && players[k].role!=Role::GK && k!=cur)) continue;
            float s=Distance(players[k].pos,bxz); if (Length(stick)>0.3f) s-=6*Dot(Unit(players[k].pos-players[cur].pos),Unit(stick));
            if (best<0 || s<bs){best=k;bs=s;} }
        return best;
    }
    void HumanKick(int c, KickKind kind, float power, const PlayerInput& input) {
        const Footballer p=players[c]; Vec2 bxz=BXZ();
        if (ball.position.y>=1.0f && ball.position.y<2.3f && Distance(bxz,p.pos)<1.2f && p.role!=Role::GK && p.kickLock<=0) {
            PerformHeader(c,true,Length(input.move)>0.3f?std::optional<Vec2>(Unit(input.move)):std::optional<Vec2>(p.Facing()),std::optional<bool>(kind==KickKind::Shot),power); return; }
        if (!(Distance(bxz,p.pos)<kickTuning.range && ball.position.y<1.0f)) { teams[(int)p.team].pendingKick=PendingKick{kind,power,input,kickTuning.bufferWindow}; return; }
        teams[(int)p.team].pendingKick.reset();
        Vec2 dir = Length(input.move)>0.3f ? Unit(input.move) : p.Facing(); float sign=AttackSign(p.team);
        switch (kind) {
        case KickKind::Shot: ExecuteShot(c,power,dir,true,input.finesseHeld); break;
        case KickKind::Header: case KickKind::Volley: break;
        default: {
            int best=-1; float bestS=-INFINITY;
            for (int pass=0;pass<2;++pass) {
                for (int j=0;j<(int)players.size();++j) { if (!(players[j].team==p.team && j!=c && players[j].onPitch && players[j].role!=Role::GK)) continue;
                    Vec2 v=players[j].pos-p.pos; float d=Length(v); if (!(d>3 && d<50)) continue;
                    float cs=Dot(v/d,dir); if (!(cs>(pass==0?0.75f:0.5f))) continue;
                    float s=cs*2-d/40; if (kind==KickKind::Through) s+=(v.x*sign)/25; if (s>bestS){bestS=s;best=j;} }
                if (best>=0) break; }
            if (best>=0) ExecutePass(c,best,kind,power,true);
            else if (kind==KickKind::Lob) ExecuteLob(c,ClampToPitch(p.pos+dir*(10+30*power)),-1,true,power);
            else { float speed=8+14*power; Vec3 v(dir.x*speed,0,dir.y*speed);
                if (phase.kind==Phase::Restart && phase.info.kind==RestartKind::ThrowIn) v=Vec3(dir.x*std::min(speed,14.f),4,dir.y*std::min(speed,14.f));
                KickBall(c,v,Vec3(),kind,power,-1); } }
        }
    }
    void HumanSkill(int c, const PlayerInput& input) {
        if (!(ballOwner==c && players[c].skillCooldown<=0 && Length(input.skill)>0.7f)) return;
        Vec2 d=Unit(input.skill); Vec2 f=players[c].Facing(), right(-f.y,f.x); float dotF=Dot(d,f), dotR=Dot(d,right);
        if (dotF>0.6f) players[c].vel+=f*1.2f;
        else if (dotF<-0.6f) { players[c].skillOffset=-f*1.25f; players[c].vel*=0.4f; }
        else { float side=dotR>=0?1.f:-1.f; players[c].skillOffset=right*side*1.5f; players[c].vel+=right*side*2.2f; }
        players[c].evade=0.6f; players[c].skillAnim=0.45f; players[c].skillCooldown=1.0f; Emit(GameEvent::SkillMove,c);
    }
    void PerformHeader(int i, bool human, std::optional<Vec2> aim, std::optional<bool> shot, float power) {
        const Footballer p=players[i]; float sign=AttackSign(p.team); const auto& a=p.attributes; Vec2 goal(sign*Pitch::HalfLength,0);
        float distGoal=Distance(goal,p.pos); Vec2 incoming=HVel(ball); Vec2 dir=aim?*aim:p.Facing();
        bool wantShot = shot ? *shot : (distGoal<17 && (goal.x-p.pos.x)*sign>0); int target=-1;
        float speed=std::min(17.f,std::max(6.f,Length(incoming)*0.55f+6))*(0.9f+0.2f*float(a.strength)/100)*(0.6f+0.8f*power); float vy;
        if (wantShot) { float aimZ=std::max(-3.f,std::min(3.f,p.pos.y*0.3f))+rng.Range(-1.2f,1.2f); dir=Unit(Vec2(goal.x-p.pos.x,aimZ-p.pos.y)); speed=std::min(21.f,speed*1.25f+3); vy=-1.2f; }
        else { std::optional<PassOption> opt; if (!human) opt=BestPassOption(i);
            if (!human && opt) { target=opt->target; dir=Unit(players[opt->target].pos-p.pos); speed=std::min(14.f,Distance(players[opt->target].pos,p.pos)*0.7f+4); }
            else if (!human) { dir=Vec2(sign,p.pos.y>=0?0.6f:-0.6f); dir=Unit(dir); speed=13; }
            vy=3.2f; }
        float err=a.ShotError()*1.6f*(human?0.9f:(2.4f-1.4f*teams[(int)p.team].skill)); dir=Rot(dir,rng.Gaussian()*err*(wantShot?1.f:0.7f));
        KickBall(i,Vec3(dir.x*speed,vy,dir.y*speed),Vec3(),KickKind::Header,power,target,wantShot);
        players[i].headAnim=0.6f; players[i].kickAnim=0;
    }
    void AutoAerial() {
        if (!(ball.position.y>=1.0f && ball.position.y<2.3f && BallSpeed(ball)>1.5f && ballOwner<0)) return;
        Vec2 bxz=BXZ(); int best=-1; float bestScore=-INFINITY;
        for (int i=0;i<(int)players.size();++i) { const Footballer& p=players[i];
            if (!(p.onPitch && p.role!=Role::GK && p.kickLock<=0 && p.stun<=0 && p.fallenTime<=0 && !p.IsSliding())) continue;
            float d=Distance(bxz,p.pos); if (!(d<0.8f)) continue; const TeamRuntime& t=teams[(int)p.team];
            if (t.human && t.controlled==i && (t.prevInput.passHeld||t.prevInput.shootHeld||t.prevInput.lobHeld||t.prevInput.throughHeld)) continue;
            float sc=float(p.attributes.strength)*0.5f+float(p.attributes.balance)*0.3f+float(p.attributes.positioning)*0.2f-d*25; if (sc>bestScore){bestScore=sc;best=i;} }
        if (best<0) return; bool human=teams[(int)players[best].team].human && teams[(int)players[best].team].controlled==best;
        PerformHeader(best,human,std::nullopt,std::nullopt,0.6f);
    }

    // ---- restart handling
    void RestartStep(RestartInfo info, const std::array<PlayerInput,2>& inputs, float dt) {
        info.elapsed+=dt; phase.kind=Phase::Restart; phase.info=info;
        if (tick%6==0) UpdateContexts();
        for (int s=0;s<2;++s) if (teams[s].human) HumanControl((TeamSide)s,inputs[s],dt);
        for (int i=0;i<(int)players.size();++i) { if (!players[i].onPitch) continue;
            if (i==info.taker) { players[i].desiredDir=Vec2(); players[i].state=AIState::SetPiece; continue; }
            int ti=TeamOf(i); if (teams[ti].controlled==i && teams[ti].human) continue;
            if (shootoutActive && players[i].role!=Role::GK) { players[i].desiredDir=Vec2(); players[i].state=AIState::Idle; continue; }
            SetPieceThink(i,info); }
        for (int i=0;i<(int)players.size();++i) Integrate(i,dt);
        EnforceRestartConstraints(info); SeparatePlayers(); GoalkeepersStep(dt);
        if (phase.kind==Phase::Restart) {
            ball.position=Vec3(info.spot.x,Pitch::BallRadius,info.spot.y); ball.velocity=Vec3();
            bool humanTaker=teams[TeamOf(info.taker)].human; float limit=humanTaker?9.f:0.f;
            if (info.elapsed>=info.minWait && (!humanTaker || info.elapsed>=limit)) AiTakeRestart(info); }
    }
    void EnforceRestartConstraints(const RestartInfo& info) {
        Vec2 spot=info.spot; TeamSide opp=Opponent(info.team);
        for (int i=0;i<(int)players.size();++i) { if (!(players[i].onPitch && i!=info.taker)) continue; Vec2 p=players[i].pos;
            switch (info.kind) {
            case RestartKind::Corner: case RestartKind::FreeKick: case RestartKind::IndirectFreeKick:
                if (players[i].team==opp) { float d=Distance(p,spot); if (d<Laws::WallDistance) p=spot+Unit(p-spot)*(Laws::WallDistance+0.05f); } break;
            case RestartKind::GoalKick:
                if (players[i].team==opp && Laws::InPenaltyArea(p,info.team)) p.x=AttackSign(info.team)*(-Pitch::HalfLength+Pitch::PenaltyAreaDepth+1); break;
            case RestartKind::Kickoff: { float s=AttackSign(players[i].team); if (p.x*s>-0.3f) p.x=-0.3f*s;
                if (players[i].team==opp && Length(p)<Laws::WallDistance) { p=Unit(p)*(Laws::WallDistance+0.1f); if (p.x*s>-0.3f) p.x=-0.3f*s; } break; }
            case RestartKind::Penalty: { TeamSide defending=opp; bool isGK=players[i].role==Role::GK && players[i].team==defending;
                if (isGK) p=Vec2(AttackSign(defending)*(-Pitch::HalfLength+0.3f),std::max(-3.5f,std::min(3.5f,p.y)));
                else { Vec2 ps=Laws::PenaltySpot(defending);
                    if (Laws::InPenaltyArea(p,defending) || Distance(p,ps)<Laws::WallDistance) { float dirOut=defending==TeamSide::Home?1.f:-1.f;
                        p.x=(defending==TeamSide::Home?-1.f:1.f)*(Pitch::HalfLength-Pitch::PenaltyAreaDepth)+dirOut*1.5f; } } break; }
            case RestartKind::ThrowIn: break; }
            players[i].pos=p; }
    }

    // ---- AI
    Vec2 PredictBallXZ(float t) const { float k=0.3f; Vec2 v=HVel(ball); return BXZ()+v*((1-std::exp(-k*t))/k); }
    float TimeToBall(int i) const {
        const Footballer& p=players[i]; float sp=std::max(3.f,p.attributes.SprintMS()*0.95f); float t=0;
        for (int k=0;k<3;++k) { float d=std::max(0.f,Distance(p.pos,PredictBallXZ(t))-0.6f); t=d/sp+0.15f; } return t;
    }
    void UpdateContexts() {
        int ownerTeam = ballOwner>=0 ? TeamOf(ballOwner) : -1; int lastTeam = lastTouch>=0 ? TeamOf(lastTouch) : -1;
        for (int si=0;si<2;++si) { TeamSide side=(TeamSide)si; float sign=AttackSign(side); TeamContext c;
            if (ballOwner>=0 && ownerTeam==si) c.carrier=ballOwner;
            c.inPossession = ownerTeam==si || (ownerTeam<0 && lastTeam==si && intendedReceiver>=0);
            c.ballDepth=std::max(0.f,std::min(1.f,(ball.position.x*sign+Pitch::HalfLength)/Pitch::Length));
            c.ballLat=std::max(-1.f,std::min(1.f,ball.position.z*sign/Pitch::HalfWidth));
            std::vector<float> oppA; for (auto& q : players) if (q.team==Opponent(side) && q.onPitch) oppA.push_back(q.pos.x*sign);
            std::sort(oppA.begin(),oppA.end(),std::greater<float>());
            c.offsideLine=std::max({oppA.size()>=2?oppA[1]:0.f, ball.position.x*sign, 0.f});
            std::vector<std::pair<int,float>> ranked;
            for (int i=0;i<(int)players.size();++i) if (players[i].team==side && players[i].onPitch && players[i].role!=Role::GK) ranked.push_back({i,TimeToBall(i)});
            std::stable_sort(ranked.begin(),ranked.end(),[](auto& a,auto& b){return a.second<b.second;});
            c.chaser=ranked.empty()?-1:ranked[0].first; c.second=ranked.size()>1?ranked[1].first:-1; teams[si].ctx=c; }
        AssignMarking();
    }
    void AssignMarking() {
        for (int si=0;si<2;++si) { TeamSide side=(TeamSide)si; TeamContext ctx=teams[si].ctx; float sign=AttackSign(side);
            for (auto& p : players) if (p.team==side) p.markTarget=-1;
            if (ctx.inPossession) continue;
            Vec2 ownGoal(-sign*Pitch::HalfLength,0);
            std::vector<int> threats; for (int i=0;i<(int)players.size();++i) if (players[i].team==Opponent(side) && players[i].onPitch && players[i].role!=Role::GK && i!=ballOwner) threats.push_back(i);
            std::stable_sort(threats.begin(),threats.end(),[&](int a,int b){return Distance(players[a].pos,ownGoal)<Distance(players[b].pos,ownGoal);}); if (threats.size()>6) threats.resize(6);
            std::vector<int> fr; for (int i=0;i<(int)players.size();++i) if (players[i].team==side && players[i].onPitch && i!=ctx.chaser && LineOf(players[i].role)!=Line::Goalkeeper && LineOf(players[i].role)!=Line::Forward && !(teams[si].human && teams[si].controlled==i)) fr.push_back(i);
            for (int o : threats) { if (fr.empty()) break; int bestJ=-1; float bestD=INFINITY;
                for (int j : fr) { Vec2 a=AnchorWorld(players[j].slot,side,ctx.ballDepth,false,ctx.ballLat); float d=Distance(a,players[o].pos); if (d<bestD){bestD=d;bestJ=j;} }
                if (bestJ>=0 && bestD<18) { players[bestJ].markTarget=o; fr.erase(std::remove(fr.begin(),fr.end(),bestJ),fr.end()); } } }
    }
    void RunAI(float dt) {
        for (int i=0;i<(int)players.size();++i) { if (!(players[i].onPitch && players[i].role!=Role::GK)) continue;
            TeamSide side=players[i].team; if (teams[(int)side].human && teams[(int)side].controlled==i) continue;
            if ((tick+players[i].thinkOffset)%6==0) AiThink(i);
            Steer(i); if (players[i].IsSliding()) SlideContact(i); }
    }
    void Steer(int i) {
        const Footballer p=players[i]; Vec2 to=p.target-p.pos; float d=Length(to); Vec2 dir = d>0.25f ? to/d : Vec2(); dir*=std::min(1.f,d/1.5f);
        Vec2 sep;
        for (int j=0;j<(int)players.size();++j) if (j!=i && players[j].team==p.team && players[j].onPitch) { Vec2 dd=p.pos-players[j].pos; float l=Length(dd); if (l<4 && l>0.01f) sep+=dd/l*((4-l)/4); }
        Vec2 out=dir+sep*0.5f; float l=Length(out); if (l>1) out/=l;
        if (d<0.25f && l<0.15f) { out=Vec2(); Vec2 toBall=BXZ()-p.pos;
            if (Length(toBall)>0.5f) { float dh=WrapPi(std::atan2(toBall.y,toBall.x)-p.heading); players[i].heading+=std::max(-0.08f,std::min(0.08f,dh*0.2f)); } }
        players[i].desiredDir=out;
    }
    void SetT(int i, Vec2 target, AIState state, bool sprint) { players[i].target=ClampToPitch(target,0.3f); players[i].state=state; players[i].wantSprint=sprint; }
    void AiThink(int i) {
        const Footballer p=players[i]; if (p.stun>0 || p.IsSliding() || p.fallenTime>0) return;
        TeamSide side=p.team; TeamContext ctx=teams[(int)side].ctx;
        if (ballOwner==i) { CarrierThink(i); return; }
        if (intendedReceiver==i && ballOwner<0) { float t=TimeToBall(i); SetT(i,PredictBallXZ(t),AIState::Intercepting,true); return; }
        int ownerTeam = ballOwner>=0 ? TeamOf(ballOwner) : -1;
        if (ctx.inPossession) AttackThink(i,ctx); else if (ownerTeam==(int)Opponent(side)) DefendThink(i,ctx); else LooseBallThink(i,ctx);
    }
    void PositionThink(int i, const TeamContext& ctx, bool possession) {
        const Footballer p=players[i]; Vec2 a=AnchorWorld(p.slot,p.team,ctx.ballDepth,possession,ctx.ballLat); bool behind=(a.x-p.pos.x)*AttackSign(p.team)<-12;
        if (!possession && Distance(a,p.pos)>10 && behind) SetT(i,a,AIState::Recovering,true); else SetT(i,a,AIState::Positioning,Distance(a,p.pos)>14);
    }
    void LooseBallThink(int i, const TeamContext& ctx) { if (ctx.chaser==i) { float t=TimeToBall(i); SetT(i,PredictBallXZ(t),AIState::Intercepting,true); } else PositionThink(i,ctx,false); }
    void DefendThink(int i, const TeamContext& ctx) {
        const Footballer p=players[i]; TeamSide side=p.team; float sign=AttackSign(side); const TeamTactics tac=teams[(int)side].setup.tactics;
        if (ballOwner<0) return; const Footballer owner=players[ballOwner]; Vec2 ownGoal(-sign*Pitch::HalfLength,0); float skill=teams[(int)side].skill; float pressLine=0.45f+0.5f*tac.pressing;
        if (ctx.chaser==i) { float d=Distance(p.pos,owner.pos); Vec2 goalSide=Unit(ownGoal-owner.pos);
            if (ctx.ballDepth>pressLine) SetT(i,owner.pos+goalSide*4,AIState::Pressing,false);
            else if (d>3) SetT(i,owner.pos+owner.vel*0.25f+goalSide*1.0f,AIState::Pressing,d>5);
            else { SetT(i,owner.pos+owner.vel*0.15f,AIState::Tackling,false);
                if (d<1.3f && p.tackleCooldown<=0 && rng.Float()<0.5f*skill*(0.5f+0.5f*float(p.attributes.defensiveAwareness)/100)) { bool sl = d>1.1f && rng.Float()<0.1f; AttemptTackle(i,sl); } }
            return; }
        if (ctx.second==i && tac.pressing>0.55f && ctx.ballDepth<=pressLine && LineOf(p.role)!=Line::Goalkeeper) {
            int m=-1; for (int j=0;j<(int)players.size();++j) if (players[j].team==Opponent(side) && players[j].onPitch && j!=ballOwner && players[j].role!=Role::GK)
                if (m<0 || Distance(players[j].pos,ownGoal)<Distance(players[m].pos,ownGoal)) m=j;
            if (m>=0) { SetT(i,owner.pos+(players[m].pos-owner.pos)*0.4f,AIState::Pressing,true); return; } }
        if (p.markTarget>=0 && players[p.markTarget].onPitch) { const Footballer m=players[p.markTarget]; Vec2 goalSide=Unit(ownGoal-m.pos); Vec2 toBall=Unit(owner.pos-m.pos);
            SetT(i,m.pos+goalSide*1.4f+toBall*0.5f,AIState::Marking,Distance(p.pos,m.pos)>10); return; }
        PositionThink(i,ctx,false);
    }
    float OpenSide(Vec2 p, float preferred) const {
        auto crowd=[&](float s){ float acc=0; for (auto& q : players) { if (!q.onPitch) continue; if (Distance(q.pos,p+Vec2(0,s*9))<8) acc+=1; } return acc; };
        float a=crowd(preferred), b=crowd(-preferred); return a<=b ? preferred : -preferred;
    }
    void AttackThink(int i, const TeamContext& ctx) {
        const Footballer p=players[i]; TeamSide side=p.team; float sign=AttackSign(side);
        Vec2 anchor=AnchorWorld(p.slot,side,ctx.ballDepth,true,ctx.ballLat);
        if (ctx.carrier<0) { PositionThink(i,ctx,true); return; }
        const Footballer c=players[ctx.carrier]; Line line=LineOf(p.role); if (line==Line::Goalkeeper) return;
        float myLat = (p.role==Role::LB||p.role==Role::LM||p.role==Role::LW) ? -1.f : ((p.role==Role::RB||p.role==Role::RM||p.role==Role::RW)?1.f:0.f);
        int rank=0; float dC=Distance(p.pos,c.pos);
        for (int j=0;j<(int)players.size();++j) if (j!=i && j!=ctx.carrier && players[j].team==side && players[j].onPitch && players[j].role!=Role::GK) if (Distance(players[j].pos,c.pos)<dC) rank++;
        float carrierWide = c.pos.y*sign>8 ? 1.f : (c.pos.y*sign<-8 ? -1.f : 0.f);
        if ((p.role==Role::LB||p.role==Role::RB) && carrierWide!=0 && carrierWide==myLat && (c.pos.x-p.pos.x)*sign<12 && IsWide(c.role)) {
            SetT(i,Vec2(c.pos.x+sign*9,sign*myLat*(Pitch::HalfWidth-4)),AIState::Supporting,true); return; }
        float aOff=ctx.offsideLine;
        if (line==Line::Forward || p.role==Role::AM) { float a=std::max(anchor.x*sign,c.pos.x*sign+10); a=std::min(a,aOff-0.8f); float z=anchor.y;
            if (ctx.ballDepth>0.62f) { float r=rng.Float(); z=z*0.4f+(r<0.5f?0.f:0.f)+(z>=0?4.f:-4.f)*0.5f; }
            SetT(i,Vec2(a*sign,z),AIState::Supporting,true); return; }
        if (rank<2 && line!=Line::Defender) { float side2=(i%2==0)?1.f:-1.f; float open=OpenSide(c.pos,side2);
            SetT(i,Vec2(c.pos.x+sign*5,c.pos.y+open*9),AIState::Supporting,dC>12); return; }
        if (IsWide(p.role)) { Vec2 t=anchor; t.y=(t.y>=0?1.f:-1.f)*Pitch::HalfWidth*0.82f; SetT(i,t,AIState::Supporting,false); return; }
        PositionThink(i,ctx,true);
    }
    float NearestOpponentDistance(Vec2 p, TeamSide side) const { float m=INFINITY; for (auto& q : players) if (q.team!=side && q.onPitch) m=std::min(m,Distance(q.pos,p)); return m; }
    float LaneRisk(Vec2 a, Vec2 b, TeamSide side) const {
        Vec2 ab=b-a; float len2=std::max(Dot(ab,ab),1e-4f), len=std::sqrt(len2), risk=0;
        for (auto& o : players) { if (!(o.team!=side && o.onPitch)) continue;
            float s=std::max(0.f,std::min(1.f,Dot(o.pos-a,ab)/len2)); Vec2 q=a+ab*s; float dq=Distance(o.pos,q); if (dq>3.5f) continue;
            float tBall=s*len/13; float tOpp=std::max(0.f,dq-0.5f)/std::max(3.f,o.attributes.SprintMS()*0.9f)+0.2f;
            if (tOpp<tBall+0.2f) risk=std::max(risk,1-dq/3.5f); }
        return risk;
    }
    std::optional<PassOption> BestPassOption(int i, bool lng=false) const {
        const Footballer p=players[i]; TeamSide side=p.team; float sign=AttackSign(side); const TeamTactics tac=teams[(int)side].setup.tactics;
        float pressure=NearestOpponentDistance(p.pos,side); std::optional<PassOption> best;
        for (int j=0;j<(int)players.size();++j) { if (!(players[j].team==side && j!=i && players[j].onPitch)) continue; const Footballer& r=players[j];
            float d=Distance(r.pos,p.pos); if (!(d>4 && d<48)) continue;
            if (r.role==Role::GK && !(pressure<3 && p.pos.x*sign<-10)) continue;
            float progress=(r.pos.x-p.pos.x)*sign; float progN=std::max(-0.4f,std::min(1.f,progress/25)); float risk=LaneRisk(p.pos,r.pos,side);
            float open=std::min(10.f,NearestOpponentDistance(r.pos,side))/10;
            float u=0.35f*progN*(0.6f+0.8f*tac.directness)+0.3f*open+0.3f*(1-risk)+0.1f;
            if (d>12) u-=0.016f*(d-12);
            if (risk>0.45f && pressure>2.5f) continue;
            if (r.pos.x*sign>Pitch::HalfLength-20) u+=0.15f;
            if (progress<-5) u-= pressure<2.5f ? -0.05f : 0.08f;
            if (lng) u+= d>25 ? 0.2f : -0.1f;
            KickKind kind=KickKind::Pass;
            if (progress>10 && risk<0.35f && Dot(r.vel,Vec2(sign,0))>2 && LineOf(r.role)!=Line::Defender) kind=KickKind::Through;
            else if ((risk>0.5f && open>0.5f && p.attributes.longPassing>45) || d>32) { kind=KickKind::Lob; if (risk>0.5f) u-=0.1f; }
            u*=(1-0.85f*risk);
            float nearOpp=NearestOpponentDistance(r.pos,side); u*=std::min(1.f,0.45f+0.22f*nearOpp);
            float fastestOpp=INFINITY; for (auto& o : players) if (o.team!=side && o.onPitch) fastestOpp=std::min(fastestOpp,std::max(0.f,Distance(o.pos,r.pos)-0.6f)/std::max(3.f,o.attributes.SprintMS()*0.9f));
            float recvT=Distance(r.pos,r.pos+r.vel*0.5f)/std::max(3.f,r.attributes.SprintMS())+d/15;
            if (fastestOpp<recvT*0.5f && nearOpp<3) u*=0.5f;
            u*=0.7f+0.3f*float(kind==KickKind::Lob?p.attributes.longPassing:p.attributes.shortPassing)/100;
            if (!best || u>best->utility) best=PassOption{j,kind,u}; }
        return best;
    }
    float ShootUtility(int i) const {
        const Footballer p=players[i]; float sign=AttackSign(p.team); Vec2 goal(sign*Pitch::HalfLength,0); float dist=Distance(goal,p.pos);
        if (!(dist<32 && (goal.x-p.pos.x)*sign>0)) return 0;
        float xg=TacticalPriors::XG(std::fabs(goal.x-p.pos.x),p.pos.y); float block=LaneRisk(p.pos,goal,p.team);
        return 2.4f*xg*(1-0.6f*block)*(0.6f+0.4f*float(p.attributes.shootingAccuracy)/100);
    }
    void CarrierThink(int i) {
        const Footballer p=players[i]; TeamSide side=p.team; float sign=AttackSign(side); float skill=teams[(int)side].skill;
        float pressure=NearestOpponentDistance(p.pos,side); float delay=p.attributes.DecisionDelay()*(2.2f-1.3f*skill); Vec2 goal(sign*Pitch::HalfLength,0);
        Vec2 rep; float fr=12; Vec2 aimDir=Unit(Vec2(goal.x-p.pos.x,p.pos.y*-0.25f));
        for (auto& q : players) if (q.team!=side && q.onPitch) { float d=Distance(q.pos,p.pos); if (d<8) { Vec2 u=Unit(q.pos-p.pos); if (Dot(u,aimDir)>0.2f) { rep-=u*(1-d/8); fr=std::min(fr,d); } } }
        Vec2 dir=Unit(aimDir+rep*1.6f);
        if (std::fabs(p.pos.y)>Pitch::HalfWidth-4) { dir.y-=(p.pos.y>0?1.f:-1.f)*0.8f; dir=Unit(dir); }
        if (p.possessionTime<(pressure<2.5f?0.1f:delay)) { SetT(i,p.pos+dir*8,AIState::Dribbling,false); return; }
        float shoot=ShootUtility(i); auto pass=BestPassOption(i,p.pos.x*sign<-25 && pressure<3);
        float dribble=0.15f+0.35f*(fr/12)*(0.5f+float(p.attributes.dribbling)/100); float noise=rng.Gaussian()*0.1f*(1-skill);
        float passU=(pass?pass->utility:0.f)+noise; float distGoal=Distance(goal,p.pos);
        if (shoot>=0.28f || shoot>=std::max(0.12f,passU*0.7f) || (shoot>0.05f && pressure<1.8f && distGoal<25 && passU<0.4f)) {
            SetT(i,goal,AIState::Shooting,false); ExecuteShot(i,rng.Range(0.7f,1.0f),std::nullopt,false); return; }
        if (pass && ((passU>dribble && passU>0.3f) || (pressure<1.6f && passU>0.2f))) { SetT(i,players[pass->target].pos,AIState::Passing,false); ExecutePass(i,pass->target,pass->kind,std::nullopt,false); return; }
        if (pressure<2 && p.pos.x*sign<-Pitch::HalfLength+25) { Vec2 tgt(p.pos.x+sign*32,p.pos.y>=0?26.f:-26.f); SetT(i,tgt,AIState::Passing,false); ExecuteLob(i,ClampToPitch(tgt),-1,false,0.8f); return; }
        SetT(i,p.pos+dir*8,AIState::Dribbling,fr>6 && p.stamina>0.3f);
    }
    void SetPieceThink(int i, const RestartInfo& info) {
        const Footballer p=players[i]; TeamSide side=p.team; float sign=AttackSign(side); bool attacking= side==info.team; TeamContext ctx=teams[(int)side].ctx;
        float spotDepth=std::max(0.f,std::min(1.f,(info.spot.x*sign+Pitch::HalfLength)/Pitch::Length)); ctx.ballDepth=spotDepth; ctx.ballLat=std::max(-1.f,std::min(1.f,info.spot.y*sign/Pitch::HalfWidth));
        Vec2 t=AnchorWorld(p.slot,side,spotDepth,attacking,ctx.ballLat); float attackGoalX=AttackSign(info.team)*Pitch::HalfLength; int slot=p.slot;
        if (p.role==Role::GK) { if (p.team!=info.team || info.kind!=RestartKind::GoalKick) t=AnchorWorld(slot,side,spotDepth,false,0); players[i].desiredDir=Vec2(); }
        switch (info.kind) {
        case RestartKind::Corner: { bool inList=(p.role==Role::ST||p.role==Role::LW||p.role==Role::RW||p.role==Role::AM||p.role==Role::CB||p.role==Role::CM);
            bool boxer=(inList && slot%2==0) || p.role==Role::ST;
            if (attacking && boxer && p.role!=Role::GK) t=Vec2(attackGoalX-AttackSign(info.team)*(7+float(slot%3)*2),float(slot%4-1)*3-1.5f);
            else if (!attacking && p.role!=Role::GK && LineOf(p.role)!=Line::Forward) t=Vec2(attackGoalX-AttackSign(info.team)*(5+float(slot%3)*2),float(slot%5-2)*3); break; }
        case RestartKind::FreeKick: { float dGoal=std::fabs(attackGoalX-info.spot.x);
            if (attacking && dGoal<32 && LineOf(p.role)==Line::Forward && i!=info.taker) t=Vec2(attackGoalX-AttackSign(info.team)*9,float(slot%3-1)*4);
            else if (!attacking && LineOf(p.role)==Line::Defender && p.role!=Role::GK) { Vec2 ownGoal(attackGoalX,0); std::vector<int> defs;
                for (int k=0;k<(int)players.size();++k) if (players[k].team==side && LineOf(players[k].role)==Line::Defender && players[k].onPitch) defs.push_back(k);
                std::stable_sort(defs.begin(),defs.end(),[&](int a,int b){return Distance(players[a].pos,info.spot)<Distance(players[b].pos,info.spot);});
                int kk=-1; for (int q=0;q<(int)defs.size() && q<3;++q) if (defs[q]==i) kk=q;
                if (kk>=0 && dGoal<32) { Vec2 dir=Unit(ownGoal-info.spot); Vec2 perp(-dir.y,dir.x); t=info.spot+dir*9.4f+perp*(float(kk)-1)*0.8f; } } break; }
        case RestartKind::Penalty: if (p.role!=Role::GK) t=Vec2(attackGoalX-AttackSign(info.team)*20,float(slot%6-3)*5); break;
        case RestartKind::ThrowIn: if (attacking && p.role!=Role::GK) { std::vector<int> near;
                for (int k=0;k<(int)players.size();++k) if (players[k].team==side && players[k].onPitch && players[k].role!=Role::GK && k!=info.taker) near.push_back(k);
                std::stable_sort(near.begin(),near.end(),[&](int a,int b){return Distance(players[a].pos,info.spot)<Distance(players[b].pos,info.spot);});
                int kk=-1; for (int q=0;q<(int)near.size() && q<3;++q) if (near[q]==i) kk=q;
                if (kk>=0) { float inward=info.spot.y>0?-1.f:1.f; t=Vec2(info.spot.x+sign*float(kk)*6-3,info.spot.y+inward*(7+float(kk)*4)); } } break;
        default: break; }
        if (p.role==Role::GK && !(p.team==info.team && info.kind==RestartKind::GoalKick)) { SetT(i,t,AIState::Goalkeeping,false); return; }
        SetT(i,t,AIState::SetPiece,Distance(p.pos,t)>12);
    }
    void AiTakeRestart(const RestartInfo& info) {
        int i=info.taker; const Footballer p=players[i]; float sign=AttackSign(p.team); float attackGoalX=sign*Pitch::HalfLength;
        auto matesBy=[&](Vec2 ref){ int b=-1; for (int j=0;j<(int)players.size();++j) if (players[j].team==p.team && j!=i && players[j].onPitch && players[j].role!=Role::GK) if (b<0 || Distance(players[j].pos,ref)<Distance(players[b].pos,ref)) b=j; return b; };
        switch (info.kind) {
        case RestartKind::Kickoff: { int j=matesBy(p.pos); if (j>=0) ExecutePass(i,j,KickKind::Pass,0.3f,false); break; }
        case RestartKind::GoalKick: { auto opt=BestPassOption(i,true);
            if (opt) { if (opt->kind==KickKind::Lob || Distance(players[opt->target].pos,p.pos)>28) ExecutePass(i,opt->target,KickKind::Lob,0.8f,false); else ExecutePass(i,opt->target,opt->kind,0.6f,false); }
            else ExecuteLob(i,Vec2(p.pos.x+sign*38,0),-1,false,0.9f); break; }
        case RestartKind::ThrowIn: case RestartKind::IndirectFreeKick: { auto opt=BestPassOption(i);
            if (opt) ExecutePass(i,opt->target,opt->kind==KickKind::Through?KickKind::Pass:opt->kind,0.5f,false);
            else ExecuteLob(i,ClampToPitch(p.pos+Vec2(sign*12,0)),-1,false,0.5f); break; }
        case RestartKind::Corner: { float rx=rng.Range(6,10); float rz=rng.Range(-4,4); Vec2 spotT(attackGoalX-sign*rx,rz); int near=matesBy(spotT);
            ExecuteLob(i,spotT,near,false,0.8f,0.75f); break; }
        case RestartKind::FreeKick: { float dGoal=Distance(Vec2(attackGoalX,0),p.pos);
            if (dGoal<28) ExecuteShot(i,0.85f,std::nullopt,false);
            else { auto opt=BestPassOption(i,dGoal<50); if (opt) ExecutePass(i,opt->target,opt->kind==KickKind::Through?KickKind::Pass:opt->kind,0.6f,false); else ExecuteLob(i,Vec2(attackGoalX-sign*10,0),-1,false,0.7f); } break; }
        case RestartKind::Penalty: ExecuteShot(i,0.9f,std::nullopt,false); break; }
    }

    // ---- goalkeepers
    void GoalkeepersStep(float dt) { for (int g=0;g<(int)players.size();++g) if (players[g].role==Role::GK && players[g].onPitch) GoalkeeperStep(g,dt); }
    void GoalkeeperStep(int g, float dt) {
        const Footballer p=players[g]; TeamSide side=p.team; float sign=AttackSign(side); Vec2 goalDir(sign,0); float ownGoalX=-sign*Pitch::HalfLength; Vec2 goalCentre(ownGoalX,0); Vec2 bxz=BXZ();
        players[g].state=AIState::Goalkeeping;
        if (phase.kind==Phase::Restart && phase.info.taker==g) return;
        if (p.diveTime>0) { CheckSave(g); return; }
        if (p.holdingBall) { players[g].desiredDir=Vec2(); players[g].holdTimer-=dt; if (players[g].holdTimer<=0) Distribute(g); return; }
        if (ballOwner==g) { players[g].desiredDir=Vec2(); if (players[g].possessionTime>0.7f) Distribute(g); return; }
        Vec2 target=goalCentre+goalDir*2; bool sprint=false;
        bool towardsGoal = ball.velocity.x*(-sign)>3; std::optional<Crossing> cross; if (towardsGoal && ballOwner<0) cross=PredictGoalCrossing(-sign);
        if (cross && std::fabs(cross->z)<Pitch::GoalWidth/2+1.5f && cross->y<3.0f) {
            if (players[g].reactTimer==0) players[g].reactTimer=0.1f+float(100-p.attributes.reactionTime)*0.002f+0.0001f;
            players[g].reactTimer-=dt;
            if (players[g].reactTimer<=0.0f || players[g].reactTimer==0) {
                target=Vec2(ownGoalX+goalDir.x*0.6f,std::max(-5.f,std::min(5.f,cross->z))); sprint=true; float dist=Distance(target,p.pos);
                if (cross->t<0.75f && dist>0.9f && p.diveTime<=0) { Vec2 dir=Unit(target-p.pos); players[g].diveTime=0.6f; players[g].vel=dir*std::min(8.5f,dist/std::max(0.25f,cross->t)+1);
                    players[g].diveDir=dir; players[g].state=AIState::Goalkeeping; return; }
            } else { players[g].desiredDir=Vec2(); return; }
        } else {
            players[g].reactTimer=0; Vec2 toBall=bxz-goalCentre; float d=Length(toBall); float depth=std::max(1.5f,std::min(6.f,0.8f+0.1f*d));
            if (ballOwner>=0 && players[ballOwner].team!=side && d<24) depth=std::min(d*0.45f,9.f);
            target=goalCentre+Unit(toBall)*depth; target.y=std::max(-3.4f,std::min(3.4f,target.y));
            if (ballOwner<0 && Laws::InPenaltyArea(bxz,side) && BallSpeed(ball)<6 && ball.position.y<2.4f) { float co=NearestOpponentDistance(bxz,side); if (Distance(p.pos,bxz)<co+1.5f) { target=bxz; sprint=true; } } }
        players[g].target=target; Vec2 to=target-p.pos; float dd=Length(to); players[g].desiredDir = dd>0.2f ? to/dd*std::min(1.f,dd/1.2f) : Vec2(); players[g].wantSprint=sprint;
        Vec2 face=Unit(bxz-p.pos); float fh=std::atan2(face.y,face.x); float dh=WrapPi(fh-players[g].heading);
        if (dd<0.3f) players[g].heading+=dh*std::min(1.f,6*dt);
        CheckSave(g);
    }
    void CheckSave(int g) {
        const Footballer p=players[g]; if (!(p.saveCooldown<=0 && ballOwner<0 && !p.holdingBall)) return;
        Vec3 hands(p.pos.x,std::min(ball.position.y,2.2f),p.pos.y); float reachH=0.75f+(p.diveTime>0?1.15f:0.4f); float hd=Distance(BXZ(),p.pos);
        if (!(hd<reachH && ball.position.y<(p.diveTime>0?2.5f:2.2f) && Distance(hands,ball.position)<reachH+0.6f)) return;
        if (lastTouch>=0 && players[lastTouch].team==p.team && BallSpeed(ball)<8) return;
        float sp=BallSpeed(ball); float a=float(p.attributes.goalkeeping); players[g].saveCooldown=0.4f;
        float saveP=std::max(0.25f,std::min(0.97f,0.82f+0.005f*(a-60)-0.012f*std::max(0.f,sp-18)));
        if (rng.Float()>saveP) return; int t=(int)p.team;
        float catchP=std::max(0.05f,std::min(0.97f,0.9f-0.035f*std::max(0.f,sp-8)+0.004f*(a-60))); stats[t].saves+=1;
        if (rng.Float()<catchP && ball.position.y<2.0f) { ballOwner=g; lastTouch=g; intendedReceiver=-1; pendingOffside.clear(); players[g].holdingBall=true; players[g].holdTimer=0.9f+rng.Range(0,0.8f);
            players[g].diveTime=0; players[g].vel=Vec2(); ball.velocity=Vec3(); Emit(GameEvent::Save,g,1); }
        else { float oz=rng.Range(-0.9f,0.9f); Vec2 out=Unit(Vec2(AttackSign(p.team),oz)); float vy=rng.Range(1,4);
            ball.velocity=Vec3(out.x*sp*0.45f,vy,out.y*sp*0.45f); lastTouch=g; intendedReceiver=-1; pendingOffside.clear(); Emit(GameEvent::Save,g,0); }
    }
    void Distribute(int g) {
        const Footballer p=players[g]; players[g].holdingBall=false; Vec2 f=p.Facing(); ball.position=Vec3(p.pos.x+f.x*0.4f,Pitch::BallRadius,p.pos.y+f.y*0.4f); players[g].holdTimer=0;
        const TeamTactics tac=teams[(int)p.team].setup.tactics; auto opt=BestPassOption(g,tac.directness>0.5f);
        if (opt) { float d=Distance(players[opt->target].pos,p.pos); if (d<22 && opt->kind!=KickKind::Lob) ExecutePass(g,opt->target,KickKind::Pass,0.5f,false); else ExecutePass(g,opt->target,KickKind::Lob,0.8f,false); }
        else ExecuteLob(g,Vec2(p.pos.x+AttackSign(p.team)*35,p.pos.y*0.5f),-1,false,0.9f);
        players[g].kickLock=0.5f;
    }

    // ---- advantage & shootout
    void UpdateAdvantage(float dt) {
        if (!advantage) return; AdvantageState a=*advantage; a.remaining-=dt;
        if (ballOwner>=0 && players[ballOwner].team==Opponent(a.victim)) { advantage.reset(); SetupRestart(RestartKind::FreeKick,a.victim,a.spot); return; }
        if (a.remaining<=0) advantage.reset(); else advantage=a;
    }
    void StartShootout() {
        shootoutActive=true; shootout=ShootoutState(); advantage.reset(); Emit(GameEvent::ShootoutStart); int k[2]={0,0};
        for (auto& p : players) if (p.onPitch && p.role!=Role::GK) { int t=(int)p.team; float a=float(k[t])*0.55f+(t==0?0.f:FB_PI);
            p.pos=Vec2(std::cos(a)*5.5f,std::sin(a)*5.5f); p.vel=Vec2(); p.desiredDir=Vec2(); k[t]++; }
        ballOwner=-1; shootout.timer=1.5f; phase=Phase(); phase.kind=Phase::Shootout;
    }
    void ShootoutPause(float dt) { IdleStep(dt); shootout.timer-=dt; if (shootout.timer<=0) NextShootoutKick(); }
    void NextShootoutKick() {
        TeamSide team=shootout.next; std::vector<int> el; for (int i=0;i<(int)players.size();++i) if (players[i].team==team && players[i].onPitch && players[i].role!=Role::GK) el.push_back(i);
        std::stable_sort(el.begin(),el.end(),[&](int a,int b){return players[a].attributes.shootingAccuracy+players[a].attributes.shotPower > players[b].attributes.shootingAccuracy+players[b].attributes.shotPower;});
        forcedTaker = el.empty() ? -1 : el[shootout.taken[(int)team]%el.size()];
        SetupRestart(RestartKind::Penalty,team,Laws::PenaltySpot(Opponent(team))); shootout.inFlight=true; shootout.timer=0;
    }
    void ShootoutPlayStep(float dt) {
        shootout.timer+=dt; for (auto& p : players) if (p.role!=Role::GK) p.desiredDir=Vec2();
        for (int i=0;i<(int)players.size();++i) Integrate(i,dt);
        GoalkeepersStep(dt); UpdateBallControl(dt); StepBall(dt);
        bool saved=false; size_t n=events.size(); for (size_t k=(n>6?n-6:0);k<n;++k) if (events[k].kind==GameEvent::Save) saved=true;
        int side=GoalSide(ball); int scorerSide = shootout.next==TeamSide::Home ? 1 : -1;
        if (side==scorerSide) ResolveShootoutKick(true);
        else if (side!=0 || saved || IsOutOfPlay(ball) || shootout.timer>5 || (shootout.timer>1.2f && BallSpeed(ball)<0.3f)) ResolveShootoutKick(false);
    }
    void ResolveShootoutKick(bool scored) {
        int t=(int)shootout.next; shootout.taken[t]+=1; if (scored) shootout.scored[t]+=1; Emit(GameEvent::ShootoutKick,t,scored?1:0);
        int remH=std::max(0,5-shootout.taken[0]), remA=std::max(0,5-shootout.taken[1]); int winner=-1;
        if (shootout.taken[0]>=5 && shootout.taken[1]>=5) { if (shootout.taken[0]==shootout.taken[1] && shootout.scored[0]!=shootout.scored[1]) winner = shootout.scored[0]>shootout.scored[1] ? 0 : 1; }
        else if (shootout.scored[0]>shootout.scored[1]+remA) winner=0; else if (shootout.scored[1]>shootout.scored[0]+remH) winner=1;
        ballOwner=-1;
        if (winner>=0) { shootout.winner=winner; shootoutActive=false; phase=Phase(); phase.kind=Phase::FullTime; Emit(GameEvent::FullTime); }
        else { shootout.next=Opponent(shootout.next); shootout.inFlight=false; shootout.timer=1.6f; phase=Phase(); phase.kind=Phase::Shootout; }
    }
};
}
