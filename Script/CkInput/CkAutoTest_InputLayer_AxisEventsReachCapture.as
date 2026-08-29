// Language=angelscript

//============================================================================
// CK INPUT LAYER - AUTOMATION TEST: ANALOG-AXIS EVENTS MATCH KEY CAPTURES
//============================================================================
//
// Capture matching consults only the KEY, never the event type
// (CkInputLayer_Processor: CatchAll -> true, Key -> FKey equality), so a Key
// capture on EKeys::MouseX must receive AnalogAxis rows verbatim - including
// their analog value. Nothing exercised this at runtime before: every prior
// layer test injects Pressed/Released, and the mouse-look design of the gym
// switchboard's pawn layer (event-driven PassThrough captures on MouseX/Y)
// leans on exactly this behavior.
//
// Also asserted: consuming an axis records NO press ownership (ownership is
// recorded only for Pressed events), so an axis Consume can never wedge a
// key, and a second axis row still routes (no one-shot latching).
//============================================================================

class UCk_AutoTest_InputLayer_AxisEventsReachCapture : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle             _Owner;
    private FCk_Handle_InputSource _Source;
    private FCk_Handle_InputLayer  _Layer;

    private int32 _Fires = 0;
    private float32 _LastAnalogValue = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));
        _Layer  = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 100));

        Assert_True(ck::IsValid(_Layer), "the axis-capturing layer must be created");

        utils_input_layer::BindTo_OnCaptureTriggered(_Layer,
            FCk_Delegate_InputLayer_CaptureTriggered(this, n"OnCaptured"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_input_layer::Request_AddCapture(_Layer, FCk_Request_InputLayer_AddCapture(
            utils_input_layer::Make_KeyCapture(EKeys::MouseX, ECk_InputLayer_CaptureBehavior::Consume)));

        Add_Step_WaitUntil("the axis capture is live",              n"Check_CaptureLanded");
        Add_Step(          "inject the first axis row",             n"Step_InjectFirstAxis");
        Add_Step_WaitUntil("the layer receives it",                 n"Check_FirstFired");
        Add_Step(          "assert value fidelity and no ownership", n"Step_AssertFirstDelivery");
        Add_Step(          "inject a second axis row",              n"Step_InjectSecondAxis");
        Add_Step_WaitUntil("the second row routes too",             n"Check_SecondFired");
        Add_Step(          "assert the second value arrived",       n"Step_AssertSecondDelivery");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_InjectFirstAxis(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Keyboard,
            EKeys::MouseX,
            ECk_InputSource_EventType::AnalogAxis);
        Event.Set_AnalogValue(0.75f);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }

    UFUNCTION()
    private void Step_AssertFirstDelivery(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_Fires, 1,
            "the Key capture on MouseX must receive the AnalogAxis row exactly once");
        Assert_True(Math::IsNearlyEqual(_LastAnalogValue, 0.75f, 0.0001f),
            "the delivered row must carry the injected analog value verbatim");
        Assert_True(ck::Is_NOT_Valid(utils_input_layer::TryGet_PressOwner(_Source, EKeys::MouseX)),
            "consuming an AnalogAxis row must record no press ownership - only Pressed events do");
    }

    UFUNCTION()
    private void Step_InjectSecondAxis(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Keyboard,
            EKeys::MouseX,
            ECk_InputSource_EventType::AnalogAxis);
        Event.Set_AnalogValue(-2.5f);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }

    UFUNCTION()
    private void Step_AssertSecondDelivery(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_Fires, 2,
            "a second axis row must route - an axis Consume must not latch or wedge the key");
        Assert_True(Math::IsNearlyEqual(_LastAnalogValue, -2.5f, 0.0001f),
            "the second delivered row must carry ITS value, including sign");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_CaptureLanded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_layer::Get_NumCaptures(_Layer) >= 1);
    }

    UFUNCTION()
    private void Check_FirstFired(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_Fires >= 1);
    }

    UFUNCTION()
    private void Check_SecondFired(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_Fires >= 2);
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnCaptured(FCk_Handle_InputLayer InLayer, FCk_InputSource_RawEvent InEvent, FCk_InputLayer_Capture InCapture)
    {
        _Fires += 1;
        _LastAnalogValue = InEvent.Get_AnalogValue();
    }
}
