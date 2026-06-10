// CkSnapshot TagSet-Parity GATE — strict value round-trip of a replicated TagSet through a listen-server SEAMLESS
// ServerTravel reload, asserted on the CLIENT. The server adds a tag the entity-script Construct does NOT add before
// save; the client must show that tag post-reload — proving the TagSet survived save -> restore -> replication, not
// just Construct re-derivation (Construct creates the TagSet EMPTY).
// Surface in Session Frontend: Ck.Snapshot.Parity.TagSet_MPReload

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/GameInstance.h"
#include "EngineUtils.h"               // TActorIterator
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel

#include "CkTagSet/CkTagSet_Utils.h"

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkAutoTest_NetSubject_M2bProbe_Replicated.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

namespace
{
    constexpr auto TagSetParity_MapPath  = TEXT("/Engine/Maps/Entry");
    const auto     TagSetParity_SlotName = FName{TEXT("CkSnapshot_TagSetParity_GateSlot")};

    // Registered in Config/DefaultGameplayTags.ini; already used by the AS TagSet net test. The
    // subject's Construct creates its TagSet EMPTY, so presence post-reload proves the round-trip.
    constexpr auto TagSetParity_TagName = TEXT("Probe.Gyms.A");

    static TWeakObjectPtr<UWorld> GTagSetParity_PreServerWorld;
    static TWeakObjectPtr<UWorld> GTagSetParity_PreClientWorld;

    auto TagSetParity_MapNameOf(UWorld* InWorld) -> FString
    {
        return InWorld != nullptr ? InWorld->RemovePIEPrefix(InWorld->GetOutermost()->GetName()) : FString{};
    }

    auto TagSetParity_Subsystem(UWorld* InWorld) -> UCk_Snapshot_Subsystem_UE*
    {
        if (InWorld == nullptr || InWorld->GetGameInstance() == nullptr) { return nullptr; }
        return InWorld->GetGameInstance()->GetSubsystem<UCk_Snapshot_Subsystem_UE>();
    }

    auto TagSetParity_FindProbe(UWorld* InWorld) -> ACk_AutoTest_NetSubject_M2bProbe_Replicated*
    {
        if (InWorld == nullptr) { return nullptr; }
        for (auto It = TActorIterator<ACk_AutoTest_NetSubject_M2bProbe_Replicated>(InWorld); It; ++It) { return *It; }
        return nullptr;
    }

    auto TagSetParity_ResolveTagSet(AActor* InProbe) -> FCk_Handle_TagSet
    {
        if (InProbe == nullptr) { return {}; }
        auto Entity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(InProbe);
        if (ck::Is_NOT_Valid(Entity)) { return {}; }
        if (NOT UCk_Utils_TagSet_UE::Has(Entity)) { return {}; }
        return UCk_Utils_TagSet_UE::Cast(Entity);
    }

    auto TagSetParity_HasTag(AActor* InProbe, bool& OutResolved) -> bool
    {
        OutResolved = false;
        auto TagSet = TagSetParity_ResolveTagSet(InProbe);
        if (ck::Is_NOT_Valid(TagSet)) { return false; }
        OutResolved = true;
        return UCk_Utils_TagSet_UE::HasTagExact(TagSet,
            FGameplayTag::RequestGameplayTag(FName{TagSetParity_TagName}));
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_TagSetParity_MPReload_Gate,
    "Ck.Snapshot.Parity.TagSet_MPReload",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_TagSetParity_MPReload_Gate::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;        // server window + 1 connected client
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesPerSettle = 30;
    constexpr auto ReloadTimeoutSeconds = 60.0f;
    constexpr auto FramesPostReconnect = 60;

    GTagSetParity_PreServerWorld = nullptr;
    GTagSetParity_PreClientWorld = nullptr;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, FString{TagSetParity_MapPath}));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // Stage 1 — open the PIE seamless gate + spawn the replicated bridged probe on the server.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
            { CVar->Set(1, ECVF_SetByCode); }

            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            auto* Probe = InServer->SpawnActor<ACk_AutoTest_NetSubject_M2bProbe_Replicated>(
                ACk_AutoTest_NetSubject_M2bProbe_Replicated::StaticClass(), FTransform{FVector{100.0, 200.0, 300.0}}, SpawnInfo);
            if (Probe == nullptr) { AddError(TEXT("Stage 1: replicated probe spawn returned null")); }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 2 — pre-reload sanity: client has the probe AND its TagSet resolves.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr) { return false; }
            return ck::IsValid(TagSetParity_ResolveTagSet(TagSetParity_FindProbe(Client)));
        }),
        ReadyTimeoutSeconds));

    // Stage 3 — ADD the tag on the server (deferred ECS request; asserted in Stage 3b after a settle).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto TagSet = TagSetParity_ResolveTagSet(TagSetParity_FindProbe(InServer));
            if (ck::Is_NOT_Valid(TagSet)) { AddError(TEXT("Stage 3: server TagSet unresolved")); return; }

            UCk_Utils_TagSet_UE::Request_AddTag(TagSet,
                FGameplayTag::RequestGameplayTag(FName{TagSetParity_TagName}));
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 3b — the deferred add has processed; assert the SERVER holds the tag before saving.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto Resolved = false;
            const auto HasTag = TagSetParity_HasTag(TagSetParity_FindProbe(InServer), Resolved);
            TestTrue(TEXT("pre-save server: TagSet resolved"), Resolved);
            TestTrue(TEXT("pre-save server: TagSet has the added tag"), HasTag);
        })));

    // Stage 4 — Save on the server; stash pre-travel worlds.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            GTagSetParity_PreServerWorld = InServer;
            GTagSetParity_PreClientWorld = ck::auto_test::net::Get_ClientWorld(0);
            auto* Sub = TagSetParity_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 4: no snapshot subsystem")); return; }
            Sub->Request_Save(TagSetParity_SlotName, FCk_Delegate_OnSaveComplete{});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 5 — fire async Load (triggers seamless ServerTravel) + assert non-blocking.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Sub = TagSetParity_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 5: no snapshot subsystem")); return; }
            Sub->Request_Load(TagSetParity_SlotName, FCk_Delegate_OnLoadComplete{});
            TestTrue(TEXT("Stage 5: Request_Load non-blocking"), Sub->Get_IsLoadInProgress());
        })));

    // Stage 6 — poll until server finished load AND client rode the travel AND the tag CONVERGED on the client.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr || Server == GTagSetParity_PreServerWorld.Get() || !Server->HasBegunPlay()) { return false; }
            if (TagSetParity_MapNameOf(Server) != TagSetParity_MapPath) { return false; }
            auto* Sub = TagSetParity_Subsystem(Server);
            if (Sub == nullptr || Sub->Get_IsLoadInProgress()) { return false; }
            if (TagSetParity_FindProbe(Server) == nullptr) { return false; }

            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr || Client == GTagSetParity_PreClientWorld.Get() || !Client->HasBegunPlay()) { return false; }
            if (TagSetParity_MapNameOf(Client) != TagSetParity_MapPath) { return false; }

            auto Resolved = false;
            return TagSetParity_HasTag(TagSetParity_FindProbe(Client), Resolved) && Resolved;
        }),
        ReloadTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPostReconnect));

    // Stage 7 — parity assertions on BOTH worlds: the added tag survived (NOT the empty Construct default).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto ServerResolved = false;
            const auto ServerHasTag = TagSetParity_HasTag(TagSetParity_FindProbe(Server), ServerResolved);
            TestTrue(TEXT("server: TagSet resolved post-reload"), ServerResolved);
            TestTrue(TEXT("server: added tag survived the snapshot round-trip"), ServerHasTag);

            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr) { AddError(TEXT("Stage 7: no post-travel client world")); return false; }

            auto ClientResolved = false;
            const auto ClientHasTag = TagSetParity_HasTag(TagSetParity_FindProbe(Client), ClientResolved);
            TestTrue(TEXT("client: TagSet resolved post-reload"), ClientResolved);
            TestTrue(TEXT("client: added tag round-tripped (not the empty Construct default)"), ClientHasTag);
            return true;
        }),
        TEXT("TagSet parity: server-added tag survives save -> seamless reload -> client re-derivation")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
