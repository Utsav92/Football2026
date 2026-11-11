#include "TrackingReplay.h"
#include "Misc/FileHelper.h"
#include "Serialization/JsonSerializer.h"
#include "Dom/JsonObject.h"
#include "Dom/JsonValue.h"

bool FTrackingReplay::Load(const FString& P, FString& Error)
{
    TArray<uint8> Raw;
    if (!FFileHelper::LoadFileToArray(Raw, *(P + TEXT(".bin")))) { Error = FString::Printf(TEXT("cannot read %s.bin (run Tools/metrica_to_unreal.py)"), *P); return false; }
    FString Json; if (!FFileHelper::LoadFileToString(Json, *(P + TEXT(".json")))) { Error = TEXT("cannot read metadata json"); return false; }
    TSharedPtr<FJsonObject> Root; if (!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json), Root) || !Root.IsValid()) { Error = TEXT("bad metadata json"); return false; }
    Frames = (int32)Root->GetNumberField(TEXT("frames"));
    if (Raw.Num() != Frames * NumSlots * 4) { Error = FString::Printf(TEXT("size mismatch: %d bytes for %d frames"), Raw.Num(), Frames); return false; }
    Data.SetNumUninitialized(Raw.Num() / 2); FMemory::Memcpy(Data.GetData(), Raw.GetData(), Raw.Num());   // little-endian int16 on arm64/x86
    Source = Root->GetStringField(TEXT("source"));
    const TSharedPtr<FJsonObject>* Pf; Period2Start = 0;
    if (Root->TryGetObjectField(TEXT("period_frames"), Pf)) { const TArray<TSharedPtr<FJsonValue>>* A; if ((*Pf)->TryGetArrayField(TEXT("2"), A) && A->Num()) Period2Start = (int32)(*A)[0]->AsNumber(); }
    Jersey.Init(0, NumSlots);
    const TSharedPtr<FJsonObject> Slots = Root->GetObjectField(TEXT("slots"));
    for (int Side = 0; Side < 2; ++Side) {
        const TArray<TSharedPtr<FJsonValue>>& L = Slots->GetArrayField(Side == 0 ? TEXT("home") : TEXT("away"));
        for (int i = 0; i < L.Num() && i < HomeSlots; ++i) Jersey[Side * HomeSlots + i] = (int32)L[i]->AsObject()->GetNumberField(TEXT("jersey"));
    }
    return true;
}

bool FTrackingReplay::Sample(float F, int32 Slot, FVector2D& Out) const
{
    const int32 I0 = FMath::Clamp((int32)F, 0, Frames - 1), I1 = FMath::Min(I0 + 1, Frames - 1); const float A = F - I0;
    FVector2D P0, P1; if (!Get(I0, Slot, P0) || !Get(I1, Slot, P1)) return false;
    Out = FMath::Lerp(P0, P1, A); return true;
}
