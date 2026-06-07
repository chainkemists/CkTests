// CkSnapshot M2b-2a GATE — replicated-entity respawn under single-player OpenLevel.
// Surface in Session Frontend: Ck.Snapshot.M2b2a.ReplicatedRespawn

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
#include "CkEcs/Net/EntityReplicationDriver/CkEntityReplicationDriver_Utils.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkAutoTest_NetSubject_M2bProbe_Replicated.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

namespace
{
    constexpr auto M2b2a_AttributeTagName = TEXT("FloatAttribute.Health");
    constexpr auto M2b2a_ExpectedFinal    = 42.5f; // the default subject script's base Health
    const auto     M2b2a_SlotName         = FName{TEXT("CkSnapshot_M2b2a_GateSlot")};
    const auto     M2b2a_SavedLocation    = FVector{100.0, 200.0, 300.0};

    static TWeakObjectPtr<UWorld> GM2b2a_PreTravelWorld;

    auto M2b2a_PostTravelWorld() -> UWorld*
    {
        if (GEngine == nullptr) { return nullptr; }
        auto* Best = static_cast<UWorld*>(nullptr);
        for (const auto& Context : GEngine->GetWorldContexts())
        {
            if (Context.WorldType != EWorldType::PIE) { continue; }
            auto* World = Context.World();
            if (World == nullptr) { continue; }
            if (World != GM2b2a_PreTravelWorld.Get() && World->HasBegunPlay())
            { Best = World; }
        }
        return Best;
    }

    auto M2b2a_Subsystem(UWorld* InWorld) -> UCk_Snapshot_Subsystem_UE*
    {
        if (InWorld == nullptr || InWorld->GetGameInstance() == nullptr) { return nullptr; }
        return InWorld->GetGameInstance()->GetSubsystem<UCk_Snapshot_Subsystem_UE>();
    }

    auto M2b2a_FindProbe(UWorld* InWorld) -> ACk_AutoTest_NetSubject_M2bProbe_Replicated*
    {
        if (InWorld == nullptr) { return nullptr; }
        for (auto It = TActorIterator<ACk_AutoTest_NetSubject_M2bProbe_Replicated>(InWorld); It; ++It) { return *It; }
        return nullptr;
    }

    auto M2b2a_CountProbes(UWorld* InWorld) -> int32
    {
        auto Count = 0;
        if (InWorld == nullptr) { return 0; }
        for (auto It = TActorIterator<ACk_AutoTest_NetSubject_M2bProbe_Replicated>(InWorld); It; ++It) { ++Count; }
        return Count;
    }

    auto M2b2a_ResolveAttribute(AActor* InProbe) -> FCk_Handle_FloatAttribute
    {
        if (InProbe == nullptr) { return {}; }
        const auto OwnerEntity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(InProbe);
        if (ck::Is_NOT_Valid(OwnerEntity)) { return {}; }
        return UCk_Utils_FloatAttribute_UE::TryGet(OwnerEntity, FGameplayTag::RequestGameplayTag(FName{M2b2a_AttributeTagName}));
    }

    auto M2b2a_LiveFinalFromRawView(UWorld* InWorld, int32& OutCount) -> float
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
    FCkSnapshot_M2b2a_ReplicatedRespawn_Gate,
    "Ck.Snapshot.M2b2a.ReplicatedRespawn",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_M2b2a_ReplicatedRespawn_Gate::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 1;
    constexpr auto ExpectedTotalWorlds = 1;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesPerSettle = 30;
    constexpr auto FramesForReload = 240;
    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    GM2b2a_PreTravelWorld = nullptr;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // Stage 1 — spawn the REPLICATED bridged probe (adds FloatAttribute.Health = 42.5; stamps FFragment_ActorSpawnIntent).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            auto* Probe = InServer->SpawnActor<ACk_AutoTest_NetSubject_M2bProbe_Replicated>(
                ACk_AutoTest_NetSubject_M2bProbe_Replicated::StaticClass(), FTransform{M2b2a_SavedLocation}, SpawnInfo);
            if (Probe == nullptr) { AddError(TEXT("Stage 1: replicated probe spawn returned null")); }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 2 — pre-save sanity + Save.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Probe = M2b2a_FindProbe(InServer);
            const auto Attr = M2b2a_ResolveAttribute(Probe);
            if (ck::Is_NOT_Valid(Attr)) { AddError(TEXT("Stage 2: could not resolve attribute pre-save")); return; }
            TestEqual(TEXT("pre-save Final == 42.5"),
                static_cast<float>(UCk_Utils_FloatAttribute_UE::Get_FinalValue(Attr)), M2b2a_ExpectedFinal);

            GM2b2a_PreTravelWorld = InServer;

            auto* Sub = M2b2a_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 2: no snapshot subsystem")); return; }
            Sub->Request_Save(M2b2a_SlotName, FCk_Delegate_OnSaveComplete{});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 3 — fire the async load (triggers the real OpenLevel internally) + assert non-blocking.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Sub = M2b2a_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 3: no snapshot subsystem")); return; }
            Sub->Request_Load(M2b2a_SlotName, FCk_Delegate_OnLoadComplete{});
            TestTrue(TEXT("Stage 3: Request_Load non-blocking — load in progress after return"),
                Sub->Get_IsLoadInProgress());
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesForReload));

    // Stage 4 — assert the full M2b-2a contract on the POST-travel world (NO crash is itself the headline).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = M2b2a_PostTravelWorld();
            if (Server == nullptr) { AddError(TEXT("Stage 4: no post-travel world")); return false; }

            TestTrue(TEXT("real travel happened — world instance changed"), Server != GM2b2a_PreTravelWorld.Get());

            auto* Sub = M2b2a_Subsystem(Server);
            if (Sub == nullptr) { AddError(TEXT("Stage 4: no snapshot subsystem")); return false; }
            TestFalse(TEXT("load flag cleared after completion"), Sub->Get_IsLoadInProgress());

            TestEqual(TEXT("exactly one probe actor (no duplicate)"), M2b2a_CountProbes(Server), 1);

            auto* Probe = M2b2a_FindProbe(Server);
            if (Probe == nullptr) { AddError(TEXT("Stage 4: replicated probe was not re-spawned by the entity")); return false; }

            const auto Entity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(Probe);
            TestTrue(TEXT("actor<->entity bridge resolves (re-bridge worked)"), ck::IsValid(Entity));

            // THE M2b-2a differentiator: the replication driver was re-established without crashing.
            TestTrue(TEXT("replication driver re-established on the restored entity"),
                ck::IsValid(Entity) && UCk_Utils_EntityReplicationDriver_UE::Has(Entity));

            const auto RespawnedLoc = Probe->GetActorLocation();
            AddInfo(FString::Printf(TEXT("DIAG M2b2a position: respawned actor at %s (saved %s)"),
                *RespawnedLoc.ToString(), *M2b2a_SavedLocation.ToString()));
            TestTrue(TEXT("respawned actor restored to its saved world location"),
                RespawnedLoc.Equals(M2b2a_SavedLocation, 1.0));

            auto AttrCount = 0;
            const auto Final = M2b2a_LiveFinalFromRawView(Server, AttrCount);
            AddInfo(FString::Printf(TEXT("DIAG M2b2a Stage 4: FloatAttribute_Current entities=%d | Final=%f"), AttrCount, Final));
            TestTrue(TEXT("at least one float attribute survived restore"), AttrCount >= 1);
            if (AttrCount >= 1)
            {
                TestEqual(TEXT("restored attribute is LIVE — Final == 42.5"), Final, M2b2a_ExpectedFinal);
            }
            return true;
        }),
        TEXT("M2b-2a: replicated respawn, driver re-established, no crash, no duplicate, bridge resolves, attribute + position live")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
