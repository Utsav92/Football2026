#include "FootballAnim.h"
#include "Animation/AnimSequence.h"
#include "Animation/AnimNodeBase.h"
#include "AnimationRuntime.h"
#include "Animation/AnimationPoseData.h"

const TCHAR* UFootballAnimInstance::ClipName(EFootballAnim S)
{
    static const TCHAR* N[] = { TEXT("idle"), TEXT("walk"), TEXT("jog"), TEXT("sprint"), TEXT("kick"), TEXT("tackle"), TEXT("slide"), TEXT("fall"), TEXT("getup"), TEXT("celebrate"), TEXT("jump_header"), TEXT("gk_ready"), TEXT("gk_dive_left"), TEXT("gk_dive_right"), TEXT("gk_catch"), TEXT("gk_punch") };
    return N[(int)S];
}
bool UFootballAnimInstance::IsLooping(EFootballAnim S)
{
    return S == EFootballAnim::Idle || S == EFootballAnim::Walk || S == EFootballAnim::Jog || S == EFootballAnim::Sprint || S == EFootballAnim::Celebrate || S == EFootballAnim::GKReady;
}
FAnimInstanceProxy* UFootballAnimInstance::CreateAnimInstanceProxy() { return new FFootballAnimProxy(this); }

void FFootballAnimProxy::Initialize(UAnimInstance* I)
{
    FAnimInstanceProxy::Initialize(I);
    Clips.Reset(); if (UFootballAnimInstance* A = Cast<UFootballAnimInstance>(I)) { for (UAnimSequence* S : A->Clips) Clips.Add(S); Phase = A->PhaseOffset; }
    Cur = 0; Prev = -1; CurT = Phase; Blend = 1.f;
}

void FFootballAnimProxy::PreUpdate(UAnimInstance* I, float Dt)
{
    FAnimInstanceProxy::PreUpdate(I, Dt);
    if (const UFootballAnimInstance* A = Cast<UFootballAnimInstance>(I)) { KickStart = A->KickStartOffset; if (Clips.Num() == 0 && A->Clips.Num() > 0) { for (UAnimSequence* S : A->Clips) Clips.Add(S); Phase = A->PhaseOffset; CurT = Phase; } Requested = (int32)A->RequestedState; ReqRate = A->PlayRate; }
}

void FFootballAnimProxy::UpdateAnimationNode(const FAnimationUpdateContext& Ctx)
{
    const float Dt = Ctx.GetDeltaTime();
    if (Requested != Cur && Clips.IsValidIndex(Requested) && Clips[Requested])
    {
        const bool Action = !UFootballAnimInstance::IsLooping((EFootballAnim)Requested);
        Prev = Cur; PrevT = CurT; Cur = Requested; CurT = Action ? (Cur == (int32)EFootballAnim::Kick ? KickStart : 0.f) : FMath::Fmod(Phase + PrevT, FMath::Max(0.1f, Clips[Cur]->GetPlayLength()));   // locomotion keeps its phase
        Blend = 0.f; BlendDur = Action ? 0.10f : 0.20f;
    }
    Rate = ReqRate;
    const EFootballAnim S = (EFootballAnim)Cur;
    if (Clips.IsValidIndex(Cur) && Clips[Cur])
    {
        const float Len = Clips[Cur]->GetPlayLength(); CurT += Dt * Rate;
        if (UFootballAnimInstance::IsLooping(S)) CurT = FMath::Fmod(CurT, Len); else CurT = FMath::Min(CurT, Len - 0.001f);   // one-shots hold the last frame
    }
    if (Prev >= 0 && Clips.IsValidIndex(Prev) && Clips[Prev]) { PrevT = FMath::Fmod(PrevT + Dt * Rate, FMath::Max(0.1f, Clips[Prev]->GetPlayLength())); }
    if (Blend < 1.f) { Blend = FMath::Min(1.f, Blend + Dt / FMath::Max(0.01f, BlendDur)); if (Blend >= 1.f) Prev = -1; }
}

void FFootballAnimProxy::EvalClip(int32 Idx, float T, FPoseContext& Out) const
{
    if (!Clips.IsValidIndex(Idx) || !Clips[Idx]) { Out.ResetToRefPose(); return; }
    FAnimationPoseData Data(Out);
    FAnimExtractContext Ctx((double)T, false, FDeltaTimeRecord(), UFootballAnimInstance::IsLooping((EFootballAnim)Idx));
    Clips[Idx]->GetAnimationPose(Data, Ctx);
}

bool FFootballAnimProxy::Evaluate(FPoseContext& Out)
{
    if (Prev < 0 || Blend >= 1.f) { EvalClip(Cur, CurT, Out); return true; }
    FPoseContext A(this), B(this);
    EvalClip(Prev, PrevT, A); EvalClip(Cur, CurT, B);
    FAnimationPoseData PA(A), PB(B), PO(Out);
    FAnimationRuntime::BlendTwoPosesTogether(PA, PB, Blend, PO);
    return true;
}
