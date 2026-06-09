// Regression test for the pending-replication stash drain (FProcessor_FloatAttribute_RetryPendingReplication).
// A replicated attribute value can arrive on a client BEFORE that client has composed the attribute —
// e.g. composition driven from an OnConstructed callback runs after the replication driver's PostLink
// replay. The rep handler stashes the value into FFragment_FloatAttribute_PendingReplicationEntries;
// the retry processor must drain it once the attribute exists. With the processor unregistered (the
// original bug), the client keeps its locally-composed initial value forever and this test fails.
//
// Shape: the server adds a SECOND attribute (Armor) post-construction with a sentinel value. The
// client world does not have Armor at that point, so the incoming container change stashes. The
// client then composes Armor late with a different initial value; the drained stash must override it.
//
// Surface in Session Frontend: Ck.Attribute.Net.Float_PreComposition_StashedValue_Applies

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
    // Registered in Config/DefaultGameplayTags.ini. Deliberately NOT one of the attributes the
    // subject's entity-script composes in Construct — the test needs an attribute that does not
    // exist on the client when its replicated value first arrives.
    constexpr auto PreComposition_AttributeTagName = TEXT("FloatAttribute.Armor");

    // Value the server bakes into its Add. This is what must survive the stash → drain round-trip.
    constexpr auto PreComposition_ServerValue = 77.0f;

    // Value the client composes with, distinct from the server's so a dropped stash shows up as a
    // clear mismatch instead of coincidentally matching.
    constexpr auto PreComposition_ClientInitialValue = 5.0f;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkAttributeNet_Float_PreComposition_StashedValue_Applies,
    "Ck.Attribute.Net.Float_PreComposition_StashedValue_Applies",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkAttributeNet_Float_PreComposition_StashedValue_Applies::RunTest(const FString& Parameters)
{
    // CkActorRelay × Iris ambient noise under multi-client PIE — same backstop the SM
    // replication tests use. Restored at the end via a trailing latent command.
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesAfterSpawn = 30;
    // Window for the server-side Add to ship its container change to the client while the client
    // still lacks the attribute — this is the stash-forming window.
    constexpr auto FramesAfterServerAdd = 120;
    // Window for the retry processor to drain the stash after the client's late composition.
    constexpr auto FramesAfterClientCompose = 120;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    auto OwnerSlot = MakeShared<FCk_Handle>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // ---- Stage 1 — server spawns the subject; WithActor entity constructs on both worlds. ----------------------

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

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterSpawn));

    // ---- Stage 2 — server composes the Armor attribute with the sentinel value. The client ---------------------
    // ---- world does NOT have this attribute, so the replicated container change stashes there. ------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, OwnerSlot](UWorld* InServer) -> void
        {
            auto* Subject = ACk_AutoTest_NetSubject::Find(InServer);
            if (Subject == nullptr)
            {
                AddError(TEXT("Stage 2: server-side subject actor missing — Stage 1 spawn never happened?"));
                return;
            }

            auto OwnerEntity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(Subject);
            if (ck::Is_NOT_Valid(OwnerEntity))
            {
                AddError(TEXT("Stage 2: server-side TryGet_ActorEntityHandle returned invalid — WithActor::Construct did not run yet (extend FramesAfterSpawn?)"));
                return;
            }

            const auto AttributeTag = FGameplayTag::RequestGameplayTag(FName{PreComposition_AttributeTagName});

            UCk_Utils_FloatAttribute_UE::Add(OwnerEntity,
                FCk_Fragment_FloatAttribute_ParamsData{AttributeTag, PreComposition_ServerValue},
                ECk_Replication::Replicates);

            *OwnerSlot = OwnerEntity;
        })));

    // Stash-forming window: the container change replicates while the client lacks the attribute.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterServerAdd));

    // ---- Stage 3 — client composes Armor late, with a different initial value. This mirrors ---------------------
    // ---- OnConstructed-driven composition that runs after the replicated value already arrived. -----------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InClient) -> void
        {
            auto* Subject = ACk_AutoTest_NetSubject::Find(InClient);
            if (Subject == nullptr)
            {
                AddError(TEXT("Stage 3: client world has no ACk_AutoTest_NetSubject — actor failed to replicate"));
                return;
            }

            auto OwnerEntity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(Subject);
            if (ck::Is_NOT_Valid(OwnerEntity))
            {
                AddError(TEXT("Stage 3: client-side actor has no bridged entity — entity-script Construct did not run on client"));
                return;
            }

            const auto AttributeTag = FGameplayTag::RequestGameplayTag(FName{PreComposition_AttributeTagName});

            UCk_Utils_FloatAttribute_UE::Add(OwnerEntity,
                FCk_Fragment_FloatAttribute_ParamsData{AttributeTag, PreComposition_ClientInitialValue},
                ECk_Replication::Replicates);
        })));

    // Drain window: FProcessor_FloatAttribute_RetryPendingReplication applies the stashed entry,
    // then the attribute request pipeline computes the final value.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterClientCompose));

    // ---- Cross-world assertion -----------------------------------------------------------------------------------

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

            const auto AttributeTag = FGameplayTag::RequestGameplayTag(FName{PreComposition_AttributeTagName});

            if (ck::IsValid(*OwnerSlot))
            {
                auto ServerOwner = *OwnerSlot;
                const auto ServerAttribute = UCk_Utils_FloatAttribute_UE::TryGet(ServerOwner, AttributeTag);
                if (ck::Is_NOT_Valid(ServerAttribute))
                {
                    AddError(TEXT("server-side TryGet for the Armor attribute returned an invalid handle"));
                }
                else
                {
                    const auto ServerValue = UCk_Utils_FloatAttribute_UE::Get_FinalValue(ServerAttribute);
                    TestEqual(TEXT("server FinalValue matches the composed sentinel value"),
                        ServerValue, PreComposition_ServerValue);
                }
            }
            else
            {
                AddError(TEXT("server-side OwnerSlot was never populated (Stage 2 lambda bailed early?)"));
            }

            auto* ClientSubject = ACk_AutoTest_NetSubject::Find(Client);
            if (ClientSubject == nullptr)
            {
                AddError(TEXT("client world has no ACk_AutoTest_NetSubject at assertion time"));
                return false;
            }

            const auto ClientOwnerEntity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(ClientSubject);
            if (ck::Is_NOT_Valid(ClientOwnerEntity))
            {
                AddError(TEXT("client-side actor has no bridged entity at assertion time"));
                return false;
            }

            const auto ClientAttribute = UCk_Utils_FloatAttribute_UE::TryGet(ClientOwnerEntity, AttributeTag);
            if (ck::Is_NOT_Valid(ClientAttribute))
            {
                AddError(TEXT("client-side TryGet found no Armor attribute — Stage 3 composition did not run"));
                return false;
            }

            // The drained stash must override the client's locally-composed initial value. With the
            // retry processor unregistered, the client stays at PreComposition_ClientInitialValue.
            const auto ClientValue = UCk_Utils_FloatAttribute_UE::Get_FinalValue(ClientAttribute);
            TestEqual(TEXT("client FinalValue matches the server value that replicated BEFORE client composition"),
                ClientValue, PreComposition_ServerValue);

            return true;
        }),
        TEXT("pre-composition replicated attribute value applies after late client composition")));

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
