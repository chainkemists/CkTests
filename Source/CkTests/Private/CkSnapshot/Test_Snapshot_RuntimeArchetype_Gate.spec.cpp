// CkSnapshot RUNTIME-ARCHETYPE gates - what a load does when a build recipe names an archetype the loading
// process cannot resolve.
//
// A recipe records its archetype as an object PATH. That is durable identity for an on-disk asset and NOT for
// one minted at runtime (GetOrCreate_TransientItemDefinition): the path resolves inside the process that minted
// it and nowhere else. The symptom is famously asymmetric - save/load in one session works because FindObject
// still answers, and the same save on a cold boot rebuilds the entity from its CLASS DEFAULT, producing an item
// with zero traits that still occupies its inventory slot.
//
// None of that needs a process restart to test. The loader branches on "does this path resolve", so the tests
// below RENAME the definition out from under its outer in the harness's post-save window: TryLoad then genuinely
// returns null, which is the same condition a fresh process produces. What is deliberately NOT covered is that
// RF_Transient objects die with the process - an engine guarantee, not this module's logic.
//
// There are TWO reapers, and which one runs is the whole attribution question. A load owns the husks IT
// produced: it reaps them at load finish and NAMES each one in its report. Every other route belongs to the
// resident ck::FProcessor_UnresolvedHusk_Reap, which ensures loudly, destroys, and deliberately writes NO report
// record - the save never contained that husk, so charging it to the load report would invent a restore loss the
// player is shown and nobody can reproduce. The gates below are split along exactly that line.
//
// A load is not the only route a transient archetype fails to survive, and the last TWO gates are the other one:
// the WIRE. The object reference is not net-addressable either, so a real client builds the same class-default husk
// with no save involved, and recovers the same way - from the identity path the builder stamps beside the reference.
// That claim is split in two because no single test can make both halves at once: same-process object aliasing means
// a PIE client's archetype pointer always resolves. So gate 7 pins, across a real wire, that the identity TRAVELS,
// and gate 8 pins, on one world with no wire, that the identity ALONE rebuilds the archetype. Neither is sufficient
// by itself; see gate 7's header for what PIE cannot stage and why.
//
// Log expectations: every gate that drives PIE sets bSuppressLogErrors/bSuppressLogWarnings, so the new
// diagnostics (CkInventory's class-default Warning, the load's per-husk reap Warning, the empty-archetype-path
// Warning) need no AddExpectedError registration - and could not be counted by one anyway, since suppression
// short-circuits the capture path that increments an expected message's occurrence count. Exactness therefore
// comes from UCk_Utils_Ensure_UE::Get_EnsureCount() instead (the T-C4-3 idiom).
//
// Surface in Session Frontend:
//   Ck.Snapshot.RuntimeArchetype.HuskIsReapedAndNamed
//   Ck.Snapshot.RuntimeArchetype.ProviderRestoresDefinition
//   Ck.Snapshot.RuntimeArchetype.UnresolvedPathIsNotErased
//   Ck.Snapshot.RuntimeArchetype.RegistryContract
//   Ck.Snapshot.RuntimeArchetype.ErasedPathStillFreesTheSlot
//   Ck.Snapshot.RuntimeArchetype.LiveRouteHuskIsReapedAndEnsured
//   Ck.Snapshot.RuntimeArchetype.TransientArchetypeReachesClientResolved
//   Ck.Snapshot.RuntimeArchetype.IdentityPathAloneResolvesViaProvider

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "Engine/GameInstance.h"
#include "EngineUtils.h"               // TActorIterator
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel
#include "UObject/Package.h"           // GetTransientPackage
#include "UObject/UObjectIterator.h"   // TObjectIterator (locating a client's replication driver)

#include "CkInventory/Inventory/CkInventory_Utils.h"
#include "CkInventory/Inventory/DataOnly/CkInventory_DataOnly_Utils.h"
#include "CkInventory/Item/CkItem_Definition.h"
#include "CkInventory/Item/CkItem_Utils.h"
#include "CkInventory/ItemTrait/Tags/CkItemTrait_Tags.h"

#include "CkCore/Ensure/CkEnsure_Utils.h"

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"
#include "CkEcs/Net/EntityReplicationDriver/CkEntityReplicationDriver_BuildRecipe.h"
#include "CkEcs/Persistence/CkRuntimeArchetype_Registry.h"
#include "CkEcs/Net/EntityReplicationDriver/CkEntityReplicationDriver_Utils.h"
#include "CkEcs/ContextOwner/CkContextOwner_Utils.h"
#include "CkEcs/Snapshot/CkSnapshot_RestoreMarker.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkAutoTest_NetSubject_Inventory.h"
#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

namespace ck_runtime_archetype_gate
{
    // The name IS the identity: the provider re-mints under exactly this name so the path the save recorded
    // resolves again. Suffixed per test so three round-trips in one editor cannot collide.
    const auto ProviderId = FName{TEXT("Ck.Test.RuntimeArchetype")};

    auto Get_DefinitionName(const TCHAR* InSuffix) -> FName
    {
        return FName{FString::Printf(TEXT("Ck_RuntimeArchetypeTestDef_%s"), InSuffix)};
    }

    // A runtime-minted definition, exactly as a game feature produces one: outered to a live object, never an
    // asset, carrying one trait so a restored item is distinguishable from a class-default husk.
    auto Mint_Definition(FName InName) -> UCk_InventoryItem_Definition*
    {
        auto Traits = TArray<UCk_ItemTrait*>{};
        Traits.Add(NewObject<UCk_ItemTrait_Tags>(GetTransientPackage()));

        return UCk_Utils_Item_UE::GetOrCreate_TransientItemDefinition(
            GetTransientPackage(), InName, FCk_InventoryItem_CoreInfo{}, Traits);
    }

    // Break the path WITHOUT destroying the object: a rename leaves the recorded path pointing at a name nothing
    // answers to, which is the condition a fresh process presents, and is deterministic where waiting on GC is not.
    // Returns false when there was nothing left to break.
    auto Break_DefinitionPath(FName InName) -> bool
    {
        auto* Definition = FindObject<UCk_InventoryItem_Definition>(GetTransientPackage(), *InName.ToString());
        if (Definition == nullptr)
        { return false; }

        const auto Displaced = FString::Printf(TEXT("%s_Displaced_%u"), *InName.ToString(), Definition->GetUniqueID());
        Definition->Rename(*Displaced, GetTransientPackage(), REN_DontCreateRedirectors | REN_NonTransactional);
        return true;
    }

    auto Find_Probe(UWorld* InWorld) -> ACk_AutoTest_NetSubject_Inventory_UE*
    {
        if (InWorld == nullptr)
        { return nullptr; }

        for (auto It = TActorIterator<ACk_AutoTest_NetSubject_Inventory_UE>(InWorld); It; ++It)
        { return *It; }

        return nullptr;
    }

    // Through the owner's RECORD, not the actor stash - the stash is populated by Construct, which the restored
    // server world abstains on.
    auto Resolve_Inventory(UWorld* InWorld) -> FCk_Handle_Inventory
    {
        auto* Probe = Find_Probe(InWorld);
        if (Probe == nullptr)
        { return {}; }

        auto Entity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(Probe);
        if (ck::Is_NOT_Valid(Entity))
        { return {}; }

        for (auto Inventory : UCk_Utils_Inventory_UE::RecordOfInventories_Utils::Get_ValidEntries(Entity))
        {
            if (UCk_Utils_Inventory_DataOnly_UE::Has(Inventory))
            { return Inventory; }
        }
        return {};
    }

    auto Spawn_Subject(UWorld* InServer) -> void
    {
        if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
        { CVar->Set(1, ECVF_SetByCode); }

        auto SpawnInfo = FActorSpawnParameters{};
        SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
        InServer->SpawnActor<ACk_AutoTest_NetSubject_Inventory_UE>(
            ACk_AutoTest_NetSubject_Inventory_UE::StaticClass(), FTransform{FVector{100.0, 200.0, 300.0}}, SpawnInfo);
    }

    auto Add_ItemFromRuntimeDefinition(UWorld* InServer, FName InName) -> bool
    {
        auto Inventory = Resolve_Inventory(InServer);
        if (ck::Is_NOT_Valid(Inventory))
        { return false; }

        auto* Definition = Mint_Definition(InName);
        if (Definition == nullptr)
        { return false; }

        auto Request = FCk_Request_Inventory_AddItemByDefinition{Definition, 1};
        Request.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
        UCk_Utils_Inventory_UE::Request_AddItemByDefinition(
            Inventory, Request, FCk_Delegate_Inventory_OnOperationResult_AddByDefinition{}, {});
        return true;
    }

    // The registry only cares that a resolver hands back a non-null archetype and that it returns THAT one, so
    // any concrete construction script serves. UCk_Entity_ConstructionScript_PDA itself is Abstract.
    auto Mint_UniqueArchetype(const TCHAR* InLeaf) -> UCk_Entity_ConstructionScript_PDA*
    {
        return Mint_Definition(FName{FString::Printf(TEXT("Ck_RuntimeArchetypeSpec_%s"), InLeaf)});
    }

    // An item built with NO archetype at all - what a save written by a build that had already rebuilt one
    // husk contains, because that build captured the null archetype back as an empty path. Mirrors
    // UCk_Utils_Item_UE::Create exactly, minus the Set_ConstructionScriptArchetype line.
    //
    // Returns the item still carrying the husk marker CkInventory's construct guard stamped on it, so a caller
    // can both OBSERVE that the guard fired and decide what happens to the marker next (see Unmark_Husk).
    auto Build_ItemWithNoArchetype(UWorld* InServer) -> FCk_Handle_Item
    {
        auto Inventory = Resolve_Inventory(InServer);
        if (ck::Is_NOT_Valid(Inventory))
        { return {}; }

        auto Owner = UCk_Utils_ContextOwner_UE::Get_ContextOwner(Inventory);
        if (ck::Is_NOT_Valid(Owner))
        { return {}; }

        const auto Info = FCk_EntityReplicationDriver_ConstructionInfo{UCk_InventoryItem_Definition::StaticClass()};
        auto Built = UCk_Utils_EntityReplicationDriver_UE::Request_BuildAndReplicate(Owner, Info);
        auto Item = UCk_Utils_Item_UE::Cast(Built);
        if (ck::Is_NOT_Valid(Item))
        { return {}; }

        UCk_Utils_Inventory_UE::Request_AddItem(
            Inventory, FCk_Request_Inventory_AddItem{Item},
            FCk_Delegate_Inventory_OnOperationResult_Add{}, {});
        return Item;
    }

    // Build_ItemWithNoArchetype's twin, differing in exactly ONE field: the info carries an archetype IDENTITY
    // and still no archetype OBJECT. That pair is what a packaged client deserializes off the wire and what a
    // cold-boot load reconstructs, and it is the only way to make Construct_FromInfo take its identity-path
    // branch on demand - a PIE client's pointer always resolves (same-process aliasing) and a same-process load
    // still finds the object by name.
    //
    // Everything else is deliberately identical, including routing through Request_BuildAndReplicate on a real
    // ContextOwner: the entity has to be created by the production path or it reaches construction with no net
    // info and no lifetime owner, which the framework ensures on.
    auto Build_ItemFromArchetypeIdentityOnly(UWorld* InServer, const FString& InIdentityPath) -> FCk_Handle_Item
    {
        auto Inventory = Resolve_Inventory(InServer);
        if (ck::Is_NOT_Valid(Inventory))
        { return {}; }

        auto Owner = UCk_Utils_ContextOwner_UE::Get_ContextOwner(Inventory);
        if (ck::Is_NOT_Valid(Owner))
        { return {}; }

        auto Info = FCk_EntityReplicationDriver_ConstructionInfo{UCk_InventoryItem_Definition::StaticClass()};
        Info.Set_ArchetypeIdentityPath(InIdentityPath);

        auto Built = UCk_Utils_EntityReplicationDriver_UE::Request_BuildAndReplicate(Owner, Info);
        auto Item = UCk_Utils_Item_UE::Cast(Built);
        if (ck::Is_NOT_Valid(Item))
        { return {}; }

        UCk_Utils_Inventory_UE::Request_AddItem(
            Inventory, FCk_Request_Inventory_AddItem{Item},
            FCk_Delegate_Inventory_OnOperationResult_Add{}, {});
        return Item;
    }

    // Strips the husk marker so the item survives a live-world settle.
    //
    // Since ck::FProcessor_UnresolvedHusk_Reap became resident, a marked husk in a live world is destroyed on the
    // next Gameplay pass - so a build that still has that processor in it cannot produce a save containing one,
    // and a test cannot stage anything with one either. Unmarking reproduces exactly the build that could: an
    // older one, with no resident reaper. Without it the erased-path gate's pre-save settle empties the inventory
    // and every one of its post-load assertions holds vacuously.
    auto Unmark_Husk(FCk_Handle_Item& InItem) -> void
    {
        InItem.Try_Remove<ck::FTag_Snapshot_UnresolvedArchetype>();
    }

    // The archetype identity as the RECEIVING side holds it, read off the replicated driver rather than off the
    // entity. Neither entity-side source exists on a client: ck::FFragment_BuildRecipe is stamped only by the
    // authority-only Request_TryBuildAndReplicate, and the TObjectPtr<...Rep> fragment only by TryAddReplicatedFragment,
    // which is likewise host-only. The driver is where the client genuinely keeps them - its OnRep_ReplicationData
    // is what hands these very infos to Construct_FromInfo - so it is located by matching the driver whose
    // associated entity IS this one. Empty means the wire carried no identity, which is the failure under test.
    auto TryGet_ReceivedArchetypeIdentityPath(const FCk_Handle& InEntity) -> FString
    {
        for (auto It = TObjectIterator<UCk_Fragment_EntityReplicationDriver_Rep>{}; It; ++It)
        {
            auto* Driver = *It;

            if (ck::Is_NOT_Valid(Driver) || Driver->IsTemplate())
            { continue; }

            if (Driver->Get_AssociatedEntity() != InEntity)
            { continue; }

            for (const auto& Info : Driver->Get_ReplicationData().Get_ConstructionInfos())
            {
                if (const auto& Path = Info.Get_ArchetypeIdentityPath(); NOT Path.IsEmpty())
                { return Path; }
            }
        }

        return {};
    }

    auto Make_SubjectReady() -> FCk_NetAutoTest_Assertion
    {
        return FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            return ck::IsValid(Resolve_Inventory(ck::auto_test::net::Get_ServerWorld()));
        });
    }
}

// --------------------------------------------------------------------------------------------------------------------
// 1. No provider: the husk does not survive the load, and the loss is NAMED.
//
// The slot is the point. An item with no traits is invisible and unusable, but it still counts against its
// container - so leaving it behind hands the player an inventory slot that looks occupied and can never be used
// again. Reaping is what makes an unresolvable recipe a reported loss rather than permanent damage.
// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_RuntimeArchetype_HuskIsReapedAndNamed,
    "Ck.Snapshot.RuntimeArchetype.HuskIsReapedAndNamed",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_RuntimeArchetype_HuskIsReapedAndNamed::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    const auto DefName = ck_runtime_archetype_gate::Get_DefinitionName(TEXT("Reaped"));

    // Unregistered defensively: the registry outlives the world, so a sibling test's leaked provider would
    // silently turn this into the opposite test and still report green.
    ck::FCk_RuntimeArchetypeRegistry::Unregister(ck_runtime_archetype_gate::ProviderId);

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = FName{TEXT("CkSnapshot_RuntimeArchetype_ReapedSlot")};
    // Save ONCE, then load THAT save on every cycle. The default (save each cycle) would have cycle 2
    // capture the already-reaped world - a save with no item in it - so the husk assertions would pass on
    // cycle 1 and be vacuously true on cycle 2. Re-loading one save also asks the stronger question:
    // repeated loads of the same save must behave identically to each other.
    Spec.SaveEveryCycle = false;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    { ck_runtime_archetype_gate::Spawn_Subject(InServer); });

    Spec.SubjectReady = ck_runtime_archetype_gate::Make_SubjectReady();

    Spec.Mutate = FCk_NetAutoTest_ServerAction::CreateLambda([this, DefName](UWorld* InServer) -> void
    {
        if (NOT ck_runtime_archetype_gate::Add_ItemFromRuntimeDefinition(InServer, DefName))
        { AddError(TEXT("Setup: could not add an item from the runtime definition")); }
    });

    // The whole fixture: the save was written with a resolvable path, and now the path stops resolving.
    Spec.PostSave = FCk_NetAutoTest_ServerAction::CreateLambda([DefName](UWorld*) -> void
    { ck_runtime_archetype_gate::Break_DefinitionPath(DefName); });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
    {
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        auto Inventory = ck_runtime_archetype_gate::Resolve_Inventory(Server);

        TestTrue(TEXT("post-load: the inventory itself still restored"), ck::IsValid(Inventory));
        if (ck::Is_NOT_Valid(Inventory))
        { return true; }

        // The container survives intact minus the one broken entry - the husk is BUILT rather than the row
        // dropped precisely so the inventory's all-or-nothing hydration is not failed by it.
        TestEqual(TEXT("post-load: the husk released its inventory slot"),
            UCk_Utils_Inventory_UE::Get_NumItems(Inventory), 0);

        auto* Sub = ck::auto_test::snapshot::Get_SnapshotSubsystem(Server);
        TestTrue(TEXT("post-load: snapshot subsystem resolves"), Sub != nullptr);
        if (Sub == nullptr)
        { return true; }

        const auto& Report = Sub->Get_LastLoadReport();

        // A count says the world came back incomplete; only a name says WHICH part of it did.
        //
        // ATTRIBUTION PIN for the "a load's husks are pending-kill before any world tick" ordering invariant.
        // A record exists ONLY when the LOAD reaped the husk: the resident ck::FProcessor_UnresolvedHusk_Reap
        // destroys without recording, deliberately. So if that processor ever raced the load and got here first -
        // through the load gate it early-outs on, or through the quarantine its view excludes - the load's own
        // sweep would find nothing tagged and this assertion would read zero. Nothing else in this gate would
        // notice: the slot check below passes either way.
        TestTrue(TEXT("post-load: the unresolvable archetype is named on the load report"),
            Report.Get_UnresolvedArchetypes().Num() > 0);

        TestTrue(TEXT("post-load: a reaped entity downgrades the verdict to Succeeded_WithLoss"),
            Report.Get_Result() == ECk_SnapshotResult::Succeeded_WithLoss);

        return true;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// 2. With a provider: the entity comes back COMPOSED, not merely present.
//
// Asserting the item exists would pass for a husk too - a class-default rebuild produces a perfectly valid item
// handle. The discriminator is whether its traits composed, which only a real definition can do.
// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_RuntimeArchetype_ProviderRestoresDefinition,
    "Ck.Snapshot.RuntimeArchetype.ProviderRestoresDefinition",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_RuntimeArchetype_ProviderRestoresDefinition::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    const auto DefName = ck_runtime_archetype_gate::Get_DefinitionName(TEXT("Restored"));
    const auto ProviderName = ck_runtime_archetype_gate::ProviderId;

    // Exactly what a game feature does: recognise its own paths by their leaf, and re-mint from the identity that
    // leaf carries. A path this provider does not own returns null, which is the normal answer, not an error.
    ck::FCk_RuntimeArchetypeRegistry::Register(ProviderName,
    [DefName](const FSoftObjectPath& InPath) -> UCk_Entity_ConstructionScript_PDA*
    {
        if (InPath.GetAssetName() != DefName.ToString())
        { return nullptr; }

        return ck_runtime_archetype_gate::Mint_Definition(DefName);
    });

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    // Left on the harness defaults (NumCycles=2, SaveEveryCycle=true) deliberately: cycle 2 saves the world cycle 1
    // rebuilt, so this gate doubles as the RE-CAPTURE guard - the recipe a loaded world writes back must still name
    // its archetype. PostSave re-breaks the path every cycle, which is what makes cycle 2 discriminating rather
    // than a repeat. Setting SaveEveryCycle=false here, as the gates around it do, would silently drop that.
    Spec.SlotName = FName{TEXT("CkSnapshot_RuntimeArchetype_RestoredSlot")};

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    { ck_runtime_archetype_gate::Spawn_Subject(InServer); });

    Spec.SubjectReady = ck_runtime_archetype_gate::Make_SubjectReady();

    Spec.Mutate = FCk_NetAutoTest_ServerAction::CreateLambda([this, DefName](UWorld* InServer) -> void
    {
        if (NOT ck_runtime_archetype_gate::Add_ItemFromRuntimeDefinition(InServer, DefName))
        { AddError(TEXT("Setup: could not add an item from the runtime definition")); }
    });

    Spec.PostSave = FCk_NetAutoTest_ServerAction::CreateLambda([DefName](UWorld*) -> void
    { ck_runtime_archetype_gate::Break_DefinitionPath(DefName); });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
    {
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        auto Inventory = ck_runtime_archetype_gate::Resolve_Inventory(Server);

        TestTrue(TEXT("post-load: the inventory restored"), ck::IsValid(Inventory));
        if (ck::Is_NOT_Valid(Inventory))
        { return true; }

        const auto Items = UCk_Utils_Inventory_UE::Get_Items(Inventory);
        TestEqual(TEXT("post-load: the item was restored, not reaped"), Items.Num(), 1);
        if (Items.Num() != 1)
        { return true; }

        const auto* Definition = UCk_Utils_Item_UE::Get_Definition(Items[0]);
        TestTrue(TEXT("post-load: the item carries a definition"), Definition != nullptr);
        if (Definition == nullptr)
        { return true; }

        // The husk discriminator. A class-default rebuild yields a valid item whose definition IS the CDO and
        // whose trait list is empty - so these two are the assertions that fail without the provider.
        TestFalse(TEXT("post-load: the definition is not the class default (husk)"),
            Definition->HasAnyFlags(RF_ClassDefaultObject));
        TestTrue(TEXT("post-load: the definition's traits composed onto the item"),
            UCk_Utils_Item_UE::Has_ItemTrait(Items[0], UCk_ItemTrait_Tags::StaticClass()));

        auto* Sub = ck::auto_test::snapshot::Get_SnapshotSubsystem(Server);
        if (Sub != nullptr)
        {
            TestEqual(TEXT("post-load: a resolved archetype reaps nothing"),
                Sub->Get_LastLoadReport().Get_UnresolvedArchetypes().Num(), 0);
        }
        return true;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);

    // The registry is process-lifetime, so a leaked provider would quietly change every later test's answer.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([ProviderName]() -> bool
        {
            ck::FCk_RuntimeArchetypeRegistry::Unregister(ProviderName);
            return true;
        }),
        TEXT("RuntimeArchetype: test provider unregistered")));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// 3. A failed resolution must not ERASE the identity it failed to resolve.
//
// The rebuild constructs from the class default, so the archetype OBJECT is null - and a capture that only ever
// wrote a valid archetype object would write an EMPTY path, destroying the key for every load afterwards. The
// recipe therefore carries the unresolved path forward, and the reap reads it back OFF that recipe to name the
// loss. So the report naming the exact path is the observable proof that the identity survived the rebuild.
//
// Asserted on the report rather than by re-capturing, because on a fixed build a husk never reaches a second
// save: it is reaped before the world is handed back. Path preservation is what keeps the loss NAMED here, and
// what would let a build that can resolve the path restore a save an older build had already loaded.
// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_RuntimeArchetype_UnresolvedPathIsNotErased,
    "Ck.Snapshot.RuntimeArchetype.UnresolvedPathIsNotErased",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_RuntimeArchetype_UnresolvedPathIsNotErased::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    const auto DefName = ck_runtime_archetype_gate::Get_DefinitionName(TEXT("Retained"));
    const auto ExpectedLeaf = DefName.ToString();

    ck::FCk_RuntimeArchetypeRegistry::Unregister(ck_runtime_archetype_gate::ProviderId);

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = FName{TEXT("CkSnapshot_RuntimeArchetype_RetainedSlot")};
    Spec.SaveEveryCycle = false;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    { ck_runtime_archetype_gate::Spawn_Subject(InServer); });

    Spec.SubjectReady = ck_runtime_archetype_gate::Make_SubjectReady();

    Spec.Mutate = FCk_NetAutoTest_ServerAction::CreateLambda([this, DefName](UWorld* InServer) -> void
    {
        if (NOT ck_runtime_archetype_gate::Add_ItemFromRuntimeDefinition(InServer, DefName))
        { AddError(TEXT("Setup: could not add an item from the runtime definition")); }
    });

    Spec.PostSave = FCk_NetAutoTest_ServerAction::CreateLambda([DefName](UWorld*) -> void
    { ck_runtime_archetype_gate::Break_DefinitionPath(DefName); });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this, ExpectedLeaf]() -> bool
    {
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        auto* Sub = ck::auto_test::snapshot::Get_SnapshotSubsystem(Server);
        TestTrue(TEXT("post-load: snapshot subsystem resolves"), Sub != nullptr);
        if (Sub == nullptr)
        { return true; }

        const auto& Named = Sub->Get_LastLoadReport().Get_UnresolvedArchetypes();
        TestTrue(TEXT("post-load: the load report names the unresolvable archetype"), Named.Num() > 0);

        auto PathWasRetained = false;
        for (const auto& Record : Named)
        {
            if (Record.Get_ArchetypePath().Contains(ExpectedLeaf))
            { PathWasRetained = true; }
        }

        // The whole point. A rebuild that dropped the path would still reap the husk and still report a loss -
        // it just could not say WHAT was lost, and the next capture would have written nothing.
        TestTrue(TEXT("post-load: the reported loss carries the archetype path the save recorded, so the "
                      "rebuild retained the identity rather than erasing it"), PathWasRetained);
        return true;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// 4. The registry contract itself, with no world involved.
//
// Two properties carry weight beyond "it stores a function". A provider that fails to REPLACE on re-registration
// accumulates stale copies of itself across hot reloads and repeated test runs; and a MISS has to be ordinary
// control flow, because every provider is asked about every unresolvable path - most of which belong to someone
// else. A registry that treated a miss as an error would make one feature's paths every other feature's problem.
// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_RuntimeArchetype_RegistryContract,
    "Ck.Snapshot.RuntimeArchetype.RegistryContract",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_RuntimeArchetype_RegistryContract::RunTest(const FString&)
{
    const auto ProviderA = FName{TEXT("Ck.Spec.RuntimeArchetype.A")};
    const auto ProviderB = FName{TEXT("Ck.Spec.RuntimeArchetype.B")};

    const auto Clear = [ProviderA, ProviderB]() -> void
    {
        ck::FCk_RuntimeArchetypeRegistry::Unregister(ProviderA);
        ck::FCk_RuntimeArchetypeRegistry::Unregister(ProviderB);
        ck::FCk_RuntimeArchetypeRegistry::Unregister(ck_runtime_archetype_gate::ProviderId);
    };

    // Process-lifetime state shared with every other test in this editor, so the spec both starts and ends from
    // a known-empty position rather than assuming one.
    Clear();

    const auto MinePath = FSoftObjectPath{TEXT("/Engine/Transient.Ck_Spec_Mine")};
    const auto TheirsPath = FSoftObjectPath{TEXT("/Engine/Transient.Ck_Spec_Theirs")};

    TestFalse(TEXT("an empty registry reports no providers"),
        ck::FCk_RuntimeArchetypeRegistry::Get_HasAnyProvider());
    TestNull(TEXT("an empty registry resolves nothing"),
        ck::FCk_RuntimeArchetypeRegistry::TryResolve(MinePath));

    auto* Minted = ck_runtime_archetype_gate::Mint_UniqueArchetype(TEXT("Mine"));
    auto AskedForTheirs = false;

    ck::FCk_RuntimeArchetypeRegistry::Register(ProviderA,
    [MinePath, Minted, &AskedForTheirs](const FSoftObjectPath& InPath) -> UCk_Entity_ConstructionScript_PDA*
    {
        if (InPath != MinePath)
        {
            AskedForTheirs = true;
            return nullptr;
        }
        return Minted;
    });

    TestTrue(TEXT("registering one provider is visible"),
        ck::FCk_RuntimeArchetypeRegistry::Get_HasAnyProvider());
    TestTrue(TEXT("a provider resolves the path it owns, returning that exact object"),
        ck::FCk_RuntimeArchetypeRegistry::TryResolve(MinePath) == Minted);
    TestNull(TEXT("a path no provider owns resolves to null"),
        ck::FCk_RuntimeArchetypeRegistry::TryResolve(TheirsPath));
    TestTrue(TEXT("the provider was consulted about the path it does not own"), AskedForTheirs);

    auto* Replacement = ck_runtime_archetype_gate::Mint_UniqueArchetype(TEXT("Replacement"));
    ck::FCk_RuntimeArchetypeRegistry::Register(ProviderA,
    [MinePath, Replacement](const FSoftObjectPath& InPath) -> UCk_Entity_ConstructionScript_PDA*
    {
        return InPath == MinePath ? Replacement : nullptr;
    });

    TestTrue(TEXT("re-registering an id REPLACES its resolver instead of accumulating one"),
        ck::FCk_RuntimeArchetypeRegistry::TryResolve(MinePath) == Replacement);

    ck::FCk_RuntimeArchetypeRegistry::Unregister(ProviderA);
    TestNull(TEXT("an unregistered provider stops answering"),
        ck::FCk_RuntimeArchetypeRegistry::TryResolve(MinePath));
    TestFalse(TEXT("removing the only provider empties the registry"),
        ck::FCk_RuntimeArchetypeRegistry::Get_HasAnyProvider());

    auto* FromB = ck_runtime_archetype_gate::Mint_UniqueArchetype(TEXT("FromB"));
    ck::FCk_RuntimeArchetypeRegistry::Register(ProviderA,
    [](const FSoftObjectPath&) -> UCk_Entity_ConstructionScript_PDA* { return nullptr; });
    ck::FCk_RuntimeArchetypeRegistry::Register(ProviderB,
    [TheirsPath, FromB](const FSoftObjectPath& InPath) -> UCk_Entity_ConstructionScript_PDA*
    {
        return InPath == TheirsPath ? FromB : nullptr;
    });

    TestTrue(TEXT("resolution walks past a declining provider to one that claims the path"),
        ck::FCk_RuntimeArchetypeRegistry::TryResolve(TheirsPath) == FromB);

    Clear();
    TestFalse(TEXT("the spec leaves the registry as it found it"),
        ck::FCk_RuntimeArchetypeRegistry::Get_HasAnyProvider());

    return true;
}


// --------------------------------------------------------------------------------------------------------------------
// 5. The path was already ERASED, and the slot is STILL freed.
//
// The other husk gate stages a path that fails to resolve. This one stages the case that path-preservation cannot
// help with: a recipe carrying NO archetype at all, which is what a save written by a build that had already
// rebuilt a husk contains - it kept the null archetype and captured it back as an empty string.
//
// CkSnapshot cannot call that a defect. FCk_EntityReplicationDriver_ConstructionInfo is constructible from a
// script class alone, so an archetype-less build is a legal shape and the framework has no basis to reject one.
// Only CkInventory knows that an item whose definition is the class default is not an item - which is why the
// guard lives there, and why it catches the husk by what it IS rather than by how it was made.
//
// This is the "the player is left working" case: those tapes are unrecoverable either way, and the difference
// this gate defends is whether their inventory slots come back usable or dead forever.
// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_RuntimeArchetype_ErasedPathStillFreesTheSlot,
    "Ck.Snapshot.RuntimeArchetype.ErasedPathStillFreesTheSlot",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_RuntimeArchetype_ErasedPathStillFreesTheSlot::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    // No provider is relevant here: there is no path for one to claim.
    ck::FCk_RuntimeArchetypeRegistry::Unregister(ck_runtime_archetype_gate::ProviderId);

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = FName{TEXT("CkSnapshot_RuntimeArchetype_ErasedSlot")};
    Spec.SaveEveryCycle = false;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    { ck_runtime_archetype_gate::Spawn_Subject(InServer); });

    Spec.SubjectReady = ck_runtime_archetype_gate::Make_SubjectReady();

    // No PostSave needed - unlike the other husk gate there is nothing to break. The recipe is born empty.
    Spec.Mutate = FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
    {
        auto Husk = ck_runtime_archetype_gate::Build_ItemWithNoArchetype(InServer);
        if (ck::Is_NOT_Valid(Husk))
        {
            AddError(TEXT("Setup: could not build an archetype-less item into the inventory"));
            return;
        }

        // The save is the fixture, and only an OLDER build could have written it - see Unmark_Husk. The reap
        // under test happens on the LOAD side, where the marker is stamped again by the rebuild.
        ck_runtime_archetype_gate::Unmark_Husk(Husk);
    });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
    {
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        auto Inventory = ck_runtime_archetype_gate::Resolve_Inventory(Server);

        TestTrue(TEXT("post-load: the inventory itself still restored"), ck::IsValid(Inventory));
        if (ck::Is_NOT_Valid(Inventory))
        { return true; }

        // The whole point of this gate. CkSnapshot never saw a path to fail on, so without CkInventory's own
        // guard this husk is never marked, never reaped, and holds its slot for the rest of the save's life.
        TestEqual(TEXT("post-load: an item with no recoverable identity still released its slot"),
            UCk_Utils_Inventory_UE::Get_NumItems(Inventory), 0);

        auto* Sub = ck::auto_test::snapshot::Get_SnapshotSubsystem(Server);
        if (Sub != nullptr)
        {
            TestTrue(TEXT("post-load: the reap is still reported, even with no path to name"),
                Sub->Get_LastLoadReport().Get_UnresolvedArchetypes().Num() > 0);
        }
        return true;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// 6. A husk that reached a live world by a route that is NOT a load.
//
// The other five gates all run through a load, which owns the husks it produces. This one stages the case the
// load cannot see: the same class-default build, in a plain running world, with no save and no load anywhere near
// it. Nothing in production is supposed to mint one this way - which is exactly why the resident
// ck::FProcessor_UnresolvedHusk_Reap ENSURES rather than merely logging when it finds one, and why it writes no
// load-report record: the save never contained it.
//
// What it must NOT do is leave the husk alone. A route nobody has thought of is still a permanently dead
// inventory slot for the player, so the reap is unconditional and the ensure is how the route gets found.
// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_RuntimeArchetype_LiveRouteHuskIsReapedAndEnsured,
    "Ck.Snapshot.RuntimeArchetype.LiveRouteHuskIsReapedAndEnsured",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_RuntimeArchetype_LiveRouteHuskIsReapedAndEnsured::RunTest(const FString& Parameters)
{
    // The reaper's ensure and its per-occurrence ecs::Error, plus CkInventory's class-default Warning, are all
    // EXPECTED here - they are the behaviour under test. Suppression is the house shape for a PIE-driving gate
    // (every sibling in this directory does the same); exactness comes from the ensure COUNT below, because
    // suppression short-circuits the capture path that would tally an AddExpectedError occurrence.
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    // No load is involved, so a leaked provider could not change the answer - unregistered for the same reason
    // the other gates do it: the registry outlives the world and a stale entry is silent.
    ck::FCk_RuntimeArchetypeRegistry::Unregister(ck_runtime_archetype_gate::ProviderId);

    // Each ADD_LATENT_AUTOMATION_COMMAND is its own heap object, so the husk handle and the ensure baseline ride
    // a shared_ptr captured by every stage. Mirrors FRoundTripState in the snapshot harness.
    struct FLiveRouteState
    {
        FCk_Handle_Item Husk;
        bool HuskWasBuilt = false;
        bool HuskWasMarked = false;
        int32 EnsureCountBeforeSettle = 0;
    };
    const auto State = MakeShared<FLiveRouteState>();

    constexpr auto ReadyTimeoutSeconds = 30.0f;
    // Comfortably past the ~3-tick deferred-destroy pipeline plus the inventory's own EndPlay release. Matches
    // FCk_SnapshotRoundTrip_Spec::SettleFrames so this gate settles like every other one in the file.
    constexpr auto SettleFrames = 60;
    constexpr auto NumPIEClients = 2;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(NumPIEClients, ReadyTimeoutSeconds));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [](UWorld* InServer) -> void { ck_runtime_archetype_gate::Spawn_Subject(InServer); })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        ck_runtime_archetype_gate::Make_SubjectReady(), ReadyTimeoutSeconds));

    // Mint the husk and prove, before anything has had a chance to tick, that it IS one - CkInventory's construct
    // guard is what stamps the marker, and this is the only stage that observes it doing so.
    //
    // Then UNMARK it, so the reaper does not race the deferred add-item request this build just enqueued. That
    // race is not the subject: whether the container had already accepted the husk before it was reaped changes
    // which code path releases the slot, and either outcome would satisfy a naive "the slot is empty" assertion.
    // Letting the add land first is what turns the slot check below into a discriminator.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr)
            { AddError(TEXT("Setup: no server world to build the live-route husk in")); return true; }

            State->Husk = ck_runtime_archetype_gate::Build_ItemWithNoArchetype(Server);
            TestTrue(TEXT("staging: the archetype-less item built"), ck::IsValid(State->Husk));
            if (ck::Is_NOT_Valid(State->Husk))
            { return true; }

            TestTrue(TEXT("staging: the class-default build marked the item as an unresolved-archetype husk"),
                State->Husk.Has<ck::FTag_Snapshot_UnresolvedArchetype>());

            State->HuskWasBuilt = true;
            ck_runtime_archetype_gate::Unmark_Husk(State->Husk);
            return true;
        }),
        TEXT("RuntimeArchetype: live-route husk minted, marker held back")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(SettleFrames));

    // The positive control, and the moment the gate actually stages its scenario: a husk sitting in a settled
    // container, holding a slot, which is then marked by something that is not a load. That is the whole shape
    // the resident reaper exists for - the marker records what an entity IS, not how it was made.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            if (NOT State->HuskWasBuilt)
            { return true; }

            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto Inventory = ck_runtime_archetype_gate::Resolve_Inventory(Server);
            TestTrue(TEXT("staging: the inventory resolves"), ck::IsValid(Inventory));
            if (ck::Is_NOT_Valid(Inventory))
            { return true; }

            TestEqual(TEXT("staging: the husk occupies an inventory slot before it is marked"),
                UCk_Utils_Inventory_UE::Get_NumItems(Inventory), 1);
            TestTrue(TEXT("staging: the husk survived the settle while unmarked"), ck::IsValid(State->Husk));
            if (ck::Is_NOT_Valid(State->Husk))
            { return true; }

            State->Husk.AddOrGet<ck::FTag_Snapshot_UnresolvedArchetype>();
            State->HuskWasMarked = true;

            // Taken after the mark so the delta covers the reaper's window and nothing else.
            State->EnsureCountBeforeSettle = UCk_Utils_Ensure_UE::Get_EnsureCount();
            return true;
        }),
        TEXT("RuntimeArchetype: live-route husk marked in a settled world")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(SettleFrames));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            // An earlier stage already reported its own failure; asserting on a husk that was never staged would
            // bury that one error under three derived ones.
            if (NOT State->HuskWasMarked)
            { return true; }

            // The reap itself. A handle to a destroyed entity reads invalid.
            TestFalse(TEXT("post-settle: the husk was destroyed by the resident reaper"),
                ck::IsValid(State->Husk));

            // An ensure per husk and no more. The route is a code defect, so it must be LOUD - but the reaper
            // visits each husk once (its view excludes FTag_DestroyEntity_Initiate, which Request_DestroyEntity
            // stamps synchronously), and a second ensure would mean it re-visited an entity it had already
            // destroyed. Counted rather than pattern-matched on the log: under bSuppressLogErrors the automation
            // framework never tallies an expected message's occurrences, so the process-global ensure counter is
            // the only exact number available.
            TestEqual(TEXT("post-settle: reaping the husk ensured exactly once"),
                UCk_Utils_Ensure_UE::Get_EnsureCount(), State->EnsureCountBeforeSettle + 1);

            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto Inventory = ck_runtime_archetype_gate::Resolve_Inventory(Server);
            TestTrue(TEXT("post-settle: the inventory itself is untouched"), ck::IsValid(Inventory));
            if (ck::Is_NOT_Valid(Inventory))
            { return true; }

            // Why the reaper destroys through the ordinary path rather than freeing the entity: the container has
            // to stop counting the slot. The previous stage measured this same number as 1, so a reap that freed
            // the entity behind the inventory's back would leave it reading 1 here and fail.
            TestEqual(TEXT("post-settle: the reaped husk released its inventory slot"),
                UCk_Utils_Inventory_UE::Get_NumItems(Inventory), 0);

            return true;
        }),
        TEXT("RuntimeArchetype: live-route husk reaped, ensured, and slot released")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// 7. The archetype identity TRAVELS to the client, and the replicated item is healthy on arrival.
//
// No save and no load anywhere in this gate, which is the point: the identity path is not a load-only repair. A
// runtime-minted definition is RF_Transient and therefore not net-addressable, so on a real client the archetype
// OBJECT reference in the replicated ConstructionInfo arrives null and the client builds from the class default -
// a trait-less item on a machine where the server has a real one.
//
// WHAT THIS GATE CANNOT ASSERT, and why it does not try. Multi-client PIE runs every world in ONE process, so the
// server's RF_Transient definition is still reachable by name from the client world and the object reference
// resolves through same-process aliasing that a packaged client does not have. The client therefore takes
// Construct_FromInfo's valid-archetype branch here no matter which build it is running, which means the item-level
// checks below - true, and kept, because a regression that broke the replicated item WOULD surface in them - cannot
// by themselves tell the fix from the bug. An earlier draft of this gate asserted the provider had been consulted
// and failed for exactly that reason.
//
// So this gate pins TRANSPORT: the builder stamps the identity, it rides the same replicated struct, and it is
// non-empty on the receiving side. The other half - that the path ALONE rebuilds the archetype, which is the branch
// a real client takes - is pinned with no wire at all by Ck.Snapshot.RuntimeArchetype.IdentityPathAloneResolvesViaProvider.
// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_RuntimeArchetype_TransientArchetypeReachesClientResolved,
    "Ck.Snapshot.RuntimeArchetype.TransientArchetypeReachesClientResolved",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_RuntimeArchetype_TransientArchetypeReachesClientResolved::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    const auto DefName = ck_runtime_archetype_gate::Get_DefinitionName(TEXT("ClientResolved"));
    const auto ExpectedLeaf = DefName.ToString();
    const auto ProviderName = ck_runtime_archetype_gate::ProviderId;

    constexpr auto NumPIEClients = 2;        // listen-server + 1 client
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto ConvergeTimeoutSeconds = 20.0;

    // Registered even though PIE's object aliasing means the client is not expected to need it: production DOES,
    // and a client that ever stops resolving the pointer must land on the provider rather than on a husk. Leaving
    // it out would make this gate depend on the aliasing it is documenting as an artefact.
    ck::FCk_RuntimeArchetypeRegistry::Register(ProviderName,
    [DefName](const FSoftObjectPath& InPath) -> UCk_Entity_ConstructionScript_PDA*
    {
        if (InPath.GetAssetName() != DefName.ToString())
        { return nullptr; }

        return ck_runtime_archetype_gate::Mint_Definition(DefName);
    });

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [](UWorld* InServer) -> void { ck_runtime_archetype_gate::Spawn_Subject(InServer); })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        ck_runtime_archetype_gate::Make_SubjectReady(), ReadyTimeoutSeconds));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, DefName](UWorld* InServer) -> void
        {
            if (NOT ck_runtime_archetype_gate::Add_ItemFromRuntimeDefinition(InServer, DefName))
            { AddError(TEXT("Setup: could not add an item from the runtime definition")); }
        })));

    // The add is a deferred request, so the server's own item is awaited rather than assumed.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            auto Inventory = ck_runtime_archetype_gate::Resolve_Inventory(ck::auto_test::net::Get_ServerWorld());
            return ck::IsValid(Inventory) && UCk_Utils_Inventory_UE::Get_NumItems(Inventory) == 1;
        }),
        ConvergeTimeoutSeconds, TEXT("RuntimeArchetype: server item built from the transient definition")));

    // The server cross-check. Without it a client that came back with nothing at all would still satisfy a
    // "the client has no husk" reading of the assertions below.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto Inventory = ck_runtime_archetype_gate::Resolve_Inventory(ck::auto_test::net::Get_ServerWorld());
            TestTrue(TEXT("server: the inventory resolves"), ck::IsValid(Inventory));
            if (ck::Is_NOT_Valid(Inventory))
            { return true; }

            const auto Items = UCk_Utils_Inventory_UE::Get_Items(Inventory);
            TestEqual(TEXT("server: the item exists"), Items.Num(), 1);
            if (Items.Num() != 1)
            { return true; }

            TestTrue(TEXT("server: the item is trait-bearing, so the client has something real to match"),
                UCk_Utils_Item_UE::Has_ItemTrait(Items[0], UCk_ItemTrait_Tags::StaticClass()));
            return true;
        }),
        TEXT("RuntimeArchetype: server-side cross-check")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            auto Inventory = ck_runtime_archetype_gate::Resolve_Inventory(ck::auto_test::net::Get_ClientWorld(0));
            return ck::IsValid(Inventory) && UCk_Utils_Inventory_UE::Get_NumItems(Inventory) == 1;
        }),
        ConvergeTimeoutSeconds, TEXT("RuntimeArchetype: the item replicated to the client")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, ExpectedLeaf]() -> bool
        {
            auto Inventory = ck_runtime_archetype_gate::Resolve_Inventory(ck::auto_test::net::Get_ClientWorld(0));
            TestTrue(TEXT("client: the inventory resolves"), ck::IsValid(Inventory));
            if (ck::Is_NOT_Valid(Inventory))
            { return true; }

            const auto Items = UCk_Utils_Inventory_UE::Get_Items(Inventory);
            TestEqual(TEXT("client: the item replicated"), Items.Num(), 1);
            if (Items.Num() != 1)
            { return true; }

            // THE PIN. The builder stamps the identity beside the object reference, and this is the receiving
            // side reading it back off the replicated struct that carried it. Empty here means the archetype
            // crossed as a bare pointer, which is the shape that produces a husk the moment the process boundary
            // is real. It is asserted rather than the resolution branch for the reason in the header comment.
            const auto ReceivedPath = ck_runtime_archetype_gate::TryGet_ReceivedArchetypeIdentityPath(Items[0]);
            TestFalse(TEXT("client: the received construction info carries a non-empty archetype identity path"),
                ReceivedPath.IsEmpty());
            TestTrue(TEXT("client: the received identity path names the definition the server built from"),
                ReceivedPath.Contains(ExpectedLeaf));

            // Health checks on the replicated item. Under PIE's object aliasing these pass on either build, so
            // they are not the discriminator - they are the guard that the transport fix did not break the item.
            //
            // A client husk is never reaped (deleting half a replicated pair is worse than leaving it), so the
            // marker would still be on the entity if one had been built.
            TestFalse(TEXT("client: the item is not an unresolved-archetype husk"),
                Items[0].Has<ck::FTag_Snapshot_UnresolvedArchetype>());

            const auto* Definition = UCk_Utils_Item_UE::Get_Definition(Items[0]);
            TestTrue(TEXT("client: the item carries a definition"), Definition != nullptr);
            if (Definition == nullptr)
            { return true; }

            TestFalse(TEXT("client: the definition is not the class default"),
                Definition->HasAnyFlags(RF_ClassDefaultObject));
            TestTrue(TEXT("client: the definition's traits composed onto the item"),
                UCk_Utils_Item_UE::Has_ItemTrait(Items[0], UCk_ItemTrait_Tags::StaticClass()));
            return true;
        }),
        TEXT("RuntimeArchetype: the archetype identity reached the client alongside a healthy item")));

    // The registry is process-lifetime, so a leaked provider would quietly change every later test's answer.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([ProviderName]() -> bool
        {
            ck::FCk_RuntimeArchetypeRegistry::Unregister(ProviderName);
            return true;
        }),
        TEXT("RuntimeArchetype: test provider unregistered")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// 8. The identity path ALONE rebuilds the archetype - the branch a packaged client actually takes.
//
// The other half of gate 7, staged where gate 7 cannot reach: an info carrying a valid ConstructionScript class, a
// NULL archetype OBJECT, and an identity path. That pair is byte-for-byte what a real client deserializes, and no
// PIE client can be made to present it - same-process aliasing keeps its pointer resolving (gate 7's header). So it
// is built directly instead, and every OTHER thing about the build is left production-shaped.
//
// ONE world, no clients, no save, no load: nothing here crosses a wire, and a listen-server PIE world is the
// cheapest place with a real entity in it. It is not run against a bare ck::FEcsWorld even though the branch under
// test needs no world - an entity created straight off a registry reaches construction with no net info and no
// lifetime owner, and the framework ensures on both. Request_BuildAndReplicate on a real ContextOwner is the
// production path, so the gate exercises the branch without also inventing an entity shape nothing else produces.
//
// The second arm is what makes the first mean something. The same build with NO identity path must produce the husk
// - class-default definition, marker stamped - so the gate reads as "the path is what did it" rather than "the
// provider works", which gate 4 already covers on its own.
// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_RuntimeArchetype_IdentityPathAloneResolvesViaProvider,
    "Ck.Snapshot.RuntimeArchetype.IdentityPathAloneResolvesViaProvider",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_RuntimeArchetype_IdentityPathAloneResolvesViaProvider::RunTest(const FString& Parameters)
{
    // The control arm builds a husk on purpose: CkInventory's construct guard Warns as it is built, and the
    // resident reaper then ensures and Errors as it destroys it. All three are the behaviour under test, and this
    // gate deliberately asserts on NEITHER the log nor the ensure count - the marker is read same-tick instead.
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    const auto DefName = ck_runtime_archetype_gate::Get_DefinitionName(TEXT("PathOnly"));
    const auto ProviderName = ck_runtime_archetype_gate::ProviderId;

    constexpr auto NumPIEClients = 1;        // listen-server only; the harness forces PIE_ListenServer either way
    constexpr auto ExpectedTotalWorlds = 1;
    constexpr auto ReadyTimeoutSeconds = 30.0f;

    // Minted once here purely to learn the path a builder WOULD stamp - taken off the object rather than spelled
    // by hand, so the gate cannot drift from the stamp's real shape. The pointer is deliberately not kept: the
    // definition is transient and unrooted, and Mint_Definition is idempotent by (outer, name), so the provider
    // re-mints the same object under the same path if GC took it in between.
    auto* Minted = ck_runtime_archetype_gate::Mint_Definition(DefName);
    if (NOT TestNotNull(TEXT("setup: the runtime definition minted"), Minted))
    { return false; }

    const auto IdentityPath = Minted->GetPathName();

    struct FPathOnlyState
    {
        bool ProviderWasConsulted = false;
    };
    const auto State = MakeShared<FPathOnlyState>();

    ck::FCk_RuntimeArchetypeRegistry::Register(ProviderName,
    [DefName, State](const FSoftObjectPath& InPath) -> UCk_Entity_ConstructionScript_PDA*
    {
        if (InPath.GetAssetName() != DefName.ToString())
        { return nullptr; }

        State->ProviderWasConsulted = true;
        return ck_runtime_archetype_gate::Mint_Definition(DefName);
    });

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [](UWorld* InServer) -> void { ck_runtime_archetype_gate::Spawn_Subject(InServer); })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        ck_runtime_archetype_gate::Make_SubjectReady(), ReadyTimeoutSeconds));

    // Both arms and every assertion live in ONE stage, and that is a correctness requirement rather than tidiness.
    // Construct_FromInfo runs synchronously inside Request_BuildAndReplicate, so the provider flag, the definition
    // and the marker are all final the instant the build returns - and the control arm's husk is marked, which
    // means the resident reaper destroys it on a later Gameplay pass. Reading it in a following stage would race
    // that reap for no benefit.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State, IdentityPath]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr)
            { AddError(TEXT("Setup: no server world to build the identity-path item in")); return true; }

            // ---- Arm 1: null archetype OBJECT, identity path present. The packaged client's branch. ----

            auto Resolved = ck_runtime_archetype_gate::Build_ItemFromArchetypeIdentityOnly(Server, IdentityPath);
            TestTrue(TEXT("resolved: the identity-only build produced an item"), ck::IsValid(Resolved));
            if (ck::Is_NOT_Valid(Resolved))
            { return true; }

            TestTrue(TEXT("resolved: the path alone reached a runtime-archetype provider"),
                State->ProviderWasConsulted);

            const auto* Definition = UCk_Utils_Item_UE::Get_Definition(Resolved);
            TestTrue(TEXT("resolved: the item carries a definition"), Definition != nullptr);
            if (Definition == nullptr)
            { return true; }

            // Identity by PATH rather than by pointer: the definition is transient and unrooted, so a GC between
            // the mint above and this build would legitimately hand back a different object at the same identity -
            // which is the correct outcome, and a pointer comparison would call it a failure.
            TestFalse(TEXT("resolved: the definition is not the class default"),
                Definition->HasAnyFlags(RF_ClassDefaultObject));
            TestEqual(TEXT("resolved: the definition is the one the identity path names"),
                Definition->GetPathName(), IdentityPath);
            TestFalse(TEXT("resolved: the entity carries no unresolved-archetype marker"),
                Resolved.Has<ck::FTag_Snapshot_UnresolvedArchetype>());
            TestTrue(TEXT("resolved: the definition's traits composed onto the entity"),
                UCk_Utils_Item_UE::Has_ItemTrait(Resolved, UCk_ItemTrait_Tags::StaticClass()));

            // ---- Arm 2: the identical build with NO identity path. What the fix prevents. ----

            auto Husk = ck_runtime_archetype_gate::Build_ItemWithNoArchetype(Server);
            TestTrue(TEXT("control: the class-default build still produced an item"), ck::IsValid(Husk));
            if (ck::Is_NOT_Valid(Husk))
            { return true; }

            const auto* HuskDefinition = UCk_Utils_Item_UE::Get_Definition(Husk);
            TestTrue(TEXT("control: the husk carries a definition"), HuskDefinition != nullptr);
            if (HuskDefinition == nullptr)
            { return true; }

            TestTrue(TEXT("control: with no identity path the entity is built from the class default"),
                HuskDefinition->HasAnyFlags(RF_ClassDefaultObject));
            TestTrue(TEXT("control: the class-default build is marked as an unresolved-archetype husk"),
                Husk.Has<ck::FTag_Snapshot_UnresolvedArchetype>());

            // Left marked on purpose. The resident reaper owns it from here and destroys it through the ordinary
            // path, which is gate 6's subject, not this one's - it is not unmarked, and no ensure count is read.
            return true;
        }),
        TEXT("RuntimeArchetype: the identity path alone rebuilt the archetype")));

    // The registry is process-lifetime, so a leaked provider would quietly change every later test's answer.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([ProviderName]() -> bool
        {
            ck::FCk_RuntimeArchetypeRegistry::Unregister(ProviderName);
            return true;
        }),
        TEXT("RuntimeArchetype: test provider unregistered")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
