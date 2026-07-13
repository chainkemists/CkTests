#pragma once

#include "CoreMinimal.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Misc/AutomationTest.h"
#include "UObject/StrongObjectPtr.h"

#include "CkTests/Net/CkAutoTest_NetSubject_Utils.h"

// --------------------------------------------------------------------------------------------------------------------
//
// Multi-client AutoTest harness for CkStateMachine replication tests (spec §13). UE 5.5/5.6 ships
// no FNetworkedFunctionalTest equivalent, so this set of latent commands + accessors is the
// project's primitive for "drive PIE with server + N clients and assert across worlds."
//
// Composable as latent commands inside a standard IMPLEMENT_SIMPLE_AUTOMATION_TEST RunTest body:
//
//   ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(2, TEXT("/CkTests/AutoTests/AutoTests_CkTests_Level")));
//   ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(2, 30.0f));
//   ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
//       [](UWorld* InServer) -> void { /* spawn SM, drive transitions */ })));
//   ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(60));
//   ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this, FCk_NetAutoTest_Assertion::CreateLambda(
//       [this]() -> bool { return /* per-world checks */; }), TEXT("scenario assertions")));
//   ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
//
// NumClients argument matches ULevelEditorPlaySettings::PlayNumberOfClients: it counts the
// ListenServer window. NumClients=2 means 1 server-window + 1 additional client (the smallest
// useful case for testing one-server-one-client replication). NumClients=3 = server + 2 clients.
//
// World accessors return nullptr if PIE isn't currently up or the requested world index is out
// of range; latent commands handle that gracefully (return true to advance, the next assertion
// fails with a clear message).
//
// --------------------------------------------------------------------------------------------------------------------

DECLARE_DELEGATE_OneParam(FCk_NetAutoTest_ServerAction, UWorld*);
DECLARE_DELEGATE_RetVal(bool, FCk_NetAutoTest_Assertion);

// Side-effect-free predicate polled once per frame by FCk_Latent_WaitUntil. Distinct from
// FCk_NetAutoTest_Assertion (same signature) to document intent: a Condition must NOT call
// TestEqual/AddError — it returns true only once the awaited state is reached, false to keep waiting.
DECLARE_DELEGATE_RetVal(bool, FCk_NetAutoTest_Condition);

namespace ck::auto_test::net
{
    // Returns the PIE world running as the server (ListenServer or DedicatedServer). nullptr if
    // no PIE session is active or no server world exists.
    CKTESTS_API auto Get_ServerWorld() -> UWorld*;

    // Returns the Nth client world. ClientIdx 0 is the first non-server PIE client. nullptr if
    // out of range or no PIE active.
    CKTESTS_API auto Get_ClientWorld(int32 ClientIdx) -> UWorld*;

    // All PIE worlds (server + clients). Order: server first, then clients in PIEInstance order.
    CKTESTS_API auto Get_AllPIEWorlds() -> TArray<UWorld*>;

    // Count of client worlds (excludes server). Returns 0 if no PIE active.
    CKTESTS_API auto Get_NumClientWorlds() -> int32;

    // Server-side PlayerController representing the Nth remote PIE client (the one whose world is
    // Get_ClientWorld(ClientIdx)). On a listen server the local player's PC has no UNetConnection;
    // remote clients' PCs do. Used to possess a subject Pawn with a client's PC so
    // OwningClientAuthoritative replication contracts can be exercised (the SM's owning-client authority
    // resolves through the bridged actor's IsLocallyControlled-by-player check). Returns nullptr if PIE
    // isn't up or there's no such remote client.
    //
    // For a single remote client (every 2-world net test) this returns the sole net-connection PC. For
    // >1 remote client the server's PlayerControllerIterator order does NOT match Get_ClientWorld's
    // PIEInstance order, so the result is CORRELATED by player identity (PlayerState UniqueId, PlayerId
    // fallback) to the SAME client as Get_ClientWorld(ClientIdx); returns nullptr (loud) if that identity
    // has not replicated yet, rather than silently binding the wrong client.
    CKTESTS_API auto Get_RemoteClientPlayerController(UWorld* InServerWorld, int32 ClientIdx) -> class APlayerController*;
}

// --------------------------------------------------------------------------------------------------------------------
// Latent commands. Defined manually rather than via DEFINE_LATENT_AUTOMATION_COMMAND_* macros so
// commands that need progress state (frame counter, elapsed time) can carry mutable fields. The
// public-facing usage is identical: construct with parameters, ADD_LATENT_AUTOMATION_COMMAND.

class CKTESTS_API FCk_Latent_StartPIEMultiClient : public IAutomationLatentCommand
{
public:
    FCk_Latent_StartPIEMultiClient(int32 InNumClients, const FString& InMapPath)
        : _NumClients(InNumClients), _MapPath(InMapPath) {}

    virtual ~FCk_Latent_StartPIEMultiClient() = default;
    virtual bool Update() override;

private:
    int32 _NumClients = 1;
    FString _MapPath;
};

class CKTESTS_API FCk_Latent_WaitForPIEReady : public IAutomationLatentCommand
{
public:
    FCk_Latent_WaitForPIEReady(int32 InExpectedTotalWorlds, float InTimeoutSeconds)
        : _ExpectedTotalWorlds(InExpectedTotalWorlds), _TimeoutSeconds(InTimeoutSeconds) {}

    virtual ~FCk_Latent_WaitForPIEReady() = default;
    virtual bool Update() override;

private:
    int32 _ExpectedTotalWorlds = 1;
    float _TimeoutSeconds = 30.0f;
    double _StartTime = -1.0;
};

// Polls a bool predicate every frame until it returns true or InTimeoutSeconds elapses, then advances.
// On timeout it advances anyway (returns true) so a following FCk_Latent_AssertCondition reports the failure
// with a clear message rather than the whole test hanging. Reuses FCk_NetAutoTest_Assertion (RetVal bool) as
// the predicate type. Use for non-deterministic waits like "client reconnected and the replicated actor exists".
class CKTESTS_API FCk_Latent_WaitForCondition : public IAutomationLatentCommand
{
public:
    FCk_Latent_WaitForCondition(const FCk_NetAutoTest_Assertion& InPredicate, float InTimeoutSeconds)
        : _Predicate(InPredicate), _TimeoutSeconds(InTimeoutSeconds) {}

    virtual ~FCk_Latent_WaitForCondition() = default;
    virtual bool Update() override;

private:
    FCk_NetAutoTest_Assertion _Predicate;
    float _TimeoutSeconds = 30.0f;
    double _StartTime = -1.0;
};

class CKTESTS_API FCk_Latent_TickWorlds : public IAutomationLatentCommand
{
public:
    explicit FCk_Latent_TickWorlds(int32 InNumFrames)
        : _NumFrames(InNumFrames) {}

    virtual ~FCk_Latent_TickWorlds() = default;
    virtual bool Update() override;

private:
    int32 _NumFrames = 0;
    int32 _FramesElapsed = 0;
};

class CKTESTS_API FCk_Latent_RunOnServer : public IAutomationLatentCommand
{
public:
    explicit FCk_Latent_RunOnServer(const FCk_NetAutoTest_ServerAction& InAction)
        : _Action(InAction) {}

    virtual ~FCk_Latent_RunOnServer() = default;
    virtual bool Update() override;

private:
    FCk_NetAutoTest_ServerAction _Action;
};

// Same shape as FCk_Latent_RunOnServer but targets the Nth client world. ClientIdx 0 is the
// first non-server PIE client (matches ck::auto_test::net::Get_ClientWorld). Reuses the
// ServerAction delegate type because the lambda payload (UWorld*) is identical — the delegate
// name is a historical artefact, not a contract.
class CKTESTS_API FCk_Latent_RunOnClient : public IAutomationLatentCommand
{
public:
    FCk_Latent_RunOnClient(int32 InClientIdx, const FCk_NetAutoTest_ServerAction& InAction)
        : _ClientIdx(InClientIdx), _Action(InAction) {}

    virtual ~FCk_Latent_RunOnClient() = default;
    virtual bool Update() override;

private:
    int32 _ClientIdx = 0;
    FCk_NetAutoTest_ServerAction _Action;
};

class CKTESTS_API FCk_Latent_AssertCondition : public IAutomationLatentCommand
{
public:
    FCk_Latent_AssertCondition(
        FAutomationTestBase* InTest,
        const FCk_NetAutoTest_Assertion& InAssertion,
        const FString& InMessage)
        : _Test(InTest), _Assertion(InAssertion), _Message(InMessage) {}

    virtual ~FCk_Latent_AssertCondition() = default;
    virtual bool Update() override;

private:
    FAutomationTestBase* _Test = nullptr;
    FCk_NetAutoTest_Assertion _Assertion;
    FString _Message;
};

// Poll-until-converged latent command. Calls the supplied Condition once per frame; advances
// (returns true) as soon as it returns true. If TimeoutSeconds (wall-clock) elapses first, it
// AddErrors on the test and advances so the suite never hangs. Replaces a fixed FCk_Latent_TickWorlds(N)
// "settle" wait when the real intent is "wait until replication has converged" — removes the
// frame-budget race. Pair with a final FCk_Latent_AssertCondition that records the actual TestEqual
// checks (which then pass immediately, since we only proceed once converged).
class CKTESTS_API FCk_Latent_WaitUntil : public IAutomationLatentCommand
{
public:
    FCk_Latent_WaitUntil(
        FAutomationTestBase* InTest,
        const FCk_NetAutoTest_Condition& InCondition,
        double InTimeoutSeconds,
        const FString& InMessage)
        : _Test(InTest), _Condition(InCondition), _TimeoutSeconds(InTimeoutSeconds), _Message(InMessage) {}

    virtual ~FCk_Latent_WaitUntil() = default;
    virtual bool Update() override;

private:
    FAutomationTestBase* _Test = nullptr;
    FCk_NetAutoTest_Condition _Condition;
    double _TimeoutSeconds = 5.0;
    FString _Message;
    double _StartTime = -1.0;
};

class CKTESTS_API FCk_Latent_EndPIE : public IAutomationLatentCommand
{
public:
    FCk_Latent_EndPIE() = default;
    virtual ~FCk_Latent_EndPIE() = default;
    virtual bool Update() override;

private:
    bool _Requested = false;
};

// Single combined command that owns the lifecycle of an AS-authored multi-client net test:
// resolves the AS class by `/Script/Angelscript.<Name>` path, spawns one instance on each PIE
// world's TransientEntity, captures the constructed handles via Promise_OnConstructed, then
// polls each world's per-body FCk_AutoTest_Result fragment until all terminal or until
// `InTimeoutSeconds` elapses. Per-world failures + timeouts are reported via `AddError` on the
// supplied automation test so they appear in the Session Frontend output.
//
// The AS class must be a subclass of `UCk_AutoTest_Base` (or `UCk_AutoTest_NetBase`), so its
// DoBeginPlay writes a Pass/Fail to the result fragment by calling `FinishSuccess()` /
// `FinishFailure()`. The command is spawn-only — multi-PIE startup, subject-actor spawn, and
// settle ticks must be issued via the existing `FCk_Latent_StartPIEMultiClient` /
// `FCk_Latent_RunOnServer` / `FCk_Latent_TickWorlds` commands first.
class CKTESTS_API FCk_Latent_RunAsTestOnAllWorlds : public IAutomationLatentCommand
{
public:
    FCk_Latent_RunAsTestOnAllWorlds(
        FAutomationTestBase* InTest,
        const FString& InClassPath,
        float InTimeoutSeconds)
        : _Test(InTest), _ClassPath(InClassPath), _TimeoutSeconds(InTimeoutSeconds) {}

    virtual ~FCk_Latent_RunAsTestOnAllWorlds() = default;
    virtual bool Update() override;

private:
    FAutomationTestBase* _Test = nullptr;
    FString _ClassPath;
    float _TimeoutSeconds = 30.0f;

    bool _Spawned = false;
    int32 _ExpectedBodyCount = 0;
    double _StartTime = -1.0;

    // TStrongObjectPtr keeps the capturer alive across Update() calls. Dropped when the latent
    // command destructs — by which point all bodies are terminal (or we timed out) and the
    // capturer has nothing left to do.
    TStrongObjectPtr<UCk_AutoTest_BodyCapturer_UE> _BodyCapturer;
};

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
