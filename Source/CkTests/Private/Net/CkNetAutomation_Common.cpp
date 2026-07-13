#include "CkTests/Net/CkNetAutomation_Common.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Editor/UnrealEdEngine.h"
#include "Engine/Engine.h"
#include "Engine/NetConnection.h"
#include "Engine/World.h"
#include "FileHelpers.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/PlayerState.h" // PlayerState identity (UniqueId/PlayerId) — remote-client<->world correlation
#include "PlayInEditorDataTypes.h"
#include "Settings/LevelEditorPlaySettings.h"
#include "UnrealEdGlobals.h"

#include "CkCore/Validation/CkIsValid.h"
#include "CkCore/Format/CkFormat.h"

#include "CkEcs/EntityScript/CkEntityScript_Fragment_Data.h"
#include "CkEcs/EntityScript/CkEntityScript_Utils.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkAutoTest_Bridge.h"
#include "CkAutoTest_Utils.h"
#include "CkTests/Net/CkAutoTest_NetSubject_Utils.h"

#include "UObject/SoftObjectPath.h"
#include <StructUtils/InstancedStruct.h>

DEFINE_LOG_CATEGORY_STATIC(LogCkNetAutomation, Log, All);

namespace
{
    template <typename TString, typename... TArgs>
    void Log_Error(const TString& Fmt, TArgs&&... Args)
    {
        UE_LOG(LogCkNetAutomation, Error, TEXT("%s"), *ck::Format_UE(Fmt, Forward<TArgs>(Args)...));
    }

    template <typename TString, typename... TArgs>
    void Log_Display(const TString& Fmt, TArgs&&... Args)
    {
        UE_LOG(LogCkNetAutomation, Display, TEXT("%s"), *ck::Format_UE(Fmt, Forward<TArgs>(Args)...));
    }
}

// --------------------------------------------------------------------------------------------------------------------

namespace ck::auto_test::net
{
    auto
        Get_AllPIEWorlds()
        -> TArray<UWorld*>
    {
        auto Worlds = TArray<UWorld*>{};
        if (GEngine == nullptr)
        { return Worlds; }

        // Server first, then clients in PIEInstance order. The world contexts list isn't
        // sorted by role, so we collect server + clients separately and append.
        auto* ServerWorld = static_cast<UWorld*>(nullptr);
        auto ClientWorlds = TArray<TPair<int32, UWorld*>>{};

        for (const auto& Context : GEngine->GetWorldContexts())
        {
            if (Context.WorldType != EWorldType::PIE)
            { continue; }

            auto* World = Context.World();
            if (ck::Is_NOT_Valid(World, ck::IsValid_Policy_NullptrOnly{}))
            { continue; }

            const auto NetMode = World->GetNetMode();
            const auto IsServer = NetMode == NM_ListenServer || NetMode == NM_DedicatedServer;

            if (IsServer && ServerWorld == nullptr)
            { ServerWorld = World; }
            else
            { ClientWorlds.Add({Context.PIEInstance, World}); }
        }

        ClientWorlds.Sort([](const TPair<int32, UWorld*>& A, const TPair<int32, UWorld*>& B) -> bool
        {
            return A.Key < B.Key;
        });

        if (ServerWorld != nullptr)
        { Worlds.Add(ServerWorld); }
        for (const auto& Pair : ClientWorlds)
        { Worlds.Add(Pair.Value); }

        return Worlds;
    }

    // ----------------------------------------------------------------------------------------------------------------

    auto
        Get_ServerWorld()
        -> UWorld*
    {
        if (GEngine == nullptr)
        { return nullptr; }

        for (const auto& Context : GEngine->GetWorldContexts())
        {
            if (Context.WorldType != EWorldType::PIE)
            { continue; }

            auto* World = Context.World();
            if (ck::Is_NOT_Valid(World, ck::IsValid_Policy_NullptrOnly{}))
            { continue; }

            const auto NetMode = World->GetNetMode();
            if (NetMode == NM_ListenServer || NetMode == NM_DedicatedServer)
            { return World; }
        }

        return nullptr;
    }

    // ----------------------------------------------------------------------------------------------------------------

    auto
        Get_ClientWorld(
            int32 ClientIdx)
        -> UWorld*
    {
        auto AllWorlds = Get_AllPIEWorlds();
        // Index 0 in AllWorlds is the server; clients start at index 1.
        const auto AbsoluteIdx = ClientIdx + 1;
        if (AllWorlds.IsValidIndex(AbsoluteIdx) == false)
        { return nullptr; }
        return AllWorlds[AbsoluteIdx];
    }

    // ----------------------------------------------------------------------------------------------------------------

    auto
        Get_NumClientWorlds()
        -> int32
    {
        const auto AllWorlds = Get_AllPIEWorlds();
        return FMath::Max(0, AllWorlds.Num() - 1);
    }

    // ----------------------------------------------------------------------------------------------------------------

    auto
        Get_RemoteClientPlayerController(
            UWorld* InServerWorld,
            int32 ClientIdx)
        -> APlayerController*
    {
        if (ck::Is_NOT_Valid(InServerWorld, ck::IsValid_Policy_NullptrOnly{}))
        { return nullptr; }

        // On a listen server, the local player's PlayerController has no UNetConnection; each
        // remote client's PC carries one. Collect the net-connection-backed PCs.
        auto RemotePCs = TArray<APlayerController*>{};
        for (auto It = InServerWorld->GetPlayerControllerIterator(); It; ++It)
        {
            auto* PC = It->Get();
            if (ck::Is_NOT_Valid(PC, ck::IsValid_Policy_NullptrOnly{}))
            { continue; }

            if (PC->GetNetConnection() != nullptr)
            { RemotePCs.Add(PC); }
        }

        // Single-remote-client fast path (every 2-world net test): iterator order is unambiguous — this
        // preserves the exact historical behavior (index into iterator order).
        if (RemotePCs.Num() <= 1)
        {
            if (RemotePCs.IsValidIndex(ClientIdx) == false)
            {
                Log_Error(TEXT("Get_RemoteClientPlayerController: no remote client PC at index [{}] (found [{}] net-connection PCs on server)"),
                    ClientIdx, RemotePCs.Num());
                return nullptr;
            }
            return RemotePCs[ClientIdx];
        }

        // >1 remote client: the server's PlayerControllerIterator order is NOT correlated to Get_ClientWorld's
        // PIEInstance order. Correlate by player identity so index N refers to the SAME client on both sides.
        // The server-side remote PC's PlayerState and the client world's local PC's PlayerState are the same
        // replicated actor, so their identity matches once replicated.
        auto* ClientWorld = Get_ClientWorld(ClientIdx);
        if (ck::Is_NOT_Valid(ClientWorld, ck::IsValid_Policy_NullptrOnly{}))
        {
            Log_Error(TEXT("Get_RemoteClientPlayerController: no client world at index [{}] to correlate against"), ClientIdx);
            return nullptr;
        }

        auto* ClientLocalPC = ClientWorld->GetFirstPlayerController();
        APlayerState* ClientPS = ClientLocalPC != nullptr ? ClientLocalPC->PlayerState.Get() : nullptr;
        if (ClientPS == nullptr)
        {
            Log_Error(TEXT("Get_RemoteClientPlayerController: client world [{}] has no local PlayerState yet"), ClientIdx);
            return nullptr;
        }

        const auto ClientUniqueId = ClientPS->GetUniqueId();
        const auto ClientPlayerId = ClientPS->GetPlayerId();

        for (auto* PC : RemotePCs)
        {
            APlayerState* ServerPS = PC->PlayerState;
            if (ServerPS == nullptr)
            { continue; }

            // Prefer the replicated unique net id; fall back to the GameMode-assigned PlayerId (int32, always
            // replicated) — a NULL online subsystem in PIE may not populate a valid UniqueId.
            const auto MatchesUniqueId = ClientUniqueId.IsValid() && ServerPS->GetUniqueId().IsValid()
                && ServerPS->GetUniqueId() == ClientUniqueId;
            const auto MatchesPlayerId = ServerPS->GetPlayerId() == ClientPlayerId;

            if (MatchesUniqueId || MatchesPlayerId)
            { return PC; }
        }

        Log_Error(TEXT("Get_RemoteClientPlayerController: no server-side remote PC matched client world [{}] identity (UniqueId valid=[{}], PlayerId=[{}]; [{}] remote PCs) — identity not replicated yet?"),
            ClientIdx, ClientUniqueId.IsValid(), ClientPlayerId, RemotePCs.Num());
        return nullptr;
    }
}

// --------------------------------------------------------------------------------------------------------------------

bool
    FCk_Latent_StartPIEMultiClient::
    Update()
{
    if (GUnrealEd == nullptr)
    {
        Log_Error(TEXT("FCk_Latent_StartPIEMultiClient: GUnrealEd is null — cannot start PIE."));
        return true;
    }

    // Load the test map first if a map path was supplied. Empty map path means "use whatever
    // map is currently open" (rare; intended for tests that build a level programmatically).
    if (_MapPath.IsEmpty() == false)
    {
        constexpr auto LoadAsTemplate = false;
        constexpr auto ShowProgress = false;
        const auto Loaded = FEditorFileUtils::LoadMap(_MapPath, LoadAsTemplate, ShowProgress);
        if (Loaded == false)
        {
            Log_Error(TEXT("FCk_Latent_StartPIEMultiClient: failed to load map [{}]"), _MapPath);
            return true;
        }
    }

    auto* Settings = GetMutableDefault<ULevelEditorPlaySettings>();
    if (Settings == nullptr)
    {
        Log_Error(TEXT("FCk_Latent_StartPIEMultiClient: GetMutableDefault<ULevelEditorPlaySettings>() returned null."));
        return true;
    }

    const auto NumClientsClamped = FMath::Max(1, _NumClients);
    Settings->SetPlayNumberOfClients(NumClientsClamped);
    Settings->SetPlayNetMode(EPlayNetMode::PIE_ListenServer);
    Settings->SetRunUnderOneProcess(true);
    Settings->bLaunchSeparateServer = false;

    auto Params = FRequestPlaySessionParams{};
    Params.WorldType = EPlaySessionWorldType::PlayInEditor;

    Log_Display(TEXT("FCk_Latent_StartPIEMultiClient: starting PIE with [{}] client(s) on map [{}]"),
        NumClientsClamped, _MapPath);

    GUnrealEd->RequestPlaySession(Params);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

bool
    FCk_Latent_WaitForPIEReady::
    Update()
{
    if (_StartTime < 0.0)
    { _StartTime = FPlatformTime::Seconds(); }

    const auto Elapsed = FPlatformTime::Seconds() - _StartTime;
    if (Elapsed > _TimeoutSeconds)
    {
        Log_Error(TEXT("FCk_Latent_WaitForPIEReady: timed out after [{}]s waiting for [{}] PIE world(s) — observed [{}]"),
            _TimeoutSeconds, _ExpectedTotalWorlds, ck::auto_test::net::Get_AllPIEWorlds().Num());
        return true;
    }

    const auto PIEWorlds = ck::auto_test::net::Get_AllPIEWorlds();
    if (PIEWorlds.Num() < _ExpectedTotalWorlds)
    { return false; }

    // All worlds present — confirm BeginPlay has fired on each (proxies for "ready to assert").
    for (auto* World : PIEWorlds)
    {
        if (World->HasBegunPlay() == false)
        { return false; }
    }

    Log_Display(TEXT("FCk_Latent_WaitForPIEReady: [{}] PIE world(s) ready after [{}]s"),
        PIEWorlds.Num(), Elapsed);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

bool
    FCk_Latent_WaitForCondition::
    Update()
{
    if (_StartTime < 0.0)
    { _StartTime = FPlatformTime::Seconds(); }

    if (_Predicate.IsBound() && _Predicate.Execute())
    { return true; }

    const auto Elapsed = FPlatformTime::Seconds() - _StartTime;
    if (Elapsed > _TimeoutSeconds)
    {
        Log_Display(TEXT("FCk_Latent_WaitForCondition: timed out after [{}]s — advancing (a following assert will report)"),
            _TimeoutSeconds);
        return true;
    }

    return false;
}

// --------------------------------------------------------------------------------------------------------------------

bool
    FCk_Latent_TickWorlds::
    Update()
{
    // The engine ticks PIE worlds normally between latent command Update() calls — this command
    // is effectively a "wait N frames" so replication can converge. Per-world Tick is intentionally
    // not invoked here; doing so would double-tick and break per-frame invariants in CkFoundation
    // processors that rely on stable DeltaT.
    ++_FramesElapsed;
    return _FramesElapsed >= _NumFrames;
}

// --------------------------------------------------------------------------------------------------------------------

bool
    FCk_Latent_RunOnServer::
    Update()
{
    auto* Server = ck::auto_test::net::Get_ServerWorld();
    if (Server == nullptr)
    {
        Log_Error(TEXT("FCk_Latent_RunOnServer: no server world available — PIE not started or not ready."));
        return true;
    }

    if (_Action.IsBound())
    { _Action.Execute(Server); }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

bool
    FCk_Latent_RunOnClient::
    Update()
{
    auto* Client = ck::auto_test::net::Get_ClientWorld(_ClientIdx);
    if (Client == nullptr)
    {
        Log_Error(TEXT("FCk_Latent_RunOnClient: no client world at index [{}] — PIE not started or not enough client instances."),
            _ClientIdx);
        return true;
    }

    if (_Action.IsBound())
    { _Action.Execute(Client); }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

bool
    FCk_Latent_AssertCondition::
    Update()
{
    if (_Test == nullptr)
    { return true; }

    if (_Assertion.IsBound() == false)
    {
        _Test->AddError(ck::Format_UE(TEXT("FCk_Latent_AssertCondition [{}]: unbound assertion delegate"), _Message));
        return true;
    }

    const auto Passed = _Assertion.Execute();
    if (Passed == false)
    { _Test->AddError(ck::Format_UE(TEXT("FCk_Latent_AssertCondition failed: {}"), _Message)); }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

bool
    FCk_Latent_WaitUntil::
    Update()
{
    if (_StartTime < 0.0)
    { _StartTime = FPlatformTime::Seconds(); }

    if (_Condition.IsBound() == false)
    {
        if (_Test != nullptr)
        { _Test->AddError(ck::Format_UE(TEXT("FCk_Latent_WaitUntil [{}]: unbound condition delegate"), _Message)); }
        return true;
    }

    // Poll the condition every frame — the engine ticks the PIE worlds between Update() calls, so
    // returning false re-checks on the next frame (replication advances in the interim).
    if (_Condition.Execute())
    {
        Log_Display(TEXT("FCk_Latent_WaitUntil: condition met after [{}]s — {}"),
            FPlatformTime::Seconds() - _StartTime, _Message);
        return true;
    }

    const auto Elapsed = FPlatformTime::Seconds() - _StartTime;
    if (Elapsed > _TimeoutSeconds)
    {
        if (_Test != nullptr)
        {
            _Test->AddError(ck::Format_UE(
                TEXT("FCk_Latent_WaitUntil: timed out after [{}]s waiting for: {}"),
                _TimeoutSeconds, _Message));
        }
        return true;
    }

    return false;
}

// --------------------------------------------------------------------------------------------------------------------

bool
    FCk_Latent_EndPIE::
    Update()
{
    if (GUnrealEd == nullptr)
    { return true; }

    if (_Requested == false)
    {
        Log_Display(TEXT("FCk_Latent_EndPIE: requesting end of PIE session."));
        GUnrealEd->RequestEndPlayMap();
        _Requested = true;
        return false;
    }

    // Wait until all PIE worlds are gone before returning — otherwise the next test inherits
    // half-torn-down state.
    return ck::auto_test::net::Get_AllPIEWorlds().IsEmpty();
}

// --------------------------------------------------------------------------------------------------------------------

bool
    FCk_Latent_RunAsTestOnAllWorlds::
    Update()
{
    if (_Test == nullptr)
    { return true; }

    // ---- Phase 1: spawn (first call only) -----------------------------------------------------------------------

    if (NOT _Spawned)
    {
        _Spawned = true;
        _StartTime = FPlatformTime::Seconds();

        const auto AsClassPath = FSoftClassPath{_ClassPath};
        auto* AsClass = AsClassPath.TryLoadClass<UCk_EntityScript_UE>();
        if (AsClass == nullptr)
        {
            _Test->AddError(ck::Format_UE(
                TEXT("FCk_Latent_RunAsTestOnAllWorlds: could not load AS class at [{}] — check the path string."),
                _ClassPath));
            return true;
        }

        const auto PieWorlds = ck::auto_test::net::Get_AllPIEWorlds();
        if (PieWorlds.IsEmpty())
        {
            _Test->AddError(TEXT("FCk_Latent_RunAsTestOnAllWorlds: no PIE worlds available — PIE not started?"));
            return true;
        }

        _BodyCapturer = TStrongObjectPtr{NewObject<UCk_AutoTest_BodyCapturer_UE>()};
        _ExpectedBodyCount = PieWorlds.Num();

        for (auto* World : PieWorlds)
        {
            auto TransientEntity = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(World);
            if (ck::Is_NOT_Valid(TransientEntity))
            {
                _Test->AddError(ck::Format_UE(
                    TEXT("FCk_Latent_RunAsTestOnAllWorlds: world [{}] has no valid TransientEntity."),
                    World->GetName()));
                continue;
            }

            auto Pending = UCk_Utils_EntityScript_UE::Request_SpawnEntity(
                TransientEntity, AsClass, FInstancedStruct{});

            auto OnConstructed = FCk_Delegate_EntityScript_Constructed{};
            OnConstructed.BindDynamic(_BodyCapturer.Get(), &UCk_AutoTest_BodyCapturer_UE::OnBodyConstructed);
            UCk_Utils_PendingEntityScript_UE::Promise_OnConstructed(Pending, OnConstructed);
        }

        return false; // wait for construction + result-fragment writes
    }

    // ---- Phase 2: poll each captured body's result fragment ------------------------------------------------------

    const auto Elapsed = FPlatformTime::Seconds() - _StartTime;
    if (Elapsed > _TimeoutSeconds)
    {
        _Test->AddError(ck::Format_UE(
            TEXT("FCk_Latent_RunAsTestOnAllWorlds: timed out after [{}]s. Captured [{}/{}] bodies."),
            _TimeoutSeconds,
            _BodyCapturer.IsValid() ? _BodyCapturer->_CapturedBodies.Num() : 0,
            _ExpectedBodyCount));
        return true;
    }

    if (NOT _BodyCapturer.IsValid())
    { return true; }

    if (_BodyCapturer->_CapturedBodies.Num() < _ExpectedBodyCount)
    { return false; } // not all worlds have constructed yet

    auto AllTerminal = true;
    auto AnyFailed   = false;
    auto FailureMessages = TArray<FString>{};

    for (auto Index = 0; Index < _BodyCapturer->_CapturedBodies.Num(); ++Index)
    {
        const auto& Body = _BodyCapturer->_CapturedBodies[Index];
        if (NOT UCk_Utils_AutoTest_UE::Has_Result(Body))
        {
            AllTerminal = false;
            break;
        }

        const auto Result = UCk_Utils_AutoTest_UE::Get_Result(Body);
        switch (Result.Status)
        {
            case ECk_AutoTest_Status::Pending:
            case ECk_AutoTest_Status::Running:
                AllTerminal = false;
                break;
            case ECk_AutoTest_Status::Passed:
                break;
            case ECk_AutoTest_Status::Failed:
            case ECk_AutoTest_Status::TimedOut:
            {
                AnyFailed = true;
                // Build the world label as an FString first — feeding ck::Format_UE's result
                // directly through `*` would dereference a temporary, garbling the label.
                const auto WorldLabel = (Index == 0)
                    ? FString{TEXT("Server")}
                    : ck::Format_UE(TEXT("Client[{}]"), Index - 1);
                FailureMessages.Add(ck::Format_UE(
                    TEXT("[{}] {} ({}/{} assertions failed)"),
                    WorldLabel,
                    Result.FailureMessage,
                    Result.AssertionsFailed,
                    Result.AssertionsRun));
                break;
            }
        }
    }

    if (NOT AllTerminal)
    { return false; }

    for (const auto& Msg : FailureMessages)
    { _Test->AddError(Msg); }

    if (NOT AnyFailed)
    {
        Log_Display(TEXT("FCk_Latent_RunAsTestOnAllWorlds: all [{}] worlds passed in [{}]s."),
            _ExpectedBodyCount, Elapsed);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
