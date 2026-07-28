// Phase 1 of the multi-client AutoTest harness rollout — the canonical "does CkAttribute's
// post-Override value replicate from server to client" test. The subject's entity-script
// (UCk_AutoTest_NetSubject_EntityScript_UE) adds a Float attribute on *both* worlds during its
// Construct; the spec then issues a Request_Override on the server and asserts both server and
// client see the post-Override value after a settle window. With replication broken, the client
// would still hold the entity-script's initial value (42.5f), so the test fails loudly.
//
// Surface in Session Frontend: Ck.Attribute.Net.Float_InitialValue_Replicates

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkAttribute/FloatAttribute/CkFloatAttribute_Fragment_Data.h"
#include "CkAttribute/FloatAttribute/CkFloatAttribute_Utils.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "CkTests/Net/CkAutoTest_NetSubject.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace
{
    // Float attribute identifier. Must match what UCk_AutoTest_NetSubject_EntityScript_UE adds
    // in its Construct — FloatAttribute.Health is registered in Config/DefaultGameplayTags.ini
    // and reused across the standalone CkAttribute AutoTests.
    constexpr auto Replicates_SubjectAttributeTagName = TEXT("FloatAttribute.Health");

    // Post-override value the server-side lambda writes. Distinct from the entity-script's
    // initial value (42.5f) so a *missing* replication shows up as a clear mismatch on the
    // client (which would still hold the initial 42.5) rather than coincidentally matching.
    constexpr auto Replicates_SubjectOverrideValue = 100.0f;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkAttributeNet_Float_InitialValue_Replicates,
    "Ck.Attribute.Net.Float_InitialValue_Replicates",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkAttributeNet_Float_InitialValue_Replicates::RunTest(const FString& Parameters)
{
    // CkActorRelay × Iris ambient noise under multi-client PIE — same backstop the SM
    // replication tests use. Restored at the end via a trailing latent command.
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    // Settle window after the subject actor spawn — gives the WithActor entity-script construction
    // path time to run on both server and client (it's deferred through the ECS scheduler) and
    // sets up the bridge component on each side.
    constexpr auto FramesAfterSpawn = 30;
    // Settle window after the server-side attribute Add. CkAttribute replicates via a container
    // fragment (FCk_RepData_FloatAttributes) on the owner entity — a SyncReplication processor on
    // the client side reads the container and reconstructs the per-attribute child entities.
    // Generous window because that reconstruction is multi-stage (Iris ships the container; the
    // SyncReplication handler fires; child entities get spawned; their gameplay-tag labels and
    // value fragments populate). 120 frames @ ~60fps ≈ 2s — well beyond what should be needed,
    // but harmless on a passing test and lets timing-related failures show up clearly.
    constexpr auto FramesAfterAdd = 120;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    // Shared slot — the second server lambda populates the owner entity handle (resolved from
    // the actor *after* the WithActor bridge has had time to construct); the assertion lambda
    // reads it back for the server-side sanity check.
    auto OwnerSlot = MakeShared<FCk_Handle>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // ---- Stage 1 — server spawns the subject actor. The actor's BeginPlay schedules a -------------------------
    // ---- Request_SpawnEntity for a UCk_EntityScript_WithActor_UE entity; its Construct (which ------------------
    // ---- adds the Actor↔Entity bridge component) runs on both server and client via the --------------------
    // ---- entity-script lifecycle's replication path. ------------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;

            auto* Subject = InServer->SpawnActor<ACk_AutoTest_NetSubject>(
                ACk_AutoTest_NetSubject::StaticClass(), FTransform::Identity, SpawnInfo);

            if (Subject == nullptr)
            {
                AddError(TEXT("server-side spawn of ACk_AutoTest_NetSubject returned null"));
                return;
            }
        })));

    // Let the WithActor entity construct + the actor replicate to the client.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterSpawn));

    // ---- Stage 2 — resolve the bridged entity + attribute on the server, issue Request_Override. --------------
    // ---- The attribute itself was already added on both worlds by the entity-script's Construct --------------
    // ---- (UCk_AutoTest_NetSubject_EntityScript_UE::Construct). This stage drives the server-side -------------
    // ---- value change whose replication the assertion lambda verifies. ----------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, OwnerSlot](UWorld* InServer) -> void
        {
            auto* Subject = ACk_AutoTest_NetSubject::Find(InServer);
            if (Subject == nullptr)
            {
                AddError(TEXT("Stage 2: server-side subject actor missing — Stage 1 spawn never happened?"));
                return;
            }

            const auto OwnerEntity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(Subject);
            if (ck::Is_NOT_Valid(OwnerEntity))
            {
                AddError(TEXT("Stage 2: server-side TryGet_ActorEntityHandle returned invalid — WithActor::Construct did not run yet (extend FramesAfterSpawn?)"));
                return;
            }

            const auto AttributeTag = FGameplayTag::RequestGameplayTag(FName{Replicates_SubjectAttributeTagName});
            auto AttributeHandle = UCk_Utils_FloatAttribute_UE::TryGet(OwnerEntity, AttributeTag);
            if (ck::Is_NOT_Valid(AttributeHandle))
            {
                AddError(TEXT("Stage 2: server-side TryGet for the entity-script-added attribute returned invalid — Construct did not add it (check entity-script class wiring)"));
                return;
            }

            UCk_Utils_FloatAttribute_UE::Request_Override(AttributeHandle, Replicates_SubjectOverrideValue, ECk_MinMaxCurrent::Current, {});

            *OwnerSlot = OwnerEntity;
        })));

    // Let the override replicate from server to client (single-value rep, no entity creation
    // needed since the attribute entity already exists on both worlds via Construct).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterAdd));

    // ---- Cross-world assertion: server reads its own value, client reads the replicated one --------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, OwnerSlot]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);

            if (Server == nullptr || Client == nullptr)
            {
                AddError(TEXT("server and/or client world unavailable at assertion time"));
                return false;
            }

            const auto AttributeTag = FGameplayTag::RequestGameplayTag(FName{Replicates_SubjectAttributeTagName});

            // Server-side sanity — the post-override value we just wrote should be readable
            // locally. Failing here means Request_Override itself didn't take, not that
            // replication broke.
            if (ck::IsValid(*OwnerSlot))
            {
                auto ServerOwner = *OwnerSlot;
                const auto ServerAttribute = UCk_Utils_FloatAttribute_UE::TryGet(ServerOwner, AttributeTag);
                if (ck::Is_NOT_Valid(ServerAttribute))
                {
                    AddError(TEXT("server-side TryGet for the attribute returned an invalid handle"));
                }
                else
                {
                    const auto ServerValue = UCk_Utils_FloatAttribute_UE::Get_FinalValue(ServerAttribute);
                    TestEqual(TEXT("server FinalValue matches post-Override value"),
                        ServerValue, Replicates_SubjectOverrideValue);
                }
            }
            else
            {
                AddError(TEXT("server-side OwnerSlot was never populated (Stage 2 lambda bailed early?)"));
            }

            // Client-side — locate the replicated subject actor, walk back to its bridged
            // entity (the WithActor entity-script Construct adds the bridge component on both
            // worlds), look up the attribute (also added by Construct on both worlds), read
            // its FinalValue. With replication working, the client sees the server-side
            // Request_Override; without it, the client still holds the entity-script's initial
            // value (42.5f, see CkAutoTest_NetSubject_EntityScript.cpp).
            auto* ClientSubject = ACk_AutoTest_NetSubject::Find(Client);
            if (ClientSubject == nullptr)
            {
                AddError(TEXT("client world has no ACk_AutoTest_NetSubject — actor failed to replicate"));
                return false;
            }

            const auto ClientOwnerEntity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(ClientSubject);
            if (ck::Is_NOT_Valid(ClientOwnerEntity))
            {
                AddError(TEXT("client-side actor has no bridged entity — entity-script Construct did not run on client"));
                return false;
            }

            const auto ClientAttribute = UCk_Utils_FloatAttribute_UE::TryGet(ClientOwnerEntity, AttributeTag);
            if (ck::Is_NOT_Valid(ClientAttribute))
            {
                AddError(TEXT("client-side TryGet found no float attribute — entity-script Construct did not Add it on the client"));
                return false;
            }

            const auto ClientValue = UCk_Utils_FloatAttribute_UE::Get_FinalValue(ClientAttribute);
            TestEqual(TEXT("client FinalValue matches server-side post-Override value (replication propagated)"),
                ClientValue, Replicates_SubjectOverrideValue);

            return true;
        }),
        TEXT("CkAttribute float initial-value replicates from server to client")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    // Restore static log suppression after teardown so subsequent tests see default semantics.
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
