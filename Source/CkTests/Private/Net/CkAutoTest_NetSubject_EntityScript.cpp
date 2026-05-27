#include "CkTests/Net/CkAutoTest_NetSubject_EntityScript.h"

#include "CkAttribute/FloatAttribute/CkFloatAttribute_Fragment_Data.h"
#include "CkAttribute/FloatAttribute/CkFloatAttribute_Utils.h"

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

    return Flow;
}

// --------------------------------------------------------------------------------------------------------------------
