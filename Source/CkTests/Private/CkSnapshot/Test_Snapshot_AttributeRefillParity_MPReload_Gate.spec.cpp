// CkSnapshot Attribute-Refill-Parity GATE — round-trip of the CkAttribute refill RUN-STATE (Running/Paused) through a
// listen-server SEAMLESS ServerTravel reload. The probe's entity script composes a Float AND an Integer refill attribute
// at StartingState = Running; the test PAUSES both on the server before save, then asserts they are still Paused after
// the reload. Because a plain rebuild re-runs Construct (which resurrects the run-state to StartingState = Running), a
// post-reload Paused proves the refill run-state PERSISTENCE HANDLER re-drove it — not Construct re-derivation.
//
// Refill run-state is NOT replicated (each world sets its own via Construct + local Request_Pause/Resume — see
// Ck.Attribute.Net.Float_Refill_Replicates), so — like the Timer parity gate — the assertions are SERVER-side. The
// refill VALUE (fill rate) rides the separate FloatAttribute/IntegerAttribute VALUE handler and is not the subject here.
//
// Surface in Session Frontend: Ck.Snapshot.Parity.AttributeRefill_MPReload

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/GameInstance.h"
#include "EngineUtils.h"               // TActorIterator
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel

#include "CkAttribute/FloatAttribute/CkFloatAttribute_Utils.h"
#include "CkAttribute/IntegerAttribute/CkIntegerAttribute_Utils.h"
#include "CkAttribute/CkAttribute_Fragment_Data.h" // ECk_Attribute_RefillState

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"
#include "CkSnapshot/Snapshot/CkSnapshot_RestoreInvariants.h"

#include "CkTests/Net/CkAutoTest_NetSubject_RefillSnapshotProbe_Replicated.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

namespace
{
    constexpr auto Refill_MapPath  = TEXT("/Engine/Maps/Entry");
    const auto     Refill_SlotName = FName{TEXT("CkSnapshot_AttributeRefillParity_GateSlot")};

    // Tags composed by UCk_AutoTest_NetSubject_RefillEntityScript_UE (StartingState = Running on both). We PAUSE them,
    // so a post-reload Running would mean the handler did nothing (Construct re-derivation), a Paused means it worked.
    constexpr auto FloatRefillTargetTagName   = TEXT("FloatAttribute.AutoTest_Energy");
    constexpr auto IntegerRefillTargetTagName = TEXT("IntegerAttribute.AutoTest_Energy");

    static TWeakObjectPtr<UWorld> GRefill_PreServerWorld;

    auto Refill_MapNameOf(UWorld* InWorld) -> FString
    {
        return InWorld != nullptr ? InWorld->RemovePIEPrefix(InWorld->GetOutermost()->GetName()) : FString{};
    }

    auto Refill_Subsystem(UWorld* InWorld) -> UCk_Snapshot_Subsystem_UE*
    {
        if (InWorld == nullptr || InWorld->GetGameInstance() == nullptr) { return nullptr; }
        return InWorld->GetGameInstance()->GetSubsystem<UCk_Snapshot_Subsystem_UE>();
    }

    auto Refill_FindProbe(UWorld* InWorld) -> ACk_AutoTest_NetSubject_RefillSnapshotProbe_Replicated*
    {
        if (InWorld == nullptr) { return nullptr; }
        for (auto It = TActorIterator<ACk_AutoTest_NetSubject_RefillSnapshotProbe_Replicated>(InWorld); It; ++It) { return *It; }
        return nullptr;
    }

    auto Refill_ResolveEntity(AActor* InProbe) -> FCk_Handle
    {
        if (InProbe == nullptr) { return {}; }
        return UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(InProbe);
    }

    // Resolve the Float refill child handle via the bridge. OutResolved=false if the bridge / attribute / refill child
    // is missing, so callers can tell "not there yet" from "there with the wrong run-state".
    auto Refill_FloatRefill(AActor* InProbe, bool& OutResolved) -> FCk_Handle_FloatAttributeRefill
    {
        OutResolved = false;
        const auto Entity = Refill_ResolveEntity(InProbe);
        if (ck::Is_NOT_Valid(Entity)) { return {}; }
        auto Attr = UCk_Utils_FloatAttribute_UE::TryGet(Entity, FGameplayTag::RequestGameplayTag(FName{FloatRefillTargetTagName}));
        if (ck::Is_NOT_Valid(Attr)) { return {}; }
        auto Refill = UCk_Utils_FloatAttribute_UE::TryGet_RefillAttribute(Attr);
        if (ck::Is_NOT_Valid(Refill)) { return {}; }
        OutResolved = true;
        return Refill;
    }

    auto Refill_IntegerRefill(AActor* InProbe, bool& OutResolved) -> FCk_Handle_IntegerAttributeRefill
    {
        OutResolved = false;
        const auto Entity = Refill_ResolveEntity(InProbe);
        if (ck::Is_NOT_Valid(Entity)) { return {}; }
        auto Attr = UCk_Utils_IntegerAttribute_UE::TryGet(Entity, FGameplayTag::RequestGameplayTag(FName{IntegerRefillTargetTagName}));
        if (ck::Is_NOT_Valid(Attr)) { return {}; }
        auto Refill = UCk_Utils_IntegerAttribute_UE::TryGet_RefillAttribute(Attr);
        if (ck::Is_NOT_Valid(Refill)) { return {}; }
        OutResolved = true;
        return Refill;
    }

    // Both refill children resolve AND both read as Paused.
    auto Refill_BothPaused(AActor* InProbe) -> bool
    {
        auto FloatResolved = false;   const auto FloatRefill   = Refill_FloatRefill(InProbe, FloatResolved);
        auto IntegerResolved = false; const auto IntegerRefill = Refill_IntegerRefill(InProbe, IntegerResolved);
        if (NOT FloatResolved || NOT IntegerResolved) { return false; }
        return UCk_Utils_FloatAttributeRefill_UE::Get_RefillState(FloatRefill)     == ECk_Attribute_RefillState::Paused
            && UCk_Utils_IntegerAttributeRefill_UE::Get_RefillState(IntegerRefill) == ECk_Attribute_RefillState::Paused;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_AttributeRefillParity_MPReload_Gate,
    "Ck.Snapshot.Parity.AttributeRefill_MPReload",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_AttributeRefillParity_MPReload_Gate::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;        // server window + 1 connected client
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesPerSettle = 30;
    constexpr auto ReloadTimeoutSeconds = 60.0f; // seamless: ServerTravelPause + transition + restore + replication
    constexpr auto FramesPostReconnect = 60;

    GRefill_PreServerWorld = nullptr;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, FString{Refill_MapPath}));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // Stage 1 — open the PIE seamless gate + spawn the replicated bridged refill probe on the server.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
            { CVar->Set(1, ECVF_SetByCode); }

            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            auto* Probe = InServer->SpawnActor<ACk_AutoTest_NetSubject_RefillSnapshotProbe_Replicated>(
                ACk_AutoTest_NetSubject_RefillSnapshotProbe_Replicated::StaticClass(), FTransform::Identity, SpawnInfo);
            if (Probe == nullptr) { AddError(TEXT("Stage 1: refill probe spawn returned null")); }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 2 — pre-reload sanity: server probe resolves, both refill children resolve AND start Running (the Construct
    // StartingState). This is the value we must move AWAY from before proving persistence.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Probe = Refill_FindProbe(InServer);
            auto FloatResolved = false;   const auto FloatRefill   = Refill_FloatRefill(Probe, FloatResolved);
            auto IntegerResolved = false; const auto IntegerRefill = Refill_IntegerRefill(Probe, IntegerResolved);
            TestTrue(TEXT("Stage 2: both refill children resolve on the server"), FloatResolved && IntegerResolved);
            if (NOT FloatResolved || NOT IntegerResolved) { return; }
            TestTrue(TEXT("Stage 2: Float refill starts Running (Construct StartingState)"),
                UCk_Utils_FloatAttributeRefill_UE::Get_RefillState(FloatRefill) == ECk_Attribute_RefillState::Running);
            TestTrue(TEXT("Stage 2: Integer refill starts Running (Construct StartingState)"),
                UCk_Utils_IntegerAttributeRefill_UE::Get_RefillState(IntegerRefill) == ECk_Attribute_RefillState::Running);
        })));

    // Stage 3 — PAUSE both refills on the server (Request_Pause is an immediate tag mutation), moving the run-state away
    // from the Construct default.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Probe = Refill_FindProbe(InServer);
            auto FloatResolved = false;   auto FloatRefill   = Refill_FloatRefill(Probe, FloatResolved);
            auto IntegerResolved = false; auto IntegerRefill = Refill_IntegerRefill(Probe, IntegerResolved);
            if (NOT FloatResolved || NOT IntegerResolved) { AddError(TEXT("Stage 3: refill children unresolved pre-pause")); return; }
            UCk_Utils_FloatAttributeRefill_UE::Request_Pause(FloatRefill, {});
            UCk_Utils_IntegerAttributeRefill_UE::Request_Pause(IntegerRefill, {});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 3b — assert the SERVER holds Paused before saving (failing here means Request_Pause didn't take, not that
    // snapshot broke).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            TestTrue(TEXT("pre-save server: both refills Paused"), Refill_BothPaused(Refill_FindProbe(InServer)));
        })));

    // Stage 4 — Save on the server; stash the pre-travel server world.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            GRefill_PreServerWorld = InServer;
            auto* Sub = Refill_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 4: no snapshot subsystem")); return; }
            Sub->Request_Save(Refill_SlotName, FCk_Delegate_OnSaveComplete{});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 5 — fire async Load (triggers seamless ServerTravel) + assert non-blocking.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Sub = Refill_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 5: no snapshot subsystem")); return; }
            Sub->Request_Load(Refill_SlotName, FCk_Delegate_OnLoadComplete{});
            TestTrue(TEXT("Stage 5: Request_Load non-blocking"), Sub->Get_IsLoadInProgress());
        })));

    // Stage 6 — poll until the server finished load, rode the travel, and BOTH refills converged on Paused (proves
    // HydrationApply re-drove the run-state; a plain re-Construct would leave them Running).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr || Server == GRefill_PreServerWorld.Get() || !Server->HasBegunPlay()) { return false; }
            if (Refill_MapNameOf(Server) != Refill_MapPath) { return false; }
            auto* Sub = Refill_Subsystem(Server);
            if (Sub == nullptr || Sub->Get_IsLoadInProgress()) { return false; }

            auto* Probe = Refill_FindProbe(Server);
            if (Probe == nullptr) { return false; }
            return Refill_BothPaused(Probe);
        }),
        ReloadTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPostReconnect));

    // Stage 7 — SERVER parity assertions: the runtime Pause survived save -> seamless reload -> hydration (NOT just
    // Construct re-derivation, which would give Running).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            // Generic invariant: after a cross-world (seamless-travel) restore, NO stored handle in the structural
            // backbone (LifetimeOwner/ContextOwner/Dependents) may dangle — catches the registry-rehome bug class.
            {
                auto* ServerWorld = ck::auto_test::net::Get_ServerWorld();
                auto* Ecs = ServerWorld ? ServerWorld->GetSubsystem<UCk_EcsWorld_Subsystem_UE>() : nullptr;
                if (Ecs != nullptr)
                {
                    auto& Reg = Ecs->Get_Registry();
                    if (auto* Raw = ck::registry_table::TryResolve(Reg.Get_RegistryHandle()))
                    {
                        const auto Dangling = ck::snapshot::Verify_AllStoredHandlesResolve(*Raw);
                        for (const auto& Entry : Dangling)
                        { AddError(FString::Printf(TEXT("post-reload dangling handle: %s"), *Entry)); }
                        TestEqual(TEXT("server: no dangling stored handles after reload"), Dangling.Num(), 0);
                    }
                }
            }

            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr) { AddError(TEXT("Stage 7: no post-travel server world")); return false; }
            auto* Probe = Refill_FindProbe(Server);
            if (Probe == nullptr) { AddError(TEXT("Stage 7: server refill probe missing post-reload")); return false; }

            auto FloatResolved = false;   const auto FloatRefill   = Refill_FloatRefill(Probe, FloatResolved);
            auto IntegerResolved = false; const auto IntegerRefill = Refill_IntegerRefill(Probe, IntegerResolved);
            TestTrue(TEXT("client-independent: both refill children re-resolve on the server post-reload"),
                FloatResolved && IntegerResolved);
            if (NOT FloatResolved || NOT IntegerResolved) { return false; }

            TestTrue(TEXT("Float refill: run-state round-tripped (Paused, not Construct default Running)"),
                UCk_Utils_FloatAttributeRefill_UE::Get_RefillState(FloatRefill) == ECk_Attribute_RefillState::Paused);
            TestTrue(TEXT("Integer refill: run-state round-tripped (Paused, not Construct default Running)"),
                UCk_Utils_IntegerAttributeRefill_UE::Get_RefillState(IntegerRefill) == ECk_Attribute_RefillState::Paused);
            return true;
        }),
        TEXT("Attribute refill: runtime Pause of Float+Integer refill survives save -> seamless reload -> hydration")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
