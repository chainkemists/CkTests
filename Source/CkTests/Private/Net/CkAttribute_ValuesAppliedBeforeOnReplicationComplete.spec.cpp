// Pins the client-side lifecycle contract: when an OnReplicationComplete callback runs on a
// replicated entity, the entity's replicated attribute values are already applied. The spec
// binds Promise_OnReplicationComplete on the client's bridged entity and asserts — via a
// snapshot taken INSIDE the callback (UCk_AutoTest_RepCompleteCapturer_UE) — that the subject's
// Construct-baked Float attribute exists and holds its value at fire time. The promise's
// FireIfPayloadInFlight policy retains the payload, so a bind after the signal already fired
// still runs the callback immediately — exactly the contract gameplay consumers (e.g. BB
// entity scripts binding at construction) rely on.
//
// Surface in Session Frontend: Ck.Attribute.Net.Values_AppliedBefore_OnReplicationComplete

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkAttribute/FloatAttribute/CkFloatAttribute_Fragment_Data.h"
#include "CkAttribute/FloatAttribute/CkFloatAttribute_Utils.h"
#include "CkEcs/Net/EntityReplicationDriver/CkEntityReplicationDriver_Utils.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "CkTests/Net/CkAutoTest_NetSubject.h"
#include "CkTests/Net/CkAutoTest_NetSubject_Utils.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace
{
    // Must match UCk_AutoTest_NetSubject_EntityScript_UE::Construct (tag registered in
    // Config/DefaultGameplayTags.ini, initial value in CkAutoTest_NetSubject_EntityScript.cpp).
    constexpr auto RepComplete_AttributeTagName = TEXT("FloatAttribute.Health");
    constexpr auto RepComplete_ExpectedValue = 42.5f;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkAttributeNet_Values_AppliedBefore_OnReplicationComplete,
    "Ck.Attribute.Net.Values_AppliedBefore_OnReplicationComplete",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkAttributeNet_Values_AppliedBefore_OnReplicationComplete::RunTest(const FString& Parameters)
{
    // CkActorRelay × Iris ambient noise under multi-client PIE — same backstop the SM
    // replication tests use. Restored at the end via a trailing latent command.
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto ClientEntityTimeoutSeconds = 15.0;
    constexpr auto FireTimeoutSeconds = 15.0;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    // Owned by the spec for the whole run; the bound dynamic delegate only weak-references it.
    auto Capturer = MakeShared<TStrongObjectPtr<UCk_AutoTest_RepCompleteCapturer_UE>>(
        NewObject<UCk_AutoTest_RepCompleteCapturer_UE>(GetTransientPackage()));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // ---- Stage 1 — server spawns the subject. ---------------------------------------------------------------------

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

    // ---- Stage 2 — wait (per-frame poll) until the client's bridged entity + replication driver exist, ------------
    // ---- then bind the capturer's promise as early as possible. ----------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr)
            { return false; }

            auto* Subject = ACk_AutoTest_NetSubject::Find(Client);
            if (Subject == nullptr)
            { return false; }

            const auto OwnerEntity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(Subject);
            if (ck::Is_NOT_Valid(OwnerEntity))
            { return false; }

            return UCk_Utils_EntityReplicationDriver_UE::Has(OwnerEntity);
        }),
        ClientEntityTimeoutSeconds,
        TEXT("client bridged entity + replication driver available")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
        FCk_NetAutoTest_ServerAction::CreateLambda([this, Capturer](UWorld* InClient) -> void
        {
            auto* Subject = ACk_AutoTest_NetSubject::Find(InClient);
            if (Subject == nullptr)
            {
                AddError(TEXT("Stage 2: client world has no ACk_AutoTest_NetSubject — actor failed to replicate"));
                return;
            }

            auto OwnerEntity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(Subject);
            if (ck::Is_NOT_Valid(OwnerEntity))
            {
                AddError(TEXT("Stage 2: client-side actor has no bridged entity at bind time"));
                return;
            }

            (*Capturer)->_AttributeTag = FGameplayTag::RequestGameplayTag(FName{RepComplete_AttributeTagName});

            auto Delegate = FCk_Delegate_EntityReplicationDriver_OnReplicationComplete{};
            Delegate.BindDynamic(Capturer->Get(), &UCk_AutoTest_RepCompleteCapturer_UE::OnReplicationComplete);

            UCk_Utils_EntityReplicationDriver_UE::Promise_OnReplicationComplete(OwnerEntity, Delegate);
        })));

    // ---- Stage 3 — wait for the promise to fire (immediately if the signal already fired). -------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([Capturer]() -> bool
        {
            return (*Capturer)->_Fired;
        }),
        FireTimeoutSeconds,
        TEXT("OnReplicationComplete promise fired on the client entity")));

    // ---- Assertion: the snapshot taken inside the callback. ---------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, Capturer]() -> bool
        {
            const auto& Snapshot = **Capturer;

            if (NOT Snapshot._Fired)
            {
                AddError(TEXT("OnReplicationComplete never fired on the client entity (see WaitUntil timeout above)"));
                return false;
            }

            if (NOT Snapshot._AttributeWasPresentAtFire)
            {
                AddError(TEXT("inside the OnReplicationComplete callback the Float attribute did not exist — replicated state was not applied before the lifecycle signal"));
                return false;
            }

            TestEqual(TEXT("FinalValue observed INSIDE the OnReplicationComplete callback matches the baked value"),
                Snapshot._FinalValueAtFire, RepComplete_ExpectedValue);

            return true;
        }),
        TEXT("replicated attribute values are applied when OnReplicationComplete consumers run")));

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
