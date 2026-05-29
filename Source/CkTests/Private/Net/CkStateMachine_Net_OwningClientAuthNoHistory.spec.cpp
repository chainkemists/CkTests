// Owning-client-authoritative + WithoutHistory snap replication.
//
// Closes the one auth x history pairing the other SM net specs don't cover (ServerAuth+History,
// ServerAuth+NoHistory, OwningClient+History already exist). Spawns
// ACk_AutoTest_NetSubject_StateMachineOwningClientNoHistory_Pawn on the server, possesses it with
// the remote client's PlayerController so the client is the owning authority. The bridged
// entity-script builds a Replicates / OwningClientAuthoritative / WithoutHistory SM (initial A).
// The owning client commits A→B then B→C locally and publishes through ACk_StateMachineRelay_UE;
// the server applies and the NoHistory rep payload snaps it to the latest state. Both worlds should
// converge to C (no replay ring — snap-to-current).
//
// Mirrors OwningClientAuth_LocalCommitReplicates but with the NoHistory rep model and a two-step
// transition to exercise snap-over-multiple-commits.
//
// Surface in Session Frontend: Ck.StateMachine.Net.OwningClientAuth_NoHistory_SnapReplicates

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "EngineUtils.h"
#include "Engine/World.h"
#include "GameFramework/PlayerController.h"

#include "CkEcs/Net/CkNet_Utils.h"
#include "CkStateMachine/StateMachine/CkStateMachine_Utils.h"

#include "CkTests/Net/CkAutoTest_NetSubject_StateMachineOwningClientPawn.h"
#include "CkTests/Net/CkAutoTest_Sm_RecordingState.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_sm_owningclient_nohistory_test
{
    auto Find_PawnSubject(UWorld* InWorld) -> ACk_AutoTest_NetSubject_StateMachineOwningClientNoHistory_Pawn*
    {
        if (InWorld == nullptr)
        { return nullptr; }
        for (auto It = TActorIterator<ACk_AutoTest_NetSubject_StateMachineOwningClientNoHistory_Pawn>(InWorld); It; ++It)
        { return *It; }
        return nullptr;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkStateMachineNet_OwningClientAuth_NoHistory_SnapReplicates,
    "Ck.StateMachine.Net.OwningClientAuth_NoHistory_SnapReplicates",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkStateMachineNet_OwningClientAuth_NoHistory_SnapReplicates::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesAfterSpawn = 30;
    constexpr auto FramesAfterPossess = 30;
    constexpr auto FramesAfterStart = 30;
    constexpr auto FramesAfterTransition = 40;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // ---- Spawn the NoHistory owning-client pawn on the server ----------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            auto* Subject = InServer->SpawnActor<ACk_AutoTest_NetSubject_StateMachineOwningClientNoHistory_Pawn>(
                ACk_AutoTest_NetSubject_StateMachineOwningClientNoHistory_Pawn::StaticClass(), FTransform::Identity, SpawnInfo);
            if (Subject == nullptr)
            { AddError(TEXT("server-side SpawnActor of OwningClient NoHistory pawn returned null")); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterSpawn));

    // ---- Possess with the remote client's PlayerController --------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Pawn = ck_sm_owningclient_nohistory_test::Find_PawnSubject(InServer);
            if (Pawn == nullptr)
            { AddError(TEXT("server-side NoHistory pawn not found at possession time")); return; }

            auto* ClientPC = ck::auto_test::net::Get_RemoteClientPlayerController(InServer, 0);
            if (ClientPC == nullptr)
            { AddError(TEXT("could not resolve remote client[0] PlayerController on the server")); return; }

            ClientPC->Possess(Pawn);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterPossess));

    // ---- Precondition: ownership resolved on the client ----------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr)
            { AddError(TEXT("client world unavailable at precondition check")); return false; }

            auto* ClientPawn = ck_sm_owningclient_nohistory_test::Find_PawnSubject(Client);
            if (ClientPawn == nullptr)
            { AddError(TEXT("client-side NoHistory pawn not found — did it replicate?")); return false; }

            const auto LocallyControlled =
                UCk_Utils_Net_UE::Get_IsActorLocallyControlled_ByPlayer(ClientPawn);
            TestEqual(TEXT("PRECONDITION: client pawn is locally-controlled-by-player (possession resolved)"),
                static_cast<int32>(LocallyControlled),
                static_cast<int32>(ECk_Utils_Net_IsLocallyControlled_Result::IsLocallyControlled));

            return true;
        }),
        TEXT("ownership precondition — possession resolved on client")));

    // ---- Owning client starts the SM + pre-warms the relay channel -----------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InClient) -> void
        {
            auto* ClientPawn = ck_sm_owningclient_nohistory_test::Find_PawnSubject(InClient);
            if (ClientPawn == nullptr)
            { AddError(TEXT("client-side pawn not found at start time")); return; }
            if (ck::Is_NOT_Valid(ClientPawn->_TestStateMachine))
            { AddError(TEXT("client-side _TestStateMachine not populated by entity-script Construct")); return; }

            UCk_Utils_StateMachine_UE::Request_Start(ClientPawn->_TestStateMachine);
            UCk_Utils_StateMachine_UE::Acquire_RelayChannel(ClientPawn->_TestStateMachine);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterStart));

    // ---- Owning client commits A → B ----------------------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InClient) -> void
        {
            auto* ClientPawn = ck_sm_owningclient_nohistory_test::Find_PawnSubject(InClient);
            if (ClientPawn == nullptr)
            { AddError(TEXT("client-side pawn not found at A->B")); return; }

            UCk_Utils_StateMachine_UE::Request_Transition(ClientPawn->_TestStateMachine,
                UCk_AutoTest_Sm_RecordingState_B::StaticClass());
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterTransition));

    // ---- Owning client commits B → C ----------------------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InClient) -> void
        {
            auto* ClientPawn = ck_sm_owningclient_nohistory_test::Find_PawnSubject(InClient);
            if (ClientPawn == nullptr)
            { AddError(TEXT("client-side pawn not found at B->C")); return; }

            UCk_Utils_StateMachine_UE::Request_Transition(ClientPawn->_TestStateMachine,
                UCk_AutoTest_Sm_RecordingState_C::StaticClass());
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterTransition));

    // ---- Assertions: both worlds snapped to C -------------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Server == nullptr || Client == nullptr)
            { AddError(TEXT("server and/or client world unavailable at assertion time")); return false; }

            const auto ExpectedClass =
                TSubclassOf<UCk_SmState_EntityScript>{UCk_AutoTest_Sm_RecordingState_C::StaticClass()};

            // Owning client (authority) committed locally → at C.
            auto* ClientPawn = ck_sm_owningclient_nohistory_test::Find_PawnSubject(Client);
            if (ClientPawn != nullptr && ck::IsValid(ClientPawn->_TestStateMachine))
            {
                TestEqual(TEXT("owning-client SM is at C (local commit)"),
                    UCk_Utils_StateMachine_UE::Get_CurrentStateClass(ClientPawn->_TestStateMachine).Get(),
                    ExpectedClass.Get());
            }
            else
            { AddError(TEXT("client pawn / _TestStateMachine missing at assertion time")); }

            // Server applied the relayed commits; NoHistory snaps to the latest → at C.
            auto* ServerPawn = ck_sm_owningclient_nohistory_test::Find_PawnSubject(Server);
            if (ServerPawn != nullptr && ck::IsValid(ServerPawn->_TestStateMachine))
            {
                TestEqual(TEXT("server SM snapped to latest relayed state → at C"),
                    UCk_Utils_StateMachine_UE::Get_CurrentStateClass(ServerPawn->_TestStateMachine).Get(),
                    ExpectedClass.Get());
            }
            else
            { AddError(TEXT("server pawn / _TestStateMachine missing at assertion time")); }

            return true;
        }),
        TEXT("owning-client NoHistory: both worlds snap to final state C")));

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
