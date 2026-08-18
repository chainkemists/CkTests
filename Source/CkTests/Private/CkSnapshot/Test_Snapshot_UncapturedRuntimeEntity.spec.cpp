// A save says what it did NOT carry.
//
// A feature composed at runtime — the canonical case is a timer started by a state machine, a task, or a request
// handler — has no construction recipe and no save identity, so capture rule 5 skips it. Under C5 that is the
// DESIGNED outcome: the durable intent is the deadline, held by the owning feature, whose Setup re-creates the
// timer on load. What was wrong was that the omission was invisible — nothing counted it, nothing named it, and
// an author had no way to tell a deliberate session-scoped loss from a silent drop (F-U4.18: three BusterBlock
// timers vanished this way and nobody knew until a QA report).
//
// So this is not a warning gate. It pins that the save REPORTS the omission as data.
// Surface in Session Frontend: Ck.Snapshot.Report.UncapturedRuntimeEntityIsNamed

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTimer/CkTimer_Fragment_Data.h"
#include "CkTimer/CkTimer_Utils.h"

#include "CkTests/CkTests_Fragment_Data.h" // TAG_Timer_AutoTest_Net_Countdown
#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

namespace ck_test_uncaptured_runtime
{
    const auto Uncaptured_SlotName = FName{TEXT("CkSnapshot_UncapturedRuntimeEntity_GateSlot")};
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_UncapturedRuntimeEntityIsNamed_Gate,
    "Ck.Snapshot.Report.UncapturedRuntimeEntityIsNamed",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_UncapturedRuntimeEntityIsNamed_Gate::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_uncaptured_runtime;

    // A save is enough — no load, no travel. The fact under test is produced by the CAPTURE.
    constexpr auto NumClients = 1;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto SettleFrames = 10;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumClients, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(NumClients, ReadyTimeoutSeconds));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
            if (NOT TestTrue(TEXT("world resolves"), Server != nullptr))
            { return true; }

            // Created HERE, at runtime, outside any construction window — so the timer's child entity gets no
            // FTag_ConstructSpawned and no spawn recipe, which is exactly the shape a timer started from an SM
            // state or a request handler has.
            auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(Server);
            if (NOT TestTrue(TEXT("scratch owner entity created"), ck::IsValid(Owner)))
            { return true; }

            // Reuses an existing declared tag rather than requesting one by name: an unregistered tag resolves
            // empty, and the label the timer's child entity is given would be the unnamed one.
            auto Params = FCk_Fragment_Timer_ParamsData{FCk_Time{30.0}};
            Params.Set_TimerName(TAG_Timer_AutoTest_Net_Countdown.GetTag());

            const auto Timer = UCk_Utils_Timer_UE::Add(Owner, Params);
            return TestTrue(TEXT("a runtime timer was composed"), ck::IsValid(Timer));
        }),
        TEXT("compose a runtime-created timer")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(SettleFrames));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
            auto* Subsystem = ck::auto_test::snapshot::Get_SnapshotSubsystem(Server);
            if (NOT TestTrue(TEXT("snapshot subsystem present"), Subsystem != nullptr))
            { return true; }

            Subsystem->Request_Save(Uncaptured_SlotName, FCk_Delegate_OnSaveComplete{});

            const auto& Report = Subsystem->Get_LastSaveReport();

            auto AllGood = TestTrue(TEXT("the save succeeded"),
                Report.Get_Result() == ECk_SnapshotResult::Success);

            const auto& Uncaptured = Report.Get_UncapturedRuntimeEntities();
            const auto* TimerRecord = Uncaptured.FindByPredicate(
                [](const FCk_Snapshot_UncapturedRuntimeRecord& InRecord) -> bool
                { return InRecord.Get_PayloadType().Contains(TEXT("Timer")); });

            // The whole point: the omission is DATA now. Before this the timer simply was not in the save and
            // nothing anywhere said so.
            AllGood &= TestTrue(
                FString::Printf(TEXT("the save NAMES the runtime timer it did not carry (records=%d)"),
                    Uncaptured.Num()),
                TimerRecord != nullptr);

            if (TimerRecord != nullptr)
            {
                AllGood &= TestTrue(TEXT("...with the entity it belonged to"),
                    NOT TimerRecord->Get_Identity().IsEmpty());
            }

            return AllGood;
        }),
        TEXT("the save report names the uncaptured runtime entity")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
