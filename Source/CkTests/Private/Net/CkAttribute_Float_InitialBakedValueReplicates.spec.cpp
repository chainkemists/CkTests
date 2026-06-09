// Pins the initial-bunch application path for replicated attribute containers: the subject's
// entity-script bakes FloatAttribute.Health = 42.5 in Construct on BOTH worlds, the spec issues
// NO override, and the client must read exactly 42.5 — initially and after an extra settle
// window. Because both worlds compose the same value, this cannot catch a silently-dropped
// initial application; what it pins is that the initial container replay (PostLink today, the
// centralized dispatcher after the refactor) never CORRUPTS the value — a double-applied or
// garbage-applied initial entry shows up as a drift away from 42.5.
//
// Surface in Session Frontend: Ck.Attribute.Net.Float_InitialBakedValue_Replicates

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
    // Must match UCk_AutoTest_NetSubject_EntityScript_UE::Construct (tag registered in
    // Config/DefaultGameplayTags.ini, initial value in CkAutoTest_NetSubject_EntityScript.cpp).
    constexpr auto InitialBaked_AttributeTagName = TEXT("FloatAttribute.Health");
    constexpr auto InitialBaked_Value = 42.5f;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkAttributeNet_Float_InitialBakedValue_Replicates,
    "Ck.Attribute.Net.Float_InitialBakedValue_Replicates",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkAttributeNet_Float_InitialBakedValue_Replicates::RunTest(const FString& Parameters)
{
    // CkActorRelay × Iris ambient noise under multi-client PIE — same backstop the SM
    // replication tests use. Restored at the end via a trailing latent command.
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    // Window for construction + the initial container bunch to land and apply on the client.
    constexpr auto FramesAfterSpawn = 120;
    // Second window after the first assertion — a late re-application of the initial entry
    // (the corruption mode this spec exists to catch) would drift the value here.
    constexpr auto FramesForStabilityCheck = 60;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    auto OwnerSlot = MakeShared<FCk_Handle>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // ---- Stage 1 — server spawns the subject; NO value is overridden anywhere in this spec. --------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, OwnerSlot](UWorld* InServer) -> void
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

    // ---- Stage 2 — capture the server-side owner entity for the assertion. --------------------------------------

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

            *OwnerSlot = OwnerEntity;
        })));

    // ---- Cross-world assertion #1: both worlds hold the baked initial value, untouched. -------------------------

    const auto AssertBothWorldsAtBakedValue =
        [this, OwnerSlot](const TCHAR* InPhase) -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);

            if (Server == nullptr || Client == nullptr)
            {
                AddError(FString::Printf(TEXT("%s: server and/or client world unavailable"), InPhase));
                return false;
            }

            const auto AttributeTag = FGameplayTag::RequestGameplayTag(FName{InitialBaked_AttributeTagName});

            if (ck::IsValid(*OwnerSlot))
            {
                auto ServerOwner = *OwnerSlot;
                const auto ServerAttribute = UCk_Utils_FloatAttribute_UE::TryGet(ServerOwner, AttributeTag);
                if (ck::Is_NOT_Valid(ServerAttribute))
                {
                    AddError(FString::Printf(TEXT("%s: server-side TryGet for the attribute returned an invalid handle"), InPhase));
                }
                else
                {
                    TestEqual(FString::Printf(TEXT("%s: server FinalValue holds the Construct-baked value"), InPhase),
                        UCk_Utils_FloatAttribute_UE::Get_FinalValue(ServerAttribute), InitialBaked_Value);
                }
            }
            else
            {
                AddError(FString::Printf(TEXT("%s: server-side OwnerSlot was never populated (Stage 2 lambda bailed early?)"), InPhase));
            }

            auto* ClientSubject = ACk_AutoTest_NetSubject::Find(Client);
            if (ClientSubject == nullptr)
            {
                AddError(FString::Printf(TEXT("%s: client world has no ACk_AutoTest_NetSubject — actor failed to replicate"), InPhase));
                return false;
            }

            const auto ClientOwnerEntity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(ClientSubject);
            if (ck::Is_NOT_Valid(ClientOwnerEntity))
            {
                AddError(FString::Printf(TEXT("%s: client-side actor has no bridged entity — entity-script Construct did not run on client"), InPhase));
                return false;
            }

            const auto ClientAttribute = UCk_Utils_FloatAttribute_UE::TryGet(ClientOwnerEntity, AttributeTag);
            if (ck::Is_NOT_Valid(ClientAttribute))
            {
                AddError(FString::Printf(TEXT("%s: client-side TryGet found no float attribute — entity-script Construct did not Add it on the client"), InPhase));
                return false;
            }

            TestEqual(FString::Printf(TEXT("%s: client FinalValue holds the Construct-baked value (initial container application did not corrupt it)"), InPhase),
                UCk_Utils_FloatAttribute_UE::Get_FinalValue(ClientAttribute), InitialBaked_Value);

            return true;
        };

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([AssertBothWorldsAtBakedValue]() -> bool
        {
            return AssertBothWorldsAtBakedValue(TEXT("post-spawn"));
        }),
        TEXT("baked initial value intact on both worlds after construction + initial replication")));

    // ---- Stability window + assertion #2: the value must not drift. ----------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesForStabilityCheck));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([AssertBothWorldsAtBakedValue]() -> bool
        {
            return AssertBothWorldsAtBakedValue(TEXT("post-stability-window"));
        }),
        TEXT("baked initial value stable on both worlds after the extra settle window")));

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
