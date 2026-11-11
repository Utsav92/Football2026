#include "FootballMatchActor.h"
#include "Components/StaticMeshComponent.h"
#include "Camera/CameraComponent.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Engine/StaticMesh.h"
#include "Engine/DirectionalLight.h"
#include "Engine/SkyLight.h"
#include "Components/DirectionalLightComponent.h"
#include "Components/SkyLightComponent.h"
#include "Kismet/GameplayStatics.h"
#include "GameFramework/PlayerController.h"
#include "UObject/ConstructorHelpers.h"
#include "Engine/World.h"
#include "Kismet/KismetSystemLibrary.h"
#include "Engine/PostProcessVolume.h"
#include "FootballStadium.h"
#include "DrawDebugHelpers.h"
#include "Engine/Engine.h"
#include "Misc/Paths.h"
#include "Components/SkeletalMeshComponent.h"
#include "Components/CapsuleComponent.h"
#include "Components/TextRenderComponent.h"
#include "InputCoreTypes.h"
#include "Engine/SkeletalMesh.h"
#include "Animation/AnimSequence.h"
#include "UnrealClient.h"
#include "GameFramework/HUD.h"

static int32 GSavedSide = -1;

AFootballMatchActor::AFootballMatchActor()
{
    PrimaryActorTick.bCanEverTick = true;
    RootComponent = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
    Camera = CreateDefaultSubobject<UCameraComponent>(TEXT("BroadcastCamera"));
    Camera->SetupAttachment(RootComponent);
    Camera->FieldOfView = 38.f;
    static ConstructorHelpers::FObjectFinder<UStaticMesh> CubeF(TEXT("/Engine/BasicShapes/Cube.Cube"));
    static ConstructorHelpers::FObjectFinder<UStaticMesh> SphereF(TEXT("/Engine/BasicShapes/Sphere.Sphere"));
    static ConstructorHelpers::FObjectFinder<UStaticMesh> CylF(TEXT("/Engine/BasicShapes/Cylinder.Cylinder"));
    static ConstructorHelpers::FObjectFinder<UStaticMesh> PlaneF(TEXT("/Engine/BasicShapes/Plane.Plane"));
    static ConstructorHelpers::FObjectFinder<UMaterialInterface> MatF(TEXT("/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));
    Cube = CubeF.Object; Sphere = SphereF.Object; Cylinder = CylF.Object; Plane = PlaneF.Object; BaseMat = MatF.Object;
}

UStaticMeshComponent* AFootballMatchActor::MakeMesh(UStaticMesh* Mesh, const FVector& Loc, const FVector& Scale, const FLinearColor& Color, const FRotator& Rot)
{
    UStaticMeshComponent* C = NewObject<UStaticMeshComponent>(this);
    C->SetStaticMesh(Mesh); C->SetupAttachment(RootComponent); C->RegisterComponent();
    C->SetWorldLocationAndRotation(Loc, Rot); C->SetWorldScale3D(Scale);
    C->SetCollisionEnabled(ECollisionEnabled::NoCollision); C->CastShadow = true;
    UMaterialInstanceDynamic* M = UMaterialInstanceDynamic::Create(BaseMat, this);
    M->SetVectorParameterValue(TEXT("Color"), Color); C->SetMaterial(0, M);
    return C;
}

void AFootballMatchActor::AddLine(float x0, float z0, float x1, float z1, float w)
{
    const float dx = x1 - x0, dz = z1 - z0, len = FMath::Sqrt(dx*dx + dz*dz);
    const float yaw = FMath::RadiansToDegrees(FMath::Atan2(dz, dx));
    UStaticMeshComponent* L = MakeMesh(Cube, ToUE((x0+x1)/2, 0.012f, (z0+z1)/2), FVector(len, w, 0.02f), FLinearColor::White, FRotator(0, yaw, 0));
    L->CastShadow = false;
}

void AFootballMatchActor::BuildPitch()
{
    using namespace FB::Pitch;
    // Surround + mown stripes, using the procedural turf material (falls back to flat colour if missing).
    UMaterialInterface* Turf = LoadObject<UMaterialInterface>(nullptr, TEXT("/Game/Football/Materials/M_Turf.M_Turf"));
    auto SetTurf = [&](UStaticMeshComponent* C, const FLinearColor& Col) {
        if (!Turf) return;
        UMaterialInstanceDynamic* Mi = UMaterialInstanceDynamic::Create(Turf, this); Mi->SetVectorParameterValue(TEXT("Color"), Col); C->SetMaterial(0, Mi); };
    UStaticMeshComponent* Sur = MakeMesh(Plane, ToUE(0, -0.02f, 0), FVector(180, 130, 1), FLinearColor(0.03f, 0.08f, 0.03f));
    SetTurf(Sur, FLinearColor(0.035f, 0.09f, 0.03f));
    for (int i = 0; i < 14; ++i) {
        const float w = Length / 14.f, cx = -HalfLength + w * (i + 0.5f);
        const FLinearColor C = (i % 2) ? FLinearColor(0.062f, 0.15f, 0.035f) : FLinearColor(0.085f, 0.20f, 0.045f);
        UStaticMeshComponent* S = MakeMesh(Plane, ToUE(cx, 0, 0), FVector(w, Width, 1), C);
        S->CastShadow = false; SetTurf(S, C);
    }
    AddLine(-HalfLength, -HalfWidth, HalfLength, -HalfWidth); AddLine(-HalfLength, HalfWidth, HalfLength, HalfWidth);
    AddLine(-HalfLength, -HalfWidth, -HalfLength, HalfWidth); AddLine(HalfLength, -HalfWidth, HalfLength, HalfWidth);
    AddLine(0, -HalfWidth, 0, HalfWidth);
    for (float s : {-1.f, 1.f}) {
        const float gx = s * HalfLength, pa = s * (HalfLength - PenaltyAreaDepth), ga = s * (HalfLength - GoalAreaDepth);
        AddLine(pa, -PenaltyAreaWidth/2, pa, PenaltyAreaWidth/2); AddLine(pa, -PenaltyAreaWidth/2, gx, -PenaltyAreaWidth/2); AddLine(pa, PenaltyAreaWidth/2, gx, PenaltyAreaWidth/2);
        AddLine(ga, -GoalAreaWidth/2, ga, GoalAreaWidth/2); AddLine(ga, -GoalAreaWidth/2, gx, -GoalAreaWidth/2); AddLine(ga, GoalAreaWidth/2, gx, GoalAreaWidth/2);
        // Goal frame + net backing.
        const float hw = GoalWidth/2;
        for (float z : {-hw, hw}) MakeMesh(Cylinder, ToUE(gx, GoalHeight/2, z), FVector(0.12f, 0.12f, GoalHeight/1.0f), FLinearColor::White);
        MakeMesh(Cylinder, ToUE(gx, GoalHeight, 0), FVector(0.12f, 0.12f, GoalWidth), FLinearColor::White, FRotator(90, 0, 0));
        UStaticMeshComponent* Net = MakeMesh(Cube, ToUE(gx + s * GoalDepth, GoalHeight/2, 0), FVector(0.05f, GoalWidth, GoalHeight), FLinearColor(0.03f, 0.03f, 0.035f)); Net->CastShadow = false;
    }
    const int N = 48; for (int i = 0; i < N; ++i) { // centre circle
        const float a0 = 2*PI*i/N, a1 = 2*PI*(i+1)/N; AddLine(CentreCircleRadius()*FMath::Cos(a0), CentreCircleRadius()*FMath::Sin(a0), CentreCircleRadius()*FMath::Cos(a1), CentreCircleRadius()*FMath::Sin(a1)); }
}

void AFootballMatchActor::BuildLighting()
{
    FString Tod = TEXT("day"); FParse::Value(FCommandLine::Get(), TEXT("-tod="), Tod);
    Stadium = GetWorld()->SpawnActor<AFootballStadium>(FVector::ZeroVector, FRotator::ZeroRotator);
    if (Stadium) Stadium->Build(Tod == TEXT("night") ? EFootballTimeOfDay::Night : (Tod == TEXT("sunset") ? EFootballTimeOfDay::Sunset : EFootballTimeOfDay::Day));
}

void AFootballMatchActor::BeginPlay()
{
    Super::BeginPlay();
    if (FParse::Param(FCommandLine::Get(), TEXT("ai"))) bHumanHome = false;
    { int32 Sd = 0; float Sh = 0.f; if (FParse::Value(FCommandLine::Get(), TEXT("-seed="), Sd)) Seed = Sd; else if (!FParse::Value(FCommandLine::Get(), TEXT("-shot="), Sh)) Seed = int32(FDateTime::Now().GetTicks() % 100000) + 1; }
    bPaused = FParse::Param(FCommandLine::Get(), TEXT("startpaused"));
    { float Sh = 0.f; Comm.SetVoiceAllowed(!FParse::Value(FCommandLine::Get(), TEXT("-shot="), Sh)); if (FParse::Param(FCommandLine::Get(), TEXT("nocomm"))) Comm.Mode_ = FFootballCommentary::Mode::Off; }
    HumanSideIdx = bHumanHome ? (GSavedSide >= 0 ? GSavedSide : 0) : -1; if (HumanSideIdx == 1) bHumanHome = true;
    FParse::Value(FCommandLine::Get(), TEXT("-warmup="), WarmupSeconds);
    FB::MatchConfig Cfg;
    Cfg.home = FB::TeamSetup::Generated("Alderford", "ALD", 76, FB::Formation::F433, Seed * 3, {0.85f, 0.1f, 0.1f}, {1, 1, 1}, 0);
    Cfg.away = FB::TeamSetup::Generated("Oakmere", "OAK", 72, FB::Formation::F442, Seed * 3 + 1, {0.1f, 0.35f, 0.8f}, {1, 1, 1}, 100);
    Cfg.humanTeams[0] = (HumanSideIdx == 0); Cfg.humanTeams[1] = (HumanSideIdx == 1); Cfg.seed = (uint64)Seed; Cfg.matchLengthSeconds = MatchLengthSeconds;
    Sim = MakeUnique<FB::MatchSimulation>(Cfg);
    BuildPitch(); BuildLighting();
    BallMesh = MakeMesh(Sphere, ToUE(0, 0.11f, 0), FVector(0.22f), FLinearColor::White);
    FParse::Value(FCommandLine::Get(), TEXT("-meshyaw="), MeshYaw);
    AthleteMesh = LoadObject<USkeletalMesh>(nullptr, TEXT("/Game/Football/Athlete/athlete.athlete"));
    KitMat = LoadObject<UMaterialInterface>(nullptr, TEXT("/Game/Football/Materials/M_Kit.M_Kit"));
    if (!KitMat) UE_LOG(LogTemp, Error, TEXT("M_Kit missing: run Scripts/make_kit_material.py"));
    for (int k = 0; k < (int)EFootballAnim::Count; ++k) AthleteClips.Add(LoadObject<UAnimSequence>(nullptr, *FString::Printf(TEXT("/Game/Football/Athlete/athleteskeleton_%s.athleteskeleton_%s"), UFootballAnimInstance::ClipName((EFootballAnim)k), UFootballAnimInstance::ClipName((EFootballAnim)k))));
    if (!AthleteMesh) UE_LOG(LogTemp, Error, TEXT("Athlete skeletal mesh missing: run Scripts/import_athlete.py"));
    // Real locomotion mocap (CMU subject 35, retargeted): walk + two jog variants. Falls back to the Blender clips if the assets are missing.
    auto LoadLoco = [&](const TCHAR* N, EFootballAnim S) { if (UAnimSequence* A = LoadObject<UAnimSequence>(nullptr, *FString::Printf(TEXT("/Game/Football/Athlete/athlete_cmu_loco_%s_Anim.athlete_cmu_loco_%s_Anim"), N, N))) { AthleteClips[(int32)S] = A; return true; } return false; };
    const bool LocoOk = LoadLoco(TEXT("walk_35_01"), EFootballAnim::Walk) & LoadLoco(TEXT("jog_35_17"), EFootballAnim::Jog) & LoadLoco(TEXT("jog_35_23"), EFootballAnim::Sprint);
    UE_LOG(LogTemp, Display, TEXT("Locomotion mocap clips loaded: %s"), LocoOk ? TEXT("yes") : TEXT("NO (using Blender clips)"));
    bLocoMocap = LocoOk;
    for (const TCHAR* N : { TEXT("01"), TEXT("02"), TEXT("03"), TEXT("05"), TEXT("06") }) if (UAnimSequence* K = LoadObject<UAnimSequence>(nullptr, *FString::Printf(TEXT("/Game/Football/Athlete/athlete_cmu_kick_%s_Anim.athlete_cmu_kick_%s_Anim"), N, N))) MocapKicks.Add(K);
    UE_LOG(LogTemp, Display, TEXT("Mocap kick variants loaded: %d"), MocapKicks.Num());
    // Microsoft Rocketbox characters (MIT): same sim, new bodies. Clips are the athlete clips retargeted to the shared Biped skeleton. "-athlete" keeps the original mesh.
    if (!FParse::Param(FCommandLine::Get(), TEXT("athlete"))) {
        for (const TCHAR* N : { TEXT("Male_Adult_01"), TEXT("Male_Adult_02"), TEXT("Male_Adult_03"), TEXT("Male_Adult_04"), TEXT("Male_Adult_05"), TEXT("Male_Adult_06"), TEXT("Male_Adult_07"), TEXT("Male_Adult_08"), TEXT("Female_Adult_01") })
            if (USkeletalMesh* M = LoadObject<USkeletalMesh>(nullptr, *FString::Printf(TEXT("/Game/Football/Rocketbox/%s/%s.%s"), N, N, N))) RbxMeshes.Add(M);
        auto Rc = [](const FString& N) { return LoadObject<UAnimSequence>(nullptr, *FString::Printf(TEXT("/Game/Football/Rocketbox/Anim/%s.%s"), *N, *N)); };
        bool Ok = RbxMeshes.Num() > 0;
        if (Ok) {
            for (int k = 0; k < (int)EFootballAnim::Count; ++k) { UAnimSequence* A = Rc(FString::Printf(TEXT("rbx_%s"), UFootballAnimInstance::ClipName((EFootballAnim)k))); if (A) AthleteClips[k] = A; else Ok = false; }
            if (bLocoMocap) { if (UAnimSequence* A = Rc(TEXT("rbx_cmu_loco_walk_35_01_Anim"))) AthleteClips[(int)EFootballAnim::Walk] = A; if (UAnimSequence* A = Rc(TEXT("rbx_cmu_loco_jog_35_17_Anim"))) AthleteClips[(int)EFootballAnim::Jog] = A; if (UAnimSequence* A = Rc(TEXT("rbx_cmu_loco_jog_35_23_Anim"))) AthleteClips[(int)EFootballAnim::Sprint] = A; }
            MocapKicks.Reset(); for (const TCHAR* N : { TEXT("01"), TEXT("02"), TEXT("03"), TEXT("05"), TEXT("06") }) if (UAnimSequence* K = Rc(FString::Printf(TEXT("rbx_cmu_kick_%s_Anim"), N))) MocapKicks.Add(K);
        }
        bRocketbox = Ok; FParse::Value(FCommandLine::Get(), TEXT("-rbxyaw="), RbxYaw);
        UE_LOG(LogTemp, Display, TEXT("Rocketbox characters: %s (%d meshes, %d kicks)"), bRocketbox ? TEXT("ON") : TEXT("OFF (missing assets)"), RbxMeshes.Num(), MocapKicks.Num());
    }
    for (int i = 0; i < 22; ++i) {
        const FB::Footballer& P = Sim->players[i]; const FB::TeamSetup& T = (P.team == FB::TeamSide::Home ? Cfg.home : Cfg.away);
        const bool gk = P.role == FB::Role::GK;
        const FLinearColor Shirt = gk ? (P.team == FB::TeamSide::Home ? FLinearColor(0.95f, 0.8f, 0.1f) : FLinearColor(0.1f, 0.75f, 0.3f)) : FLinearColor(T.primary.r, T.primary.g, T.primary.b);
        const FLinearColor Shorts = gk ? FLinearColor(0.03f, 0.03f, 0.04f) : FLinearColor(T.secondary.r, T.secondary.g, T.secondary.b) * 0.9f;
        Athletes.Add(MakeAthlete(Shirt, Shorts, gk ? Shirt * 0.6f : Shirt, P.appearance.skinTone, P.appearance.hairColor, P.appearance.height, P.appearance.build, P.number));
    }
    for (int i = 0; i < 22; ++i) {   // query-only collision capsule per player (the match logic itself runs in the simulation)
        UCapsuleComponent* K = NewObject<UCapsuleComponent>(this); K->SetupAttachment(RootComponent); K->InitCapsuleSize(35.f, 92.f); K->RegisterComponent();
        K->SetCollisionEnabled(ECollisionEnabled::QueryOnly); K->SetCollisionObjectType(ECC_Pawn); K->SetCollisionResponseToAllChannels(ECR_Block); Capsules.Add(K);
    }
    FParse::Value(FCommandLine::Get(), TEXT("-cam="), StartCam); CamMode = StartCam;
    if (APlayerController* PC = UGameplayStatics::GetPlayerController(this, 0)) { PC->SetViewTarget(this); PC->SetInputMode(FInputModeGameOnly()); PC->bShowMouseCursor = false; }
    for (int s = 0; s < int(WarmupSeconds * 120); ++s) Sim->Step(ReadInput());
    Sim->DrainEvents();
    { FString TD; if (FParse::Value(FCommandLine::Get(), TEXT("-trailer="), TD) && !TD.IsEmpty()) { bTrailer = true; TrailerDir = TD; Comm.SetVoiceAllowed(false); Comm.Mode_ = FFootballCommentary::Mode::Off; BuildTrailer(Cfg); } }
    if (FParse::Param(FCommandLine::Get(), TEXT("replay"))) SetupReplay();
}


// Ground-plane movement relative to the camera (W = away from the camera / up the screen, D = right), in simulation coordinates (x, z).
static FB::Vec2 ScreenMoveToSim(const UCameraComponent* Cam, float Forward, float Right)
{
    if (!Cam) return FB::Vec2(Forward, Right);
    FVector F = Cam->GetForwardVector(); F.Z = 0.f; if (F.SizeSquared() < 1e-4f) F = Cam->GetUpVector(); F.Z = 0.f; F.Normalize();
    const FVector Rt(-F.Y, F.X, 0.f);   // UE is left-handed Z-up: right = (-Fy, Fx)
    const FVector V = F * Forward + Rt * Right;
    return FB::Vec2(V.X, V.Y);
}

std::array<FB::PlayerInput,2> AFootballMatchActor::ReadInput() const
{
    std::array<FB::PlayerInput,2> In{};
    APlayerController* PC = UGameplayStatics::GetPlayerController(this, 0);
    if (!PC || HumanSideIdx < 0 || bPaused) return In;
    auto Down = [&](const FKey& K) { return PC->IsInputKeyDown(K); };
    FB::PlayerInput& I = In[HumanSideIdx];
    float fw = (Down(EKeys::W) || Down(EKeys::Up) ? 1.f : 0.f) - (Down(EKeys::S) || Down(EKeys::Down) ? 1.f : 0.f);   // screen-relative
    float rt = (Down(EKeys::D) || Down(EKeys::Right) ? 1.f : 0.f) - (Down(EKeys::A) || Down(EKeys::Left) ? 1.f : 0.f);
    { FString TK; if (FParse::Value(FCommandLine::Get(), TEXT("-testkeys="), TK)) { if (TK.Contains(TEXT("W"))) fw = 1.f; if (TK.Contains(TEXT("S"))) fw = -1.f; if (TK.Contains(TEXT("D"))) rt = 1.f; if (TK.Contains(TEXT("A"))) rt = -1.f; } }
    FB::Vec2 mv = ScreenMoveToSim(Camera, fw, rt); const float ml = FB::Length(mv); if (ml > 1.f) mv = mv / ml;
    I.move = mv;
    // Gamepad (PlayStation layout, same context-sensitive mapping as the Swift game). Untested on hardware.
    {
        const float Dz = 0.18f; float lx = PC->GetInputAnalogKeyState(EKeys::Gamepad_LeftX), ly = PC->GetInputAnalogKeyState(EKeys::Gamepad_LeftY);
        if (FMath::Sqrt(lx*lx + ly*ly) > Dz) { I.move = ScreenMoveToSim(Camera, ly, lx); const float L2 = FB::Length(I.move); if (L2 > 1.f) I.move = I.move / L2; }
        const float rx = PC->GetInputAnalogKeyState(EKeys::Gamepad_RightX), ry = PC->GetInputAnalogKeyState(EKeys::Gamepad_RightY); if (FMath::Sqrt(rx*rx + ry*ry) > 0.5f) I.skill = ScreenMoveToSim(Camera, ry, rx);
        const bool Attack = Sim && Sim->ballOwner >= 0 && (int)Sim->players[Sim->ballOwner].team == HumanSideIdx;
        const bool Cross = Down(EKeys::Gamepad_FaceButton_Bottom), Circle = Down(EKeys::Gamepad_FaceButton_Right), Square = Down(EKeys::Gamepad_FaceButton_Left), Tri = Down(EKeys::Gamepad_FaceButton_Top), R1 = Down(EKeys::Gamepad_RightShoulder);
        if (Attack) { I.passHeld |= Cross; I.shootHeld |= Circle; I.lobHeld |= Square; I.throughHeld |= Tri; I.finesseHeld |= R1; }
        else { I.tackleHeld |= Cross || R1; I.slideHeld |= Circle; I.switchPressed |= Square; I.throughHeld |= Tri; }
        I.sprint |= PC->GetInputAnalogKeyState(EKeys::Gamepad_RightTriggerAxis) > 0.3f || Down(EKeys::Gamepad_RightTrigger); I.switchPressed |= Down(EKeys::Gamepad_LeftShoulder); I.jockeyHeld |= PC->GetInputAnalogKeyState(EKeys::Gamepad_LeftTriggerAxis) > 0.3f;
    }
    I.sprint |= Down(EKeys::LeftShift) || Down(EKeys::RightShift); I.passHeld |= Down(EKeys::E) || Down(EKeys::J); I.shootHeld |= Down(EKeys::SpaceBar) || Down(EKeys::K); I.lobHeld |= Down(EKeys::F) || Down(EKeys::L); I.throughHeld |= Down(EKeys::G) || Down(EKeys::I);
    I.tackleHeld |= Down(EKeys::X); I.slideHeld |= Down(EKeys::V); I.switchPressed |= Down(EKeys::Q); I.finesseHeld |= Down(EKeys::Z); I.jockeyHeld |= Down(EKeys::LeftControl);
    return In;
}

void AFootballMatchActor::Tick(float DeltaSeconds)
{
    Super::Tick(DeltaSeconds);
    if (!Sim) return;
    TickMenu();
    if (bTrailer) { TrailerBegin(); if (TFrame >= (int32)(TTotal * 30.f) + 40) { UKismetSystemLibrary::ExecuteConsoleCommand(this, TEXT("quit")); return; } }
    if (bReplay) { ReplayTick(DeltaSeconds); }
    else if (!bPaused) { const std::array<FB::PlayerInput,2> In = ReadInput(); const int n = Stepper.Advance(DeltaSeconds); for (int i = 0; i < n; ++i) Sim->Step(In); }

    { FString TK; static float Tt = 0.f, Last = -1.f; if (FParse::Value(FCommandLine::Get(), TEXT("-testkeys="), TK) && HumanSideIdx >= 0 && !bPaused) { Tt += DeltaSeconds; if (Tt - Last >= 0.4f && Tt < 6.f) { Last = Tt; const int Cc = Sim->teams[HumanSideIdx].controlled; if (Cc >= 0) { const FB::Footballer& P = Sim->players[Cc]; UE_LOG(LogTemp, Display, TEXT("MOVE_TEST phase=%d t=%.1f ctrl=%d speed=%.2f vel=(%.2f,%.2f) heading=%.0f"), (int)Sim->phase.kind, Tt, Cc, P.Speed(), P.vel.x, P.vel.y, FMath::RadiansToDegrees(P.heading)); } } } }
    if (!bReplay) { Comm.Consume(Sim->DrainEvents(), *Sim); if (!bPaused) Comm.Tick(DeltaSeconds, *Sim); }
    const FB::BallState& B = Sim->ball;
    BallMesh->SetWorldLocationAndRotation(ToUE(B.position.x, B.position.y, B.position.z), FQuat(B.orientation.x, B.orientation.z, B.orientation.y, -B.orientation.w));
    for (int i = 0; i < 22; ++i) {
        const FB::Footballer& P = Sim->players[i];
        const bool show = P.onPitch && !bReplay;
        USkeletalMeshComponent* A = Athletes[i]; A->SetVisibility(show); if (!show) continue;
        const float yaw = FMath::RadiansToDegrees(P.heading) + (bRocketbox ? RbxYaw : MeshYaw);
        A->SetWorldLocationAndRotation(ToUE(P.pos.x, 0.f, P.pos.y), FRotator(0, yaw, 0));
        if (Capsules.IsValidIndex(i)) { Capsules[i]->SetWorldLocation(ToUE(P.pos.x, 0.92f, P.pos.y)); Capsules[i]->SetCollisionEnabled(show ? ECollisionEnabled::QueryOnly : ECollisionEnabled::NoCollision); }
        const float Spd = P.Speed(); EFootballAnim St; float Rate = 1.f; const bool Gk = P.role == FB::Role::GK;
        if (P.IsDiving()) { const FB::Vec2 f = P.Facing(); St = (f.x * P.diveDir.y - f.y * P.diveDir.x) > 0 ? EFootballAnim::GKDiveLeft : EFootballAnim::GKDiveRight; }
        else if (P.holdingBall) St = EFootballAnim::GKCatch;
        else if (P.fallenTime > 0.4f) St = EFootballAnim::Fall; else if (P.fallenTime > 0.f) St = EFootballAnim::GetUp;
        else if (P.IsSliding()) St = EFootballAnim::Slide;
        else if (P.tackleAnim > 0.f) St = EFootballAnim::Tackle;
        else if (P.headAnim > 0.f) St = EFootballAnim::Header;
        else if (P.kickAnim > 0.f) St = Gk ? EFootballAnim::GKPunch : EFootballAnim::Kick;
        else if (P.celebrate > 0.f) St = EFootballAnim::Celebrate;
        else Locomotion(Spd, Gk, St, Rate);
        DriveAnim(A, St, Rate);
    }
    if (Stadium) { const float Pk = FMath::Clamp((FMath::Abs(B.position.x) - 25.f) / 25.f, 0.f, 1.f); Stadium->TickCrowd(GetWorld()->GetTimeSeconds(), Pk);
        Stadium->SetScoreText(TEXT("ALD"), TEXT("OAK"), Sim->score.home, Sim->score.away, FString::Printf(TEXT("%02d:%02d"), Sim->clock.Minutes(), int(Sim->clock.gameSeconds) % 60)); }
    // Cameras. C cycles: 0 broadcast, 1 tele, 2 end-to-end, 3 low sideline, 4 establishing wide, 5 goal cam.
    UGameplayStatics::GetPlayerController(this, 0);
    if (APlayerController* PC = UGameplayStatics::GetPlayerController(this, 0)) { const bool C = PC->IsInputKeyDown(EKeys::C); if (C && !bPrevC) CamMode = (CamMode + 1) % 6; bPrevC = C; }
    const FVector BP = ToUE(B.position.x, B.position.y, B.position.z); FVector Want, Look; float Fov = 38.f, Fstop = 0.f;
    const float bx = FMath::Clamp(B.position.x, -45.f, 45.f); const float sgn = B.position.x >= 0 ? 1.f : -1.f;
    switch (CamMode) {
    case 0: Want = ToUE(bx * 0.85f, 26.f, 58.f); Look = ToUE(B.position.x * 0.9f, 0.f, B.position.z * 0.4f); Fov = 38.f; break;
    case 1: Want = ToUE(bx * 0.9f, 33.f, 72.f); Look = ToUE(B.position.x, 0.f, B.position.z * 0.5f); Fov = 18.f; Fstop = 2.8f; break;
    case 2: Want = ToUE(B.position.x - sgn * 38.f, 14.f, B.position.z * 0.3f); Look = ToUE(B.position.x + sgn * 14.f, 0.5f, B.position.z * 0.5f); Fov = 45.f; break;
    case 3: Want = ToUE(B.position.x - 6.f, 1.6f, HalfWidthM() + 2.5f); Look = ToUE(B.position.x + 8.f, 1.2f, B.position.z); Fov = 50.f; Fstop = 2.0f; break;
    case 4: Want = ToUE(0.f, 70.f, 92.f); Look = ToUE(0.f, 0.f, 4.f); Fov = 58.f; break;
    default: Want = ToUE(sgn * 62.f, 3.2f, B.position.z * 0.15f + 6.f); Look = ToUE(B.position.x, 1.f, B.position.z); Fov = 34.f; Fstop = 2.8f; break; }
    bool bNoSmooth = false; float TFov = Fov, TFs = Fstop; if (bTrailer) { FVector W2, L2; if (TrailerCamera(W2, L2, TFov, TFs)) { Want = W2; Look = L2; Fov = TFov; Fstop = TFs; bNoSmooth = true; } }
    if (bNoSmooth) { SmoothedCam = Want; SmoothedLook = Look; bCamInit = true; PrevMode = CamMode; }
    if (!bCamInit) { SmoothedCam = Want; SmoothedLook = Look; bCamInit = true; PrevMode = CamMode; }
    if (PrevMode != CamMode) { SmoothedCam = Want; SmoothedLook = Look; PrevMode = CamMode; }
    const float k = 1.f - FMath::Exp(-(CamMode == 3 ? 6.f : 2.5f) * DeltaSeconds);
    SmoothedCam = FMath::Lerp(SmoothedCam, Want, k); SmoothedLook = FMath::Lerp(SmoothedLook, Look, k);
    Camera->SetWorldLocationAndRotation(SmoothedCam, (SmoothedLook - SmoothedCam).Rotation()); Camera->SetFieldOfView(Fov);
    FPostProcessSettings& PS = Camera->PostProcessSettings;
    PS.bOverride_DepthOfFieldFstop = true; PS.bOverride_DepthOfFieldFocalDistance = true; PS.bOverride_DepthOfFieldSensorWidth = true;
    PS.DepthOfFieldSensorWidth = 24.576f; PS.DepthOfFieldFstop = Fstop > 0.f ? Fstop : 32.f; PS.DepthOfFieldFocalDistance = FMath::Max(100.f, FVector::Dist(SmoothedCam, BP));
    if (bTrailer) {
        if (TFrame >= 40 && TShotIdx >= 0 && TShotIdx < TShots.Num()) {
            if (APlayerController* PC = UGameplayStatics::GetPlayerController(this, 0)) if (PC->MyHUD) PC->MyHUD->bShowHUD = TShots[TShotIdx].Hud;
            UKismetSystemLibrary::ExecuteConsoleCommand(this, FString::Printf(TEXT("HighResShot 1920x1080 filename=\"%s/f%05d.png\""), *TrailerDir, TCapture++));
        }
        ++TFrame;
    }
    // Automated screenshot: -shot=<seconds of real time>
    static float ShotAt = -1.f; static float Elapsed = 0.f; static bool Done = false;
    if (ShotAt < 0.f) { ShotAt = 0.f; FParse::Value(FCommandLine::Get(), TEXT("-shot="), ShotAt); if (ShotAt == 0.f) ShotAt = -2.f; }
    Elapsed += DeltaSeconds; { static float Acc = 0.f; static int Fr = 0; static float Worst = 0.f; if (Elapsed > 6.f) { Acc += DeltaSeconds; ++Fr; Worst = FMath::Max(Worst, DeltaSeconds); if (!Done && ShotAt > 0.f && Elapsed > ShotAt - 0.1f && Fr > 10) UE_LOG(LogTemp, Display, TEXT("PERF avg_fps=%.1f worst_ms=%.1f frames=%d"), Fr / Acc, Worst * 1000.f, Fr); } }
    if (!Done && ShotAt > 0.f && Elapsed > ShotAt - 1.f && !bReplay && FParse::Param(FCommandLine::Get(), TEXT("verifyfacing"))) { static bool Vf = false; if (!Vf) { Vf = true; VerifyFacing(); } }
    if (!Done && ShotAt > 0.f && Elapsed > ShotAt - 1.f && !bReplay && FParse::Param(FCommandLine::Get(), TEXT("verifycollision"))) { static bool Ver = false; if (!Ver) { Ver = true; VerifyCollision(); } }
    if (!Done && ShotAt > 0.f && Elapsed > ShotAt) { Done = true; UKismetSystemLibrary::ExecuteConsoleCommand(this, TEXT("HighResShot 1280x720")); }
    if (Done && Elapsed > ShotAt + 3.f) UKismetSystemLibrary::ExecuteConsoleCommand(this, TEXT("quit"));
}

bool AFootballMatchActor::KeyPressed(const FKey& K)
{
    APlayerController* PC = UGameplayStatics::GetPlayerController(this, 0); if (!PC) return false;
    const bool Down = PC->IsInputKeyDown(K); const bool Was = KeysDown.Contains(K);
    if (Down) KeysDown.Add(K); else KeysDown.Remove(K);
    return Down && !Was;
}

void AFootballMatchActor::SetupReplay()
{
    FString Path = FPaths::ConvertRelativePathToFull(FPaths::ProjectDir(), TEXT("../../Datasets/replay/metrica_game1")), Err;
    FString Over; if (FParse::Value(FCommandLine::Get(), TEXT("-replay="), Over) && !Over.IsEmpty()) Path = Over;
    if (!Replay.Load(Path, Err)) { UE_LOG(LogTemp, Error, TEXT("Replay: %s"), *Err); GEngine->AddOnScreenDebugMessage(1, 30.f, FColor::Red, Err); return; }
    bReplay = true; float Start = 0.f; FParse::Value(FCommandLine::Get(), TEXT("-replaystart="), Start); ReplayFrame = Start * FTrackingReplay::Hz;
    FParse::Value(FCommandLine::Get(), TEXT("-replayspeed="), ReplaySpeed);
    for (int i = 0; i < 28; ++i) {
        const bool Home = i < FTrackingReplay::HomeSlots; const bool Gk = (i % 14) == 0;
        const FLinearColor Kit = Gk ? (Home ? FLinearColor(0.95f, 0.8f, 0.1f) : FLinearColor(0.1f, 0.8f, 0.3f)) : (Home ? FLinearColor(0.85f, 0.1f, 0.1f) : FLinearColor(0.1f, 0.35f, 0.8f));
        RAthletes.Add(MakeAthlete(Kit, Gk ? FLinearColor(0.03f, 0.03f, 0.04f) : FLinearColor(0.9f, 0.9f, 0.9f), Kit * 0.7f, i % 6, i % 5));
    }
    UE_LOG(LogTemp, Display, TEXT("Replay loaded: %d frames (%.1f min), source %s"), Replay.Frames, Replay.Frames / FTrackingReplay::Hz / 60.f, *Replay.Source);
}

void AFootballMatchActor::ReplayTick(float Dt)
{
    // Controls: P pause, ]/[ speed, Left/Right +-10 s, Up/Down +-60 s, N second half, O overlay.
    if (KeyPressed(EKeys::P)) bReplayPaused = !bReplayPaused;
    if (KeyPressed(EKeys::RightBracket)) ReplaySpeed = FMath::Min(32.f, ReplaySpeed * 2.f);
    if (KeyPressed(EKeys::LeftBracket)) ReplaySpeed = FMath::Max(0.25f, ReplaySpeed * 0.5f);
    if (KeyPressed(EKeys::Right)) ReplayFrame += 10.f * FTrackingReplay::Hz; if (KeyPressed(EKeys::Left)) ReplayFrame -= 10.f * FTrackingReplay::Hz;
    if (KeyPressed(EKeys::Up)) ReplayFrame += 60.f * FTrackingReplay::Hz; if (KeyPressed(EKeys::Down)) ReplayFrame -= 60.f * FTrackingReplay::Hz;
    if (KeyPressed(EKeys::N)) ReplayFrame = (float)Replay.Period2Start; if (KeyPressed(EKeys::O)) bOverlay = !bOverlay;
    if (!bReplayPaused) ReplayFrame += Dt * ReplaySpeed * FTrackingReplay::Hz;
    ReplayFrame = FMath::Clamp(ReplayFrame, 0.f, (float)(Replay.Frames - 2));

    FVector2D P; const float F = ReplayFrame;
    TArray<FVector> Pos[2]; int32 Near = -1; float NearD = 1e9f; FVector2D Ball(0, 0); const bool HaveBall = Replay.Sample(F, FTrackingReplay::BallSlot, Ball);
    for (int i = 0; i < 28; ++i) {
        FVector2D A, B;
        const bool Ok = Replay.Sample(F, i, A) && Replay.Sample(F + 1.f, i, B);
        RAthletes[i]->SetVisibility(Ok); if (!Ok) continue;
        const FVector2D V = (B - A) * FTrackingReplay::Hz / 100.f; const float Spd = V.Size();
        const float Yaw = Spd > 0.4f ? FMath::RadiansToDegrees(FMath::Atan2(V.Y, V.X)) + MeshYaw : RAthletes[i]->GetComponentRotation().Yaw;
        RAthletes[i]->SetWorldLocationAndRotation(FVector(A.X, A.Y, 0.f), FRotator(0, Yaw, 0));
        const bool Gk = (i % 14) == 0; EFootballAnim St; float Rt = 1.f; Locomotion(Spd, Gk, St, Rt);
        DriveAnim(RAthletes[i], St, Rt);
        const bool Home = i < 14; Pos[Home ? 0 : 1].Add(FVector(A.X, A.Y, 0));
        if (HaveBall) { const float D = FVector2D::Distance(A, Ball); if (D < NearD) { NearD = D; Near = i; } }
    }
    if (HaveBall) { BallMesh->SetWorldLocation(FVector(Ball.X, Ball.Y, 11.f)); Sim->ball.position = FB::Vec3(Ball.X / 100.f, 0.11f, Ball.Y / 100.f); }
    if (bOverlay) {
        UWorld* W = GetWorld();
        for (int T = 0; T < 2; ++T) {
            if (Pos[T].Num() < 3) continue; const FColor C = T == 0 ? FColor(255, 70, 70) : FColor(80, 140, 255);
            FVector Cen = FVector::ZeroVector; float MinX = 1e9f, MaxX = -1e9f, MinY = 1e9f, MaxY = -1e9f;
            for (const FVector& V : Pos[T]) { Cen += V; MinX = FMath::Min(MinX, V.X); MaxX = FMath::Max(MaxX, V.X); MinY = FMath::Min(MinY, V.Y); MaxY = FMath::Max(MaxY, V.Y); }
            Cen /= Pos[T].Num(); DrawDebugSphere(W, Cen + FVector(0, 0, 30), 70.f, 12, C, false, -1.f, 0, 8.f);
            DrawDebugBox(W, FVector((MinX + MaxX) / 2, (MinY + MaxY) / 2, 20), FVector((MaxX - MinX) / 2, (MaxY - MinY) / 2, 1), C, false, -1.f, 0, 6.f);   // team shape (length x width)
            // Defensive line: four deepest outfield players (own goal is at -X for home in period 1, +X in period 2; use whichever end the keeper is nearest to).
            const FVector2D Gk = Pos[T].Num() ? FVector2D(Pos[T][0].X, Pos[T][0].Y) : FVector2D::ZeroVector; const float Dir = Gk.X < 0 ? 1.f : -1.f;
            TArray<FVector> Out; for (int k = 1; k < Pos[T].Num(); ++k) Out.Add(Pos[T][k]);
            Out.Sort([Dir](const FVector& A, const FVector& B) { return A.X * Dir < B.X * Dir; });
            if (Out.Num() >= 4) { float Ymin = 1e9f, Ymax = -1e9f, Xs = 0; for (int k = 0; k < 4; ++k) { Ymin = FMath::Min(Ymin, Out[k].Y); Ymax = FMath::Max(Ymax, Out[k].Y); Xs += Out[k].X; } Xs /= 4;
                DrawDebugLine(W, FVector(Xs, Ymin, 25), FVector(Xs, Ymax, 25), FColor::Yellow, false, -1.f, 0, 10.f); }
        }
        if (Near >= 0) DrawDebugCircle(W, FVector(Ball.X, Ball.Y, 15), 90.f, 24, FColor::White, false, -1.f, 0, 6.f, FVector(1, 0, 0), FVector(0, 1, 0), false);
        const int32 Period = (int32)ReplayFrame >= Replay.Period2Start ? 2 : 1; const float Sec = ReplayFrame / FTrackingReplay::Hz;
        GEngine->AddOnScreenDebugMessage(10, 0.f, FColor::White, FString::Printf(TEXT("TRACKING REPLAY  %s   %02d:%02d  P%d   x%.2g%s   frames %d/%d   [P pause  [ ] speed  arrows seek  N 2nd half  O overlay]"),
            *Replay.Source, int(Sec) / 60, int(Sec) % 60, Period, ReplaySpeed, bReplayPaused ? TEXT(" PAUSED") : TEXT(""), int(ReplayFrame), Replay.Frames));
        if (Near >= 0) GEngine->AddOnScreenDebugMessage(11, 0.f, FColor::Yellow, FString::Printf(TEXT("Ball nearest: %s #%d (%.1f m)"), Near < 14 ? TEXT("Home") : TEXT("Away"), Replay.Jersey[Near], NearD / 100.f));
    }
}

USkeletalMeshComponent* AFootballMatchActor::MakeAthlete(const FLinearColor& Shirt, const FLinearColor& Shorts, const FLinearColor& Socks, int32 SkinIdx, int32 HairIdx, float Height, float Build, int32 Number)
{
    USkeletalMeshComponent* C = NewObject<USkeletalMeshComponent>(this);
    USkeletalMesh* UseMesh = AthleteMesh; if (bRocketbox) UseMesh = RbxMeshes[(Number * 5 + SkinIdx * 3 + HairIdx) % RbxMeshes.Num()];
    C->SetSkeletalMesh(UseMesh); C->SetupAttachment(RootComponent);
    C->SetAnimationMode(EAnimationMode::AnimationBlueprint); C->SetAnimInstanceClass(UFootballAnimInstance::StaticClass());
    C->SetCollisionEnabled(ECollisionEnabled::NoCollision); C->CastShadow = true;
    C->VisibilityBasedAnimTickOption = EVisibilityBasedAnimTickOption::AlwaysTickPoseAndRefreshBones;
    C->RegisterComponent();
    // Distinct bodies: height from the player's appearance (1.70-1.92 m) and a build factor for width.
    C->SetRelativeScale3D(FVector(0.92f + 0.16f * Build, 0.92f + 0.16f * Build, Height / (bRocketbox ? 1.82f : 1.84f)));
    if (Number > 0) {   // shirt-back number
        UTextRenderComponent* T = NewObject<UTextRenderComponent>(this); T->SetupAttachment(C); T->RegisterComponent();
        T->SetText(FText::AsNumber(Number)); T->SetWorldSize(26.f); T->SetHorizontalAlignment(EHTA_Center); T->SetVerticalAlignment(EVRTA_TextCenter);
        T->SetTextRenderColor(FColor::White); T->SetRelativeLocationAndRotation(FVector(0.f, -16.f, 128.f), FRotator(0.f, -90.f, 0.f)); T->CastShadow = false;
    }
    if (UFootballAnimInstance* AI = Cast<UFootballAnimInstance>(C->GetAnimInstance())) {
        AI->Clips = AthleteClips; AI->PhaseOffset = FMath::FRand() * 0.8f;
        if (MocapKicks.Num() > 0) { AI->Clips[(int32)EFootballAnim::Kick] = MocapKicks[(Number > 0 ? Number : FMath::Rand()) % MocapKicks.Num()]; AI->KickStartOffset = 0.42f; }   // retargeted CMU mocap kick (right foot); strike ~0.55 s in
    }
    static const FLinearColor Skins[6] = { {0.80f,0.58f,0.45f}, {0.72f,0.50f,0.36f}, {0.55f,0.36f,0.25f}, {0.38f,0.24f,0.17f}, {0.88f,0.68f,0.55f}, {0.27f,0.17f,0.12f} };
    static const FLinearColor Hairs[5] = { {0.03f,0.02f,0.02f}, {0.12f,0.07f,0.04f}, {0.3f,0.18f,0.08f}, {0.55f,0.4f,0.15f}, {0.5f,0.5f,0.5f} };
    if (bRocketbox && UseMesh) {
        const TArray<FSkeletalMaterial>& Mats = UseMesh->GetMaterials();
        for (int32 i = 0; i < Mats.Num(); ++i) {
            if (!Mats[i].MaterialInterface) continue;
            UMaterialInstanceDynamic* M = UMaterialInstanceDynamic::Create(Mats[i].MaterialInterface, this);
            if (Mats[i].MaterialSlotName.ToString().ToLower().Contains(TEXT("body"))) { const bool Dbg = FParse::Param(FCommandLine::Get(), TEXT("kitdebug")); M->SetVectorParameterValue(TEXT("Shirt"), Shirt); M->SetVectorParameterValue(TEXT("Shorts"), Dbg ? FLinearColor(0.f, 1.f, 0.f) : Shorts); M->SetVectorParameterValue(TEXT("Socks"), Dbg ? FLinearColor(1.f, 0.f, 1.f) : Socks); }
            C->SetMaterial(i, M);
        }
    } else if (AthleteMesh) {
        const TArray<FSkeletalMaterial>& Mats = AthleteMesh->GetMaterials();
        for (int32 i = 0; i < Mats.Num(); ++i) {
            const FString N = Mats[i].MaterialSlotName.ToString().ToLower(); FLinearColor Col = FLinearColor(0.2f, 0.2f, 0.2f);
            if (N.Contains(TEXT("skin"))) Col = Skins[SkinIdx % 6]; else if (N.Contains(TEXT("shirt"))) Col = Shirt; else if (N.Contains(TEXT("shorts"))) Col = Shorts;
            else if (N.Contains(TEXT("socks"))) Col = Socks; else if (N.Contains(TEXT("boots"))) Col = FLinearColor(0.02f, 0.02f, 0.025f); else if (N.Contains(TEXT("hair"))) Col = Hairs[HairIdx % 5];
            UMaterialInterface* KitBase = KitMat ? KitMat.Get() : BaseMat.Get(); UMaterialInstanceDynamic* M = UMaterialInstanceDynamic::Create(KitBase, this); M->SetVectorParameterValue(TEXT("Color"), Col); C->SetMaterial(i, M);
        }
    }
    return C;
}

void AFootballMatchActor::DriveAnim(USkeletalMeshComponent* C, EFootballAnim S, float Rate)
{
    if (UFootballAnimInstance* AI = C ? Cast<UFootballAnimInstance>(C->GetAnimInstance()) : nullptr) AI->Request(S, Rate);
}

void AFootballMatchActor::VerifyCollision()
{
    int Hit = 0, Total = 0; UWorld* W = GetWorld();
    for (int i = 0; i < 22; ++i) {
        if (!Sim->players[i].onPitch) continue; ++Total; const FVector P = Capsules[i]->GetComponentLocation();
        FHitResult R; FCollisionQueryParams Q; Q.bTraceComplex = false;
        if (W->LineTraceSingleByChannel(R, P + FVector(0, 0, 600), P - FVector(0, 0, 100), ECC_Pawn, Q) && R.GetComponent() == Capsules[i]) ++Hit;
    }
    UE_LOG(LogTemp, Display, TEXT("COLLISION_CHECK %d/%d player capsules hit by a vertical trace"), Hit, Total);
    GEngine->AddOnScreenDebugMessage(40, 20.f, FColor::Green, FString::Printf(TEXT("COLLISION_CHECK %d/%d"), Hit, Total));
}

void AFootballMatchActor::VerifyFacing()
{
    // Ground truth: compare the body's real forward (from the hip axis, in world space) with the player's travel direction.
    int Moving = 0, Aligned = 0, Opposed = 0, Side = 0; double SumDot = 0;
    for (int i = 0; i < 22; ++i) {
        const FB::Footballer& P = Sim->players[i]; if (!P.onPitch || P.Speed() < 3.f) continue;
        USkeletalMeshComponent* A = Athletes[i];
        // Hip axis (left thigh -> right thigh) is stable through the gait cycle; forward = that vector rotated so a +Y-facing rest pose (left->right = -X) gives +Y.
        const FVector LR = (bRocketbox ? A->GetBoneLocation(TEXT("Bip01-R-Thigh")) - A->GetBoneLocation(TEXT("Bip01-L-Thigh")) : A->GetBoneLocation(TEXT("thigh_R")) - A->GetBoneLocation(TEXT("thigh_L")));
        FVector Fwd(LR.Y, -LR.X, 0.f); if (Fwd.SizeSquared() < 1.f) continue; Fwd.Normalize();
        FVector Vel(P.vel.x, P.vel.y, 0.f); Vel.Normalize(); const float D = FVector::DotProduct(Fwd, Vel);
        { const FB::Vec2 f = P.Facing(); FVector SF(f.x, f.y, 0.f); const float SimDot = FVector::DotProduct(SF, Vel);
          UFootballAnimInstance* AI = Cast<UFootballAnimInstance>(A->GetAnimInstance());
          UE_LOG(LogTemp, Display, TEXT("FACING_DETAIL p%02d role=%d speed=%.1f simHeadingDotVel=%.2f meshHipDotVel=%.2f animState=%d"), i, (int)P.role, P.Speed(), SimDot, D, AI ? (int)AI->RequestedState : -1); }
        ++Moving; SumDot += D; if (D > 0.7f) ++Aligned; else if (D < -0.7f) ++Opposed; else ++Side;
    }
    UE_LOG(LogTemp, Display, TEXT("FACING_CHECK moving=%d aligned(>0.7)=%d opposed(<-0.7)=%d sideways=%d meanDot=%.2f MeshYaw=%.0f"), Moving, Aligned, Opposed, Side, Moving ? SumDot / Moving : 0.0, bRocketbox ? RbxYaw : MeshYaw);
}

void AFootballMatchActor::Locomotion(float Spd, bool Gk, EFootballAnim& St, float& Rate) const
{
    // Playback rate = movement speed / the clip's effective ground speed, so the feet stay planted instead of skating.
    // Effective ground speeds (m/s) of the retargeted CMU cycles: walk 0.85, jog 2.40, jog-b 2.59 (CMU true speeds 1.29 / 3.15 / 3.41 scaled by the
    // retarget's measured stride ratio for the athlete's shorter legs). The Blender fallback clips keep the old calibration.
    if (Spd < 0.35f) { St = Gk ? EFootballAnim::GKReady : EFootballAnim::Idle; Rate = 1.f; return; }
    if (!bLocoMocap) {
        if (Spd < 2.3f) { St = EFootballAnim::Walk; Rate = FMath::Clamp(Spd / 1.6f, 0.6f, 1.6f); }
        else if (Spd < 5.6f) { St = EFootballAnim::Jog; Rate = FMath::Clamp(Spd / 4.2f, 0.7f, 1.5f); }
        else { St = EFootballAnim::Sprint; Rate = FMath::Clamp(Spd / 7.8f, 0.8f, 1.4f); }
        return;
    }
    if (Spd < 1.5f) { St = EFootballAnim::Walk; Rate = FMath::Clamp(Spd / 0.85f, 0.5f, 1.9f); }
    else if (Spd < 4.6f) { St = EFootballAnim::Jog; Rate = FMath::Clamp(Spd / 2.40f, 0.6f, 2.0f); }
    else { St = EFootballAnim::Sprint; Rate = FMath::Clamp(Spd / 2.59f, 1.0f, 2.1f); }
}


// ---------------- Pause menu / side selection ----------------
static const TCHAR* CamNames[] = { TEXT("Broadcast"), TEXT("Tele"), TEXT("End-to-end"), TEXT("Sideline"), TEXT("Wide"), TEXT("Goal cam") };

TArray<FString> AFootballMatchActor::MenuLabels() const
{
    const FString Side = HumanSideIdx == 0 ? TEXT("HOME  (attack right)") : HumanSideIdx == 1 ? TEXT("AWAY  (attack left)") : TEXT("CPU vs CPU");
    return { TEXT("Resume"), FString::Printf(TEXT("Side:  < %s >"), *Side), FString::Printf(TEXT("Camera:  < %s >"), CamNames[CamMode % 6]), FString::Printf(TEXT("Commentary:  < %s >"), *Comm.ModeLabel()), TEXT("Restart match"), TEXT("Quit game") };
}

void AFootballMatchActor::SetHumanSide(int32 Side)
{
    if (!Sim || Side == HumanSideIdx) return;
    for (int t = 0; t < 2; ++t) { Sim->teams[t].human = (t == Side); Sim->config.humanTeams[t] = (t == Side); if (t != Side) Sim->teams[t].controlled = -1; }
    if (Side >= 0) Sim->teams[Side].controlled = Sim->NearestOutfield((FB::TeamSide)Side, Sim->BXZ());
    HumanSideIdx = Side; GSavedSide = Side;
}

void AFootballMatchActor::MenuActivate(int32 Dir)
{
    switch (MenuSel) {
    case 0: bPaused = false; break;
    case 1: { const int32 Next = HumanSideIdx < 0 ? 0 : (HumanSideIdx + (Dir >= 0 ? 1 : 3)) % 2; SetHumanSide(Next); break; }
    case 2: CamMode = (CamMode + (Dir >= 0 ? 1 : 5)) % 6; break;
    case 3: Comm.CycleMode(Dir); break;
    case 4: GSavedSide = HumanSideIdx; UGameplayStatics::OpenLevel(this, FName(*UGameplayStatics::GetCurrentLevelName(this, true))); break;
    case 5: UKismetSystemLibrary::ExecuteConsoleCommand(this, TEXT("quit")); break;
    }
}

void AFootballMatchActor::TickMenu()
{
    if (bReplay) return;
    if (KeyPressed(EKeys::Escape) || KeyPressed(EKeys::Gamepad_Special_Right)) { bPaused = !bPaused; MenuSel = 0; return; }
    if (!bPaused) return;
    const int N = 6;
    if (KeyPressed(EKeys::Up) || KeyPressed(EKeys::Gamepad_DPad_Up)) MenuSel = (MenuSel + N - 1) % N;
    if (KeyPressed(EKeys::Down) || KeyPressed(EKeys::Gamepad_DPad_Down)) MenuSel = (MenuSel + 1) % N;
    if (KeyPressed(EKeys::Left) || KeyPressed(EKeys::Gamepad_DPad_Left)) MenuActivate(-1);
    if (KeyPressed(EKeys::Right) || KeyPressed(EKeys::Gamepad_DPad_Right) || KeyPressed(EKeys::Enter) || KeyPressed(EKeys::Gamepad_FaceButton_Bottom)) MenuActivate(+1);
}

int32 AFootballMatchActor::PassTarget() const
{
    if (!Sim || HumanSideIdx < 0) return -1;
    const int c = Sim->teams[HumanSideIdx].controlled; if (c < 0) return -1;
    const FB::Footballer& p = Sim->players[c]; const FB::TeamSide team = p.team;
    FB::Vec2 dir = p.Facing();
    if (APlayerController* PC = UGameplayStatics::GetPlayerController(this, 0)) {
        float fw = ((PC->IsInputKeyDown(EKeys::W) || PC->IsInputKeyDown(EKeys::Up)) ? 1.f : 0.f) - ((PC->IsInputKeyDown(EKeys::S) || PC->IsInputKeyDown(EKeys::Down)) ? 1.f : 0.f), rt = ((PC->IsInputKeyDown(EKeys::D) || PC->IsInputKeyDown(EKeys::Right)) ? 1.f : 0.f) - ((PC->IsInputKeyDown(EKeys::A) || PC->IsInputKeyDown(EKeys::Left)) ? 1.f : 0.f);
        fw = FMath::Clamp(fw + PC->GetInputAnalogKeyState(EKeys::Gamepad_LeftY), -1.f, 1.f); rt = FMath::Clamp(rt + PC->GetInputAnalogKeyState(EKeys::Gamepad_LeftX), -1.f, 1.f);
        const FB::Vec2 mv = ScreenMoveToSim(Camera, fw, rt); if (FB::Length(mv) > 0.3f) dir = FB::Unit(mv);
    }
    int best = -1; float bestS = -1e9f;
    for (int pass = 0; pass < 2 && best < 0; ++pass)
        for (int j = 0; j < 22; ++j) {
            const FB::Footballer& q = Sim->players[j]; if (!(q.team == team && j != c && q.onPitch && q.role != FB::Role::GK)) continue;
            const FB::Vec2 v = q.pos - p.pos; const float d = FB::Length(v); if (!(d > 3.f && d < 50.f)) continue;
            const float cs = FB::Dot(v / d, dir); if (!(cs > (pass == 0 ? 0.75f : 0.5f))) continue;
            const float sc = cs * 2.f - d / 40.f; if (sc > bestS) { bestS = sc; best = j; } }
    return best;
}


// ---------------- Trailer director ----------------
void AFootballMatchActor::BuildTrailer(const FB::MatchConfig& Cfg)
{
    // Pre-pass: replay the identical deterministic match headless to find the moments worth filming.
    FB::MatchSimulation Pre(Cfg); const std::array<FB::PlayerInput,2> None{};
    for (int s = 0; s < 120 * 330; ++s) { Pre.Step(None); const float T = Pre.tick * FB::MatchSimulation::DT; for (const FB::GameEvent& E : Pre.DrainEvents()) TEvents.Add({ T, (int32)E.kind, E.a, E.b, E.f }); }
    auto Find = [&](FB::GameEvent::Kind K, float After, TFunction<bool(const FTEvt&)> Pred = nullptr) -> const FTEvt* { for (const FTEvt& E : TEvents) if (E.Kind == (int32)K && E.T > After && (!Pred || Pred(E))) return &E; return nullptr; };
    using K = FB::GameEvent::Kind;
    const FTEvt* Goal = Find(K::Goal, 25.f); const FTEvt* Skill = Find(K::SkillMove, 20.f); const FTEvt* Tackle = Find(K::Tackle, 20.f, [](const FTEvt& E) { return E.F > 0.5f; });
    const FTEvt* Save = Find(K::Save, 20.f, [](const FTEvt& E) { return E.B == 1; }); if (!Save) Save = Find(K::Save, 20.f);
    UE_LOG(LogTemp, Display, TEXT("TRAILER events: goal=%.1f skill=%.1f tackle=%.1f save=%.1f (of %d events)"), Goal ? Goal->T : -1.f, Skill ? Skill->T : -1.f, Tackle ? Tackle->T : -1.f, Save ? Save->T : -1.f, TEvents.Num());
    const float tG = Goal ? Goal->T : 120.f, tSk = Skill ? Skill->T : 70.f, tTk = Tackle ? Tackle->T : 90.f, tSv = Save ? Save->T : 100.f; const int32 Scorer = Goal ? Goal->B : -2, SkillP = Skill ? Skill->A : -2;
    float T0 = 0.f; auto Add = [&](const TCHAR* Nm, float Dur, int32 Mode, int32 Target, float SimAt, float Slow, bool Hud = false, bool Pause = false) { TShots.Add({ T0, Dur, SimAt, Slow, Mode, Target, Hud, Pause, FName(Nm) }); T0 += Dur; };
    // Mode: 0..5 standard cameras, 10 orbit, 11 stadium flyover, 12 low hero approach, 13 reverse flyover. Target -2 = current ball owner.
    // Order follows the match's own timeline (the simulation only runs forward).
    Add(TEXT("flyover"),      7.0f, 11, -1, 11.f,        1.f);
    Add(TEXT("sideline"),     4.0f,  3, -1, -1.f,        1.f);
    Add(TEXT("hero"),         4.0f, 12, -2, -1.f,        1.f);
    Add(TEXT("save"),         3.5f, 14, -1, tSv - 2.f,   0.6f);
    Add(TEXT("buildup"),      5.0f,  1, -1, tG - 7.f,    1.f, true);
    Add(TEXT("goalcam"),      3.6f, 14, -1, tG - 1.4f,   0.3f);
    Add(TEXT("celebrate"),    5.0f, 10, Scorer, -1.f,    0.7f);
    { const int32 MM[6] = { 1, 3, 0, 4, 12, 10 }; for (int i = 0; i < 6; ++i) Add(i == 0 ? TEXT("mosaic0") : (i == 1 ? TEXT("mosaic1") : (i == 2 ? TEXT("mosaic2") : (i == 3 ? TEXT("mosaic3") : (i == 4 ? TEXT("mosaic4") : TEXT("mosaic5"))))), 1.2f, MM[i], MM[i] >= 10 ? -2 : -1, i == 0 ? tG + 14.f : -1.f, 1.f); }
    Add(TEXT("tackle"),       3.0f,  3, -1, tTk - 1.2f,  1.f);
    Add(TEXT("orbit"),        5.0f, 10, -2, -1.f,        0.5f);
    Add(TEXT("menu"),         5.0f,  0, -1, -1.f,        1.f, true, true);
    Add(TEXT("outro"),        6.0f, 13, -1, -1.f,        1.f);
    TTotal = T0;
}

void AFootballMatchActor::TrailerShotStart(const FTShot& S)
{
    if (S.SimAt >= 0.f) { const std::array<FB::PlayerInput,2> None{}; int Guard = 0; while (Sim->tick * FB::MatchSimulation::DT < S.SimAt && Guard++ < 120 * 400) Sim->Step(None); Sim->DrainEvents(); }
    UGameplayStatics::SetGlobalTimeDilation(this, S.Slow);
    if (S.Pause) bPaused = true; else bPaused = false;
    if (S.Mode >= 0 && S.Mode <= 5) CamMode = S.Mode;   // standard broadcast cameras
    bCamInit = false; MenuSel = 0;
}

void AFootballMatchActor::TrailerBegin()
{
    const float T = TFrame > 40 ? (TFrame - 40) / 30.f : -1.f; if (T < 0.f) { if (TFrame == 0 && TShots.Num()) { TShotIdx = 0; TrailerShotStart(TShots[0]); } return; }
    int32 Idx = TShotIdx; while (Idx + 1 < TShots.Num() && T >= TShots[Idx + 1].Start) ++Idx;
    if (Idx != TShotIdx || TShotIdx < 0) { TShotIdx = Idx; TrailerShotStart(TShots[Idx]); }
}

bool AFootballMatchActor::TrailerCamera(FVector& Want, FVector& Look, float& Fov, float& Fstop)
{
    if (TShotIdx < 0 || TShotIdx >= TShots.Num()) return false;
    const FTShot& S = TShots[TShotIdx]; const float T = FMath::Max(0.f, (TFrame - 40) / 30.f - S.Start), U = FMath::Clamp(T / S.Dur, 0.f, 1.f);
    const float E = U * U * (3.f - 2.f * U);   // smoothstep
    const FB::BallState& B = Sim->ball;
    int32 Tgt = S.Target == -2 ? Sim->ballOwner : S.Target; if (S.Target == -2 && Tgt < 0) Tgt = Sim->lastTouch;
    auto PP = [&](int32 i) { return Sim->players[FMath::Clamp(i, 0, 21)]; };
    switch (S.Mode) {
    case 10: {   // orbit hero shot: low, long lens, shallow depth of field
        const FB::Footballer& P = PP(Tgt < 0 ? 4 : Tgt); const float Ang = FMath::DegreesToRadians(200.f + 70.f * U), R = FMath::Lerp(330.f, 240.f, E);
        const FVector C = ToUE(P.pos.x, 1.15f, P.pos.y); Want = C + FVector(FMath::Cos(Ang) * R, FMath::Sin(Ang) * R, FMath::Lerp(-25.f, 15.f, E)); Look = C + FVector(0, 0, 5.f); Fov = 30.f; Fstop = 1.8f; return true; }
    case 11: {   // stadium flyover: high and wide, descending toward the pitch
        Want = ToUE(FMath::Lerp(-72.f, -20.f, E), FMath::Lerp(46.f, 22.f, E), FMath::Lerp(44.f, 56.f, E)); Look = ToUE(FMath::Lerp(-8.f, 8.f, E), 0.f, 0.f); Fov = FMath::Lerp(50.f, 40.f, E); Fstop = 0.f; return true; }
    case 14: {   // goal-side camera: low, off the goal line at the near touchline, long lens, shallow depth of field
        const float sg = B.position.x >= 0 ? 1.f : -1.f; Want = ToUE(sg * 41.f, 1.7f, 17.f); Look = ToUE(B.position.x * 0.97f + sg * 2.f, FMath::Max(0.8f, B.position.y), B.position.z * 0.8f); Fov = 36.f; Fstop = 2.8f; return true; }
    case 13: {   // closing pull-back, rising away from the stadium
        Want = ToUE(FMath::Lerp(10.f, 34.f, E), FMath::Lerp(24.f, 78.f, E), FMath::Lerp(56.f, 62.f, E)); Look = ToUE(FMath::Lerp(0.f, -6.f, E), 0.f, 0.f); Fov = FMath::Lerp(44.f, 52.f, E); Fstop = 0.f; return true; }
    case 12: {   // low hero approach: camera on the grass ahead of the runner, looking back up the line
        const FB::Footballer& P = PP(Tgt < 0 ? 4 : Tgt); FB::Vec2 F = P.Speed() > 1.f ? FB::Unit(P.vel) : P.Facing();
        const FVector C = ToUE(P.pos.x, 1.1f, P.pos.y); Want = ToUE(P.pos.x + F.x * 9.f, 0.45f, P.pos.y + F.y * 9.f + 1.5f); Look = C; Fov = 26.f; Fstop = 2.0f; return true; }
    default: break;
    }
    return false;
}
