#pragma once
#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "FootballGameMode.generated.h"
UCLASS()
class AFootballGameMode : public AGameModeBase
{
    GENERATED_BODY()
public:
    AFootballGameMode();
    virtual void BeginPlay() override;
};
