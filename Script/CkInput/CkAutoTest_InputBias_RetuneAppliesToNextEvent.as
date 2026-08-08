// Language=angelscript

//============================================================================
// CK INPUT BIAS — AUTOMATION TEST: A RETUNE CONDITIONS THE NEXT EVENT, NOT THE LAST
//============================================================================
//
// The conditioning table is runtime-mutable — a sensitivity slider moves it
// while the player is holding the stick — and that makes "when does it take
// effect" a contract rather than an implementation detail.
//
// It is a deferred request, so the answer is: the next event to arrive. Three
// distinct moments are pinned, because two of them are where an "obvious"
// implementation goes wrong:
//
//   1. On the calling stack the table has not moved at all (an immediate
//      mutator would have changed it here, and would then be able to change
//      it in the middle of a conditioning pass).
//   2. Once the retune HAS drained, the sample already taken is unchanged —
//      conditioned state is a record of a past event, not a live formula, so
//      re-deriving it under new settings would fabricate an input the device
//      never sent.
//   3. The next event arrives conditioned by the new row.
//
// The raw half is asserted at the end for the same reason it is asserted
// everywhere else: retuning must never disturb the record.
//============================================================================

class UCk_AutoTest_InputBias_RetuneAppliesToNextEvent : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle             _Owner;
    private FCk_Handle_InputSource _Source;
    private FCk_Handle_InputBias   _Bias;

    private int32 _RetuneFires = 0;
    private bool  _RetuneSucceeded = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));
        _Bias   = utils_input_bias::Add(_Owner, FCk_Fragment_InputBias_ParamsData());

        Assert_True(ck::IsValid(_Bias),
            "the bias must compose for this test to mean anything");

        Add_Step(          "inject a sample under the identity",       n"Step_InjectFirst");
        Add_Step_WaitUntil("the first sample lands",                   n"Check_SampledFirst");
        Add_Step(          "assert identity, then enqueue a retune",   n"Step_AssertIdentityThenRetune");
        Add_Step_WaitUntil("the retune drains onto the table",         n"Check_RetuneLanded");
        Add_Step(          "assert the old sample was not rewritten",  n"Step_AssertNoRetroactiveRewrite");
        Add_Step_WaitUntil("the second sample lands",                  n"Check_SampledSecond");
        Add_Step(          "assert the new bias conditioned it",       n"Step_AssertNewBiasApplied");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_InjectFirst(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInjectAxis(0.5f);
    }

    UFUNCTION()
    private void Step_AssertIdentityThenRetune(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Float(utils_input_bias::Get_ConditionedAxisValue(_Bias, EKeys::Gamepad_LeftX), 0.5f, 0.0001f,
            "with no declared bias the first sample must pass through untouched");

        auto Row = FCk_InputBias_AxisBias(EKeys::Gamepad_LeftX);
        Row.Set_Sensitivity(2.0f);

        utils_input_bias::Request_SetAxisBias(_Bias, FCk_Request_InputBias_SetAxisBias(Row),
            FCk_Delegate_Request_OnCompleted(this, n"OnRetuneCompleted"));

        Assert_Equals_Int(utils_input_bias::Get_AxisBiases(_Bias).Num(), 0,
            "a retune is deferred — the table must not have moved on the calling stack");
        Assert_Equals_Int(_RetuneFires, 0,
            "an accepted retune completes when it DRAINS, not when it is enqueued");
    }

    UFUNCTION()
    private void Step_AssertNoRetroactiveRewrite(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_RetuneFires, 1,
            "the drained retune must have completed exactly once");
        Assert_True(_RetuneSucceeded,
            "a retune within range must complete Succeeded");

        auto Declared = utils_input_bias::TryGet_AxisBias(_Bias, EKeys::Gamepad_LeftX);
        Assert_Equals_Float(Declared.Get_Sensitivity(), 2.0f, 0.0001f,
            "the drained retune must be readable back from the live table");

        Assert_Equals_Float(utils_input_bias::Get_ConditionedAxisValue(_Bias, EKeys::Gamepad_LeftX), 0.5f, 0.0001f,
            "conditioned state records a past event — a retune must not re-derive it and invent an input the device never sent");

        DoInjectAxis(0.6f);
    }

    UFUNCTION()
    private void Step_AssertNewBiasApplied(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Float(utils_input_bias::Get_ConditionedAxisValue(_Bias, EKeys::Gamepad_LeftX), 1.2f, 0.001f,
            "the first event AFTER the retune must be conditioned by it");
        Assert_Equals_Float(utils_input_bias::Get_LastRawAxisValue(_Bias, EKeys::Gamepad_LeftX), 0.6f, 0.0001f,
            "retuning must not disturb the raw value the producer reported");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_SampledFirst(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(Math::IsNearlyEqual(
            utils_input_bias::Get_LastRawAxisValue(_Bias, EKeys::Gamepad_LeftX), 0.5f, 0.0001f));
    }

    UFUNCTION()
    private void Check_RetuneLanded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_bias::Get_AxisBiases(_Bias).Num() >= 1);
    }

    UFUNCTION()
    private void Check_SampledSecond(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(Math::IsNearlyEqual(
            utils_input_bias::Get_LastRawAxisValue(_Bias, EKeys::Gamepad_LeftX), 0.6f, 0.0001f));
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnRetuneCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (IsFinished()) { return; }

        _RetuneFires += 1;
        _RetuneSucceeded = InResult == ECk_Request_OperationResult::Succeeded;

        Assert_True(InRequestOwner == _Bias,
            "completion must report the bias the retune was enqueued on");
    }

    private void DoInjectAxis(float InAnalogValue)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Gamepad,
            EKeys::Gamepad_LeftX,
            ECk_InputSource_EventType::AnalogAxis);

        Event.Set_AnalogValue(InAnalogValue);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }
}
