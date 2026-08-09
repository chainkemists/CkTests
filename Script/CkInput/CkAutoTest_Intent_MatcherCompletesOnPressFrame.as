// Language=angelscript

//============================================================================
// CK INTENT — AUTOMATION TEST: A MOTION COMPLETES ON THE PRESS FRAME
//============================================================================
//
// The latency claim the whole module is shaped around, asserted as an
// EQUALITY rather than as "eventually": a quarter-circle-punch completes on
// the very record frame that carries the punch's press edge, not on the one
// after it and not once a timer expired.
//
// That is only possible because the matcher scans BACKWARDS. A forward
// matcher would have to notice 2, then 3, then wait to see whether 6+punch
// ever arrives — and the frame it finally answers on is the frame after the
// press at best. Here the press is the question and the record behind it is
// the answer, so the two share a frame index by construction.
//
// The directions are driven as ANALOG through the source pipeline, exactly
// the way the octant tests drive them, because the octant on a row is
// hysteresis-damped state the sampler derives and not something a test can
// hand it directly. The punch is a tier-2 Physical button: the tier that
// exists so a synthetic source with no binding profile still has a button
// space.
//
// The set is baked IN-TEST through the same parse-then-bake pipeline a game
// uses — there is one parser, and a fixture that assembled a set beside it
// would be proving something no shipped move ever goes through.
//============================================================================

class UCk_AutoTest_Intent_MatcherCompletesOnPressFrame : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 25.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputBias      _Bias;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;
    private FCk_Handle_InputLayer     _Layer;
    private FCk_Handle_IntentMatcher  _Matcher;

    private FKey  _PunchKey;
    private FName _PunchButtonName;

    private ECk_Intent_Octant _AwaitedOctant = ECk_Intent_Octant::Neutral;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _PunchKey = EKeys::N;
        _PunchButtonName = _PunchKey.GetKeyName();

        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));
        _Bias   = utils_input_bias::Add(_Owner, FCk_Fragment_InputBias_ParamsData());

        TArray<FKey> PhysicalButtons;
        PhysicalButtons.Add(_PunchKey);

        _Map     = utils_input_button_map::Add(_Owner, FCk_Fragment_InputButtonMap_ParamsData(PhysicalButtons));
        _Sampler = utils_intent_sampler::Add(_Owner, FCk_Fragment_IntentSampler_ParamsData(120));

        _Layer   = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 50));
        FCk_Handle LayerEntity = _Layer;
        _Matcher = utils_intent_matcher::Add(LayerEntity, FCk_Fragment_IntentMatcher_ParamsData());

        Assert_True(ck::IsValid(_Map),     "the button map must compose for this test to mean anything");
        Assert_True(ck::IsValid(_Sampler), "the sampler must compose for this test to mean anything");
        Assert_True(ck::IsValid(_Layer),   "the matcher's layer must be created");
        Assert_True(ck::IsValid(_Matcher), "the matcher must compose onto the layer");

        Add_Step_WaitUntil("the map mints the punch key and the sampler records", n"Check_Recording");
        Add_Step(          "bake the quarter-circle set and activate it",         n"Step_SwapSet");
        Add_Step_WaitUntil("the swap registers the terminal's capture",           n"Check_SetActive");

        Add_Step(          "drive the stick to S",                                n"Step_DriveSouth");
        Add_Step_WaitUntil("the record reads S",                                  n"Check_AwaitedOctant");
        Add_Step(          "drive the stick to SE",                               n"Step_DriveSouthEast");
        Add_Step_WaitUntil("the record reads SE",                                 n"Check_AwaitedOctant");

        Add_Step(          "drive E and punch on the same frame",                 n"Step_DriveEastAndPunch");
        Add_Step_WaitUntil("the matcher completes the motion",                    n"Check_Completed");
        Add_Step(          "assert it completed ON the press frame",              n"Step_AssertSameFrame");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("236+P", n"AS_Qcf", 100));

        TArray<FCk_Intent_ButtonNameRow> Rows;
        Rows.Add(FCk_Intent_ButtonNameRow(n"P", DoMake_PhysicalButton(_PunchKey)));

        auto Baked = utils_intent_grammar::Bake(Definitions, Rows, 3);

        Assert_True(Baked.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture set must compile before the matcher can run it");

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(Baked.Get_CompiledSet()));
    }

    UFUNCTION()
    private void Step_DriveSouth(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _AwaitedOctant = ECk_Intent_Octant::S;
        DoDriveAxes(0.0f, -0.9f);
    }

    UFUNCTION()
    private void Step_DriveSouthEast(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _AwaitedOctant = ECk_Intent_Octant::SE;
        DoDriveAxes(0.7f, -0.7f);
    }

    UFUNCTION()
    private void Step_DriveEastAndPunch(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // Both injections reach the inbox on one render frame, so one logic frame claims them together and the
        // terminal chord's direction and its button land on a SINGLE row — which is what simultaneity means here.
        DoDriveAxes(0.9f, 0.0f);

        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Keyboard,
            _PunchKey,
            ECk_InputSource_EventType::Pressed);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }

    UFUNCTION()
    private void Step_AssertSameFrame(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto PressFrame = DoFind_PunchPressFrame();

        Assert_True(PressFrame >= 0,
            "a retained row must carry the punch's press edge for the comparison to mean anything");

        auto CompletionFrame = utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Qcf");

        Assert_Equals_Int(CompletionFrame, PressFrame,
            "the motion must complete ON the frame carrying its terminal press, not on a later one");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_Recording(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_button_map::Get_ButtonIdsForKey(_Map, _PunchKey).Num() >= 1 &&
                utils_intent_sampler::Get_FrameCount(_Sampler) >= 1);
    }

    UFUNCTION()
    private void Check_SetActive(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_HasActiveSet(_Matcher) &&
                utils_intent_matcher::Get_RegisteredCaptureKeys(_Matcher).Contains(_PunchKey));
    }

    UFUNCTION()
    private void Check_AwaitedOctant(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_sampler::Get_LatestFrame(_Sampler).Get_Octant() == _AwaitedOctant);
    }

    UFUNCTION()
    private void Check_Completed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Qcf") == ECk_Intent_Phase::Completed);
    }

    //------------------------------------------------------------------------

    private FCk_Intent_Definition DoParse(const FString& InNotation, FName InName, int32 InPriority)
    {
        auto Result = utils_intent_grammar::Parse(InNotation, InName, InPriority, FGameplayTag());

        Assert_True(Result.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture notation must parse before the bake can mean anything");

        return Result.Get_Definition();
    }

    // A tier-2 button's identity IS its key's name, so the expectation is derived rather than spelled out: a
    // literal would silently stop matching if the key's name ever changed.
    private FCk_Input_ButtonId DoMake_PhysicalButton(FKey InKey)
    {
        return FCk_Input_ButtonId(ECk_Input_ButtonTier::Physical, InKey.GetKeyName());
    }

    private void DoDriveAxes(float InX, float InY)
    {
        DoInjectAxis(EKeys::Gamepad_LeftX, InX);
        DoInjectAxis(EKeys::Gamepad_LeftY, InY);
    }

    private void DoInjectAxis(FKey InAxisKey, float InAnalogValue)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Gamepad,
            InAxisKey,
            ECk_InputSource_EventType::AnalogAxis);

        Event.Set_AnalogValue(InAnalogValue);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }

    private int32 DoFind_PunchPressFrame()
    {
        auto Count = utils_intent_sampler::Get_FrameCount(_Sampler);

        for (auto Offset = 0; Offset < Count; Offset++)
        {
            auto Row = utils_intent_sampler::TryGet_FrameAtOffset(_Sampler, Offset);
            auto Pressed = Row.Get_Pressed();

            for (auto Index = 0; Index < Pressed.Num(); Index++)
            {
                if (Pressed[Index].Get_Tier() != ECk_Input_ButtonTier::Physical)
                { continue; }

                if (Pressed[Index].Get_Name() == _PunchButtonName)
                { return Row.Get_FrameIndex(); }
            }
        }

        return -1;
    }
}
