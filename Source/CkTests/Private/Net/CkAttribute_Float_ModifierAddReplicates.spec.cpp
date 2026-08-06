// Phase 2 / Test 2 of the multi-client AutoTest harness rollout — server-side `Add_Revocable`
// modifier on a Float attribute, asserts the resultant FinalValue replicates to the client.
//
// Reuses the same harness (`ACk_AutoTest_NetSubject` + `UCk_AutoTest_NetSubject_EntityScript_UE`)
// as `CkAttribute_Float_Replicates.spec.cpp` — entity-script `Construct` adds the attribute on
// both worlds with initial=42.5. Spec adds a revocable +20 modifier server-side; the container
// fragment carries the post-modifier final value (62.5) to the client.
//
// Surface in Session Frontend: Ck.Attribute.Net.Float_ModifierAdd_Replicates

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
    // Matches the attribute name used by UCk_AutoTest_NetSubject_EntityScript_UE::Construct.
    constexpr auto ModifierAdd_SubjectAttributeTagName = TEXT("FloatAttribute.Health");

    // Tag identifying the test's modifier. We reuse FloatAttribute.Health since it's already
    // registered in DefaultGameplayTags.ini — the modifier name is a separate index from the
    // attribute name within CkAttribute and doesn't have to be a different tag string.
    constexpr auto ModifierAdd_SubjectModifierTagName = TEXT("FloatAttribute.Health");

    // Modifier delta. The entity-script's initial attribute value is 42.5; with an Add-operation
    // revocable modifier of +20, the FinalValue should be 62.5 on both worlds. Negative delta
    // would also work (Subtract operation) — Add @ +20 is just the simplest distinctive case.
    constexpr auto ModifierAdd_SubjectModifierDelta = 20.0f;

    // Expected FinalValue after the modifier is applied. Initial 42.5 + Add 20.0 = 62.5.
    // Picked so it's neither at the clamp boundary (Max=100) nor coincidentally matching the
    // initial value — both server and client must report exactly 62.5 for the test to pass.
    constexpr auto ModifierAdd_ExpectedPostModifierValue = 62.5f;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkAttributeNet_Float_ModifierAdd_Replicates,
    "Ck.Attribute.Net.Float_ModifierAdd_Replicates",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkAttributeNet_Float_ModifierAdd_Replicates::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesAfterSpawn = 30;
    constexpr auto FramesAfterModifier = 30;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    auto OwnerSlot = MakeShared<FCk_Handle>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // ---- Stage 1 — server spawns the subject actor; entity-script Construct adds the float ----------------------
    // ---- attribute on both worlds. -------------------------------------------------------------------------------

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

    // ---- Stage 2 — resolve attribute on the server, apply revocable Add modifier. The modifier ----------------
    // ---- itself lives on the server (modifier entities are server-side); the value impact -------------------
    // ---- (post-modifier FinalValue) replicates to the client via the existing container ---------------------
    // ---- fragment sync handler. -------------------------------------------------------------------------------

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
                AddError(TEXT("Stage 2: server-side TryGet_ActorEntityHandle returned invalid"));
                return;
            }

            const auto AttributeTag = FGameplayTag::RequestGameplayTag(FName{ModifierAdd_SubjectAttributeTagName});
            auto AttributeHandle = UCk_Utils_FloatAttribute_UE::TryGet(OwnerEntity, AttributeTag);
            if (ck::Is_NOT_Valid(AttributeHandle))
            {
                AddError(TEXT("Stage 2: server-side TryGet for the entity-script-added attribute returned invalid"));
                return;
            }

            const auto ModifierTag = FGameplayTag::RequestGameplayTag(FName{ModifierAdd_SubjectModifierTagName});
            const auto ModifierParams = FCk_FloatAttributeModifier_Spec{
                ModifierAdd_SubjectModifierDelta, ECk_MinMaxCurrent::Current};

            UCk_Utils_FloatAttributeModifier_UE::Add_Revocable(
                AttributeHandle,
                ModifierTag,
                ECk_AttributeModifier_Operation::Add,
                ModifierParams);

            *OwnerSlot = OwnerEntity;
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterModifier));

    // ---- Cross-world assertion: server's FinalValue == 62.5, client's FinalValue == 62.5 ---------------------

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

            const auto AttributeTag = FGameplayTag::RequestGameplayTag(FName{ModifierAdd_SubjectAttributeTagName});

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
                    TestEqual(TEXT("server FinalValue reflects the revocable Add modifier locally"),
                        ServerValue, ModifierAdd_ExpectedPostModifierValue);
                }
            }
            else
            {
                AddError(TEXT("server-side OwnerSlot was never populated (Stage 2 bailed early?)"));
            }

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
                AddError(TEXT("client-side TryGet found no float attribute — entity-script Construct did not Add it on client"));
                return false;
            }

            const auto ClientValue = UCk_Utils_FloatAttribute_UE::Get_FinalValue(ClientAttribute);
            TestEqual(TEXT("client FinalValue matches server-side post-modifier value (replication propagated)"),
                ClientValue, ModifierAdd_ExpectedPostModifierValue);

            return true;
        }),
        TEXT("CkAttribute float modifier-add replicates resultant FinalValue to the client")));

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
