// Language=angelscript

//============================================================================
// CK INPUT LAYER - AUTOMATION TEST: PASSTHROUGH ACTS AND KEEPS WALKING
//============================================================================
//
// The other half of the propagation rule. A PassThrough capture is delivered
// exactly like a Consume one - the layer acts - but the walk continues, so a
// layer below can still claim the same key.
//
// This is what lets one layer take part of a device and leave the rest: a
// vehicle layer consuming movement while passing look through is this row,
// declared per capture rather than per layer.
//
// Press ownership goes to the CONSUMER, not to the pass-through layer that
// merely observed the press - that is what makes the eventual release land on
// the layer that is actually holding state for the key.
//============================================================================

class UCk_AutoTest_InputLayer_PassThroughDoesNotMask : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle             _Owner;
    private FCk_Handle_InputSource _Source;
    private FCk_Handle_InputLayer  _Observer;
    private FCk_Handle_InputLayer  _Consumer;

    private int32 _ObserverFires = 0;
    private int32 _ConsumerFires = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        _Observer = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 100));
        _Consumer = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 10));

        Assert_True(ck::IsValid(_Observer), "the pass-through layer must be created");
        Assert_True(ck::IsValid(_Consumer), "the consuming layer must be created");

        utils_input_layer::BindTo_OnCaptureTriggered(_Observer,
            FCk_Delegate_InputLayer_CaptureTriggered(this, n"OnObserverCaptured"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_input_layer::BindTo_OnCaptureTriggered(_Consumer,
            FCk_Delegate_InputLayer_CaptureTriggered(this, n"OnConsumerCaptured"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_input_layer::Request_AddCapture(_Observer, FCk_Request_InputLayer_AddCapture(
            utils_input_layer::Make_KeyCapture(EKeys::P, ECk_InputLayer_CaptureBehavior::PassThrough)));

        utils_input_layer::Request_AddCapture(_Consumer, FCk_Request_InputLayer_AddCapture(
            utils_input_layer::Make_KeyCapture(EKeys::P, ECk_InputLayer_CaptureBehavior::Consume)));

        Add_Step_WaitUntil("both capture sets are live",                 n"Check_CapturesLanded");
        Add_Step(          "inject the press",                           n"Step_InjectPress");
        Add_Step_WaitUntil("the event reaches the layer underneath",     n"Check_ConsumerFired");
        Add_Step(          "assert the pass-through layer acted too",    n"Step_AssertBothActed");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_InjectPress(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Keyboard,
            EKeys::P,
            ECk_InputSource_EventType::Pressed);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }

    UFUNCTION()
    private void Step_AssertBothActed(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_ObserverFires, 1,
            "a PassThrough capture must be delivered to its layer, exactly once");
        Assert_Equals_Int(_ConsumerFires, 1,
            "a PassThrough capture must not mask the layer below it");

        Assert_True(utils_input_layer::TryGet_PressOwner(_Source, EKeys::P) == _Consumer,
            "press ownership belongs to the layer that CONSUMED, not to one that passed through");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_CapturesLanded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_layer::Get_NumCaptures(_Observer) >= 1 &&
                utils_input_layer::Get_NumCaptures(_Consumer) >= 1);
    }

    UFUNCTION()
    private void Check_ConsumerFired(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_ConsumerFires >= 1);
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnObserverCaptured(FCk_Handle_InputLayer InLayer, FCk_InputSource_RawEvent InEvent, FCk_InputLayer_Capture InCapture)
    {
        _ObserverFires += 1;
    }

    UFUNCTION()
    private void OnConsumerCaptured(FCk_Handle_InputLayer InLayer, FCk_InputSource_RawEvent InEvent, FCk_InputLayer_Capture InCapture)
    {
        _ConsumerFires += 1;
    }
}
