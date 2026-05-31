// Regression guard for the state-sub-graph replication fix.
//
// A Replicates / ServerAuthoritative / WithHistory SM is spawned via the shared NetSubject
// (ACk_AutoTest_NetSubject_StateMachine_UE) so it Constructs symmetrically on the server and the
// non-owning client. The bug this pins: SmState/SmCondition/SmTask entity-scripts used to derive
// their replication from the owning SM's params, so a Replicates SM made the server push every
// state entity out as its OWN Iris net object. The non-owning client then reconstructed a second,
// malformed copy via the replication SpawnProcessor (no FFragment_RecordOfSmTransitions, owner ref
// resolving to a tombstone) — the orphaned initial-state husks that tripped CastChecked on BeginPlay.
//
// The fix forces UCk_SmState_EntityScript::Get_EffectiveReplication (and the SmCondition/SmTask
// equivalents) to always return DoesNotReplicate: the SM's transition-history container fragment is
// the sole transport, and clients rebuild the state sub-graph locally via the replay path. This
// test asserts the invariant directly on the live entity-script instance — on BOTH worlds the SM's
// current-state entity must report DoesNotReplicate even though the SM itself Replicates. Reverting
// the override flips this assertion. (Get_EntityReplication reads the net-params fragment, which is
// a different value, so we query the entity-script's Get_EffectiveReplication — the actual source of
// truth the spawn path consults.)
//
// Surface in Session Frontend: Ck.StateMachine.Net.StateSubGraph_NotIndependentlyReplicated

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkCore/Enums/CkEnums.h"

#include "CkEcs/EntityScript/CkEntityScript_Fragment.h"

#include "CkStateMachine/State/EntityScripts/CkSmState_EntityScript.h"
#include "CkStateMachine/StateMachine/CkStateMachine_Utils.h"

#include "CkTests/Net/CkAutoTest_NetSubject.h"
#include "CkTests/Net/CkAutoTest_NetSubject_StateMachine.h"
#include "CkTests/Net/CkAutoTest_Sm_RecordingState.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_sm_norep_test
{
    // Reads the live entity-script instance off the SM's current-state entity and returns its
    // effective replication. AddError + empty optional on any structural miss so the failure reads
    // as "couldn't resolve the state script" rather than an opaque replication mismatch.
    auto Get_CurrentStateEffectiveReplication(
        FAutomationTestBase* InTest,
        const FCk_Handle_StateMachine& InSm,
        const TCHAR* InWho) -> TOptional<ECk_Replication>
    {
        if (ck::Is_NOT_Valid(InSm))
        { InTest->AddError(FString::Printf(TEXT("%s: SM handle invalid"), InWho)); return {}; }

        auto StateHandle = UCk_Utils_StateMachine_UE::Get_CurrentStateHandle(InSm);
        if (ck::Is_NOT_Valid(StateHandle))
        { InTest->AddError(FString::Printf(TEXT("%s: SM current-state handle invalid"), InWho)); return {}; }

        if (StateHandle.Has<ck::FFragment_EntityScript_Current>() == false)
        { InTest->AddError(FString::Printf(TEXT("%s: current-state entity has no EntityScript fragment"), InWho)); return {}; }

        auto* Script = StateHandle.Get<ck::FFragment_EntityScript_Current>().Get_Script().Get();
        if (Cast<UCk_SmState_EntityScript>(Script) == nullptr)
        { InTest->AddError(FString::Printf(TEXT("%s: current-state script is not a UCk_SmState_EntityScript"), InWho)); return {}; }

        // Get_EffectiveReplication is public on the UCk_EntityScript_UE base (protected on the
        // SmState subclass); call through the base pointer so virtual dispatch reaches the override.
        return static_cast<UCk_EntityScript_UE*>(Script)->Get_EffectiveReplication();
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkStateMachineNet_StateSubGraph_NotIndependentlyReplicated,
    "Ck.StateMachine.Net.StateSubGraph_NotIndependentlyReplicated",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkStateMachineNet_StateSubGraph_NotIndependentlyReplicated::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesAfterSpawn = 30;        // setup + RepData propagation + Construct on both worlds
    constexpr auto FramesAfterTransition = 30;   // A→B rep convergence so both worlds have a current state

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // ---- Spawn the Replicates/ServerAuth SM subject on the server -------------------------------------------

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

    // ---- Transition A → B so both worlds have a well-defined current state ----------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* SmSubject = Cast<ACk_AutoTest_NetSubject_StateMachine_UE>(ACk_AutoTest_NetSubject::Find(InServer));
            if (SmSubject == nullptr)
            { AddError(TEXT("server-side SM subject not found / not the expected subclass")); return; }
            if (ck::Is_NOT_Valid(SmSubject->_TestStateMachine))
            { AddError(TEXT("server-side _TestStateMachine wasn't populated by entity-script Construct")); return; }

            UCk_Utils_StateMachine_UE::Request_Transition(SmSubject->_TestStateMachine,
                UCk_AutoTest_Sm_RecordingState_B::StaticClass());
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterTransition));

    // ---- Assert: the SM Replicates, but its state sub-graph entities do NOT ---------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Server == nullptr || Client == nullptr)
            { AddError(TEXT("server and/or client world unavailable at assertion time")); return false; }

            // ---- Server: the SM is the authority and replicates; its state must not -------------------------

            auto* ServerSubject = Cast<ACk_AutoTest_NetSubject_StateMachine_UE>(ACk_AutoTest_NetSubject::Find(Server));
            if (ServerSubject != nullptr && ck::IsValid(ServerSubject->_TestStateMachine))
            {
                const auto ServerStateRep = ck_sm_norep_test::Get_CurrentStateEffectiveReplication(
                    this, ServerSubject->_TestStateMachine, TEXT("server"));
                if (ServerStateRep.IsSet())
                {
                    TestEqual(TEXT("server: current-state entity-script Get_EffectiveReplication is DoesNotReplicate"),
                        static_cast<int32>(ServerStateRep.GetValue()),
                        static_cast<int32>(ECk_Replication::DoesNotReplicate));
                }
            }
            else
            { AddError(TEXT("server-side SM subject / _TestStateMachine missing at assertion time")); }

            // ---- Client (non-owning): only the locally-replayed state should exist, also non-replicating ----

            auto* ClientSubject = Cast<ACk_AutoTest_NetSubject_StateMachine_UE>(ACk_AutoTest_NetSubject::Find(Client));
            if (ClientSubject != nullptr && ck::IsValid(ClientSubject->_TestStateMachine))
            {
                const auto ClientStateRep = ck_sm_norep_test::Get_CurrentStateEffectiveReplication(
                    this, ClientSubject->_TestStateMachine, TEXT("client"));
                if (ClientStateRep.IsSet())
                {
                    TestEqual(TEXT("client: current-state entity-script Get_EffectiveReplication is DoesNotReplicate"),
                        static_cast<int32>(ClientStateRep.GetValue()),
                        static_cast<int32>(ECk_Replication::DoesNotReplicate));
                }
            }
            else
            { AddError(TEXT("client-side SM subject / _TestStateMachine missing at assertion time")); }

            return true;
        }),
        TEXT("Replicates SM keeps its state sub-graph local (DoesNotReplicate) on both worlds")));

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
