// Phase 2 / Test 4 of the multi-client AutoTest harness rollout — exercises CkAttribute's
// refill processor under multi-client replication. Distinct from Tests 1-3 (which only test
// discrete one-shot mutations) in that the value changes *continuously per tick*. The test
// asserts both worlds observe the post-refill value rising above the initial value, and that
// the two worlds remain in agreement after the settle window.
//
// Uses `ACk_AutoTest_NetSubject_Refill` (subclass of the standard NetSubject) which configures
// the actor to spawn `UCk_AutoTest_NetSubject_RefillEntityScript_UE` instead of the standard
// entity script — that subclass enables refill on the Float attribute it adds.
//
// Surface in Session Frontend: Ck.Attribute.Net.Float_Refill_Replicates

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkAttribute/FloatAttribute/CkFloatAttribute_Fragment_Data.h"
#include "CkAttribute/FloatAttribute/CkFloatAttribute_Utils.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "CkTests/Net/CkAutoTest_NetSubject.h"
#include "CkTests/Net/CkAutoTest_NetSubject_Refill.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace
{
    // Matches the attribute the refill entity script adds (see CkAutoTest_NetSubject_RefillEntityScript.cpp).
    constexpr auto SubjectAttributeTagName = TEXT("FloatAttribute.AutoTest_Energy");

    // Initial value baked into the refill entity script. Test asserts both worlds see a value
    // strictly greater than this after the settle window — that's the evidence refill ran.
    constexpr auto SubjectInitialValue = 0.0f;

    // Lower bound the post-settle value must clear. Picked conservatively below the expected
    // refill amount (FillRate=20/sec over ~1s = 20.0) so that scheduler-tick-rate jitter or
    // partial frames don't false-fail.
    constexpr auto MinExpectedPostRefillValue = 5.0f;

    // Tolerance for server↔client value comparison. Refill runs on the authority side and the
    // resulting value replicates to the client via the FCk_RepData_FloatAttributes container
    // fragment — but the client also runs its own refill processor (entity-script Construct
    // ran symmetrically and enabled refill on both worlds), so the two worlds tick
    // independently *and* exchange values via replication. The result is bounded drift around
    // ~one settle interval's worth of fill at the configured rate. Generous tolerance lets the
    // test focus on "both worlds clearly observed refill" rather than chasing exact agreement
    // on a continuous quantity.
    constexpr auto ServerClientToleranceValue = 10.0f;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkAttributeNet_Float_Refill_Replicates,
    "Ck.Attribute.Net.Float_Refill_Replicates",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkAttributeNet_Float_Refill_Replicates::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesAfterSpawn = 30;
    // Settle window that lets refill processor tick enough on both worlds to produce an
    // observable value > InitialValue + MinExpectedPostRefillValue. 90 frames @ 60fps ≈ 1.5s,
    // safely past the 1s mark when refill should have added ~20.
    constexpr auto FramesForRefillToProgress = 90;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    auto OwnerSlot = MakeShared<FCk_Handle>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // ---- Stage 1 — server spawns the refill subject; entity-script Construct adds the float ---------------------
    // ---- attribute with refill enabled, on both worlds. ----------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;

            auto* Subject = InServer->SpawnActor<ACk_AutoTest_NetSubject_Refill>(
                ACk_AutoTest_NetSubject_Refill::StaticClass(), FTransform::Identity, SpawnInfo);

            if (Subject == nullptr)
            {
                AddError(TEXT("server-side spawn of ACk_AutoTest_NetSubject_Refill returned null"));
                return;
            }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterSpawn));

    // ---- Stage 2 — capture the bridged entity for the server-side assertion. No mutation issued; -----------------
    // ---- refill itself drives the value change. -----------------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, OwnerSlot](UWorld* InServer) -> void
        {
            auto* Subject = ACk_AutoTest_NetSubject::Find(InServer);
            if (Subject == nullptr)
            {
                AddError(TEXT("Stage 2: server-side refill subject actor missing"));
                return;
            }

            const auto OwnerEntity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(Subject);
            if (ck::Is_NOT_Valid(OwnerEntity))
            {
                AddError(TEXT("Stage 2: server-side TryGet_ActorEntityHandle returned invalid"));
                return;
            }

            *OwnerSlot = OwnerEntity;
        })));

    // Let refill processors tick enough times to produce an observable value change on both worlds.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesForRefillToProgress));

    // ---- Cross-world assertion: both worlds see a value > initial and agree to within tolerance ----------------

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

            auto ServerValue = SubjectInitialValue;
            if (ck::IsValid(*OwnerSlot))
            {
                auto ServerOwner = *OwnerSlot;
                const auto ServerAttribute = UCk_Utils_FloatAttribute_UE::TryGet(ServerOwner, AttributeTag);
                if (ck::Is_NOT_Valid(ServerAttribute))
                {
                    AddError(TEXT("server-side TryGet for the refill attribute returned invalid"));
                }
                else
                {
                    ServerValue = UCk_Utils_FloatAttribute_UE::Get_FinalValue(ServerAttribute);
                    TestTrue(TEXT("server FinalValue rose above initial after refill ran"),
                        ServerValue > SubjectInitialValue + MinExpectedPostRefillValue);
                }
            }
            else
            {
                AddError(TEXT("server-side OwnerSlot was never populated (Stage 2 bailed early?)"));
            }

            auto* ClientSubject = ACk_AutoTest_NetSubject::Find(Client);
            if (ClientSubject == nullptr)
            {
                AddError(TEXT("client world has no refill subject actor — actor failed to replicate"));
                return false;
            }

            const auto ClientOwnerEntity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(ClientSubject);
            if (ck::Is_NOT_Valid(ClientOwnerEntity))
            {
                AddError(TEXT("client-side refill actor has no bridged entity"));
                return false;
            }

            const auto ClientAttribute = UCk_Utils_FloatAttribute_UE::TryGet(ClientOwnerEntity, AttributeTag);
            if (ck::Is_NOT_Valid(ClientAttribute))
            {
                AddError(TEXT("client-side TryGet for the refill attribute returned invalid"));
                return false;
            }

            const auto ClientValue = UCk_Utils_FloatAttribute_UE::Get_FinalValue(ClientAttribute);

            TestTrue(TEXT("client FinalValue rose above initial after refill ran"),
                ClientValue > SubjectInitialValue + MinExpectedPostRefillValue);

            TestTrue(TEXT("server and client refill values converge within tolerance"),
                FMath::IsNearlyEqual(ServerValue, ClientValue, ServerClientToleranceValue));

            return true;
        }),
        TEXT("CkAttribute float refill ticks both worlds' values up and they stay in agreement")));

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
