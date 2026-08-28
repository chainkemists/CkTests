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
#include "CkSnapshot/Persistence/CkSnapshot_PersistentEntityMutation.h"
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
    const auto StaleWorldMutationSlot = FName{TEXT("Ck_LevelRootRemoval_StaleWorld")};
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
    using namespace ck_test_snapshot_level_root_removal_contract;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(SinglePIEClient, EntryMap));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(SinglePIEWorld, PIEReadyTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            const auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
            auto FirstRoot = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Transient);
            auto CollidingRoot = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Transient);
            ck::save_key::AssignLevelPlaced(FirstRoot, TEXT("Ck.Spec.DuplicateLevelRoot"));
            ck::save_key::AssignLevelPlaced(CollidingRoot, TEXT("Ck.Spec.DuplicateLevelRoot"));

            auto* Subsystem = Get_SnapshotSubsystem(InServer);
            TestNotNull(TEXT("snapshot subsystem is valid"), Subsystem);
            if (Subsystem == nullptr)
            { return; }

            const auto Ticket = Subsystem->Request_BeginEntityRemoval(FirstRoot);
            TestEqual(TEXT("duplicate live authored publisher fails closed before suppression"),
                Ticket.Get_BeginResult(), ECk_PersistentEntityMutationResult::Failed_DuplicateLivePublisher);
            TestFalse(TEXT("duplicate refusal leaves the authored identity unsuppressed"),
                Subsystem->TestOnly_Get_IsSaveKeySuppressed(FirstRoot.Get<FFragment_SaveKey>().Get_Key()));
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

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
    using namespace ck_test_snapshot_level_root_removal_contract;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(SinglePIEClient, EntryMap));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(SinglePIEWorld, PIEReadyTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            const auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
            auto LevelRoot = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Transient);
            ck::save_key::AssignLevelPlaced(LevelRoot, TEXT("Ck.Spec.CancelAfterSourceTeardown"));
            const auto Key = LevelRoot.Get<FFragment_SaveKey>().Get_Key();

            auto* Subsystem = Get_SnapshotSubsystem(InServer);
            TestNotNull(TEXT("snapshot subsystem is valid"), Subsystem);
            if (Subsystem == nullptr)
            { return; }

            const auto Ticket = Subsystem->Request_BeginEntityRemoval(LevelRoot);
            TestEqual(TEXT("authored removal begins"), Ticket.Get_BeginResult(),
                ECk_PersistentEntityMutationResult::Succeeded);
            TestFalse(TEXT("beginning removal is runtime-only and does not suppress reconstruction"),
                Subsystem->TestOnly_Get_IsSaveKeySuppressed(Key));

            LevelRoot.Add<ck::FTag_DestroyEntity_Teardown>();
            TestFalse(TEXT("source is unavailable before cancellation"), ck::IsValid(LevelRoot));
            TestEqual(TEXT("ticket cancellation survives source teardown"),
                Subsystem->Request_CancelPersistentMutation(Ticket),
                ECk_PersistentEntityMutationResult::Succeeded);
            TestFalse(TEXT("cancellation restores reconstruction"),
                Subsystem->TestOnly_Get_IsSaveKeySuppressed(Key));

            auto DeterministicRoot = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Transient);
            auto LatePublisher = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Transient);
            ck::save_key::AssignLevelPlaced(DeterministicRoot, TEXT("Ck.Spec.DeterministicRemovalCommit"));
            ck::save_key::AssignLevelPlaced(LatePublisher, TEXT("Ck.Spec.DeterministicRemovalCommit"));
            const auto DeterministicKey = DeterministicRoot.Get<FFragment_SaveKey>().Get_Key();

            // Remove the deliberate duplicate before begin, then prove the reservation prevents it from
            // publishing while an external inventory grant is in flight.
            LatePublisher.Remove<FFragment_SaveKey>();
            const auto DeterministicTicket = Subsystem->Request_BeginEntityRemoval(DeterministicRoot);
            TestEqual(TEXT("deterministic removal reserves its authored identity"),
                DeterministicTicket.Get_BeginResult(), ECk_PersistentEntityMutationResult::Succeeded);
            ck::save_key::AssignLevelPlaced(LatePublisher, TEXT("Ck.Spec.DeterministicRemovalCommit"));
            TestFalse(TEXT("a pending removal rejects a late publisher for its reserved identity"),
                Subsystem->TestOnly_TryPublish_SaveKeyWithoutDiagnostics(DeterministicKey, LatePublisher));
            TestEqual(TEXT("successful begin makes same-world authority removal commit deterministic"),
                Subsystem->Request_CommitEntityRemoval(DeterministicTicket),
                ECk_PersistentEntityMutationResult::Succeeded);
            TestTrue(TEXT("deterministic commit durably suppresses the reserved authored identity"),
                Subsystem->TestOnly_Get_IsSaveKeySuppressed(DeterministicKey));
            UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(LatePublisher);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_LevelRootLegacyRelocationCompatibility,
    "Ck.Snapshot.LevelRootRemoval.LegacyRelocationCompatibility",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_LevelRootLegacyRelocationCompatibility::RunTest(const FString& Parameters)
{
    using namespace ck_test_snapshot_level_root_removal_contract;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(SinglePIEClient, EntryMap));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(SinglePIEWorld, PIEReadyTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            const auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
            auto LegacySource = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Transient);
            auto LegacyDestination = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Transient);
            auto SemanticSource = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Transient);
            auto SemanticDestination = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Transient);
            auto SecondSemanticDestination = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Transient);
            ck::save_key::AssignLevelPlaced(LegacySource, TEXT("Ck.Spec.LegacyFixtureRelocation"));
            ck::save_key::AssignLevelPlaced(SemanticSource, TEXT("Ck.Spec.SemanticFixtureRelocation"));
            const auto LegacyKey = LegacySource.Get<FFragment_SaveKey>().Get_Key();

            auto* Subsystem = Get_SnapshotSubsystem(InServer);
            TestNotNull(TEXT("snapshot subsystem is valid"), Subsystem);
            if (Subsystem == nullptr)
            { return; }

            const auto LegacyRemoval = Subsystem->Request_BeginEntityRemoval(LegacySource);
            TestEqual(TEXT("legacy source removal begins"), LegacyRemoval.Get_BeginResult(),
                ECk_PersistentEntityMutationResult::Succeeded);
            TestEqual(TEXT("legacy source removal commits its durable suppression"),
                Subsystem->Request_CommitEntityRemoval(LegacyRemoval),
                ECk_PersistentEntityMutationResult::Succeeded);
            TestTrue(TEXT("committed historical removal supplies the legacy suppression"),
                Subsystem->TestOnly_Get_IsSaveKeySuppressed(LegacyKey));

            const auto LegacyDestinationReservation =
                Subsystem->Request_BeginEntityRemoval(LegacyDestination);
            TestEqual(TEXT("legacy relocation destination can be reserved as another mutation source"),
                LegacyDestinationReservation.Get_BeginResult(),
                ECk_PersistentEntityMutationResult::Succeeded);
            TestEqual(TEXT("legacy relocation rejects a destination reserved by another operation"),
                Subsystem->Request_CompleteLegacySaveKeyRelocation(LegacyDestination, LegacyKey),
                ECk_PersistentEntityMutationResult::Failed_DestinationAlreadyReserved);
            TestEqual(TEXT("legacy relocation destination reservation cancels cleanly"),
                Subsystem->Request_CancelPersistentMutation(LegacyDestinationReservation),
                ECk_PersistentEntityMutationResult::Succeeded);
            TestEqual(TEXT("legacy SaveKey relocation consumes the historical suppression"),
                Subsystem->Request_CompleteLegacySaveKeyRelocation(LegacyDestination, LegacyKey),
                ECk_PersistentEntityMutationResult::Succeeded);
            TestTrue(TEXT("legacy replacement owns the original canonical key"),
                LegacyDestination.Has<FFragment_SaveKey>() &&
                LegacyDestination.Get<FFragment_SaveKey>().Get_Key() == LegacyKey);
            TestFalse(TEXT("legacy completion clears the historical suppression"),
                Subsystem->TestOnly_Get_IsSaveKeySuppressed(LegacyKey));

            const auto Relocation = Subsystem->Request_BeginPersistentRelocation(SemanticSource);
            TestEqual(TEXT("persistent relocation begins for the authored source"),
                Relocation.Get_BeginResult(), ECk_PersistentEntityMutationResult::Succeeded);
            TestEqual(TEXT("removal completion rejects a relocation ticket"),
                Subsystem->Request_CommitEntityRemoval(Relocation),
                ECk_PersistentEntityMutationResult::Failed_WrongOperationKind);
            TestEqual(TEXT("default ticket is invalid"),
                Subsystem->Request_CancelPersistentMutation(FCk_PersistentEntityMutationTicket{}),
                ECk_PersistentEntityMutationResult::Failed_InvalidTicket);

            const auto SemanticDestinationReservation =
                Subsystem->Request_BeginEntityRemoval(SemanticDestination);
            TestEqual(TEXT("semantic relocation destination can be reserved as another mutation source"),
                SemanticDestinationReservation.Get_BeginResult(),
                ECk_PersistentEntityMutationResult::Succeeded);
            TestEqual(TEXT("semantic relocation rejects a destination reserved by another operation"),
                Subsystem->Request_CompletePersistentRelocation(SemanticDestination, Relocation),
                ECk_PersistentEntityMutationResult::Failed_DestinationAlreadyReserved);
            TestEqual(TEXT("semantic relocation destination reservation cancels cleanly"),
                Subsystem->Request_CancelPersistentMutation(SemanticDestinationReservation),
                ECk_PersistentEntityMutationResult::Succeeded);
            TestEqual(TEXT("semantic relocation completes onto its replacement"),
                Subsystem->Request_CompletePersistentRelocation(SemanticDestination, Relocation),
                ECk_PersistentEntityMutationResult::Succeeded);
            TestTrue(TEXT("semantic replacement retains authored-root provenance"),
                SemanticDestination.Has<FFragment_SaveKey>() &&
                SemanticDestination.Get<FFragment_SaveKey>().Get_IsLevelPlacedRoot());
            TestEqual(TEXT("a terminal relocation ticket cannot complete twice"),
                Subsystem->Request_CompletePersistentRelocation(SecondSemanticDestination, Relocation),
                ECk_PersistentEntityMutationResult::Failed_AlreadyTerminal);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

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

            const auto Retirement = Subsystem->Request_BeginEntityRemoval(LevelRoot);
            TestEqual(TEXT("authored spawner pickup opens removal"), Retirement.Get_BeginResult(),
                ECk_PersistentEntityMutationResult::Succeeded);
            TestTrue(TEXT("failed pickup cancels authored spawner retirement"),
                Subsystem->Request_CancelPersistentMutation(Retirement) ==
                    ECk_PersistentEntityMutationResult::Succeeded);

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
            TestEqual(TEXT("persistent removal refuses while the snapshot load is active"),
                Subsystem->Request_BeginEntityRemoval(LevelRoot).Get_BeginResult(),
                ECk_PersistentEntityMutationResult::Failed_SnapshotBusy);
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

            const auto Retirement = Subsystem->Request_BeginEntityRemoval(LevelRoot);
            TestEqual(TEXT("successful authored-spawner pickup opens removal"),
                Retirement.Get_BeginResult(), ECk_PersistentEntityMutationResult::Succeeded);
            TestTrue(TEXT("successful authored-spawner pickup commits retirement"),
                Subsystem->Request_CommitEntityRemoval(Retirement) ==
                    ECk_PersistentEntityMutationResult::Succeeded);
            TestFalse(TEXT("terminal spawner removal leaves no live source SaveKey"),
                LevelRoot.Has<FFragment_SaveKey>());
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

            // Give the pending save a known-good predecessor. A pending mutation must leave these bytes intact.
            Subsystem->Request_Save(PendingMutationSlot, FCk_Delegate_OnSaveComplete{});
            auto PreMutationBytes = TArray<uint8>{};
            TestTrue(TEXT("pending-mutation slot captures its predecessor bytes"),
                UGameplayStatics::LoadDataFromSlot(PreMutationBytes, PendingMutationSlot.ToString(), 0));

            const auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
            auto AuthoredRoot = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Transient);
            ck::save_key::AssignLevelPlaced(AuthoredRoot, TEXT("Ck.Spec.SaveDuringFixtureGrant"));
            const auto Key = AuthoredRoot.Get<FFragment_SaveKey>().Get_Key();
            *ExpectedKey = Key;

            const auto PendingRetirement = Subsystem->Request_BeginEntityRemoval(AuthoredRoot);
            TestEqual(TEXT("fixture pickup opens a removal transaction"), PendingRetirement.Get_BeginResult(),
                ECk_PersistentEntityMutationResult::Succeeded);

            Subsystem->Request_Load(PendingMutationSlot, FCk_Delegate_OnLoadComplete{});
            TestFalse(TEXT("pending mutation blocks load before world teardown begins"),
                Subsystem->Get_IsLoadInProgress());
            TestEqual(TEXT("blocked load updates the pull completion report"),
                Subsystem->Get_LastLoadReport().Get_Result(),
                ECk_SnapshotResult::Failed_NotQuiescent);
            TestTrue(TEXT("blocked load leaves the reserved source live with its authored identity"),
                ck::IsValid(AuthoredRoot) && AuthoredRoot.Has<FFragment_SaveKey>() &&
                AuthoredRoot.Get<FFragment_SaveKey>().Get_Key() == Key);

            Subsystem->Request_Save(PendingMutationSlot, FCk_Delegate_OnSaveComplete{});
            TestEqual(TEXT("blocked save updates the pull completion report"),
                Subsystem->Get_LastSaveReport().Get_Result(),
                ECk_SnapshotResult::Failed_NotQuiescent);

            auto PendingMutationBytes = TArray<uint8>{};
            TestTrue(TEXT("pending-mutation slot remains readable"),
                UGameplayStatics::LoadDataFromSlot(PendingMutationBytes, PendingMutationSlot.ToString(), 0));
            TestTrue(TEXT("pending mutation blocks save without overwriting its predecessor bytes"),
                PendingMutationBytes == PreMutationBytes);

            auto* PendingSave = Load_SaveGame(PendingMutationSlot);
            TestNotNull(TEXT("save taken during the pending inventory grant loads"), PendingSave);
            if (PendingSave != nullptr)
            {
                TestFalse(TEXT("pending mutation blocks overwrite and leaves the predecessor durable"),
                    PendingSave->_HeaderV3.Get_SuppressedSaveKeys().Contains(Key));
            }

            TestTrue(TEXT("failed inventory grant rolls the retirement back"),
                Subsystem->Request_CancelPersistentMutation(PendingRetirement) ==
                    ECk_PersistentEntityMutationResult::Succeeded);
            Subsystem->Request_Save(CancelledMutationSlot, FCk_Delegate_OnSaveComplete{});

            auto* CancelledSave = Load_SaveGame(CancelledMutationSlot);
            TestNotNull(TEXT("post-cancellation save loads"), CancelledSave);
            if (CancelledSave != nullptr)
            {
                TestFalse(TEXT("cancelled pickup remains reconstructible in the durable header"),
                    CancelledSave->_HeaderV3.Get_SuppressedSaveKeys().Contains(Key));
            }

            const auto CommittedRetirement = Subsystem->Request_BeginEntityRemoval(AuthoredRoot);
            TestEqual(TEXT("successful inventory grant begins removal"),
                CommittedRetirement.Get_BeginResult(), ECk_PersistentEntityMutationResult::Succeeded);
            TestEqual(TEXT("successful inventory grant commits removal"),
                Subsystem->Request_CommitEntityRemoval(CommittedRetirement),
                ECk_PersistentEntityMutationResult::Succeeded);
            TestFalse(TEXT("terminal removal leaves no live source SaveKey before the next tick"),
                AuthoredRoot.Has<FFragment_SaveKey>());

            Subsystem->Request_Save(CommittedMutationSlot, FCk_Delegate_OnSaveComplete{});
            auto* SameFrameCommittedSave = Load_SaveGame(CommittedMutationSlot);
            TestNotNull(TEXT("same-frame terminal save loads"), SameFrameCommittedSave);
            if (SameFrameCommittedSave != nullptr)
            {
                TestTrue(TEXT("same-frame terminal save persists suppression without a duplicate source"),
                    SameFrameCommittedSave->_HeaderV3.Get_SuppressedSaveKeys().Contains(Key));
            }
        })));

    // Let the terminal request's deferred teardown drain before the final durable-read assertion.
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
    FCkSnapshot_LevelRootPendingMutationDoesNotSurviveWorldTravel,
    "Ck.Snapshot.LevelRootRemoval.PendingMutationDoesNotSurviveWorldTravel",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_LevelRootPendingMutationDoesNotSurviveWorldTravel::RunTest(const FString& Parameters)
{
    using namespace ck_test_snapshot_level_root_removal_contract;

    const auto PreTravelWorld = MakeShared<TWeakObjectPtr<UWorld>>();
    const auto StaleTicket = MakeShared<FCk_PersistentEntityMutationTicket>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(SinglePIEClient, EntryMap));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(SinglePIEWorld, PIEReadyTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda(
            [this, PreTravelWorld, StaleTicket](UWorld* InServer) -> void
            {
                auto* Subsystem = Get_SnapshotSubsystem(InServer);
                TestNotNull(TEXT("pre-travel snapshot subsystem is valid"), Subsystem);
                if (Subsystem == nullptr)
                { return; }

                auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
                auto Source = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Transient);
                *StaleTicket = Subsystem->Request_BeginEntityRemoval(Source);
                TestEqual(TEXT("pre-travel mutation begins"), StaleTicket->Get_BeginResult(),
                    ECk_PersistentEntityMutationResult::Succeeded);

                *PreTravelWorld = InServer;
                const auto MapName = InServer->RemovePIEPrefix(InServer->GetOutermost()->GetName());
                constexpr auto AbsoluteTravel = true;
                UGameplayStatics::OpenLevel(InServer, FName{*MapName}, AbsoluteTravel);
            })));

    // OpenLevel leaves the single-client PIE world in NM_Standalone, so the net harness can no
    // longer find it as a server. Let travel settle, then address the replacement PIE world directly.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(150));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, PreTravelWorld, StaleTicket]() -> bool
        {
            auto* Current = Get_CurrentPIEWorld();
            if (Current == nullptr || Current == PreTravelWorld->Get() || Current->HasBegunPlay() == false)
            { AddError(TEXT("ordinary travel did not produce a ready replacement PIE world")); return false; }

            auto* Subsystem = Get_SnapshotSubsystem(Current);
            TestNotNull(TEXT("post-travel snapshot subsystem is valid"), Subsystem);
            if (Subsystem == nullptr)
            { return false; }

            UGameplayStatics::DeleteGameInSlot(StaleWorldMutationSlot.ToString(), 0);
            Subsystem->Request_Save(StaleWorldMutationSlot, FCk_Delegate_OnSaveComplete{});
            TestEqual(TEXT("post-travel save prunes the abandoned old-world mutation"),
                Subsystem->Get_LastSaveReport().Get_Result(), ECk_SnapshotResult::Success);
            TestTrue(TEXT("post-travel save writes a readable slot"),
                UGameplayStatics::DoesSaveGameExist(StaleWorldMutationSlot.ToString(), 0));
            TestEqual(TEXT("pruned old-world ticket has deterministic terminal status"),
                Subsystem->Request_CancelPersistentMutation(*StaleTicket),
                ECk_PersistentEntityMutationResult::Failed_AlreadyTerminal);
            UGameplayStatics::DeleteGameInSlot(StaleWorldMutationSlot.ToString(), 0);
            return true;
        }), TEXT("ordinary travel prunes abandoned persistent mutations before the next save")));
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

    const auto ServerTicket = MakeShared<FCk_PersistentEntityMutationTicket>();
    const auto ServerRoot = MakeShared<FCk_Handle>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(MultiPIEClients, EntryMap));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(
        ListenServerAndClientWorlds, PIEReadyTimeoutSeconds));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, ServerTicket, ServerRoot](UWorld* InServer) -> void
        {
            auto* Subsystem = Get_SnapshotSubsystem(InServer);
            TestNotNull(TEXT("server snapshot subsystem is valid"), Subsystem);
            if (Subsystem == nullptr)
            { return; }

            const auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
            *ServerRoot = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Transient);
            ck::save_key::AssignLevelPlaced(*ServerRoot, TEXT("Ck.Spec.ServerCanRetireLevelRoot"));

            *ServerTicket = Subsystem->Request_BeginEntityRemoval(*ServerRoot);
            TestEqual(TEXT("authoritative server can open the persistent-removal transaction"),
                ServerTicket->Get_BeginResult(), ECk_PersistentEntityMutationResult::Succeeded);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
        FCk_NetAutoTest_ServerAction::CreateLambda([this, ServerTicket](UWorld* InClient) -> void
        {
            auto* Subsystem = Get_SnapshotSubsystem(InClient);
            TestNotNull(TEXT("client snapshot subsystem is valid"), Subsystem);
            if (Subsystem == nullptr)
            { return; }

            const auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InClient);
            auto ClientRoot = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Transient);
            ck::save_key::AssignLevelPlaced(ClientRoot, TEXT("Ck.Spec.ClientCannotRetireLevelRoot"));

            const auto ClientRetirement = Subsystem->Request_BeginEntityRemoval(ClientRoot);
            TestEqual(TEXT("non-authoritative client cannot create durable world suppression"),
                ClientRetirement.Get_BeginResult(), ECk_PersistentEntityMutationResult::Failed_NotAuthority);
            TestEqual(TEXT("a ticket cannot be committed through another world's subsystem"),
                Subsystem->Request_CommitEntityRemoval(*ServerTicket),
                ECk_PersistentEntityMutationResult::Failed_WrongWorld);
            UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(ClientRoot);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, ServerTicket, ServerRoot](UWorld* InServer) -> void
        {
            auto* Subsystem = Get_SnapshotSubsystem(InServer);
            TestNotNull(TEXT("server snapshot subsystem remains valid"), Subsystem);
            if (Subsystem == nullptr)
            { return; }

            TestEqual(TEXT("server cancellation closes the transaction"),
                Subsystem->Request_CancelPersistentMutation(*ServerTicket),
                ECk_PersistentEntityMutationResult::Succeeded);
            UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(*ServerRoot);
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
    using namespace ck_test_snapshot_level_root_removal_contract;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(SinglePIEClient, EntryMap));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(SinglePIEWorld, PIEReadyTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            const auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
            auto UnkeyedRoot = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Transient);
            auto StableRuntimeRoot = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Transient);
            auto SharedInfrastructureRoot = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Transient);
            ck::save_key::Assign(StableRuntimeRoot, TEXT("Ck.Spec.StableRuntimeRoot"));
            ck::save_key::AssignSharedRendezvousGroup(
                SharedInfrastructureRoot, TEXT("Ck.Spec.SharedInfrastructureRoot"));

            auto* Subsystem = Get_SnapshotSubsystem(InServer);
            TestNotNull(TEXT("snapshot subsystem is valid"), Subsystem);
            if (Subsystem == nullptr)
            { return; }

            TestFalse(TEXT("unkeyed runtime source has no durable identity to suppress"),
                UnkeyedRoot.Has<FFragment_SaveKey>());
            TestEqual(TEXT("unkeyed runtime destruction succeeds without durable suppression"),
                Subsystem->Request_DestroyEntityPersistently(UnkeyedRoot),
                ECk_PersistentEntityMutationResult::Succeeded);
            TestEqual(TEXT("generic stable rendezvous identity is not removal authority"),
                Subsystem->Request_BeginEntityRemoval(StableRuntimeRoot).Get_BeginResult(),
                ECk_PersistentEntityMutationResult::Failed_KeyedNonAuthoredSource);
            TestEqual(TEXT("shared infrastructure identity is not removal authority"),
                Subsystem->Request_BeginEntityRemoval(SharedInfrastructureRoot).Get_BeginResult(),
                ECk_PersistentEntityMutationResult::Failed_SharedSaveKeySource);
            TestFalse(TEXT("generic stable identity remains unsuppressed after refusal"),
                Subsystem->TestOnly_Get_IsSaveKeySuppressed(
                    StableRuntimeRoot.Get<FFragment_SaveKey>().Get_Key()));
            TestFalse(TEXT("shared infrastructure identity remains unsuppressed after refusal"),
                Subsystem->TestOnly_Get_IsSaveKeySuppressed(
                    SharedInfrastructureRoot.Get<FFragment_SaveKey>().Get_Key()));

            auto OldestTerminalTicket = FCk_PersistentEntityMutationTicket{};
            auto NewestTerminalTicket = FCk_PersistentEntityMutationTicket{};
            for (auto Index = 0; Index < 257; ++Index)
            {
                auto ChurnRoot = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Transient);
                const auto ChurnTicket = Subsystem->Request_BeginEntityRemoval(ChurnRoot);
                if (Index == 0)
                { OldestTerminalTicket = ChurnTicket; }
                if (Index == 256)
                { NewestTerminalTicket = ChurnTicket; }
                if (ChurnTicket.Get_BeginResult() != ECk_PersistentEntityMutationResult::Succeeded ||
                    Subsystem->Request_CancelPersistentMutation(ChurnTicket) !=
                        ECk_PersistentEntityMutationResult::Succeeded)
                {
                    AddError(FString::Printf(
                        TEXT("terminal-history churn failed at operation [%d]"), Index));
                    break;
                }
                UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(ChurnRoot);
            }
            TestEqual(TEXT("terminal idempotence history is bounded"),
                Subsystem->TestOnly_Get_NumRememberedTerminalPersistentMutations(), 256);
            TestEqual(TEXT("oldest evicted terminal ticket becomes stale"),
                Subsystem->Request_CancelPersistentMutation(OldestTerminalTicket),
                ECk_PersistentEntityMutationResult::Failed_StaleTicket);
            TestEqual(TEXT("newest terminal ticket retains deterministic idempotence"),
                Subsystem->Request_CancelPersistentMutation(NewestTerminalTicket),
                ECk_PersistentEntityMutationResult::Failed_AlreadyTerminal);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
