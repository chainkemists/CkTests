#pragma once

#include "CkEcs/Handle/CkHandle.h"
#include "CkGroundNav/Facade/CkGroundNav_WorldFieldRegistry.h"
#include "CkGroundNav/Streaming/CkGroundNav_StreamPartitionLifecycle.h"

#include <GameFramework/Info.h>

#include "CkGroundNav_StreamingAcceptanceActor.generated.h"

/**
 * A local visualization of GroundNav's production stream-partition lifecycle.
 *
 * It creates a deterministic in-memory all-profile source and drives Load, Deactivate, Reactivate,
 * and Unload against the PIE world's stream-partition registry. It does not read manifests, data layers,
 * level streaming, or World Partition, so its verdict is deliberately limited to lifecycle transactions.
 */
UCLASS(BlueprintType, Blueprintable)
class CKTESTS_API ACk_GroundNav_StreamingAcceptanceActor : public AInfo
{
    GENERATED_BODY()

public:
    ACk_GroundNav_StreamingAcceptanceActor();

    auto BeginPlay() -> void override;
    auto EndPlay(EEndPlayReason::Type InEndPlayReason) -> void override;
    auto Tick(float InDeltaSeconds) -> void override;

    UFUNCTION(BlueprintCallable, Exec, Category = "CkTests|GroundNav|Streaming Acceptance")
    void CkGroundNavStreaming_Reset();

    UFUNCTION(BlueprintCallable, Exec, Category = "CkTests|GroundNav|Streaming Acceptance")
    void CkGroundNavStreaming_Load();

    UFUNCTION(BlueprintCallable, Exec, Category = "CkTests|GroundNav|Streaming Acceptance")
    void CkGroundNavStreaming_Deactivate();

    UFUNCTION(BlueprintCallable, Exec, Category = "CkTests|GroundNav|Streaming Acceptance")
    void CkGroundNavStreaming_Reactivate();

    UFUNCTION(BlueprintCallable, Exec, Category = "CkTests|GroundNav|Streaming Acceptance")
    void CkGroundNavStreaming_Unload();

private:
    auto Do_Reset() -> bool;
    auto Do_MakeBundles() -> bool;
    auto Do_MakeTransitions() -> bool;
    auto Do_HasExpectedAllProfileState(bool InExpectedBuilt) const -> bool;
    auto Do_RecordResult(const FString& InAction, bool InPassed, const FString& InDetail) -> void;
    auto Do_RenderStatus() const -> void;
    auto Get_IsRuntimeWorld() const -> bool;

private:
    UPROPERTY(EditAnywhere, Category = "CkTests|GroundNav|Streaming Acceptance", meta = (ClampMin = "1"))
    int32 _StreamingVolumeId = 991001;

    UPROPERTY(EditAnywhere, Category = "CkTests|GroundNav|Streaming Acceptance", meta = (ClampMin = "1"))
    int32 _PartitionId = 1;

    /** Pressing PIE is sufficient: run the complete lifecycle once with a visible pause between steps. */
    UPROPERTY(EditAnywhere, Category = "CkTests|GroundNav|Streaming Acceptance")
    bool _AutoRun = true;

    UPROPERTY(EditAnywhere, Category = "CkTests|GroundNav|Streaming Acceptance", meta = (ClampMin = "0.25"))
    float _AutoStepSeconds = 1.5f;

    FCk_Handle _Owner;
    uint64 _OwnerInstance = 0;
    uint64 _NextGeneration = 1;
    ck::groundnav::FCk_GroundNav_StreamFieldBundle _SourceBundle;
    ck::groundnav::FCk_GroundNav_StreamFieldBundle _TemplateBundle;
    TArray<ck::groundnav::FCk_GroundNav_StreamTileTransition> _Transitions;
    bool _IsRegistered = false;
    bool _IsLoaded = false;
    FString _ResetVerdict = TEXT("PENDING");
    FString _LoadVerdict = TEXT("PENDING");
    FString _DeactivateVerdict = TEXT("PENDING");
    FString _ReactivateVerdict = TEXT("PENDING");
    FString _UnloadVerdict = TEXT("PENDING");
    FString _LastAction = TEXT("Not started");
    FString _LastVerdict = TEXT("PENDING");
    float _AutoElapsedSeconds = 0.0f;
    int32 _AutoStep = 0;
};
