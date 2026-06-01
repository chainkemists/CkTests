// Regression guard for the non-owning initial-state "first sync".
//
// A ServerAuthoritative / WithHistory SM (initial state A, AutoStart=OnSetup) is spawned via the
// shared NetSubject so it Constructs on the server and the non-owning client. The server auto-starts
// and enters A; run-status (Running) replicates to the client. NO transition is driven.
//
// The bug this pins: the WithHistory ring carries only transitions, and the initial-state entry is
// not a transition — so a non-owning machine learned the SM was Running but never entered its initial
// state, leaving Get_CurrentStateClass() == null (the gym's SM=<none>). The fix (MirrorRunStatus tags
// + FProcessor_Sm_FirstSyncInitialState) makes the non-owning machine enter its locally-known initial
// state on the first run-status sync. This test asserts the client's current state is A before any
// transition — it would be null before the fix.
//
// Surface in Session Frontend: Ck.StateMachine.Net.InitialState_FirstSyncOnNonOwningClient

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkStateMachine/StateMachine/CkStateMachine_Utils.h"

#include "CkTests/Net/CkAutoTest_NetSubject.h"
#include "CkTests/Net/CkAutoTest_NetSubject_StateMachine.h"
#include "CkTests/Net/CkAutoTest_Sm_RecordingState.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkStateMachineNet_InitialState_FirstSyncOnNonOwningClient,
    "Ck.StateMachine.Net.InitialState_FirstSyncOnNonOwningClient",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkStateMachineNet_InitialState_FirstSyncOnNonOwningClient::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesAfterSpawn = 30;   // setup + auto-start + run-status replication + first-sync

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // ---- Spawn the ServerAuth/WithHistory SM subject on the server (auto-starts at A) ------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            auto* Subject = InServer->SpawnActor<ACk_AutoTest_NetSubject_StateMachine_UE>(
                ACk_AutoTest_NetSubject_StateMachine_UE::StaticClass(), FTransform::Identity, SpawnInfo);
            if (Subject == nullptr)
            { AddError(TEXT("server-side SpawnActor of ACk_AutoTest_NetSubject_StateMachine_UE returned null")); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterSpawn));

    // ---- Assert: BOTH worlds are at the initial state A, with NO transition ever driven --------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Server == nullptr || Client == nullptr)
            { AddError(TEXT("server and/or client world unavailable at assertion time")); return false; }

            const auto ExpectedInitial =
                TSubclassOf<UCk_SmState_EntityScript>{UCk_AutoTest_Sm_RecordingState_A::StaticClass()};

            // Server (authority) entered A via auto-start DoStart — sanity baseline.
            auto* ServerSubject = Cast<ACk_AutoTest_NetSubject_StateMachine_UE>(ACk_AutoTest_NetSubject::Find(Server));
            if (ServerSubject != nullptr && ck::IsValid(ServerSubject->_TestStateMachine))
            {
                TestEqual(TEXT("server SM is at initial state A"),
                    UCk_Utils_StateMachine_UE::Get_CurrentStateClass(ServerSubject->_TestStateMachine).Get(),
                    ExpectedInitial.Get());
            }
            else
            { AddError(TEXT("server-side SM subject / _TestStateMachine missing at assertion time")); }

            // Non-owning client: the first-sync must have entered A (would be null before the fix).
            auto* ClientSubject = Cast<ACk_AutoTest_NetSubject_StateMachine_UE>(ACk_AutoTest_NetSubject::Find(Client));
            if (ClientSubject != nullptr && ck::IsValid(ClientSubject->_TestStateMachine))
            {
                TestEqual(TEXT("non-owning client first-synced to initial state A (not <none>)"),
                    UCk_Utils_StateMachine_UE::Get_CurrentStateClass(ClientSubject->_TestStateMachine).Get(),
                    ExpectedInitial.Get());
            }
            else
            { AddError(TEXT("client-side SM subject / _TestStateMachine missing at assertion time")); }

            return true;
        }),
        TEXT("non-owning client reflects the initial state via first-sync, before any transition")));

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
