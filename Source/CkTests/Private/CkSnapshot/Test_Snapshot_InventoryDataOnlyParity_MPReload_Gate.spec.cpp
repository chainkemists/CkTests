// CkSnapshot Inventory(DataOnly)-Parity GATE — a replicated DataOnly inventory's ITEM survives a listen-server
// SEAMLESS ServerTravel reload, asserted on the CLIENT. The server adds one Shield (by definition) pre-save; the
// post-reload client must show NumItems == 1 — proving the restored server inventory re-derived its lost shape
// tag (FTag_Inventory_DataOnly is not snapshotted), re-created the owner-hosted container entry (Construct is
// abstained during reconstitution), re-armed FTag_Inventory_MayRequireReplication, and that the restored item
// record + item entity carry everything the Replicate entry-builder needs. Spatial is intentionally NOT covered:
// its grid child entity does not survive a save until CkGrid gains snapshot wiring (see the ratchet reason).
// Surface in Session Frontend: Ck.Snapshot.Parity.InventoryDataOnly_MPReload

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
#include "CkInventory/Item/CkItem_Utils.h"

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkAutoTest_NetSubject_Inventory.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

namespace
{
    constexpr auto InvDOParity_MapPath        = TEXT("/Engine/Maps/Entry");
    const auto     InvDOParity_SlotName       = FName{TEXT("CkSnapshot_InvDOParity_GateSlot")};
    constexpr auto InvDOParity_ShieldDefName  = TEXT("ItemDef_InvGym_Shield");   // 1x1, Tags-only trait — no Stackable warning
    constexpr auto InvDOParity_TargetItems    = int32{1};

    static TWeakObjectPtr<UWorld> GInvDOParity_PreServerWorld;
    static TWeakObjectPtr<UWorld> GInvDOParity_PreClientWorld;

    auto InvDOParity_MapNameOf(UWorld* InWorld) -> FString
    {
        return InWorld != nullptr ? InWorld->RemovePIEPrefix(InWorld->GetOutermost()->GetName()) : FString{};
    }

    auto InvDOParity_Subsystem(UWorld* InWorld) -> UCk_Snapshot_Subsystem_UE*
    {
        if (InWorld == nullptr || InWorld->GetGameInstance() == nullptr) { return nullptr; }
        return InWorld->GetGameInstance()->GetSubsystem<UCk_Snapshot_Subsystem_UE>();
    }

    auto InvDOParity_FindProbe(UWorld* InWorld) -> ACk_AutoTest_NetSubject_Inventory_UE*
    {
        if (InWorld == nullptr) { return nullptr; }
        for (auto It = TActorIterator<ACk_AutoTest_NetSubject_Inventory_UE>(InWorld); It; ++It) { return *It; }
        return nullptr;
    }

    // Resolved through the owner's inventory RECORD, not the actor stash — the stash is populated by
    // Construct, which is ABSTAINED on the restored server world.
    auto InvDOParity_ResolveDataOnlyInventory(AActor* InProbe) -> FCk_Handle_Inventory
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

    auto InvDOParity_NumItems(AActor* InProbe, bool& OutResolved) -> int32
    {
        OutResolved = false;
        auto Inventory = InvDOParity_ResolveDataOnlyInventory(InProbe);
        if (ck::Is_NOT_Valid(Inventory)) { return 0; }
        OutResolved = true;
        return UCk_Utils_Inventory_UE::Get_NumItems(Inventory);
    }

    auto InvDOParity_AllItemsHaveRestoredParentInventory(AActor* InProbe) -> bool
    {
        const auto Inventory = InvDOParity_ResolveDataOnlyInventory(InProbe);
        if (ck::Is_NOT_Valid(Inventory)) { return false; }

        for (const auto Item : UCk_Utils_Inventory_UE::Get_Items(Inventory))
        {
            if (ck::Is_NOT_Valid(Item) || UCk_Utils_Item_UE::Get_ParentInventory(Item) != Inventory)
            { return false; }
        }
        return true;
    }

    auto InvDOParity_FindShieldDef() -> const UCk_InventoryItem_Definition*
    {
        for (TObjectIterator<UCk_InventoryItem_Definition> It; It; ++It)
        {
            if (It->GetName() == InvDOParity_ShieldDefName)
            { return *It; }
        }
        return nullptr;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_InventoryDataOnlyParity_MPReload_Gate,
    "Ck.Snapshot.Parity.InventoryDataOnly_MPReload",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_InventoryDataOnlyParity_MPReload_Gate::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;        // server window + 1 connected client
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesPerSettle = 30;
    constexpr auto ReloadTimeoutSeconds = 60.0f;
    constexpr auto FramesPostReconnect = 60;

    GInvDOParity_PreServerWorld = nullptr;
    GInvDOParity_PreClientWorld = nullptr;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, FString{InvDOParity_MapPath}));
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
            return ck::IsValid(InvDOParity_ResolveDataOnlyInventory(InvDOParity_FindProbe(Server))) &&
                   ck::IsValid(InvDOParity_ResolveDataOnlyInventory(InvDOParity_FindProbe(Client)));
        }),
        ReadyTimeoutSeconds));

    // Stage 3 — server adds one Shield by definition (deferred request; settle covers handling + replication).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto Inventory = InvDOParity_ResolveDataOnlyInventory(InvDOParity_FindProbe(InServer));
            if (ck::Is_NOT_Valid(Inventory)) { AddError(TEXT("Stage 3: server DataOnly inventory unresolved")); return; }

            const auto* ShieldDef = InvDOParity_FindShieldDef();
            if (ShieldDef == nullptr) { AddError(TEXT("Stage 3: Shield item definition not found")); return; }

            auto Request = FCk_Request_Inventory_AddItemByDefinition{ShieldDef, InvDOParity_TargetItems};
            Request.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
            UCk_Utils_Inventory_UE::Request_AddItemByDefinition(
                Inventory, Request, FCk_Delegate_Inventory_OnOperationResult_AddByDefinition{}, {});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 3b — assert the SERVER holds the item before saving.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto Resolved = false;
            const auto NumItems = InvDOParity_NumItems(InvDOParity_FindProbe(InServer), Resolved);
            TestTrue(TEXT("pre-save server: DataOnly inventory resolved"), Resolved);
            TestTrue(TEXT("pre-save server: NumItems == 1"), NumItems == InvDOParity_TargetItems);
        })));

    // Stage 4 — Save on the server; stash pre-travel worlds.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            GInvDOParity_PreServerWorld = InServer;
            GInvDOParity_PreClientWorld = ck::auto_test::net::Get_ClientWorld(0);
            auto* Sub = InvDOParity_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 4: no snapshot subsystem")); return; }
            Sub->Request_Save(InvDOParity_SlotName, FCk_Delegate_OnSaveComplete{});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 5 — fire async Load (triggers seamless ServerTravel) + assert non-blocking.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Sub = InvDOParity_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 5: no snapshot subsystem")); return; }
            Sub->Request_Load(InvDOParity_SlotName, FCk_Delegate_OnLoadComplete{});
            TestTrue(TEXT("Stage 5: Request_Load non-blocking"), Sub->Get_IsLoadInProgress());
        })));

    // Stage 6 — poll until server finished load AND client rode the travel AND the item CONVERGED on the client.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr || Server == GInvDOParity_PreServerWorld.Get() || !Server->HasBegunPlay()) { return false; }
            if (InvDOParity_MapNameOf(Server) != InvDOParity_MapPath) { return false; }
            auto* Sub = InvDOParity_Subsystem(Server);
            if (Sub == nullptr || Sub->Get_IsLoadInProgress()) { return false; }
            if (InvDOParity_FindProbe(Server) == nullptr) { return false; }

            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr || Client == GInvDOParity_PreClientWorld.Get() || !Client->HasBegunPlay()) { return false; }
            if (InvDOParity_MapNameOf(Client) != InvDOParity_MapPath) { return false; }

            auto Resolved = false;
            const auto NumItems = InvDOParity_NumItems(InvDOParity_FindProbe(Client), Resolved);
            return Resolved && NumItems == InvDOParity_TargetItems;
        }),
        ReloadTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPostReconnect));

    // Stage 7 — parity assertions on BOTH worlds: the item survived (NOT an empty Construct-default inventory).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto ServerResolved = false;
            const auto ServerNumItems = InvDOParity_NumItems(InvDOParity_FindProbe(Server), ServerResolved);
            TestTrue(TEXT("server: DataOnly inventory resolved post-reload (shape tag re-derived)"), ServerResolved);
            TestTrue(TEXT("server: item survived the snapshot round-trip (NumItems == 1)"),
                ServerNumItems == InvDOParity_TargetItems);
            TestTrue(TEXT("server: every restored DataOnly item points to its restored inventory"),
                InvDOParity_AllItemsHaveRestoredParentInventory(InvDOParity_FindProbe(Server)));

            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr) { AddError(TEXT("Stage 7: no post-travel client world")); return false; }

            auto ClientResolved = false;
            const auto ClientNumItems = InvDOParity_NumItems(InvDOParity_FindProbe(Client), ClientResolved);
            TestTrue(TEXT("client: DataOnly inventory resolved post-reload"), ClientResolved);
            TestTrue(TEXT("client: item round-tripped (NumItems == 1, not the empty Construct default)"),
                ClientNumItems == InvDOParity_TargetItems);
            TestTrue(TEXT("client: every restored DataOnly item points to its restored inventory"),
                InvDOParity_AllItemsHaveRestoredParentInventory(InvDOParity_FindProbe(Client)));
            return true;
        }),
        TEXT("Inventory(DataOnly) parity: server item survives save -> seamless reload -> client re-derivation")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
