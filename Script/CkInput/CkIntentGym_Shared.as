// Language=angelscript

//============================================================================
// CK INTENT GYMS — SHARED CONTRACT (FIGHTING + SOULS + DEBUGGER)
//============================================================================
//
// Station tags, the keys the gym reads, the one-per-local-player composition
// every station shares, and the read/format helpers the panels are built from.
//
// THREE GYMS, ONE SOURCE-LEVEL COMPOSITION. The fighting gym (three stations on
// the deferral law), the souls gym (three stations on the hold half of it) and
// the debugger gym (four stations that exist to put traffic in front of the Ck
// Intent Debugger's views) are separate GameModes and never run at once, but
// they read the same player input source through the same sampler and the same
// button map. The map mints its whole vocabulary in one derive pass, so the key
// list below carries ALL THREE gyms' keys — a station that arms later finds its
// key already there, and there is still exactly one minting authority. The same
// reasoning governs the sampler's SOCD quad: it is an Add-time parameter and the
// sampler has no requests, so whichever gym composes first has to compose the
// quad every later gym will read.
//
// EVERY PANEL IS A LIST OF COLOURED LINES, never one blob of text — the same
// currency the key-binding gym speaks (CkInputGym_Shared.as). Green means a
// check matched, red means a check that SHOULD have matched did not, amber is a
// value drifting while something is mid-flight, cyan is the live step or an
// instruction to the viewer, and grey is idle / not attempted yet. A motion the
// player has not performed is GREY, never red.
//
// THE PLAYER'S OWN INPUT SOURCE, NOT A SYNTHETIC ONE. The Slate writer resolves
// every real device event through UCk_InputSource_Subsystem::Get_InputSource(),
// so a source composed by this gym would be perfectly functional for injected
// events and would never receive a single real one (CkInput/CLAUDE.md
// anti-pattern 10). Everything here composes onto the subsystem's source.
//
// ONE SAMPLER, ONE BUTTON MAP, ONE BIAS — PER SOURCE, NOT PER STATION. Add
// rejects a second sampler on one source (CkIntent/CLAUDE.md anti-pattern 6),
// and a second button map would be a second minting authority. So the
// source-level composition is done ONCE, idempotently, by whichever station
// ticks first, and every station reads the same ring. What a station DOES own is
// its own input LAYER and the matcher on it: a matcher is a set running on one
// layer's arbitration, and three stations asking three different questions need
// three of them.
//
// DIRECTIONS ARE ANALOG-ONLY. The record's octant is derived from the sampler's
// axis pair and nothing else (CkIntentSampler_Processor.cpp DoRecordOctant), so
// a keyboard cannot move it — the SOCD-cleaned cardinals are a separate reading
// that no direction step is matched against. Every motion on these gyms
// therefore needs a stick; the keyboard legs exist for the BUTTON half, which is
// the half the deferral law is actually about.
//============================================================================

namespace Ck
{
    asset IntentGym_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"Gym.Intent.DeferralCounter");
        GameplayTags.Add(n"Gym.Intent.DeferredVsInstant");
        GameplayTags.Add(n"Gym.Intent.NearMiss");

        GameplayTags.Add(n"Gym.Intent.SoulsTapVsHold");
        GameplayTags.Add(n"Gym.Intent.SoulsCharge");
        GameplayTags.Add(n"Gym.Intent.SoulsDeliveryLoss");

        GameplayTags.Add(n"Gym.Intent.DebuggerTimeline");
        GameplayTags.Add(n"Gym.Intent.DebuggerLayerStack");
        GameplayTags.Add(n"Gym.Intent.DebuggerOctant");
        GameplayTags.Add(n"Gym.Intent.DebuggerNearMiss");
    }
}

//----------------------------------------------------------------------------
// One spawn-params shape for all three stations — field names match the
// UPROPERTY(ExposeOnSpawn) names each station script declares, which is what the
// spawn-params contract keys on (Script/CLAUDE.md 10).
//----------------------------------------------------------------------------

USTRUCT()
struct FCkIntentGym_StationSpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY()
    FString StationTitle;

    UPROPERTY()
    FString StationDescription;
}

//----------------------------------------------------------------------------
// One recorded attempt. Every station keeps the LAST one and renders it whether
// or not the state machine is currently sitting on its report step, so a viewer
// who looks away does not lose the answer.
//
// PressFrame and CompletionFrame are two different frames on purpose: the
// completion names the frame the wait ended on, the press names the row the
// terminal edge landed on, and the difference between them is the whole point
// of this gym.
//----------------------------------------------------------------------------

USTRUCT()
struct FCkIntentGym_Attempt
{
    UPROPERTY()
    bool Recorded = false;

    UPROPERTY()
    FName IntentName;

    UPROPERTY()
    int32 PressFrame = -1;

    UPROPERTY()
    int32 CompletionFrame = -1;

    UPROPERTY()
    int32 DeferralFrames = -1;

    UPROPERTY()
    int32 AttemptCount = 0;
}

namespace intent_gym
{
    //------------------------------------------------------------------------
    // Station identity
    //------------------------------------------------------------------------
    //
    // The Gym.Intent.* gameplay tags ride the GymStation DISPLAY entity; these
    // FName tags sit on the station SCRIPT entities, which is what lets the
    // PlayerController's exec commands reach the station that owns a matcher.

    const FName k_Tag_DeferralCounter   = n"TAG_IntentGym_DeferralCounter";
    const FName k_Tag_DeferredVsInstant = n"TAG_IntentGym_DeferredVsInstant";
    const FName k_Tag_NearMiss          = n"TAG_IntentGym_NearMiss";

    const FName k_Tag_Souls_TapVsHold    = n"TAG_IntentGym_Souls_TapVsHold";
    const FName k_Tag_Souls_Charge       = n"TAG_IntentGym_Souls_Charge";
    const FName k_Tag_Souls_DeliveryLoss = n"TAG_IntentGym_Souls_DeliveryLoss";

    const FName k_Tag_Debugger_Timeline   = n"TAG_IntentGym_Debugger_Timeline";
    const FName k_Tag_Debugger_LayerStack = n"TAG_IntentGym_Debugger_LayerStack";
    const FName k_Tag_Debugger_Octant     = n"TAG_IntentGym_Debugger_Octant";
    const FName k_Tag_Debugger_NearMiss   = n"TAG_IntentGym_Debugger_NearMiss";

    //------------------------------------------------------------------------
    // The keys this gym reads
    //------------------------------------------------------------------------
    //
    // KEYBOARD KEYS ARE THE RIGHT-HAND PUNCTUATION CLUSTER, and every one of
    // them is unclaimed by the CkInput AutoTest battery and by every other
    // script in CkTests — verified with
    //   rg --no-ignore -o 'EKeys::[A-Za-z_0-9]+' Script/
    // which reports zero hits for Semicolon / Apostrophe / Comma / Period /
    // Slash and hits for every letter key. Gamepad face buttons and shoulders
    // are free by construction: the battery injects synthetic gamepad AXIS rows
    // only, and the key-binding gym binds no pad button.
    //
    // A button name in a baked set resolves to exactly ONE ButtonId, so a move
    // that should be playable on both devices is declared TWICE under two names
    // rather than one name pointing at two keys — the bake rejects the latter
    // outright (ConflictingButtonRow).

    const FKey k_Key_Punch_Pad    = EKeys::Gamepad_FaceButton_Bottom;
    const FKey k_Key_Punch_Kb     = EKeys::Semicolon;

    const FKey k_Key_ChordA       = EKeys::Apostrophe;
    const FKey k_Key_ChordB       = EKeys::Comma;
    const FKey k_Key_Suffix       = EKeys::Period;

    const FKey k_Key_NearMiss_Pad = EKeys::Gamepad_RightShoulder;
    const FKey k_Key_NearMiss_Kb  = EKeys::Slash;

    // The souls gym takes the REST of the punctuation cluster and the pad
    // buttons the fighting gym left alone. The same grep reports zero hits for
    // LeftBracket / RightBracket / Backslash / Equals and for
    // Gamepad_FaceButton_Right / _Top / Gamepad_LeftShoulder /
    // Gamepad_Special_Right, so no station on either gym and no test in the
    // battery shares a key with another.
    //
    // The MENU keys carry no move and appear in no move table. They exist so
    // the delivery-loss station can read a press edge off the RECORD — which
    // holds every claimed event regardless of who received it — and open a
    // modal over the charge without a second delivery channel.

    const FKey k_Key_Souls_TapHold_Kb  = EKeys::LeftBracket;
    const FKey k_Key_Souls_TapHold_Pad = EKeys::Gamepad_FaceButton_Right;

    const FKey k_Key_Souls_Charge_Kb   = EKeys::RightBracket;
    const FKey k_Key_Souls_Charge_Pad  = EKeys::Gamepad_FaceButton_Top;

    const FKey k_Key_Souls_Loss_Kb     = EKeys::Backslash;
    const FKey k_Key_Souls_Loss_Pad    = EKeys::Gamepad_LeftShoulder;

    const FKey k_Key_Souls_Menu_Kb     = EKeys::Equals;
    const FKey k_Key_Souls_Menu_Pad    = EKeys::Gamepad_Special_Right;

    // The punctuation cluster is spent, so the debugger gym takes the function
    // row above it and the numeric-pad OPERATORS — the same grep reports zero
    // hits for F6 / F7 / F8 / F12 / Insert / Delete / Hyphen / Subtract / Add /
    // Divide / Multiply and for Gamepad_FaceButton_Left /
    // Gamepad_RightTrigger. The digit rows, the arrow keys, Home / End /
    // PageUp / PageDown / Enter / Escape / Tab / BackSpace and the NumPad digits
    // are all claimed by the gym menu HUD and are deliberately left alone.
    //
    // Only the two MOTION stations declare a pad leg: the octant sweep and the
    // near-miss corpus are the stations whose exercise needs a stick, and the
    // free pad-button space (six buttons) does not stretch to a second leg for
    // the two button-only stations without either sharing a key with another
    // station or spending the last of it. Two moves per table also keeps the
    // debugger's timeline to one lane per thing a viewer is being asked to look
    // at, which is the point of this gym.

    const FKey k_Key_Debugger_ChordA = EKeys::F6;
    const FKey k_Key_Debugger_ChordB = EKeys::F7;
    const FKey k_Key_Debugger_Hold   = EKeys::F8;

    const FKey k_Key_Debugger_Masked = EKeys::F12;
    const FKey k_Key_Debugger_Menu   = EKeys::Insert;

    const FKey k_Key_Debugger_Octant_Kb  = EKeys::Delete;
    const FKey k_Key_Debugger_Octant_Pad = EKeys::Gamepad_FaceButton_Left;

    const FKey k_Key_Debugger_Corpus_Kb  = EKeys::Hyphen;
    const FKey k_Key_Debugger_Corpus_Pad = EKeys::Gamepad_RightTrigger;

    // The SOCD quad. These carry no move and appear in no move table — cleaning
    // is a property of the RECORD, derived from the quad's held buttons, and the
    // octant station renders it beside the octant so a viewer can see the two
    // readings are different questions. The numeric pad's operator cluster is
    // used because its geometry is honest: on a standard pad `-` sits above `+`
    // and `/` sits left of `*`.
    const FKey k_Key_Debugger_Socd_Up    = EKeys::Subtract;
    const FKey k_Key_Debugger_Socd_Down  = EKeys::Add;
    const FKey k_Key_Debugger_Socd_Left  = EKeys::Divide;
    const FKey k_Key_Debugger_Socd_Right = EKeys::Multiply;

    //------------------------------------------------------------------------
    // Tuning
    //------------------------------------------------------------------------

    // Four seconds of history at the sampler's 60 Hz cadence. Wide enough that a
    // human-paced quarter-circle is still retained behind its terminal press,
    // which is what the backward scan needs; not a session log
    // (CkIntent/CLAUDE.md anti-pattern 5).
    const int32 k_RingCapacity = 240;

    // Ten seconds. The default 20 frames decays a third of a second after the
    // move lands, which is fine for a consumer and useless for a panel a human
    // is reading — the station compares completion FRAMES for freshness, so a
    // long latch costs it nothing (anti-pattern 15 is honoured by the frame
    // comparison, not by the decay window).
    const int32 k_LatchDecayFrames = 600;

    // A third of a second, an order of magnitude past the shipped default of 3.
    // The contrast station exists to make the wait VISIBLE, and three frames is
    // not visible.
    const int32 k_ChordWindowFrames = 20;

    // A fifth of a second. Tight enough that a deliberately slow quarter-circle
    // exhausts it, which is the near-miss the station instructs.
    const int32 k_NearMissWindowFrames = 12;

    // The souls gym's three hold thresholds. Each one is written LITERALLY into
    // its move's notation string — the string is the authoring surface and stays
    // literal — and the panel asserts the BAKED verdict against the constant,
    // which is what pins the two together (the forty-move table's
    // `k_ChargeHoldFrames` is the same shape).
    //
    //   TapVsHold  three quarters of a second: long enough that a human can feel
    //              the difference between letting go early and holding on, short
    //              enough to try twenty times in a row without boredom.
    //   Charge     two seconds — a real souls-style heavy, and long enough that
    //              the countdown is worth reading rather than a flicker.
    //   Loss       a second and a half: enough time to reach the menu key
    //              mid-charge with both hands on a keyboard.
    const int32 k_Souls_TapHoldFrames = 45;
    const int32 k_Souls_ChargeFrames  = 120;
    const int32 k_Souls_LossFrames    = 90;

    // The debugger gym's numbers, same discipline: written literally into the
    // notation and asserted against the baked verdict here.
    //
    //   Hold           a full second. The timeline station wants a phase span
    //                  wide enough to see, click and scrub inside of.
    //   Window_Tight   eight frames — under a fifth of a second, so an unhurried
    //                  quarter-circle cannot beat it.
    //   Window_Medium  twenty. Beatable with intent, missed at a browsing pace,
    //                  and far enough from eight that the two rows' frame counts
    //                  are visibly different rather than adjacent.
    const int32 k_Debugger_HoldFrames    = 60;
    const int32 k_Debugger_Window_Tight  = 8;
    const int32 k_Debugger_Window_Medium = 20;

    // Distinct priorities, one stack, disjoint terminal keys. Two layers may not
    // share a priority on one source (CkInput/CLAUDE.md anti-pattern 11), and
    // because no two stations name the same key the default Consume behaviour
    // never starves a station below.
    const int32 k_LayerPriority_DeferralCounter   = 520;
    const int32 k_LayerPriority_DeferredVsInstant = 510;
    const int32 k_LayerPriority_NearMiss          = 500;

    // The souls band sits clear of the fighting band so a reader comparing the
    // two files never has to work out whether a number is reused. The MENU layer
    // is the highest of all of them on purpose: a modal that only masked the
    // station below it would be a weaker claim than the one the station makes.
    const int32 k_LayerPriority_Souls_Menu         = 450;
    const int32 k_LayerPriority_Souls_TapVsHold    = 420;
    const int32 k_LayerPriority_Souls_Charge       = 410;
    const int32 k_LayerPriority_Souls_DeliveryLoss = 400;

    // The debugger band sits clear of both. Its masker and the layer it masks
    // are ADJACENT numbers on purpose: the station tells a viewer to expect
    // exactly those two rows, one above the other, in the debugger's layer-stack
    // view, and two numbers a hundred apart would read as two unrelated things.
    const int32 k_LayerPriority_Debugger_Timeline   = 340;
    const int32 k_LayerPriority_Debugger_Mask       = 335;
    const int32 k_LayerPriority_Debugger_LayerStack = 330;
    const int32 k_LayerPriority_Debugger_Octant     = 320;
    const int32 k_LayerPriority_Debugger_NearMiss   = 310;

    //------------------------------------------------------------------------
    // The player's input source, and the features every station reads off it
    //------------------------------------------------------------------------

    APlayerController Get_LocalPlayerController()
    {
        return Gameplay::GetPlayerController(0);
    }

    // Invalid until the local player has a PlayerController — the subsystem
    // creates the source lazily and gives up quietly until then, which is the
    // normal startup order rather than a failure.
    FCk_Handle_InputSource TryGet_PlayerSource()
    {
        auto PlayerController = Get_LocalPlayerController();
        if (ck::Is_NOT_Valid(PlayerController))
        { return utils_input_source::Get_InvalidHandle(); }

        auto SourceSubsystem = UCk_InputSource_Subsystem::Get(PlayerController);
        if (ck::Is_NOT_Valid(SourceSubsystem))
        { return utils_input_source::Get_InvalidHandle(); }

        return SourceSubsystem.Get_InputSource();
    }

    // Every key any station terminates on. Declared at Add rather than
    // registered one at a time so the map mints the whole vocabulary in the
    // first derive pass, and a station that arms later finds its key already
    // there.
    TArray<FKey> Get_AllGymKeys()
    {
        auto Keys = TArray<FKey>();
        Keys.Add(k_Key_Punch_Pad);
        Keys.Add(k_Key_Punch_Kb);
        Keys.Add(k_Key_ChordA);
        Keys.Add(k_Key_ChordB);
        Keys.Add(k_Key_Suffix);
        Keys.Add(k_Key_NearMiss_Pad);
        Keys.Add(k_Key_NearMiss_Kb);

        Keys.Add(k_Key_Souls_TapHold_Kb);
        Keys.Add(k_Key_Souls_TapHold_Pad);
        Keys.Add(k_Key_Souls_Charge_Kb);
        Keys.Add(k_Key_Souls_Charge_Pad);
        Keys.Add(k_Key_Souls_Loss_Kb);
        Keys.Add(k_Key_Souls_Loss_Pad);
        Keys.Add(k_Key_Souls_Menu_Kb);
        Keys.Add(k_Key_Souls_Menu_Pad);

        Keys.Add(k_Key_Debugger_ChordA);
        Keys.Add(k_Key_Debugger_ChordB);
        Keys.Add(k_Key_Debugger_Hold);
        Keys.Add(k_Key_Debugger_Masked);
        Keys.Add(k_Key_Debugger_Menu);
        Keys.Add(k_Key_Debugger_Octant_Kb);
        Keys.Add(k_Key_Debugger_Octant_Pad);
        Keys.Add(k_Key_Debugger_Corpus_Kb);
        Keys.Add(k_Key_Debugger_Corpus_Pad);

        Keys.Add(k_Key_Debugger_Socd_Up);
        Keys.Add(k_Key_Debugger_Socd_Down);
        Keys.Add(k_Key_Debugger_Socd_Left);
        Keys.Add(k_Key_Debugger_Socd_Right);

        return Keys;
    }

    // Idempotent, and called from every station's display tick rather than once
    // from a construct: the source does not exist until the local player has a
    // controller, so "compose it when it appears" is the only shape that cannot
    // race the engine's startup order.
    //
    // The SOCD quad is composed here for the same reason the key list is: it is
    // an Add-time parameter and the sampler has no requests, so a gym that
    // reached the source second would find a sampler it could not add a quad to.
    // It costs the other gyms nothing — no direction step is ever matched
    // against the cleaned pair, and nothing outside the octant station reads it.
    bool Request_EnsureSourceComposed()
    {
        auto Source = TryGet_PlayerSource();
        if (ck::Is_NOT_Valid(Source))
        { return false; }

        FCk_Handle SourceEntity = Source;

        if (utils_input_bias::DoCast(SourceEntity).IsSet() == false)
        { utils_input_bias::Add(SourceEntity, FCk_Fragment_InputBias_ParamsData()); }

        if (utils_input_button_map::DoCast(SourceEntity).IsSet() == false)
        { utils_input_button_map::Add(SourceEntity, FCk_Fragment_InputButtonMap_ParamsData(Get_AllGymKeys())); }

        if (utils_intent_sampler::DoCast(SourceEntity).IsSet() == false)
        {
            auto SamplerParams = FCk_Fragment_IntentSampler_ParamsData(k_RingCapacity);
            SamplerParams.Set_SocdQuad(Make_SocdQuad());

            utils_intent_sampler::Add(SourceEntity, SamplerParams);
        }

        return true;
    }

    FCk_Handle_IntentSampler TryGet_Sampler()
    {
        auto Source = TryGet_PlayerSource();
        if (ck::Is_NOT_Valid(Source))
        { return utils_intent_sampler::Get_InvalidHandle(); }

        FCk_Handle SourceEntity = Source;
        auto CastResult = utils_intent_sampler::DoCast(SourceEntity);
        if (CastResult.IsSet() == false)
        { return utils_intent_sampler::Get_InvalidHandle(); }

        return CastResult.GetValue();
    }

    FCk_Handle_InputButtonMap TryGet_ButtonMap()
    {
        auto Source = TryGet_PlayerSource();
        if (ck::Is_NOT_Valid(Source))
        { return utils_input_button_map::Get_InvalidHandle(); }

        FCk_Handle SourceEntity = Source;
        auto CastResult = utils_input_button_map::DoCast(SourceEntity);
        if (CastResult.IsSet() == false)
        { return utils_input_button_map::Get_InvalidHandle(); }

        return CastResult.GetValue();
    }

    // A tier-2 button's identity IS its key's own name, so the expectation is
    // derived rather than spelled out — a literal would silently stop matching
    // if a key's name ever changed.
    FCk_Input_ButtonId Make_PhysicalButton(FKey InKey)
    {
        return FCk_Input_ButtonId(ECk_Input_ButtonTier::Physical, InKey.GetKeyName());
    }

    // The quad is all four or none — a partial one is rejected at Add,
    // atomically, because cleaning resolves opposing PAIRS and three buttons
    // describe an axis with one end.
    FCk_Intent_SocdQuad Make_SocdQuad()
    {
        return FCk_Intent_SocdQuad(
            Make_PhysicalButton(k_Key_Debugger_Socd_Up),
            Make_PhysicalButton(k_Key_Debugger_Socd_Down),
            Make_PhysicalButton(k_Key_Debugger_Socd_Left),
            Make_PhysicalButton(k_Key_Debugger_Socd_Right));
    }

    //------------------------------------------------------------------------
    // Reading the record
    //------------------------------------------------------------------------

    bool Get_RowCarriesButton(const FCk_Intent_FrameRecord&in InRow, FName InButtonName, bool InUseHeld)
    {
        auto Buttons = InUseHeld ? InRow.Get_Held() : InRow.Get_Pressed();

        for (auto Index = 0; Index < Buttons.Num(); Index++)
        {
            if (Buttons[Index].Get_Tier() != ECk_Input_ButtonTier::Physical)
            { continue; }

            if (Buttons[Index].Get_Name() == InButtonName)
            { return true; }
        }

        return false;
    }

    // Offset 0 is the newest row, so the first press found walking forward from
    // it is the most recent one — which is the press a completion just behind it
    // was scanning back from.
    int32 Get_LatestPressFrame(FCk_Handle_IntentSampler InSampler, FName InButtonName)
    {
        if (ck::Is_NOT_Valid(InSampler))
        { return -1; }

        auto Count = utils_intent_sampler::Get_FrameCount(InSampler);

        for (auto Offset = 0; Offset < Count; Offset++)
        {
            auto Row = utils_intent_sampler::TryGet_FrameAtOffset(InSampler, Offset);

            if (Get_RowCarriesButton(Row, InButtonName, false))
            { return Row.Get_FrameIndex(); }
        }

        return -1;
    }

    bool Get_IsButtonHeld(FCk_Handle_IntentSampler InSampler, FName InButtonName)
    {
        if (ck::Is_NOT_Valid(InSampler))
        { return false; }

        return Get_RowCarriesButton(utils_intent_sampler::Get_LatestFrame(InSampler), InButtonName, true);
    }

    // DISPLAY ONLY, and the naming says so because the distinction is the whole
    // of CkIntent anti-pattern 23: this counts the rows the RECORD reports the
    // button down for, which is the physical fact and keeps counting straight
    // through a mask. The matcher's accumulator is the policy-applied count, it
    // is not readable, and it is the phases — not this number — that a panel is
    // allowed to grade an outcome from.
    int32 Get_HeldRunFrames(FCk_Handle_IntentSampler InSampler, FName InButtonName)
    {
        if (ck::Is_NOT_Valid(InSampler))
        { return 0; }

        auto Count = utils_intent_sampler::Get_FrameCount(InSampler);
        auto Run = 0;

        for (auto Offset = 0; Offset < Count; Offset++)
        {
            auto Row = utils_intent_sampler::TryGet_FrameAtOffset(InSampler, Offset);

            if (Get_RowCarriesButton(Row, InButtonName, true) == false)
            { return Run; }

            Run++;
        }

        return Run;
    }

    // The newest row's held set, in button space. The debugger's key/state view
    // lists exactly this, one row per button, which is why a panel meant to be
    // compared against it renders the names rather than a count.
    TArray<FName> Get_HeldButtonNames(FCk_Handle_IntentSampler InSampler)
    {
        auto Names = TArray<FName>();

        if (ck::Is_NOT_Valid(InSampler))
        { return Names; }

        auto Buttons = utils_intent_sampler::Get_LatestFrame(InSampler).Get_Held();

        for (auto Index = 0; Index < Buttons.Num(); Index++)
        {
            Names.Add(Buttons[Index].Get_Name());
        }

        return Names;
    }

    ECk_Intent_Octant Get_LiveOctant(FCk_Handle_IntentSampler InSampler)
    {
        if (ck::Is_NOT_Valid(InSampler))
        { return ECk_Intent_Octant::Neutral; }

        return utils_intent_sampler::Get_LatestFrame(InSampler).Get_Octant();
    }

    int32 Get_LiveFrameIndex(FCk_Handle_IntentSampler InSampler)
    {
        if (ck::Is_NOT_Valid(InSampler))
        { return -1; }

        return utils_intent_sampler::Get_LatestFrame(InSampler).Get_FrameIndex();
    }

    //------------------------------------------------------------------------
    // Formatting
    //------------------------------------------------------------------------

    FString Format_Key(FKey InKey)
    {
        if (InKey.IsValid() == false)
        { return "<unbound>"; }

        return InKey.GetKeyName().ToString();
    }

    FString Format_Phase(ECk_Intent_Phase InPhase)
    {
        return f"{InPhase :n}";
    }

    FString Format_Octant(ECk_Intent_Octant InOctant)
    {
        return f"{InOctant :n}";
    }

    FString Format_CleanedAxis(ECk_Intent_CleanedAxis InAxis)
    {
        return f"{InAxis :n}";
    }

    FString Format_Bool(bool InValue)
    {
        if (InValue)
        { return "yes"; }

        return "no";
    }

    //------------------------------------------------------------------------
    // Coloured panel building blocks
    //------------------------------------------------------------------------

    void Add_Line(TArray<FCkGym_ColoredLine>& OutLines, FString InText, FColor InColour)
    {
        OutLines.Add(FCkGym_ColoredLine(InText, InColour));
    }

    // A blank line still belongs to a run, so it carries the colour of whatever
    // it separates rather than starting one of its own.
    void Add_Spacer(TArray<FCkGym_ColoredLine>& OutLines, FColor InColour)
    {
        OutLines.Add(FCkGym_ColoredLine(" ", InColour));
    }

    FColor Get_VerdictColour(bool InPassed)
    {
        if (InPassed)
        { return gym_palette::Green; }

        return gym_palette::Red;
    }

    // The one self-asserting shape every station on this gym uses: what was
    // expected, what was actually there, and green or red for whether the two
    // agree.
    void Add_Verdict(TArray<FCkGym_ColoredLine>& OutLines, FString InWhat, FString InExpect, FString InGot, bool InPassed)
    {
        Add_Line(OutLines, f"  {InWhat}  EXPECT {InExpect} -> GOT {InGot}", Get_VerdictColour(InPassed));
    }

    // A check nobody has performed yet has not FAILED. Red on this gym means a
    // motion the player made that the module answered wrongly; a motion never
    // made is grey.
    void Add_Verdict_Pending(TArray<FCkGym_ColoredLine>& OutLines, FString InWhat, FString InExpect)
    {
        Add_Line(OutLines, f"  {InWhat}  EXPECT {InExpect} -> GOT (not attempted yet)", gym_palette::Grey);
    }

    // The debugger gym's stations each point at ONE view and then say what it
    // should show. The header is shared so the four of them cannot drift into
    // four different ways of naming the same tool.
    void Add_DebuggerViewHeader(TArray<FCkGym_ColoredLine>& OutLines, FString InViewName)
    {
        Add_Line(OutLines, f"OPEN THE CK INTENT DEBUGGER - {InViewName}", gym_palette::Cyan);
    }

    // Live step list, sourced from the state machine's current state, so the
    // panel cannot advertise a step other than the one running.
    void Add_SmSteps(TArray<FCkGym_ColoredLine>& OutLines, const FCkGym_SmConfig&in InConfig, FCk_Handle_StateMachine InSm)
    {
        auto HasCurrent = ck::IsValid(InSm);
        TSubclassOf<UCk_SmState_EntityScript> Current;
        if (HasCurrent)
        { Current = utils_state_machine::Get_CurrentStateClass(InSm); }

        for (auto Index = 0; Index < InConfig.Steps.Num(); Index++)
        {
            auto IsActive = HasCurrent && InConfig.Steps[Index].StateClass == Current;

            if (IsActive)
            {
                Add_Line(OutLines, f"  >> {InConfig.Steps[Index].Description}", gym_palette::Cyan);
                continue;
            }

            Add_Line(OutLines, f"     {InConfig.Steps[Index].Description}", gym_palette::Grey);
        }
    }

    //------------------------------------------------------------------------
    // Shared panel sections
    //------------------------------------------------------------------------

    // What the module is reading RIGHT NOW, in the terms a viewer with no
    // feature knowledge can check against their own hands.
    void Add_LiveInput(TArray<FCkGym_ColoredLine>& OutLines, FCk_Handle_IntentSampler InSampler)
    {
        Add_Line(OutLines, "WHAT THE GAME IS READING RIGHT NOW", gym_palette::White);

        if (ck::Is_NOT_Valid(InSampler))
        {
            Add_Line(OutLines, "  no input source yet - waiting for the local player's controller", gym_palette::Grey);
            return;
        }

        auto Octant = Get_LiveOctant(InSampler);
        auto OctantColour = Octant == ECk_Intent_Octant::Neutral ? gym_palette::Grey : gym_palette::Cyan;

        Add_Line(OutLines, f"  stick direction  {Format_Octant(Octant)}", OctantColour);
        Add_Line(OutLines, f"  logic frame      {Get_LiveFrameIndex(InSampler)}", gym_palette::White);
        Add_Line(OutLines, "  Directions come from the gamepad LEFT STICK only. A keyboard cannot", gym_palette::White);
        Add_Line(OutLines, "  move this reading - the buttons below work on either device.", gym_palette::White);
    }

    // Whether the station's set is live. A swap is deferred and drains two
    // groups ahead of the scan, so polling straight after the request reads the
    // OLD set (CkIntent/CLAUDE.md anti-pattern 21) — this asks the matcher, not
    // the layer, because a capture edit is not visible on the layer for a frame
    // (anti-pattern 18).
    bool Get_IsArmed(FCk_Handle_IntentMatcher InMatcher, FKey InTerminalKey)
    {
        if (ck::Is_NOT_Valid(InMatcher))
        { return false; }

        if (utils_intent_matcher::Get_HasActiveSet(InMatcher) == false)
        { return false; }

        return utils_intent_matcher::Get_RegisteredCaptureKeys(InMatcher).Contains(InTerminalKey);
    }

    void Add_ArmingStatus(
        TArray<FCkGym_ColoredLine>& OutLines,
        FCk_Handle_IntentMatcher InMatcher,
        FKey InTerminalKey,
        bool InSwapRejected)
    {
        if (InSwapRejected)
        {
            Add_Line(OutLines, "  The move set was REJECTED - a terminal button resolved to no key.", gym_palette::Red);
            return;
        }

        if (Get_IsArmed(InMatcher, InTerminalKey) == false)
        {
            Add_Line(OutLines, "  Arming the move set...", gym_palette::Grey);
            return;
        }

        Add_Line(OutLines, f"  Move set live - {utils_intent_matcher::Get_ActiveIntentCount(InMatcher)} moves loaded.", gym_palette::Green);
    }

    //------------------------------------------------------------------------
    // Attempt bookkeeping — the anti-pattern-15 shape
    //------------------------------------------------------------------------
    //
    // `Completed` is LATCHED, so branching on the phase alone re-reads the same
    // completion every frame until it decays. The freshness test is the
    // COMPLETION FRAME against the one already recorded, which is exactly what
    // the module's doc prescribes.

    bool Request_RecordAttempt(
        FCkIntentGym_Attempt& OutAttempt,
        FCk_Handle_IntentMatcher InMatcher,
        FCk_Handle_IntentSampler InSampler,
        FName InIntentName,
        FName InTerminalButtonName)
    {
        if (ck::Is_NOT_Valid(InMatcher))
        { return false; }

        auto CompletionFrame = utils_intent_matcher::TryGet_CompletionFrame_ByName(InMatcher, InIntentName);

        if (CompletionFrame < 0)
        { return false; }

        if (OutAttempt.Recorded && OutAttempt.CompletionFrame == CompletionFrame)
        { return false; }

        OutAttempt.Recorded = true;
        OutAttempt.IntentName = InIntentName;
        OutAttempt.CompletionFrame = CompletionFrame;
        OutAttempt.PressFrame = Get_LatestPressFrame(InSampler, InTerminalButtonName);
        OutAttempt.DeferralFrames = OutAttempt.PressFrame >= 0 ? CompletionFrame - OutAttempt.PressFrame : -1;
        OutAttempt.AttemptCount++;

        return true;
    }
}
