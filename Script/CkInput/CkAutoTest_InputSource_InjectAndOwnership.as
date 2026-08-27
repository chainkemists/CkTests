// Language=angelscript

//============================================================================
// CK INPUT SOURCE - AUTOMATION TEST: SYNTHETIC INJECT + DEVICE-OWNERSHIP REJECTION
//============================================================================
//
// Two contracts of the raw input layer, pinned together because the second
// needs the first's source entity to prove it left no partial state:
//
//   1. INJECT ROUND-TRIP. Request_InjectRawEvent is the single append surface
//      - the Slate writer, tooling and this test all use it - so a row that
//      goes in through it must come back out of the inbox byte-for-byte.
//      Every field is asserted, not just the key: an event whose device class
//      or ordering provenance is lost is indistinguishable from a correct one
//      until a consumer tries to order a chord and silently gets it wrong.
//
//   2. INVALID ASSIGNMENT IS ATOMIC. Assigning a device to a source that does
//      not exist must reject before anything is enqueued, report
//      Failed_NotEnqueued to the caller rather than stranding it, and leave
//      no device claimed anywhere in the world.
//
// The inbox is asserted from the completion delegate rather than from a frame
// count: the append is deferred to the feature's HandleRequests processor, and
// completion firing IS the drain having happened.
//============================================================================

class UCk_AutoTest_InputSource_InjectAndOwnership : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle _Owner;
    private FCk_Handle_InputSource _Source;

    private int _InjectFireCount = 0;
    private int _RejectFireCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto Params = FCk_Fragment_InputSource_ParamsData(0);
        _Source = utils_input_source::Add(_Owner, Params);

        Assert_True(ck::IsValid(_Source),
            "InputSource Add should return a valid FCk_Handle_InputSource");
        Assert_Equals_Int(utils_input_source::Get_LocalPlayerIndex(_Source), 0,
            "a freshly added InputSource reports the local player index it was composed with");
        Assert_Equals_Int(utils_input_source::Get_NumPendingRawEvents(_Source), 0,
            "a freshly added InputSource starts with an empty inbox");
        Assert_Equals_Int(utils_input_source::Get_OwnedDevices(_Source).Num(), 0,
            "a freshly added InputSource owns no devices until one is explicitly assigned");

        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Gamepad,
            EKeys::Gamepad_LeftX,
            ECk_InputSource_EventType::AnalogAxis);

        Event.Set_OrderingFidelity(ECk_InputSource_OrderingFidelity::SubFrameOrdered);
        Event.Set_AnalogValue(0.75f);
        Event.Set_RawDeviceUserIndex(3);

        auto InjectRequest = FCk_Request_InputSource_InjectRawEvent(Event);

        utils_input_source::Request_InjectRawEvent(_Source, InjectRequest,
            FCk_Delegate_Request_OnCompleted(this, n"OnInjectCompleted"));
    }

    UFUNCTION()
    private void OnInjectCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (IsFinished()) { return; }

        _InjectFireCount += 1;

        Assert_True(InResult == ECk_Request_OperationResult::Succeeded,
            f"a drained inject must complete with Succeeded (got {InResult})");
        Assert_True(InRequestOwner == _Source,
            "completion must report the input source the event was injected into");

        auto Pending = utils_input_source::Get_PendingRawEvents(_Source);

        Assert_Equals_Int(Pending.Num(), 1,
            "the injected event must be in the inbox once completion has fired");

        if (Pending.Num() != 1)
        {
            FinishFailure("inbox did not receive the injected event - the remaining field assertions cannot run");
            return;
        }

        auto Row = Pending[0];

        Assert_True(Row.Get_DeviceClass() == ECk_InputSource_DeviceClass::Gamepad,
            f"device class must survive the round trip (got {Row.Get_DeviceClass()})");
        Assert_True(Row.Get_Key() == EKeys::Gamepad_LeftX,
            "key must survive the round trip");
        Assert_True(Row.Get_EventType() == ECk_InputSource_EventType::AnalogAxis,
            f"event type must survive the round trip (got {Row.Get_EventType()})");
        Assert_True(Row.Get_OrderingFidelity() == ECk_InputSource_OrderingFidelity::SubFrameOrdered,
            f"per-event ordering provenance must survive the round trip (got {Row.Get_OrderingFidelity()})");
        Assert_True(Math::IsNearlyEqual(Row.Get_AnalogValue(), 0.75f, 0.0001f),
            f"the analog value must be recorded verbatim (got {Row.Get_AnalogValue()})");
        Assert_Equals_Int(Row.Get_RawDeviceUserIndex(), 3,
            "the raw device user index must survive the round trip");

        DoRunInvalidAssignmentLeg();

        // MUST stay a settle: the next hop asserts each delegate fired EXACTLY once and both counts are
        // already 1 here. There is no condition to wait for - the window exists to give a second,
        // erroneous fire a chance to arrive.
        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnAssignRejected(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (IsFinished()) { return; }

        _RejectFireCount += 1;

        Assert_True(InResult == ECk_Request_OperationResult::Failed_NotEnqueued,
            f"an assignment rejected before enqueue must report Failed_NotEnqueued (got {InResult})");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_InjectFireCount, 1, "the inject completion delegate must fire exactly once");
        Assert_Equals_Int(_RejectFireCount, 1, "the rejected assignment must complete exactly once");

        FinishSuccess();
    }

    private void DoRunInvalidAssignmentLeg()
    {
        FCk_Handle_InputSource InvalidSource;

        Assert_True(!ck::IsValid(InvalidSource),
            "a default-constructed InputSource handle must be invalid for this leg to mean anything");

        auto DeviceId = FCk_InputSource_DeviceId(ECk_InputSource_DeviceClass::Gamepad, 3);
        auto AssignRequest = FCk_Request_InputSource_AssignDevice(DeviceId);

        utils_input_source::Request_AssignDevice(InvalidSource, AssignRequest,
            FCk_Delegate_Request_OnCompleted(this, n"OnAssignRejected"));

        Assert_Equals_Int(_RejectFireCount, 1,
            "rejection happens before enqueue, so the delegate must have fired on this stack");
        Assert_Equals_Int(utils_input_source::Get_OwnedDevices(_Source).Num(), 0,
            "a rejected assignment must not leak a device claim onto any other source");
        Assert_True(!utils_input_source::Get_OwnsDevice(_Source, DeviceId),
            "the live source must not own the device the rejected assignment named");
        Assert_True(!ck::IsValid(utils_input_source::TryGet_SourceOwningDevice(_Owner, DeviceId)),
            "no source anywhere in the world may claim a device whose assignment was rejected");
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR - registers the deliberate-ensure log pattern.
//============================================================================

class ACk_AutoTest_InputSource_InjectAndOwnership_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_InputSource_InjectAndOwnership;
    default _TimeoutSeconds = 4.0f;

    // The invalid-assignment leg deliberately trips the CK_ENSURE_IF_NOT guarding
    // Request_AssignDevice; register the substring so the automation framework does
    // not auto-fail the run on it.
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("Request_AssignDevice");
        return Out;
    }
}
