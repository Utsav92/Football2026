#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Sim/MatchSimulation.h"
#include "TrackingReplay.h"
#include "FootballAnim.h"
#include "FootballCommentary.h"
#include "FootballMatchActor.generated.h"

class UStaticMeshComponent;
class UCameraComponent;
class UMaterialInstanceDynamic;
class AFootballStadium;
class USkeletalMeshComponent;
class USkeletalMesh;
class UAnimSequence;

/** Owns the C++ match simulation (ported from the Swift engine) and renders it with Unreal components. */
UCLASS()
class AFootballMatchActor : public AActor
{
    GENERATED_BODY()
public:
    AFootballMatchActor();
    virtual void BeginPlay() override;
    virtual void Tick(float DeltaSeconds) override;

    UPROPERTY(EditAnywhere) int32 Seed = 7;
    UPROPERTY(EditAnywhere) bool bHumanHome = true;
    UPROPERTY(EditAnywhere) float MatchLengthSeconds = 360.f;
    /** For automated screenshots: skip the clock ahead this many simulated seconds before the first frame. */
    UPROPERTY(EditAnywhere) float WarmupSeconds = 0.f;

    // HUD / menu API
    const FB::MatchSimulation* GetSim() const { return Sim.Get(); }
    bool IsPaused() const { return bPaused; }
    int32 HumanSide() const { return HumanSideIdx; }          // 0 home, 1 away, -1 none (AI vs AI)
    int32 PassTarget() const;                                  // player the pass button would find right now, or -1
    const FFootballCommentary& Commentary() const { return Comm; }
    TArray<FString> MenuLabels() const; int32 MenuSelection() const { return MenuSel; }

private:
    // ---- Trailer capture director (-trailer=<dir> with -benchmark -fps=30 -ai) ----
    struct FTEvt { float T; int32 Kind, A, B; float F; };
    struct FTShot { float Start, Dur, SimAt, Slow; int32 Mode, Target; bool Hud, Pause; FName Name; };
    bool bTrailer = false; FString TrailerDir; int32 TFrame = 0, TShotIdx = -1, TCapture = 0; TArray<FTEvt> TEvents; TArray<FTShot> TShots; float TTotal = 0.f;
    void BuildTrailer(const FB::MatchConfig& Cfg); void TrailerBegin(); void TrailerShotStart(const FTShot& S);
    bool TrailerCamera(FVector& Want, FVector& Look, float& Fov, float& Fstop);
    FFootballCommentary Comm;
public: virtual void EndPlay(const EEndPlayReason::Type R) override { Comm.Shutdown(); Super::EndPlay(R); }
private:
    bool bPaused = false; int32 MenuSel = 0; int32 HumanSideIdx = 0;
    void TickMenu(); void MenuActivate(int32 Dir); void SetHumanSide(int32 Side);
    TUniquePtr<FB::MatchSimulation> Sim;
    FB::FixedStepper Stepper;
    UPROPERTY() TObjectPtr<UCameraComponent> Camera;
    UPROPERTY() TObjectPtr<UStaticMeshComponent> BallMesh;
    UPROPERTY() TArray<TObjectPtr<USkeletalMeshComponent>> Athletes;   // 22 simulated players
    UPROPERTY() TObjectPtr<USkeletalMesh> AthleteMesh; UPROPERTY() TObjectPtr<UMaterialInterface> KitMat; UPROPERTY() TArray<TObjectPtr<UAnimSequence>> AthleteClips; UPROPERTY() TArray<TObjectPtr<UAnimSequence>> MocapKicks; float MeshYaw = -90.f; float RbxYaw = -90.f;
    USkeletalMeshComponent* MakeAthlete(const FLinearColor& Shirt, const FLinearColor& Shorts, const FLinearColor& Socks, int32 SkinIdx, int32 HairIdx, float Height = 1.84f, float Build = 0.5f, int32 Number = 0);
    UPROPERTY() TArray<TObjectPtr<class UCapsuleComponent>> Capsules; void VerifyCollision(); void VerifyFacing();
    static void DriveAnim(USkeletalMeshComponent* C, EFootballAnim S, float Rate);
    bool bLocoMocap = false; bool bRocketbox = false; UPROPERTY() TArray<TObjectPtr<USkeletalMesh>> RbxMeshes; void Locomotion(float Spd, bool Gk, EFootballAnim& St, float& Rate) const;
    UPROPERTY() TObjectPtr<UStaticMesh> Cube; UPROPERTY() TObjectPtr<UStaticMesh> Sphere; UPROPERTY() TObjectPtr<UStaticMesh> Cylinder; UPROPERTY() TObjectPtr<UStaticMesh> Plane;
    UPROPERTY() TObjectPtr<UMaterialInterface> BaseMat;
    UPROPERTY() TObjectPtr<AFootballStadium> Stadium;
    // Tracking-data replay (local research data only).
    bool bReplay = false; FTrackingReplay Replay; float ReplayFrame = 0.f, ReplaySpeed = 1.f; bool bReplayPaused = false, bOverlay = true; TSet<FKey> KeysDown;
    UPROPERTY() TArray<TObjectPtr<USkeletalMeshComponent>> RAthletes;   // 28 replay slots
    void SetupReplay(); void ReplayTick(float Dt); bool KeyPressed(const FKey& K);
    int32 CamMode = 0; int32 PrevMode = 0; static constexpr float HalfWidthM() { return FB::Pitch::HalfWidth; } bool bPrevC = false; UPROPERTY(EditAnywhere) int32 StartCam = 0;
    FVector SmoothedCam = FVector::ZeroVector; FVector SmoothedLook = FVector::ZeroVector; bool bCamInit = false;

    UStaticMeshComponent* MakeMesh(UStaticMesh* Mesh, const FVector& Loc, const FVector& Scale, const FLinearColor& Color, const FRotator& Rot = FRotator::ZeroRotator);
    void BuildPitch();
    void AddLine(float x0, float z0, float x1, float z1, float w = 0.12f);
    void BuildLighting();
    std::array<FB::PlayerInput,2> ReadInput() const;
    static FVector ToUE(float x, float y, float z) { return FVector(x * 100.f, z * 100.f, y * 100.f); }
};
