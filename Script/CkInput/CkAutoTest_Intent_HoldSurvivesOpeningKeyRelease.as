// Language=angelscript

//============================================================================
// CK INTENT — AUTOMATION TEST: A CHARGE OUTLIVES THE RELEASE OF THE KEY IT
//                              OPENED ON
//============================================================================
//
// A Mapped button now carries every bound slot's key, so one logical button
// can be down because of EITHER device. That makes "is the button still
// down?" a question about the union of its keys — while the episode that is
// charging remembers exactly one key, the one its opening press arrived on
// (FIntentMatcher_PendingEpisode::_PressKey).
//
// The two facts have to agree, and this is the case where a naive
// implementation would have them disagree: the player starts a charge on the
// keyboard, puts a thumb on the gamepad, then lifts the keyboard key. The
// button never came up. The charge must not notice.
//
// A wrong implementation fails LOUDLY here rather than subtly, and it fails
// as the SIBLING completing: if the opening key's release were read as "the
// button came up", the hold cause would disarm and the episode would resolve
// to the tap. So the discriminator is not merely "the charge completed" — it
// is "the charge completed AND the tap did not", plus exact frame arithmetic
// proving the accumulator was never reset along the way.
//
// A rival is mandatory, not decoration: with one candidate on the terminal
// there is no forward ambiguity, the bake writes no verdict, and the press
// would resolve immediately with no episode to survive anything. The tap
// sibling is what makes the deferral exist at all — Step_SwapSet asserts the
// verdict rather than assuming it.
//
// The threshold is three seconds of logic frames. That is not tuning slack:
// the release sequence needs several step-hops to land (press primary, press
// secondary, confirm each reached the record, release primary, confirm that
// reached the record) and every one of them must happen while the episode is
// STILL pending, or the test is asserting nothing.
//
// CkTests_DualBound stays on its authored F8/F12 defaults for the whole test
// — no key binding is mutated, so there is nothing to reset on teardown.
//============================================================================

class UCk_AutoTest_Intent_HoldSurvivesOpeningKeyRelease : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;
    private FCk_Handle_InputLayer     _Layer;
    private FCk_Handle_IntentMatcher  _Matcher;

    private FName _MappingName = n"CkTests_DualBound";
    private FKey  _PrimaryKey;
    private FKey  _SecondaryKey;

    // Three seconds at the sampler's 60 Hz cadence. See the header: this has to
    // outlast the whole release sequence, not merely the press.
    private int32 _HoldThresholdFrames = 180;

    private int32 _PressFrame = -1;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _PrimaryKey   = EKeys::F8;
        _SecondaryKey = EKeys::F12;

        auto PlayerController = Gameplay::GetPlayerController(0);
        if (ck::Is_NOT_Valid(PlayerController))
        {
            FinishFailure("no local PlayerController — the mapped tier derives from the local player's profile");
            return;
        }

        auto UserSettings = utils_key_binding::Get_InputUserSettings(PlayerController);
        if (ck::Is_NOT_Valid(UserSettings))
        {
            FinishFailure("Enhanced Input user settings unavailable on the local player");
            return;
        }

        UserSettings.RegisterInputMappingContext(input_assets::IMC_CkTests_KeyBinding);

        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        _Map     = utils_input_button_map::Add(_Owner, FCk_Fragment_InputButtonMap_ParamsData());
        _Sampler = utils_intent_sampler::Add(_Owner, FCk_Fragment_IntentSampler_ParamsData(240));

        _Layer   = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 50));

        // The completion latch is read a step after it is stamped and compared against a press
        // frame recorded long before it, so the decay window must outlast the whole sequence.
        auto MatcherParams = FCk_Fragment_IntentMatcher_ParamsData();
        MatcherParams.Set_LatchDecayFrames(600);

        FCk_Handle LayerEntity = _Layer;
        _Matcher = utils_intent_matcher::Add(LayerEntity, MatcherParams);

        Assert_True(ck::IsValid(_Map),     "the button map must compose for this test to mean anything");
        Assert_True(ck::IsValid(_Sampler), "the sampler must compose for this test to mean anything");
        Assert_True(ck::IsValid(_Matcher), "the matcher must compose onto the layer");

        Add_Step_WaitUntil("the dual-bound button derives with both keys",          n"Check_DualBoundDerived");
        Add_Step(          "bake the tap/charge pair on the dual-bound button",     n"Step_SwapSet");
        Add_Step_WaitUntil("the swap registers captures for BOTH keys",             n"Check_CapturesBothKeys");

        Add_Step(          "press the PRIMARY key — the charge opens on it",        n"Step_PressPrimary");
        Add_Step_WaitUntil("the press is held pending",                             n"Check_ChargeIsPending");
        Add_Step(          "record the press frame",                                n"Step_RecordPressFrame");

        Add_Step(          "press the SECONDARY key while the primary is down",     n"Step_PressSecondary");
        Add_Step_WaitUntil("the secondary press reaches the record",                n"Check_SecondaryPressRecorded");

        Add_Step(          "release the PRIMARY key — the one the episode opened on", n"Step_ReleasePrimary");
        Add_Step_WaitUntil("the primary release reaches the record",                n"Check_PrimaryReleaseRecorded");
        Add_Step(          "assert the charge survived its opening key coming up",  n"Step_AssertStillCharging");

        // Explicit budget: the default 240 polls is ~2.1s of render frames, which cannot outlast a
        // 180-logic-frame (3s) threshold no matter how the charge behaves. 600 clears it with room.
        Add_Step_WaitUntil("the charge reaches its threshold",                       n"Check_ChargeCompleted", 600);
        Add_Step(          "assert it landed exactly on the threshold frame, then release", n"Step_AssertChargeCompleted");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("CkTests_DualBound hold=180", n"AS_DualHold_Charged", 100));
        Definitions.Add(DoParse("CkTests_DualBound",          n"AS_DualHold_Quick",    50));

        TArray<FCk_Intent_ButtonNameRow> Rows;
        Rows.Add(FCk_Intent_ButtonNameRow(_MappingName, DoMake_MappedButton()));

        auto Baked = utils_intent_grammar::Bake(Definitions, Rows, 3);

        Assert_True(Baked.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture set must compile before the matcher can run it");

        auto Verdict = utils_intent_grammar::Get_DeferralVerdict(
            Baked.Get_CompiledSet(), DoMake_MappedButton());

        Assert_Equals_Int(Verdict.Get_HoldSiblingFrames(), _HoldThresholdFrames,
            "without a rival the press would resolve on its own frame and there would be no episode to survive anything");

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(Baked.Get_CompiledSet()));
    }

    UFUNCTION()
    private void Step_PressPrimary(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(_PrimaryKey, ECk_InputSource_EventType::Pressed);
    }

    UFUNCTION()
    private void Step_RecordPressFrame(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _PressFrame = DoFind_LatestPressFrame();

        Assert_True(_PressFrame >= 0,
            "a retained row must carry the press edge for the frame arithmetic to mean anything");
    }

    UFUNCTION()
    private void Step_PressSecondary(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(_SecondaryKey, ECk_InputSource_EventType::Pressed);
    }

    UFUNCTION()
    private void Step_ReleasePrimary(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(_PrimaryKey, ECk_InputSource_EventType::Released);
    }

    UFUNCTION()
    private void Step_AssertStillCharging(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // The assertions below only mean something while the wait is still open, so the budget is
        // checked rather than assumed: a threshold this sequence outran would make "still Pending"
        // unreachable and the failure would read as a behaviour change instead of a slow machine.
        auto ElapsedFrames = utils_intent_sampler::Get_LatestFrame(_Sampler).Get_FrameIndex() - _PressFrame;

        Assert_True(ElapsedFrames < _HoldThresholdFrames,
            f"the release sequence took {ElapsedFrames} frames, past the {_HoldThresholdFrames}-frame threshold — raise the threshold, this run proved nothing about survival");

        Assert_True(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_DualHold_Charged") ==
                    ECk_Intent_Phase::Pending,
            "the opening key came up while a co-bound key stayed down — the button never came up, so the charge must still be waiting");

        Assert_True(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_DualHold_Quick") ==
                    ECk_Intent_Phase::Pending,
            "the tap must not have been answered either — the episode is intact, not resolved");
    }

    UFUNCTION()
    private void Step_AssertChargeCompleted(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto CompletionFrame = utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_DualHold_Charged");

        Assert_Equals_Int(CompletionFrame - _PressFrame, _HoldThresholdFrames,
            "the charge completes exactly its threshold after the press — a reset accumulator would land late, and a cancelled episode would never land at all");

        Assert_True(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_DualHold_Quick") ==
                    ECk_Intent_Phase::Idle,
            "the tap lost the arbitration rather than being answered by the primary key's release");

        DoInject(_SecondaryKey, ECk_InputSource_EventType::Released);
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_DualBoundDerived(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_button_map::Get_KeysForButton(_Map, DoMake_MappedButton()).Num() == 2 &&
                utils_intent_sampler::Get_FrameCount(_Sampler) >= 1);
    }

    UFUNCTION()
    private void Check_CapturesBothKeys(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        auto Keys = utils_intent_matcher::Get_RegisteredCaptureKeys(_Matcher);
        Res.Set(Keys.Contains(_PrimaryKey) && Keys.Contains(_SecondaryKey));
    }

    UFUNCTION()
    private void Check_ChargeIsPending(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_DualHold_Charged") ==
                ECk_Intent_Phase::Pending);
    }

    // The press and the release are gated on the RECORD rather than on a hop count because the
    // whole test turns on their ORDER: a release that had not landed yet would leave the charge
    // completing for the ordinary reason and the test passing without ever exercising anything.
    UFUNCTION()
    private void Check_SecondaryPressRecorded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoFind_RoutedEdge(_SecondaryKey, ECk_InputSource_EventType::Pressed));
    }

    UFUNCTION()
    private void Check_PrimaryReleaseRecorded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoFind_RoutedEdge(_PrimaryKey, ECk_InputSource_EventType::Released));
    }

    UFUNCTION()
    private void Check_ChargeCompleted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_DualHold_Charged") ==
                ECk_Intent_Phase::Completed);
    }

    //------------------------------------------------------------------------

    private FCk_Intent_Definition DoParse(const FString& InNotation, FName InName, int32 InPriority)
    {
        auto Result = utils_intent_grammar::Parse(InNotation, InName, InPriority, FGameplayTag());

        Assert_True(Result.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture notation must parse before the bake can mean anything");

        return Result.Get_Definition();
    }

    private FCk_Input_ButtonId DoMake_MappedButton()
    {
        return FCk_Input_ButtonId(ECk_Input_ButtonTier::Mapped, _MappingName);
    }

    private void DoInject(FKey InKey, ECk_InputSource_EventType InEventType)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Keyboard,
            InKey,
            InEventType);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }

    // Offset 0 is the newest row, so the first press found walking forward from it is the most recent one.
    private int32 DoFind_LatestPressFrame()
    {
        auto Count = utils_intent_sampler::Get_FrameCount(_Sampler);

        for (auto Offset = 0; Offset < Count; Offset++)
        {
            auto Row = utils_intent_sampler::TryGet_FrameAtOffset(_Sampler, Offset);
            auto Pressed = Row.Get_Pressed();

            for (auto Index = 0; Index < Pressed.Num(); Index++)
            {
                if (Pressed[Index].Get_Tier() != ECk_Input_ButtonTier::Mapped)
                { continue; }

                if (Pressed[Index].Get_Name() == _MappingName)
                { return Row.Get_FrameIndex(); }
            }
        }

        return -1;
    }

    private bool DoFind_RoutedEdge(FKey InKey, ECk_InputSource_EventType InEventType)
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

                if (Routed[Index].Get_Event().Get_EventType() != InEventType)
                { continue; }

                return true;
            }
        }

        return false;
    }
}
