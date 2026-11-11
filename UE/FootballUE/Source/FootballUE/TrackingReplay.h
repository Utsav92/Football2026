#pragma once
#include "CoreMinimal.h"

/** Loads a replay produced by Tools/metrica_to_unreal.py (int16 centimetres, 25 Hz, slots 0-13 home, 14-27 away, 28 ball).
 *  LOCAL RESEARCH ONLY: the Metrica sample declares no licence, so this data is read from outside Content and never packaged. */
struct FTrackingReplay
{
    static constexpr int32 NumSlots = 29, BallSlot = 28, HomeSlots = 14;
    static constexpr float Hz = 25.f;
    int32 Frames = 0; int32 Period2Start = 0; TArray<int16> Data; TArray<int32> Jersey; FString Source;

    bool Load(const FString& PathNoExt, FString& Error);
    bool Get(int32 Frame, int32 Slot, FVector2D& OutCm) const
    {
        const int32 K = (Frame * NumSlots + Slot) * 2; const int16 X = Data[K], Y = Data[K + 1];
        if (X == -32768) return false; OutCm = FVector2D(X, Y); return true;
    }
    /** Interpolated position at fractional frame; false if either neighbour is missing (player not on the pitch / masked artefact). */
    bool Sample(float FrameF, int32 Slot, FVector2D& OutCm) const;
};
