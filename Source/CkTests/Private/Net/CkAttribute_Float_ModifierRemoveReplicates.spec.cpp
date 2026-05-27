// Phase 2 / Test 3 of the multi-client AutoTest harness rollout — server-side `Add_Revocable`
// followed by `Remove`, asserts the resultant FinalValue (back to base) replicates to the client.
//
// Two-stage server mutation: Stage 2a adds the +20 modifier (saved in a shared handle slot);
// Stage 2b removes it. Between stages we tick to let the post-Add state settle, and after the
// remove we tick again to let the reverted FinalValue replicate. The end-state assertion
// checks both worlds see FinalValue == base (42.5) — proving the remove path is symmetric
// with the add path on the wire.
//
// Surface in Session Frontend: Ck.Attribute.Net.Float_ModifierRemove_Replicates

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
    constexpr auto SubjectAttributeTagName = TEXT("FloatAttribute.Health");
    constexpr auto SubjectModifierTagName = TEXT("FloatAttribute.Health");

    constexpr auto SubjectModifierDelta = 20.0f;

    // Initial value baked into the attribute by UCk_AutoTest_NetSubject_EntityScript_UE::Construct.
    // After Add(+20) the value is 62.5; after Remove the value should revert exactly back to
    // this initial 42.5. If client sees 62.5 still, replication of the remove didn't fire.
    constexpr auto ExpectedBaseValue = 42.5f;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkAttributeNet_Float_ModifierRemove_Replicates,
    "Ck.Attribute.Net.Float_ModifierRemove_Replicates",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkAttributeNet_Float_ModifierRemove_Replicates::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesAfterSpawn = 30;
    constexpr auto FramesAfterModifierAdd = 15;     // shorter — we don't assert mid-state
    constexpr auto FramesAfterModifierRemove = 30;  // generous post-remove settle

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    auto OwnerSlot = MakeShared<FCk_Handle>();
    // The modifier handle returned by Add_Revocable on the server, threaded into Stage 2b's
    // Remove call. Modifier entities are server-side only (the rep data carries the post-
    // modifier FinalValue, not the modifier itself), so storing this server handle is fine.
    auto ModifierSlot = MakeShared<FCk_Handle_FloatAttributeModifier>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // ---- Stage 1 — spawn the subject; entity-script Construct adds the float attribute -------------------------

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

    // ---- Stage 2a — apply the revocable modifier server-side, capture handle ----------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda(
            [this, OwnerSlot, ModifierSlot](UWorld* InServer) -> void
        {
            auto* Subject = ACk_AutoTest_NetSubject::Find(InServer);
            if (Subject == nullptr)
            {
                AddError(TEXT("Stage 2a: server-side subject actor missing"));
                return;
            }

            const auto OwnerEntity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(Subject);
            if (ck::Is_NOT_Valid(OwnerEntity))
            {
                AddError(TEXT("Stage 2a: server-side TryGet_ActorEntityHandle returned invalid"));
                return;
            }

            const auto AttributeTag = FGameplayTag::RequestGameplayTag(FName{SubjectAttributeTagName});
            auto AttributeHandle = UCk_Utils_FloatAttribute_UE::TryGet(OwnerEntity, AttributeTag);
            if (ck::Is_NOT_Valid(AttributeHandle))
            {
                AddError(TEXT("Stage 2a: server-side TryGet for the attribute returned invalid"));
                return;
            }

            const auto ModifierTag = FGameplayTag::RequestGameplayTag(FName{SubjectModifierTagName});
            const auto ModifierParams = FCk_Fragment_FloatAttributeModifier_ParamsData{
                SubjectModifierDelta, ECk_MinMaxCurrent::Current};

            *ModifierSlot = UCk_Utils_FloatAttributeModifier_UE::Add_Revocable(
                AttributeHandle,
                ModifierTag,
                ECk_AttributeModifier_Operation::Add,
                ModifierParams);

            if (ck::Is_NOT_Valid(*ModifierSlot))
            {
                AddError(TEXT("Stage 2a: Add_Revocable returned an invalid modifier handle"));
                return;
            }

            *OwnerSlot = OwnerEntity;
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterModifierAdd));

    // ---- Stage 2b — remove the modifier server-side --------------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda(
            [this, ModifierSlot](UWorld* /*InServer*/) -> void
        {
            if (ck::Is_NOT_Valid(*ModifierSlot))
            {
                AddError(TEXT("Stage 2b: ModifierSlot was never populated (Stage 2a failed?)"));
                return;
            }

            auto ModifierHandle = *ModifierSlot;
            UCk_Utils_FloatAttributeModifier_UE::Remove(ModifierHandle);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterModifierRemove));

    // ---- Cross-world assertion: both server and client back to base value (42.5) -------------------------------

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

            const auto AttributeTag = FGameplayTag::RequestGameplayTag(FName{SubjectAttributeTagName});

            if (ck::IsValid(*OwnerSlot))
            {
                auto ServerOwner = *OwnerSlot;
                const auto ServerAttribute = UCk_Utils_FloatAttribute_UE::TryGet(ServerOwner, AttributeTag);
                if (ck::Is_NOT_Valid(ServerAttribute))
                {
                    AddError(TEXT("server-side TryGet for the attribute returned invalid"));
                }
                else
                {
                    const auto ServerValue = UCk_Utils_FloatAttribute_UE::Get_FinalValue(ServerAttribute);
                    TestEqual(TEXT("server FinalValue reverted to base after Remove"),
                        ServerValue, ExpectedBaseValue);
                }
            }
            else
            {
                AddError(TEXT("server-side OwnerSlot was never populated"));
            }

            auto* ClientSubject = ACk_AutoTest_NetSubject::Find(Client);
            if (ClientSubject == nullptr)
            {
                AddError(TEXT("client world has no ACk_AutoTest_NetSubject"));
                return false;
            }

            const auto ClientOwnerEntity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(ClientSubject);
            if (ck::Is_NOT_Valid(ClientOwnerEntity))
            {
                AddError(TEXT("client-side actor has no bridged entity"));
                return false;
            }

            const auto ClientAttribute = UCk_Utils_FloatAttribute_UE::TryGet(ClientOwnerEntity, AttributeTag);
            if (ck::Is_NOT_Valid(ClientAttribute))
            {
                AddError(TEXT("client-side TryGet found no float attribute"));
                return false;
            }

            const auto ClientValue = UCk_Utils_FloatAttribute_UE::Get_FinalValue(ClientAttribute);
            TestEqual(TEXT("client FinalValue reverted to base after server Remove (replication propagated)"),
                ClientValue, ExpectedBaseValue);

            return true;
        }),
        TEXT("CkAttribute float modifier-remove reverts FinalValue on the client")));

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
