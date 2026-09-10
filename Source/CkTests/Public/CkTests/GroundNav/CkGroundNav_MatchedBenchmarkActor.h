#pragma once

#include "CkEcs/Handle/CkHandle.h"
#include "CkCore/Macros/CkMacros.h"
#include "CkGroundNav/Volume/CkGroundNavVolume_Fragment_Data.h"
#include "CkNavigation/NavSurface/CkNavSurface_Fragment_Data.h"

#include <GameFramework/Info.h>

#include "CkGroundNav_MatchedBenchmarkActor.generated.h"

UENUM(BlueprintType)
enum class ECk_GroundNav_BenchmarkMode : uint8
{
    QueryBurst128,
    CrowdConvergence240
};
CK_DEFINE_CUSTOM_FORMATTER_ENUM(ECk_GroundNav_BenchmarkMode);

/**
 * Runtime-only, explicitly commanded comparison harness for the authored GroundNav benchmark map.
 * It does not create or alter fixture geometry.
 */
UCLASS(BlueprintType, Blueprintable)
class CKTESTS_API ACk_GroundNav_MatchedBenchmarkActor : public AInfo
{
    GENERATED_BODY()

public:
    ACk_GroundNav_MatchedBenchmarkActor();

    auto BeginPlay() -> void override;
    auto EndPlay(EEndPlayReason::Type InEndPlayReason) -> void override;
    auto Tick(float InDeltaSeconds) -> void override;

    UFUNCTION(BlueprintCallable, Category = "CkTests|GroundNav|Benchmark")
    bool
    Request_Run(ECk_NavSurface_Provider InProvider, ECk_GroundNav_BenchmarkMode InMode);

    UFUNCTION(BlueprintPure, Category = "CkTests|GroundNav|Benchmark")
    bool
    Get_IsFinished() const;

    UFUNCTION(BlueprintPure, Category = "CkTests|GroundNav|Benchmark")
    bool
    Get_DidPass() const;

    UFUNCTION(BlueprintPure, Category = "CkTests|GroundNav|Benchmark")
    FString
    Get_Report() const;

private:
    enum class EPhase : uint8
    {
        Idle, Staging, BodyReadiness, FieldSettle, ProviderReadiness,
        EndpointProof, Run, Cleanup, Finished
    };

    struct FQuerySample
    {
        FVector Start = FVector::ZeroVector;
        FVector End = FVector::ZeroVector;
        int32 IssueFrame = 0;
        int32 LatencyFrames = 0;
        double IssueSeconds = 0.0;
        float LatencyMs = 0.0f;
        float SearchMs = 0.0f;
        float Length = 0.0f;
        bool HasSearchTiming = false;
        bool Complete = false;
        FString Status = TEXT("Failed");
    };

    auto Do_ValidateFixture() -> bool;
    auto Do_StageFixtureBodies() -> bool;
    auto Do_CreateGroundNavField() -> bool;
    auto Do_ProviderIsReady(ECk_NavSurface_Provider InProvider) const -> bool;
    auto Do_AdvanceEndpointProof() -> bool;
    auto Do_StartQueryBurst() -> bool;
    auto Do_PollQueryBurst() -> void;
    auto Do_StartCrowd() -> bool;
    auto Do_PollCrowd(float InDeltaSeconds) -> void;
    auto Do_Cleanup() -> void;
    auto Do_AreOwnedEntitiesRetired() const -> bool;
    auto Do_Finish(bool InPassed, FString InReason) -> void;
    auto Do_BuildReport() -> FString;
    auto Do_SetFailure(FString InReason) -> void;
    auto Do_IsRuntimeWorld() const -> bool;

private:
    EPhase _Phase = EPhase::Idle;
    ECk_NavSurface_Provider _RequestedProvider = ECk_NavSurface_Provider::Recast;
    ECk_NavSurface_Provider _PriorProvider = ECk_NavSurface_Provider::Recast;
    ECk_GroundNav_BenchmarkMode _Mode = ECk_GroundNav_BenchmarkMode::QueryBurst128;
    FCk_Handle _Owner;
    FCk_Handle_GroundNavVolume _Volume;
    TArray<FCk_Handle> _WorkloadEntities;
    TArray<FCk_Handle> _CrowdAgents;
    TArray<FCk_Handle> _RetiringEntities;
    FCk_Handle _RetiringOwner;
    TArray<TWeakObjectPtr<AActor>> _BodiesBakedByHarness;
    TArray<FQuerySample> _QuerySamples;
    TArray<int32> _CompletionHistogram;
    TArray<float> _FrameMs;
    TArray<FVector> _CrowdObservedLocations;
    TSet<int32> _OffSurfaceAgents;
    TMap<FString, FString> _SchedulerSettings;
    TMap<FString, FString> _DebugSettings;
    TMap<FString, FString> _DebugEffectiveSettings;
    TMap<FString, uint32> _DebugSetByFlags;
    int32 _CrowdObservationCursor = 0;
    int32 _Frame = 0;
    int32 _EndpointProviderIndex = 0;
    int32 _ReadyCount = 0;
    int32 _PartialCount = 0;
    int32 _FailedCount = 0;
    int32 _GoalFailures = 0;
    int32 _OffSurface = 0;
    int32 _CrowdReached = 0;
    TSet<int32> _CrowdReplannedAgents;
    TMap<FString, int32> _CrowdTerminalStates;
    bool _FixtureValidated = false;
    bool _EndpointProof = false;
    bool _ProviderRestored = false;
    bool _PriorProviderWasSettled = false;
    bool _DebugSettingsRestored = true;
    bool _DidPass = false;
    bool _CleanupStarted = false;
    bool _CrowdTerminalFrozen = false;
    double _StartedSeconds = 0.0;
    double _CleanupStartedSeconds = 0.0;
    double _CrowdElapsedSeconds = 0.0;
    ECk_NavSurface_ProviderHealth _PriorProviderHealth = ECk_NavSurface_ProviderHealth::NoData;
    FString _FailureReason;
    FString _Report;
};
