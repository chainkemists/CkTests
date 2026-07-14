// CkSnapshot Inventory StackCount-Parity GATE (G17) — a definition-built STACKABLE item's runtime-mutated stack
// count survives a listen-server SEAMLESS ServerTravel reload, asserted on BOTH server and client. The server adds
// one Potion (by definition; InitialCount == 1) then mutates its stack count to 7 pre-save. After the reload the
// restored item must show stack count == 7, NOT the definition default (1). This is the G17 fixture gap: the
// Potion's stack count is a LABELED IntegerAttribute child composed during the item's Request_BuildAndReplicate
// construction. Before the FTag_DefinitionBuild_InProgress provenance fix, that child (owner = definition-built item,
// which carries no EntityScript fragment) missed the ConstructSpawned stamp, fell to rule-5 anonymous-skip, and was
// re-created at InitialCount on rebuild — silently reverting 7 -> 1. With the fix it classifies as ConstructSpawned,
// is persisted, adopted by (owner, label), and re-hydrated through the existing attribute pipeline (zero new payload
// code). Mirrors Ck.Snapshot.Parity.InventoryDataOnly_MPReload; the only material deltas are a stackable definition +
// a runtime stack-count mutation + the stack-count assertions.
// Surface in Session Frontend: Ck.Snapshot.Parity.InventoryStackCount_MPReload

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/GameInstance.h"
#include "EngineUtils.h"               // TActorIterator
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel
#include "UObject/UObjectIterator.h"   // TObjectIterator

#include "CkInventory/Inventory/CkInventory_Utils.h"
#include "CkInventory/Inventory/DataOnly/CkInventory_DataOnly_Utils.h"
#include "CkInventory/Item/CkItem_Definition.h"
#include "CkInventory/ItemTrait/Stackable/CkItemTrait_Stackable_Utils.h"

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkAutoTest_NetSubject_Inventory.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

namespace
{
    constexpr auto InvSCParity_MapPath        = TEXT("/Engine/Maps/Entry");
    const auto     InvSCParity_SlotName       = FName{TEXT("CkSnapshot_InvStackCountParity_GateSlot")};
    constexpr auto InvSCParity_PotionDefName  = TEXT("ItemDef_InvGym_Potion");   // Stackable trait, InitialCount 1, MaxStackSize 10
    constexpr auto InvSCParity_DefaultCount   = int32{1};   // Potion _InitialCount — the value a stamp-less rebuild would revert to
    constexpr auto InvSCParity_CountDelta     = int32{6};   // runtime mutation applied pre-save
    constexpr auto InvSCParity_MutatedCount   = int32{7};   // == DefaultCount + CountDelta; the value that must survive the round-trip

    static TWeakObjectPtr<UWorld> GInvSCParity_PreServerWorld;
    static TWeakObjectPtr<UWorld> GInvSCParity_PreClientWorld;

    auto InvSCParity_MapNameOf(UWorld* InWorld) -> FString
    {
        return InWorld != nullptr ? InWorld->RemovePIEPrefix(InWorld->GetOutermost()->GetName()) : FString{};
    }

    auto InvSCParity_Subsystem(UWorld* InWorld) -> UCk_Snapshot_Subsystem_UE*
    {
        if (InWorld == nullptr || InWorld->GetGameInstance() == nullptr) { return nullptr; }
        return InWorld->GetGameInstance()->GetSubsystem<UCk_Snapshot_Subsystem_UE>();
    }

    auto InvSCParity_FindProbe(UWorld* InWorld) -> ACk_AutoTest_NetSubject_Inventory_UE*
    {
        if (InWorld == nullptr) { return nullptr; }
        for (auto It = TActorIterator<ACk_AutoTest_NetSubject_Inventory_UE>(InWorld); It; ++It) { return *It; }
        return nullptr;
    }

    // Resolved through the owner's inventory RECORD, not the actor stash — the stash is populated by
    // Construct, which is ABSTAINED on the restored server world.
    auto InvSCParity_ResolveDataOnlyInventory(AActor* InProbe) -> FCk_Handle_Inventory
    {
        if (InProbe == nullptr) { return {}; }
        auto Entity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(InProbe);
        if (ck::Is_NOT_Valid(Entity)) { return {}; }

        const auto& Inventories = UCk_Utils_Inventory_UE::RecordOfInventories_Utils::Get_ValidEntries(Entity);
        for (auto Inventory : Inventories)
        {
            if (UCk_Utils_Inventory_DataOnly_UE::Has(Inventory))
            { return Inventory; }
        }
        return {};
    }

    // The DataOnly inventory holds exactly the one Potion added in Stage 3.
    auto InvSCParity_ResolvePotionItem(AActor* InProbe) -> FCk_Handle_Item
    {
        auto Inventory = InvSCParity_ResolveDataOnlyInventory(InProbe);
        if (ck::Is_NOT_Valid(Inventory)) { return {}; }
        const auto Items = UCk_Utils_Inventory_UE::Get_Items(Inventory);
        return Items.Num() > 0 ? Items[0] : FCk_Handle_Item{};
    }

    auto InvSCParity_StackCount(AActor* InProbe, bool& OutResolved) -> int32
    {
        OutResolved = false;
        auto Item = InvSCParity_ResolvePotionItem(InProbe);
        if (ck::Is_NOT_Valid(Item)) { return 0; }
        OutResolved = true;
        return UCk_Utils_ItemTrait_Stackable_UE::Get_StackCount(Item);
    }

    auto InvSCParity_FindPotionDef() -> const UCk_InventoryItem_Definition*
    {
        for (TObjectIterator<UCk_InventoryItem_Definition> It; It; ++It)
        {
            if (It->GetName() == InvSCParity_PotionDefName)
            { return *It; }
        }
        return nullptr;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_InventoryStackCountParity_MPReload_Gate,
    "Ck.Snapshot.Parity.InventoryStackCount_MPReload",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_InventoryStackCountParity_MPReload_Gate::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;        // server window + 1 connected client
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesPerSettle = 30;
    constexpr auto ReloadTimeoutSeconds = 60.0f;
    constexpr auto FramesPostReconnect = 60;

    GInvSCParity_PreServerWorld = nullptr;
    GInvSCParity_PreClientWorld = nullptr;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, FString{InvSCParity_MapPath}));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // Stage 1 — open the PIE seamless gate + spawn the replicated inventory subject on the server.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
            { CVar->Set(1, ECVF_SetByCode); }

            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            auto* Probe = InServer->SpawnActor<ACk_AutoTest_NetSubject_Inventory_UE>(
                ACk_AutoTest_NetSubject_Inventory_UE::StaticClass(), FTransform{FVector{100.0, 200.0, 300.0}}, SpawnInfo);
            if (Probe == nullptr) { AddError(TEXT("Stage 1: inventory subject spawn returned null")); }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 2 — pre-reload sanity: the DataOnly inventory resolves on BOTH worlds (Construct ran on each).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Server == nullptr || Client == nullptr) { return false; }
            return ck::IsValid(InvSCParity_ResolveDataOnlyInventory(InvSCParity_FindProbe(Server))) &&
                   ck::IsValid(InvSCParity_ResolveDataOnlyInventory(InvSCParity_FindProbe(Client)));
        }),
        ReadyTimeoutSeconds));

    // Stage 3 — server adds one Potion by definition (deferred request; settle covers handling + replication).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto Inventory = InvSCParity_ResolveDataOnlyInventory(InvSCParity_FindProbe(InServer));
            if (ck::Is_NOT_Valid(Inventory)) { AddError(TEXT("Stage 3: server DataOnly inventory unresolved")); return; }

            const auto* PotionDef = InvSCParity_FindPotionDef();
            if (PotionDef == nullptr) { AddError(TEXT("Stage 3: Potion item definition not found")); return; }

            auto Request = FCk_Request_Inventory_AddItemByDefinition{PotionDef, InvSCParity_DefaultCount};
            Request.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
            UCk_Utils_Inventory_UE::Request_AddItemByDefinition(
                Inventory, Request, FCk_Delegate_Inventory_OnOperationResult_AddByDefinition{});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 3b — mutate the item's stack count at RUNTIME (1 -> 7) so the persisted value is provably NOT the
    // definition default. AdjustStackCount composes as an Add modifier (see the API doc) — correct for an existing
    // item. Settle covers the deferred attribute modifier + replication.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto Item = InvSCParity_ResolvePotionItem(InvSCParity_FindProbe(InServer));
            if (ck::Is_NOT_Valid(Item)) { AddError(TEXT("Stage 3b: server Potion item unresolved")); return; }

            if (UCk_Utils_ItemTrait_Stackable_UE::Get_StackCount(Item) != InvSCParity_DefaultCount)
            { AddError(TEXT("Stage 3b: freshly-added Potion did not start at its definition InitialCount")); return; }

            UCk_Utils_ItemTrait_Stackable_UE::Request_AdjustStackCount(Item, InvSCParity_CountDelta);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 3c — assert the SERVER holds the mutated stack count before saving.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto Resolved = false;
            const auto Count = InvSCParity_StackCount(InvSCParity_FindProbe(InServer), Resolved);
            TestTrue(TEXT("pre-save server: Potion item resolved"), Resolved);
            TestTrue(TEXT("pre-save server: stack count mutated to 7"), Count == InvSCParity_MutatedCount);
        })));

    // Stage 4 — Save on the server; stash pre-travel worlds.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            GInvSCParity_PreServerWorld = InServer;
            GInvSCParity_PreClientWorld = ck::auto_test::net::Get_ClientWorld(0);
            auto* Sub = InvSCParity_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 4: no snapshot subsystem")); return; }
            Sub->Request_Save(InvSCParity_SlotName, FCk_Delegate_OnSaveComplete{});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 5 — fire async Load (triggers seamless ServerTravel) + assert non-blocking.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Sub = InvSCParity_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 5: no snapshot subsystem")); return; }
            Sub->Request_Load(InvSCParity_SlotName, FCk_Delegate_OnLoadComplete{});
            TestTrue(TEXT("Stage 5: Request_Load non-blocking"), Sub->Get_IsLoadInProgress());
        })));

    // Stage 6 — poll until server finished load AND client rode the travel AND the mutated count CONVERGED on the client.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr || Server == GInvSCParity_PreServerWorld.Get() || !Server->HasBegunPlay()) { return false; }
            if (InvSCParity_MapNameOf(Server) != InvSCParity_MapPath) { return false; }
            auto* Sub = InvSCParity_Subsystem(Server);
            if (Sub == nullptr || Sub->Get_IsLoadInProgress()) { return false; }
            if (InvSCParity_FindProbe(Server) == nullptr) { return false; }

            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr || Client == GInvSCParity_PreClientWorld.Get() || !Client->HasBegunPlay()) { return false; }
            if (InvSCParity_MapNameOf(Client) != InvSCParity_MapPath) { return false; }

            auto Resolved = false;
            const auto Count = InvSCParity_StackCount(InvSCParity_FindProbe(Client), Resolved);
            return Resolved && Count == InvSCParity_MutatedCount;
        }),
        ReloadTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPostReconnect));

    // Stage 7 — parity assertions on BOTH worlds: the RUNTIME-MUTATED stack count survived (NOT the definition default).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto ServerResolved = false;
            const auto ServerCount = InvSCParity_StackCount(InvSCParity_FindProbe(Server), ServerResolved);
            TestTrue(TEXT("server: Potion item resolved post-reload"), ServerResolved);
            TestTrue(TEXT("server: stack count restored to 7 (labeled attribute child persisted, not reverted to InitialCount 1)"),
                ServerCount == InvSCParity_MutatedCount);

            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr) { AddError(TEXT("Stage 7: no post-travel client world")); return false; }

            auto ClientResolved = false;
            const auto ClientCount = InvSCParity_StackCount(InvSCParity_FindProbe(Client), ClientResolved);
            TestTrue(TEXT("client: Potion item resolved post-reload"), ClientResolved);
            TestTrue(TEXT("client: stack count round-tripped (7, not the definition-default 1)"),
                ClientCount == InvSCParity_MutatedCount);
            return true;
        }),
        TEXT("Inventory stack-count parity: definition-built stackable item's runtime-mutated count survives save -> seamless reload")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
