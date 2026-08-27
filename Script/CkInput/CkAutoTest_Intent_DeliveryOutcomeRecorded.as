// Language=angelscript

//============================================================================
// CK INTENT - AUTOMATION TEST: THE ROW SAYS WHAT THE ROUTER DID
//============================================================================
//
// A record of presses without their fate is ambiguous in exactly the way that
// matters: "the player pressed Escape" and "the player pressed Escape and a
// modal ate it" are the same row unless the outcome rides along. So the record
// carries the router's verdict per event, and both verdicts are pinned here
// against the SAME source in the SAME session:
//
//   - a key a layer captures with Consume is recorded ConsumedByLayer, and the
//     row names THAT layer - not merely "someone consumed it";
//   - a key no layer captures walks off the bottom and is recorded
//     PassedThrough.
//
// The two are asserted together on purpose. Either one alone would also pass
// against an implementation that stamped every event with one constant.
//============================================================================

class UCk_AutoTest_Intent_DeliveryOutcomeRecorded : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 12.0f;

    private FCk_Handle               _Owner;
    private FCk_Handle_InputSource   _Source;
    private FCk_Handle_InputLayer    _Layer;
    private FCk_Handle_IntentSampler _Sampler;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        _Layer = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 50));
        Assert_True(ck::IsValid(_Layer), "the capturing layer must be created");

        _Sampler = utils_intent_sampler::Add(_Owner, FCk_Fragment_IntentSampler_ParamsData(120));
        Assert_True(ck::IsValid(_Sampler), "the sampler must compose for this test to mean anything");

        utils_input_layer::Request_AddCapture(_Layer, FCk_Request_InputLayer_AddCapture(
            utils_input_layer::Make_KeyCapture(EKeys::J, ECk_InputLayer_CaptureBehavior::Consume)));

        Add_Step_WaitUntil("the capture is live and the sampler is recording", n"Check_Ready");
        Add_Step(          "inject the captured key",                          n"Step_InjectCaptured");
        Add_Step_WaitUntil("the consumed outcome reaches a row",               n"Check_ConsumedRecorded");
        Add_Step(          "assert the row names the consuming layer",         n"Step_AssertConsumed");
        Add_Step(          "inject a key nothing captures",                    n"Step_InjectUncaptured");
        Add_Step_WaitUntil("the passed-through outcome reaches a row",         n"Check_PassedRecorded");
        Add_Step(          "assert it fell through with no owner named",       n"Step_AssertPassedThrough");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_InjectCaptured(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(EKeys::J);
    }

    UFUNCTION()
    private void Step_InjectUncaptured(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(EKeys::U);
    }

    UFUNCTION()
    private void Step_AssertConsumed(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Offset = DoFindOutcomeOffset(EKeys::J, ECk_InputLayer_DeliveryOutcome::ConsumedByLayer);
        Assert_True(Offset >= 0, "a retained row must record the captured key as consumed");

        auto Row = utils_intent_sampler::TryGet_FrameAtOffset(_Sampler, Offset);
        auto Routed = Row.Get_RoutedEvents();
        auto Found = false;

        for (auto Index = 0; Index < Routed.Num(); Index++)
        {
            if (Routed[Index].Get_Event().Get_Key() != EKeys::J)
            { continue; }

            Assert_True(Routed[Index].Get_ConsumingLayer() == _Layer,
                "a consumed event must name the layer that ended the walk, not just report that one did");

            Found = true;
        }

        Assert_True(Found, "the row that reported the outcome must still hold the event it belongs to");
    }

    UFUNCTION()
    private void Step_AssertPassedThrough(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Offset = DoFindOutcomeOffset(EKeys::U, ECk_InputLayer_DeliveryOutcome::PassedThrough);
        Assert_True(Offset >= 0, "a key no layer captures must be recorded as having passed through");

        auto Row = utils_intent_sampler::TryGet_FrameAtOffset(_Sampler, Offset);
        auto Routed = Row.Get_RoutedEvents();

        for (auto Index = 0; Index < Routed.Num(); Index++)
        {
            if (Routed[Index].Get_Event().Get_Key() != EKeys::U)
            { continue; }

            Assert_True(ck::Is_NOT_Valid(Routed[Index].Get_ConsumingLayer()),
                "nothing ended the walk, so there is no layer for the row to name");
        }
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_layer::Get_NumCaptures(_Layer) >= 1 &&
                utils_intent_sampler::Get_FrameCount(_Sampler) >= 1);
    }

    UFUNCTION()
    private void Check_ConsumedRecorded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoFindOutcomeOffset(EKeys::J, ECk_InputLayer_DeliveryOutcome::ConsumedByLayer) >= 0);
    }

    UFUNCTION()
    private void Check_PassedRecorded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoFindOutcomeOffset(EKeys::U, ECk_InputLayer_DeliveryOutcome::PassedThrough) >= 0);
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

    private int32 DoFindOutcomeOffset(FKey InKey, ECk_InputLayer_DeliveryOutcome InOutcome)
    {
        auto Count = utils_intent_sampler::Get_FrameCount(_Sampler);

        for (auto Offset = 0; Offset < Count; Offset++)
        {
            auto Row = utils_intent_sampler::TryGet_FrameAtOffset(_Sampler, Offset);
            auto Routed = Row.Get_RoutedEvents();

            for (auto Index = 0; Index < Routed.Num(); Index++)
            {
                if (Routed[Index].Get_Event().Get_Key() != InKey)
                { continue; }

                if (Routed[Index].Get_Outcome() != InOutcome)
                { continue; }

                return Offset;
            }
        }

        return -1;
    }
}
