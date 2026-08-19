// C3: session state is rebuilt by the feature's own construction path, never restored. This pins the
// consequence for the commonest shape a real feature has — a fragment holding a handle to a child its own
// Construct creates (a probe node, a SceneNode, a spawned sub-entity).
//
// The child is an UNLABELED ConstructSpawned entity, so the save has no identity for it and never captures it.
// Before postures existed, its owner's fragment WAS captured, and hydration wrote the saved handle over the one
// construction had just built — remapping it to a tombstone, because the child it named was never persisted.
// The feature came back structurally present and functionally dead, which is the ChangeablePoster / presented-
// hand / dead-HUD class in one sentence. A positional backstop used to catch it; it was deleted with the last
// undeclared fragment, because a backstop is not a contract.
//
// Declaring the fragment Session removes the whole exchange: capture skips it, hydration skips it, and the
// handle Construct wrote is simply left alone. The assertions are therefore about what the REBUILD produced —
// a valid handle, naming a NEW entity. Validity alone would pass for a saved handle remapped onto something
// live, which is why the id comparison is here rather than a nice-to-have.
//
// NOTE ON POLARITY: this is a PIN, not a red-then-green. The violation it describes was closed when posture
// went live (Session fragments stopped being captured on both sides); it is green on arrival and its job is to
// stay that way. It would have been red before that switch.
// Surface in Session Frontend: Ck.Snapshot.Session.SetupRebuildsSessionState

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel

#include "CkDynamic/CkDynamic_Utils.h"

#include "CkEcs/EntityScript/CkEntityScript_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Snapshot/CkSnapshot_Posture.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Snapshot/CkAutoTest_Snapshot_Ordering.h"
#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

namespace ck_test_session_rebuilt
{
    const auto SlotName = FName{TEXT("CkSnapshot_SessionRebuiltBySetup_GateSlot")};

    auto ResolveProbe(UWorld* InWorld) -> FCk_Handle
    {
        if (InWorld == nullptr)
        { return {}; }
        return ck::auto_test::snapshot::ResolveEntityBySpawnRecipe(
            InWorld, UCk_AutoTest_Snapshot_HandleGraphProbe_EntityScript_UE::StaticClass());
    }

    auto Get_SessionChild(const FCk_Handle& InProbe) -> FCk_Handle
    {
        if (ck::Is_NOT_Valid(InProbe))
        { return {}; }

        if (NOT UCk_Utils_DynamicFragment_UE::Has_Fragment(
            InProbe, FCk_Test_Session_ChildRef::StaticStruct()))
        { return {}; }

        return UCk_Utils_DynamicFragment_UE::Get_Fragment_TypeUnsafe(
            InProbe, FCk_Test_Session_ChildRef::StaticStruct()).Get<FCk_Test_Session_ChildRef>().Child;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Session_SetupRebuildsSessionState,
    "Ck.Snapshot.Session.SetupRebuildsSessionState",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_Session_SetupRebuildsSessionState::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_session_rebuilt;
    using namespace ck_autotest_snapshot_ordering;

    // The premise the whole test rests on. Asserted first so a posture regression reads as "the fixture stopped
    // being Session" instead of surfacing as a confusing handle-identity failure three stages later.
    TestEqual(
        TEXT("the child-referencing fixture resolves Session"),
        static_cast<int32>(ck::Get_FragmentPosture(FCk_Test_Session_ChildRef::StaticStruct())),
        static_cast<int32>(ECk_Snapshot_Posture::Session));

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = SlotName;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
        { CVar->Set(1, ECVF_SetByCode); }

        auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient, UCk_AutoTest_Snapshot_HandleGraphProbe_EntityScript_UE::StaticClass(),
            FInstancedStruct{}, {});
    });

    Spec.SubjectReady = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
    {
        const auto Probe = ResolveProbe(ck::auto_test::snapshot::Get_PostTravelServerWorld());
        return ck::IsValid(Probe) && ck::IsValid(Get_SessionChild(Probe));
    });

    Spec.Mutate = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        Reset_Observations();

        const auto Child = Get_SessionChild(ResolveProbe(InServer));
        Get_Observations().HandleGraph_PreSaveChildId =
            ck::IsValid(Child) ? static_cast<int32>(Child.Get_Entity().Get_ID()) : 0;
    });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
    {
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        auto AllGood = TestTrue(TEXT("post-load server world resolves"), Server != nullptr);
        if (Server == nullptr)
        { return false; }

        auto Probe = ResolveProbe(Server);
        if (NOT TestTrue(TEXT("the probe was restored (the load ran)"), ck::IsValid(Probe)))
        { return false; }

        auto& Obs = Get_Observations();

        AllGood &= TestNotEqual(
            TEXT("the pre-save child id was recorded (otherwise the comparison below is vacuous)"),
            Obs.HandleGraph_PreSaveChildId, 0);

        const auto Child = Get_SessionChild(Probe);

        AllGood &= TestTrue(
            TEXT("the Session fragment's child handle is VALID after the load — Construct rebuilt the child and "
                 "nothing overwrote the handle naming it"),
            ck::IsValid(Child));

        if (ck::Is_NOT_Valid(Child))
        { return false; }

        AllGood &= TestNotEqual(
            TEXT("and it names a NEW entity, not the pre-save one — the child was never persisted, so a handle "
                 "carrying the old id back would mean the Session fragment was captured and hydrated after all"),
            static_cast<int32>(Child.Get_Entity().Get_ID()), Obs.HandleGraph_PreSaveChildId);

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
