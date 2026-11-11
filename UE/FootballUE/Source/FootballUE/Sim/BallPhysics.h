#pragma once
// C++ port of Packages/FootballKit/Sources/FootballPhysics (PitchSpec, BallPhysics, Collision).
#include "FBMath.h"
#include <vector>
namespace FB {
namespace Pitch {
constexpr float Length=105, Width=68, HalfLength=Length/2, HalfWidth=Width/2;
constexpr float GoalWidth=7.32f, GoalHeight=2.44f, GoalDepth=2.0f, PostRadius=0.06f;
constexpr float BallRadius=0.11f, BallMass=0.43f, Gravity=9.81f;
constexpr float PenaltyAreaDepth=16.5f, PenaltyAreaWidth=40.32f, GoalAreaDepth=5.5f, GoalAreaWidth=18.32f, PenaltySpotDistance=11.f;
inline constexpr float CentreCircleRadius(){return 9.15f;}
}
struct BallState {
    Vec3 position{0,Pitch::BallRadius,0}, velocity, angularVelocity, curveSpin;
    Quat orientation;
};
struct BallEvent { enum Kind {Bounce,Woodwork,Net} kind; float impactSpeed; };
struct BallPhysicsConfig {
    float gravity=Pitch::Gravity, airDragK=0.0133f, magnusK=0.004f, groundRestitution=0.62f, bounceFriction=0.9f, rollingDecel=1.15f,
          woodworkRestitution=0.6f, woodworkFriction=0.9f, netRestitution=0.0f, netFriction=0.4f, restSpeed=0.7f;
    int substeps=4;
};
struct Capsule { Vec3 a,b; float radius; };
struct Box { Vec3 mn,mx; Box(Vec3 c,Vec3 h):mn(c-h),mx(c+h){} };
struct GoalGeometry {
    std::vector<Capsule> frames; std::vector<Box> nets;
    GoalGeometry() {
        using namespace Pitch;
        float hw=GoalWidth/2,h=GoalHeight,r=PostRadius;
        for (float s : {-1.f,1.f}) {
            float x=s*HalfLength;
            frames.push_back({Vec3(x,0,-hw),Vec3(x,h,-hw),r});
            frames.push_back({Vec3(x,0,hw),Vec3(x,h,hw),r});
            frames.push_back({Vec3(x,h,-hw),Vec3(x,h,hw),r});
        }
        float d=GoalDepth,t=0.05f;
        for (float s : {-1.f,1.f}) {
            float xl=s*HalfLength, xb=s*(HalfLength+d), gap=0.15f, xm=(xl+s*gap+xb)/2, hl=(d-gap)/2;
            nets.emplace_back(Vec3(xb+s*t,h/2,0),Vec3(t,h/2,hw+2*t));
            nets.emplace_back(Vec3(xm,h/2,-(hw+t)),Vec3(hl,h/2,t));
            nets.emplace_back(Vec3(xm,h/2,hw+t),Vec3(hl,h/2,t));
            nets.emplace_back(Vec3(xm,h+t,0),Vec3(hl,t,hw+2*t));
        }
    }
};
inline float CollideCapsule(Vec3& p, Vec3& v, float r, const Capsule& c, float e, float f) {
    Vec3 ab=c.b-c.a;
    float t=std::clamp(Dot(p-c.a,ab)/Dot(ab,ab),0.f,1.f);
    Vec3 q=c.a+ab*t, d=p-q; float dist=Length(d), minDist=r+c.radius;
    if (!(dist<minDist && dist>1e-6f)) return 0;
    Vec3 n=d/dist; p=q+n*minDist;
    float vn=Dot(v,n); if (!(vn<0)) return 0;
    v=(v-n*vn)*f-n*(vn*e); return -vn;
}
inline float CollideBox(Vec3& p, Vec3& v, float r, const Box& b, float e, float f) {
    Vec3 c=Clamp(p,b.mn,b.mx), d=p-c; float dist=Length(d);
    if (!(dist<r)) return 0;
    Vec3 n;
    if (dist>1e-6f) { n=d/dist; p=c+n*r; }
    else {
        Vec3 lo=p-b.mn, hi=b.mx-p; float best=lo.x; n=Vec3(-1,0,0);
        if (hi.x<best){best=hi.x;n=Vec3(1,0,0);} if (lo.y<best){best=lo.y;n=Vec3(0,-1,0);}
        if (hi.y<best){best=hi.y;n=Vec3(0,1,0);} if (lo.z<best){best=lo.z;n=Vec3(0,0,-1);}
        if (hi.z<best){best=hi.z;n=Vec3(0,0,1);}
        p+=n*(best+r);
    }
    float vn=Dot(v,n); if (!(vn<0)) return 0;
    v=(v-n*vn)*f-n*(vn*e); return -vn;
}
class BallPhysics {
public:
    BallPhysicsConfig Config; GoalGeometry Goals;
    void Step(BallState& b, float dt, std::vector<BallEvent>* events=nullptr) const {
        float h=dt/float(Config.substeps);
        for (int i=0;i<Config.substeps;++i) Substep(b,h,events);
    }
private:
    void Substep(BallState& b, float h, std::vector<BallEvent>* ev) const {
        const float r=Pitch::BallRadius; Vec3 p=b.position, v=b.velocity;
        Vec3 a(0,-Config.gravity,0); float speed=Length(v);
        if (speed>1e-4f) a-=v*(speed*Config.airDragK);
        if (Config.magnusK!=0 && !(p.y<=r+0.002f)) a+=Cross(b.curveSpin,v)*Config.magnusK;
        v+=a*h; p+=v*h;
        if (p.y<r) {
            p.y=r;
            if (v.y<0) { float impact=-v.y;
                if (impact>Config.restSpeed) { v.y=impact*Config.groundRestitution; v.x*=Config.bounceFriction; v.z*=Config.bounceFriction;
                    if (ev) ev->push_back({BallEvent::Bounce,impact}); }
                else v.y=0; }
        }
        bool rolling = p.y<=r+0.002f && std::fabs(v.y)<0.05f;
        if (rolling) { float s=std::sqrt(v.x*v.x+v.z*v.z);
            if (s>0) { float ns=std::max(0.f,s-Config.rollingDecel*h), k=ns/s; v.x*=k; v.z*=k; if (ns<0.03f){v.x=0;v.z=0;} } }
        for (auto& c:Goals.frames) { float imp=CollideCapsule(p,v,r,c,Config.woodworkRestitution,Config.woodworkFriction); if (imp>1 && ev) ev->push_back({BallEvent::Woodwork,imp}); }
        for (auto& bx:Goals.nets)  { float imp=CollideBox(p,v,r,bx,Config.netRestitution,Config.netFriction); if (imp>1 && ev) ev->push_back({BallEvent::Net,imp}); }
        b.curveSpin*=std::max(0.f,1-(rolling?8.f:0.4f)*h);
        if (rolling) b.angularVelocity=Cross(Vec3(0,1,0),v)/r; else b.angularVelocity*=std::max(0.f,1-0.15f*h);
        float w=Length(b.angularVelocity);
        if (w>1e-4f) b.orientation=Normalize(Mul(FromAxisAngle(b.angularVelocity/w,w*h),b.orientation));
        b.position=p; b.velocity=v;
    }
};
inline int GoalSide(const BallState& b) {
    using namespace Pitch; const Vec3& p=b.position;
    if (!(std::fabs(p.z)<GoalWidth/2 && p.y<GoalHeight)) return 0;
    if (p.x>HalfLength+BallRadius) return 1; if (p.x<-HalfLength-BallRadius) return -1; return 0;
}
inline bool IsOutOfPlay(const BallState& b) {
    using namespace Pitch; if (GoalSide(b)!=0) return false;
    return std::fabs(b.position.z)>HalfWidth+BallRadius || std::fabs(b.position.x)>HalfLength+BallRadius;
}
}
