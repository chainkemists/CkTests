// Server-authoritative WithoutHistory snap-to-final-state.
//
// Spawns ACk_AutoTest_NetSubject_StateMachineNoHistory_UE — its entity-script builds a
// Replicates / ServerAuthoritative / WithoutHistory SM with initial state A on both worlds. The
// server then drives A→B→C in a SINGLE server action (no TickWorlds between the two transitions),
// so the WithoutHistory rep payload (FCk_RepData_StateMachine_NoHistory, carrying only the latest
// _CurrentStateClass) converges the client straight to C.
//
// Contrast with the WithHistory test (Ck.StateMachine.Net.ServerAuth_ABC_Replay): there the client
// replays every transition via the ring and records Enter(B) AND Enter(C). Here, with no history
// ring, the client snaps to current — it is NOT guaranteed to observe the intermediate B. So the
// robust, non-flaky contract asserted here is: the client's SM converges to final state C. Whether
// the client happened to also record an intermediate B is timing-dependent and intentionally NOT
// asserted.
//
// Surface in Session Frontend: Ck.StateMachine.Net.ServerAuth_NoHistory_SnapsToFinalState

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkStateMachine/StateMachine/CkStateMachine_Utils.h"

#include "CkTests/Net/CkAutoTest_NetSubject.h"
#include "CkTests/Net/CkAutoTest_NetSubject_StateMachine.h"
#include "CkTests/Net/CkAutoTest_Sm_Recorder.h"
#include "CkTests/Net/CkAutoTest_Sm_RecordingState.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkStateMachineNet_ServerAuth_NoHistory_SnapsToFinalState,
    "Ck.StateMachine.Net.ServerAuth_NoHistory_SnapsToFinalState",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkStateMachineNet_ServerAuth_NoHistory_SnapsToFinalState::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesAfterSpawn = 30;
    constexpr auto FramesAfterTransitions = 40;  // generous — rep convergence of the snapped final state

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            auto* Subject = InServer->SpawnActor<ACk_AutoTest_NetSubject_StateMachineNoHistory_UE>(
                ACk_AutoTest_NetSubject_StateMachineNoHistory_UE::StaticClass(), FTransform::Identity, SpawnInfo);
            if (Subject == nullptr)
            { AddError(TEXT("server-side SpawnActor of ACk_AutoTest_NetSubject_StateMachineNoHistory_UE returned null")); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterSpawn));

    // ---- Rapid A → B → C in a single server action ----------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Subject = ACk_AutoTest_NetSubject::Find(InServer);
            auto* SmSubject = Cast<ACk_AutoTest_NetSubject_StateMachineNoHistory_UE>(Subject);
            if (SmSubject == nullptr)
            { AddError(TEXT("server-side NoHistory SM subject not found")); return; }
            if (ck::Is_NOT_Valid(SmSubject->_TestStateMachine))
            { AddError(TEXT("server-side _TestStateMachine not populated by entity-script Construct")); return; }

            UCk_Utils_StateMachine_UE::Request_Transition(SmSubject->_TestStateMachine,
                UCk_AutoTest_Sm_RecordingState_B::StaticClass(), {});
            UCk_Utils_StateMachine_UE::Request_Transition(SmSubject->_TestStateMachine,
                UCk_AutoTest_Sm_RecordingState_C::StaticClass(), {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterTransitions));

    // ---- Assertions ------------------------------------------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);

            if (Server == nullptr || Client == nullptr)
            {
                AddError(TEXT("server and/or client world unavailable at assertion time"));
                return false;
            }

            const auto ExpectedFinalClass =
                TSubclassOf<UCk_SmState_EntityScript>{UCk_AutoTest_Sm_RecordingState_C::StaticClass()};

            // ---- Server final state is C ---------------------------------------------------------------------

            auto* ServerSubject = Cast<ACk_AutoTest_NetSubject_StateMachineNoHistory_UE>(
                ACk_AutoTest_NetSubject::Find(Server));
            if (ServerSubject != nullptr && ck::IsValid(ServerSubject->_TestStateMachine))
            {
                TestEqual(TEXT("server SM final state class is C"),
                    UCk_Utils_StateMachine_UE::Get_CurrentStateClass(ServerSubject->_TestStateMachine).Get(),
                    ExpectedFinalClass.Get());
            }
            else
            {
                AddError(TEXT("server-side NoHistory SM subject / _TestStateMachine missing at assertion time"));
            }

            // ---- Client snapped to final state C -------------------------------------------------------------
            // The core WithoutHistory contract: the client converges to the latest state via the
            // NoHistory rep payload, independent of how many intermediate transitions the server made.

            auto* ClientSubject = Cast<ACk_AutoTest_NetSubject_StateMachineNoHistory_UE>(
                ACk_AutoTest_NetSubject::Find(Client));
            if (ClientSubject != nullptr && ck::IsValid(ClientSubject->_TestStateMachine))
            {
                TestEqual(TEXT("client SM snapped to final state class C"),
                    UCk_Utils_StateMachine_UE::Get_CurrentStateClass(ClientSubject->_TestStateMachine).Get(),
                    ExpectedFinalClass.Get());
            }
            else
            {
                AddError(TEXT("client-side NoHistory SM subject / _TestStateMachine missing at assertion time"));
            }

            // ---- Client recorder's most-recent Enter is C ----------------------------------------------------

            auto* ClientRecorder = Client->GetSubsystem<UCk_AutoTest_Sm_RecorderSubsystem>();
            if (ClientRecorder == nullptr)
            {
                AddError(TEXT("client recorder subsystem missing"));
                return false;
            }

            const auto& ClientAll = ClientRecorder->Get_Events();
            const FCk_AutoTest_Sm_RecordedEvent* LastEnter = nullptr;
            for (const auto& E : ClientAll)
            {
                if (E.Kind == ECk_AutoTest_Sm_EventKind::EnterState)
                { LastEnter = &E; }
            }

            if (LastEnter == nullptr)
            { AddError(TEXT("client recorder has no EnterState events at all — snap never landed")); }
            else
            {
                TestEqual(TEXT("client's most-recent EnterState is C"),
                    LastEnter->StateClass.Get(), ExpectedFinalClass.Get());
                TestEqual(TEXT("client's most-recent Enter has NetContext NonOwningClient"),
                    static_cast<int32>(LastEnter->NetContext),
                    static_cast<int32>(ECk_Sm_NetContext::NonOwningClient));
            }

            return true;
        }),
        TEXT("server-auth NoHistory: client snaps to final state C")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            FAutomationTestBase::bSuppressLogErrors = false;
            FAutomationTestBase::bSuppressLogWarnings = false;
            return true;
        }),
        TEXT("restore log suppression statics")));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
