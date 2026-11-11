#pragma once
#include "CoreMinimal.h"
#include "Animation/AnimInstance.h"
#include "Animation/AnimInstanceProxy.h"
#include "FootballAnim.generated.h"

class UAnimSequence;

UENUM()
enum class EFootballAnim : uint8
{
    Idle, Walk, Jog, Sprint, Kick, Tackle, Slide, Fall, GetUp, Celebrate, Header, GKReady, GKDiveLeft, GKDiveRight, GKCatch, GKPunch, Count
};

/** Code-driven animation state machine with cross-fades (no Animation Blueprint graph asset needed).
 *  The game sets RequestedState / PlayRate each tick; the proxy blends the clips on the animation worker thread. */
UCLASS()
class UFootballAnimInstance : public UAnimInstance
{
    GENERATED_BODY()
public:
    UPROPERTY() TArray<TObjectPtr<UAnimSequence>> Clips;   // indexed by EFootballAnim
    EFootballAnim RequestedState = EFootballAnim::Idle; float PlayRate = 1.f; float PhaseOffset = 0.f; float KickStartOffset = 0.f;   // seconds into the Kick clip to start at (mocap strike happens ~0.55 s in)
    void Request(EFootballAnim S, float Rate) { RequestedState = S; PlayRate = Rate; }
    static const TCHAR* ClipName(EFootballAnim S);
    static bool IsLooping(EFootballAnim S);
protected:
    virtual FAnimInstanceProxy* CreateAnimInstanceProxy() override;
};

struct FFootballAnimProxy : public FAnimInstanceProxy
{
    FFootballAnimProxy(UAnimInstance* I) : FAnimInstanceProxy(I) {}
    TArray<UAnimSequence*> Clips; int32 Cur = 0, Prev = -1; float CurT = 0.f, PrevT = 0.f, Blend = 1.f, BlendDur = 0.18f, Rate = 1.f, Phase = 0.f; int32 Requested = 0; float ReqRate = 1.f; float KickStart = 0.f;
    virtual void Initialize(UAnimInstance* I) override;
    virtual void PreUpdate(UAnimInstance* I, float Dt) override;
    virtual void UpdateAnimationNode(const FAnimationUpdateContext& Ctx) override;
    virtual bool Evaluate(FPoseContext& Out) override;
private:
    void EvalClip(int32 Idx, float T, FPoseContext& Out) const;
};
