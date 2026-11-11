#include "FootballGameMode.h"
#include "FootballMatchActor.h"
#include "FootballHUD.h"
#include "GameFramework/SpectatorPawn.h"
#include "Engine/World.h"
AFootballGameMode::AFootballGameMode() { DefaultPawnClass = nullptr; HUDClass = AFootballHUD::StaticClass(); }
void AFootballGameMode::BeginPlay()
{
    Super::BeginPlay();
    FActorSpawnParameters P; GetWorld()->SpawnActor<AFootballMatchActor>(FVector::ZeroVector, FRotator::ZeroRotator, P);
}
