// CkSnapshot M2b-1 GATE — real OpenLevel reload + entity-driven bridged-actor respawn.
// Surface in Session Frontend: Ck.Snapshot.M2b.LevelReload

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/GameInstance.h"
#include "EngineUtils.h" // TActorIterator

#include "CkAttribute/FloatAttribute/CkFloatAttribute_Utils.h"

#include "CkAttribute/FloatAttribute/CkFloatAttribute_Fragment.h"

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkAutoTest_NetSubject_M2bProbe.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

namespace
{
    constexpr auto M2b_AttributeTagName = TEXT("FloatAttribute.Health");
    constexpr auto M2b_ExpectedFinal    = 42.5f; // the default subject script's base Health (per the M2a gate)
    const auto     M2b_SlotName         = FName{TEXT("CkSnapshot_M2b_GateSlot")};
    const auto     M2b_SavedLocation    = FVector{100.0, 200.0, 300.0}; // distinct from identity → proves position round-trips

    static TWeakObjectPtr<UWorld> GM2b_PreTravelWorld;

    // PHASE A FINDING: post-OpenLevel the world is NM_Standalone, so the net harness's Get_ServerWorld()
    // (ListenServer/Dedicated only) returns null. Enumerate PIE worlds netmode-agnostically: the post-travel
    // world is the PIE world that HasBegunPlay and is NOT GM2b_PreTravelWorld.
    auto M2b_PostTravelWorld() -> UWorld*
    {
        if (GEngine == nullptr) { return nullptr; }
        auto* Best = static_cast<UWorld*>(nullptr);
        for (const auto& Context : GEngine->GetWorldContexts())
        {
            if (Context.WorldType != EWorldType::PIE) { continue; }
            auto* World = Context.World();
            if (World == nullptr) { continue; }
            if (World != GM2b_PreTravelWorld.Get() && World->HasBegunPlay())
            { Best = World; }
        }
        return Best;
    }

    auto M2b_Subsystem(UWorld* InWorld) -> UCk_Snapshot_Subsystem_UE*
    {
        if (InWorld == nullptr || InWorld->GetGameInstance() == nullptr) { return nullptr; }
        return InWorld->GetGameInstance()->GetSubsystem<UCk_Snapshot_Subsystem_UE>();
    }

    auto M2b_FindProbe(UWorld* InWorld) -> ACk_AutoTest_NetSubject_M2bProbe*
    {
        if (InWorld == nullptr) { return nullptr; }
        for (auto It = TActorIterator<ACk_AutoTest_NetSubject_M2bProbe>(InWorld); It; ++It) { return *It; }
        return nullptr;
    }

    auto M2b_CountProbes(UWorld* InWorld) -> int32
    {
        auto Count = 0;
        if (InWorld == nullptr) { return 0; }
        for (auto It = TActorIterator<ACk_AutoTest_NetSubject_M2bProbe>(InWorld); It; ++It) { ++Count; }
        return Count;
    }

    auto M2b_ResolveAttribute(AActor* InProbe) -> FCk_Handle_FloatAttribute
    {
        if (InProbe == nullptr) { return {}; }
        const auto OwnerEntity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(InProbe);
        if (ck::Is_NOT_Valid(OwnerEntity)) { return {}; }
        return UCk_Utils_FloatAttribute_UE::TryGet(OwnerEntity, FGameplayTag::RequestGameplayTag(FName{M2b_AttributeTagName}));
    }

    // Liveness via raw-registry view over the FloatAttribute value fragment (independent of the parent->attribute
    // record/meta-fragment round-trip, which M2b-1 does not cover — mirrors the M2a gate). Cast ensures on
    // LifetimeOwner (the liveness check); Get_FinalValue reads through. OutCount = attribute entities found.
    auto M2b_LiveFinalFromRawView(UWorld* InWorld, int32& OutCount) -> float
    {
        OutCount = 0;
        auto Final = -1.0f;
        auto* Ecs = InWorld ? InWorld->GetSubsystem<UCk_EcsWorld_Subsystem_UE>() : nullptr;
        if (ck::Is_NOT_Valid(Ecs)) { return Final; }
        auto& CkRegistry = Ecs->Get_Registry();
        auto* Raw = ck::registry_table::TryResolve(CkRegistry.Get_RegistryHandle());
        if (Raw == nullptr) { return Final; }
        for (const auto Entity : Raw->view<ck::FFragment_FloatAttribute_Current>())
        {
            ++OutCount;
            auto Handle = ck::MakeHandle(FCk_Entity{Entity}, CkRegistry);
            auto AttrHandle = UCk_Utils_FloatAttribute_UE::Cast(Handle);
            Final = static_cast<float>(UCk_Utils_FloatAttribute_UE::Get_FinalValue(AttrHandle));
        }
        return Final;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_M2b_LevelReload_Gate,
    "Ck.Snapshot.M2b.LevelReload",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_M2b_LevelReload_Gate::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 1;
    constexpr auto ExpectedTotalWorlds = 1;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesPerSettle = 30;
    constexpr auto FramesForReload = 240; // teardown + OpenLevel + restore + respawn + quiescence all span frames
    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    GM2b_PreTravelWorld = nullptr;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // Stage 1 — spawn the bridged probe (adds FloatAttribute.Health = 42.5; stamps FFragment_ActorSpawnIntent).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            auto* Probe = InServer->SpawnActor<ACk_AutoTest_NetSubject_M2bProbe>(
                ACk_AutoTest_NetSubject_M2bProbe::StaticClass(), FTransform{M2b_SavedLocation}, SpawnInfo);
            if (Probe == nullptr) { AddError(TEXT("Stage 1: probe spawn returned null")); }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 2 — pre-save sanity + Save.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Probe = M2b_FindProbe(InServer);
            const auto Attr = M2b_ResolveAttribute(Probe);
            if (ck::Is_NOT_Valid(Attr)) { AddError(TEXT("Stage 2: could not resolve attribute pre-save")); return; }
            TestEqual(TEXT("pre-save Final == 42.5"),
                static_cast<float>(UCk_Utils_FloatAttribute_UE::Get_FinalValue(Attr)), M2b_ExpectedFinal);

            GM2b_PreTravelWorld = InServer;

            auto* Sub = M2b_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 2: no snapshot subsystem")); return; }
            Sub->Request_Save(M2b_SlotName, FCk_Delegate_OnSaveComplete{});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 3 — fire the async load (triggers the real OpenLevel internally) + assert non-blocking.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Sub = M2b_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 3: no snapshot subsystem")); return; }
            Sub->Request_Load(M2b_SlotName, FCk_Delegate_OnLoadComplete{});
            TestTrue(TEXT("Stage 3: Request_Load non-blocking — load in progress after return"),
                Sub->Get_IsLoadInProgress());
        })));

    // Tick across teardown + OpenLevel + restore + respawn + quiescence.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesForReload));

    // Stage 4 — assert the full M2b-1 contract on the POST-travel world.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = M2b_PostTravelWorld();
            if (Server == nullptr) { AddError(TEXT("Stage 4: no post-travel world")); return false; }

            TestTrue(TEXT("real travel happened — world instance changed"), Server != GM2b_PreTravelWorld.Get());

            auto* Sub = M2b_Subsystem(Server);
            if (Sub == nullptr) { AddError(TEXT("Stage 4: no snapshot subsystem")); return false; }
            TestFalse(TEXT("load flag cleared after completion"), Sub->Get_IsLoadInProgress());

            TestEqual(TEXT("exactly one probe actor (no duplicate)"), M2b_CountProbes(Server), 1);

            auto* Probe = M2b_FindProbe(Server);
            if (Probe == nullptr) { AddError(TEXT("Stage 4: probe actor was not re-spawned by the entity")); return false; }

            const auto Entity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(Probe);
            TestTrue(TEXT("actor<->entity bridge resolves (re-bridge worked)"), ck::IsValid(Entity));

            // Position-restore: the respawned actor is back at its SAVED world location (not identity).
            const auto RespawnedLoc = Probe->GetActorLocation();
            AddInfo(FString::Printf(TEXT("DIAG M2b position: respawned actor at %s (saved %s)"),
                *RespawnedLoc.ToString(), *M2b_SavedLocation.ToString()));
            TestTrue(TEXT("respawned actor restored to its saved world location"),
                RespawnedLoc.Equals(M2b_SavedLocation, 1.0));

            // Liveness via raw-view (decoupled from the parent->attribute record round-trip, not covered by M2b-1).
            auto AttrCount = 0;
            const auto Final = M2b_LiveFinalFromRawView(Server, AttrCount);
            AddInfo(FString::Printf(TEXT("DIAG M2b Stage 4: FloatAttribute_Current entities=%d | Final=%f"), AttrCount, Final));
            TestTrue(TEXT("at least one float attribute survived restore"), AttrCount >= 1);
            if (AttrCount >= 1)
            {
                TestEqual(TEXT("restored attribute is LIVE — Final == 42.5"), Final, M2b_ExpectedFinal);
            }
            return true;
        }),
        TEXT("M2b-1: real travel, no duplicate, actor re-spawned by entity, bridge resolves, attribute live")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
