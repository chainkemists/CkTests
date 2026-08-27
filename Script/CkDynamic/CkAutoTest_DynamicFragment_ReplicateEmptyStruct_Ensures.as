// Language=angelscript

//============================================================================
// CK DYNAMIC - AUTOMATION TEST: REPLICATING A TAG / SIZE-0 STRUCT ENSURES
//============================================================================
//
// Adding a dynamic fragment whose struct carries no reflected properties with
// ECk_Replication::Replicates must trip the size-0 guard ensure in
// DoSetupReplication - replicating a payload with no data is meaningless.
//
// Add_Fragment returns an invalid handle on rejection, and the AS binding turns that into a
// FAngelscriptManager::Throw (CkDynamic_Utils.cpp:679) which UNWINDS THE REST OF DoBeginPlay.
// Anything after the rejected call - including FinishSuccess - never runs, which is why the
// verdict is armed on a timer BEFORE the call rather than written after it.
//
// The timer also buys the real assertion: CanSetupReplication validates before Add_Fragment
// performs its first mutation, so a rejected replicated tag must leave NOTHING behind - no
// local-only named storage, no presence marker. That is what is checked once the stack unwinds.
//============================================================================

class UCk_AutoTest_DynamicFragment_ReplicateEmptyStruct_Ensures : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 2.0f;

    private FCk_Handle _Entity;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Entity = InHandle;

        ScheduleSettle(0.2f, n"Stage_Assert");

        auto TagPayload = FCk_Fragment_DynamicTest_TagPayload();
        _Entity.Add_Fragment(TagPayload, ECk_Replication::Replicates);
    }

    UFUNCTION()
    private void Stage_Assert(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto _CkPerfScope = ck::ScopedStat();

        Assert_True(_Entity.Has_Fragment(FCk_Fragment_DynamicTest_TagPayload) == false,
            "the rejected replicated tag left no fragment behind");

        FinishSuccess();
    }

    private void ScheduleSettle(float InSeconds, FName InHandlerName)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(InSeconds));
        Params.Set_StartingState(ECk_Timer_State::Running)
              .Set_Behavior(ECk_Timer_Behavior::StopOnDone);
        auto Timer = utils_timer::Add(_Entity, Params);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, InHandlerName));
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR - registers the deliberate-ensure log pattern.
//============================================================================

class ACk_AutoTest_DynamicFragment_ReplicateEmptyStruct_Ensures_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_DynamicFragment_ReplicateEmptyStruct_Ensures;
    default _TimeoutSeconds = 2.0f;

    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("carries no data and is meaningless");
        // The AS binding throws on the rejected result, and that throw logs at Error severity as a
        // message line PLUS two callstack lines. All of them have to be expected or the harness
        // auto-fails on the deliberate diagnostic. Matched without the line/column so that editing
        // this file cannot silently un-expect the callstack.
        Out.Add("Dynamic Fragment Add rejected invalid input");
        Out.Add("CkAutoTest_DynamicFragment_ReplicateEmptyStruct_Ensures");
        Out.Add("DoBeginPlay_Implementation");
        return Out;
    }
}
