// Language=angelscript

//============================================================================
// CK INPUT LAYER - AUTOMATION TEST: CONSUME MASKS EVERYTHING BELOW
//============================================================================
//
// The core arbitration rule. Three layers on one source all declare interest
// in the same key: an ordinary layer at priority 100, another at 10, and the
// reserved global-action layer at the bottom. The highest one consumes, so
// the other two must never see the event.
//
// Blocking here is STRUCTURAL: nothing on the lower layers is disabled, no
// flag is set, and neither lower layer knows the top one exists. That is the
// whole argument for the stack over a suspension flag - there is nothing to
// forget to clear.
//
// The two silences are asserted only after a positive: the top layer's fire
// proves routing ran at all, so "the lower layers did not fire" cannot pass
// vacuously on a router that did nothing.
//============================================================================

class UCk_AutoTest_InputLayer_ConsumeMasksLowerLayers : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle             _Owner;
    private FCk_Handle_InputSource _Source;
    private FCk_Handle_InputLayer  _Top;
    private FCk_Handle_InputLayer  _Bottom;
    private FCk_Handle_InputLayer  _GlobalActions;

    private int32 _TopFires    = 0;
    private int32 _BottomFires = 0;
    private int32 _GlobalFires = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        _Top    = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 100));
        _Bottom = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 10));

        Assert_True(ck::IsValid(_Top),    "the higher-priority layer must be created");
        Assert_True(ck::IsValid(_Bottom), "the lower-priority layer must be created");

        utils_input_layer::Request_AddGlobalAction(_Source,
            FCk_Request_InputLayer_AddGlobalAction(EKeys::M));

        _GlobalActions = utils_input_layer::TryGet_GlobalActionLayer(_Source);

        Assert_True(ck::IsValid(_GlobalActions),
            "registering a global action must create the reserved bottom layer immediately");

        utils_input_layer::BindTo_OnCaptureTriggered(_Top,
            FCk_Delegate_InputLayer_CaptureTriggered(this, n"OnTopCaptured"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_input_layer::BindTo_OnCaptureTriggered(_Bottom,
            FCk_Delegate_InputLayer_CaptureTriggered(this, n"OnBottomCaptured"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_input_layer::BindTo_OnCaptureTriggered(_GlobalActions,
            FCk_Delegate_InputLayer_CaptureTriggered(this, n"OnGlobalCaptured"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_input_layer::Request_AddCapture(_Top, FCk_Request_InputLayer_AddCapture(
            utils_input_layer::Make_KeyCapture(EKeys::M, ECk_InputLayer_CaptureBehavior::Consume)));

        utils_input_layer::Request_AddCapture(_Bottom, FCk_Request_InputLayer_AddCapture(
            utils_input_layer::Make_KeyCapture(EKeys::M, ECk_InputLayer_CaptureBehavior::Consume)));

        Add_Step_WaitUntil("all three capture sets are live",             n"Check_CapturesLanded");
        Add_Step(          "inject the press",                            n"Step_InjectPress");
        Add_Step_WaitUntil("the top layer receives it",                   n"Check_TopFired");
        Add_Step_WaitFrames("give a masked layer a chance to fire late",  6);
        Add_Step(          "assert both layers below stayed silent",      n"Step_AssertMasked");

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
            EKeys::M,
            ECk_InputSource_EventType::Pressed);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }

    UFUNCTION()
    private void Step_AssertMasked(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_TopFires, 1,
            "the highest-priority matching layer must receive the event exactly once");
        Assert_Equals_Int(_BottomFires, 0,
            "a Consume capture above must stop the event reaching the layer below");
        Assert_Equals_Int(_GlobalFires, 0,
            "a global action must not fire while a layer above it consumed the key");

        Assert_True(utils_input_layer::TryGet_PressOwner(_Source, EKeys::M) == _Top,
            "the router must record the consuming layer as the owner of the in-flight press");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_CapturesLanded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_layer::Get_NumCaptures(_Top) >= 1 &&
                utils_input_layer::Get_NumCaptures(_Bottom) >= 1 &&
                utils_input_layer::Get_NumCaptures(_GlobalActions) >= 1);
    }

    UFUNCTION()
    private void Check_TopFired(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_TopFires >= 1);
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnTopCaptured(FCk_Handle_InputLayer InLayer, FCk_InputSource_RawEvent InEvent, FCk_InputLayer_Capture InCapture)
    {
        _TopFires += 1;
    }

    UFUNCTION()
    private void OnBottomCaptured(FCk_Handle_InputLayer InLayer, FCk_InputSource_RawEvent InEvent, FCk_InputLayer_Capture InCapture)
    {
        _BottomFires += 1;
    }

    UFUNCTION()
    private void OnGlobalCaptured(FCk_Handle_InputLayer InLayer, FCk_InputSource_RawEvent InEvent, FCk_InputLayer_Capture InCapture)
    {
        _GlobalFires += 1;
    }
}
