// Pins the unified actor-side ready promise (UCk_Utils_OwningActor_UE::Promise_OnActorEcsReady)
// across server and client:
//
//   - Server: a ValuesReplicated promise bound immediately after SpawnActor (before the bridged
//     entity exists) queues on the link component and fires once the entity is linked + replicated.
//   - Client (bind before link): a ValuesReplicated promise bound as soon as the replicated ACTOR
//     exists (typically before its bridged entity arrives) fires with the entity linked AND its
//     replicated values applied — the Construct-baked Float attribute is readable inside the
//     callback. This is the EntityBridge-parity contract: one binding, network-correct by default.
//   - Client (LinkEstablished policy): fires with a valid linked entity (no values guarantee).
//   - Client (bind after ready): a ValuesReplicated promise bound after the actor is already ready
//     fires synchronously at bind time.
//
// Surface in Session Frontend: Ck.OwningActor.Net.EcsReady_PromisePolicies

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "CkTests/Net/CkAutoTest_NetSubject.h"
#include "CkTests/Net/CkAutoTest_NetSubject_Utils.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace
{
    // Must match UCk_AutoTest_NetSubject_EntityScript_UE::Construct (tag registered in
    // Config/DefaultGameplayTags.ini, initial value in CkAutoTest_NetSubject_EntityScript.cpp).
    constexpr auto EcsReady_AttributeTagName = TEXT("FloatAttribute.Health");
    constexpr auto EcsReady_ExpectedValue = 42.5f;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkOwningActorNet_EcsReady_PromisePolicies,
    "Ck.OwningActor.Net.EcsReady_PromisePolicies",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkOwningActorNet_EcsReady_PromisePolicies::RunTest(const FString& Parameters)
{
    // CkActorRelay × Iris ambient noise under multi-client PIE — same backstop the SM
    // replication tests use. Restored at the end via a trailing latent command.
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto ClientActorTimeoutSeconds = 15.0;
    constexpr auto FireTimeoutSeconds = 15.0;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    const auto AttributeTag = [] { return FGameplayTag::RequestGameplayTag(FName{EcsReady_AttributeTagName}); };

    // Owned by the spec for the whole run; bound dynamic delegates only weak-reference them.
    auto ServerCapturer = MakeShared<TStrongObjectPtr<UCk_AutoTest_EcsReadyCapturer_UE>>(
        NewObject<UCk_AutoTest_EcsReadyCapturer_UE>(GetTransientPackage()));
    auto ClientCapturer_ValuesReplicated = MakeShared<TStrongObjectPtr<UCk_AutoTest_EcsReadyCapturer_UE>>(
        NewObject<UCk_AutoTest_EcsReadyCapturer_UE>(GetTransientPackage()));
    auto ClientCapturer_LinkEstablished = MakeShared<TStrongObjectPtr<UCk_AutoTest_EcsReadyCapturer_UE>>(
        NewObject<UCk_AutoTest_EcsReadyCapturer_UE>(GetTransientPackage()));
    auto ClientCapturer_LateBind = MakeShared<TStrongObjectPtr<UCk_AutoTest_EcsReadyCapturer_UE>>(
        NewObject<UCk_AutoTest_EcsReadyCapturer_UE>(GetTransientPackage()));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // ---- Stage 1 — server spawns the subject and binds a ValuesReplicated promise BEFORE the ----
    // ---- bridged entity exists (BeginPlay's spawn request is deferred to the processor). --------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, ServerCapturer, AttributeTag](UWorld* InServer) -> void
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

            (*ServerCapturer)->_AttributeTag = AttributeTag();

            auto Delegate = FCk_Delegate_OwningActor_OnEcsReady{};
            Delegate.BindDynamic(ServerCapturer->Get(), &UCk_AutoTest_EcsReadyCapturer_UE::OnActorEcsReady);

            UCk_Utils_OwningActor_UE::Promise_OnActorEcsReady(
                Subject, Delegate, ECk_ActorEcsReady_Policy::ValuesReplicated);
        })));

    // ---- Stage 2 — as soon as the ACTOR replicates to the client (typically before its bridged ----
    // ---- entity arrives), bind both client promises. ------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr)
            { return false; }

            return ACk_AutoTest_NetSubject::Find(Client) != nullptr;
        }),
        ClientActorTimeoutSeconds,
        TEXT("subject actor replicated to the client")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
        FCk_NetAutoTest_ServerAction::CreateLambda(
            [this, ClientCapturer_ValuesReplicated, ClientCapturer_LinkEstablished, AttributeTag](UWorld* InClient) -> void
        {
            auto* Subject = ACk_AutoTest_NetSubject::Find(InClient);
            if (Subject == nullptr)
            {
                AddError(TEXT("Stage 2: client world has no ACk_AutoTest_NetSubject — actor failed to replicate"));
                return;
            }

            (*ClientCapturer_ValuesReplicated)->_AttributeTag = AttributeTag();
            (*ClientCapturer_LinkEstablished)->_AttributeTag = AttributeTag();

            auto Delegate_ValuesReplicated = FCk_Delegate_OwningActor_OnEcsReady{};
            Delegate_ValuesReplicated.BindDynamic(
                ClientCapturer_ValuesReplicated->Get(), &UCk_AutoTest_EcsReadyCapturer_UE::OnActorEcsReady);
            UCk_Utils_OwningActor_UE::Promise_OnActorEcsReady(
                Subject, Delegate_ValuesReplicated, ECk_ActorEcsReady_Policy::ValuesReplicated);

            auto Delegate_LinkEstablished = FCk_Delegate_OwningActor_OnEcsReady{};
            Delegate_LinkEstablished.BindDynamic(
                ClientCapturer_LinkEstablished->Get(), &UCk_AutoTest_EcsReadyCapturer_UE::OnActorEcsReady);
            UCk_Utils_OwningActor_UE::Promise_OnActorEcsReady(
                Subject, Delegate_LinkEstablished, ECk_ActorEcsReady_Policy::LinkEstablished);
        })));

    // ---- Stage 3 — wait for all three early-bound promises to fire. --------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda(
            [ServerCapturer, ClientCapturer_ValuesReplicated, ClientCapturer_LinkEstablished]() -> bool
        {
            return (*ServerCapturer)->_Fired &&
                (*ClientCapturer_ValuesReplicated)->_Fired &&
                (*ClientCapturer_LinkEstablished)->_Fired;
        }),
        FireTimeoutSeconds,
        TEXT("server + client EcsReady promises fired")));

    // ---- Stage 4 — bind-after-ready on the client must fire synchronously at bind time. -----------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
        FCk_NetAutoTest_ServerAction::CreateLambda([this, ClientCapturer_LateBind, AttributeTag](UWorld* InClient) -> void
        {
            auto* Subject = ACk_AutoTest_NetSubject::Find(InClient);
            if (Subject == nullptr)
            {
                AddError(TEXT("Stage 4: client world lost its ACk_AutoTest_NetSubject"));
                return;
            }

            (*ClientCapturer_LateBind)->_AttributeTag = AttributeTag();

            auto Delegate = FCk_Delegate_OwningActor_OnEcsReady{};
            Delegate.BindDynamic(ClientCapturer_LateBind->Get(), &UCk_AutoTest_EcsReadyCapturer_UE::OnActorEcsReady);
            UCk_Utils_OwningActor_UE::Promise_OnActorEcsReady(
                Subject, Delegate, ECk_ActorEcsReady_Policy::ValuesReplicated);

            if (NOT (*ClientCapturer_LateBind)->_Fired)
            {
                AddError(TEXT("Stage 4: ValuesReplicated promise bound AFTER the actor was ready did not fire synchronously at bind time"));
            }
        })));

    // ---- Assertions: snapshots taken INSIDE the callbacks. ------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda(
            [this, ServerCapturer, ClientCapturer_ValuesReplicated, ClientCapturer_LinkEstablished, ClientCapturer_LateBind]() -> bool
        {
            const auto& Server = **ServerCapturer;
            const auto& ClientValues = **ClientCapturer_ValuesReplicated;
            const auto& ClientLink = **ClientCapturer_LinkEstablished;
            const auto& ClientLate = **ClientCapturer_LateBind;

            auto Success = true;

            // Server-side: queued before the entity existed, fired with a valid linked entity.
            if (NOT (Server._Fired && Server._EntityWasValidAtFire))
            {
                AddError(TEXT("server ValuesReplicated promise did not fire with a valid linked entity"));
                Success = false;
            }

            // Client ValuesReplicated: the heart of the contract — replicated values applied at fire.
            if (NOT ClientValues._EntityWasValidAtFire)
            {
                AddError(TEXT("client ValuesReplicated promise fired without a valid linked entity"));
                Success = false;
            }
            if (NOT ClientValues._ReplicationWasCompleteAtFire)
            {
                AddError(TEXT("client ValuesReplicated promise fired BEFORE OnReplicationComplete — policy contract broken"));
                Success = false;
            }
            if (NOT ClientValues._AttributeWasPresentAtFire)
            {
                AddError(TEXT("inside the client ValuesReplicated callback the Construct-baked Float attribute did not exist"));
                Success = false;
            }
            else
            {
                TestEqual(TEXT("FinalValue observed INSIDE the client ValuesReplicated callback matches the baked value"),
                    ClientValues._FinalValueAtFire, EcsReady_ExpectedValue);
            }

            // Client LinkEstablished: fired with a valid entity (values intentionally not guaranteed).
            if (NOT (ClientLink._Fired && ClientLink._EntityWasValidAtFire))
            {
                AddError(TEXT("client LinkEstablished promise did not fire with a valid linked entity"));
                Success = false;
            }

            // Each promise is one-shot — no double fires.
            if (Server._FireCount != 1 || ClientValues._FireCount != 1 ||
                ClientLink._FireCount != 1 || ClientLate._FireCount != 1)
            {
                AddError(FString::Printf(TEXT("a promise fired more than once (server [%d], client-values [%d], client-link [%d], client-late [%d])"),
                    Server._FireCount, ClientValues._FireCount, ClientLink._FireCount, ClientLate._FireCount));
                Success = false;
            }

            return Success;
        }),
        TEXT("Promise_OnActorEcsReady policy contracts hold on server and client")));

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
