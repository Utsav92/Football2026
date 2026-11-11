#include "../FootballUE/Source/FootballUE/Sim/BallPhysics.h"
#include <cstdio>
#include <string>
using namespace FB;
int main(){
    struct S{const char* n; Vec3 p,v,s;};
    S sc[]={{"lob_curve",{-20,0.11f,5},{18,9,-3},{0,40,0}},{"ground_pass",{0,0.11f,0},{14,0,4},{}},
            {"shot_crossbar",{35,0.11f,0.5f},{30,7.5f,0.3f},{}},{"shot_net",{40,0.11f,1.0f},{28,3.0f,0.4f},{0,-15,0}},
            {"post_hit",{40,0.11f,-3.0f},{24,1.0f,0.8f},{}}};
    BallPhysics phys;
    for(auto& s:sc){ BallState b; b.position=s.p; b.velocity=s.v; b.curveSpin=s.s;
        for(int i=0;i<720;++i){ phys.Step(b,1.0f/120);
            if(i%30==29) printf("%s %d %.4f %.4f %.4f %.4f %.4f %.4f\n",s.n,i+1,b.position.x,b.position.y,b.position.z,b.velocity.x,b.velocity.y,b.velocity.z);} }
}
