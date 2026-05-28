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
#include "CkTagSet/CkTagSet_Utils.h"
#include "CkPhysics/Acceleration/CkAcceleration_Utils.h"

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

    using namespace ck::auto_test::netsubject;

    const auto AttributeTag = FGameplayTag::RequestGameplayTag(FName{AttributeTagName});

    auto Params = FCk_Fragment_FloatAttribute_ParamsData{AttributeTag, InitialValue};
    Params.Set_MinMax(ECk_MinMax::MinMax);
    Params.Set_MinValue(MinValue);
    Params.Set_MaxValue(MaxValue);

    UCk_Utils_FloatAttribute_UE::Add(InHandle, Params, ECk_Replication::Replicates);

    // Byte / Integer / Vector — same Replicates path, distinct initial values so an unreplicated
    // override shows as a clear cross-world mismatch.
    UCk_Utils_ByteAttribute_UE::Add(InHandle,
        FCk_Fragment_ByteAttribute_ParamsData{FGameplayTag::RequestGameplayTag(FName{ByteAttributeTagName}), ByteInitialValue},
        ECk_Replication::Replicates);

    UCk_Utils_IntegerAttribute_UE::Add(InHandle,
        FCk_Fragment_IntegerAttribute_ParamsData{FGameplayTag::RequestGameplayTag(FName{IntegerAttributeTagName}), IntegerInitialValue},
        ECk_Replication::Replicates);

    UCk_Utils_VectorAttribute_UE::Add(InHandle,
        FCk_Fragment_VectorAttribute_ParamsData{FGameplayTag::RequestGameplayTag(FName{VectorAttributeTagName}), FVector{1.0, 2.0, 3.0}},
        ECk_Replication::Replicates);

    // Replicated TagSet (empty initial container). The CkTagSet net test drives Request_AddTag on
    // the server and polls HasTag on the client. Stash the handle on the actor so the test can
    // reach it without a by-name lookup (a TagSet is single-per-entity).
    auto TagSet = UCk_Utils_TagSet_UE::Add(InHandle, FGameplayTagContainer{}, ECk_Replication::Replicates);

    // Replicated Acceleration (World coords, zero starting). The CkPhysics net test drives
    // Request_OverrideAcceleration on the server and polls Get_CurrentAcceleration on the client.
    // World coords avoid the Local-coords Transform/rotation path. Stash the handle on the actor
    // (Acceleration is single-per-entity, no by-tag TryGet) mirroring _TestTagSet.
    auto Acceleration = UCk_Utils_Acceleration_UE::Add(InHandle,
        FCk_Fragment_Acceleration_ParamsData{ECk_LocalWorld::World, FVector::ZeroVector},
        ECk_Replication::Replicates);

    auto* OwningActor = UCk_Utils_OwningActor_UE::Get_EntityOwningActor(InHandle);
    if (auto* Subject = Cast<ACk_AutoTest_NetSubject>(OwningActor))
    {
        Subject->_TestTagSet = TagSet;
        Subject->_TestAcceleration = Acceleration;
    }

    return Flow;
}

// --------------------------------------------------------------------------------------------------------------------
