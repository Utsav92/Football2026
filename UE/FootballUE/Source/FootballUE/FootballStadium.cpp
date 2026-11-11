#include "FootballStadium.h"
#include "Sim/BallPhysics.h"
#include "Components/StaticMeshComponent.h"
#include "Components/InstancedStaticMeshComponent.h"
#include "Components/TextRenderComponent.h"
#include "Components/DirectionalLightComponent.h"
#include "Components/SkyLightComponent.h"
#include "Components/SkyAtmosphereComponent.h"
#include "Components/ExponentialHeightFogComponent.h"
#include "Components/RectLightComponent.h"
#include "Components/PointLightComponent.h"
#include "Engine/DirectionalLight.h"
#include "Engine/SkyLight.h"
#include "Engine/ExponentialHeightFog.h"
#include "Engine/PostProcessVolume.h"
#include "Engine/RectLight.h"
#include "Engine/StaticMesh.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "UObject/ConstructorHelpers.h"
#include "Engine/World.h"

using namespace FB::Pitch;

AFootballStadium::AFootballStadium()
{
    RootComponent = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
    static ConstructorHelpers::FObjectFinder<UStaticMesh> CubeF(TEXT("/Engine/BasicShapes/Cube.Cube"));
    static ConstructorHelpers::FObjectFinder<UStaticMesh> SphereF(TEXT("/Engine/BasicShapes/Sphere.Sphere"));
    static ConstructorHelpers::FObjectFinder<UStaticMesh> CylF(TEXT("/Engine/BasicShapes/Cylinder.Cylinder"));
    static ConstructorHelpers::FObjectFinder<UMaterialInterface> MatF(TEXT("/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));
    Cube = CubeF.Object; Sphere = SphereF.Object; Cylinder = CylF.Object; BaseMat = MatF.Object;
}

UStaticMeshComponent* AFootballStadium::Box(const FVector& C, const FVector& S, const FLinearColor& Col, const FRotator& R, bool bShadow)
{
    UStaticMeshComponent* K = NewObject<UStaticMeshComponent>(this);
    K->SetStaticMesh(Cube); K->SetupAttachment(RootComponent); K->RegisterComponent();
    K->SetWorldLocationAndRotation(C, R); K->SetWorldScale3D(FVector(S.X, S.Y, S.Z));   // Cube is 100 cm: scale == metres
    K->SetCollisionEnabled(ECollisionEnabled::NoCollision); K->CastShadow = bShadow;
    UMaterialInstanceDynamic* Mi = UMaterialInstanceDynamic::Create(BaseMat, this); Mi->SetVectorParameterValue(TEXT("Color"), Col); K->SetMaterial(0, Mi);
    return K;
}

UInstancedStaticMeshComponent* AFootballStadium::MakeISM(UStaticMesh* Mesh, const FLinearColor& Col)
{
    UInstancedStaticMeshComponent* I = NewObject<UInstancedStaticMeshComponent>(this);
    I->SetStaticMesh(Mesh); I->SetupAttachment(RootComponent); I->RegisterComponent(); I->SetCollisionEnabled(ECollisionEnabled::NoCollision); I->CastShadow = false;
    UMaterialInstanceDynamic* Mi = UMaterialInstanceDynamic::Create(BaseMat, this); Mi->SetVectorParameterValue(TEXT("Color"), Col); I->SetMaterial(0, Mi);
    return I;
}

UTextRenderComponent* AFootballStadium::Text(const FString& S, const FVector& C, const FRotator& R, float SizeCm, const FLinearColor& Col)
{
    UTextRenderComponent* T = NewObject<UTextRenderComponent>(this);
    T->SetupAttachment(RootComponent); T->RegisterComponent(); T->SetText(FText::FromString(S)); T->SetWorldLocationAndRotation(C, R);
    T->SetWorldSize(SizeCm); T->SetHorizontalAlignment(EHTA_Center); T->SetVerticalAlignment(EVRTA_TextCenter); T->SetTextRenderColor(Col.ToFColor(true)); T->CastShadow = false;
    return T;
}

void AFootballStadium::Build(EFootballTimeOfDay InTime)
{
    TimeOfDay = InTime;
    BuildSky(); BuildStands(); BuildRoofAndTowers(); BuildAdBoards(); BuildDugouts(); BuildScoreboards(); BuildPostProcess();
}

void AFootballStadium::BuildStands()
{
    const int Rows = 26; const float Step = 0.85f, Rise = 0.5f, Margin = 7.f, SeatPitch = 0.55f;
    const FLinearColor Concrete(0.30f, 0.31f, 0.34f), Seat(0.10f, 0.12f, 0.18f);
    // 8 shirt colours + 3 skin tones.
    const FLinearColor Shirts[8] = { {0.55f,0.08f,0.08f}, {0.55f,0.55f,0.55f}, {0.08f,0.2f,0.5f}, {0.6f,0.45f,0.08f}, {0.06f,0.06f,0.08f}, {0.1f,0.35f,0.16f}, {0.35f,0.14f,0.35f}, {0.55f,0.28f,0.07f} };
    const FLinearColor Skins[3] = { {0.85f,0.65f,0.5f}, {0.55f,0.38f,0.26f}, {0.3f,0.2f,0.14f} };
    TArray<UInstancedStaticMeshComponent*> Bodies, Heads;
    for (auto& C : Shirts) { Bodies.Add(MakeISM(Cube, C)); } for (auto& C : Skins) { Heads.Add(MakeISM(Sphere, C)); }
    FRandomStream Rng(2026);
    struct Side { bool Along; float Sign; };
    const Side Sides[4] = { {true,-1}, {true,1}, {false,-1}, {false,1} };
    for (const Side& S : Sides) {
        const float Span = S.Along ? (Length + 24.f) : (Width + 2 * (Margin + Rows * Step) );
        for (int r = 0; r < Rows; ++r) {
            const float d = (S.Along ? Margin : Margin + 3.f) + r * Step, h = 0.5f + r * Rise;
            const float off = (S.Along ? HalfWidth : HalfLength) + d + Step / 2;
            const FVector C = S.Along ? M(0, h / 2, S.Sign * off) : M(S.Sign * off, h / 2, 0);
            Box(C, S.Along ? FVector(Span, Step, h) : FVector(Step, Span, h), (r % 2) ? Concrete : Concrete * 0.88f, FRotator::ZeroRotator, false);
            const int N = int(Span / SeatPitch);
            for (int i = 0; i < N; ++i) {
                if (Rng.FRand() > 0.9f) continue;
                const float u = -Span / 2 + (i + 0.5f) * SeatPitch;
                const float jx = Rng.FRandRange(-0.05f, 0.05f);
                const FVector Pos = S.Along ? M(u, h + 0.3f, S.Sign * (off + 0.1f)) : M(S.Sign * (off + 0.1f), h + 0.3f, u);
                // Fans lean forward slightly and stand/sit at random heights.
                const float stand = Rng.FRand() < 0.18f ? 0.45f : 0.f;
                Bodies[Rng.RandHelper(8)]->AddInstance(FTransform(FRotator::ZeroRotator, Pos + FVector(jx*100, 0, stand*100), FVector(0.42f, 0.32f, 0.62f)));
                Heads[Rng.RandHelper(3)]->AddInstance(FTransform(FRotator::ZeroRotator, Pos + FVector(jx*100, 0, (0.55f + stand) * 100), FVector(0.23f)));
            }
        }
        // Back wall / concourse.
        const float back = (S.Along ? HalfWidth : HalfLength) + (S.Along ? Margin : Margin + 3.f) + Rows * Step + 0.6f, hh = 0.5f + Rows * Rise;
        Box(S.Along ? M(0, hh / 2 + 2, S.Sign * back) : M(S.Sign * back, hh / 2 + 2, 0), S.Along ? FVector(Span, 1.2f, hh + 4) : FVector(1.2f, Span, hh + 4), Concrete * 0.7f);
    }
    // Pitch-side fence/apron.
    for (float s : {-1.f, 1.f}) { Box(M(0, 0.4f, s * (HalfWidth + 6.9f)), FVector(Length + 20, 0.3f, 1.4f), Concrete * 0.6f, FRotator::ZeroRotator, false);
                                  Box(M(s * (HalfLength + 9.9f), 0.4f, 0), FVector(0.3f, Width + 14, 1.4f), Concrete * 0.6f, FRotator::ZeroRotator, false); }
    CrowdBody = {}; for (auto* B : Bodies) CrowdBody.Add(B);
}

void AFootballStadium::BuildRoofAndTowers()
{
    const FLinearColor Steel(0.32f, 0.34f, 0.38f), Dark(0.08f, 0.08f, 0.1f);
    const float RoofY = 0.5f + 26 * 0.5f + 8.f;
    // Roof canopies over the rear half of the two long sides and both ends.
    for (float s : {-1.f, 1.f}) {
        Box(M(0, RoofY, s * (HalfWidth + 7 + 18 + 7)), FVector(Length + 26, 16, 0.5f), Steel, FRotator(s * 4.f, 0, 0));
        Box(M(s * (HalfLength + 10 + 18 + 4), RoofY, 0), FVector(14, Width + 40, 0.5f), Steel, FRotator(0, 0, s * -4.f));
        for (float x = -50; x <= 50; x += 25) Box(M(x, RoofY / 2, s * (HalfWidth + 7 + 26 * 0.85f + 3)), FVector(0.6f, 0.6f, RoofY), Steel);
    }
    // Four floodlight towers.
    const bool Night = TimeOfDay == EFootballTimeOfDay::Night;
    for (float sx : {-1.f, 1.f}) for (float sz : {-1.f, 1.f}) {
        const FVector Foot(sx * (HalfLength + 20), 0, sz * (HalfWidth + 26)); const float H = 44.f;
        UStaticMeshComponent* Pole = NewObject<UStaticMeshComponent>(this); Pole->SetStaticMesh(Cylinder); Pole->SetupAttachment(RootComponent); Pole->RegisterComponent();
        Pole->SetWorldLocationAndRotation(M(Foot.X, H / 2, Foot.Z), FRotator::ZeroRotator); Pole->SetWorldScale3D(FVector(0.9f, 0.9f, H));
        UMaterialInstanceDynamic* Mi = UMaterialInstanceDynamic::Create(BaseMat, this); Mi->SetVectorParameterValue(TEXT("Color"), Steel); Pole->SetMaterial(0, Mi); Pole->SetCollisionEnabled(ECollisionEnabled::NoCollision);
        const FVector Head = M(sx * (HalfLength + 20), H + 1, sz * (HalfWidth + 26));
        const FRotator Aim = ((M(0, 0, 0) - Head).Rotation());
        Box(Head, FVector(7, 5, 0.6f), Dark, Aim);
        for (int a = 0; a < 3; ++a) for (int b = 0; b < 4; ++b) Box(Head + Aim.RotateVector(FVector(-30, (b - 1.5f) * 150, (a - 1) * 120)), FVector(0.1f, 1.2f, 0.9f), Night ? FLinearColor(30, 28, 22) : FLinearColor(0.8f, 0.8f, 0.7f), Aim, false);
        if (Night) {
            ARectLight* L = GetWorld()->SpawnActor<ARectLight>(Head + Aim.RotateVector(FVector(-60, 0, 0)), Aim);
            if (L) { URectLightComponent* C = Cast<URectLightComponent>(L->GetLightComponent()); C->SetSourceWidth(900); C->SetSourceHeight(600); C->SetIntensity(9000000.f); C->SetAttenuationRadius(30000.f); C->SetLightColor(FLinearColor(1.f, 0.96f, 0.88f)); C->SetCastShadows(true); }
        }
    }
}

void AFootballStadium::BuildAdBoards()
{
    static const TCHAR* Brands[] = { TEXT("NOVA BANK"), TEXT("AEROLINE"), TEXT("KESTREL"), TEXT("FJORD ENERGY"), TEXT("MERIDIAN"), TEXT("PULSE SPORT"), TEXT("ALTAIR"), TEXT("ORBITEL") };
    static const FLinearColor Cols[] = { {0.85f,0.12f,0.12f}, {0.04f,0.04f,0.05f}, {0.95f,0.55f,0.1f}, {0.2f,0.75f,0.8f}, {0.6f,0.15f,0.7f}, {0.2f,0.7f,0.3f}, {0.3f,0.3f,0.9f}, {0.1f,0.45f,0.85f} };
    int k = 0; const float W = 8.f;
    for (float s : {-1.f, 1.f}) for (float x = -HalfLength - 4; x < HalfLength + 4; x += W) {
        const int b = k++ % 8; const FVector C = M(x + W / 2, 0.5f, s * (HalfWidth + 3.f));
        Box(C, FVector(W - 0.1f, 0.12f, 1.0f), Cols[b], FRotator::ZeroRotator, false);
        Text(Brands[b], C + FVector(0, -s * 8.f, 0), FRotator(0, s > 0 ? -90.f : 90.f, 0), 55.f, FLinearColor::White);
    }
    for (float s : {-1.f, 1.f}) for (float z = -HalfWidth - 3; z < HalfWidth + 3; z += W) {
        const int b = k++ % 8; const FVector C = M(s * (HalfLength + 3.5f), 0.5f, z + W / 2);
        Box(C, FVector(0.12f, W - 0.1f, 1.0f), Cols[b], FRotator::ZeroRotator, false);
        Text(Brands[b], C + FVector(-s * 8.f, 0, 0), FRotator(0, s > 0 ? 180.f : 0.f, 0), 55.f, FLinearColor::White);
    }
}

void AFootballStadium::BuildDugouts()
{
    const FLinearColor Glass(0.5f, 0.6f, 0.7f), Bench(0.1f, 0.1f, 0.12f);
    for (float x : {-8.f, 8.f}) {
        const FVector C = M(x, 1.0f, -(HalfWidth + 5.0f));
        Box(C + FVector(0, -60, 100), FVector(8, 0.15f, 2.0f), Glass, FRotator::ZeroRotator, false);
        Box(C + FVector(0, -20, 215), FVector(8.4f, 2.2f, 0.12f), Bench);
        Box(C + FVector(0, 20, -50), FVector(7, 0.5f, 0.5f), Bench, FRotator::ZeroRotator, false);
    }
}

void AFootballStadium::BuildScoreboards()
{
    for (float s : {-1.f, 1.f}) {
        const float x = s * (HalfLength + 10 + 3 * 0.85f + 26 * 0.85f);
        const FVector C = M(x - s * 1.5f, 0.5f + 26 * 0.5f + 3.f, 0);
        Box(C, FVector(0.4f, 22, 5.5f), FLinearColor(0.01f, 0.01f, 0.015f));
        ScoreTexts.Add(Text(TEXT("ALD 0 - 0 OAK   00:00"), C + FVector(-s * 28.f, 0, 0), FRotator(0, s > 0 ? 180.f : 0.f, 0), 260.f, FLinearColor(1.f, 0.85f, 0.2f)));
    }
}

void AFootballStadium::SetScoreText(const FString& Home, const FString& Away, int32 HG, int32 AG, const FString& Clock)
{
    const FString S = FString::Printf(TEXT("%s %d - %d %s   %s"), *Home, HG, AG, *Away, *Clock);
    for (auto& T : ScoreTexts) if (T) T->SetText(FText::FromString(S));
}

void AFootballStadium::TickCrowd(float Time, float Excitement)
{
    // Cheap crowd life: bob the whole shirt layers slightly; stronger when the ball is near a goal.
    for (int i = 0; i < CrowdBody.Num(); ++i) if (CrowdBody[i]) CrowdBody[i]->SetRelativeLocation(FVector(0, 0, FMath::Sin(Time * (5.f + i * 0.7f) + i) * (1.5f + 5.f * Excitement)));
}

void AFootballStadium::BuildSky()
{
    UWorld* W = GetWorld(); const float Hr = TimeOfDay == EFootballTimeOfDay::Night ? 0.f : 1.f;
    FRotator SunRot = TimeOfDay == EFootballTimeOfDay::Day ? FRotator(-48, -30, 0) : (TimeOfDay == EFootballTimeOfDay::Sunset ? FRotator(-7, -30, 0) : FRotator(-35, -30, 0));
    Sun = W->SpawnActor<ADirectionalLight>(FVector(0, 0, 5000), SunRot);
    if (Sun) { UDirectionalLightComponent* L = Cast<UDirectionalLightComponent>(Sun->GetLightComponent()); L->SetAtmosphereSunLight(true); L->SetCastShadows(true);
        L->SetIntensity(TimeOfDay == EFootballTimeOfDay::Day ? 11.f : (TimeOfDay == EFootballTimeOfDay::Sunset ? 7.f : 0.05f));
        L->SetLightColor(TimeOfDay == EFootballTimeOfDay::Sunset ? FLinearColor(1.f, 0.7f, 0.5f) : FLinearColor(1.f, 0.97f, 0.92f)); }
    if (ADirectionalLight* Fill = W->SpawnActor<ADirectionalLight>(FVector(0, 0, 5000), FRotator(-30, 150, 0))) {   // soft bounce from the opposite side, no shadows
        UDirectionalLightComponent* F = Cast<UDirectionalLightComponent>(Fill->GetLightComponent()); F->SetCastShadows(false); F->SetIntensity(TimeOfDay == EFootballTimeOfDay::Night ? 0.4f : 3.0f); F->SetLightColor(FLinearColor(0.7f, 0.82f, 1.f)); F->SetAtmosphereSunLightIndex(1); }
    W->SpawnActor<ASkyAtmosphere>(FVector::ZeroVector, FRotator::ZeroRotator);
    if (ASkyLight* SL = W->SpawnActor<ASkyLight>(FVector(0, 0, 5000), FRotator::ZeroRotator)) { SL->GetLightComponent()->bRealTimeCapture = true; SL->GetLightComponent()->SetIntensity(Hr > 0 ? 1.f : 0.25f); }
    if (AExponentialHeightFog* F = W->SpawnActor<AExponentialHeightFog>(FVector(0, 0, 0), FRotator::ZeroRotator)) { F->GetComponent()->SetFogDensity(0.0025f); F->GetComponent()->SetFogInscatteringColor(FLinearColor(0.55f, 0.65f, 0.8f)); }
    // Ground beyond the stadium.
    Box(M(0, -1.1f, 0), FVector(900, 900, 1), FLinearColor(0.07f, 0.1f, 0.06f), FRotator::ZeroRotator, false);
}

void AFootballStadium::BuildPostProcess()
{
    if (APostProcessVolume* P = GetWorld()->SpawnActor<APostProcessVolume>(FVector::ZeroVector, FRotator::ZeroRotator)) {
        P->bUnbound = true; FPostProcessSettings& S = P->Settings;
        S.bOverride_AutoExposureMethod = true; S.AutoExposureMethod = AEM_Histogram;
        S.bOverride_AutoExposureMinBrightness = true; S.AutoExposureMinBrightness = TimeOfDay == EFootballTimeOfDay::Night ? 0.5f : 0.8f; S.bOverride_AutoExposureMaxBrightness = true; S.AutoExposureMaxBrightness = TimeOfDay == EFootballTimeOfDay::Night ? 0.9f : 1.6f;
        S.bOverride_AutoExposureBias = true; S.AutoExposureBias = TimeOfDay == EFootballTimeOfDay::Night ? 0.f : 0.f;
        // Lumen (software ray tracing on Metal): GI + reflections, raised quality.
        S.bOverride_DynamicGlobalIlluminationMethod = true; S.DynamicGlobalIlluminationMethod = EDynamicGlobalIlluminationMethod::Lumen;
        S.bOverride_ReflectionMethod = true; S.ReflectionMethod = EReflectionMethod::Lumen;
        S.bOverride_LumenSceneLightingQuality = true; S.LumenSceneLightingQuality = 2.f;
        S.bOverride_LumenSceneDetail = true; S.LumenSceneDetail = 1.5f;
        S.bOverride_LumenFinalGatherQuality = true; S.LumenFinalGatherQuality = 2.f;
        S.bOverride_LumenReflectionQuality = true; S.LumenReflectionQuality = 1.5f;
        S.bOverride_LumenSkylightLeaking = true; S.LumenSkylightLeaking = 0.f;
        // Film look: ACES-style curve, warm highlights / cool shadows, soft bloom, lens fringe, gentle grain + vignette.
        S.bOverride_BloomIntensity = true; S.BloomIntensity = 0.7f; S.bOverride_BloomThreshold = true; S.BloomThreshold = 0.9f;
        S.bOverride_VignetteIntensity = true; S.VignetteIntensity = 0.5f;
        S.bOverride_FilmGrainIntensity = true; S.FilmGrainIntensity = 0.1f; S.bOverride_FilmGrainIntensityHighlights = true; S.FilmGrainIntensityHighlights = 0.05f;
        S.bOverride_ColorSaturation = true; S.ColorSaturation = FVector4(1.08f, 1.08f, 1.08f, 1.f);
        S.bOverride_ColorContrast = true; S.ColorContrast = FVector4(1.06f, 1.06f, 1.06f, 1.f);
        S.bOverride_ColorGainHighlights = true; S.ColorGainHighlights = FVector4(1.04f, 1.0f, 0.93f, 1.f);
        S.bOverride_ColorGainShadows = true; S.ColorGainShadows = FVector4(0.95f, 0.98f, 1.05f, 1.f);
        S.bOverride_FilmSlope = true; S.FilmSlope = 0.88f; S.bOverride_FilmToe = true; S.FilmToe = 0.55f; S.bOverride_FilmShoulder = true; S.FilmShoulder = 0.26f;
        S.bOverride_FilmBlackClip = true; S.FilmBlackClip = 0.f; S.bOverride_FilmWhiteClip = true; S.FilmWhiteClip = 0.04f;
        S.bOverride_AmbientOcclusionIntensity = true; S.AmbientOcclusionIntensity = 0.5f;
        S.bOverride_SceneFringeIntensity = true; S.SceneFringeIntensity = 0.12f;
        S.bOverride_MotionBlurAmount = true; S.MotionBlurAmount = 0.25f;
    }
}
