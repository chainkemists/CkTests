// GW-35 — the load-time freeze is single-valued, and says so instead of dropping a world's dial on the floor.
//
// DoApply_TimeFreeze captures ONE prior dilation for ONE world. That is correct for the shape a load actually
// has — the pre-travel world is frozen, dies, and the post-travel world is frozen in its place — but the
// bookkeeping cannot express two worlds frozen at once: the second apply overwrites the first world's captured
// prior value, and the restore that would have handed it back can then only hand back the SECOND world's. The
// first world runs the rest of the session at 1/10000 speed with nothing left holding a note of what it was.
//
// So a second apply while a LIVE world is still held is refused with an ensure rather than served silently.
// "Live" is the whole discrimination: the legitimate second apply of every load happens after the outgoing
// world has had BeginTearingDown called on it (UnrealEngine.cpp's LoadMap, World.cpp's seamless travel), so it
// is not live and its dial is about to stop existing along with it.
//
// RED before this change: the second apply took the freeze, silently rebased _PriorTimeDilation onto the second
// world's value, and left the first world dilated with no owner.
// Surface in Session Frontend: Ck.Snapshot.LoadHold.TimeFreezeRefusesASecondLiveWorld
//                              Ck.Snapshot.LoadHold.TimeFreezeRearmsOverATearingDownWorld

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/Macros/CkMacros.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "Engine/GameInstance.h"  // the subsystem's ClassWithin — see FScopedWorlds
#include "Engine/World.h"
#include "GameFramework/WorldSettings.h"

namespace ck_test_loadhold_freezescope
{
    constexpr auto kFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;

    // The freeze writes MinGlobalTimeDilation, which defaults to 1e-4. Anything at or under this is frozen;
    // anything near 1.0 is not. Deliberately loose — the test asks WHICH world moved, never by how much.
    constexpr auto FrozenCeiling = 0.01;
    constexpr auto NotFrozenFloor = 0.5;

    struct FScopedWorlds
    {
        UWorld* A = nullptr;
        UWorld* B = nullptr;
        UGameInstance* SubsystemOuter = nullptr;
        UCk_Snapshot_Subsystem_UE* Subsystem = nullptr;

        FScopedWorlds()
        {
            A = UWorld::CreateWorld(EWorldType::Game, /*bInformEngineOfWorld=*/false);
            B = UWorld::CreateWorld(EWorldType::Game, /*bInformEngineOfWorld=*/false);

            // The subsystem is exercised as a plain object: the freeze pair reads nothing but the world it is
            // handed and its own members, so standing up a PIE GameInstance would prove nothing extra. But it is
            // a UGameInstanceSubsystem, so its ClassWithin IS UGameInstance and NewObject into the transient
            // PACKAGE trips StaticAllocateObjectErrorTests' ensure (UObjectGlobals.cpp) — which the automation
            // framework scores as a failure. That ensure is one-shot per call site, so with two tests sharing
            // this fixture only the FIRST one reds and the second passes on the suppressed repeat: a green there
            // was luck, not evidence. A throwaway instance satisfies the constraint and owns nothing.
            SubsystemOuter = NewObject<UGameInstance>(GetTransientPackage());
            SubsystemOuter->AddToRoot();

            Subsystem = NewObject<UCk_Snapshot_Subsystem_UE>(SubsystemOuter);
            Subsystem->AddToRoot();
        }

        ~FScopedWorlds()
        {
            Subsystem->RemoveFromRoot();
            SubsystemOuter->RemoveFromRoot();

            if (B != nullptr)
            { B->DestroyWorld(/*bInformEngineOfWorld=*/false); }

            if (A != nullptr)
            { A->DestroyWorld(/*bInformEngineOfWorld=*/false); }
        }
    };

    auto Get_Dilation(const UWorld* InWorld) -> double
    {
        const auto* Settings = InWorld != nullptr ? InWorld->GetWorldSettings() : nullptr;
        return Settings != nullptr ? static_cast<double>(Settings->GetEffectiveTimeDilation()) : -1.0;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_LoadHold_TimeFreezeRefusesASecondLiveWorld,
    "Ck.Snapshot.LoadHold.TimeFreezeRefusesASecondLiveWorld",
    ck_test_loadhold_freezescope::kFlags)

bool FCk_Snapshot_LoadHold_TimeFreezeRefusesASecondLiveWorld::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_loadhold_freezescope;

    auto Scoped = FScopedWorlds{};

    if (NOT TestTrue(TEXT("two worlds and a subsystem to exercise"),
        Scoped.A != nullptr && Scoped.B != nullptr && Scoped.Subsystem != nullptr))
    { return false; }

    auto AllGood = TestEqual(TEXT("world A starts undilated"), Get_Dilation(Scoped.A), 1.0, 1.0e-3);
    AllGood &= TestEqual(TEXT("world B starts undilated"), Get_Dilation(Scoped.B), 1.0, 1.0e-3);

    Scoped.Subsystem->TestOnly_Apply_TimeFreeze(*Scoped.A);

    AllGood &= TestTrue(
        FString::Printf(TEXT("world A is frozen after the first apply (dilation %.6f)"), Get_Dilation(Scoped.A)),
        Get_Dilation(Scoped.A) <= FrozenCeiling);

    // The refusal is the ensure — one Error line, and the only evidence a caller gets that its world is NOT
    // going to be held. At least once rather than exactly once: how many lines one ensure prints belongs to
    // the host, not to the code under test.
    constexpr auto AtLeastOnce = 0;
    AddExpectedError(
        TEXT("already held on the LIVE world"),
        EAutomationExpectedErrorFlags::Contains,
        AtLeastOnce);

    Scoped.Subsystem->TestOnly_Apply_TimeFreeze(*Scoped.B);

    AllGood &= TestTrue(
        FString::Printf(TEXT("world B was NOT frozen — the second apply is refused, not served (dilation %.6f)"),
            Get_Dilation(Scoped.B)),
        Get_Dilation(Scoped.B) >= NotFrozenFloor);

    AllGood &= TestTrue(
        FString::Printf(TEXT("...and world A is still frozen — the refusal costs the incumbent nothing "
                             "(dilation %.6f)"), Get_Dilation(Scoped.A)),
        Get_Dilation(Scoped.A) <= FrozenCeiling);

    // The point of refusing: A's prior value survived, so A can still be given back. Had the second apply been
    // served, this restore would have handed A whatever B happened to be sitting at.
    Scoped.Subsystem->TestOnly_Restore_TimeFreeze(*Scoped.A);

    AllGood &= TestEqual(
        TEXT("world A is restored to exactly the dilation it had before the freeze"),
        Get_Dilation(Scoped.A), 1.0, 1.0e-3);

    return AllGood;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_LoadHold_TimeFreezeRearmsOverATearingDownWorld,
    "Ck.Snapshot.LoadHold.TimeFreezeRearmsOverATearingDownWorld",
    ck_test_loadhold_freezescope::kFlags)

bool FCk_Snapshot_LoadHold_TimeFreezeRearmsOverATearingDownWorld::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_loadhold_freezescope;

    auto Scoped = FScopedWorlds{};

    if (NOT TestTrue(TEXT("two worlds and a subsystem to exercise"),
        Scoped.A != nullptr && Scoped.B != nullptr && Scoped.Subsystem != nullptr))
    { return false; }

    Scoped.Subsystem->TestOnly_Apply_TimeFreeze(*Scoped.A);

    // Exactly what a load's own travel does to the world it leaves, and the reason the refusal above must not
    // be a blanket "one freeze per subsystem": EVERY load freezes twice, and the second one has to take. The
    // flag is set directly rather than through BeginTearingDown() because that broadcasts a global engine
    // delegate, and a bare transient world this test owns has no business firing world-teardown listeners.
    Scoped.A->bIsTearingDown = true;

    Scoped.Subsystem->TestOnly_Apply_TimeFreeze(*Scoped.B);

    auto AllGood = TestTrue(
        FString::Printf(TEXT("the post-travel world IS frozen — a world that has begun tearing down is not a "
                             "world the freeze still owes anything to (dilation %.6f)"), Get_Dilation(Scoped.B)),
        Get_Dilation(Scoped.B) <= FrozenCeiling);

    Scoped.Subsystem->TestOnly_Restore_TimeFreeze(*Scoped.B);

    AllGood &= TestEqual(
        TEXT("...and it is restored on the way out"),
        Get_Dilation(Scoped.B), 1.0, 1.0e-3);

    return AllGood;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
