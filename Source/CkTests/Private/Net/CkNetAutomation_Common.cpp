#include "CkTests/Net/CkNetAutomation_Common.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Editor/UnrealEdEngine.h"
#include "Engine/Engine.h"
#include "Engine/World.h"
#include "FileHelpers.h"
#include "PlayInEditorDataTypes.h"
#include "Settings/LevelEditorPlaySettings.h"
#include "UnrealEdGlobals.h"

#include "CkCore/Validation/CkIsValid.h"
#include "CkCore/Format/CkFormat.h"

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
    FCk_Latent_AssertCondition::
    Update()
{
    if (_Test == nullptr)
    { return true; }

    if (_Assertion.IsBound() == false)
    {
        _Test->AddError(FString::Printf(TEXT("FCk_Latent_AssertCondition [%s]: unbound assertion delegate"), *_Message));
        return true;
    }

    const auto Passed = _Assertion.Execute();
    if (Passed == false)
    { _Test->AddError(FString::Printf(TEXT("FCk_Latent_AssertCondition failed: %s"), *_Message)); }

    return true;
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

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
