// Regression guard: a DoesNotReplicate SM must run its full lifecycle on a NON-owning client.
//
// A DoesNotReplicate / AutoStart-OnSetup SM is spawned via the shared NetSubject ACTOR (a
// server-replicated, NON-player object — the trashcan / shelf / truck shape). The entity-script
// Constructs the SM on BOTH worlds; the SM is local-only, so each machine is self-authoritative and
// auto-starts independently. The initial state is the AngelScript tick-gated UCk_SmNetSubTest_Sub_Wait
// (a Delay 0.3s task → TaskResults transition → UCk_SmNetSubTest_Sub_Reached).
//
// The bug this pins: on a client, a top-level SM on a non-player replicated entity resolves
// ComputeNetContext == NonOwningClient (not authority, owner not player-locally-controlled). The
// lifecycle processors (FProcessor_SmTask_Tick / FProcessor_SmCondition / FProcessor_SmTransition)
// early-return on NonOwningClient WITHOUT exempting DoesNotReplicate — so the client's Delay never
// ticks, the transition never evaluates, and the SM is stuck at Sub_Wait. This is exactly why every
// interaction HFSM (built with default DoesNotReplicate params via utils_state_machine::Add) is dead
// on remote clients while working on the host.
//
// PASS: the NON-owning client's SM advances to Sub_Reached. (Pre-fix it stays stuck at Sub_Wait.)
// The server (NetContext == Server, never gated) reaching Sub_Reached is the baseline that proves
// the topology is valid and isolates the failure to the client gate.
//
// Surface in Session Frontend: Ck.StateMachine.Net.DoesNotReplicate_RunsOnNonOwningClient

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkStateMachine/StateMachine/CkStateMachine_Utils.h"
#include "CkStateMachine/State/EntityScripts/CkSmState_EntityScript.h"

#include "CkTests/Net/CkAutoTest_NetSubject.h"
#include "CkTests/Net/CkAutoTest_NetSubject_StateMachine.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_sm_dnr_test
{
    // The AS class name has its leading 'U' stripped in the UClass FName.
    constexpr auto k_ReachedStateName = TEXT("Ck_SmNetSubTest_Sub_Reached");

    auto Find_Subject(UWorld* InWorld) -> ACk_AutoTest_NetSubject_StateMachine_UE*
    {
        if (InWorld == nullptr)
        { return nullptr; }
        return Cast<ACk_AutoTest_NetSubject_StateMachine_UE>(ACk_AutoTest_NetSubject::Find(InWorld));
    }

    auto Get_SmCurrentStateName(ACk_AutoTest_NetSubject_StateMachine_UE* InSubject) -> FString
    {
        if (InSubject == nullptr || ck::Is_NOT_Valid(InSubject->_TestStateMachine))
        { return {}; }

        const auto* CurrentClass = UCk_Utils_StateMachine_UE::Get_CurrentStateClass(InSubject->_TestStateMachine).Get();
        return CurrentClass != nullptr ? CurrentClass->GetName() : FString{};
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkStateMachineNet_DoesNotReplicate_RunsOnNonOwningClient,
    "Ck.StateMachine.Net.DoesNotReplicate_RunsOnNonOwningClient",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkStateMachineNet_DoesNotReplicate_RunsOnNonOwningClient::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesAfterSpawn = 30;   // construct on both worlds + setup + auto-start + initial-state entry

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // ---- Spawn the DoesNotReplicate SM subject on the server (a non-player replicated actor) ----------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            auto* Subject = InServer->SpawnActor<ACk_AutoTest_NetSubject_StateMachineDoesNotReplicate_UE>(
                ACk_AutoTest_NetSubject_StateMachineDoesNotReplicate_UE::StaticClass(), FTransform::Identity, SpawnInfo);
            if (Subject == nullptr)
            { AddError(TEXT("server-side SpawnActor of ACk_AutoTest_NetSubject_StateMachineDoesNotReplicate_UE returned null")); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterSpawn));

    // ---- Wait for the NON-owning client's SM to advance past the tick-gated Delay -------------------------
    // This is the regression target: it can only happen if the client's DoesNotReplicate SM ticks its
    // Delay task despite resolving NetContext == NonOwningClient. Pre-fix the lifecycle processors gate
    // NonOwningClient off (without exempting DoesNotReplicate) → Sub_Wait never completes → times out.

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr)
            { return false; }

            return ck_sm_dnr_test::Get_SmCurrentStateName(ck_sm_dnr_test::Find_Subject(Client))
                == ck_sm_dnr_test::k_ReachedStateName;
        }),
        10.0,
        TEXT("non-owning client DoesNotReplicate SM advances to Sub_Reached (tick-gated Delay ran)")));

    // ---- Assert: server (baseline) AND non-owning client both reached Sub_Reached -------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Server == nullptr || Client == nullptr)
            { AddError(TEXT("server and/or client world unavailable at assertion time")); return false; }

            // Server (NetContext == Server, never gated) — sanity baseline that the topology runs.
            auto* ServerSubject = ck_sm_dnr_test::Find_Subject(Server);
            if (ServerSubject != nullptr && ck::IsValid(ServerSubject->_TestStateMachine))
            {
                TestEqual(TEXT("server DoesNotReplicate SM is at Sub_Reached (baseline — Server context not gated)"),
                    ck_sm_dnr_test::Get_SmCurrentStateName(ServerSubject),
                    FString{ck_sm_dnr_test::k_ReachedStateName});
            }
            else
            { AddError(TEXT("server-side SM subject / _TestStateMachine missing at assertion time")); }

            // Non-owning client — the regression target. Stuck at Sub_Wait before the gate fix.
            auto* ClientSubject = ck_sm_dnr_test::Find_Subject(Client);
            if (ClientSubject != nullptr && ck::IsValid(ClientSubject->_TestStateMachine))
            {
                TestEqual(TEXT("non-owning client DoesNotReplicate SM advanced to Sub_Reached (lifecycle ran locally)"),
                    ck_sm_dnr_test::Get_SmCurrentStateName(ClientSubject),
                    FString{ck_sm_dnr_test::k_ReachedStateName});
            }
            else
            { AddError(TEXT("client-side SM subject / _TestStateMachine missing at assertion time")); }

            return true;
        }),
        TEXT("DoesNotReplicate SM runs its full lifecycle on both the server and the non-owning client")));

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
