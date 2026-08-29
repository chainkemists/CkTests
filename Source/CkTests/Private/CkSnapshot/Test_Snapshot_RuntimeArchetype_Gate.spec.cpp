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
// Surface in Session Frontend:
//   Ck.Snapshot.RuntimeArchetype.HuskIsReapedAndNamed
//   Ck.Snapshot.RuntimeArchetype.ProviderRestoresDefinition
//   Ck.Snapshot.RuntimeArchetype.UnresolvedPathIsNotErased
//   Ck.Snapshot.RuntimeArchetype.RegistryContract

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "Engine/GameInstance.h"
#include "EngineUtils.h"               // TActorIterator
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel
#include "UObject/Package.h"           // GetTransientPackage

#include "CkInventory/Inventory/CkInventory_Utils.h"
#include "CkInventory/Inventory/DataOnly/CkInventory_DataOnly_Utils.h"
#include "CkInventory/Item/CkItem_Definition.h"
#include "CkInventory/Item/CkItem_Utils.h"
#include "CkInventory/ItemTrait/Tags/CkItemTrait_Tags.h"

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"
#include "CkEcs/Net/EntityReplicationDriver/CkEntityReplicationDriver_BuildRecipe.h"
#include "CkEcs/Persistence/CkRuntimeArchetype_Registry.h"

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

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
