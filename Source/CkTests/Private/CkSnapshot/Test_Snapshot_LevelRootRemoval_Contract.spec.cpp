// CkSnapshot regression contract for Foundation-owned level-root persistence.
//
// These tests deliberately stop below fixture policy. They pin Foundation invariants that are
// independent of the eventual public removal API: automatic origin provenance, durable suppression,
// collision safety, cancellation after source teardown, and refusal of non-authored identities.

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/GameInstance.h"
#include "Engine/World.h"
#include "GameFramework/Actor.h"
#include "Kismet/GameplayStatics.h"
#include "Misc/ScopeExit.h"
#include "StructUtils/InstancedStruct.h"
#include "UObject/SoftObjectPath.h"
#include "UObject/UnrealType.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Registry/CkRegistry.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "CkEcs/Snapshot/CkSaveKey_Fragment.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkEcsExt/EntityScript/CkEntityScript_WithActor.h"
#include "CkEcsExt/EntityScript/CkEntityScript_WithActor_Data.h"

#include "CkEntitySpawner/CkEntitySpawner_Actor.h"

#include "CkSnapshot/SaveGame/CkSnapshot_SaveGame.h"
#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_snapshot_level_root_removal_contract
{
    constexpr auto SinglePIEClient = 1;
    constexpr auto MultiPIEClients = 2;
    constexpr auto SinglePIEWorld = 1;
    constexpr auto ListenServerAndClientWorlds = 2;
    constexpr auto PIEReadyTimeoutSeconds = 30.0f;

    const auto EntryMap = FString{TEXT("/Engine/Maps/Entry")};
    const auto PendingMutationSlot = FName{TEXT("Ck_LevelRootRemoval_PendingMutation")};
    const auto CancelledMutationSlot = FName{TEXT("Ck_LevelRootRemoval_CancelledMutation")};
    const auto CommittedMutationSlot = FName{TEXT("Ck_LevelRootRemoval_CommittedMutation")};
    const auto SpawnerCancelledSlot = FName{TEXT("Ck_LevelRootRemoval_SpawnerCancelled")};
    const auto SpawnerCommittedSlot = FName{TEXT("Ck_LevelRootRemoval_SpawnerCommitted")};
    const auto SpawnerProbeName = FName{TEXT("Ck_LevelRootRemoval_SpawnerProbe")};

    struct FInjectedSpawnerState
    {
        FDelegateHandle InjectionHandle;
        FGuid ExpectedKey;
        int32 NumInjectedWorlds = 0;
        FString Failure;
    };

    auto Inject_OwningActor(
        UCk_EntityScript_WithActor_UE& InScript,
        AActor& InActor) -> bool
    {
        auto* OwningActorProperty = FindFProperty<FObjectPropertyBase>(
            InScript.GetClass(), TEXT("_OwningActor"));
        if (OwningActorProperty == nullptr)
        { return false; }

        OwningActorProperty->SetObjectPropertyValue_InContainer(&InScript, &InActor);
        return true;
    }

    auto Get_SnapshotSubsystem(UWorld* InWorld) -> UCk_Snapshot_Subsystem_UE*
    {
        if (InWorld == nullptr || InWorld->GetGameInstance() == nullptr)
        { return nullptr; }
        return InWorld->GetGameInstance()->GetSubsystem<UCk_Snapshot_Subsystem_UE>();
    }

    auto Count_SaveKeys(UWorld* InWorld, const FGuid* InKey = nullptr) -> int32
    {
        auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InWorld);
        if (ck::Is_NOT_Valid(Transient))
        { return 0; }

        auto Count = 0;
        Transient.View<FFragment_SaveKey>().ForEach(
            [&Count, InKey](const FCk_Entity&, const FFragment_SaveKey& InSaveKey)
            {
                if (InKey == nullptr || InSaveKey.Get_Key() == *InKey)
                { ++Count; }
            });
        return Count;
    }

    auto Find_SaveKey(UWorld* InWorld, const FGuid& InKey) -> FCk_Handle
    {
        auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InWorld);
        if (ck::Is_NOT_Valid(Transient))
        { return {}; }

        auto Result = FCk_Handle{};
        Transient.View<FFragment_SaveKey>().ForEach(
            [&Result, &Transient, &InKey](const FCk_Entity& InEntity, const FFragment_SaveKey& InSaveKey)
            {
                if (ck::Is_NOT_Valid(Result) && InSaveKey.Get_Key() == InKey)
                { Result = ck::MakeHandle(InEntity, Transient); }
            });
        return Result;
    }

    auto Get_CurrentPIEWorld() -> UWorld*
    {
        for (auto* World : ck::auto_test::net::Get_AllPIEWorlds())
        {
            if (World != nullptr && World->HasBegunPlay())
            { return World; }
        }
        return nullptr;
    }

    auto Remove_SpawnerInjector(const TSharedRef<FInjectedSpawnerState>& InState) -> void
    {
        if (InState->InjectionHandle.IsValid())
        {
            FWorldDelegates::OnPostWorldInitialization.Remove(InState->InjectionHandle);
            InState->InjectionHandle.Reset();
        }
    }

    auto Load_SaveGame(const FName InSlotName) -> UCk_Snapshot_SaveGame*
    {
        return Cast<UCk_Snapshot_SaveGame>(
            UGameplayStatics::LoadGameFromSlot(InSlotName.ToString(), 0));
    }

    auto Resolve_LevelRootProbeClass() -> TSubclassOf<UCk_EntityScript_UE>
    {
        return FSoftClassPath(TEXT("/Script/Angelscript.Ck_AutoTest_Snapshot_LevelRootProbe_EntityScript"))
            .TryLoadClass<UCk_EntityScript_UE>();
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_LevelRootOriginContract,
    "Ck.Snapshot.LevelRootRemoval.OriginContract",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_LevelRootOriginContract::RunTest(const FString& Parameters)
{
    const auto* LevelRootProperty = FindFProperty<FBoolProperty>(
        FFragment_SaveKey::StaticStruct(), TEXT("_IsLevelPlacedRoot"));
    TestNotNull(TEXT("level-root provenance remains reflected"), LevelRootProperty);
    if (LevelRootProperty != nullptr)
    {
        TestTrue(TEXT("level-root provenance is reconstructed rather than serialized"),
            LevelRootProperty->HasAnyPropertyFlags(CPF_Transient));
        TestFalse(TEXT("level-root provenance never enters save payloads"),
            LevelRootProperty->HasAnyPropertyFlags(CPF_SaveGame));
    }

    auto EnttRegistry = ck::registry_table::EnttRegistryType{};
    const auto RegistryHandle = ck::registry_table::Allocate(&EnttRegistry);
    auto Registry = FCk_Registry{RegistryHandle};
    ON_SCOPE_EXIT { ck::registry_table::Free(RegistryHandle); };

    auto LevelRoot = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
    auto OrdinaryKeyedRoot = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
    auto SharedRoot = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);

    ck::save_key::AssignLevelPlaced(LevelRoot, TEXT("Ck.Spec.LevelRoot"));
    ck::save_key::Assign(OrdinaryKeyedRoot, TEXT("Ck.Spec.OrdinaryRoot"));
    ck::save_key::AssignSharedRendezvousGroup(SharedRoot, TEXT("Ck.Spec.SharedRoot"));

    TestTrue(TEXT("AssignLevelPlaced marks authored provenance"),
        LevelRoot.Get<FFragment_SaveKey>().Get_IsLevelPlacedRoot());
    TestFalse(TEXT("generic stable identity is not level-removal authority"),
        OrdinaryKeyedRoot.Get<FFragment_SaveKey>().Get_IsLevelPlacedRoot());
    TestFalse(TEXT("shared infrastructure identity is not level-removal authority"),
        SharedRoot.Get<FFragment_SaveKey>().Get_IsLevelPlacedRoot());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_LevelRootCkEntitySpawnerOrigin,
    "Ck.Snapshot.LevelRootRemoval.CkEntitySpawnerOrigin",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_LevelRootCkEntitySpawnerOrigin::RunTest(const FString& Parameters)
{
    using namespace ck_test_snapshot_level_root_removal_contract;

    const auto BaselineKeyCount = MakeShared<int32>(0);
    const auto ExpectedLevelKey = MakeShared<FGuid>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(SinglePIEClient, EntryMap));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(SinglePIEWorld, PIEReadyTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda(
            [this, BaselineKeyCount, ExpectedLevelKey](UWorld* InServer) -> void
            {
                const auto ProbeClass = Resolve_LevelRootProbeClass();
                TestTrue(TEXT("fixture probe EntityScript resolves"), ProbeClass != nullptr);
                if (ProbeClass == nullptr)
                { return; }

                *BaselineKeyCount = Count_SaveKeys(InServer);

                const auto LevelTransform = FTransform{FVector{-1200.0, 0.0, 0.0}};
                auto* LevelSpawner = InServer->SpawnActorDeferred<ACk_EntitySpawner_UE>(
                    ACk_EntitySpawner_UE::StaticClass(), LevelTransform);
                TestNotNull(TEXT("level-authored spawner actor is created"), LevelSpawner);
                if (LevelSpawner == nullptr)
                { return; }

                // RF_WasLoaded is the exact linker-owned production discriminator. Setting it before BeginPlay
                // gives this real ACk_EntitySpawner_UE the same origin state as a serialized map actor without
                // committing a binary map solely for this contract spec.
                LevelSpawner->SetFlags(RF_WasLoaded);
                LevelSpawner->EditorOnly_InitializeEntityScript(ProbeClass);
                const auto LevelIdentity = ck::save_key::Get_LevelPlacedIdentity(LevelSpawner);
                TestFalse(TEXT("serialized spawner identity is non-empty"), LevelIdentity.IsEmpty());
                *ExpectedLevelKey = FGuid::NewDeterministicGuid(LevelIdentity);
                UGameplayStatics::FinishSpawningActor(LevelSpawner, LevelTransform);

                const auto RuntimeTransform = FTransform{FVector{1200.0, 0.0, 0.0}};
                auto* RuntimeSpawner = InServer->SpawnActorDeferred<ACk_EntitySpawner_UE>(
                    ACk_EntitySpawner_UE::StaticClass(), RuntimeTransform);
                TestNotNull(TEXT("runtime spawner actor is created"), RuntimeSpawner);
                if (RuntimeSpawner == nullptr)
                { return; }

                RuntimeSpawner->EditorOnly_InitializeEntityScript(ProbeClass);
                TestTrue(TEXT("runtime spawner has no stable level identity"),
                    ck::save_key::Get_LevelPlacedIdentity(RuntimeSpawner).IsEmpty());
                UGameplayStatics::FinishSpawningActor(RuntimeSpawner, RuntimeTransform);
            })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(10));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda(
            [this, BaselineKeyCount, ExpectedLevelKey](UWorld* InServer) -> void
            {
                TestTrue(TEXT("serialized spawner produced its deterministic SaveKey"),
                    ExpectedLevelKey->IsValid());
                TestEqual(TEXT("serialized fixture spawner adds exactly one keyed root while runtime spawner adds none"),
                    Count_SaveKeys(InServer), *BaselineKeyCount + 1);
                TestEqual(TEXT("serialized fixture spawner publishes exactly one entity with its canonical key"),
                    Count_SaveKeys(InServer, &ExpectedLevelKey.Get()), 1);

                auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
                auto FoundLevelProvenance = false;
                Transient.View<FFragment_SaveKey>().ForEach(
                    [&FoundLevelProvenance, ExpectedLevelKey](
                        const FCk_Entity&, const FFragment_SaveKey& InSaveKey)
                    {
                        if (InSaveKey.Get_Key() == *ExpectedLevelKey)
                        { FoundLevelProvenance = InSaveKey.Get_IsLevelPlacedRoot(); }
                    });
                TestTrue(TEXT("serialized fixture spawner stamps level-root provenance"),
                    FoundLevelProvenance);
            })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_LevelRootSuppressionHeaderRoundTrip,
    "Ck.Snapshot.LevelRootRemoval.SuppressionHeaderRoundTrip",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_LevelRootSuppressionHeaderRoundTrip::RunTest(const FString& Parameters)
{
    auto* SaveGame = NewObject<UCk_Snapshot_SaveGame>();
    TestNotNull(TEXT("snapshot SaveGame object is valid"), SaveGame);
    if (SaveGame == nullptr)
    { return false; }

    const auto SuppressedKey = FGuid::NewGuid();
    auto SuppressedKeys = TArray<FGuid>{SuppressedKey};
    SaveGame->_HeaderV3.Set_SuppressedSaveKeys(SuppressedKeys);
    SaveGame->_SnapshotBytesV3 = {0x43, 0x4B};

    auto Bytes = TArray<uint8>{};
    TestTrue(TEXT("snapshot serializes through the Unreal SaveGame envelope"),
        UGameplayStatics::SaveGameToMemory(SaveGame, Bytes));
    TestTrue(TEXT("serialized snapshot has a SaveGame envelope"),
        ck::snapshot::Get_HasSaveGameEnvelopeTag(Bytes));

    auto* Loaded = Cast<UCk_Snapshot_SaveGame>(
        UGameplayStatics::LoadGameFromMemory(Bytes));
    TestNotNull(TEXT("serialized snapshot loads as UCk_Snapshot_SaveGame"), Loaded);
    if (Loaded == nullptr)
    { return false; }

    TestTrue(TEXT("durable level-root suppression survives header serialization"),
        Loaded->_HeaderV3.Get_SuppressedSaveKeys().Contains(SuppressedKey));
    TestTrue(TEXT("header addition preserves the native snapshot payload"),
        Loaded->_SnapshotBytesV3 == SaveGame->_SnapshotBytesV3);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_LevelActorBridgeOrigin,
    "Ck.Snapshot.LevelRootRemoval.LevelActorBridgeOrigin",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_LevelActorBridgeOrigin::RunTest(const FString& Parameters)
{
    using namespace ck_test_snapshot_level_root_removal_contract;

    auto EnttRegistry = ck::registry_table::EnttRegistryType{};
    const auto RegistryHandle = ck::registry_table::Allocate(&EnttRegistry);
    auto Registry = FCk_Registry{RegistryHandle};
    ON_SCOPE_EXIT { ck::registry_table::Free(RegistryHandle); };

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);
    TestNotNull(TEXT("test world is valid"), World);
    if (World == nullptr)
    { return false; }
    ON_SCOPE_EXIT { World->DestroyWorld(false); };

    auto* LevelActor = World->SpawnActor<AActor>();
    TestNotNull(TEXT("level-origin actor is valid"), LevelActor);
    if (LevelActor == nullptr)
    { return false; }

    // RF_WasLoaded is the production discriminator used by Get_LevelPlacedIdentity. Applying it
    // to a real actor in a real ULevel isolates the construction contract without requiring a
    // committed binary test map merely to exercise the same linker-owned flag.
    LevelActor->SetFlags(RF_WasLoaded);

    auto LevelEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
    auto* LevelScript = NewObject<UCk_EntityScript_WithActor_UE>();
    TestNotNull(TEXT("level ActorBridge script is valid"), LevelScript);
    if (LevelScript == nullptr)
    { return false; }
    const auto LevelActorInjected = Inject_OwningActor(*LevelScript, *LevelActor);
    TestTrue(TEXT("level ActorBridge test injects its production owning-actor field"), LevelActorInjected);
    if (NOT LevelActorInjected)
    { return false; }

    const auto LevelSpawnParams = FInstancedStruct::Make<FCk_EntityScript_WithActor_SpawnParams>(LevelActor);
    const auto LevelFlow = LevelScript->Construct(LevelEntity, LevelSpawnParams);
    TestEqual(TEXT("level ActorBridge construction finishes"),
        LevelFlow, ECk_EntityScript_ConstructionFlow::Finished);
    TestTrue(TEXT("level ActorBridge receives a deterministic SaveKey"),
        LevelEntity.Has<FFragment_SaveKey>());
    if (LevelEntity.Has<FFragment_SaveKey>())
    {
        TestTrue(TEXT("level ActorBridge SaveKey carries level-root provenance"),
            LevelEntity.Get<FFragment_SaveKey>().Get_IsLevelPlacedRoot());
    }

    auto* RuntimeActor = World->SpawnActor<AActor>();
    TestNotNull(TEXT("runtime actor is valid"), RuntimeActor);
    if (RuntimeActor == nullptr)
    { return false; }

    auto RuntimeEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
    auto* RuntimeScript = NewObject<UCk_EntityScript_WithActor_UE>();
    TestNotNull(TEXT("runtime ActorBridge script is valid"), RuntimeScript);
    if (RuntimeScript == nullptr)
    { return false; }
    const auto RuntimeActorInjected = Inject_OwningActor(*RuntimeScript, *RuntimeActor);
    TestTrue(TEXT("runtime ActorBridge test injects its production owning-actor field"), RuntimeActorInjected);
    if (NOT RuntimeActorInjected)
    { return false; }

    const auto RuntimeSpawnParams = FInstancedStruct::Make<FCk_EntityScript_WithActor_SpawnParams>(RuntimeActor);
    const auto RuntimeFlow = RuntimeScript->Construct(RuntimeEntity, RuntimeSpawnParams);
    TestEqual(TEXT("runtime ActorBridge construction finishes"),
        RuntimeFlow, ECk_EntityScript_ConstructionFlow::Finished);
    TestFalse(TEXT("runtime ActorBridge is never marked as a level-authored root"),
        RuntimeEntity.Has<FFragment_SaveKey>() &&
            RuntimeEntity.Get<FFragment_SaveKey>().Get_IsLevelPlacedRoot());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_LevelRootDuplicateIdentityFailsClosed,
    "Ck.Snapshot.LevelRootRemoval.DuplicateIdentityFailsClosed",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_LevelRootDuplicateIdentityFailsClosed::RunTest(const FString& Parameters)
{
    auto EnttRegistry = ck::registry_table::EnttRegistryType{};
    const auto RegistryHandle = ck::registry_table::Allocate(&EnttRegistry);
    auto Registry = FCk_Registry{RegistryHandle};
    ON_SCOPE_EXIT { ck::registry_table::Free(RegistryHandle); };

    auto FirstRoot = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
    auto CollidingRoot = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
    const auto Identity = FString{TEXT("Ck.Spec.DuplicateLevelRoot")};
    ck::save_key::AssignLevelPlaced(FirstRoot, Identity);
    ck::save_key::AssignLevelPlaced(CollidingRoot, Identity);

    auto* GameInstance = NewObject<UGameInstance>();
    TestNotNull(TEXT("snapshot subsystem outer is valid"), GameInstance);
    if (GameInstance == nullptr)
    { return false; }

    auto* Subsystem = NewObject<UCk_Snapshot_Subsystem_UE>(GameInstance);
    TestNotNull(TEXT("snapshot subsystem test instance is valid"), Subsystem);
    if (Subsystem == nullptr)
    { return false; }

    const auto Key = FirstRoot.Get<FFragment_SaveKey>().Get_Key();
    TestTrue(TEXT("first unique authored publisher is accepted"),
        Subsystem->TestOnly_TryPublish_SaveKeyWithoutDiagnostics(Key, FirstRoot));
    TestFalse(TEXT("second live authored publisher proves the identity collision"),
        Subsystem->TestOnly_TryPublish_SaveKeyWithoutDiagnostics(Key, CollidingRoot));

    const auto Retirement = Subsystem->Request_BeginSaveKeyRetirement(FirstRoot);
    TestFalse(TEXT("persistent removal refuses a colliding authored identity"),
        Retirement.IsValid());
    TestFalse(TEXT("collision refusal leaves every authored root unsuppressed"),
        Subsystem->TestOnly_Get_IsSaveKeySuppressed(Key));

    // Current code suppresses before noticing the collision. Restore local test state so this red
    // specification cannot contaminate another test sharing the same process.
    if (Retirement.IsValid())
    { Subsystem->Request_CancelSaveKeyRetirement(FirstRoot, Retirement); }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_LevelRootRetirementCancellationSurvivesSourceTeardown,
    "Ck.Snapshot.LevelRootRemoval.CancellationSurvivesSourceTeardown",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_LevelRootRetirementCancellationSurvivesSourceTeardown::RunTest(
    const FString& Parameters)
{
    auto EnttRegistry = ck::registry_table::EnttRegistryType{};
    const auto RegistryHandle = ck::registry_table::Allocate(&EnttRegistry);
    auto Registry = FCk_Registry{RegistryHandle};
    ON_SCOPE_EXIT { ck::registry_table::Free(RegistryHandle); };

    auto LevelRoot = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
    ck::save_key::AssignLevelPlaced(LevelRoot, TEXT("Ck.Spec.CancelAfterSourceTeardown"));

    auto* GameInstance = NewObject<UGameInstance>();
    TestNotNull(TEXT("snapshot subsystem outer is valid"), GameInstance);
    if (GameInstance == nullptr)
    { return false; }

    auto* Subsystem = NewObject<UCk_Snapshot_Subsystem_UE>(GameInstance);
    TestNotNull(TEXT("snapshot subsystem test instance is valid"), Subsystem);
    if (Subsystem == nullptr)
    { return false; }

    const auto Key = LevelRoot.Get<FFragment_SaveKey>().Get_Key();
    const auto Retirement = Subsystem->Request_BeginSaveKeyRetirement(LevelRoot);
    TestEqual(TEXT("retirement begins with the authored root's identity"), Retirement, Key);
    TestTrue(TEXT("pending retirement suppresses level reconstruction"),
        Subsystem->TestOnly_Get_IsSaveKeySuppressed(Key));

    UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(LevelRoot);
    LevelRoot.Add<ck::FTag_DestroyEntity_Teardown>();
    TestFalse(TEXT("source is unavailable before the outer operation cancels"),
        ck::IsValid(LevelRoot));

    AddExpectedError(TEXT("source entity is invalid"),
        EAutomationExpectedErrorFlags::Contains, -1);
    TestTrue(TEXT("opaque retirement authority can cancel after source teardown"),
        Subsystem->Request_CancelSaveKeyRetirement(LevelRoot, Retirement));
    TestFalse(TEXT("cancellation after source teardown restores level reconstruction"),
        Subsystem->TestOnly_Get_IsSaveKeySuppressed(Key));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_LevelRootLegacyRelocationCompatibility,
    "Ck.Snapshot.LevelRootRemoval.LegacyRelocationCompatibility",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_LevelRootLegacyRelocationCompatibility::RunTest(const FString& Parameters)
{
    auto EnttRegistry = ck::registry_table::EnttRegistryType{};
    const auto RegistryHandle = ck::registry_table::Allocate(&EnttRegistry);
    auto Registry = FCk_Registry{RegistryHandle};
    ON_SCOPE_EXIT { ck::registry_table::Free(RegistryHandle); };

    auto AuthoredSource = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
    auto PlacedDestination = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
    ck::save_key::AssignLevelPlaced(AuthoredSource, TEXT("Ck.Spec.LegacyFixtureRelocation"));

    auto* GameInstance = NewObject<UGameInstance>();
    auto* Subsystem = NewObject<UCk_Snapshot_Subsystem_UE>(GameInstance);
    TestNotNull(TEXT("snapshot subsystem test instance is valid"), Subsystem);
    if (Subsystem == nullptr)
    { return false; }

    const auto Key = AuthoredSource.Get<FFragment_SaveKey>().Get_Key();
    TestTrue(TEXT("authored source publishes before the legacy pickup"),
        Subsystem->TestOnly_TryPublish_SaveKeyWithoutDiagnostics(Key, AuthoredSource));

    const auto Relocation = Subsystem->Request_BeginSaveKeyRelocation(AuthoredSource);
    TestEqual(TEXT("legacy pickup token receives the authored root identity"), Relocation, Key);
    TestTrue(TEXT("unfinished legacy relocation suppresses the authored root"),
        Subsystem->TestOnly_Get_IsSaveKeySuppressed(Key));

    UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(AuthoredSource);
    AuthoredSource.Add<ck::FTag_DestroyEntity_Teardown>();
    TestFalse(TEXT("legacy source can disappear before placement completes"),
        ck::IsValid(AuthoredSource));

    TestTrue(TEXT("an old relocation token can complete onto the placed replacement"),
        Subsystem->Request_CompleteSaveKeyRelocation(PlacedDestination, Relocation));
    TestTrue(TEXT("replacement owns the original canonical key"),
        PlacedDestination.Has<FFragment_SaveKey>() &&
        PlacedDestination.Get<FFragment_SaveKey>().Get_Key() == Key);
    TestTrue(TEXT("replacement retains authored-root provenance"),
        PlacedDestination.Get<FFragment_SaveKey>().Get_IsLevelPlacedRoot());
    TestFalse(TEXT("completed relocation no longer suppresses the key"),
        Subsystem->TestOnly_Get_IsSaveKeySuppressed(Key));

    auto Resolved = FCk_Handle{};
    TestTrue(TEXT("canonical key resolves after legacy placement"),
        Subsystem->TryResolve_SaveKey(Key, Resolved));
    TestEqual(TEXT("canonical key resolves to the replacement"), Resolved, PlacedDestination);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_LevelRootCkEntitySpawnerRemovalTravelRoundTrip,
    "Ck.Snapshot.LevelRootRemoval.CkEntitySpawnerRemovalTravelRoundTrip",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_LevelRootCkEntitySpawnerRemovalTravelRoundTrip::RunTest(const FString& Parameters)
{
    using namespace ck_test_snapshot_level_root_removal_contract;

    AddExpectedErrorPlain(TEXT("Request_Load: rebuild stalled (no progress)"),
        EAutomationExpectedErrorFlags::Contains, -1);

    const auto ProbeClass = Resolve_LevelRootProbeClass();
    TestTrue(TEXT("fixture probe EntityScript resolves for travel injection"), ProbeClass != nullptr);
    if (ProbeClass == nullptr)
    { return false; }

    const auto State = MakeShared<FInjectedSpawnerState>();
    State->InjectionHandle = FWorldDelegates::OnPostWorldInitialization.AddLambda(
        [State, ProbeClass](UWorld* InWorld, const UWorld::InitializationValues) -> void
        {
            if (InWorld == nullptr || InWorld->WorldType != EWorldType::PIE ||
                UWorld::RemovePIEPrefix(InWorld->GetPackage()->GetName()) != EntryMap)
            { return; }

            auto SpawnParams = FActorSpawnParameters{};
            SpawnParams.Name = SpawnerProbeName;
            SpawnParams.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            auto* Spawner = InWorld->SpawnActor<ACk_EntitySpawner_UE>(
                ACk_EntitySpawner_UE::StaticClass(), FTransform::Identity, SpawnParams);
            if (Spawner == nullptr)
            {
                State->Failure = TEXT("world initialization could not inject the authored spawner probe");
                return;
            }

            // The linker sets this on a real serialized map actor. Installing the real spawner before BeginPlay
            // with that exact production discriminator lets each OpenLevel rebuild the same authored identity
            // without adding a binary map fixture solely for this C++ contract.
            Spawner->SetFlags(RF_WasLoaded);
            Spawner->EditorOnly_InitializeEntityScript(ProbeClass);

            const auto Identity = ck::save_key::Get_LevelPlacedIdentity(Spawner);
            const auto InjectedKey = FGuid::NewDeterministicGuid(Identity);
            if (Identity.IsEmpty() || NOT InjectedKey.IsValid())
            {
                State->Failure = TEXT("injected authored spawner produced no deterministic level identity");
                return;
            }
            if (State->ExpectedKey.IsValid() && State->ExpectedKey != InjectedKey)
            {
                State->Failure = TEXT("the same authored spawner name changed identity across OpenLevel travel");
                return;
            }

            State->ExpectedKey = InjectedKey;
            ++State->NumInjectedWorlds;
        });

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(SinglePIEClient, EntryMap));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(SinglePIEWorld, PIEReadyTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(60));

    // A failed asynchronous inventory grant cancels persistent removal. Loading that save must therefore
    // reconstruct the authored spawner entity exactly once.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            UGameplayStatics::DeleteGameInSlot(SpawnerCancelledSlot.ToString(), 0);
            UGameplayStatics::DeleteGameInSlot(SpawnerCommittedSlot.ToString(), 0);

            TestTrue(TEXT("initial PIE world received the authored spawner probe"),
                State->NumInjectedWorlds == 1 && State->Failure.IsEmpty());
            TestTrue(TEXT("authored spawner probe has a stable SaveKey"), State->ExpectedKey.IsValid());

            auto LevelRoot = Find_SaveKey(InServer, State->ExpectedKey);
            TestTrue(TEXT("authored spawner produced one live level-root entity before cancellation"),
                ck::IsValid(LevelRoot) && Count_SaveKeys(InServer, &State->ExpectedKey) == 1);
            if (ck::Is_NOT_Valid(LevelRoot))
            { return; }

            auto* Subsystem = Get_SnapshotSubsystem(InServer);
            TestNotNull(TEXT("snapshot subsystem is valid before cancelled spawner removal"), Subsystem);
            if (Subsystem == nullptr)
            { return; }

            const auto Retirement = Subsystem->Request_BeginSaveKeyRetirement(LevelRoot);
            TestEqual(TEXT("authored spawner pickup opens retirement"), Retirement, State->ExpectedKey);
            TestTrue(TEXT("failed pickup cancels authored spawner retirement"),
                Subsystem->Request_CancelSaveKeyRetirement(LevelRoot, Retirement));

            Subsystem->Request_Save(SpawnerCancelledSlot, FCk_Delegate_OnSaveComplete{});
            auto* CancelledSave = Load_SaveGame(SpawnerCancelledSlot);
            TestNotNull(TEXT("cancelled authored-spawner save loads"), CancelledSave);
            if (CancelledSave != nullptr)
            {
                TestFalse(TEXT("cancelled authored-spawner removal is not durable"),
                    CancelledSave->_HeaderV3.Get_SuppressedSaveKeys().Contains(State->ExpectedKey));
            }

            Subsystem->Request_Load(SpawnerCancelledSlot, FCk_Delegate_OnLoadComplete{});
            TestTrue(TEXT("cancelled authored-spawner load starts asynchronously"),
                Subsystem->Get_IsLoadInProgress());
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            const auto* Subsystem = Get_SnapshotSubsystem(Get_CurrentPIEWorld());
            return Subsystem != nullptr && NOT Subsystem->Get_IsLoadInProgress();
        }),
        60.0, TEXT("cancelled authored-spawner save to finish loading")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(60));

    // The cancelled load reconstructed the same level root. Retire that fresh copy, save, and load again;
    // durable suppression must remove the next world's authored copy before gameplay resumes.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            auto* InServer = Get_CurrentPIEWorld();
            if (InServer == nullptr)
            {
                AddError(TEXT("cancelled removal load has no current PIE world"));
                return true;
            }

            TestTrue(TEXT("cancelled removal rebuild injected the authored spawner again"),
                State->NumInjectedWorlds >= 2 && State->Failure.IsEmpty());
            TestEqual(TEXT("cancelled removal leaves exactly one authored spawner entity after load"),
                Count_SaveKeys(InServer, &State->ExpectedKey), 1);

            auto LevelRoot = Find_SaveKey(InServer, State->ExpectedKey);
            TestTrue(TEXT("reconstructed authored spawner root resolves for committed pickup"),
                ck::IsValid(LevelRoot));
            if (ck::Is_NOT_Valid(LevelRoot))
            { return true; }

            auto* Subsystem = Get_SnapshotSubsystem(InServer);
            TestNotNull(TEXT("snapshot subsystem is valid before committed spawner removal"), Subsystem);
            if (Subsystem == nullptr)
            { return true; }

            const auto Retirement = Subsystem->Request_BeginSaveKeyRetirement(LevelRoot);
            TestEqual(TEXT("successful authored-spawner pickup opens retirement"),
                Retirement, State->ExpectedKey);
            TestTrue(TEXT("successful authored-spawner pickup commits retirement"),
                Subsystem->Request_CommitSaveKeyRetirement(Retirement));
            UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(LevelRoot);
            return true;
        }), TEXT("cancelled authored-spawner removal reconstructs before committed removal")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(10));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            auto* InServer = Get_CurrentPIEWorld();
            if (InServer == nullptr)
            {
                AddError(TEXT("committed removal save has no current PIE world"));
                return true;
            }

            auto* Subsystem = Get_SnapshotSubsystem(InServer);
            TestNotNull(TEXT("snapshot subsystem survives committed spawner source teardown"), Subsystem);
            if (Subsystem == nullptr)
            { return true; }

            Subsystem->Request_Save(SpawnerCommittedSlot, FCk_Delegate_OnSaveComplete{});
            auto* CommittedSave = Load_SaveGame(SpawnerCommittedSlot);
            TestNotNull(TEXT("committed authored-spawner save loads"), CommittedSave);
            if (CommittedSave != nullptr)
            {
                TestTrue(TEXT("committed authored-spawner removal is durable"),
                    CommittedSave->_HeaderV3.Get_SuppressedSaveKeys().Contains(State->ExpectedKey));
            }

            Subsystem->Request_Load(SpawnerCommittedSlot, FCk_Delegate_OnLoadComplete{});
            TestTrue(TEXT("committed authored-spawner load starts asynchronously"),
                Subsystem->Get_IsLoadInProgress());
            return true;
        }), TEXT("committed authored-spawner removal saves and starts reload")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            const auto* Subsystem = Get_SnapshotSubsystem(Get_CurrentPIEWorld());
            return Subsystem != nullptr && NOT Subsystem->Get_IsLoadInProgress();
        }),
        60.0, TEXT("committed authored-spawner save to finish loading")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(60));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            ON_SCOPE_EXIT
            {
                UGameplayStatics::DeleteGameInSlot(SpawnerCancelledSlot.ToString(), 0);
                UGameplayStatics::DeleteGameInSlot(SpawnerCommittedSlot.ToString(), 0);
                Remove_SpawnerInjector(State);
            };

            auto* InServer = Get_CurrentPIEWorld();
            if (InServer == nullptr)
            {
                AddError(TEXT("committed removal load has no current PIE world"));
                return true;
            }

            TestTrue(TEXT("committed removal load injected the authored spawner a third time"),
                State->NumInjectedWorlds >= 3 && State->Failure.IsEmpty());
            TestEqual(TEXT("committed removal suppresses the fresh authored spawner entity after load"),
                Count_SaveKeys(InServer, &State->ExpectedKey), 0);

            auto* Subsystem = Get_SnapshotSubsystem(InServer);
            TestNotNull(TEXT("snapshot subsystem is valid after committed spawner removal load"), Subsystem);
            if (Subsystem != nullptr)
            {
                TestTrue(TEXT("committed authored-spawner suppression remains active after load"),
                    Subsystem->TestOnly_Get_IsSaveKeySuppressed(State->ExpectedKey));
            }
            return true;
        }), TEXT("committed authored-spawner removal suppresses the next level copy")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_LevelRootMutationSaveAtomicity,
    "Ck.Snapshot.LevelRootRemoval.MutationSaveAtomicity",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_LevelRootMutationSaveAtomicity::RunTest(const FString& Parameters)
{
    using namespace ck_test_snapshot_level_root_removal_contract;

    // Current Foundation refuses capture while a suppressed source is still live. A future implementation may
    // instead capture the pre-mutation state. Both are atomic provided the durable slot never contains the
    // uncommitted suppression, so accept either mechanism while pinning the durable outcome.
    AddExpectedError(TEXT("HasSuppressedSaveKey"), EAutomationExpectedErrorFlags::Contains, -1);
    AddExpectedError(TEXT("Failed Not Quiescent"), EAutomationExpectedErrorFlags::Contains, -1);

    const auto ExpectedKey = MakeShared<FGuid>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(SinglePIEClient, EntryMap));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(SinglePIEWorld, PIEReadyTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, ExpectedKey](UWorld* InServer) -> void
        {
            auto* Subsystem = Get_SnapshotSubsystem(InServer);
            TestNotNull(TEXT("live snapshot subsystem is valid"), Subsystem);
            if (Subsystem == nullptr)
            { return; }

            UGameplayStatics::DeleteGameInSlot(PendingMutationSlot.ToString(), 0);
            UGameplayStatics::DeleteGameInSlot(CancelledMutationSlot.ToString(), 0);
            UGameplayStatics::DeleteGameInSlot(CommittedMutationSlot.ToString(), 0);

            // Give the pending save a known-good predecessor. Refusal must leave this intact; an atomic
            // implementation that succeeds may replace it, but still must not persist uncommitted suppression.
            Subsystem->Request_Save(PendingMutationSlot, FCk_Delegate_OnSaveComplete{});

            const auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
            auto AuthoredRoot = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Transient);
            ck::save_key::AssignLevelPlaced(AuthoredRoot, TEXT("Ck.Spec.SaveDuringFixtureGrant"));
            const auto Key = AuthoredRoot.Get<FFragment_SaveKey>().Get_Key();
            *ExpectedKey = Key;

            const auto PendingRetirement = Subsystem->Request_BeginSaveKeyRetirement(AuthoredRoot);
            TestEqual(TEXT("fixture pickup opens a retirement transaction"), PendingRetirement, Key);
            Subsystem->Request_Save(PendingMutationSlot, FCk_Delegate_OnSaveComplete{});

            auto* PendingSave = Load_SaveGame(PendingMutationSlot);
            TestNotNull(TEXT("save taken during the pending inventory grant loads"), PendingSave);
            if (PendingSave != nullptr)
            {
                TestFalse(TEXT("uncommitted pickup suppression is never durable"),
                    PendingSave->_HeaderV3.Get_SuppressedSaveKeys().Contains(Key));
            }

            TestTrue(TEXT("failed inventory grant rolls the retirement back"),
                Subsystem->Request_CancelSaveKeyRetirement(AuthoredRoot, PendingRetirement));
            Subsystem->Request_Save(CancelledMutationSlot, FCk_Delegate_OnSaveComplete{});

            auto* CancelledSave = Load_SaveGame(CancelledMutationSlot);
            TestNotNull(TEXT("post-cancellation save loads"), CancelledSave);
            if (CancelledSave != nullptr)
            {
                TestFalse(TEXT("cancelled pickup remains reconstructible in the durable header"),
                    CancelledSave->_HeaderV3.Get_SuppressedSaveKeys().Contains(Key));
            }

            const auto CommittedRetirement = Subsystem->Request_BeginSaveKeyRetirement(AuthoredRoot);
            TestTrue(TEXT("successful inventory grant commits retirement"),
                Subsystem->Request_CommitSaveKeyRetirement(CommittedRetirement));
            UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(AuthoredRoot);
        })));

    // Match the real fixture task: commit, request entity destruction, then let teardown drain before saving.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(10));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, ExpectedKey](UWorld* InServer) -> void
        {
            ON_SCOPE_EXIT
            {
                UGameplayStatics::DeleteGameInSlot(PendingMutationSlot.ToString(), 0);
                UGameplayStatics::DeleteGameInSlot(CancelledMutationSlot.ToString(), 0);
                UGameplayStatics::DeleteGameInSlot(CommittedMutationSlot.ToString(), 0);
            };

            auto* Subsystem = Get_SnapshotSubsystem(InServer);
            TestNotNull(TEXT("live snapshot subsystem remains valid after source teardown"), Subsystem);
            if (Subsystem == nullptr || NOT ExpectedKey->IsValid())
            { return; }

            Subsystem->Request_Save(CommittedMutationSlot, FCk_Delegate_OnSaveComplete{});
            auto* CommittedSave = Load_SaveGame(CommittedMutationSlot);
            TestNotNull(TEXT("post-commit save loads"), CommittedSave);
            if (CommittedSave != nullptr)
            {
                TestTrue(TEXT("committed pickup suppression is durable"),
                    CommittedSave->_HeaderV3.Get_SuppressedSaveKeys().Contains(*ExpectedKey));
            }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_LevelRootRemovalAuthorityBoundary,
    "Ck.Snapshot.LevelRootRemoval.AuthorityBoundary",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_LevelRootRemovalAuthorityBoundary::RunTest(const FString& Parameters)
{
    using namespace ck_test_snapshot_level_root_removal_contract;

    AddExpectedError(TEXT("authority"), EAutomationExpectedErrorFlags::Contains, -1);

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(MultiPIEClients, EntryMap));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(
        ListenServerAndClientWorlds, PIEReadyTimeoutSeconds));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InClient) -> void
        {
            auto* Subsystem = Get_SnapshotSubsystem(InClient);
            TestNotNull(TEXT("client snapshot subsystem is valid"), Subsystem);
            if (Subsystem == nullptr)
            { return; }

            const auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InClient);
            auto ClientRoot = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Transient);
            ck::save_key::AssignLevelPlaced(ClientRoot, TEXT("Ck.Spec.ClientCannotRetireLevelRoot"));

            const auto ClientRetirement = Subsystem->Request_BeginSaveKeyRetirement(ClientRoot);
            TestFalse(TEXT("non-authoritative client cannot create durable world suppression"),
                ClientRetirement.IsValid());

            // Current production accepts this request, which is the intended red. Keep that failure local to
            // this client world so the remainder of the suite does not inherit suppression state.
            if (ClientRetirement.IsValid())
            { Subsystem->Request_CancelSaveKeyRetirement(ClientRoot, ClientRetirement); }
            UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(ClientRoot);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Subsystem = Get_SnapshotSubsystem(InServer);
            TestNotNull(TEXT("server snapshot subsystem is valid"), Subsystem);
            if (Subsystem == nullptr)
            { return; }

            const auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
            auto ServerRoot = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Transient);
            ck::save_key::AssignLevelPlaced(ServerRoot, TEXT("Ck.Spec.ServerCanRetireLevelRoot"));

            const auto ServerRetirement = Subsystem->Request_BeginSaveKeyRetirement(ServerRoot);
            TestTrue(TEXT("authoritative server can open the persistent-removal transaction"),
                ServerRetirement.IsValid());
            if (ServerRetirement.IsValid())
            { Subsystem->Request_CancelSaveKeyRetirement(ServerRoot, ServerRetirement); }
            UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(ServerRoot);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_LevelRootRemovalRejectsNonAuthoredOrigins,
    "Ck.Snapshot.LevelRootRemoval.RejectsNonAuthoredOrigins",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_LevelRootRemovalRejectsNonAuthoredOrigins::RunTest(const FString& Parameters)
{
    auto EnttRegistry = ck::registry_table::EnttRegistryType{};
    const auto RegistryHandle = ck::registry_table::Allocate(&EnttRegistry);
    auto Registry = FCk_Registry{RegistryHandle};
    ON_SCOPE_EXIT { ck::registry_table::Free(RegistryHandle); };

    auto UnkeyedRoot = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
    auto StableRuntimeRoot = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
    auto SharedInfrastructureRoot = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
    ck::save_key::Assign(StableRuntimeRoot, TEXT("Ck.Spec.StableRuntimeRoot"));
    ck::save_key::AssignSharedRendezvousGroup(
        SharedInfrastructureRoot, TEXT("Ck.Spec.SharedInfrastructureRoot"));

    auto* GameInstance = NewObject<UGameInstance>();
    TestNotNull(TEXT("snapshot subsystem outer is valid"), GameInstance);
    if (GameInstance == nullptr)
    { return false; }

    auto* Subsystem = NewObject<UCk_Snapshot_Subsystem_UE>(GameInstance);
    TestNotNull(TEXT("snapshot subsystem test instance is valid"), Subsystem);
    if (Subsystem == nullptr)
    { return false; }

    // Refusal is the result under test. Allow the associated diagnostics to exist or disappear
    // without making their wording/count the behavioral contract.
    AddExpectedError(TEXT("has no save identity"), EAutomationExpectedErrorFlags::Contains, -1);
    AddExpectedError(TEXT("was not created from a level-authored root"),
        EAutomationExpectedErrorFlags::Contains, -1);
    AddExpectedError(TEXT("uses a shared infrastructure SaveKey"),
        EAutomationExpectedErrorFlags::Contains, -1);

    TestFalse(TEXT("unkeyed runtime root cannot retire an authored level identity"),
        Subsystem->Request_BeginSaveKeyRetirement(UnkeyedRoot).IsValid());
    TestFalse(TEXT("generic stable rendezvous identity is not persistent-removal authority"),
        Subsystem->Request_BeginSaveKeyRetirement(StableRuntimeRoot).IsValid());
    TestFalse(TEXT("shared infrastructure identity cannot be retired as one authored root"),
        Subsystem->Request_BeginSaveKeyRetirement(SharedInfrastructureRoot).IsValid());

    TestFalse(TEXT("generic stable identity remains unsuppressed after refusal"),
        Subsystem->TestOnly_Get_IsSaveKeySuppressed(
            StableRuntimeRoot.Get<FFragment_SaveKey>().Get_Key()));
    TestFalse(TEXT("shared infrastructure identity remains unsuppressed after refusal"),
        Subsystem->TestOnly_Get_IsSaveKeySuppressed(
            SharedInfrastructureRoot.Get<FFragment_SaveKey>().Get_Key()));

    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
