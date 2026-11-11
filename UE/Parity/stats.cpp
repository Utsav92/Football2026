#include "../FootballUE/Source/FootballUE/Sim/MatchSimulation.h"
#include <cstdio>
using namespace FB;
int main(int argc,char** argv){ int n=argc>1?atoi(argv[1]):20;
  for(int seed=1;seed<=n;++seed){ MatchConfig cfg; cfg.home=TeamSetup::Generated("H","HOM",75,Formation::F433,seed*3,{1,0,0},{1,1,1},0);
    cfg.away=TeamSetup::Generated("A","AWY",70,Formation::F442,seed*3+1,{0,0,1},{1,1,1},100); cfg.humanTeams[0]=cfg.humanTeams[1]=false; cfg.seed=seed;
    MatchSimulation sim(cfg); std::array<PlayerInput,2> in{}; int steps=0;
    while(sim.phase.kind!=Phase::FullTime && steps<200000){ sim.Step(in); steps++; }
    auto&a=sim.stats[0]; auto&b=sim.stats[1];
    printf("match %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",seed,steps,sim.score.home,sim.score.away,a.shots,b.shots,a.shotsOnTarget,b.shotsOnTarget,a.passes,b.passes,a.passesCompleted,b.passesCompleted,a.tackles,b.tackles,a.fouls,b.fouls,a.corners,b.corners,a.offsides,b.offsides,a.saves,b.saves,a.yellowCards+b.yellowCards,a.redCards+b.redCards); } }
