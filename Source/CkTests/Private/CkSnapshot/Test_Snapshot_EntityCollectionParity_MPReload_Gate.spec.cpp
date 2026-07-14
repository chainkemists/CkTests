// CkSnapshot EntityCollection-Parity GATE — a Construct-composed EntityCollection's runtime MEMBERSHIP survives a
// listen-server SEAMLESS ServerTravel reload, asserted on the SERVER (authority). Like the Timer gate the assertions
// are server-side: the net Apply only stamps the ClientOnly SyncReplication fragment, so the restored membership is
// re-driven by the AUTHORITY-side HydrationApply; client convergence rides the ordinary re-armed replication path and
// is covered by the Ck.EntityCollection.Net.* gates, not re-asserted here.
//
// WHAT IT PROVES: the owner probe's Construct composes ONE replicated, EMPTY collection (tag EntityCollection.AutoTest_Net)
// on its own bridged entity. Pre-save the server runtime-Adds TWO members to it — the owner's OWN entity plus a SEPARATE
// persisted bridged member (an M2bProbe_Replicated). Both are RuntimeSpawned/respawnable, so both round-trip as saved
// entity ids and re-resolve on load. After save -> seamless reload -> load the restored collection must show NumEntities == 2
// (NOT the empty Construct default, and NOT a merged/inflated set), and every member handle must re-resolve to a live
// bridged entity — proving Produce mirrored the Replicate build, the nested array-of-structs-of-handles payload remapped,
// and HydrationApply re-drove the membership authority-side. Cross-entity round-trip (the separate member, not just self)
// is the point of using two members.
// Surface in Session Frontend: Ck.Snapshot.Parity.EntityCollection_MPReload

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/GameInstance.h"
#include "EngineUtils.h"               // TActorIterator
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel

#include "CkEntityCollection/CkEntityCollection_Utils.h"
#include "CkEntityCollection/CkEntityCollection_Fragment_Data.h" // FCk_Handle_EntityCollection, FCk_Request_EntityCollection_AddEntities

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/CkTests_Fragment_Data.h" // TAG_EntityCollection_AutoTest_Net
#include "CkTests/Net/CkAutoTest_NetSubject_EntityCollection.h"
#include "CkTests/Net/CkAutoTest_NetSubject_M2bProbe_Replicated.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

namespace
{
    constexpr auto EcParity_MapPath   = TEXT("/Engine/Maps/Entry");
    const auto     EcParity_SlotName  = FName{TEXT("CkSnapshot_EntityCollectionParity_GateSlot")};
    const auto     EcParity_OwnerLoc  = FVector{100.0, 200.0, 300.0};
    const auto     EcParity_MemberLoc = FVector{-400.0, 500.0, 300.0};
    constexpr auto EcParity_ExpectedMembers = int32{2}; // owner's own entity + the separate member probe

    static TWeakObjectPtr<UWorld> GEcParity_PreServerWorld;

    auto EcParity_MapNameOf(UWorld* InWorld) -> FString
    {
        return InWorld != nullptr ? InWorld->RemovePIEPrefix(InWorld->GetOutermost()->GetName()) : FString{};
    }

    auto EcParity_Subsystem(UWorld* InWorld) -> UCk_Snapshot_Subsystem_UE*
    {
        if (InWorld == nullptr || InWorld->GetGameInstance() == nullptr) { return nullptr; }
        return InWorld->GetGameInstance()->GetSubsystem<UCk_Snapshot_Subsystem_UE>();
    }

    // Distinct probe classes -> each iterator is unambiguous (owner vs member).
    auto EcParity_FindOwner(UWorld* InWorld) -> ACk_AutoTest_NetSubject_EntityCollection_UE*
    {
        if (InWorld == nullptr) { return nullptr; }
        for (auto It = TActorIterator<ACk_AutoTest_NetSubject_EntityCollection_UE>(InWorld); It; ++It) { return *It; }
        return nullptr;
    }

    auto EcParity_FindMember(UWorld* InWorld) -> ACk_AutoTest_NetSubject_M2bProbe_Replicated*
    {
        if (InWorld == nullptr) { return nullptr; }
        for (auto It = TActorIterator<ACk_AutoTest_NetSubject_M2bProbe_Replicated>(InWorld); It; ++It) { return *It; }
        return nullptr;
    }

    auto EcParity_ResolveEntity(AActor* InProbe) -> FCk_Handle
    {
        if (InProbe == nullptr) { return {}; }
        return UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(InProbe);
    }

    // Resolve the collection through the owner's RecordOfEntityCollections (by the known tag), NOT the actor's
    // _TestCollection stash — the record path is robust regardless of Construct-stash timing on the restored world.
    auto EcParity_ResolveCollection(AActor* InOwner) -> FCk_Handle_EntityCollection
    {
        const auto Owner = EcParity_ResolveEntity(InOwner);
        if (ck::Is_NOT_Valid(Owner)) { return {}; }
        return UCk_Utils_EntityCollection_UE::TryGet_EntityCollection(Owner, TAG_EntityCollection_AutoTest_Net.GetTag());
    }

    auto EcParity_MemberCount(AActor* InOwner, bool& OutResolved) -> int32
    {
        OutResolved = false;
        auto Collection = EcParity_ResolveCollection(InOwner);
        if (ck::Is_NOT_Valid(Collection)) { return 0; }
        OutResolved = true;
        return UCk_Utils_EntityCollection_UE::Get_NumEntitiesInCollection(Collection);
    }

    // Every member handle in the restored collection must re-resolve to a live bridged entity (proves the payload
    // handles remapped to real re-spawned entities, not dangling tombstones).
    auto EcParity_AllMembersLiveBridged(AActor* InOwner) -> bool
    {
        auto Collection = EcParity_ResolveCollection(InOwner);
        if (ck::Is_NOT_Valid(Collection)) { return false; }
        const auto Content = UCk_Utils_EntityCollection_UE::Get_EntitiesInCollection(Collection);
        const auto& Members = Content.Get_EntitiesInCollection();
        if (Members.IsEmpty()) { return false; }
        for (const auto& Member : Members)
        {
            if (ck::Is_NOT_Valid(Member)) { return false; }
            if (UCk_Utils_OwningActor_UE::TryGet_EntityOwningActor(Member) == nullptr) { return false; }
        }
        return true;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_EntityCollectionParity_MPReload_Gate,
    "Ck.Snapshot.Parity.EntityCollection_MPReload",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_EntityCollectionParity_MPReload_Gate::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;        // server window + 1 connected client (seamless-travel harness)
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesPerSettle = 30;
    constexpr auto ReloadTimeoutSeconds = 60.0f;
    constexpr auto FramesPostReconnect = 60;

    GEcParity_PreServerWorld = nullptr;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, FString{EcParity_MapPath}));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // Stage 1 — open the PIE seamless gate + spawn the collection-owner probe and one separate member probe.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
            { CVar->Set(1, ECVF_SetByCode); }

            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;

            auto* Owner = InServer->SpawnActor<ACk_AutoTest_NetSubject_EntityCollection_UE>(
                ACk_AutoTest_NetSubject_EntityCollection_UE::StaticClass(), FTransform{EcParity_OwnerLoc}, SpawnInfo);
            if (Owner == nullptr) { AddError(TEXT("Stage 1: collection-owner probe spawn returned null")); }

            auto* Member = InServer->SpawnActor<ACk_AutoTest_NetSubject_M2bProbe_Replicated>(
                ACk_AutoTest_NetSubject_M2bProbe_Replicated::StaticClass(), FTransform{EcParity_MemberLoc}, SpawnInfo);
            if (Member == nullptr) { AddError(TEXT("Stage 1: member probe spawn returned null")); }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 2 — pre-reload sanity: the owner's empty collection is composed (Construct ran) AND the member entity
    // resolves; THEN runtime-Add the two members (owner's own entity + the member entity).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr) { return false; }
            return ck::IsValid(EcParity_ResolveCollection(EcParity_FindOwner(Server))) &&
                   ck::IsValid(EcParity_ResolveEntity(EcParity_FindMember(Server)));
        }),
        ReadyTimeoutSeconds));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto Collection = EcParity_ResolveCollection(EcParity_FindOwner(InServer));
            if (ck::Is_NOT_Valid(Collection)) { AddError(TEXT("Stage 2: server collection unresolved")); return; }

            const auto OwnerEntity  = EcParity_ResolveEntity(EcParity_FindOwner(InServer));
            const auto MemberEntity = EcParity_ResolveEntity(EcParity_FindMember(InServer));
            if (ck::Is_NOT_Valid(OwnerEntity) || ck::Is_NOT_Valid(MemberEntity))
            { AddError(TEXT("Stage 2: server owner/member entities unresolved")); return; }

            // Runtime-add both members (deferred request; the following settle drains it + replication).
            UCk_Utils_EntityCollection_UE::Request_AddEntities(
                Collection, FCk_Request_EntityCollection_AddEntities{TArray<FCk_Handle>{OwnerEntity, MemberEntity}});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 2b — assert the SERVER holds both members before saving (failing here means the Add didn't take, not that
    // snapshot broke).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto Resolved = false;
            const auto Count = EcParity_MemberCount(EcParity_FindOwner(InServer), Resolved);
            TestTrue(TEXT("pre-save server: collection resolved"), Resolved);
            TestTrue(TEXT("pre-save server: NumEntities == 2"), Count == EcParity_ExpectedMembers);
        })));

    // Stage 3 — Save on the server; stash the pre-travel server world.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            GEcParity_PreServerWorld = InServer;
            auto* Sub = EcParity_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 3: no snapshot subsystem")); return; }
            Sub->Request_Save(EcParity_SlotName, FCk_Delegate_OnSaveComplete{});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 4 — fire async Load (triggers seamless ServerTravel) + assert non-blocking.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Sub = EcParity_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 4: no snapshot subsystem")); return; }
            Sub->Request_Load(EcParity_SlotName, FCk_Delegate_OnLoadComplete{});
            TestTrue(TEXT("Stage 4: Request_Load non-blocking"), Sub->Get_IsLoadInProgress());
        })));

    // Stage 5 — poll until the server finished load, rode the travel, and the membership CONVERGED on the restored
    // value (proves HydrationApply's re-drive completed, not just that the collection was re-Constructed empty).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr || Server == GEcParity_PreServerWorld.Get() || !Server->HasBegunPlay()) { return false; }
            if (EcParity_MapNameOf(Server) != EcParity_MapPath) { return false; }
            auto* Sub = EcParity_Subsystem(Server);
            if (Sub == nullptr || Sub->Get_IsLoadInProgress()) { return false; }

            auto Resolved = false;
            const auto Count = EcParity_MemberCount(EcParity_FindOwner(Server), Resolved);
            return Resolved && Count == EcParity_ExpectedMembers;
        }),
        ReloadTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPostReconnect));

    // Stage 6 — SERVER parity assertions: membership survived save -> seamless reload -> hydration (NOT the empty
    // Construct default), and every restored member re-resolves to a live bridged entity.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr) { AddError(TEXT("Stage 6: no post-travel server world")); return false; }
            auto* Owner = EcParity_FindOwner(Server);
            if (Owner == nullptr) { AddError(TEXT("Stage 6: owner probe missing post-reload")); return false; }

            auto Resolved = false;
            const auto Count = EcParity_MemberCount(Owner, Resolved);
            TestTrue(TEXT("collection re-resolves on the server post-reload (owner re-composed the collection)"), Resolved);
            TestTrue(TEXT("membership round-tripped (NumEntities == 2, not the empty Construct default)"),
                Count == EcParity_ExpectedMembers);
            TestTrue(TEXT("every restored member handle re-resolves to a live bridged entity (payload handles remapped)"),
                EcParity_AllMembersLiveBridged(Owner));
            return true;
        }),
        TEXT("EntityCollection parity: runtime membership (self + separate persisted member) survives save -> seamless reload")));

    // Stage 7 — stability: after further ticks the restored membership is STILL exactly 2 (Add is idempotent; the
    // re-armed Replicate pass must not double-add or drop members).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPostReconnect));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto* Owner  = EcParity_FindOwner(Server);
            auto Resolved = false;
            const auto Count = EcParity_MemberCount(Owner, Resolved);
            TestTrue(TEXT("post-settle: collection still resolves"), Resolved);
            TestTrue(TEXT("post-settle: membership still exactly 2 (no double-add / drop after re-arm)"),
                Count == EcParity_ExpectedMembers);
            return true;
        }),
        TEXT("EntityCollection parity: restored membership is stable post-load (no inflation/loss)")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    // Restore log-suppression statics (they are static on FAutomationTestBase; leaking them would silence later tests).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            FAutomationTestBase::bSuppressLogErrors = false;
            FAutomationTestBase::bSuppressLogWarnings = false;
            return true;
        }),
        TEXT("EntityCollection: restore log suppression statics")));

    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
