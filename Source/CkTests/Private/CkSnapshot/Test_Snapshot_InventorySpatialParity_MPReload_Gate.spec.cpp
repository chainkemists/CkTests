// CkSnapshot Inventory(Spatial)-Parity GATE — a replicated Spatial inventory's ITEM survives a listen-server
// SEAMLESS ServerTravel reload WITH ITS PLACEMENT, asserted on BOTH worlds. The server adds one Sword (3x1
// Dimensions trait, by definition), relocates it to a NON-DEFAULT placement {(1,2), Quarter} pre-save; post-reload
// both worlds must report NumItems == 1 AND the same coordinate + rotation — proving:
//   - the restored server re-derived the Spatial shape tag and re-composed the inventory's 2dGrid (the grid's
//     cells live in a PRIVATE nested registry the snapshot can never capture),
//   - the per-item placement decision record (FFragment_Item_SpatialPlacement — the snapshotable home for the
//     coordinate; the cell ItemRefs are derived state) round-tripped and was re-stamped onto the rebuilt grid,
//   - the item's own Dimensions-trait shape grid was re-composed from its restored Definition,
//   - the owner-hosted Spatial container entry was re-created + FTag_Inventory_MayRequireReplication re-armed,
//     so the fresh post-travel client converges through the ordinary SyncReplication path.
// Asserts placement parity (coordinate + rotation), not just count.
// Surface in Session Frontend: Ck.Snapshot.Parity.InventorySpatial_MPReload

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/GameInstance.h"
#include "EngineUtils.h"               // TActorIterator
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel
#include "UObject/UObjectIterator.h"   // TObjectIterator

#include "CkGrid/2dGridSystem/Grid/Ck2dGridSystem_Utils.h"

#include "CkInventory/Inventory/CkInventory_Utils.h"
#include "CkInventory/Inventory/Spatial/CkInventory_Spatial_Utils.h"
#include "CkInventory/Item/CkItem_Definition.h"

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkAutoTest_NetSubject_Inventory.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

namespace
{
    constexpr auto InvSpParity_MapPath       = TEXT("/Engine/Maps/Entry");
    const auto     InvSpParity_SlotName      = FName{TEXT("CkSnapshot_InvSpParity_GateSlot")};
    constexpr auto InvSpParity_SwordDefName  = TEXT("ItemDef_InvGym_Sword");   // 3x1 Dimensions trait, no Stackable
    constexpr auto InvSpParity_TargetItems   = int32{1};
    const auto     InvSpParity_Coordinate    = FIntPoint{1, 2};                       // != auto-place (0,0)
    constexpr auto InvSpParity_Rotation      = ECk_CardinalRotation::Quarter;         // != default None

    static TWeakObjectPtr<UWorld> GInvSpParity_PreServerWorld;
    static TWeakObjectPtr<UWorld> GInvSpParity_PreClientWorld;

    auto InvSpParity_MapNameOf(UWorld* InWorld) -> FString
    {
        return InWorld != nullptr ? InWorld->RemovePIEPrefix(InWorld->GetOutermost()->GetName()) : FString{};
    }

    auto InvSpParity_Subsystem(UWorld* InWorld) -> UCk_Snapshot_Subsystem_UE*
    {
        if (InWorld == nullptr || InWorld->GetGameInstance() == nullptr) { return nullptr; }
        return InWorld->GetGameInstance()->GetSubsystem<UCk_Snapshot_Subsystem_UE>();
    }

    auto InvSpParity_FindProbe(UWorld* InWorld) -> ACk_AutoTest_NetSubject_Inventory_UE*
    {
        if (InWorld == nullptr) { return nullptr; }
        for (auto It = TActorIterator<ACk_AutoTest_NetSubject_Inventory_UE>(InWorld); It; ++It) { return *It; }
        return nullptr;
    }

    // Resolved through the owner's inventory RECORD, not the actor stash — the stash is populated by
    // Construct, which is ABSTAINED on the restored server world.
    auto InvSpParity_ResolveSpatialInventory(AActor* InProbe) -> FCk_Handle_Inventory_Spatial
    {
        if (InProbe == nullptr) { return {}; }
        auto Entity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(InProbe);
        if (ck::Is_NOT_Valid(Entity)) { return {}; }

        const auto& Inventories = UCk_Utils_Inventory_UE::RecordOfInventories_Utils::Get_ValidEntries(Entity);
        for (auto Inventory : Inventories)
        {
            if (UCk_Utils_Inventory_Spatial_UE::Has(Inventory))
            { return UCk_Utils_Inventory_Spatial_UE::Cast(Inventory); }
        }
        return {};
    }

    auto InvSpParity_ResolveSoleItem(const FCk_Handle_Inventory_Spatial& InInventory) -> FCk_Handle_Item
    {
        if (ck::Is_NOT_Valid(InInventory)) { return {}; }
        const auto& Items = UCk_Utils_Inventory_UE::RecordOfInventoryItems_Utils::Get_ValidEntries(InInventory);
        return Items.Num() == 1 ? Items[0] : FCk_Handle_Item{};
    }

    // True when the world's Spatial inventory holds exactly one item at the expected {coordinate, rotation}.
    auto InvSpParity_PlacementMatches(UWorld* InWorld) -> bool
    {
        auto Inventory = InvSpParity_ResolveSpatialInventory(InvSpParity_FindProbe(InWorld));
        if (ck::Is_NOT_Valid(Inventory)) { return false; }

        // A restored inventory whose grid has not (yet) been re-composed must read as "not converged",
        // not crash — the placement queries below walk the grid.
        if (NOT UCk_Utils_2dGridSystem_UE::Has(Inventory)) { return false; }

        if (UCk_Utils_Inventory_UE::Get_NumItems(Inventory) != InvSpParity_TargetItems) { return false; }

        const auto Item = InvSpParity_ResolveSoleItem(Inventory);
        if (ck::Is_NOT_Valid(Item)) { return false; }

        return UCk_Utils_Inventory_Spatial_UE::Get_ItemPlacementCoordinate(Inventory, Item) == InvSpParity_Coordinate
            && UCk_Utils_Inventory_Spatial_UE::Get_ItemPlacementRotation(Item) == InvSpParity_Rotation;
    }

    auto InvSpParity_FindSwordDef() -> const UCk_InventoryItem_Definition*
    {
        for (TObjectIterator<UCk_InventoryItem_Definition> It; It; ++It)
        {
            if (It->GetName() == InvSpParity_SwordDefName)
            { return *It; }
        }
        return nullptr;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_InventorySpatialParity_MPReload_Gate,
    "Ck.Snapshot.Parity.InventorySpatial_MPReload",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_InventorySpatialParity_MPReload_Gate::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;        // server window + 1 connected client
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesPerSettle = 30;
    constexpr auto ReloadTimeoutSeconds = 60.0f;
    constexpr auto FramesPostReconnect = 60;

    GInvSpParity_PreServerWorld = nullptr;
    GInvSpParity_PreClientWorld = nullptr;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, FString{InvSpParity_MapPath}));
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

    // Stage 2 — pre-reload sanity: the Spatial inventory resolves on BOTH worlds (Construct ran on each).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Server == nullptr || Client == nullptr) { return false; }
            return ck::IsValid(InvSpParity_ResolveSpatialInventory(InvSpParity_FindProbe(Server))) &&
                   ck::IsValid(InvSpParity_ResolveSpatialInventory(InvSpParity_FindProbe(Client)));
        }),
        ReadyTimeoutSeconds));

    // Stage 3 — server adds one Sword by definition (auto-placed), then relocates it to the
    // non-default placement. Two deferred requests; the settles cover handling + replication.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto Inventory = InvSpParity_ResolveSpatialInventory(InvSpParity_FindProbe(InServer));
            if (ck::Is_NOT_Valid(Inventory)) { AddError(TEXT("Stage 3: server Spatial inventory unresolved")); return; }

            const auto* SwordDef = InvSpParity_FindSwordDef();
            if (SwordDef == nullptr) { AddError(TEXT("Stage 3: Sword item definition not found")); return; }

            auto Request = FCk_Request_Inventory_AddItemByDefinition{SwordDef, InvSpParity_TargetItems};
            Request.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
            auto BaseInventory = FCk_Handle_Inventory{Inventory};
            UCk_Utils_Inventory_UE::Request_AddItemByDefinition(
                BaseInventory, Request, FCk_Delegate_Inventory_OnOperationResult_AddByDefinition{});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 3b — relocate the added item to {(1,2), Quarter} (away from the auto-place default).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto Inventory = InvSpParity_ResolveSpatialInventory(InvSpParity_FindProbe(InServer));
            auto Item = InvSpParity_ResolveSoleItem(Inventory);
            if (ck::Is_NOT_Valid(Item)) { AddError(TEXT("Stage 3b: server item unresolved after AddByDefinition")); return; }

            auto Placement = FCk_SpatialPlacement{};
            Placement.Set_Coordinate(InvSpParity_Coordinate);
            Placement.Set_Rotation(InvSpParity_Rotation);

            UCk_Utils_Inventory_Spatial_UE::Request_RelocateItem(
                Inventory,
                FCk_Request_Inventory_Spatial_RelocateItem{Item, Placement},
                FCk_Delegate_Inventory_OnOperationResult_Relocate{});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 3c — pre-save parity on BOTH worlds (the live path must already deliver the placement to the
    // client — otherwise the post-reload assert wouldn't isolate the restore path).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            return InvSpParity_PlacementMatches(ck::auto_test::net::Get_ServerWorld())
                && InvSpParity_PlacementMatches(ck::auto_test::net::Get_ClientWorld(0));
        }),
        ReadyTimeoutSeconds));

    // Stage 4 — Save on the server; stash pre-travel worlds.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            GInvSpParity_PreServerWorld = InServer;
            GInvSpParity_PreClientWorld = ck::auto_test::net::Get_ClientWorld(0);
            auto* Sub = InvSpParity_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 4: no snapshot subsystem")); return; }
            Sub->Request_Save(InvSpParity_SlotName, FCk_Delegate_OnSaveComplete{});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 5 — fire async Load (triggers seamless ServerTravel) + assert non-blocking.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Sub = InvSpParity_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 5: no snapshot subsystem")); return; }
            Sub->Request_Load(InvSpParity_SlotName, FCk_Delegate_OnLoadComplete{});
            TestTrue(TEXT("Stage 5: Request_Load non-blocking"), Sub->Get_IsLoadInProgress());
        })));

    // Stage 6 — poll until server finished load AND client rode the travel AND the placement CONVERGED
    // on the client (re-drive on the server, ordinary SyncReplication to the client).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr || Server == GInvSpParity_PreServerWorld.Get() || !Server->HasBegunPlay()) { return false; }
            if (InvSpParity_MapNameOf(Server) != InvSpParity_MapPath) { return false; }
            auto* Sub = InvSpParity_Subsystem(Server);
            if (Sub == nullptr || Sub->Get_IsLoadInProgress()) { return false; }
            if (InvSpParity_FindProbe(Server) == nullptr) { return false; }

            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr || Client == GInvSpParity_PreClientWorld.Get() || !Client->HasBegunPlay()) { return false; }
            if (InvSpParity_MapNameOf(Client) != InvSpParity_MapPath) { return false; }

            return InvSpParity_PlacementMatches(Client);
        }),
        ReloadTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPostReconnect));

    // Stage 7 — parity assertions on BOTH worlds: the item AND its placement survived (NOT an empty
    // Construct-default inventory, NOT the auto-place default placement).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            TestTrue(TEXT("server: Spatial item at {(1,2), Quarter} post-reload (grid re-composed + placement re-stamped)"),
                InvSpParity_PlacementMatches(Server));

            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr) { AddError(TEXT("Stage 7: no post-travel client world")); return false; }
            TestTrue(TEXT("client: Spatial item at {(1,2), Quarter} post-reload (placement round-tripped + replicated)"),
                InvSpParity_PlacementMatches(Client));
            return true;
        }),
        TEXT("Inventory(Spatial) parity: item + placement survive save -> seamless reload -> client convergence")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
