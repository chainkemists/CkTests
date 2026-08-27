// Language=angelscript

//============================================================================
// CK INPUT LAYER - AUTOMATION TEST: GLOBAL ACTIONS AT THE BOTTOM OF THE STACK
//============================================================================
//
// A global action is a raw key bound with no binding profile, no intent
// definition and no bake - the prototyping and debug-key surface. It lives on
// a reserved layer pinned to the bottom of its source's stack, so it is
// arbitrated by the same walk as everything else rather than by a side door.
//
// Two legs, and they need each other:
//
//   1. A key nobody above claimed reaches the global action.
//   2. A key an ordinary layer DOES claim reaches that layer and leaves the
//      global-action layer silent - which also proves leg 1 was not just the
//      global layer answering everything.
//============================================================================

class UCk_AutoTest_InputLayer_GlobalActionFiresWhenUnmasked : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle             _Owner;
    private FCk_Handle_InputSource _Source;
    private FCk_Handle_InputLayer  _Gameplay;
    private FCk_Handle_InputLayer  _GlobalActions;

    private int32 _GameplayFires = 0;
    private int32 _GlobalFires   = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        _Gameplay = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 10));

        Assert_True(ck::IsValid(_Gameplay), "the gameplay layer must be created");

        utils_input_layer::Request_AddGlobalAction(_Source,
            FCk_Request_InputLayer_AddGlobalAction(EKeys::G));

        _GlobalActions = utils_input_layer::TryGet_GlobalActionLayer(_Source);

        Assert_True(ck::IsValid(_GlobalActions),
            "registering a global action must create the reserved bottom layer immediately");
        Assert_Equals_Int(utils_input_layer::Get_Priority(_GlobalActions),
            utils_input_layer::Get_GlobalActionPriority(),
            "the global-action layer must sit at the reserved bottom priority");

        utils_input_layer::BindTo_OnCaptureTriggered(_Gameplay,
            FCk_Delegate_InputLayer_CaptureTriggered(this, n"OnGameplayCaptured"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_input_layer::BindTo_OnCaptureTriggered(_GlobalActions,
            FCk_Delegate_InputLayer_CaptureTriggered(this, n"OnGlobalCaptured"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_input_layer::Request_AddCapture(_Gameplay, FCk_Request_InputLayer_AddCapture(
            utils_input_layer::Make_KeyCapture(EKeys::J, ECk_InputLayer_CaptureBehavior::Consume)));

        Add_Step_WaitUntil("both capture sets are live",                     n"Check_CapturesLanded");
        Add_Step(          "inject the unclaimed key",                       n"Step_InjectGlobalKey");
        Add_Step_WaitUntil("the global action receives it",                  n"Check_GlobalFired");
        Add_Step(          "assert only the global action fired, then inject the claimed key", n"Step_AssertGlobalThenInjectClaimed");
        Add_Step_WaitUntil("the gameplay layer receives its own key",        n"Check_GameplayFired");
        Add_Step_WaitFrames("give a late global-action fire a chance",       6);
        Add_Step(          "assert the claimed key never reached the bottom", n"Step_AssertClaimedStoppedAbove");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_InjectGlobalKey(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Keyboard,
            EKeys::G,
            ECk_InputSource_EventType::Pressed);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }

    UFUNCTION()
    private void Step_AssertGlobalThenInjectClaimed(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_GlobalFires, 1,
            "a key no layer above claimed must reach the global action exactly once");
        Assert_Equals_Int(_GameplayFires, 0,
            "a layer must not receive a key it never declared a capture for");

        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Keyboard,
            EKeys::J,
            ECk_InputSource_EventType::Pressed);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }

    UFUNCTION()
    private void Step_AssertClaimedStoppedAbove(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_GameplayFires, 1,
            "the gameplay layer must receive the key it claimed, exactly once");
        Assert_Equals_Int(_GlobalFires, 1,
            "a key consumed above must never reach the global-action layer");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_CapturesLanded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_layer::Get_NumCaptures(_Gameplay) >= 1 &&
                utils_input_layer::Get_NumCaptures(_GlobalActions) >= 1);
    }

    UFUNCTION()
    private void Check_GlobalFired(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_GlobalFires >= 1);
    }

    UFUNCTION()
    private void Check_GameplayFired(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_GameplayFires >= 1);
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnGameplayCaptured(FCk_Handle_InputLayer InLayer, FCk_InputSource_RawEvent InEvent, FCk_InputLayer_Capture InCapture)
    {
        _GameplayFires += 1;
    }

    UFUNCTION()
    private void OnGlobalCaptured(FCk_Handle_InputLayer InLayer, FCk_InputSource_RawEvent InEvent, FCk_InputLayer_Capture InCapture)
    {
        _GlobalFires += 1;
    }
}
