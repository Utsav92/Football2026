#include "../FootballUE/Source/FootballUE/Sim/MatchSimulation.h"
#include <cstdio>
using namespace FB;
int main(int argc,char** argv){ int from=1,to=24000,stride=1200; for(int i=1;i+1<argc;i++){ std::string a=argv[i]; if(a=="--from")from=atoi(argv[i+1]); if(a=="--to")to=atoi(argv[i+1]); if(a=="--stride")stride=atoi(argv[i+1]); }
    MatchConfig cfg; cfg.home=TeamSetup::Generated("Home","HOM",75,Formation::F433,11,{1,0,0},{1,1,1},0);
    cfg.away=TeamSetup::Generated("Away","AWY",70,Formation::F442,22,{0,0,1},{1,1,1},100);
    cfg.humanTeams[0]=false; cfg.humanTeams[1]=false; cfg.seed=5; cfg.matchLengthSeconds=360;
    MatchSimulation sim(cfg); std::array<PlayerInput,2> in{};
    for(int s=1;s<=to;++s){ sim.Step(in);
        if(s>=from && s%stride==0) printf("snap %d score %d-%d clock %.2f ball %.6f %.6f %.6f p0 %.6f %.6f p15 %.6f %.6f shots %d %d passes %d %d\n",s,sim.score.home,sim.score.away,sim.clock.gameSeconds,sim.ball.position.x,sim.ball.position.y,sim.ball.position.z,sim.players[0].pos.x,sim.players[0].pos.y,sim.players[15].pos.x,sim.players[15].pos.y,sim.stats[0].shots,sim.stats[1].shots,sim.stats[0].passes,sim.stats[1].passes); }
}
