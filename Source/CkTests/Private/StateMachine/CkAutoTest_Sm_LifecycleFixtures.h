#pragma once

#include "CkStateMachine/Condition/EntityScripts/CkSmCondition_Polled.h"
#include "CkStateMachine/Condition/EntityScripts/CkSmCondition_TaskResult.h"
#include "CkStateMachine/Task/EntityScripts/CkSmTask_EntityScript.h"

#include "CkTests/Net/CkAutoTest_Sm_RecordingState.h"

#include "CkAutoTest_Sm_LifecycleFixtures.generated.h"

// --------------------------------------------------------------------------------------------------------------------
//
// Fixtures for the SM lifecycle-request edge-state specs (CkStateMachine_Lifecycle_RequestEdgeStates.spec.cpp)
// and the task-result-latch spec. The lifecycle bugs under test are evaluator-driven — they need a
// transition gated on a polled condition whose pass/fail the spec can flip between latent
// commands. The recording states (A/B/C) are pure markers with no transitions, so these fixtures
// supply the missing gated / tasked topologies.
//
// --------------------------------------------------------------------------------------------------------------------

// Polled condition that evaluates a spec-controlled static flag. Specs MUST reset `Gate` and
// `EvaluateCallCount` at the start of each RunTest — they are process-global state shared across
// tests in one session. `EvaluateCallCount` lets specs assert whether the polled evaluator ran at
// all (e.g. "a Paused SM must not call user Evaluate predicates").
UCLASS()
class UCk_AutoTest_Sm_GateCondition_UE : public UCk_SmCondition_Polled
{
    GENERATED_BODY()

public:
    auto
    Evaluate(
        FCk_Handle_SmCondition InHandle,
        FCk_Time InDeltaT) const -> bool override;

    static bool  Gate;
    static int32 EvaluateCallCount;
};

// --------------------------------------------------------------------------------------------------------------------

// Tick-mode task that reproduces the terminal-result clobber race entirely within one frame:
// when `MarkSucceededOnNextTick` is armed, its next Tick calls Mark_Result(Succeeded) and then
// returns Running — the exact sequence where the processor's Request_UpdateTaskResult(Running)
// used to overwrite the not-yet-broadcast terminal result ("finished: Running"). It ALWAYS
// returns Running, so the one broadcast triggered by the mark is the only completion signal a
// consumer can ever see — making clobber vs latch crisply observable.
UCLASS()
class UCk_AutoTest_Sm_SelfClobberTask_UE : public UCk_SmTask_EntityScript
{
    GENERATED_BODY()

public:
    UCk_AutoTest_Sm_SelfClobberTask_UE();

    auto
    Tick(
        FCk_Handle_SmTask InHandle,
        FCk_Time InDeltaT,
        ECk_Sm_NetContext InNetContext) -> ECk_SmTaskResult override;

    static bool  MarkSucceededOnNextTick;
    static int32 TickCount;
};

// --------------------------------------------------------------------------------------------------------------------

// TaskResult condition pre-wired to the self-clobber task (expects Succeeded — the default).
// This is the real broadcast consumer: it only satisfies if OnSmTaskFinished carries the
// terminal result, which is exactly what the clobber destroyed.
UCLASS()
class UCk_AutoTest_Sm_ClobberTaskResultCondition_UE : public UCk_SmCondition_TaskResult
{
    GENERATED_BODY()

public:
    UCk_AutoTest_Sm_ClobberTaskResultCondition_UE();
};

// --------------------------------------------------------------------------------------------------------------------

// Idle state hosting the self-clobber task, with a transition to RecordingState_B gated on the
// task finishing Succeeded. The latch spec asserts the transition fires — i.e. the broadcast
// carried the terminal result, not the clobbered Running.
UCLASS()
class UCk_AutoTest_Sm_TaskLatchIdleState_UE : public UCk_AutoTest_Sm_RecordingState_Base
{
    GENERATED_BODY()

protected:
    auto
    DefineState(
        FCk_Handle_SmState_UnderConstruction& InHandle) -> void override;
};

// --------------------------------------------------------------------------------------------------------------------

// Idle state with a single transition to UCk_AutoTest_Sm_RecordingState_B, gated on
// UCk_AutoTest_Sm_GateCondition_UE. Enter/Exit recording comes from the RecordingState base.
UCLASS()
class UCk_AutoTest_Sm_GatedIdleState_UE : public UCk_AutoTest_Sm_RecordingState_Base
{
    GENERATED_BODY()

protected:
    auto
    DefineState(
        FCk_Handle_SmState_UnderConstruction& InHandle) -> void override;
};

// --------------------------------------------------------------------------------------------------------------------
