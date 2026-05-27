#include "CkTests/Net/CkAutoTest_NetSubject_RefillEntityScript.h"

#include "CkAttribute/FloatAttribute/CkFloatAttribute_Fragment_Data.h"
#include "CkAttribute/FloatAttribute/CkFloatAttribute_Utils.h"

#include "GameplayTagContainer.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck::auto_test::netsubject_refill
{
    // Energy + Energy.Refill are registered in Config/DefaultGameplayTags.ini for use by the
    // standalone CkAttribute refill AutoTests — reuse them here so this test doesn't need its
    // own tag-registration commit.
    constexpr auto AttributeTagName       = TEXT("FloatAttribute.AutoTest_Energy");
    constexpr auto RefillAttributeTagName = TEXT("FloatAttribute.AutoTest_Energy.Refill");

    // Initial Energy value. 0 is deliberate — the test asserts the refill processor *increased*
    // the value above this initial; if the assertion sees 0 the refill never ran (or never
    // replicated). Min/Max bracket the refill target so it isn't continually clamping.
    constexpr auto InitialValue = 0.0f;
    constexpr auto MinValue     = 0.0f;
    constexpr auto MaxValue     = 100.0f;

    // Per-second fill rate. With the spec's settle window of ~60 frames @ 60fps ≈ 1s, the
    // expected value is around InitialValue + 20.0 = 20.0 (modulo per-tick discretisation).
    // The spec asserts "value > InitialValue + safety margin" rather than an exact value to
    // avoid brittleness around scheduler tick rate / frame timing.
    constexpr auto FillRate = 20.0f;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_NetSubject_RefillEntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams)
    -> ECk_EntityScript_ConstructionFlow
{
    const auto Flow = Super::Construct(InHandle, InSpawnParams);

    using namespace ck::auto_test::netsubject_refill;

    const auto AttributeTag       = FGameplayTag::RequestGameplayTag(FName{AttributeTagName});
    const auto RefillAttributeTag = FGameplayTag::RequestGameplayTag(FName{RefillAttributeTagName});

    auto RefillParams = FCk_Fragment_FloatAttributeRefill_ParamsData{RefillAttributeTag, FillRate};
    RefillParams.Set_StartingState(ECk_Attribute_RefillState::Running);

    auto Params = FCk_Fragment_FloatAttribute_ParamsData{AttributeTag, InitialValue};
    Params.Set_MinMax(ECk_MinMax::MinMax);
    Params.Set_MinValue(MinValue);
    Params.Set_MaxValue(MaxValue);
    Params.Set_EnableRefill(true);
    Params.Set_RefillParams(RefillParams);

    UCk_Utils_FloatAttribute_UE::Add(InHandle, Params, ECk_Replication::Replicates);

    return Flow;
}

// --------------------------------------------------------------------------------------------------------------------
