// Language=angelscript

//============================================================================
// CK INPUT LAYER - AUTOMATION TEST: A CAPTURE EDIT NEVER LANDS MID-PASS
//============================================================================
//
// Capture edits are deferred requests, which buys the routing pass an
// IMMUTABLE capture set: a modal opened by this frame's Escape does not go on
// to swallow the rest of this frame's input, and the router never has to guard
// against the stack changing underneath it while it walks.
//
// Proving that needs the edit to be made from INSIDE a routing pass, which is
// why two events are injected together. A catch-all pass-through probe at the
// top of the stack sees the first one and, from its delegate, asks a lower
// layer to start capturing the SECOND event's key. The second event is routed
// in that same pass - if the edit were immediate the lower layer would take
// it. It must not; the same key must only be captured once the edit has
// drained and a LATER pass routes it.
//
// The trailing re-injection is what makes the silence meaningful: without it,
// a lower layer that could never fire at all would pass this test.
//============================================================================

class UCk_AutoTest_InputLayer_CaptureEditLandsNextFrame : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle             _Owner;
    private FCk_Handle_InputSource _Source;
    private FCk_Handle_InputLayer  _Probe;
    private FCk_Handle_InputLayer  _Late;

    private int32 _ProbeFires   = 0;
    private int32 _LateFires    = 0;
    private bool  _EditEnqueued = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        _Probe = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 100));
        _Late  = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 10));

        Assert_True(ck::IsValid(_Probe), "the probe layer must be created");
        Assert_True(ck::IsValid(_Late),  "the late-capturing layer must be created");

        utils_input_layer::BindTo_OnCaptureTriggered(_Probe,
            FCk_Delegate_InputLayer_CaptureTriggered(this, n"OnProbeCaptured"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_input_layer::BindTo_OnCaptureTriggered(_Late,
            FCk_Delegate_InputLayer_CaptureTriggered(this, n"OnLateCaptured"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_input_layer::Request_AddCapture(_Probe, FCk_Request_InputLayer_AddCapture(
            utils_input_layer::Make_CatchAllCapture(ECk_InputLayer_CaptureBehavior::PassThrough)));

        Add_Step_WaitUntil("the probe's catch-all capture is live",             n"Check_ProbeCaptureLanded");
        Add_Step(          "inject both events in one batch",                   n"Step_InjectBothEvents");
        Add_Step_WaitUntil("both events have been routed",                      n"Check_BothEventsRouted");
        Add_Step(          "assert the mid-pass edit did not take effect",      n"Step_AssertEditNotVisibleInPass");
        Add_Step_WaitUntil("the deferred edit drains onto the layer",           n"Check_LateCaptureLanded");
        Add_Step(          "assert the old event was not re-delivered, then reinject", n"Step_AssertNoReplayAndReinject");
        Add_Step_WaitUntil("a later pass honours the new capture",              n"Check_LateFired");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_InjectBothEvents(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(utils_input_layer::Get_NumCaptures(_Late), 0,
            "the lower layer must start with no captures for this test to mean anything");

        DoInject(EKeys::N);
        DoInject(EKeys::B);
    }

    UFUNCTION()
    private void Step_AssertEditNotVisibleInPass(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_EditEnqueued,
            "the probe must have enqueued the capture edit from inside the routing pass");
        Assert_Equals_Int(_LateFires, 0,
            "a capture added during a routing pass must not capture an event routed in that same pass");
    }

    UFUNCTION()
    private void Step_AssertNoReplayAndReinject(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_LateFires, 0,
            "a drained capture edit must not retroactively deliver an event that was already routed");

        DoInject(EKeys::B);
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_ProbeCaptureLanded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_layer::Get_NumCaptures(_Probe) >= 1);
    }

    UFUNCTION()
    private void Check_BothEventsRouted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_ProbeFires >= 2);
    }

    UFUNCTION()
    private void Check_LateCaptureLanded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_layer::Get_HasCaptureForKey(_Late, ECk_InputLayer_CaptureMatch::Key, EKeys::B));
    }

    UFUNCTION()
    private void Check_LateFired(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_LateFires >= 1);
    }

    //------------------------------------------------------------------------

    private void DoInject(FKey InKey)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Keyboard,
            InKey,
            ECk_InputSource_EventType::Pressed);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }

    UFUNCTION()
    private void OnProbeCaptured(FCk_Handle_InputLayer InLayer, FCk_InputSource_RawEvent InEvent, FCk_InputLayer_Capture InCapture)
    {
        _ProbeFires += 1;

        if (_EditEnqueued)
        { return; }

        if (!(InEvent.Get_Key() == EKeys::N))
        { return; }

        _EditEnqueued = true;

        utils_input_layer::Request_AddCapture(_Late, FCk_Request_InputLayer_AddCapture(
            utils_input_layer::Make_KeyCapture(EKeys::B, ECk_InputLayer_CaptureBehavior::Consume)));
    }

    UFUNCTION()
    private void OnLateCaptured(FCk_Handle_InputLayer InLayer, FCk_InputSource_RawEvent InEvent, FCk_InputLayer_Capture InCapture)
    {
        _LateFires += 1;
    }
}
