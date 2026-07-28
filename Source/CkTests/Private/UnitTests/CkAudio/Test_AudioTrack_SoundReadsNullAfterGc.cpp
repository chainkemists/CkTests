// AudioTrack params hold a SOFT reference — a serialized path, never a strong pointer. UE's GC does
// not trace EnTT fragment members, so a fragment cannot root anything even if it wanted to; the
// properties the params CAN guarantee are that a collected sound resolves back as null instead of
// as a dangling pointer, and that the authored PATH survives — which is why Get_TrackName (derived
// from the path, never a dereference) keeps working after the collect. Composed through the public
// Create rather than by adding the fragment directly: FFragment_AudioTrack_Params is a bare alias
// of the reflected, BlueprintReadWrite struct, so a Blueprint caller reaches exactly this shape.

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "CkAudio/AudioTrack/CkAudioTrack_Fragment.h"
#include "CkAudio/AudioTrack/CkAudioTrack_Utils.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/World/CkEcsWorld.h"
#include "UnitTests/CkGcWeakRef_TestBase.h"

#include "Sound/SoundCue.h"

#include "UObject/GarbageCollection.h"
#include "UObject/UObjectGlobals.h"
#include "UObject/WeakObjectPtr.h"

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_CUSTOM_SIMPLE_AUTOMATION_TEST(
    FCkTest_AudioTrack_SoundReadsNullAfterGc,
    FCkTest_GcWeakRefBase,
    "CkTests.UnitTests.CkAudio.AudioTrack.SoundReadsNullAfterGc",
    ck_test_gc_weak_ref::kTestFlags)

bool FCkTest_AudioTrack_SoundReadsNullAfterGc::RunTest(const FString& Parameters)
{
    auto  EcsWorld = ck::FEcsWorld{};
    auto& Registry = EcsWorld.Get_Registry();

    // Transient, not a shipped asset — see the sibling CkFx test for why an asset would mask this.
    auto*      Sound             = NewObject<USoundCue>(GetTransientPackage());
    const auto WeakSound         = TWeakObjectPtr<USoundBase>{Sound};
    const auto ExpectedTrackName = Sound->GetFName();

    auto Director = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
    auto Track    = UCk_Utils_AudioTrack_UE::Create(Director, FCk_Fragment_AudioTrack_ParamsData{Sound});

    Sound = nullptr;
    CollectGarbage(RF_NoFlags, true);

    TestFalse(TEXT("a sound reachable only through an AudioTrack fragment is NOT kept alive by that fragment"),
        WeakSound.IsValid());

    const auto& Params = Track.Get<ck::FFragment_AudioTrack_Params>();

    TestNull(TEXT("the collected sound resolves from the params as null, never as a dangling pointer"),
        Params.Get_Sound().Get());

    TestFalse(TEXT("the authored soft PATH survives the collect - the params stay re-loadable"),
        Params.Get_Sound().IsNull());

    TestTrue(TEXT("the sound-derived track name comes from the PATH, so it survives the collect without a dereference"),
        Params.Get_TrackName() == ExpectedTrackName);

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
