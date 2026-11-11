#include "../FootballUE/Source/FootballUE/Sim/Foundation.h"
#include <cstdio>
using namespace FB;
static const char* RN[]={"gk","cb","lb","rb","dm","cm","am","lm","rm","lw","rw","st"};
int main(){
    SplitMix64 r(42);
    for(int i=0;i<5;i++) printf("rng %llu\n",(unsigned long long)r.Next());
    for(int i=0;i<5;i++) printf("float %.7f\n",r.Float());
    for(int i=0;i<5;i++) printf("gauss %.5f\n",r.Gaussian());
    int a=r.Int(11), b=r.Int(100), c=r.Int(3); printf("int %d %d %d\n",a,b,c);
    for(int i=0;i<12;i++){ SplitMix64 g(100+i); auto at=PlayerAttributes::Generated((Role)i,70,g);
        printf("attr %s %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",RN[i],at.sprintSpeed,at.acceleration,at.stamina,at.strength,at.agility,at.balance,at.dribbling,at.ballControl,at.shortPassing,at.longPassing,at.shootingAccuracy,at.shotPower,at.defensiveAwareness,at.tackling,at.goalkeeping,at.positioning,at.reactionTime,at.Overall());
        printf("derived %s %.5f %.5f %.5f %.5f %.5f %.5f %.5f %.5f %.5f %.5f %.5f %.5f %.5f\n",RN[i],at.SprintMS(),at.JogMS(),at.AccelMS2(),at.TurnRate(),at.SprintDrain(),at.StaminaRecovery(),at.DecisionDelay(),at.TrapLimit(),at.DribbleFactor(),at.DribbleGain(),at.MaxShotSpeed(),at.MaxPassSpeed(),at.PassError(true)+at.PassError(false)+at.ShotError()); }
    std::vector<float> opp={-52,-10,5,12,20,25,30};
    struct O{float rx,bx,s;}; O os[]={{30,10,1},{22,25,1},{12,5,1},{-30,-10,-1},{-20,0,-1},{-5,-10,-1}};
    for(auto& o:os){ std::vector<float> v; for(float x:opp) v.push_back(x*o.s); printf("offside %s\n",Laws::IsOffside(o.rx,o.bx,v,o.s)?"true":"false"); }
    Vec3 ps[]={{-30,0,20},{53,0.1f,3},{53,0.1f,20},{-53,0.1f,30},{-53,0.1f,2},{60,0,-34.5f}};
    for(auto& p:ps) for(int lt=0;lt<2;lt++){ auto rr=Laws::RestartAfterBallOut(p,(TeamSide)lt);
        printf("restart %d %d %.3f %.3f %d\n",lt,(int)rr.kind,rr.spot.x,rr.spot.y,(int)rr.team); }
    struct P{float x,y;TeamSide s;}; P pp[]={{-45,5,TeamSide::Home},{-30,5,TeamSide::Home},{45,25,TeamSide::Away},{45,0,TeamSide::Away},{-52,19,TeamSide::Home}};
    for(auto& p:pp) printf("pen %s\n",Laws::InPenaltyArea({p.x,p.y},p.s)?"true":"false");
    for(float len:{360.f,600.f}){ MatchClock c; c.matchLengthSeconds=len; FixedStepper st; int steps=0;
        for(int f=0;f<1000;f++){ steps+=st.Advance(0.013f+float(f%7)*0.002f); c.Tick(0.0083f);} 
        printf("clock %.3f %d %.3f %d\n",c.gameSeconds,c.Minutes(),c.TimeScale(),steps);
        c.StartSecondHalf(); c.addedSeconds=120;
        printf("clock2 %d %g %g %s %s\n",c.half,c.gameSeconds,c.NominalEnd(),c.InAddedTime()?"true":"false",c.IsHalfOver()?"true":"false");
        c.StartNextPeriod(); printf("clock3 %d %g %g\n",c.half,c.gameSeconds,c.NominalEnd()); }
}
