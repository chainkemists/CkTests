// CkSnapshot M2a GATE — frame-spanning load orchestration through the real EndPlay teardown pipeline.
// Surface in Session Frontend: Ck.Snapshot.M2a.LoadOrchestration

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "Engine/GameInstance.h"

#include "CkAttribute/FloatAttribute/CkFloatAttribute_Utils.h"
#include "CkAttribute/FloatAttribute/CkFloatAttribute_Fragment.h"

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"
#include "CkSnapshot/Snapshot/CkSnapshot_LoadReport.h"

#include "CkTests/Net/CkAutoTest_NetSubject_M2aProbe.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include <atomic>

// --------------------------------------------------------------------------------------------------------------------

namespace
{
    constexpr auto M2a_AttributeTagName = TEXT("FloatAttribute.Health");
    constexpr auto M2a_ExpectedFinal    = 42.5f; // the probe script's base Health; no modifier added here
    const auto     M2a_SlotName         = FName{TEXT("CkSnapshot_M2a_GateSlot")};

    auto M2a_ResolveAttribute(UWorld* InServer) -> FCk_Handle_FloatAttribute
    {
        if (InServer == nullptr) { return {}; }
        auto* Subject = ACk_AutoTest_NetSubject::Find(InServer);
        if (Subject == nullptr) { return {}; }
        const auto OwnerEntity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(Subject);
        if (ck::Is_NOT_Valid(OwnerEntity)) { return {}; }
        return UCk_Utils_FloatAttribute_UE::TryGet(OwnerEntity, FGameplayTag::RequestGameplayTag(FName{M2a_AttributeTagName}));
    }

    auto M2a_Subsystem(UWorld* InServer) -> UCk_Snapshot_Subsystem_UE*
    {
        if (InServer == nullptr || InServer->GetGameInstance() == nullptr) { return nullptr; }
        return InServer->GetGameInstance()->GetSubsystem<UCk_Snapshot_Subsystem_UE>();
    }

    // Post-restore the actor<->entity bridge is severed by the wipe (same as the M1 FloatAttribute gate), so the
    // restored attribute is re-discovered by raw-registry view over its value fragment. Cast ensures on LifetimeOwner
    // (the liveness check); Get_FinalValue reads through. Returns the Final value; OutCount = attribute entities found.
    auto M2a_LiveFinalFromRawView(UWorld* InServer, int32& OutCount) -> float
    {
        OutCount = 0;
        auto Final = -1.0f;

        auto* Ecs = InServer ? InServer->GetSubsystem<UCk_EcsWorld_Subsystem_UE>() : nullptr;
        if (ck::Is_NOT_Valid(Ecs)) { return Final; }
        auto& CkRegistry = Ecs->Get_Registry();
        auto* Raw = ck::registry_table::TryResolve(CkRegistry.Get_RegistryHandle());
        if (Raw == nullptr) { return Final; }

        auto View = Raw->view<ck::FFragment_FloatAttribute_Current>();
        for (const auto Entity : View)
        {
            ++OutCount;
            auto Handle = ck::MakeHandle(FCk_Entity{Entity}, CkRegistry);
            auto AttrHandle = UCk_Utils_FloatAttribute_UE::Cast(Handle);
            Final = static_cast<float>(UCk_Utils_FloatAttribute_UE::Get_FinalValue(AttrHandle));
        }
        return Final;
    }

}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_M2a_LoadOrchestration_Gate,
    "Ck.Snapshot.M2a.LoadOrchestration",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_M2a_LoadOrchestration_Gate::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 1;
    constexpr auto ExpectedTotalWorlds = 1;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesPerSettle = 30;
    constexpr auto FramesForLoad   = 150; // generous: teardown (multi-frame) + restore + post-restore recompute
    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    auto FlagDuringLoad = MakeShared<bool>(false);

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // Stage 1 — spawn the EndPlay-probe subject (adds FloatAttribute.Health = 42.5).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            UCk_AutoTest_NetSubject_M2aProbe_EntityScript_UE::GEndPlayCount.store(0, std::memory_order_relaxed);
            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            auto* Subject = InServer->SpawnActor<ACk_AutoTest_NetSubject_M2aProbe>(
                ACk_AutoTest_NetSubject_M2aProbe::StaticClass(), FTransform::Identity, SpawnInfo);
            if (Subject == nullptr)
            { AddError(TEXT("Stage 1: probe subject spawn returned null")); }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 2 — pre-save sanity + Save via the subsystem.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            const auto Attr = M2a_ResolveAttribute(InServer);
            if (ck::Is_NOT_Valid(Attr)) { AddError(TEXT("Stage 2: could not resolve attribute pre-save")); return; }
            TestEqual(TEXT("pre-save Final == 42.5"),
                static_cast<float>(UCk_Utils_FloatAttribute_UE::Get_FinalValue(Attr)), M2a_ExpectedFinal);

            auto* Sub = M2a_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 2: no snapshot subsystem")); return; }
            Sub->Request_Save(M2a_SlotName, FCk_Delegate_OnSaveComplete{});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 3 — fire the async load; assert it is non-blocking (flag true immediately, returns same call).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, FlagDuringLoad](UWorld* InServer) -> void
        {
            auto* Sub = M2a_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 4: no snapshot subsystem")); return; }
            Sub->Request_Load(M2a_SlotName, FCk_Delegate_OnLoadComplete{});
            *FlagDuringLoad = Sub->Get_IsLoadInProgress();
            TestTrue(TEXT("Stage 4: Request_Load is non-blocking — load in progress immediately after return"), *FlagDuringLoad);
        })));

    // Tick enough real frames for teardown (multi-frame) + restore to complete via FTSTicker.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesForLoad));

    // Stage 5 — assert the full M2a contract.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto* Sub = M2a_Subsystem(Server);
            if (Sub == nullptr) { AddError(TEXT("Stage 5: no snapshot subsystem")); return false; }

            TestFalse(TEXT("load flag cleared after completion"), Sub->Get_IsLoadInProgress());
            TestTrue (TEXT("EndPlay actually ran during teardown (counter > 0)"),
                UCk_AutoTest_NetSubject_M2aProbe_EntityScript_UE::GEndPlayCount.load(std::memory_order_relaxed) > 0);

            // Liveness: re-discover via raw view (the actor bridge is severed by restore), Cast (ensures on
            // LifetimeOwner) + Get_FinalValue. Exactly one float attribute should have survived restore.
            auto AttrCount = 0;
            const auto Final = M2a_LiveFinalFromRawView(Server, AttrCount);
            AddInfo(FString::Printf(TEXT("DIAG M2a Stage 5: FloatAttribute_Current entities=%d | Final=%f"), AttrCount, Final));
            TestEqual(TEXT("exactly one float attribute survived restore"), AttrCount, 1);
            if (AttrCount > 0)
            {
                TestEqual(TEXT("restored attribute is LIVE — Final == 42.5"), Final, M2a_ExpectedFinal);
            }
            return true;
        }),
        TEXT("M2a: flag cleared, EndPlay ran, no residual destruction, restored entity live")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            FAutomationTestBase::bSuppressLogErrors = false;
            FAutomationTestBase::bSuppressLogWarnings = false;
            return true;
        }),
        TEXT("M2a: restore log suppression statics")));

    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
