// Language=angelscript

//============================================================================
// CK INPUT LAYER - AUTOMATION TEST: PRESS/RELEASE PAIRING SURVIVES A POP
//============================================================================
//
// The failure this exists to stop: a layer consumes a key's press, the layer
// is popped while the key is still physically held, and the release then falls
// through to the layer below - which receives a key-up for a press it never
// saw and unlatches state nothing ever latched.
//
// Ownership of a press lives in the ROUTER, keyed by the physical key, not in
// the layers (they stay declarative and would have nowhere to put it). When
// the release arrives the router hands it to the recorded owner and clears the
// entry; when that owner is gone the entry is cleared and the release is
// dropped rather than offered downward.
//
// The final leg re-presses the same key: a "the lower layer stayed at zero"
// assertion is worthless if the lower layer was simply unreachable, so the
// test proves it can still consume that key afterwards.
//============================================================================

class UCk_AutoTest_InputLayer_ReleasePairingSurvivesLayerPop : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle             _Owner;
    private FCk_Handle_InputSource _Source;
    private FCk_Handle_InputLayer  _Modal;
    private FCk_Handle_InputLayer  _Gameplay;

    private int32 _ModalFires    = 0;
    private int32 _GameplayFires = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        _Modal    = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 100));
        _Gameplay = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 10));

        Assert_True(ck::IsValid(_Modal),    "the modal layer must be created");
        Assert_True(ck::IsValid(_Gameplay), "the gameplay layer must be created");

        utils_input_layer::BindTo_OnCaptureTriggered(_Modal,
            FCk_Delegate_InputLayer_CaptureTriggered(this, n"OnModalCaptured"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_input_layer::BindTo_OnCaptureTriggered(_Gameplay,
            FCk_Delegate_InputLayer_CaptureTriggered(this, n"OnGameplayCaptured"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_input_layer::Request_AddCapture(_Modal, FCk_Request_InputLayer_AddCapture(
            utils_input_layer::Make_KeyCapture(EKeys::Q, ECk_InputLayer_CaptureBehavior::Consume)));

        utils_input_layer::Request_AddCapture(_Gameplay, FCk_Request_InputLayer_AddCapture(
            utils_input_layer::Make_KeyCapture(EKeys::Q, ECk_InputLayer_CaptureBehavior::Consume)));

        Add_Step_WaitUntil("both capture sets are live",                   n"Check_CapturesLanded");
        Add_Step(          "press and hold the key",                       n"Step_InjectPress");
        Add_Step_WaitUntil("the modal layer consumes the press",           n"Check_ModalFiredPress");
        Add_Step(          "pop the modal layer mid-hold",                 n"Step_PopModal");
        Add_Step_WaitUntil("the popped layer is gone",                     n"Check_ModalGone");
        Add_Step(          "release the key",                              n"Step_InjectRelease");
        Add_Step_WaitFrames("give an orphaned release a chance to land",   8);
        Add_Step(          "assert nothing below received the release",    n"Step_AssertNoOrphanedRelease");
        Add_Step(          "press the key again",                          n"Step_InjectSecondPress");
        Add_Step_WaitUntil("the gameplay layer now consumes the key",      n"Check_GameplayFired");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_InjectPress(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(ECk_InputSource_EventType::Pressed);
    }

    UFUNCTION()
    private void Step_PopModal(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_input_layer::TryGet_PressOwner(_Source, EKeys::Q) == _Modal,
            "the router must record the modal layer as the owner of the held press");

        utils_entity_lifetime::Request_DestroyEntity(_Modal);
    }

    UFUNCTION()
    private void Step_InjectRelease(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(ECk_InputSource_EventType::Released);
    }

    UFUNCTION()
    private void Step_AssertNoOrphanedRelease(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_ModalFires, 1,
            "the popped layer must not receive anything after it is gone");
        Assert_Equals_Int(_GameplayFires, 0,
            "a release whose press was consumed above must never fall through as an orphaned key-up");

        Assert_True(!ck::IsValid(utils_input_layer::TryGet_PressOwner(_Source, EKeys::Q)),
            "delivering (or dropping) the release must clear the router's ownership entry");
    }

    UFUNCTION()
    private void Step_InjectSecondPress(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(ECk_InputSource_EventType::Pressed);
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_CapturesLanded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_layer::Get_NumCaptures(_Modal) >= 1 &&
                utils_input_layer::Get_NumCaptures(_Gameplay) >= 1);
    }

    UFUNCTION()
    private void Check_ModalFiredPress(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_ModalFires >= 1);
    }

    UFUNCTION()
    private void Check_ModalGone(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(!ck::IsValid(_Modal));
    }

    UFUNCTION()
    private void Check_GameplayFired(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_GameplayFires >= 1);
    }

    //------------------------------------------------------------------------

    private void DoInject(ECk_InputSource_EventType InEventType)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Keyboard,
            EKeys::Q,
            InEventType);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }

    UFUNCTION()
    private void OnModalCaptured(FCk_Handle_InputLayer InLayer, FCk_InputSource_RawEvent InEvent, FCk_InputLayer_Capture InCapture)
    {
        _ModalFires += 1;
    }

    UFUNCTION()
    private void OnGameplayCaptured(FCk_Handle_InputLayer InLayer, FCk_InputSource_RawEvent InEvent, FCk_InputLayer_Capture InCapture)
    {
        _GameplayFires += 1;
    }
}
