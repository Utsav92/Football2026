#pragma once
#include "CoreMinimal.h"
#include "GameFramework/HUD.h"
#include "FootballHUD.generated.h"

class AFootballMatchActor;

/** In-match overlay: scoreboard (top-left), match clock (top-right), possession arrow + pass-target marker above players,
 *  radar minimap (bottom-right) and the Esc pause menu with side selection. */
UCLASS()
class AFootballHUD : public AHUD
{
    GENERATED_BODY()
public:
    virtual void DrawHUD() override;
private:
    UPROPERTY() TObjectPtr<AFootballMatchActor> Match;
    void Box(float X, float Y, float W, float H, const FLinearColor& C);
    void Txt(const FString& S, float X, float Y, const FLinearColor& C, float Scale = 1.f, bool bCentre = false);
    void Arrow(const FVector2D& Tip, float Size, const FLinearColor& C);
    void DrawScoreboard(); void DrawClock(); void DrawMarkers(); void DrawMinimap(); void DrawBanner(); void DrawCommentary(); void DrawMenu();
};
