// AnimAsset params hold SOFT references — serialized paths, never strong pointers. UE's GC does not
// trace EnTT fragment members, so a fragment cannot root anything even if it wanted to; AnimAsset is
// pure path data by contract (it kicks no loads — consumers resolve through their own loader consumer
// id). The properties the params CAN guarantee are that a collected animation resolves back as null
// instead of as a dangling pointer, and that the authored PATH survives the collect.

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/World/CkEcsWorld.h"
#include "UnitTests/CkGcWeakRef_TestBase.h"

#include "CkAnimation/AnimAsset/CkAnimAsset_Fragment.h"

#include "Animation/AnimMontage.h"

#include "UObject/GarbageCollection.h"
#include "UObject/UObjectGlobals.h"
#include "UObject/WeakObjectPtr.h"

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_CUSTOM_SIMPLE_AUTOMATION_TEST(
    FCkTest_AnimAsset_AnimationReadsNullAfterGc,
    FCkTest_GcWeakRefBase,
    "CkTests.UnitTests.CkAnimation.AnimAsset.AnimationReadsNullAfterGc",
    ck_test_gc_weak_ref::kTestFlags)

bool FCkTest_AnimAsset_AnimationReadsNullAfterGc::RunTest(const FString& Parameters)
{
    auto  EcsWorld = ck::FEcsWorld{};
    auto& Registry = EcsWorld.Get_Registry();

    // A TRANSIENT animation, never a shipped asset: an asset is kept resident by the editor's package
    // and asset-registry machinery, so an asset-based version of this would never collect in the
    // editor while a cooked build still does. A transient object behaves the same in both.
    // TWeakObjectPtr is the only safe liveness probe — it is serial-number validated, so it never
    // reads the freed object.
    auto*      Animation     = NewObject<UAnimMontage>(GetTransientPackage());
    const auto WeakAnimation = TWeakObjectPtr<UAnimationAsset>{Animation};

    auto Entity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
    Entity.Add<ck::FFragment_AnimAsset_Params>(
        FCk_Fragment_AnimAsset_ParamsData{FCk_AnimAsset_Animation{FGameplayTag{}, Animation}});

    Animation = nullptr;
    CollectGarbage(RF_NoFlags, true);

    TestFalse(TEXT("an animation reachable only through an AnimAsset fragment is NOT kept alive by that fragment"),
        WeakAnimation.IsValid());

    const auto& Params = Entity.Get<ck::FFragment_AnimAsset_Params>().Get_Params();

    TestNull(TEXT("the collected animation resolves from the params as null, never as a dangling pointer"),
        Params.Get_AnimationAsset().Get_Animation().Get());

    TestFalse(TEXT("the authored soft PATH survives the collect - the params stay re-loadable"),
        Params.Get_AnimationAsset().Get_Animation().IsNull());

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
