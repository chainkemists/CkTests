#include "CkTests/Net/CkAutoTest_NetSubject_RefillEntityScript.h"

#include "CkAttribute/FloatAttribute/CkFloatAttribute_Fragment_Data.h"
#include "CkAttribute/FloatAttribute/CkFloatAttribute_Utils.h"
#include "CkAttribute/IntegerAttribute/CkIntegerAttribute_Fragment_Data.h"
#include "CkAttribute/IntegerAttribute/CkIntegerAttribute_Utils.h"

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

    // Integer refill rides the exact same templated refill + container-replication path as Float
    // (refill is supported on Float and Integer only). The Integer net refill test reuses this
    // subject (Get_SubjectEntity) and reads the Integer energy attribute. Tags are reused from the
    // standalone CkAttribute IntegerRefill AutoTest — IntegerAttribute.AutoTest_Energy is an
    // implicit parent of the registered .Refill tag, so no new registration is needed.
    constexpr auto IntegerAttributeTagName       = TEXT("IntegerAttribute.AutoTest_Energy");
    constexpr auto IntegerRefillAttributeTagName = TEXT("IntegerAttribute.AutoTest_Energy.Refill");

    constexpr auto IntegerInitialValue = int32{0};
    constexpr auto IntegerMinValue     = int32{0};
    constexpr auto IntegerMaxValue     = int32{100};
    constexpr auto IntegerFillRate     = 20.0f;
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

    auto RefillParams = FCk_FloatAttributeRefill_Spec{RefillAttributeTag, FillRate};
    RefillParams.Set_StartingState(ECk_Attribute_RefillState::Running);

    auto Params = FCk_FloatAttribute_Spec{AttributeTag, InitialValue};
    Params.Set_MinMax(ECk_MinMax::MinMax);
    Params.Set_MinValue(MinValue);
    Params.Set_MaxValue(MaxValue);
    Params.Set_EnableRefill(true);
    Params.Set_RefillParams(RefillParams);

    UCk_Utils_FloatAttribute_UE::Add(InHandle, Params, ECk_Replication::Replicates);

    // Integer refill — same templated refill + Replicates path, distinct tag so it sits alongside
    // the Float energy attribute on the same subject without interfering.
    const auto IntegerAttributeTag       = FGameplayTag::RequestGameplayTag(FName{IntegerAttributeTagName});
    const auto IntegerRefillAttributeTag = FGameplayTag::RequestGameplayTag(FName{IntegerRefillAttributeTagName});

    auto IntegerRefillParams = FCk_IntegerAttributeRefill_Spec{IntegerRefillAttributeTag, IntegerFillRate};
    IntegerRefillParams.Set_StartingState(ECk_Attribute_RefillState::Running);

    auto IntegerParams = FCk_IntegerAttribute_Spec{IntegerAttributeTag, IntegerInitialValue};
    IntegerParams.Set_MinMax(ECk_MinMax::MinMax);
    IntegerParams.Set_MinValue(IntegerMinValue);
    IntegerParams.Set_MaxValue(IntegerMaxValue);
    IntegerParams.Set_EnableRefill(true);
    IntegerParams.Set_RefillParams(IntegerRefillParams);

    UCk_Utils_IntegerAttribute_UE::Add(InHandle, IntegerParams, ECk_Replication::Replicates);

    return Flow;
}

// --------------------------------------------------------------------------------------------------------------------
