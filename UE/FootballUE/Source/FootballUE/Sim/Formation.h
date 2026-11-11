#pragma once
// C++ port of FootballGame/Formation.swift
#include "Foundation.h"
namespace FB {
struct FormationSlot { Role role; float depth, lateral; };
enum class Formation { F433, F442, F4231, F352, F532, F4141 };
inline const char* FormationName(Formation f) { static const char* n[]={"4-3-3","4-4-2","4-2-3-1","3-5-2","5-3-2","4-1-4-1"}; return n[(int)f]; }
inline std::vector<FormationSlot> Slots(Formation f) {
    using R = Role; auto s=[](R r,float d,float l){return FormationSlot{r,d,l};};
    FormationSlot gk=s(R::GK,0.03f,0);
    std::vector<FormationSlot> back4={s(R::LB,0.22f,-0.8f),s(R::CB,0.19f,-0.28f),s(R::CB,0.19f,0.28f),s(R::RB,0.22f,0.8f)};
    std::vector<FormationSlot> out{gk}; auto add=[&](std::vector<FormationSlot> v){out.insert(out.end(),v.begin(),v.end());};
    switch (f) {
    case Formation::F433: add(back4); add({s(R::CM,0.42f,-0.4f),s(R::DM,0.37f,0),s(R::CM,0.42f,0.4f),s(R::LW,0.68f,-0.72f),s(R::ST,0.75f,0),s(R::RW,0.68f,0.72f)}); break;
    case Formation::F442: add(back4); add({s(R::LM,0.46f,-0.8f),s(R::CM,0.41f,-0.25f),s(R::CM,0.41f,0.25f),s(R::RM,0.46f,0.8f),s(R::ST,0.72f,-0.2f),s(R::ST,0.72f,0.2f)}); break;
    case Formation::F4231: add(back4); add({s(R::DM,0.36f,-0.25f),s(R::DM,0.36f,0.25f),s(R::LM,0.56f,-0.7f),s(R::AM,0.59f,0),s(R::RM,0.56f,0.7f),s(R::ST,0.75f,0)}); break;
    case Formation::F352: add({s(R::CB,0.2f,-0.42f),s(R::CB,0.17f,0),s(R::CB,0.2f,0.42f),s(R::LM,0.44f,-0.85f),s(R::CM,0.4f,-0.3f),s(R::DM,0.33f,0),s(R::CM,0.4f,0.3f),s(R::RM,0.44f,0.85f),s(R::ST,0.72f,-0.2f),s(R::ST,0.72f,0.2f)}); break;
    case Formation::F532: add({s(R::LB,0.26f,-0.85f),s(R::CB,0.2f,-0.42f),s(R::CB,0.17f,0),s(R::CB,0.2f,0.42f),s(R::RB,0.26f,0.85f),s(R::CM,0.43f,-0.35f),s(R::CM,0.4f,0),s(R::CM,0.43f,0.35f),s(R::ST,0.72f,-0.2f),s(R::ST,0.72f,0.2f)}); break;
    case Formation::F4141: add(back4); add({s(R::DM,0.33f,0),s(R::LM,0.5f,-0.8f),s(R::CM,0.47f,-0.25f),s(R::CM,0.47f,0.25f),s(R::RM,0.5f,0.8f),s(R::ST,0.74f,0)}); break;
    }
    return out;
}
inline float OutfieldMeanDepth(Formation f) { auto s=Slots(f); float t=0; for (size_t i=1;i<s.size();++i) t+=s[i].depth; return t/float(s.size()-1); }

namespace TacticalPriors {
constexpr float CentroidSlope=0.64f, CentroidInterceptInPossession=2.4f, CentroidInterceptOutOfPossession=-9.1f;
constexpr float LengthKeepInPossession=0.56f, LengthKeepOutOfPossession=0.45f, WidthKeepInPossession=0.62f, WidthKeepOutOfPossession=0.52f;
constexpr float XgIntercept=-1.2393f, XgDistance=-0.10017f, XgAngle=1.71337f, XgHeader=-0.98381f;
inline float XG(float dx, float dy, bool header=false) {
    float dist=std::sqrt(dx*dx+dy*dy);
    float a=std::atan2(7.32f*dx, dx*dx+dy*dy-3.66f*3.66f);
    if (a<0) a+=3.14159265358979323846f;
    float z=XgIntercept+XgDistance*dist+XgAngle*a+(header?XgHeader:0);
    return 1/(1+std::exp(-z));
}
}
struct TeamTactics { float pressing=0.5f, defensiveLine=0.5f, width=0.5f, directness=0.5f; };
struct ColorRGB { float r=0,g=0,b=0; };
struct Appearance { int skinTone=3, hairStyle=0, hairColor=0; float height=1.8f, build=0.5f; };
struct PlayerProfile { int id=0; std::string name; int number=0; Role role=Role::CM; PlayerAttributes attributes; Appearance appearance; };
struct TeamSetup {
    std::string name, shortName; Formation formation=Formation::F433; TeamTactics tactics; ColorRGB primary, secondary; std::vector<PlayerProfile> players;
    static TeamSetup Generated(const std::string& name, const std::string& sh, int quality, Formation formation, uint64_t seed, ColorRGB primary, ColorRGB secondary, int idBase=0) {
        SplitMix64 rng(seed); TeamSetup t; t.name=name; t.shortName=sh; t.formation=formation; t.primary=primary; t.secondary=secondary;
        static const char* surnames[]={"Alder","Brook","Castell","Dorn","Ebner","Fairn","Gaunt","Holt","Ivers","Jory","Kestrel","Lund","Marsh","Nyland","Orsay","Pryce","Quill","Rowan","Sable","Thorne"};
        auto make=[&](int i, Role role){
            Appearance ap; ap.skinTone=rng.Int(6); ap.hairStyle=rng.Int(6); ap.hairColor=rng.Int(5);
            ap.height = role==Role::GK ? rng.Range(1.85f,1.98f) : rng.Range(1.70f,1.92f); ap.build=rng.Float();
            // Swift argument order: name (letter, surname), then attributes.
            char letter=char(65+rng.Int(26)); int si=rng.Int(20);
            PlayerProfile p; p.id=idBase+i; p.name=std::string(1,letter)+". "+surnames[si]; p.number= i==0?1:i+1; p.role=role;
            p.attributes=PlayerAttributes::Generated(role,quality,rng); p.appearance=ap; return p; };
        auto sl=Slots(formation);
        for (size_t i=0;i<sl.size();++i) t.players.push_back(make(int(i),sl[i].role));
        Role subs[]={Role::GK,Role::CB,Role::CM,Role::LW,Role::ST};
        for (int j=0;j<5;++j) t.players.push_back(make(11+j,subs[j]));
        return t;
    }
};
struct Difficulty { int level=3; float Skill() const { static const float s[]={0.35f,0.5f,0.65f,0.82f,1.0f}; return s[level]; } };
}
