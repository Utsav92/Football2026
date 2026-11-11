#include "../FootballUE/Source/FootballUE/Sim/Formation.h"
#include <cstdio>
using namespace FB;
static const char* RN[]={"gk","cb","lb","rb","dm","cm","am","lm","rm","lw","rw","st"};
int main(){
    Formation fs[]={Formation::F433,Formation::F442,Formation::F4231,Formation::F352,Formation::F532,Formation::F4141};
    for(auto f:fs){ printf("formation %s %.5f ",FormationName(f),OutfieldMeanDepth(f)); auto s=Slots(f);
        for(size_t i=0;i<s.size();++i) printf("%s%s:%g:%g",i?",":"",RN[(int)s[i].role],s[i].depth,s[i].lateral); printf("\n"); }
    struct X{float dx,dy;bool h;}; X xs[]={{11,0,false},{16,8,false},{6,2,true},{30,-10,false},{3,0.5f,false},{20,20,true}};
    for(auto& x:xs) printf("xg %.5f\n",TacticalPriors::XG(x.dx,x.dy,x.h));
    for(int k=0;k<6;k++){ auto t=TeamSetup::Generated("T","T",65+k*3,fs[k],7+k,{1,0,0},{0,0,1},k*100);
        for(auto& p:t.players) printf("player %d %s %d %s %d %d %d %d %d %d %.5f %.5f\n",p.id,p.name.c_str(),p.number,RN[(int)p.role],p.attributes.Overall(),p.attributes.sprintSpeed,p.attributes.goalkeeping,p.appearance.skinTone,p.appearance.hairStyle,p.appearance.hairColor,p.appearance.height,p.appearance.build); }
    printf("difficulty"); for(int i=0;i<5;i++) printf("%s%.2f",i?",":" ",Difficulty{i}.Skill()); printf("\n");
}
