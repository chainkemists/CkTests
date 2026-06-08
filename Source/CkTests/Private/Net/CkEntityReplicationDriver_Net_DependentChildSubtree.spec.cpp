// Regression test: a wide REPLICATED dependent subtree fully constructs on the client.
//
// A single replicated WithActor PARENT entity-script whose Construct fans out a wide set of replicated
// DEPENDENT CHILD entity-scripts (see ACk_AutoTest_NetSubject_DependentSubtree_UE). On a 2-PIE
// listen-server we assert the whole subtree reports replication-complete on the CLIENT.
//
// Context: this exercises the EntityReplicationDriver dependent-subtree path that the (never-drained)
// `_PendingChildEntityConstructions` park branch belongs to. A 2026-06 investigation established that
// the park branch is unreachable for this same-actor topology — all child drivers are subobjects on the
// parent's Actor, so the parent's associated entity is always valid before any child OnReps — and that a
// child can only park if its owner driver is constructed without a UWorld (which now logs a loud
// warning). This test is the positive guard: the wide subtree must replicate cleanly, and because the
// AutoTest harness escalates warnings, any owner-no-world / park condition would also fail it.
//
// A server-side cross-check first confirms the children ARE set up as dependent drivers, so the client
// "replication complete on all dependents" check can't pass vacuously.
//
// Surface in Session Frontend: Ck.EntityReplicationDriver.Net.DependentChildSubtreeConstructs

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkEcs/OwningActor/CkOwningActor_Utils.h"
#include "CkEcs/Net/EntityReplicationDriver/CkEntityReplicationDriver_Utils.h"

#include "CkTests/Net/CkAutoTest_NetSubject_DependentSubtree.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkEntityReplicationDriverNet_DependentChildSubtreeConstructs,
    "Ck.EntityReplicationDriver.Net.DependentChildSubtreeConstructs",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkEntityReplicationDriverNet_DependentChildSubtreeConstructs::RunTest(const FString& Parameters)
{
    using namespace ck::auto_test::dependent_subtree;

    // CkActorRelay x Iris ambient noise under multi-client PIE — suppress so it doesn't escalate to
    // spurious failures. Restored at the end. The real verdict is the assertion below.
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;        // listen-server + 1 client
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesAfterSpawn = 60;    // parent + children construct on server, start replicating
    constexpr auto CompleteTimeoutSeconds = 15.0;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // ---- Server spawns the dependent-subtree subject --------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;

            auto* Subject = InServer->SpawnActor<ACk_AutoTest_NetSubject_DependentSubtree_UE>(
                ACk_AutoTest_NetSubject_DependentSubtree_UE::StaticClass(), FTransform::Identity, SpawnInfo);

            if (Subject == nullptr)
            { AddError(TEXT("server-side SpawnActor of the dependent-subtree subject returned null")); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterSpawn));

    // ---- Server cross-check: the children really are dependent drivers of the parent ------------------------
    // Guards against a vacuous pass: if the parent's expected-dependents count were ~0, the client
    // "replication complete on all dependents" check would be trivially true.

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr)
            { AddError(TEXT("server world unavailable at cross-check time")); return false; }

            auto* Subject = ACk_AutoTest_NetSubject_DependentSubtree_UE::Find(Server);
            if (Subject == nullptr)
            { AddError(TEXT("server-side dependent-subtree subject not found — did Stage 1 spawn happen?")); return false; }

            const auto ServerParent = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(Subject);
            if (ck::Is_NOT_Valid(ServerParent))
            { AddError(TEXT("server-side parent entity not resolved — WithActor Construct did not run (extend FramesAfterSpawn?)")); return false; }

            const auto NumDrivers =
                UCk_Utils_EntityReplicationDriver_UE::Get_NumOfReplicationDriversIncludingDependents(ServerParent);

            // self (parent) + NumDependentChildren. Use >= so an extra internal sub-entity driver
            // doesn't make this brittle — the point is that the wide fan is genuinely dependents.
            TestTrue(
                FString::Printf(TEXT("server parent has at least %d dependent replication drivers (got %d)"),
                    NumDependentChildren, NumDrivers),
                NumDrivers >= NumDependentChildren);

            return true;
        }),
        TEXT("server-side dependent-driver count cross-check")));

    // ---- Wait for the whole subtree to report replication-complete on the CLIENT ----------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr)
            { return false; }

            auto* Subject = ACk_AutoTest_NetSubject_DependentSubtree_UE::Find(Client);
            if (Subject == nullptr)
            { return false; }

            const auto ClientParent = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(Subject);
            if (ck::Is_NOT_Valid(ClientParent))
            { return false; }

            return UCk_Utils_EntityReplicationDriver_UE::Get_IsReplicationCompleteAllDependents(ClientParent);
        }),
        CompleteTimeoutSeconds,
        TEXT("client: parent's entire dependent subtree reports replication-complete")));

    // ---- Final verdict --------------------------------------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr)
            { AddError(TEXT("client world unavailable at assertion time")); return false; }

            auto* Subject = ACk_AutoTest_NetSubject_DependentSubtree_UE::Find(Client);
            if (Subject == nullptr)
            { AddError(TEXT("client world has no dependent-subtree subject — actor failed to replicate")); return false; }

            const auto ClientParent = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(Subject);
            if (ck::Is_NOT_Valid(ClientParent))
            { AddError(TEXT("client-side parent entity not resolved — WithActor Construct did not run on the client")); return false; }

            const auto Complete =
                UCk_Utils_EntityReplicationDriver_UE::Get_IsReplicationCompleteAllDependents(ClientParent);

            TestTrue(
                TEXT("client parent's dependent subtree replication completed on all dependents"),
                Complete);

            return Complete;
        }),
        TEXT("dependent-child subtree fully constructs on the client")));

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
