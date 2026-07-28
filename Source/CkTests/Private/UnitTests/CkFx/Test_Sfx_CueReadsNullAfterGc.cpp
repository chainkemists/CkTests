// Sfx params hold a SOFT reference — a serialized path, never a strong pointer. UE's GC does not
// trace EnTT fragment members, so a fragment cannot root anything even if it wanted to; the
// properties the params CAN guarantee are that a collected cue resolves back as null instead of as
// a dangling pointer, and that the authored PATH survives the collect (the Setup processor re-loads
// and roots it through CkResourceLoader — that rooted lifetime lives on Current, not here).

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/World/CkEcsWorld.h"
#include "UnitTests/CkGcWeakRef_TestBase.h"

#include "Sfx/CkSfx_Fragment.h"

#include "Sound/SoundCue.h"

#include "UObject/GarbageCollection.h"
#include "UObject/UObjectGlobals.h"
#include "UObject/WeakObjectPtr.h"

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_CUSTOM_SIMPLE_AUTOMATION_TEST(
    FCkTest_Sfx_CueReadsNullAfterGc,
    FCkTest_GcWeakRefBase,
    "CkTests.UnitTests.CkFx.Sfx.CueReadsNullAfterGc",
    ck_test_gc_weak_ref::kTestFlags)

bool FCkTest_Sfx_CueReadsNullAfterGc::RunTest(const FString& Parameters)
{
    auto  EcsWorld = ck::FEcsWorld{};
    auto& Registry = EcsWorld.Get_Registry();

    // A TRANSIENT cue, never a shipped asset: an asset is kept resident by the editor's package and
    // asset-registry machinery, so an asset-based version of this would never collect in the editor
    // while a cooked build still does. A transient object behaves the same in both. TWeakObjectPtr is
    // the only safe liveness probe — it is serial-number validated, so it never reads the freed object.
    auto*      Cue     = NewObject<USoundCue>(GetTransientPackage());
    const auto WeakCue = TWeakObjectPtr<USoundBase>{Cue};

    auto Entity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
    Entity.Add<ck::FFragment_Sfx_Params>(FCk_Fragment_Sfx_ParamsData{FGameplayTag{}, Cue});

    Cue = nullptr;
    CollectGarbage(RF_NoFlags, true);

    TestFalse(TEXT("a cue reachable only through an Sfx fragment is NOT kept alive by that fragment"),
        WeakCue.IsValid());

    const auto& Params = Entity.Get<ck::FFragment_Sfx_Params>().Get_Params();

    TestNull(TEXT("the collected cue resolves from the params as null, never as a dangling pointer"),
        Params.Get_SoundCue().Get());

    TestFalse(TEXT("the authored soft PATH survives the collect - the params stay re-loadable"),
        Params.Get_SoundCue().IsNull());

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
