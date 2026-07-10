#include "CkAutoTest_Sm_LifecycleFixtures.h"

// --------------------------------------------------------------------------------------------------------------------

bool  UCk_AutoTest_Sm_GateCondition_UE::Gate = false;
int32 UCk_AutoTest_Sm_GateCondition_UE::EvaluateCallCount = 0;

auto
    UCk_AutoTest_Sm_GateCondition_UE::
    Evaluate(
        FCk_Handle_SmCondition InHandle,
        FCk_Time InDeltaT) const
    -> bool
{
    ++EvaluateCallCount;
    return Gate;
}

// --------------------------------------------------------------------------------------------------------------------

bool  UCk_AutoTest_Sm_SelfClobberTask_UE::MarkSucceededOnNextTick = false;
int32 UCk_AutoTest_Sm_SelfClobberTask_UE::TickCount = 0;

UCk_AutoTest_Sm_SelfClobberTask_UE::UCk_AutoTest_Sm_SelfClobberTask_UE()
{
    _TaskMode = ECk_SmTaskMode::Tick;
}

auto
    UCk_AutoTest_Sm_SelfClobberTask_UE::
    Tick(
        FCk_Handle_SmTask InHandle,
        FCk_Time InDeltaT,
        ECk_Sm_NetContext InNetContext)
    -> ECk_SmTaskResult
{
    ++TickCount;

    if (MarkSucceededOnNextTick)
    {
        MarkSucceededOnNextTick = false;
        Mark_Result(ECk_SmTaskResult::Succeeded);
    }

    return ECk_SmTaskResult::Running;
}

// --------------------------------------------------------------------------------------------------------------------

UCk_AutoTest_Sm_ClobberTaskResultCondition_UE::UCk_AutoTest_Sm_ClobberTaskResultCondition_UE()
{
    _TaskClass = UCk_AutoTest_Sm_SelfClobberTask_UE::StaticClass();
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_Sm_TaskLatchIdleState_UE::
    DefineState(
        FCk_Handle_SmState_UnderConstruction& InHandle)
    -> void
{
    Super::DefineState(InHandle);

    AddTask(InHandle, UCk_AutoTest_Sm_SelfClobberTask_UE::StaticClass());

    auto Transition = AddTransition(InHandle, UCk_AutoTest_Sm_RecordingState_B::StaticClass());
    AddCondition(Transition, UCk_AutoTest_Sm_ClobberTaskResultCondition_UE::StaticClass());
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_Sm_GatedIdleState_UE::
    DefineState(
        FCk_Handle_SmState_UnderConstruction& InHandle)
    -> void
{
    Super::DefineState(InHandle);

    auto Transition = AddTransition(InHandle, UCk_AutoTest_Sm_RecordingState_B::StaticClass());
    AddCondition(Transition, UCk_AutoTest_Sm_GateCondition_UE::StaticClass());
}

// --------------------------------------------------------------------------------------------------------------------
