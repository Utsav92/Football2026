#include "FootballHUD.h"
#include "FootballMatchActor.h"
#include "Engine/Canvas.h"
#include "Engine/Engine.h"
#include "Engine/Font.h"
#include "EngineUtils.h"
#include "CanvasItem.h"

static FLinearColor Kit(const FB::ColorRGB& C) { return FLinearColor(C.r, C.g, C.b); }

void AFootballHUD::Box(float X, float Y, float W, float H, const FLinearColor& C) { if (Canvas) { FCanvasTileItem T(FVector2D(X, Y), FVector2D(W, H), C); T.BlendMode = SE_BLEND_Translucent; Canvas->DrawItem(T); } }

void AFootballHUD::Txt(const FString& S, float X, float Y, const FLinearColor& C, float Scale, bool bCentre)
{
    if (!Canvas) return;
    Scale *= 1.55f;
    UFont* F = GEngine->GetLargeFont(); float W = 0, H = 0; Canvas->TextSize(F, S, W, H, Scale, Scale);
    FCanvasTextItem T(FVector2D(bCentre ? X - W * 0.5f : X, Y), FText::FromString(S), F, C); T.Scale = FVector2D(Scale, Scale);
    T.EnableShadow(FLinearColor(0, 0, 0, 0.9f)); Canvas->DrawItem(T);
}

void AFootballHUD::Arrow(const FVector2D& Tip, float S, const FLinearColor& C)
{
    if (!Canvas) return;
    FCanvasTriangleItem Tri(Tip, Tip + FVector2D(-S * 0.6f, -S), Tip + FVector2D(S * 0.6f, -S), GWhiteTexture); Tri.SetColor(C); Tri.BlendMode = SE_BLEND_Translucent; Canvas->DrawItem(Tri);
    FCanvasTriangleItem Out(Tip + FVector2D(0, 3), Tip + FVector2D(-S * 0.6f - 3, -S - 2), Tip + FVector2D(S * 0.6f + 3, -S - 2), GWhiteTexture); Out.SetColor(FLinearColor(0, 0, 0, 0.55f)); Out.BlendMode = SE_BLEND_Translucent; Canvas->DrawItem(Out);
    Canvas->DrawItem(Tri);
}

void AFootballHUD::DrawHUD()
{
    Super::DrawHUD();
    if (!Match) { TActorIterator<AFootballMatchActor> It(GetWorld()); if (It) Match = *It; }
    if (!Match || !Match->GetSim() || !Canvas) return;
    DrawMarkers(); DrawScoreboard(); DrawClock(); DrawMinimap(); DrawBanner(); DrawCommentary();
    if (Match->IsPaused()) DrawMenu();
}

void AFootballHUD::DrawScoreboard()
{
    const FB::MatchSimulation& S = *Match->GetSim(); const float X = 24, Y = 20, H = 44;
    const FLinearColor H1 = Kit(S.teams[0].setup.primary), A1 = Kit(S.teams[1].setup.primary);
    Box(X, Y, 330, H, FLinearColor(0.02f, 0.03f, 0.06f, 0.82f));
    Box(X, Y, 8, H, H1); Txt(UTF8_TO_TCHAR(S.teams[0].setup.shortName.c_str()), X + 20, Y + 8, FLinearColor::White, 0.9f);
    Box(X + 88, Y, 100, H, FLinearColor(0.95f, 0.95f, 0.95f, 0.95f));
    Txt(FString::Printf(TEXT("%d  -  %d"), S.score.home, S.score.away), X + 138, Y + 8, FLinearColor(0.02f, 0.02f, 0.08f), 1.0f, true);
    Txt(UTF8_TO_TCHAR(S.teams[1].setup.shortName.c_str()), X + 204, Y + 8, FLinearColor::White, 0.9f); Box(X + 322, Y, 8, H, A1);
}

void AFootballHUD::DrawClock()
{
    const FB::MatchSimulation& S = *Match->GetSim(); const FB::MatchClock& C = S.clock; const float W = 190, X = Canvas->ClipX - W - 24, Y = 20;
    const float gs = C.gameSeconds; FString T;
    if (C.InAddedTime()) T = FString::Printf(TEXT("%d+%d:%02d"), int(C.NominalEnd()) / 60, int(gs - C.NominalEnd()) / 60, int(gs - C.NominalEnd()) % 60);
    else T = FString::Printf(TEXT("%02d:%02d"), int(gs) / 60, int(gs) % 60);
    const TCHAR* Per = C.half == 1 ? TEXT("1ST HALF") : C.half == 2 ? TEXT("2ND HALF") : C.half == 3 ? TEXT("EXTRA TIME 1") : TEXT("EXTRA TIME 2");
    Box(X, Y, W, 44, FLinearColor(0.02f, 0.03f, 0.06f, 0.82f)); Box(X, Y, 5, 44, FLinearColor(1.f, 0.82f, 0.1f));
    Txt(T, X + 22, Y + 7, FLinearColor::White, 1.0f); Txt(Per, X + 110, Y + 16, FLinearColor(0.75f, 0.82f, 1.f), 0.5f);
    if (C.addedSeconds > 0 && !C.InAddedTime()) Txt(FString::Printf(TEXT("+%d"), int(C.addedSeconds / 60)), X + 110, Y + 2, FLinearColor(1.f, 0.82f, 0.1f), 0.45f);
}

void AFootballHUD::DrawMarkers()
{
    const FB::MatchSimulation& S = *Match->GetSim(); APlayerController* PC = GetOwningPlayerController(); if (!PC) return;
    const float Time = GetWorld()->GetTimeSeconds(); const float Bob = 4.f * FMath::Sin(Time * 6.f);
    auto Head = [&](int i, FVector2D& Out) { const FB::Footballer& P = S.players[i]; return PC->ProjectWorldLocationToScreen(FVector(P.pos.x * 100.f, P.pos.y * 100.f, 215.f), Out, false); };
    const int Side = Match->HumanSide(); if (Side < 0) return;
    const int C = S.teams[Side].controlled; if (C < 0 || !S.players[C].onPitch) return;
    FVector2D Sc;
    // Pass target (same rule the sim uses for the human kick: aim = stick direction or facing).
    int Tgt = Match->PassTarget(); if (Tgt >= 0 && Head(Tgt, Sc)) {
        Arrow(Sc + FVector2D(0, Bob * 0.5f - 6), 16.f, FLinearColor(0.2f, 0.85f, 1.f)); }
    if (Head(C, Sc)) {
        const bool HasBall = S.ballOwner == C; const FLinearColor Col = HasBall ? FLinearColor(1.f, 0.88f, 0.1f) : FLinearColor(1.f, 1.f, 1.f);
        Arrow(Sc + FVector2D(0, Bob - 6), HasBall ? 24.f : 20.f, Col);
    }
}

void AFootballHUD::DrawMinimap()
{
    const FB::MatchSimulation& S = *Match->GetSim(); const float W = 260, H = W * (2 * FB::Pitch::HalfWidth) / (2 * FB::Pitch::HalfLength) + 8, X = Canvas->ClipX - W - 24, Y = Canvas->ClipY - H - 24;
    const float Hl = FB::Pitch::HalfLength, Hw = FB::Pitch::HalfWidth, PX = X + 6, PY = Y + 6, PW = W - 12, PH = H - 12;
    Box(X, Y, W, H, FLinearColor(0.02f, 0.05f, 0.03f, 0.78f)); Box(PX, PY, PW, PH, FLinearColor(0.05f, 0.30f, 0.08f, 0.85f));
    const FLinearColor L(1, 1, 1, 0.55f);
    Box(PX, PY, PW, 1.5f, L); Box(PX, PY + PH - 1.5f, PW, 1.5f, L); Box(PX, PY, 1.5f, PH, L); Box(PX + PW - 1.5f, PY, 1.5f, PH, L); Box(PX + PW / 2 - 0.75f, PY, 1.5f, PH, L);
    const float Dir = 1.f;   // fixed orientation: matches the broadcast camera (home attacks left to right)
    auto Map = [&](float x, float z) { return FVector2D(PX + (x * Dir / Hl * 0.5f + 0.5f) * PW, PY + (z * Dir / Hw * 0.5f + 0.5f) * PH); };
    const int Side = Match->HumanSide(); const int C = Side >= 0 ? S.teams[Side].controlled : -1, Tgt = Match->PassTarget();
    for (int i = 0; i < 22; ++i) {
        const FB::Footballer& P = S.players[i]; if (!P.onPitch) continue;
        const FVector2D M = Map(P.pos.x, P.pos.y); FLinearColor Col = Kit(S.teams[(int)P.team].setup.primary); if (P.role == FB::Role::GK) Col = FLinearColor(0.95f, 0.8f, 0.1f);
        const float R = (i == C) ? 6.f : (i == Tgt ? 6.f : 4.f);
        if (i == C) Box(M.X - R - 2, M.Y - R - 2, 2 * R + 4, 2 * R + 4, FLinearColor::White); else if (i == Tgt) Box(M.X - R - 2, M.Y - R - 2, 2 * R + 4, 2 * R + 4, FLinearColor(0.2f, 0.85f, 1.f));
        Box(M.X - R, M.Y - R, 2 * R, 2 * R, Col);
    }
    const FVector2D B = Map(S.ball.position.x, S.ball.position.z); Box(B.X - 3, B.Y - 3, 6, 6, FLinearColor::White); Box(B.X - 2, B.Y - 2, 4, 4, FLinearColor(0.1f, 0.1f, 0.1f));
}

void AFootballHUD::DrawBanner()
{
    const FB::Phase& P = Match->GetSim()->phase; FString T;
    switch (P.kind) { case FB::Phase::GoalCelebration: T = TEXT("GOAL!"); break; case FB::Phase::HalfTime: T = TEXT("HALF TIME"); break; case FB::Phase::FullTime: T = TEXT("FULL TIME"); break; default: return; }
    Box(0, Canvas->ClipY * 0.38f, Canvas->ClipX, 90, FLinearColor(0, 0, 0, 0.55f)); Txt(T, Canvas->ClipX / 2, Canvas->ClipY * 0.38f + 14, FLinearColor(1.f, 0.88f, 0.1f), 2.2f, true);
}

void AFootballHUD::DrawMenu()
{
    const float W = 520, H = 400, X = (Canvas->ClipX - W) / 2, Y = (Canvas->ClipY - H) / 2;
    Box(0, 0, Canvas->ClipX, Canvas->ClipY, FLinearColor(0, 0, 0, 0.55f)); Box(X, Y, W, H, FLinearColor(0.03f, 0.05f, 0.1f, 0.95f)); Box(X, Y, W, 6, FLinearColor(1.f, 0.82f, 0.1f));
    Txt(TEXT("PAUSED"), X + W / 2, Y + 24, FLinearColor::White, 1.5f, true);
    const TArray<FString> Items = Match->MenuLabels(); const int Sel = Match->MenuSelection();
    for (int i = 0; i < Items.Num(); ++i) {
        const float Iy = Y + 100 + i * 52; const bool On = i == Sel;
        Box(X + 30, Iy - 4, W - 60, 44, On ? FLinearColor(1.f, 0.82f, 0.1f, 0.95f) : FLinearColor(1, 1, 1, 0.07f));
        Txt(Items[i], X + W / 2, Iy + 4, On ? FLinearColor(0.02f, 0.02f, 0.08f) : FLinearColor::White, 0.8f, true);
    }
    Txt(TEXT("UP/DOWN select    LEFT/RIGHT/ENTER change    ESC resume"), X + W / 2, Y + H - 34, FLinearColor(0.7f, 0.78f, 1.f), 0.4f, true);
}

void AFootballHUD::DrawCommentary()
{
    const FFootballCommentary& C = Match->Commentary(); if (C.Line().IsEmpty() || !C.ShowsText()) return;
    const float A = C.LineAlpha(); const float W = FMath::Min(Canvas->ClipX - 560.f, 760.f), X = (Canvas->ClipX - W) / 2 - 120.f, Y = Canvas->ClipY - 92.f;
    Box(X, Y, W, 56, FLinearColor(0.02f, 0.03f, 0.06f, 0.78f * A)); Box(X, Y, 6, 56, FLinearColor(1.f, 0.82f, 0.1f, A));
    Txt(C.Line(), X + 18, Y + 14, FLinearColor(1.f, 1.f, 1.f, A), 0.56f);
}
