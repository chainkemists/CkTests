// CkSnapshot AnimPlan-Parity GATE — strict state round-trip of a replicated AnimPlan through a listen-server SEAMLESS
// ServerTravel reload, asserted on the CLIENT. The server moves the plan from its Construct default (state A) to
// state B before save; the client must show state B post-reload — proving the cluster/state survived save ->
// restore -> replication, not just Construct re-derivation.
// Surface in Session Frontend: Ck.Snapshot.Parity.AnimPlan_MPReload

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/GameInstance.h"
#include "EngineUtils.h"               // TActorIterator
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel

#include "CkAnimation/AnimPlan/CkAnimPlan_Utils.h"

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/CkTests_Fragment_Data.h"
#include "CkTests/Net/CkAutoTest_NetSubject_M2bProbe_Replicated.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

namespace
{
    constexpr auto AnimPlanParity_MapPath  = TEXT("/Engine/Maps/Entry");
    const auto     AnimPlanParity_SlotName = FName{TEXT("CkSnapshot_AnimPlanParity_GateSlot")};

    static TWeakObjectPtr<UWorld> GAnimPlanParity_PreServerWorld;
    static TWeakObjectPtr<UWorld> GAnimPlanParity_PreClientWorld;

    auto AnimPlanParity_MapNameOf(UWorld* InWorld) -> FString
    {
        return InWorld != nullptr ? InWorld->RemovePIEPrefix(InWorld->GetOutermost()->GetName()) : FString{};
    }

    auto AnimPlanParity_Subsystem(UWorld* InWorld) -> UCk_Snapshot_Subsystem_UE*
    {
        if (InWorld == nullptr || InWorld->GetGameInstance() == nullptr) { return nullptr; }
        return InWorld->GetGameInstance()->GetSubsystem<UCk_Snapshot_Subsystem_UE>();
    }

    auto AnimPlanParity_FindProbe(UWorld* InWorld) -> ACk_AutoTest_NetSubject_M2bProbe_Replicated*
    {
        if (InWorld == nullptr) { return nullptr; }
        for (auto It = TActorIterator<ACk_AutoTest_NetSubject_M2bProbe_Replicated>(InWorld); It; ++It) { return *It; }
        return nullptr;
    }

    auto AnimPlanParity_ResolvePlan(AActor* InProbe) -> FCk_Handle_AnimPlan
    {
        if (InProbe == nullptr) { return {}; }
        auto Entity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(InProbe);
        if (ck::Is_NOT_Valid(Entity)) { return {}; }
        return UCk_Utils_AnimPlan_UE::TryGet_AnimPlan(Entity, TAG_AnimPlan_AutoTest_Net_Goal.GetTag());
    }

    auto AnimPlanParity_CurrentStateTag(AActor* InProbe, bool& OutResolved) -> FGameplayTag
    {
        OutResolved = false;
        auto Plan = AnimPlanParity_ResolvePlan(InProbe);
        if (ck::Is_NOT_Valid(Plan)) { return {}; }
        OutResolved = true;
        return UCk_Utils_AnimPlan_UE::Get_AnimState(Plan).Get_AnimState();
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_AnimPlanParity_MPReload_Gate,
    "Ck.Snapshot.Parity.AnimPlan_MPReload",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_AnimPlanParity_MPReload_Gate::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;        // server window + 1 connected client
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesPerSettle = 30;
    constexpr auto ReloadTimeoutSeconds = 60.0f;
    constexpr auto FramesPostReconnect = 60;

    GAnimPlanParity_PreServerWorld = nullptr;
    GAnimPlanParity_PreClientWorld = nullptr;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, FString{AnimPlanParity_MapPath}));
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

    // Stage 2 — pre-reload sanity: client has the probe AND its AnimPlan resolves.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr) { return false; }
            return ck::IsValid(AnimPlanParity_ResolvePlan(AnimPlanParity_FindProbe(Client)));
        }),
        ReadyTimeoutSeconds));

    // Stage 3 — move the plan A -> B on the server (deferred ECS request; asserted in 3b after a settle).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto Plan = AnimPlanParity_ResolvePlan(AnimPlanParity_FindProbe(InServer));
            if (ck::Is_NOT_Valid(Plan)) { AddError(TEXT("Stage 3: server AnimPlan unresolved")); return; }

            UCk_Utils_AnimPlan_UE::Request_UpdateAnimState(Plan,
                FCk_Request_AnimPlan_UpdateAnimState{
                    TAG_AnimPlan_AutoTest_Net_Cluster.GetTag(), TAG_AnimPlan_AutoTest_Net_State_B.GetTag()});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 3b — assert the SERVER holds state B before saving.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto Resolved = false;
            const auto StateTag = AnimPlanParity_CurrentStateTag(AnimPlanParity_FindProbe(InServer), Resolved);
            TestTrue(TEXT("pre-save server: AnimPlan resolved"), Resolved);
            TestTrue(TEXT("pre-save server: plan moved to state B"),
                StateTag == TAG_AnimPlan_AutoTest_Net_State_B.GetTag());
        })));

    // Stage 4 — Save on the server; stash pre-travel worlds.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            GAnimPlanParity_PreServerWorld = InServer;
            GAnimPlanParity_PreClientWorld = ck::auto_test::net::Get_ClientWorld(0);
            auto* Sub = AnimPlanParity_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 4: no snapshot subsystem")); return; }
            Sub->Request_Save(AnimPlanParity_SlotName, FCk_Delegate_OnSaveComplete{});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 5 — fire async Load (triggers seamless ServerTravel) + assert non-blocking.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Sub = AnimPlanParity_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 5: no snapshot subsystem")); return; }
            Sub->Request_Load(AnimPlanParity_SlotName, FCk_Delegate_OnLoadComplete{});
            TestTrue(TEXT("Stage 5: Request_Load non-blocking"), Sub->Get_IsLoadInProgress());
        })));

    // Stage 6 — poll until server finished load AND client rode the travel AND state B CONVERGED on the client.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr || Server == GAnimPlanParity_PreServerWorld.Get() || !Server->HasBegunPlay()) { return false; }
            if (AnimPlanParity_MapNameOf(Server) != AnimPlanParity_MapPath) { return false; }
            auto* Sub = AnimPlanParity_Subsystem(Server);
            if (Sub == nullptr || Sub->Get_IsLoadInProgress()) { return false; }
            if (AnimPlanParity_FindProbe(Server) == nullptr) { return false; }

            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr || Client == GAnimPlanParity_PreClientWorld.Get() || !Client->HasBegunPlay()) { return false; }
            if (AnimPlanParity_MapNameOf(Client) != AnimPlanParity_MapPath) { return false; }

            auto Resolved = false;
            const auto StateTag = AnimPlanParity_CurrentStateTag(AnimPlanParity_FindProbe(Client), Resolved);
            return Resolved && StateTag == TAG_AnimPlan_AutoTest_Net_State_B.GetTag();
        }),
        ReloadTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPostReconnect));

    // Stage 7 — parity assertions on BOTH worlds: state B survived (NOT the Construct default A).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto ServerResolved = false;
            const auto ServerState = AnimPlanParity_CurrentStateTag(AnimPlanParity_FindProbe(Server), ServerResolved);
            TestTrue(TEXT("server: AnimPlan resolved post-reload"), ServerResolved);
            TestTrue(TEXT("server: state B survived the snapshot round-trip"),
                ServerState == TAG_AnimPlan_AutoTest_Net_State_B.GetTag());

            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr) { AddError(TEXT("Stage 7: no post-travel client world")); return false; }

            auto ClientResolved = false;
            const auto ClientState = AnimPlanParity_CurrentStateTag(AnimPlanParity_FindProbe(Client), ClientResolved);
            TestTrue(TEXT("client: AnimPlan resolved post-reload"), ClientResolved);
            TestTrue(TEXT("client: state B round-tripped (not Construct default A)"),
                ClientState == TAG_AnimPlan_AutoTest_Net_State_B.GetTag());
            return true;
        }),
        TEXT("AnimPlan parity: server state change survives save -> seamless reload -> client re-derivation")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
