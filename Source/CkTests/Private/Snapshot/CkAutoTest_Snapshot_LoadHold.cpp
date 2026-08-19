#include "CkTests/Snapshot/CkAutoTest_Snapshot_LoadHold.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/EntityScript/CkEntityScript_SpawnRecipe.h"
#include "CkEcs/Handle/CkHandle_Utils.h"
#include "CkEcs/Persistence/CkPersistenceHydration.h" // FCk_Delegate_Hydration_OnHydrated
#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "CkEcs/Scheduler/CkProcessorRegistration.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkShapes/CkShapes_Common.h"
#include "CkShapes/Sphere/CkShapeSphere_Fragment_Data.h"

#include "CkSnapshot/CkSnapshot_Utils.h"
#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkSpatialQuery/Probe/CkProbe_Utils.h"

#include "CkTimer/CkTimer_Utils.h"

#include <Engine/GameInstance.h>
#include <Engine/World.h>
#include <GameFramework/WorldSettings.h>
#include <NativeGameplayTags.h>

// --------------------------------------------------------------------------------------------------------------------

CK_REGISTER_PROCESSOR(ck::FProcessor_AutoTest_LoadHold_TimeAccum);

// --------------------------------------------------------------------------------------------------------------------

namespace ck_autotest_snapshot_loadhold
{
    UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_AutoTest_LoadHold_Timer, TEXT("Timer.AutoTest.LoadHold"));
    UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_AutoTest_LoadHold_TriggerProbe, TEXT("Probe.AutoTest.LoadHold.Trigger"));
    UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_AutoTest_LoadHold_OccupantProbe, TEXT("Probe.AutoTest.LoadHold.Occupant"));

    // Both probes sit at the origin with the same radius, so the pair is unambiguously intersecting the instant
    // both bodies exist. What the test measures is WHEN the overlap becomes knowable, never whether the geometry
    // was ambiguous.
    constexpr auto ProbeRadius = 100.0f;

    const auto PendingForeverRowName = FName{TEXT("AutoTest.LoadHold.PendingForever")};
    const auto NotApplicableRowName  = FName{TEXT("AutoTest.LoadHold.NotApplicable")};

    // Process-wide: the readings are taken in the pre-travel world and read in the post-travel one, so nothing
    // entity-scoped or world-scoped survives to carry them.
    FLoadHoldObservations GObservations{};

    auto Get_Observations() -> FLoadHoldObservations&
    {
        return GObservations;
    }

    auto Reset_Observations() -> void
    {
        GObservations = FLoadHoldObservations{};
    }

    // ----------------------------------------------------------------------------------------------------------------

    // Local copy of the harness's recipe resolver: this fixture compiles in every configuration, and the harness
    // header is automation-test-only.
    auto DoResolve_ByRecipe(
        UWorld* InWorld,
        UClass* InScriptClass) -> FCk_Handle
    {
        if (InWorld == nullptr || InScriptClass == nullptr)
        { return {}; }

        auto* Ecs = InWorld->GetSubsystem<UCk_EcsWorld_Subsystem_UE>();
        if (ck::Is_NOT_Valid(Ecs))
        { return {}; }

        auto& CkRegistry = Ecs->Get_Registry();
        auto* Raw = ck::registry_table::TryResolve(CkRegistry.Get_RegistryHandle());
        if (Raw == nullptr)
        { return {}; }

        for (const auto Entity : Raw->view<ck::FFragment_SpawnRecipe>())
        {
            auto Handle = ck::MakeHandle(FCk_Entity{Entity}, CkRegistry);
            if (ck::Is_NOT_Valid(Handle))
            { continue; }

            if (Handle.Get<ck::FFragment_SpawnRecipe>().Get_ScriptClass().Get() == InScriptClass)
            { return Handle; }
        }

        return {};
    }

    auto DoResolve_ClockProbe(UWorld* InWorld) -> FCk_Handle
    {
        return DoResolve_ByRecipe(InWorld, UCk_AutoTest_Snapshot_LoadHoldProbe_EntityScript_UE::StaticClass());
    }

    // ----------------------------------------------------------------------------------------------------------------

    auto TryGet_ProbeTimerElapsedSeconds(
        UWorld* InWorld,
        double& OutElapsedSeconds) -> bool
    {
        OutElapsedSeconds = 0.0;

        const auto Probe = DoResolve_ClockProbe(InWorld);
        if (ck::Is_NOT_Valid(Probe))
        { return false; }

        const auto Timer = UCk_Utils_Timer_UE::TryGet_Timer(Probe, TAG_AutoTest_LoadHold_Timer.GetTag());
        if (ck::Is_NOT_Valid(Timer))
        { return false; }

        OutElapsedSeconds = UCk_Utils_Timer_UE::Get_CurrentTimerValue(Timer).Get_TimeElapsed().Get_Seconds();
        return true;
    }

    auto Take_Sample(UWorld* InWorld) -> FLoadHoldSample
    {
        auto Sample = FLoadHoldSample{};
        if (InWorld == nullptr)
        { return Sample; }

        Sample.Taken = true;
        Sample.GameTimeSeconds = InWorld->GetTimeSeconds();
        Sample.RealTimeSeconds = InWorld->GetRealTimeSeconds();

        if (const auto* Settings = InWorld->GetWorldSettings())
        { Sample.TimeDilation = Settings->GetEffectiveTimeDilation(); }

        if (auto* Ecs = InWorld->GetSubsystem<UCk_EcsWorld_Subsystem_UE>();
            ck::IsValid(Ecs))
        {
            if (const auto* Accum = Ecs->Get_Registry().TryGetContext<ck::FCtx_AutoTest_LoadHold_TimeAccum>();
                Accum != nullptr)
            {
                Sample.AccumulatedSeconds = Accum->_AccumulatedSeconds;
                Sample.AccumTickCount = Accum->_TickCount;
            }
        }

        Sample.TimerResolved = TryGet_ProbeTimerElapsedSeconds(InWorld, Sample.TimerElapsedSeconds);

        return Sample;
    }

    // ----------------------------------------------------------------------------------------------------------------

    auto Get_PendingForeverRowName() -> FName
    {
        return PendingForeverRowName;
    }

    auto Get_NotApplicableRowName() -> FName
    {
        return NotApplicableRowName;
    }

    auto Install_PendingForeverRow() -> void
    {
        ck::FCk_LoadConvergenceRegistry::Register(PendingForeverRowName,
            [](const FCk_Registry&) -> ck::ECk_LoadConvergence
            { return ck::ECk_LoadConvergence::Pending; });
    }

    auto Install_NotApplicableRow() -> void
    {
        ck::FCk_LoadConvergenceRegistry::Register(NotApplicableRowName,
            [](const FCk_Registry&) -> ck::ECk_LoadConvergence
            { return ck::ECk_LoadConvergence::NotApplicable; });
    }

    auto Remove_TestConvergenceRows() -> void
    {
        ck::FCk_LoadConvergenceRegistry::Unregister(PendingForeverRowName);
        ck::FCk_LoadConvergenceRegistry::Unregister(NotApplicableRowName);
    }

    // ----------------------------------------------------------------------------------------------------------------

    auto DoResolve_ProbeUnder(
        UWorld* InWorld,
        UClass* InOwnerScriptClass,
        const FGameplayTag& InProbeName) -> FCk_Handle
    {
        const auto Owner = DoResolve_ByRecipe(InWorld, InOwnerScriptClass);
        if (ck::Is_NOT_Valid(Owner))
        { return {}; }

        for (auto Dependent : UCk_Utils_EntityLifetime_UE::Get_LifetimeDependents(Owner))
        {
            const auto AsProbe = UCk_Utils_Probe_UE::Cast(Dependent);
            if (ck::Is_NOT_Valid(AsProbe))
            { continue; }

            if (UCk_Utils_Probe_UE::Get_Name(AsProbe) != InProbeName)
            { continue; }

            return Dependent;
        }

        return {};
    }

    auto TryGet_TriggerProbe(UWorld* InWorld) -> FCk_Handle
    {
        return DoResolve_ProbeUnder(InWorld,
            UCk_AutoTest_Snapshot_LoadHoldTrigger_EntityScript_UE::StaticClass(),
            TAG_AutoTest_LoadHold_TriggerProbe.GetTag());
    }

    auto TryGet_OccupantProbe(UWorld* InWorld) -> FCk_Handle
    {
        return DoResolve_ProbeUnder(InWorld,
            UCk_AutoTest_Snapshot_LoadHoldOccupant_EntityScript_UE::StaticClass(),
            TAG_AutoTest_LoadHold_OccupantProbe.GetTag());
    }

    auto Get_TriggerContainsOccupant(UWorld* InWorld) -> bool
    {
        auto Trigger = TryGet_TriggerProbe(InWorld);
        const auto Occupant = TryGet_OccupantProbe(InWorld);

        if (ck::Is_NOT_Valid(Trigger) || ck::Is_NOT_Valid(Occupant))
        { return false; }

        const auto TriggerProbe = UCk_Utils_Probe_UE::Cast(Trigger);
        if (ck::Is_NOT_Valid(TriggerProbe))
        { return false; }

        for (const auto& Overlap : UCk_Utils_Probe_UE::Get_CurrentOverlaps(TriggerProbe))
        {
            if (Overlap.Get_OtherEntity() == Occupant)
            { return true; }
        }

        return false;
    }

    // ----------------------------------------------------------------------------------------------------------------

    auto DoMake_ProbeParams(
        const FGameplayTag& InProbeName,
        ECk_MotionType InMotionType) -> FCk_Fragment_Probe_ParamsData
    {
        // Any, not the DifferentContextOnly default: both owners are spawned under the same transient root, so the
        // default policy would refuse the pair for a reason that has nothing to do with convergence.
        return FCk_Fragment_Probe_ParamsData{InProbeName}
            .Set_ContextOverlapPolicy(ECk_Probe_ContextOverlapPolicy::Any)
            .Set_MotionType(InMotionType);
    }
}

// --------------------------------------------------------------------------------------------------------------------

namespace ck
{
    auto
        FProcessor_AutoTest_LoadHold_TimeAccum::
        DoTick(
            TimeType InDeltaT)
        -> void
    {
        // Registry-wide and view-independent: the number under test is what the scheduler handed a non-kernel
        // processor this frame, and it has to be recorded even on the frames where the view is empty.
        auto Registry = _TransientEntity.Get_RegistryView();
        auto& Accum = Registry.SetContext<FCtx_AutoTest_LoadHold_TimeAccum>();
        Accum._AccumulatedSeconds += InDeltaT.Get_Seconds();
        ++Accum._TickCount;

        TProcessor::DoTick(InDeltaT);
    }

    auto
        FProcessor_AutoTest_LoadHold_TimeAccum::
        ForEachEntity(
            TimeType InDeltaT,
            HandleType InHandle)
        -> void
    {
    }
}

// --------------------------------------------------------------------------------------------------------------------

UCk_AutoTest_Snapshot_LoadHoldProbe_EntityScript_UE::
    UCk_AutoTest_Snapshot_LoadHoldProbe_EntityScript_UE()
{
    _Replication = ECk_Replication::DoesNotReplicate;
    _InstancingPolicy = ECk_EntityScript_InstancingPolicy::InstancedPerEntity;
}

auto
    UCk_AutoTest_Snapshot_LoadHoldProbe_EntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams)
    -> ECk_EntityScript_ConstructionFlow
{
    InHandle.AddOrGet<ck::FTag_AutoTest_LoadHold_Probe>();

    UCk_Utils_Timer_UE::Add(InHandle,
        FCk_Fragment_Timer_ParamsData{FCk_Time{ck_autotest_snapshot_loadhold::ProbeTimerDurationSeconds}}
            .Set_TimerName(ck_autotest_snapshot_loadhold::TAG_AutoTest_LoadHold_Timer.GetTag())
            .Set_CountDirection(ECk_Timer_CountDirection::CountUp)
            .Set_Behavior(ECk_Timer_Behavior::PauseOnDone)
            .Set_StartingState(ECk_Timer_State::Running));

    return ECk_EntityScript_ConstructionFlow::Finished;
}

auto
    UCk_AutoTest_Snapshot_LoadHoldProbe_EntityScript_UE::
    BeginPlay()
    -> void
{
    Super::BeginPlay();

    auto Self = Get_AssociatedEntity();
    if (ck::Is_NOT_Valid(Self))
    { return; }

    // Bound on the TIMER, not on this probe. UCk_Utils_Timer_UE::Add puts the timer on a CHILD entity connected
    // through RecordOfTimers, so it carries its own payload and its own hydration — and this probe's OnHydrated
    // fires when THIS entity's payloads are final, which says nothing about the child's. Sampling the timer at
    // the owner's edge reads the fresh-construct value and then attributes the restored value's arrival to the
    // hold, which is a measurement artefact rather than time passing.
    auto Timer = UCk_Utils_Timer_UE::TryGet_Timer(Self,
        ck_autotest_snapshot_loadhold::TAG_AutoTest_LoadHold_Timer.GetTag());

    if (ck::Is_NOT_Valid(Timer))
    { return; }

    auto Delegate = FCk_Delegate_Hydration_OnHydrated{};
    Delegate.BindUFunction(this, TEXT("OnHydrated"));

    UCk_Utils_Snapshot_UE::Promise_OnHydrated(Timer, Delegate);
}

void
    UCk_AutoTest_Snapshot_LoadHoldProbe_EntityScript_UE::
    OnHydrated(
        FCk_Handle InHandle)
{
    auto& Observations = ck_autotest_snapshot_loadhold::Get_Observations();
    ++Observations.OnHydratedFireCount;

    auto* World = UCk_Utils_EntityLifetime_UE::Get_WorldForEntity(InHandle);
    if (ck::Is_NOT_Valid(World))
    { return; }

    Observations.AtHydrated = ck_autotest_snapshot_loadhold::Take_Sample(World);
}

auto
    UCk_AutoTest_Snapshot_LoadHoldProbe_EntityScript_UE::
    Get_IsSnapshotRespawnable() const
    -> bool
{
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

UCk_AutoTest_Snapshot_LoadHoldTrigger_EntityScript_UE::
    UCk_AutoTest_Snapshot_LoadHoldTrigger_EntityScript_UE()
{
    _Replication = ECk_Replication::DoesNotReplicate;
    _InstancingPolicy = ECk_EntityScript_InstancingPolicy::InstancedPerEntity;
}

auto
    UCk_AutoTest_Snapshot_LoadHoldTrigger_EntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams)
    -> ECk_EntityScript_ConstructionFlow
{
    UCk_Utils_Probe_UE::Create(InHandle,
        FTransform::Identity,
        FCk_AnyShape{FCk_ShapeSphere_Dimensions{ck_autotest_snapshot_loadhold::ProbeRadius}},
        ck_autotest_snapshot_loadhold::DoMake_ProbeParams(
            ck_autotest_snapshot_loadhold::TAG_AutoTest_LoadHold_TriggerProbe.GetTag(),
            ECk_MotionType::Static),
        FCk_Probe_DebugInfo{});

    return ECk_EntityScript_ConstructionFlow::Finished;
}

auto
    UCk_AutoTest_Snapshot_LoadHoldTrigger_EntityScript_UE::
    Get_IsSnapshotRespawnable() const
    -> bool
{
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

UCk_AutoTest_Snapshot_LoadHoldOccupant_EntityScript_UE::
    UCk_AutoTest_Snapshot_LoadHoldOccupant_EntityScript_UE()
{
    _Replication = ECk_Replication::DoesNotReplicate;
    _InstancingPolicy = ECk_EntityScript_InstancingPolicy::InstancedPerEntity;
}

auto
    UCk_AutoTest_Snapshot_LoadHoldOccupant_EntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams)
    -> ECk_EntityScript_ConstructionFlow
{
    // Kinematic, because a static pair never generates a contact: the occupant is the moving half of the shape
    // the trigger is watching for.
    UCk_Utils_Probe_UE::Create(InHandle,
        FTransform::Identity,
        FCk_AnyShape{FCk_ShapeSphere_Dimensions{ck_autotest_snapshot_loadhold::ProbeRadius}},
        ck_autotest_snapshot_loadhold::DoMake_ProbeParams(
            ck_autotest_snapshot_loadhold::TAG_AutoTest_LoadHold_OccupantProbe.GetTag(),
            ECk_MotionType::Kinematic),
        FCk_Probe_DebugInfo{});

    return ECk_EntityScript_ConstructionFlow::Finished;
}

auto
    UCk_AutoTest_Snapshot_LoadHoldOccupant_EntityScript_UE::
    Get_IsSnapshotRespawnable() const
    -> bool
{
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

void
    UCk_AutoTest_Snapshot_LoadHoldWitness_UE::
    OnPreLoad(
        FCk_Handle InHandle)
{
    if (_ArmCount > 0)
    { return; }

    ++_ArmCount;

    auto Delegate = FCk_Delegate_Snapshot_OnLoadComplete{};
    Delegate.BindUFunction(this, TEXT("OnLoadComplete"));

    UCk_Utils_Snapshot_UE::Promise_OnLoadComplete(InHandle, Delegate);
}

void
    UCk_AutoTest_Snapshot_LoadHoldWitness_UE::
    OnLoadComplete(
        FCk_Handle InHandle,
        FCk_Snapshot_LoadReport InReport)
{
    auto& Observations = ck_autotest_snapshot_loadhold::Get_Observations();

    ++Observations.FireCount;
    Observations.ResultAtFire = InReport.Get_Result();
    Observations.AccountingClosedAtFire = InReport.Get_IsAccountingClosed();
    Observations.ConvergenceUnmetAtFire = InReport.Get_ConvergenceUnmet().Num();

    auto* World = UCk_Utils_EntityLifetime_UE::Get_WorldForEntity(InHandle);
    if (ck::Is_NOT_Valid(World))
    { return; }

    Observations.AtLoadComplete = ck_autotest_snapshot_loadhold::Take_Sample(World);

    if (_SampleOverlap)
    { _OverlapHeldAtFire = ck_autotest_snapshot_loadhold::Get_TriggerContainsOccupant(World); }

    if (auto* GameInstance = World->GetGameInstance();
        GameInstance != nullptr)
    {
        if (auto* Subsystem = GameInstance->GetSubsystem<UCk_Snapshot_Subsystem_UE>();
            Subsystem != nullptr)
        {
            Observations.ReadyToResumeAtFire = Subsystem->Get_IsReadyToResume();
            Observations.LoadInProgressAtFire = Subsystem->Get_IsLoadInProgress();
        }
    }
}

// --------------------------------------------------------------------------------------------------------------------
