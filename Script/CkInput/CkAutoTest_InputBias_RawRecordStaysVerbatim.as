// Language=angelscript

//============================================================================
// CK INPUT BIAS - AUTOMATION TEST: CONDITIONING NEVER REWRITES THE RAW ROW
//============================================================================
//
// The whole reason conditioned values live in their own state instead of
// being applied in place is that the transform is lossy: a deadzone maps an
// entire band onto zero, so a row conditioned in place can never be read back
// as the physical fact or re-conditioned by a later retune.
//
// Asserting that from gameplay is not enough - the inbox is drained by the
// router every frame, so gameplay can only ever see an empty one. The proof
// has to come from INSIDE the routing pass, which is what the observing layer
// is for: it receives the row the router is delivering, on the same frame,
// AFTER conditioning has already run over that inbox. If the stage had
// touched the row, this is where it would show.
//
// The bias is deliberately violent - inverted, a third of the range dead, a
// square curve, quadruple gain - so the conditioned value and the raw one
// cannot coincide by accident.
//============================================================================

class UCk_AutoTest_InputBias_RawRecordStaysVerbatim : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle             _Owner;
    private FCk_Handle_InputSource _Source;
    private FCk_Handle_InputBias   _Bias;
    private FCk_Handle_InputLayer  _Observer;

    private int32 _DeliveredCount   = 0;
    private float _DeliveredRawValue = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        auto Row = FCk_InputBias_AxisBias(EKeys::Gamepad_LeftX);
        Row.Set_Inversion(ECk_InputBias_AxisInversion::Inverted);
        Row.Set_Deadzone(0.3f);
        Row.Set_Exponent(2.0f);
        Row.Set_Sensitivity(4.0f);

        auto Rows = TArray<FCk_InputBias_AxisBias>();
        Rows.Add(Row);

        _Bias = utils_input_bias::Add(_Owner, FCk_Fragment_InputBias_ParamsData(Rows));

        Assert_True(ck::IsValid(_Bias),
            "the bias must compose for this test to mean anything");

        _Observer = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 100));

        Assert_True(ck::IsValid(_Observer),
            "the observing layer must be created");

        utils_input_layer::BindTo_OnCaptureTriggered(_Observer,
            FCk_Delegate_InputLayer_CaptureTriggered(this, n"OnObserverCaptured"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_input_layer::Request_AddCapture(_Observer, FCk_Request_InputLayer_AddCapture(
            utils_input_layer::Make_CatchAllCapture(ECk_InputLayer_CaptureBehavior::PassThrough)));

        Add_Step_WaitUntil("the observer's catch-all capture is live",   n"Check_CaptureLanded");
        Add_Step(          "inject a heavily biased axis sample",        n"Step_InjectAxis");
        Add_Step_WaitUntil("the router delivers the row",                n"Check_RowDelivered");
        Add_Step(          "assert the delivered row is verbatim",       n"Step_AssertRawSurvived");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_InjectAxis(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Gamepad,
            EKeys::Gamepad_LeftX,
            ECk_InputSource_EventType::AnalogAxis);

        Event.Set_AnalogValue(0.8f);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }

    UFUNCTION()
    private void Step_AssertRawSurvived(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_DeliveredCount, 1,
            "the observing layer must have received the axis row exactly once");
        Assert_Equals_Float(_DeliveredRawValue, 0.8f, 0.0001f,
            "the row the router delivered - after conditioning ran over that same inbox - must carry the value the producer wrote");

        Assert_Equals_Float(utils_input_bias::Get_LastRawAxisValue(_Bias, EKeys::Gamepad_LeftX), 0.8f, 0.0001f,
            "the conditioned state keeps the raw half of the sample verbatim beside the conditioned one");

        // invert -> 0.8 dead-banded to (0.8-0.3)/0.7 -> squared -> x4, sign restored
        Assert_Equals_Float(utils_input_bias::Get_ConditionedAxisValue(_Bias, EKeys::Gamepad_LeftX), -2.0408f, 0.001f,
            "the conditioned half must carry the biased value");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_CaptureLanded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_layer::Get_NumCaptures(_Observer) >= 1);
    }

    UFUNCTION()
    private void Check_RowDelivered(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_DeliveredCount >= 1);
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnObserverCaptured(FCk_Handle_InputLayer InLayer, FCk_InputSource_RawEvent InEvent, FCk_InputLayer_Capture InCapture)
    {
        _DeliveredCount += 1;
        _DeliveredRawValue = InEvent.Get_AnalogValue();
    }
}
