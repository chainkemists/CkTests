// Language=angelscript

//============================================================================
// CK INTENT — AUTOMATION TEST: ONE PRESS PRODUCES EXACTLY ONE EDGE
//============================================================================
//
// The record is written on a fixed 60 Hz cadence over a surface the router
// clears every RENDER frame, and those two do not compose without the pending
// buffer between them. Both failures the buffer exists to prevent are
// invisible to a test that only asks "did the edge arrive":
//
//   - LOSS, above 60 fps: the sampler skips render frames outright, and an
//     event routed on a skipped one is gone before it looks.
//   - DUPLICATION, below 60 fps: a catch-up burst replays the sampler several
//     times in one render frame, and each replay re-reads the same events.
//
// Neither is directly drivable from script — nothing here can dictate the
// render cadence — so this pins the INVARIANT both would break instead: one
// injected press appears in exactly ONE row, and stays that way while the
// sampler keeps running.
//
// The two guards against a vacuous pass are the reason the test is shaped
// this way. Counting only after the edge has been seen means "count == 1"
// cannot pass as "count == 0". Waiting on a NAMED count of further logic
// frames — not a render-frame hop — means the sampler provably kept ticking
// afterwards, at any frame rate, so "no duplicate" is not "nothing happened".
// The held-set check at the end is the third: the sampler is still recording
// this button as down, so it is still looking at it and still declining to
// record a second edge for it.
//============================================================================

class UCk_AutoTest_Intent_NoEdgeLostAcrossSkippedRenderFrames : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;

    private FKey  _SubjectKey;
    private FName _SubjectButtonName;

    private int32 _IndexAtDetect = -1;
    private int32 _SettleFrames  = 10;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        _SubjectKey = EKeys::Y;
        _SubjectButtonName = _SubjectKey.GetKeyName();

        TArray<FKey> PhysicalButtons;
        PhysicalButtons.Add(_SubjectKey);

        _Map     = utils_input_button_map::Add(_Owner, FCk_Fragment_InputButtonMap_ParamsData(PhysicalButtons));
        _Sampler = utils_intent_sampler::Add(_Owner, FCk_Fragment_IntentSampler_ParamsData(120));

        Assert_True(ck::IsValid(_Map),     "the button map must compose for this test to mean anything");
        Assert_True(ck::IsValid(_Sampler), "the sampler must compose for this test to mean anything");

        Add_Step_WaitUntil("the map mints the button and the sampler starts recording", n"Check_Recording");
        Add_Step(          "inject exactly one press",                                  n"Step_InjectOnce");
        Add_Step_WaitUntil("the press edge reaches the record",                         n"Check_EdgeLanded");
        Add_Step(          "capture the frame it landed on",                            n"Step_Capture");
        Add_Step_WaitUntil("ten further logic frames are recorded",                     n"Check_SettleFramesElapsed");
        Add_Step(          "assert exactly one row carries the edge",                   n"Step_AssertExactlyOnce");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_InjectOnce(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Keyboard,
            _SubjectKey,
            ECk_InputSource_EventType::Pressed);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }

    UFUNCTION()
    private void Step_Capture(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(DoCountPressRows(), 1,
            "the press must be on exactly one row the moment it is first observed");

        _IndexAtDetect = utils_intent_sampler::Get_LatestFrame(_Sampler).Get_FrameIndex();

        Assert_True(_IndexAtDetect >= 0,
            "the sampler must have a real latest frame once the edge has landed");
    }

    UFUNCTION()
    private void Step_AssertExactlyOnce(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Latest = utils_intent_sampler::Get_LatestFrame(_Sampler);

        Assert_True(Latest.Get_FrameIndex() >= _IndexAtDetect + _SettleFrames,
            "the sampler must have kept writing rows, or the no-duplicate assertion below proves nothing");

        Assert_Equals_Int(DoCountPressRows(), 1,
            "one injected press is one recorded edge — a replayed catch-up tick must not record it again");

        Assert_True(DoContainsPhysical(Latest.Get_Held(), _SubjectButtonName),
            "the button is still down, so the sampler is still tracking it and still declining to re-edge it");

        Assert_Equals_Int(DoCountReleaseRows(), 0,
            "nothing released the button, so no row may carry a release edge for it");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_Recording(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_button_map::Get_ButtonIdsForKey(_Map, _SubjectKey).Num() >= 1 &&
                utils_intent_sampler::Get_FrameCount(_Sampler) >= 1);
    }

    UFUNCTION()
    private void Check_EdgeLanded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoCountPressRows() >= 1);
    }

    UFUNCTION()
    private void Check_SettleFramesElapsed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_sampler::Get_LatestFrame(_Sampler).Get_FrameIndex() >= _IndexAtDetect + _SettleFrames);
    }

    //------------------------------------------------------------------------

    private int32 DoCountPressRows()
    {
        auto Count = utils_intent_sampler::Get_FrameCount(_Sampler);
        auto Hits = 0;

        for (auto Offset = 0; Offset < Count; Offset++)
        {
            auto Row = utils_intent_sampler::TryGet_FrameAtOffset(_Sampler, Offset);

            if (DoContainsPhysical(Row.Get_Pressed(), _SubjectButtonName))
            { Hits += 1; }
        }

        return Hits;
    }

    private int32 DoCountReleaseRows()
    {
        auto Count = utils_intent_sampler::Get_FrameCount(_Sampler);
        auto Hits = 0;

        for (auto Offset = 0; Offset < Count; Offset++)
        {
            auto Row = utils_intent_sampler::TryGet_FrameAtOffset(_Sampler, Offset);

            if (DoContainsPhysical(Row.Get_Released(), _SubjectButtonName))
            { Hits += 1; }
        }

        return Hits;
    }

    private bool DoContainsPhysical(const TArray<FCk_Input_ButtonId>& InButtons, FName InName)
    {
        for (auto Index = 0; Index < InButtons.Num(); Index++)
        {
            if (InButtons[Index].Get_Tier() != ECk_Input_ButtonTier::Physical)
            { continue; }

            if (InButtons[Index].Get_Name() == InName)
            { return true; }
        }

        return false;
    }
}
