#pragma once
#include "CoreMinimal.h"
#include "HAL/PlatformProcess.h"
#include "Sim/MatchSimulation.h"

/** Live match commentary driven by the simulation's event stream.
 *  Original template lines filled with match context (names, score, minute); shown as subtitles and optionally spoken with the
 *  macOS system voice (`say`) - no cloud services and no voice cloning. */
class FFootballCommentary
{
public:
    enum class Mode : uint8 { Voice, VoiceText, TextOnly, Off };
    Mode Mode_ = Mode::Voice;   // spoken only by default: no text on screen
    bool ShowsText() const { return Mode_ == Mode::VoiceText || Mode_ == Mode::TextOnly; }

    void Consume(const std::vector<FB::GameEvent>& Events, const FB::MatchSimulation& Sim);
    void Tick(float Dt, const FB::MatchSimulation& Sim);
    const FString& Line() const { return Current; }
    float LineAlpha() const { return Current.IsEmpty() ? 0.f : FMath::Clamp(ShowTimer / 0.4f, 0.f, 1.f); }
    void SetVoiceAllowed(bool b) { bVoice = b; }
    void Shutdown();
    FString ModeLabel() const { return Mode_ == Mode::Voice ? TEXT("Voice only") : Mode_ == Mode::VoiceText ? TEXT("Voice + subtitles") : Mode_ == Mode::TextOnly ? TEXT("Subtitles only") : TEXT("Off"); }
    void CycleMode(int Dir) { Mode_ = (Mode)(((int)Mode_ + (Dir >= 0 ? 1 : 3)) % 4); if (Mode_ == Mode::Off) { Current.Reset(); Queue.Reset(); } }

private:
    struct FLine { FString Text; int32 Priority; float Time; };
    TArray<FLine> Queue; FString Current; float ShowTimer = 0.f, SinceLast = 0.f, SinceSpoke = 0.f; bool bVoice = true;
    FProcHandle Proc; bool bHalfDone[2] = { false, false }; int32 LastMinuteReminder = 0; FRandomStream Rng{ 1234 };
    void Push(const FString& T, int32 Pri, const TCHAR* Key = nullptr, float Cooldown = 0.f); void Speak(const FString& T, int32 Pri);
    // Picks a variant that differs from the last one used for this call site's option set.
    FString Pick(const TArray<FString>& A) { int32 I = Rng.RandRange(0, A.Num() - 1); const uint32 H = GetTypeHash(A[0]); int32* Last = LastPick.Find(H); if (A.Num() > 1 && Last && *Last == I) I = (I + 1 + Rng.RandRange(0, A.Num() - 2)) % A.Num(); LastPick.Add(H, I); return A[I]; }
    TMap<uint32, int32> LastPick; TMap<FString, float> KeyTime; float Clock = 0.f; TArray<FString> Recent;
    int32 PassStreak = 0, StreakTeam = -1; float SinceStreakLine = 99.f;
    static FString Surname(const std::string& N);
};
