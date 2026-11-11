#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "FootballStadium.generated.h"

class UStaticMeshComponent; class UInstancedStaticMeshComponent; class UTextRenderComponent; class UMaterialInstanceDynamic; class ADirectionalLight; class APostProcessVolume;

UENUM() enum class EFootballTimeOfDay : uint8 { Day, Sunset, Night };

/** Procedural stadium: tiered stands, instanced crowd, roof, floodlights, ad boards, scoreboards, dugouts, sky and the cinematic render setup. */
UCLASS()
class AFootballStadium : public AActor
{
    GENERATED_BODY()
public:
    AFootballStadium();
    void Build(EFootballTimeOfDay InTime);
    void SetScoreText(const FString& Home, const FString& Away, int32 HG, int32 AG, const FString& Clock);
    void TickCrowd(float Time, float Excitement);
    EFootballTimeOfDay TimeOfDay = EFootballTimeOfDay::Day;

private:
    UPROPERTY() TObjectPtr<UStaticMesh> Cube; UPROPERTY() TObjectPtr<UStaticMesh> Sphere; UPROPERTY() TObjectPtr<UStaticMesh> Cylinder;
    UPROPERTY() TObjectPtr<UMaterialInterface> BaseMat;
    UPROPERTY() TArray<TObjectPtr<UInstancedStaticMeshComponent>> CrowdBody;
    UPROPERTY() TArray<TObjectPtr<UTextRenderComponent>> ScoreTexts;
    UPROPERTY() TObjectPtr<ADirectionalLight> Sun;
    float CrowdBaseZ = 0.f;

    UStaticMeshComponent* Box(const FVector& CenterM, const FVector& SizeM, const FLinearColor& C, const FRotator& R = FRotator::ZeroRotator, bool bShadow = true);
    UInstancedStaticMeshComponent* MakeISM(UStaticMesh* M, const FLinearColor& C);
    UTextRenderComponent* Text(const FString& S, const FVector& CenterM, const FRotator& R, float SizeCm, const FLinearColor& C);
    void BuildStands(); void BuildRoofAndTowers(); void BuildAdBoards(); void BuildDugouts(); void BuildScoreboards(); void BuildSky(); void BuildPostProcess();
    static FVector M(float x, float y, float z) { return FVector(x * 100.f, z * 100.f, y * 100.f); }  // sim metres -> UE cm
};
