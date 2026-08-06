#include "CkTests/Net/CkAutoTest_NetSubject_EntityScript.h"
#include "CkTests/Net/CkAutoTest_NetSubject.h"

#include "CkAttribute/FloatAttribute/CkFloatAttribute_Fragment_Data.h"
#include "CkAttribute/FloatAttribute/CkFloatAttribute_Utils.h"
#include "CkAttribute/ByteAttribute/CkByteAttribute_Fragment_Data.h"
#include "CkAttribute/ByteAttribute/CkByteAttribute_Utils.h"
#include "CkAttribute/IntegerAttribute/CkIntegerAttribute_Fragment_Data.h"
#include "CkAttribute/IntegerAttribute/CkIntegerAttribute_Utils.h"
#include "CkAttribute/VectorAttribute/CkVectorAttribute_Fragment_Data.h"
#include "CkAttribute/VectorAttribute/CkVectorAttribute_Utils.h"
#include "CkAttribute/RotatorAttribute/CkRotatorAttribute_Fragment_Data.h"
#include "CkAttribute/RotatorAttribute/CkRotatorAttribute_Utils.h"
#include "CkTagSet/CkTagSet_Utils.h"
#include "CkPhysics/Acceleration/CkAcceleration_Utils.h"
#include "CkAnimation/AnimPlan/CkAnimPlan_Utils.h"
#include "CkRelationship/Team/CkTeam_Utils.h"
#include "CkRelationship/Player/CkPlayer_Utils.h"
#include "CkTimer/CkTimer_Utils.h"

#include "CkTests/CkTests_Fragment_Data.h"

#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "GameplayTagContainer.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck::auto_test::netsubject
{
    // FloatAttribute.Health is registered in Config/DefaultGameplayTags.ini and is already used
    // by the standalone CkAttribute AutoTests — reusing it here means we don't need a separate
    // tag-registration commit for the multi-client test.
    constexpr auto AttributeTagName = TEXT("FloatAttribute.Health");

    // Distinctive initial value baked into the attribute on both worlds. Picked so that the
    // post-override value (set from the test spec) is something *different* than this; that lets
    // an unreplicated override show up as a clear cross-world mismatch instead of accidentally
    // matching by coincidence.
    constexpr auto InitialValue = 42.5f;

    // Bracket the initial value so no clamping fires during Construct. Clamping is its own
    // replication path and out of scope for the basic value-replicates test.
    constexpr auto MinValue = 0.0f;
    constexpr auto MaxValue = 100.0f;

    // Byte / Integer / Vector attributes ride the exact same templated replication path as Float
    // (CkAttribute_Processor.inl.h → per-type FCk_RepData_*Attributes container). The default
    // subject exposes one of each so the Byte/Integer/Vector net tests can reuse this subject the
    // same way the Float test does. Tags are all registered in Config/DefaultGameplayTags.ini.
    // No MinMax bracketing — the net tests just Request_Override and poll, no clamping involved.
    constexpr auto ByteAttributeTagName    = TEXT("ByteAttribute.Health");
    constexpr auto IntegerAttributeTagName = TEXT("IntegerAttribute.Health");
    constexpr auto VectorAttributeTagName  = TEXT("VectorAttribute.AutoTest_PerComponent");

    constexpr auto ByteInitialValue    = uint8{7};
    constexpr auto IntegerInitialValue = int32{13};
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_NetSubject_EntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams)
    -> ECk_EntityScript_ConstructionFlow
{
    // Super::Construct sets up the actor↔entity bridge (OwningActor, transform, label) and must
    // run before we add the attribute — the attribute Add needs an OwningActor in the chain to
    // resolve the replicated outer Actor for its container fragment.
    const auto Flow = Super::Construct(InHandle, InSpawnParams);

    auto* OwningActor = UCk_Utils_OwningActor_UE::Get_EntityOwningActor(InHandle);
    const auto FeatureReplication = OwningActor != nullptr && OwningActor->GetIsReplicated()
        ? ECk_Replication::Replicates
        : ECk_Replication::DoesNotReplicate;

    using namespace ck::auto_test::netsubject;

    const auto AttributeTag = FGameplayTag::RequestGameplayTag(FName{AttributeTagName});

    auto Params = FCk_Fragment_FloatAttribute_ParamsData{AttributeTag, InitialValue};
    Params.Set_MinMax(ECk_MinMax::MinMax);
    Params.Set_MinValue(MinValue);
    Params.Set_MaxValue(MaxValue);

    UCk_Utils_FloatAttribute_UE::Add(InHandle, Params, FeatureReplication);

    // Byte / Integer / Vector — same Replicates path, distinct initial values so an unreplicated
    // override shows as a clear cross-world mismatch.
    UCk_Utils_ByteAttribute_UE::Add(InHandle,
        FCk_Fragment_ByteAttribute_ParamsData{FGameplayTag::RequestGameplayTag(FName{ByteAttributeTagName}), ByteInitialValue},
        FeatureReplication);

    UCk_Utils_IntegerAttribute_UE::Add(InHandle,
        FCk_Fragment_IntegerAttribute_ParamsData{FGameplayTag::RequestGameplayTag(FName{IntegerAttributeTagName}), IntegerInitialValue},
        FeatureReplication);

    UCk_Utils_VectorAttribute_UE::Add(InHandle,
        FCk_Fragment_VectorAttribute_ParamsData{FGameplayTag::RequestGameplayTag(FName{VectorAttributeTagName}), FVector{1.0, 2.0, 3.0}},
        FeatureReplication);

    UCk_Utils_RotatorAttribute_UE::Add(InHandle,
        FCk_Fragment_RotatorAttribute_ParamsData{TAG_RotatorAttribute_AutoTest_Net.GetTag(), FRotator{10.0, 20.0, 30.0}},
        FeatureReplication);

    // Replicated TagSet (empty initial container). The CkTagSet net test drives Request_AddTag on
    // the server and polls HasTag on the client. Stash the handle on the actor so the test can
    // reach it without a by-name lookup (a TagSet is single-per-entity).
    auto TagSet = UCk_Utils_TagSet_UE::Add(InHandle, FGameplayTagContainer{}, FeatureReplication);

    // Replicated Acceleration (World coords, zero starting). The CkPhysics net test drives
    // Request_OverrideAcceleration on the server and polls Get_CurrentAcceleration on the client.
    // World coords avoid the Local-coords Transform/rotation path. Stash the handle on the actor
    // (Acceleration is single-per-entity, no by-tag TryGet) mirroring _TestTagSet.
    auto Acceleration = UCk_Utils_Acceleration_UE::Add(InHandle,
        FCk_Fragment_Acceleration_ParamsData{ECk_LocalWorld::World, FVector::ZeroVector},
        FeatureReplication);

    // Replicated AnimPlan (pure tag-state — no skeletal mesh). Starts at cluster + state A; the
    // CkAnimation net test moves it to state B on the server and polls the replicated state on the
    // client via the FCk_RepData_AnimPlans handler. Retrieved by goal tag (TryGet_AnimPlan), so no
    // actor stash is needed.
    auto AnimPlanParams = FCk_Fragment_AnimPlan_ParamsData{TAG_AnimPlan_AutoTest_Net_Goal.GetTag()};
    AnimPlanParams.Set_StartingAnimCluster(TAG_AnimPlan_AutoTest_Net_Cluster.GetTag());
    AnimPlanParams.Set_StartingAnimState(TAG_AnimPlan_AutoTest_Net_State_A.GetTag());
    UCk_Utils_AnimPlan_UE::Add(InHandle, AnimPlanParams, FeatureReplication);

    // Replicated Team + Player (Unassigned starting on both worlds). The Snapshot Team/Player parity
    // gate Assigns non-default IDs on the server; the client-side rep handlers return NotReady until
    // the feature is composed, so the subject must compose both on every world. Retrieved via
    // Has/Cast on the entity (single-per-entity), so no actor stash is needed.
    UCk_Utils_Team_UE::Add(InHandle, ECk_Team_ID::Unassigned, FeatureReplication);
    UCk_Utils_Player_UE::Add(InHandle, ECk_Player_ID::Unassigned, FeatureReplication);

    // Two unreplicated Construct-timers for the CkSnapshot Timer-parity gate. Composing them in Construct (not from
    // the test spec) is deliberate: only Construct-composed timers get a spawn recipe and are rebuilt on load, so this
    // is what the persistence handler actually covers. Both start PAUSED (StartingState default) so their elapsed is
    // deterministic across the reload — a running timer keeps advancing post-load and would defeat the
    // "elapsed within one tick" assertion. The gate advances each via a server-side Request_Jump before saving.
    //   - Countdown : 10s countdown, mid-run elapsed round-trip (+ CountDown direction + Paused run-state).
    //   - Done      : 4s count-up, jumped to completion — terminal-state round-trip + no OnTimerDone re-fire on load.
    {
        auto CountdownTimerParams = FCk_Timer_Spec{FCk_Time{10.0}};
        CountdownTimerParams.Set_TimerName(TAG_Timer_AutoTest_Net_Countdown.GetTag());
        CountdownTimerParams.Set_CountDirection(ECk_Timer_CountDirection::CountDown);
        UCk_Utils_Timer_UE::Add(InHandle, CountdownTimerParams);

        auto DoneTimerParams = FCk_Timer_Spec{FCk_Time{4.0}};
        DoneTimerParams.Set_TimerName(TAG_Timer_AutoTest_Net_Done.GetTag());
        DoneTimerParams.Set_CountDirection(ECk_Timer_CountDirection::CountUp);
        UCk_Utils_Timer_UE::Add(InHandle, DoneTimerParams);
    }

    if (auto* Subject = Cast<ACk_AutoTest_NetSubject>(OwningActor))
    {
        Subject->_TestTagSet = TagSet;
        Subject->_TestAcceleration = Acceleration;
    }

    return Flow;
}

// --------------------------------------------------------------------------------------------------------------------
