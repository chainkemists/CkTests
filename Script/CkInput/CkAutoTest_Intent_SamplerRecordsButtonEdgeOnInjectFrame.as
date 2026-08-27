// Language=angelscript

//============================================================================
// CK INTENT - AUTOMATION TEST: A PRESS AND ITS RELEASE REACH THE FRAME RECORD
//============================================================================
//
// The record's reason to exist: a press must be readable back AS A BUTTON, on a
// row, after the frame it happened on. Three things are pinned:
//
//   1. The press appears as a Pressed edge carrying the ButtonId the source's
//      map mints for that key - not the key, and not an identity the sampler
//      invented for itself.
//   2. The same row reports the button HELD. Edges and held-ness are separate
//      questions and a record that only answered the first could not tell
//      "tapped" from "still down".
//   3. The release appears as a Released edge on a LATER row, and that row no
//      longer reports it held.
//
// The key is registered as a tier-2 Physical button, which is the tier that
// exists precisely so a synthetic source with no binding profile still has a
// button space. Rows are SEARCHED rather than indexed: which logic frame an
// injection lands on is a property of the sampler's cadence against the
// renderer's, and asserting a specific row would be asserting the frame rate.
//============================================================================

class UCk_AutoTest_Intent_SamplerRecordsButtonEdgeOnInjectFrame : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 12.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;

    private int32 _PressFrameIndex = -1;

    private FKey  _SubjectKey;
    private FName _SubjectButtonName;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        // A tier-2 button's identity IS its key's name, so the expectation is derived rather than spelled
        // a literal would silently stop matching if the key's name ever changed.
        _SubjectKey = EKeys::K;
        _SubjectButtonName = _SubjectKey.GetKeyName();

        TArray<FKey> PhysicalButtons;
        PhysicalButtons.Add(_SubjectKey);

        _Map     = utils_input_button_map::Add(_Owner, FCk_Fragment_InputButtonMap_ParamsData(PhysicalButtons));
        _Sampler = utils_intent_sampler::Add(_Owner, FCk_Fragment_IntentSampler_ParamsData(120));

        Assert_True(ck::IsValid(_Map),     "the button map must compose for this test to mean anything");
        Assert_True(ck::IsValid(_Sampler), "the sampler must compose for this test to mean anything");

        Add_Step_WaitUntil("the map mints K and the sampler starts recording", n"Check_Recording");
        Add_Step(          "inject the press",                                 n"Step_InjectPress");
        Add_Step_WaitUntil("the press edge reaches a row",                     n"Check_PressRecorded");
        Add_Step(          "assert the edge and the held set, then release",   n"Step_AssertPressThenRelease");
        Add_Step_WaitUntil("the release edge reaches a later row",             n"Check_ReleaseRecorded");
        Add_Step(          "assert the release cleared the held set",          n"Step_AssertRelease");

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
    private void Step_AssertPressThenRelease(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Offset = DoFindPressOffset();
        Assert_True(Offset >= 0, "a retained row must carry the press edge");

        auto Row = utils_intent_sampler::TryGet_FrameAtOffset(_Sampler, Offset);

        Assert_True(Row.Get_FrameIndex() >= 0,
            "a row found inside the retained range must carry a real frame index");

        Assert_True(DoContainsPhysical(Row.Get_Held(), _SubjectButtonName),
            "the row that records the press must also report the button held");

        _PressFrameIndex = Row.Get_FrameIndex();

        DoInject(ECk_InputSource_EventType::Released);
    }

    UFUNCTION()
    private void Step_AssertRelease(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Offset = DoFindReleaseOffset();
        Assert_True(Offset >= 0, "a retained row must carry the release edge");

        auto Row = utils_intent_sampler::TryGet_FrameAtOffset(_Sampler, Offset);

        Assert_True(Row.Get_FrameIndex() > _PressFrameIndex,
            "the release must be recorded on a LATER frame than the press, not folded into it");

        Assert_False(DoContainsPhysical(Row.Get_Held(), _SubjectButtonName),
            "a released button must leave the held set, or the record would report it down forever");
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
    private void Check_PressRecorded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoFindPressOffset() >= 0);
    }

    UFUNCTION()
    private void Check_ReleaseRecorded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoFindReleaseOffset() >= 0);
    }

    //------------------------------------------------------------------------

    private void DoInject(ECk_InputSource_EventType InEventType)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Keyboard,
            _SubjectKey,
            InEventType);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }

    private int32 DoFindPressOffset()
    {
        auto Count = utils_intent_sampler::Get_FrameCount(_Sampler);

        for (auto Offset = 0; Offset < Count; Offset++)
        {
            auto Row = utils_intent_sampler::TryGet_FrameAtOffset(_Sampler, Offset);

            if (DoContainsPhysical(Row.Get_Pressed(), _SubjectButtonName))
            { return Offset; }
        }

        return -1;
    }

    private int32 DoFindReleaseOffset()
    {
        auto Count = utils_intent_sampler::Get_FrameCount(_Sampler);

        for (auto Offset = 0; Offset < Count; Offset++)
        {
            auto Row = utils_intent_sampler::TryGet_FrameAtOffset(_Sampler, Offset);

            if (DoContainsPhysical(Row.Get_Released(), _SubjectButtonName))
            { return Offset; }
        }

        return -1;
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
