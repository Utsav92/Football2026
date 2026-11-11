#pragma once
// Dependency-free math for the Football2026 simulation core (mirrors Swift simd semantics).
#include <cmath>
#include <algorithm>
namespace FB {
struct Vec2 {
    float x=0,y=0;
    Vec2() = default; Vec2(float X,float Y):x(X),y(Y){}
    Vec2 operator+(Vec2 o) const {return {x+o.x,y+o.y};}
    Vec2 operator-(Vec2 o) const {return {x-o.x,y-o.y};}
    Vec2 operator-() const {return {-x,-y};}
    Vec2 operator*(float s) const {return {x*s,y*s};}
    Vec2 operator/(float s) const {return {x/s,y/s};}
    Vec2& operator+=(Vec2 o){x+=o.x;y+=o.y;return *this;}
    Vec2& operator-=(Vec2 o){x-=o.x;y-=o.y;return *this;}
    Vec2& operator*=(float s){x*=s;y*=s;return *this;}
    Vec2& operator/=(float s){x/=s;y/=s;return *this;}
};
inline float Dot(Vec2 a, Vec2 b){return a.x*b.x+a.y*b.y;}
inline float Length(Vec2 a){return std::sqrt(Dot(a,a));}
inline float Distance(Vec2 a, Vec2 b){return Length(a-b);}
struct Vec3 {
    float x=0,y=0,z=0;
    Vec3() = default; Vec3(float X,float Y,float Z):x(X),y(Y),z(Z){}
    Vec3 operator+(Vec3 o) const {return {x+o.x,y+o.y,z+o.z};}
    Vec3 operator-(Vec3 o) const {return {x-o.x,y-o.y,z-o.z};}
    Vec3 operator*(float s) const {return {x*s,y*s,z*s};}
    Vec3 operator/(float s) const {return {x/s,y/s,z/s};}
    Vec3& operator+=(Vec3 o){x+=o.x;y+=o.y;z+=o.z;return *this;}
    Vec3& operator-=(Vec3 o){x-=o.x;y-=o.y;z-=o.z;return *this;}
    Vec3& operator*=(float s){x*=s;y*=s;z*=s;return *this;}
};
inline float Dot(Vec3 a, Vec3 b){return a.x*b.x+a.y*b.y+a.z*b.z;}
inline Vec3 Cross(Vec3 a, Vec3 b){return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x};}
inline float Length(Vec3 a){return std::sqrt(Dot(a,a));}
inline Vec3 Clamp(Vec3 p, Vec3 lo, Vec3 hi){return {std::clamp(p.x,lo.x,hi.x),std::clamp(p.y,lo.y,hi.y),std::clamp(p.z,lo.z,hi.z)};}
struct Quat { float x=0,y=0,z=0,w=1; };
inline Quat Mul(Quat a, Quat b){return {a.w*b.x+a.x*b.w+a.y*b.z-a.z*b.y, a.w*b.y-a.x*b.z+a.y*b.w+a.z*b.x, a.w*b.z+a.x*b.y-a.y*b.x+a.z*b.w, a.w*b.w-a.x*b.x-a.y*b.y-a.z*b.z};}
inline Quat FromAxisAngle(Vec3 axis, float angle){float s=std::sin(angle*0.5f);return {axis.x*s,axis.y*s,axis.z*s,std::cos(angle*0.5f)};}
inline Quat Normalize(Quat q){float l=std::sqrt(q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w);return {q.x/l,q.y/l,q.z/l,q.w/l};}
}
