#include "CkTests/GroundNav/CkGroundNav_MatchedBenchmarkActor.h"

#include "CkCore/Validation/CkIsValid.h"
#include "CkCrowd/Agent/CkCrowdAgent_Fragment_Data.h"
#include "CkCrowd/Agent/CkCrowdAgent_Utils.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcsExt/Transform/CkTransform_Utils.h"
#include "CkGroundNav/Path/CkGroundNavPath_Fragment_Data.h"
#include "CkGroundNav/Path/CkGroundNavPath_Utils.h"
#include "CkGroundNav/Volume/CkGroundNavVolume_Utils.h"
#include "CkJolt/StaticWorld/CkJoltStaticWorld_Utils.h"
#include "CkJolt/StaticWorld/CkJoltStaticActor_Utils.h"
#include "CkNavigation/NavSurface/CkNavSurface_Utils.h"
#include "CkNavigation/Settings/CkNav_ProjectSettings.h"
#include "CkNavigation/Utils/CkNav_Utils.h"
#include "CkPhysics/Acceleration/CkAcceleration_Utils.h"
#include "CkPhysics/EulerIntegrator/CkEulerIntegrator_Utils.h"
#include "CkPhysics/Velocity/CkVelocity_Utils.h"
#include "CkShapes/CkShapes_Utils.h"

#include <Dom/JsonObject.h>
#include <Components/StaticMeshComponent.h>
#include <Engine/StaticMesh.h>
#include <Engine/StaticMeshActor.h>
#include <EngineUtils.h>
#include <HAL/PlatformTime.h>
#include <HAL/PlatformProperties.h>
#include <HAL/PlatformMisc.h>
#include <HAL/PlatformProcess.h>
#include <HAL/IConsoleManager.h>
#include <Misc/App.h>
#include <Misc/Paths.h>
#include <Misc/SecureHash.h>
#include <NavMesh/RecastNavMesh.h>
#include <Serialization/JsonSerializer.h>
#include <Serialization/JsonWriter.h>
#include <Policies/CondensedJsonPrintPolicy.h>

namespace ck_groundnav_matched_benchmark
{
    constexpr float GAgentRadius = 42.0f;
    constexpr float GAgentHeight = 192.0f;
    constexpr float GAgentHalfHeight = 96.0f;
    constexpr float GProjectionXyTolerance = 25.0f;
    constexpr float GProjectionZTolerance = 2.0f;
    constexpr double GWallTimeoutSeconds = 90.0;
    constexpr double GWarmupSeconds = 3.0;
    constexpr double GSampleSeconds = 6.0;
    const FName GFloorTag(TEXT("CkTests.GroundNavBenchmark.Floor"));
    const TCHAR* GFixture = TEXT("/CkTests/GroundNavBenchmark/Maps/GroundNavMatchedBenchmark");

    auto VectorJson(const FVector& V) -> TArray<TSharedPtr<FJsonValue>>
    {
        return {MakeShared<FJsonValueNumber>(V.X), MakeShared<FJsonValueNumber>(V.Y), MakeShared<FJsonValueNumber>(V.Z)};
    }

    auto IsClose(const FVector& A, const FVector& B, float Tolerance) -> bool
    { return FMath::Abs(A.X - B.X) <= Tolerance && FMath::Abs(A.Y - B.Y) <= Tolerance; }

    auto ProviderName(ECk_NavSurface_Provider Provider) -> const TCHAR*
    { return Provider == ECk_NavSurface_Provider::GroundNav ? TEXT("GroundNav") : TEXT("Recast"); }

    auto ModeName(ECk_GroundNav_BenchmarkMode Mode) -> const TCHAR*
    { return Mode == ECk_GroundNav_BenchmarkMode::QueryBurst128 ? TEXT("QueryBurst128") : TEXT("CrowdConvergence240"); }

    auto StatusName(ECk_Nav_PathStatus Status) -> FString
    {
        return Status == ECk_Nav_PathStatus::Ready ? TEXT("Ready") :
            Status == ECk_Nav_PathStatus::Partial ? TEXT("Partial") : TEXT("Failed");
    }

    auto StatusName(ECk_GroundNav_PathStatus Status) -> FString
    { return Status == ECk_GroundNav_PathStatus::Ready ? TEXT("Ready") : Status == ECk_GroundNav_PathStatus::Partial ? TEXT("Partial") : TEXT("Failed"); }

    auto FixtureHash() -> FString
    {
        const auto Filename = FPaths::ConvertRelativePathToFull(FPaths::ProjectPluginsDir() /
            TEXT("CkTests/Content/GroundNavBenchmark/Maps/GroundNavMatchedBenchmark.umap"));
        const auto Hash = FMD5Hash::HashFile(*Filename);
        return Hash.IsValid() ? FString::Printf(TEXT("md5:%s"), *LexToString(Hash)) : TEXT("md5:unavailable");
    }

    auto ReadCVar(const TCHAR* Name) -> FString
    {
        const auto* CVar = IConsoleManager::Get().FindConsoleVariable(Name);
        return CVar != nullptr ? CVar->GetString() : TEXT("unavailable");
    }

    auto ProviderHealthName(ECk_NavSurface_ProviderHealth Health) -> const TCHAR*
    {
        switch (Health)
        {
            case ECk_NavSurface_ProviderHealth::Ready: return TEXT("Ready");
            case ECk_NavSurface_ProviderHealth::Building: return TEXT("Building");
            case ECk_NavSurface_ProviderHealth::NoData: return TEXT("NoData");
            default: return TEXT("Error");
        }
    }

    auto RestoreDebugCVars(const TMap<FString, FString>& InValues, const TMap<FString, uint32>& InSetByFlags) -> void
    {
        for (const auto& Value : InValues)
        {
            IConsoleVariable* CVar = IConsoleManager::Get().FindConsoleVariable(*Value.Key);
            const uint32* SetByFlags = InSetByFlags.Find(Value.Key);
            if (CVar != nullptr && SetByFlags != nullptr)
            { CVar->Set(*Value.Value, static_cast<EConsoleVariableFlags>(*SetByFlags)); }
        }
    }
}

ACk_GroundNav_MatchedBenchmarkActor::ACk_GroundNav_MatchedBenchmarkActor()
{
    PrimaryActorTick.bCanEverTick = true;
    PrimaryActorTick.bStartWithTickEnabled = true;
    bReplicates = false;
}

auto ACk_GroundNav_MatchedBenchmarkActor::BeginPlay() -> void
{
    Super::BeginPlay();
    // Deliberately idle: a benchmark must be explicitly commanded by its test agent.
}

auto ACk_GroundNav_MatchedBenchmarkActor::EndPlay(EEndPlayReason::Type InEndPlayReason) -> void
{
    Do_Cleanup();
    Super::EndPlay(InEndPlayReason);
}

bool ACk_GroundNav_MatchedBenchmarkActor::Request_Run(ECk_NavSurface_Provider InProvider, ECk_GroundNav_BenchmarkMode InMode)
{
    if ((InProvider != ECk_NavSurface_Provider::Recast && InProvider != ECk_NavSurface_Provider::GroundNav) ||
        (InMode != ECk_GroundNav_BenchmarkMode::QueryBurst128 && InMode != ECk_GroundNav_BenchmarkMode::CrowdConvergence240))
    { return false; }
    if (_Phase != EPhase::Idle && _Phase != EPhase::Finished)
    { return false; }
    if (!Do_IsRuntimeWorld())
    { return false; }

    _RequestedProvider = InProvider;
    _PriorProvider = UCk_Utils_NavSurface_UE::Get_Provider(this);
    _PriorProviderHealth = UCk_Utils_NavSurface_UE::Get_ProviderHealth(this);
    _PriorProviderWasSettled = UCk_Utils_NavSurface_UE::Get_IsSurfaceSettled(this);
    if (_PriorProviderHealth == ECk_NavSurface_ProviderHealth::Building || _PriorProviderHealth == ECk_NavSurface_ProviderHealth::Error ||
        UCk_Utils_NavSurface_UE::Get_IsBuildInProgress(this))
    { return false; }
    _Mode = InMode;
    _Phase = EPhase::Staging;
    _Frame = _ReadyCount = _PartialCount = _FailedCount = _GoalFailures = _OffSurface = _CrowdReached = 0;
    _CrowdReplannedAgents.Reset();
    _CrowdTerminalStates.Reset();
    _EndpointProviderIndex = 0;
    _FixtureValidated = _EndpointProof = _ProviderRestored = _DidPass = _CleanupStarted = _CrowdTerminalFrozen = false;
    _StartedSeconds = FPlatformTime::Seconds();
    _CleanupStartedSeconds = 0.0;
    _CrowdElapsedSeconds = 0.0;
    _FailureReason.Reset(); _Report.Reset(); _QuerySamples.Reset(); _CompletionHistogram.Reset(); _FrameMs.Reset();
    _WorkloadEntities.Reset(); _CrowdAgents.Reset(); _RetiringEntities.Reset(); _RetiringOwner = {};
    _BodiesBakedByHarness.Reset(); _CrowdObservedLocations.Reset(); _OffSurfaceAgents.Reset(); _CrowdObservationCursor = 0;
    _DebugSettings.Reset(); _DebugEffectiveSettings.Reset(); _DebugSetByFlags.Reset();
    _DebugSettingsRestored = true;
    _SchedulerSettings = {
        {TEXT("Recast.MaxPathQueriesPerFrame"), LexToString(UCk_Utils_Nav_Settings_UE::Get_MaxPathQueriesPerFrame())},
        {TEXT("ck.Nav.MaxDeferralSeconds"), ck_groundnav_matched_benchmark::ReadCVar(TEXT("ck.Nav.MaxDeferralSeconds"))},
        {TEXT("ck.GroundNav.MaxSearchesPerFrame"), ck_groundnav_matched_benchmark::ReadCVar(TEXT("ck.GroundNav.MaxSearchesPerFrame"))},
        {TEXT("ck.GroundNav.SliceBudgetMs"), ck_groundnav_matched_benchmark::ReadCVar(TEXT("ck.GroundNav.SliceBudgetMs"))},
        {TEXT("ck.GroundNav.MaxIterationsPerSlice"), ck_groundnav_matched_benchmark::ReadCVar(TEXT("ck.GroundNav.MaxIterationsPerSlice"))},
        {TEXT("ck.GroundNav.MaxDeferralSeconds"), ck_groundnav_matched_benchmark::ReadCVar(TEXT("ck.GroundNav.MaxDeferralSeconds"))}};
    for (const auto& Setting : _SchedulerSettings)
    {
        if (Setting.Value == TEXT("unavailable")) { Do_SetFailure(TEXT("required scheduler setting is unavailable")); return true; }
    }
    static const TCHAR* DebugCVarNames[] = {
        TEXT("ck.GroundNav.Debug.RetainedDraw"), TEXT("ck.GroundNav.Debug.DrawMarkup"),
        TEXT("ck.GroundNav.PathDiagnostics"), TEXT("ck.GroundNav.Debug.CellSearchTiming")};
    for (const TCHAR* Name : DebugCVarNames)
    {
        IConsoleVariable* CVar = IConsoleManager::Get().FindConsoleVariable(Name);
        if (CVar == nullptr) { Do_SetFailure(TEXT("required debug setting is unavailable")); return true; }
        const FString Key(Name);
        _DebugSettings.Add(Key, CVar->GetString());
        _DebugSetByFlags.Add(Key, CVar->GetFlags() & ECVF_SetByMask);
    }
    for (const TCHAR* Name : DebugCVarNames)
    {
        IConsoleVariable* CVar = IConsoleManager::Get().FindConsoleVariable(Name);
        const uint32* SetByFlags = _DebugSetByFlags.Find(FString(Name));
        if (CVar == nullptr || SetByFlags == nullptr)
        {
            ck_groundnav_matched_benchmark::RestoreDebugCVars(_DebugSettings, _DebugSetByFlags);
            Do_SetFailure(TEXT("required debug setting disappeared before it could be disabled"));
            return true;
        }
        CVar->Set(0, static_cast<EConsoleVariableFlags>(*SetByFlags));
        if (CVar->GetInt() != 0)
        {
            ck_groundnav_matched_benchmark::RestoreDebugCVars(_DebugSettings, _DebugSetByFlags);
            Do_SetFailure(TEXT("required debug setting could not be disabled"));
            return true;
        }
        _DebugEffectiveSettings.Add(Name, CVar->GetString());
    }
    _DebugSettingsRestored = false;
    _Owner = {}; _Volume = {};
    return true;
}

bool ACk_GroundNav_MatchedBenchmarkActor::Get_IsFinished() const { return _Phase == EPhase::Finished; }
bool ACk_GroundNav_MatchedBenchmarkActor::Get_DidPass() const { return _DidPass; }
FString ACk_GroundNav_MatchedBenchmarkActor::Get_Report() const { return _Report; }

auto ACk_GroundNav_MatchedBenchmarkActor::Tick(float InDeltaSeconds) -> void
{
    Super::Tick(InDeltaSeconds);
    if (_Phase == EPhase::Idle || _Phase == EPhase::Finished) { return; }
    ++_Frame;
    if (_Phase != EPhase::Cleanup && FPlatformTime::Seconds() - _StartedSeconds > ck_groundnav_matched_benchmark::GWallTimeoutSeconds)
    { Do_SetFailure(TEXT("wall-time budget exceeded before benchmark completion")); }

    switch (_Phase)
    {
        case EPhase::Staging:
            if (Do_ValidateFixture() && Do_StageFixtureBodies() && Do_CreateGroundNavField()) { _Phase = EPhase::BodyReadiness; }
            break;
        case EPhase::BodyReadiness:
            if (ck::IsValid(_Owner)) { _Phase = EPhase::FieldSettle; }
            else { Do_SetFailure(TEXT("transient owner was not created")); }
            break;
        case EPhase::FieldSettle:
            if (UCk_Utils_GroundNavVolume_UE::Get_IsBuilt(_Volume) && UCk_Utils_NavSurface_UE::Get_IsSurfaceSettled(this)) { _Phase = EPhase::ProviderReadiness; }
            break;
        case EPhase::ProviderReadiness:
            UCk_Utils_NavSurface_UE::Request_SetProvider(this, _RequestedProvider);
            if (Do_ProviderIsReady(_RequestedProvider)) { _Phase = EPhase::EndpointProof; }
            break;
        case EPhase::EndpointProof:
            if (Do_AdvanceEndpointProof()) { _Phase = EPhase::Run; }
            break;
        case EPhase::Run:
            if (_Mode == ECk_GroundNav_BenchmarkMode::QueryBurst128)
            {
                if (_QuerySamples.IsEmpty()) { if (!Do_StartQueryBurst()) { Do_SetFailure(TEXT("query workload could not be issued")); } }
                else { Do_PollQueryBurst(); }
            }
            else if (_CrowdAgents.IsEmpty())
            {
                if (!Do_StartCrowd()) { Do_SetFailure(TEXT("crowd workload could not be issued")); }
            }
            else { Do_PollCrowd(InDeltaSeconds); }
            break;
        case EPhase::Cleanup:
            Do_Cleanup();
            {
                const auto RestoredHealth = UCk_Utils_NavSurface_UE::Get_ProviderHealth(this);
                const bool SurfaceRestored = _PriorProviderHealth == ECk_NavSurface_ProviderHealth::NoData
                    ? RestoredHealth == ECk_NavSurface_ProviderHealth::NoData && !UCk_Utils_NavSurface_UE::Get_IsBuildInProgress(this)
                    : RestoredHealth == ECk_NavSurface_ProviderHealth::Ready && UCk_Utils_NavSurface_UE::Get_IsSurfaceSettled(this);
                if (_ProviderRestored && _DebugSettingsRestored && Do_AreOwnedEntitiesRetired() && SurfaceRestored) { Do_Finish(_FailureReason.IsEmpty(), _FailureReason); }
                else if (FPlatformTime::Seconds() - _CleanupStartedSeconds > 10.0)
                { Do_Finish(false, _FailureReason.IsEmpty() ? TEXT("cleanup surface/provider did not settle before wall escape") : _FailureReason); }
            }
            break;
        default: break;
    }
}

auto ACk_GroundNav_MatchedBenchmarkActor::Do_ValidateFixture() -> bool
{
    using namespace ck_groundnav_matched_benchmark;
    struct FExpected { FName Tag; FVector Location; FVector Scale; };
    if (!GetWorld()->GetMapName().EndsWith(TEXT("GroundNavMatchedBenchmark")))
    { Do_SetFailure(TEXT("benchmark actor is not running in GroundNavMatchedBenchmark")); return false; }
    const TArray<FExpected> Expected{{GFloorTag, {0,0,-50}, {36,24,1}},
        {FName(TEXT("CkTests.GroundNavBenchmark.Pillar0")), {-350,-350,150}, {1.5,1.5,3}},
        {FName(TEXT("CkTests.GroundNavBenchmark.Pillar1")), {-350,350,150}, {1.5,1.5,3}},
        {FName(TEXT("CkTests.GroundNavBenchmark.Pillar2")), {350,-350,150}, {1.5,1.5,3}},
        {FName(TEXT("CkTests.GroundNavBenchmark.Pillar3")), {350,350,150}, {1.5,1.5,3}}};
    for (const auto& Need : Expected)
    {
        AStaticMeshActor* Found = nullptr;
        for (TActorIterator<AStaticMeshActor> It(GetWorld()); It; ++It)
        {
            if (It->Tags.Contains(Need.Tag)) { if (Found != nullptr) { Do_SetFailure(TEXT("fixture tag is not unique")); return false; } Found = *It; }
        }
        if (!IsValid(Found) || Found->GetStaticMeshComponent()->GetStaticMesh() == nullptr ||
            Found->GetStaticMeshComponent()->GetStaticMesh()->GetPathName() != TEXT("/Engine/BasicShapes/Cube.Cube") ||
            Found->GetStaticMeshComponent()->Mobility != EComponentMobility::Static ||
            Found->GetStaticMeshComponent()->GetCollisionEnabled() == ECollisionEnabled::NoCollision ||
            Found->GetStaticMeshComponent()->GetCollisionProfileName() != TEXT("BlockAll") ||
            !Found->GetStaticMeshComponent()->CanEverAffectNavigation() ||
            !Found->GetActorLocation().Equals(Need.Location, 0.01f) || !Found->GetActorRotation().Equals(FRotator::ZeroRotator, 0.01f) ||
            !Found->GetActorScale3D().Equals(Need.Scale, 0.01f))
        { Do_SetFailure(FString::Printf(TEXT("fixture geometry/collision/tag validation failed for %s"), *Need.Tag.ToString())); return false; }
    }
    int32 StaticCollisionMeshCount = 0;
    for (TActorIterator<AStaticMeshActor> It(GetWorld()); It; ++It)
    {
        const auto* Component = It->GetStaticMeshComponent();
        if (IsValid(Component) && Component->Mobility == EComponentMobility::Static && Component->GetCollisionEnabled() != ECollisionEnabled::NoCollision)
        { ++StaticCollisionMeshCount; }
    }
    if (StaticCollisionMeshCount != Expected.Num()) { Do_SetFailure(TEXT("fixture contains extra or missing static collision meshes")); return false; }
    int32 HarnessCount = 0;
    for (TActorIterator<AActor> It(GetWorld()); It; ++It)
    { HarnessCount += It->Tags.Contains(FName(TEXT("CkTests.GroundNavBenchmark.Harness"))) ? 1 : 0; }
    if (HarnessCount != 1) { Do_SetFailure(TEXT("fixture harness tag count is not exactly one")); return false; }
    ARecastNavMesh* Recast = nullptr;
    for (TActorIterator<ARecastNavMesh> It(GetWorld()); It; ++It)
    {
        if (Recast != nullptr) { Do_SetFailure(TEXT("fixture has more than one Recast nav data actor")); return false; }
        Recast = *It;
    }
    if (!IsValid(Recast) || !FMath::IsNearlyEqual(Recast->GetConfig().AgentRadius, GAgentRadius) ||
        !FMath::IsNearlyEqual(Recast->GetConfig().AgentHeight, GAgentHeight))
    { Do_SetFailure(TEXT("fixture Recast agent radius/height does not match the 42/192 profile")); return false; }
    if (FixtureHash() == TEXT("md5:unavailable")) { Do_SetFailure(TEXT("fixture saved map hash is unavailable")); return false; }
    _FixtureValidated = true;
    return true;
}

auto ACk_GroundNav_MatchedBenchmarkActor::Do_StageFixtureBodies() -> bool
{
    for (TActorIterator<AStaticMeshActor> It(GetWorld()); It; ++It)
    {
        if (!It->Tags.Contains(ck_groundnav_matched_benchmark::GFloorTag) && !It->Tags.Contains(FName(TEXT("CkTests.GroundNavBenchmark.Pillar0"))) &&
            !It->Tags.Contains(FName(TEXT("CkTests.GroundNavBenchmark.Pillar1"))) && !It->Tags.Contains(FName(TEXT("CkTests.GroundNavBenchmark.Pillar2"))) && !It->Tags.Contains(FName(TEXT("CkTests.GroundNavBenchmark.Pillar3")))) { continue; }
        FVector BoundsOrigin = FVector::ZeroVector;
        FVector BoundsExtent = FVector::ZeroVector;
        It->GetActorBounds(false, BoundsOrigin, BoundsExtent);
        const bool IsFloor = It->Tags.Contains(ck_groundnav_matched_benchmark::GFloorTag);
        const FVector Start = BoundsOrigin + FVector(0.0, 0.0, BoundsExtent.Z + 10.0);
        const FVector End = IsFloor ? BoundsOrigin - FVector(0.0, 0.0, BoundsExtent.Z + 10.0) : BoundsOrigin - FVector(0.0, 0.0, BoundsExtent.Z - 1.0);
        const auto Probe = UCk_Utils_JoltStaticWorld_UE::Get_RayCastStaticWorld(this, Start, End);
        if (Probe.Get_HasHit())
        {
            const auto Attribution = ck::StaticCast<FCk_Handle_JoltStaticActor>(Probe.Get_Entity());
            if (ck::Is_NOT_Valid(Attribution) || UCk_Utils_JoltStaticActor_UE::Get_SourceActor(Attribution) != *It)
            { Do_SetFailure(TEXT("fixture has pre-existing or wrongly attributed Jolt static bodies")); return false; }
            continue;
        }
        if (UCk_Utils_JoltStaticWorld_UE::Request_BakeActor(*It) < 1)
        { Do_SetFailure(TEXT("fixture actor could not be staged into Jolt")); return false; }
        _BodiesBakedByHarness.Add(*It);
    }
    return true;
}

auto ACk_GroundNav_MatchedBenchmarkActor::Do_CreateGroundNavField() -> bool
{
    using namespace ck_groundnav_matched_benchmark;
    _Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(this);
    if (ck::Is_NOT_Valid(_Owner)) { Do_SetFailure(TEXT("could not create benchmark owner")); return false; }
    auto Config = FCk_GroundNav_BakeConfig{25.0f, 10.0f}; Config.Set_TileSizeUu(800.0f);
    auto Profile = FCk_GroundNav_AgentProfile{UCk_Utils_Shapes_UE::Make_Capsule(FCk_ShapeCapsule_Dimensions{GAgentHalfHeight, GAgentRadius})};
    Profile.Set_LedgeSensitivity(0.0f);
    auto Params = FCk_Fragment_GroundNavVolume_ParamsData{FBox(FVector(-1800,-1200,-100), FVector(1800,1200,400)), Config, Profile};
    Params.Set_AutoBuildOnSetup(ECk_EnableDisable::Disable);
    _Volume = UCk_Utils_GroundNavVolume_UE::Add(_Owner, Params);
    if (ck::Is_NOT_Valid(_Volume)) { Do_SetFailure(TEXT("could not create GroundNav bake volume")); return false; }
    UCk_Utils_GroundNavVolume_UE::Request_Build(_Volume, {}, {});
    return true;
}

auto ACk_GroundNav_MatchedBenchmarkActor::Do_ProviderIsReady(ECk_NavSurface_Provider InProvider) const -> bool
{
    return UCk_Utils_NavSurface_UE::Get_Provider(this) == InProvider &&
        UCk_Utils_NavSurface_UE::Get_ProviderHealth(this) == ECk_NavSurface_ProviderHealth::Ready &&
        UCk_Utils_NavSurface_UE::Get_IsSurfaceSettled(this);
}

auto ACk_GroundNav_MatchedBenchmarkActor::Do_AdvanceEndpointProof() -> bool
{
    using namespace ck_groundnav_matched_benchmark;
    static const ECk_NavSurface_Provider Providers[] = {ECk_NavSurface_Provider::Recast, ECk_NavSurface_Provider::GroundNav};
    if (_EndpointProviderIndex >= UE_ARRAY_COUNT(Providers)) { UCk_Utils_NavSurface_UE::Request_SetProvider(this, _RequestedProvider); _EndpointProof = true; return Do_ProviderIsReady(_RequestedProvider); }
    const auto Provider = Providers[_EndpointProviderIndex];
    UCk_Utils_NavSurface_UE::Request_SetProvider(this, Provider);
    if (!Do_ProviderIsReady(Provider)) { return false; }
    auto ProvePoint = [this, Provider](const FVector& Point, int32 Index) -> bool
    {
        auto Query = FCk_NavSurface_ProjectionQuery{Point}; Query.Set_Mode(ECk_NavSurface_ProjectionMode::Closest); Query.Set_SearchHalfExtents({GAgentRadius, GAgentRadius, GAgentHeight});
        const auto Result = UCk_Utils_NavSurface_UE::Try_ProjectPoint(this, Query);
        if (Result.Get_Status() == ECk_NavSurface_QueryStatus::Success && IsClose(Result.Get_Location(), Point, GProjectionXyTolerance) &&
            FMath::Abs(Result.Get_Location().Z - Point.Z) <= GProjectionZTolerance) { return true; }
        Do_SetFailure(FString::Printf(TEXT("endpoint proof failed for %s at workload point %d"), ProviderName(Provider), Index));
        return false;
    };
    if (_Mode == ECk_GroundNav_BenchmarkMode::QueryBurst128)
    {
        for (int32 Index = 0; Index < 128; ++Index)
        {
            const double A = 2.0 * UE_DOUBLE_PI * double(Index) / 128.0;
            const FVector Start{1400.0 * FMath::Cos(A), 900.0 * FMath::Sin(A), 0.0};
            if (!ProvePoint(Start, 2 * Index) || !ProvePoint(FVector{-Start.X, -Start.Y, 0.0}, 2 * Index + 1)) { return false; }
        }
    }
    else
    {
        const double Step = 2.0 * UE_DOUBLE_PI / 40.0;
        for (int32 Ring = 0; Ring < 6; ++Ring) for (int32 I = 0; I < 40; ++I)
        {
            const double Radius = 750.0 + 50.0 * Ring;
            const double A = Step * double(I) + ((Ring & 1) ? Step * 0.5 : 0.0);
            const FVector Start{Radius * FMath::Cos(A), Radius * FMath::Sin(A), 0.0};
            const int32 Index = Ring * 40 + I;
            if (!ProvePoint(Start, 2 * Index) || !ProvePoint(FVector{-Start.X, -Start.Y, 0.0}, 2 * Index + 1)) { return false; }
        }
    }
    ++_EndpointProviderIndex;
    return false;
}

auto ACk_GroundNav_MatchedBenchmarkActor::Do_StartQueryBurst() -> bool
{
    using namespace ck_groundnav_matched_benchmark;
    const double Now = FPlatformTime::Seconds();
    for (int32 Index = 0; Index < 128; ++Index)
    {
        const double A = 2.0 * UE_DOUBLE_PI * double(Index) / 128.0;
        FQuerySample Sample;
        Sample.Start = {1400.0 * FMath::Cos(A), 900.0 * FMath::Sin(A), 0.0};
        Sample.End = {-Sample.Start.X, -Sample.Start.Y, 0.0};
        if (Sample.Start.ContainsNaN() || Sample.End.ContainsNaN()) { return false; }
        Sample.IssueFrame = _Frame;
        Sample.IssueSeconds = Now;
        auto Entity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(_Owner);
        if (ck::Is_NOT_Valid(Entity)) { return false; }
        _WorkloadEntities.Add(Entity);
        UCk_Utils_Transform_UE::Add(Entity, FTransform(Sample.Start), ECk_Replication::DoesNotReplicate);
        if (_RequestedProvider == ECk_NavSurface_Provider::GroundNav)
        {
            auto Path = UCk_Utils_GroundNavPath_UE::Add(Entity, FCk_Fragment_GroundNavPath_ParamsData{GAgentRadius});
            if (ck::Is_NOT_Valid(Path)) { return false; }
            UCk_Utils_GroundNavPath_UE::Request_FindPath(Path, FCk_Request_GroundNavPath_FindPath{Sample.Start, Sample.End}, {});
        }
        else { UCk_Utils_Nav_UE::Request_FindPath(Entity, FCk_Request_Nav_FindPath{Sample.End}, {}); }
        _QuerySamples.Add(MoveTemp(Sample));
    }
    _CompletionHistogram.SetNumZeroed(1);
    return _QuerySamples.Num() == 128;
}

auto ACk_GroundNav_MatchedBenchmarkActor::Do_PollQueryBurst() -> void
{
    for (int32 Index = 0; Index < _QuerySamples.Num(); ++Index)
    {
        auto& Sample = _QuerySamples[Index]; if (Sample.Complete) { continue; }
        if (_RequestedProvider == ECk_NavSurface_Provider::GroundNav)
        {
            const auto Path = ck::StaticCast<FCk_Handle_GroundNavPath>(_WorkloadEntities[Index]);
            if (!UCk_Utils_GroundNavPath_UE::Get_HasFreshResult(Path)) { continue; }
            const auto Result = UCk_Utils_GroundNavPath_UE::Get_Result(Path);
            Sample.Status = ck_groundnav_matched_benchmark::StatusName(Result.Get_Status()); Sample.Length = float(Result.Get_LengthUu());
            Sample.HasSearchTiming = Result.Get_HasSearchDuration();
            Sample.SearchMs = Sample.HasSearchTiming ? Result.Get_SearchDurationMs() : 0.0f;
        }
        else
        {
            const auto Result = UCk_Utils_Nav_UE::Get_PathResult(_WorkloadEntities[Index]);
            if (Result.Get_Status() == ECk_Nav_PathStatus::None || Result.Get_Status() == ECk_Nav_PathStatus::Pending) { continue; }
            Sample.Status = ck_groundnav_matched_benchmark::StatusName(Result.Get_Status());
            for (int32 P = 1; P < Result.Get_Waypoints().Num(); ++P) { Sample.Length += FVector::Distance(Result.Get_Waypoints()[P - 1], Result.Get_Waypoints()[P]); }
            Sample.HasSearchTiming = Result.Get_Diagnostics().Get_HasQueryDuration();
            Sample.SearchMs = Sample.HasSearchTiming ? Result.Get_Diagnostics().Get_LastQueryDurationMs() : 0.0f;
        }
        Sample.Complete = true; Sample.LatencyFrames = _Frame - Sample.IssueFrame; Sample.LatencyMs = float((FPlatformTime::Seconds() - Sample.IssueSeconds) * 1000.0);
        if (!FMath::IsFinite(Sample.LatencyMs) || Sample.LatencyMs < 0.0f || !FMath::IsFinite(Sample.Length) || Sample.Length < 0.0f ||
            !Sample.HasSearchTiming || !FMath::IsFinite(Sample.SearchMs) || Sample.SearchMs < 0.0f)
        { Do_SetFailure(TEXT("query result lacks finite measured duration, latency, or path length")); return; }
        if (_CompletionHistogram.Num() <= Sample.LatencyFrames) { _CompletionHistogram.SetNumZeroed(Sample.LatencyFrames + 1, EAllowShrinking::No); }
        ++_CompletionHistogram[Sample.LatencyFrames];
        if (Sample.Status == TEXT("Ready")) { ++_ReadyCount; } else if (Sample.Status == TEXT("Partial")) { ++_PartialCount; } else { ++_FailedCount; }
    }
    if (_ReadyCount + _PartialCount + _FailedCount == 128)
    {
        if (_ReadyCount != 128) { Do_SetFailure(FString::Printf(TEXT("query terminal mix ready=%d partial=%d failed=%d"), _ReadyCount, _PartialCount, _FailedCount)); }
        else { _Phase = EPhase::Cleanup; }
    }
}

auto ACk_GroundNav_MatchedBenchmarkActor::Do_StartCrowd() -> bool
{
    const double Step = 2.0 * UE_DOUBLE_PI / 40.0;
    for (int32 Ring = 0; Ring < 6; ++Ring) for (int32 I = 0; I < 40; ++I)
    {
        const double Radius = 750.0 + 50.0 * Ring;
        const double A = Step * double(I) + ((Ring & 1) ? Step * 0.5 : 0.0);
        const FVector Start{Radius * FMath::Cos(A), Radius * FMath::Sin(A), 0.0};
        const FVector Goal{-Start.X, -Start.Y, 0.0};
        if (Start.ContainsNaN() || Goal.ContainsNaN()) { return false; }
        auto Entity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(_Owner); if (ck::Is_NOT_Valid(Entity)) { return false; }
        _WorkloadEntities.Add(Entity);
        auto Transform = UCk_Utils_Transform_UE::Add(Entity, FTransform((Goal - Start).Rotation(), Start), ECk_Replication::DoesNotReplicate);
        if (ck::Is_NOT_Valid(Transform)) { return false; }
        auto Agent = UCk_Utils_CrowdAgent_UE::Add(Transform, FCk_Fragment_CrowdAgent_ParamsData{42.0f, 192.0f});
        if (ck::Is_NOT_Valid(Agent)) { return false; }
        UCk_Utils_Velocity_UE::Add(Entity, FCk_Fragment_Velocity_ParamsData{ECk_LocalWorld::World, FVector::ZeroVector}, ECk_Replication::DoesNotReplicate);
        UCk_Utils_Acceleration_UE::Add(Entity, FCk_Fragment_Acceleration_ParamsData{ECk_LocalWorld::World, FVector::ZeroVector}, ECk_Replication::DoesNotReplicate);
        UCk_Utils_EulerIntegrator_UE::Request_Start(Entity, {}); UCk_Utils_CrowdAgent_UE::Request_MoveTo(Agent, FCk_Request_CrowdAgent_MoveTo{Goal}, {});
        _CrowdAgents.Add(Agent);
    }
    return _CrowdAgents.Num() == 240;
}

auto ACk_GroundNav_MatchedBenchmarkActor::Do_PollCrowd(float InDeltaSeconds) -> void
{
    if (!FMath::IsFinite(InDeltaSeconds) || InDeltaSeconds <= 0.0f) { Do_SetFailure(TEXT("crowd benchmark received non-finite or non-positive delta time")); return; }
    bool AllReady = true;
    if (!_CrowdTerminalFrozen)
    {
        for (int32 Index = 0; Index < _CrowdAgents.Num(); ++Index)
        {
            const auto Agent = ck::StaticCast<FCk_Handle_CrowdAgent>(_CrowdAgents[Index]);
            if (ck::Is_NOT_Valid(Agent)) { Do_SetFailure(TEXT("crowd agent became invalid")); return; }
            if (UCk_Utils_CrowdAgent_UE::Get_IsGoalFailedHold(Agent)) { ++_GoalFailures; }
            const auto State = UCk_Utils_CrowdAgent_UE::Get_MovementState(Agent);
            if (_CrowdElapsedSeconds > 0.0 && State == ECk_CrowdAgent_MovementState::PathPending) { _CrowdReplannedAgents.Add(Index); }
            if (State != ECk_CrowdAgent_MovementState::Walking && !UCk_Utils_CrowdAgent_UE::Get_HasReachedActiveGoal(Agent)) { AllReady = false; }
        }
    }
    if (!_CrowdTerminalFrozen && _GoalFailures != 0) { Do_SetFailure(TEXT("crowd goal-failed hold observed")); return; }
    // Readiness gates entry only. Normal replans remain in the continuous sample;
    // goal-failed hold and captured off-surface observations remain failures.
    if (!_CrowdTerminalFrozen && !AllReady && _CrowdElapsedSeconds == 0.0)
    {
        return;
    }
    if (!_CrowdTerminalFrozen && _CrowdElapsedSeconds == 0.0) { _ReadyCount = 240; }
    _CrowdElapsedSeconds += InDeltaSeconds;
    if (_CrowdElapsedSeconds > ck_groundnav_matched_benchmark::GWarmupSeconds && _CrowdElapsedSeconds <= ck_groundnav_matched_benchmark::GWarmupSeconds + ck_groundnav_matched_benchmark::GSampleSeconds)
    {
        _FrameMs.Add(InDeltaSeconds * 1000.0f);
        for (const FCk_Handle& Entity : _WorkloadEntities)
        {
            const auto Transform = UCk_Utils_Transform_UE::Cast(Entity);
            if (ck::Is_NOT_Valid(Transform))
            { Do_SetFailure(TEXT("crowd entity lost its transform during the sample")); return; }
            _CrowdObservedLocations.Add(UCk_Utils_Transform_UE::Get_EntityCurrentLocation(Transform));
        }
        return;
    }
    if (_CrowdElapsedSeconds <= ck_groundnav_matched_benchmark::GWarmupSeconds + ck_groundnav_matched_benchmark::GSampleSeconds) { return; }
    if (!_CrowdTerminalFrozen)
    {
        _CrowdTerminalFrozen = true;
        _CrowdReached = 0;
        _CrowdTerminalStates.Add(TEXT("Walking"), 0);
        _CrowdTerminalStates.Add(TEXT("PathPending"), 0);
        _CrowdTerminalStates.Add(TEXT("Idle"), 0);
        _CrowdTerminalStates.Add(TEXT("None"), 0);
        for (const FCk_Handle& Handle : _CrowdAgents)
        {
            const auto Agent = ck::StaticCast<FCk_Handle_CrowdAgent>(Handle);
            if (UCk_Utils_CrowdAgent_UE::Get_HasReachedActiveGoal(Agent)) { ++_CrowdReached; }
            const auto State = UCk_Utils_CrowdAgent_UE::Get_MovementState(Agent);
            const FString StateName = State == ECk_CrowdAgent_MovementState::Walking ? TEXT("Walking") :
                State == ECk_CrowdAgent_MovementState::PathPending ? TEXT("PathPending") :
                State == ECk_CrowdAgent_MovementState::Idle ? TEXT("Idle") : TEXT("None");
            ++_CrowdTerminalStates.FindChecked(StateName);
        }
        if (_CrowdTerminalStates.FindChecked(TEXT("None")) != 0) { Do_SetFailure(TEXT("crowd terminal snapshot contains an uninitialized movement state")); return; }
        // End the owned movement episodes at the fixed sample boundary. Deferred
        // validation examines immutable captured positions, not extra live simulation.
        for (FCk_Handle& Handle : _CrowdAgents)
        {
            auto Agent = ck::StaticCast<FCk_Handle_CrowdAgent>(Handle);
            UCk_Utils_CrowdAgent_UE::Request_Stop(Agent, {});
        }
        UE_LOG(LogTemp, Display, TEXT("[NAV-BENCHMARK-BOUNDARY] %s: sample closed; stop requested for %d agents before captured-position validation"), ck_groundnav_matched_benchmark::ProviderName(_RequestedProvider), _CrowdAgents.Num());
    }
    constexpr int32 ObservationsPerCorrectnessTick = 512;
    for (const FCk_Handle& Handle : _CrowdAgents)
    {
        const auto Agent = ck::StaticCast<FCk_Handle_CrowdAgent>(Handle);
        if (ck::Is_NOT_Valid(Agent)) { Do_SetFailure(TEXT("crowd agent became invalid while stopping")); return; }
        if (UCk_Utils_CrowdAgent_UE::Get_MovementState(Agent) != ECk_CrowdAgent_MovementState::Idle) { return; }
    }
    for (int32 Count = 0; Count < ObservationsPerCorrectnessTick && _CrowdObservationCursor < _CrowdObservedLocations.Num(); ++Count, ++_CrowdObservationCursor)
    {
        const int32 AgentIndex = _CrowdObservationCursor % _CrowdAgents.Num();
        const FVector Location = _CrowdObservedLocations[_CrowdObservationCursor];
        auto Query = FCk_NavSurface_ProjectionQuery{Location}; Query.Set_Mode(ECk_NavSurface_ProjectionMode::Closest); Query.Set_SearchHalfExtents({42,42,192}); const auto Projection = UCk_Utils_NavSurface_UE::Try_ProjectPoint(this, Query);
        if (Projection.Get_Status() != ECk_NavSurface_QueryStatus::Success || !ck_groundnav_matched_benchmark::IsClose(Projection.Get_Location(), Location, 25.0f) || FMath::Abs(Projection.Get_Location().Z - Location.Z) > 2.0f) { _OffSurfaceAgents.Add(AgentIndex); }
    }
    if (_CrowdObservationCursor < _CrowdObservedLocations.Num()) { return; }
    _OffSurface = _OffSurfaceAgents.Num();
    if (_FrameMs.IsEmpty()) { Do_SetFailure(TEXT("crowd benchmark sampled no frames")); } else if (_OffSurface != 0) { Do_SetFailure(TEXT("crowd agent projection drift/off-surface observed")); } else { _Phase = EPhase::Cleanup; }
}

auto ACk_GroundNav_MatchedBenchmarkActor::Do_Cleanup() -> void
{
    if (_Phase == EPhase::Idle || _Phase == EPhase::Finished) { return; }
    if (!_CleanupStarted)
    {
        _CleanupStarted = true;
        _CleanupStartedSeconds = FPlatformTime::Seconds();
        for (FCk_Handle& Agent : _CrowdAgents)
        {
            auto Crowd = ck::StaticCast<FCk_Handle_CrowdAgent>(Agent);
            UCk_Utils_CrowdAgent_UE::Request_Stop(Crowd, {});
        }
        _RetiringEntities.Append(_WorkloadEntities);
        for (FCk_Handle& Entity : _WorkloadEntities)
        {
            if (_Mode == ECk_GroundNav_BenchmarkMode::QueryBurst128 && _RequestedProvider == ECk_NavSurface_Provider::GroundNav && ck::IsValid(Entity)) { auto Path = ck::StaticCast<FCk_Handle_GroundNavPath>(Entity); UCk_Utils_GroundNavPath_UE::Request_AbandonPath(Path, FCk_Request_GroundNavPath_AbandonPath{}, {}); }
            else if (_Mode == ECk_GroundNav_BenchmarkMode::QueryBurst128 && ck::IsValid(Entity)) { UCk_Utils_Nav_UE::Request_AbandonPath(Entity, FCk_Request_Nav_AbandonPath{}, {}); }
            UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(Entity, ECk_EntityLifetime_DestructionBehavior::ForceDestroy);
        }
        _WorkloadEntities.Reset();
        _CrowdAgents.Reset();
        if (ck::IsValid(_Owner))
        {
            _RetiringOwner = _Owner;
            UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(_Owner, ECk_EntityLifetime_DestructionBehavior::ForceDestroy);
            _Owner = {};
            _Volume = {};
        }
        for (const auto& Actor : _BodiesBakedByHarness) { if (Actor.IsValid()) { UCk_Utils_JoltStaticWorld_UE::Request_RemoveActor(Actor.Get()); } }
        _BodiesBakedByHarness.Reset();
        ck_groundnav_matched_benchmark::RestoreDebugCVars(_DebugSettings, _DebugSetByFlags);
        UCk_Utils_NavSurface_UE::Request_SetProvider(this, _PriorProvider);
    }
    _ProviderRestored = UCk_Utils_NavSurface_UE::Get_Provider(this) == _PriorProvider;
    _DebugSettingsRestored = true;
    for (const auto& Setting : _DebugSettings)
    {
        const IConsoleVariable* CVar = IConsoleManager::Get().FindConsoleVariable(*Setting.Key);
        const uint32* SetByFlags = _DebugSetByFlags.Find(Setting.Key);
        if (CVar == nullptr || SetByFlags == nullptr || CVar->GetString() != Setting.Value ||
            (CVar->GetFlags() & ECVF_SetByMask) != *SetByFlags)
        { _DebugSettingsRestored = false; break; }
    }
    if (!_DebugSettingsRestored && _FailureReason.IsEmpty()) { _FailureReason = TEXT("debug settings did not restore exactly"); }
}

auto ACk_GroundNav_MatchedBenchmarkActor::Do_AreOwnedEntitiesRetired() const -> bool
{
    if (ck::IsValid(_RetiringOwner, ck::IsValid_Policy_IncludePendingKill{})) { return false; }
    for (const FCk_Handle& Handle : _RetiringEntities)
    {
        if (ck::IsValid(Handle, ck::IsValid_Policy_IncludePendingKill{})) { return false; }
    }
    return true;
}

auto ACk_GroundNav_MatchedBenchmarkActor::Do_SetFailure(FString InReason) -> void
{
    if (_FailureReason.IsEmpty()) { _FailureReason = MoveTemp(InReason); }
    _Phase = EPhase::Cleanup;
}

auto ACk_GroundNav_MatchedBenchmarkActor::Do_Finish(bool InPassed, FString InReason) -> void
{
    _DidPass = InPassed; if (!InReason.IsEmpty()) { _FailureReason = MoveTemp(InReason); }
    _Report = Do_BuildReport(); UE_LOG(LogTemp, Display, TEXT("[NAV-BENCHMARK] %s"), *_Report); _Phase = EPhase::Finished;
}

auto ACk_GroundNav_MatchedBenchmarkActor::Do_BuildReport() -> FString
{
    using namespace ck_groundnav_matched_benchmark;
    const auto Root = MakeShared<FJsonObject>();
    Root->SetNumberField(TEXT("schema"), 1); Root->SetStringField(TEXT("mode"), ModeName(_Mode)); Root->SetStringField(TEXT("provider"), ProviderName(_RequestedProvider));
    Root->SetStringField(TEXT("purpose"), TEXT("local-correctness")); Root->SetStringField(TEXT("fixture"), GFixture); Root->SetNumberField(TEXT("fixtureVersion"), 1); Root->SetStringField(TEXT("fixtureHash"), FixtureHash());
    Root->SetNumberField(TEXT("agentRadius"), GAgentRadius); Root->SetNumberField(TEXT("agentHeight"), GAgentHeight); Root->SetStringField(TEXT("machine"), FPlatformProcess::ComputerName()); Root->SetStringField(TEXT("config"), LexToString(FApp::GetBuildConfiguration()));
    Root->SetStringField(TEXT("environment"), GetWorld()->WorldType == EWorldType::PIE ? TEXT("PIE") : TEXT("Game")); Root->SetBoolField(TEXT("eligible"), _DidPass); Root->SetStringField(TEXT("failureReason"), _FailureReason); Root->SetBoolField(TEXT("providerRestored"), _ProviderRestored); Root->SetBoolField(TEXT("fixtureValidated"), _FixtureValidated); Root->SetBoolField(TEXT("endpointProof"), _EndpointProof);
    Root->SetStringField(TEXT("priorProviderHealth"), ProviderHealthName(_PriorProviderHealth)); Root->SetStringField(TEXT("restoredProviderHealth"), ProviderHealthName(UCk_Utils_NavSurface_UE::Get_ProviderHealth(this))); Root->SetBoolField(TEXT("priorProviderWasSettled"), _PriorProviderWasSettled);
    TArray<TSharedPtr<FJsonValue>> Samples;
    for (int32 I = 0; I < _QuerySamples.Num(); ++I) { const auto& S = _QuerySamples[I]; auto O = MakeShared<FJsonObject>(); O->SetNumberField(TEXT("index"), I); O->SetArrayField(TEXT("start"), VectorJson(S.Start)); O->SetArrayField(TEXT("end"), VectorJson(S.End)); O->SetNumberField(TEXT("latencyFrames"), S.LatencyFrames); O->SetNumberField(TEXT("latencyMs"), S.LatencyMs); O->SetNumberField(TEXT("searchMs"), S.SearchMs); O->SetBoolField(TEXT("hasSearchTiming"), S.HasSearchTiming); O->SetNumberField(TEXT("length"), S.Length); O->SetStringField(TEXT("status"), S.Status); Samples.Add(MakeShared<FJsonValueObject>(O)); }
    Root->SetArrayField(TEXT("querySamples"), Samples);
    TArray<TSharedPtr<FJsonValue>> Histogram; for (int32 V : _CompletionHistogram) { Histogram.Add(MakeShared<FJsonValueNumber>(V)); } Root->SetArrayField(TEXT("completionHistogram"), Histogram);
    TArray<TSharedPtr<FJsonValue>> Frames; for (float V : _FrameMs) { Frames.Add(MakeShared<FJsonValueNumber>(V)); } Root->SetArrayField(TEXT("frameMs"), Frames);
    const auto SchedulerSettings = MakeShared<FJsonObject>();
    Root->SetNumberField(TEXT("crowdReplannedAgents"), _CrowdReplannedAgents.Num());
    const auto CrowdTerminalStates = MakeShared<FJsonObject>();
    for (const auto& State : _CrowdTerminalStates) { CrowdTerminalStates->SetNumberField(State.Key, State.Value); }
    Root->SetObjectField(TEXT("crowdTerminalStates"), CrowdTerminalStates);
    for (const auto& Setting : _SchedulerSettings) { SchedulerSettings->SetStringField(Setting.Key, Setting.Value); }
    Root->SetObjectField(TEXT("schedulerSettings"), SchedulerSettings);
    const auto DebugSettings = MakeShared<FJsonObject>();
    for (const auto& Setting : _DebugSettings) { DebugSettings->SetStringField(Setting.Key, Setting.Value); }
    Root->SetObjectField(TEXT("debugSettings"), DebugSettings);
    const auto DebugEffectiveSettings = MakeShared<FJsonObject>();
    for (const auto& Setting : _DebugEffectiveSettings) { DebugEffectiveSettings->SetStringField(Setting.Key, Setting.Value); }
    Root->SetObjectField(TEXT("debugEffectiveSettings"), DebugEffectiveSettings); Root->SetBoolField(TEXT("debugRestored"), _DebugSettingsRestored);
    Root->SetNumberField(TEXT("ready"), _ReadyCount); Root->SetNumberField(TEXT("partial"), _PartialCount); Root->SetNumberField(TEXT("failed"), _FailedCount); Root->SetNumberField(TEXT("completions"), _Mode == ECk_GroundNav_BenchmarkMode::QueryBurst128 ? _ReadyCount + _PartialCount + _FailedCount : _CrowdReached); Root->SetNumberField(TEXT("goalFailures"), _GoalFailures); Root->SetNumberField(TEXT("offSurface"), _OffSurface);
    float Sum = 0.0f, Max = 0.0f; for (float V : _FrameMs) { Sum += V; Max = FMath::Max(Max, V); } TArray<float> Sorted = _FrameMs; Sorted.Sort(); const float P95 = Sorted.IsEmpty() ? 0.0f : Sorted[FMath::Clamp(FMath::CeilToInt(0.95f * Sorted.Num()) - 1, 0, Sorted.Num() - 1)];
    Root->SetNumberField(TEXT("avgFrameMs"), _FrameMs.IsEmpty() ? 0.0f : Sum / _FrameMs.Num()); Root->SetNumberField(TEXT("p95FrameMs"), P95); Root->SetNumberField(TEXT("maxFrameMs"), Max); Root->SetNumberField(TEXT("fps"), Sum > 0.0f ? 1000.0f * _FrameMs.Num() / Sum : 0.0f);
    Root->SetStringField(TEXT("timingScope"), _Mode == ECk_GroundNav_BenchmarkMode::QueryBurst128 ? TEXT("end-to-end issue-to-observed-terminal; measured search duration required") : TEXT("raw per-frame delta during 3s warmup then 6s sample; projection validation is deferred over captured sample locations"));
    FString Out;
    const auto Writer = TJsonWriterFactory<TCHAR, TCondensedJsonPrintPolicy<TCHAR>>::Create(&Out);
    FJsonSerializer::Serialize(Root, Writer);
    return Out;
}

auto ACk_GroundNav_MatchedBenchmarkActor::Do_IsRuntimeWorld() const -> bool { return GetWorld() != nullptr && (GetWorld()->WorldType == EWorldType::PIE || GetWorld()->WorldType == EWorldType::Game); }
