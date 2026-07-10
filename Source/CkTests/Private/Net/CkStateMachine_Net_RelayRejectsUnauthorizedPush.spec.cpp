// Relay authorization — a client must not be able to drive an SM it does not own.
//
// The server spawns the ServerAuth/WithHistory SM subject (initial state A, server-owned — no
// client owns it). The remote client then abuses ITS OWN relay actor (UE only routes Server RPCs
// through the owning connection, so the attacker's vehicle is always its own relay) to push:
//   - Server_PushCurrentState  → tries to snap the server SM to C with a forged fingerprint,
//   - Server_PushTransitionBatch → tries to inject a forged A→C transition event,
//   - Server_PushRunStatus     → tries to stop the server SM.
//
// All three must be rejected by DoGet_IsAuthorizedOwningClientPush (the SM is ServerAuthoritative
// and not owned by the pushing connection). Before the 2026-07 fix the handlers only validated
// handle resolution — the pushes would drive the transition, stop the SM, and a forged
// fingerprint could stamp FTag_Sm_DeterminismFault on the server's SM (one-RPC quarantine).
//
// Surface in Session Frontend: Ck.StateMachine.Net.Relay_RejectsUnauthorizedPush

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "EngineUtils.h"
#include "Engine/World.h"

#include "CkStateMachine/Net/CkStateMachineRelay_Actor.h"
#include "CkStateMachine/Net/CkStateMachine_TestSupport.h"
#include "CkStateMachine/StateMachine/CkStateMachine_Utils.h"

#include "CkTests/Net/CkAutoTest_NetSubject.h"
#include "CkTests/Net/CkAutoTest_NetSubject_StateMachine.h"
#include "CkTests/Net/CkAutoTest_Sm_RecordingState.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_sm_relay_reject_test
{
    auto Find_SmSubject(UWorld* InWorld) -> ACk_AutoTest_NetSubject_StateMachine_UE*
    {
        return Cast<ACk_AutoTest_NetSubject_StateMachine_UE>(ACk_AutoTest_NetSubject::Find(InWorld));
    }

    // The client's own relay: the one actor of the relay class on the client world with a local
    // net owner. Calling a Server RPC on a relay the client does NOT own is silently dropped by
    // UE (which would make this test pass vacuously), so the locally-owned one is required.
    auto Find_LocallyOwnedRelay(UWorld* InWorld) -> ACk_StateMachineRelay_UE*
    {
        if (InWorld == nullptr)
        { return nullptr; }

        for (auto It = TActorIterator<ACk_StateMachineRelay_UE>(InWorld); It; ++It)
        {
            if (It->HasLocalNetOwner())
            { return *It; }
        }
        return nullptr;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkStateMachineNet_Relay_RejectsUnauthorizedPush,
    "Ck.StateMachine.Net.Relay_RejectsUnauthorizedPush",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkStateMachineNet_Relay_RejectsUnauthorizedPush::RunTest(const FString& Parameters)
{
    // The rejected pushes intentionally log warnings server-side; ambient multi-client Iris noise
    // is suppressed like the rest of the suite. Restored after teardown.
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesAfterSpawn = 30;
    constexpr auto FramesAfterPush = 40;
    constexpr auto ForgedFingerprint = 0x0BADF00D;
    constexpr auto ForgedSeq = 99;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

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

    // ---- Preconditions: subject + SM on both worlds, client has a locally-owned relay ------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            auto* ClientSubject = ck_sm_relay_reject_test::Find_SmSubject(Client);
            return ClientSubject != nullptr
                && ck::IsValid(ClientSubject->_TestStateMachine)
                && ck_sm_relay_reject_test::Find_LocallyOwnedRelay(Client) != nullptr;
        }),
        15.0,
        TEXT("client subject SM + locally-owned relay actor available")));

    // ---- The abuse: client pushes forged state/batch/status for a ServerAuth SM it doesn't own ---------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InClient) -> void
        {
            auto* ClientSubject = ck_sm_relay_reject_test::Find_SmSubject(InClient);
            if (ClientSubject == nullptr || ck::Is_NOT_Valid(ClientSubject->_TestStateMachine))
            { AddError(TEXT("client-side subject / _TestStateMachine missing at push time")); return; }

            auto* Relay = ck_sm_relay_reject_test::Find_LocallyOwnedRelay(InClient);
            if (Relay == nullptr)
            { AddError(TEXT("client-side locally-owned relay actor not found at push time")); return; }

            const auto TargetSm = FCk_Handle{ClientSubject->_TestStateMachine};

            Relay->Server_PushCurrentState(TargetSm,
                UCk_AutoTest_Sm_RecordingState_C::StaticClass(), ForgedSeq, ForgedFingerprint);

            auto ForgedEvent = FCk_Sm_TransitionEvent{
                UCk_AutoTest_Sm_RecordingState_A::StaticClass(),
                UCk_AutoTest_Sm_RecordingState_C::StaticClass(),
                ForgedSeq,
                ForgedFingerprint};
            Relay->Server_PushTransitionBatch(TargetSm, TArray<FCk_Sm_TransitionEvent>{ForgedEvent});

            Relay->Server_PushRunStatus(TargetSm, ECk_SmRunStatus::Stopped);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterPush));

    // ---- Server SM must be untouched --------------------------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto* ServerSubject = ck_sm_relay_reject_test::Find_SmSubject(Server);
            if (ServerSubject == nullptr || ck::Is_NOT_Valid(ServerSubject->_TestStateMachine))
            { AddError(TEXT("server-side subject / _TestStateMachine missing at assertion time")); return false; }

            auto& ServerSm = ServerSubject->_TestStateMachine;

            TestEqual(TEXT("server SM still in its initial state (forged transition rejected)"),
                UCk_Utils_StateMachine_UE::Get_CurrentStateClass(ServerSm).Get(),
                static_cast<UClass*>(UCk_AutoTest_Sm_RecordingState_A::StaticClass()));
            TestEqual(TEXT("server SM still Running (forged stop rejected)"),
                static_cast<int32>(UCk_Utils_StateMachine_UE::Get_RunStatus(ServerSm)),
                static_cast<int32>(ECk_SmRunStatus::Running));
            TestFalse(TEXT("server SM has no determinism fault (forged fingerprint rejected)"),
                UCk_Utils_StateMachine_Test_UE::Test_Get_HasDeterminismFault(ServerSm));

            return true;
        }),
        TEXT("unauthorized relay pushes are rejected — server SM untouched")));

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
