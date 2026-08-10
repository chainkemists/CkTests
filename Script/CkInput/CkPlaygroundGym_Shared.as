// Language=angelscript

//============================================================================
// CK INPUT PLAYGROUND GYM — SHARED CONTRACT
//============================================================================
//
// The one-per-local-player composition the playground shares, the read helpers
// the combat kit is built from, and the key ledger that keeps two claimants off
// one key.
//
// ONE MAP, ONE PAWN, ONE SOURCE-LEVEL COMPOSITION. The playground is a single
// drivable level with no stations on it: the pawn IS the exercise. The
// source-level composition below is still minted ONCE and read by everything,
// because Add rejects a second sampler on one source (CkIntent/CLAUDE.md
// anti-pattern 6) and a second button map would be a second minting authority.
// The composition is idempotent and whoever ticks first performs it — the pawn
// and the PlayerController both call it, so neither has to be ordered against
// the other. What a CONSUMER owns is its own input LAYER and the matcher on it:
// a matcher is a set running on one layer's arbitration.
//
// THE PLAYER'S OWN INPUT SOURCE, NOT A SYNTHETIC ONE. The Slate writer resolves
// every real device event through UCk_InputSource_Subsystem::Get_InputSource(),
// so a source composed by this gym would be perfectly functional for injected
// events and would never receive a single real one (CkInput/CLAUDE.md
// anti-pattern 10). Everything here composes onto the subsystem's source.
//
// DIRECTIONS ARE ANALOG-ONLY, AND NOTHING IS MATCHED AGAINST ONE. The record's
// octant is derived from the sampler's axis pair and nothing else, so a keyboard
// cannot move it. No move in this gym declares a direction STEP — the forward
// combo is a chord of two BUTTONS, one of which happens to be the forward key —
// so the octant is read but never matched, and the SOCD quad is left UNNAMED: an
// unnamed quad is the documented unset state, both cleaned slots stay Neutral,
// and no SOCD work runs. That is a composition with no direction keys at all,
// which is exactly what a mouse-driven kit needs.
//
// THE PLAYGROUND RENDERS SHAPES, NOT PANELS. There is no coloured-line panel
// vocabulary here and no display entity: the pawn says what it means with the PMG
// geometry it throws and the label floating over its head. Nothing in this file
// builds text blocks.
//
//----------------------------------------------------------------------------
// KEY LEDGER — every key the playground claims, and who owns it
//----------------------------------------------------------------------------
//
// One key, one claimant. Grep-proof, same discipline as the gym this file was
// salvaged from:
//   rg --no-ignore -o 'EKeys::[A-Za-z_0-9]+' Script/
// Anything not listed below is either free or owned by the row that names it.
//
// MINTED — declared to the button map, so the RECORD carries a row for them and
// a move can terminate on them:
//
//   LeftMouseButton                    light attacks + light charge (k_Key_Light)
//   RightMouseButton                   heavy attacks + heavy charge (k_Key_Heavy)
//   W                                  forward locomotion AND the forward combo's
//                                      chord partner (k_Key_Forward)
//   Q                                  block (k_Key_Block) — MINTED, NO MOVE ROWS
//
// W IS READ TWICE, DELIBERATELY. It is the only key in this gym with two
// claimants, and they cannot starve each other because they read different
// surfaces: the combat kit's matcher captures W on its own input LAYER (a
// `Consume` capture, like every other terminal the set registers), while
// locomotion polls `APlayerController::IsInputKeyDown` in the pawn's tick, which
// is engine-level state outside the routed pipeline entirely. A capture ends a
// ROUTING walk; it does not make a key stop being down. So holding W walks the
// character forward and simultaneously satisfies the `W+L` chord the instant the
// mouse button lands, which is the whole shape of a direction combo.
//
// Q IS MINTED AND CARRIES NOTHING, ON PURPOSE. It appears in no move table, no
// intent terminates on it, and the matcher never grades it — it is minted so the
// RECORD carries a row for it, and the pawn reads the block straight off that
// row's HELD SET. That is the deliberate contrast this playground exists to show:
// seven moves that are notation compiled into a set and graded by the module,
// beside one state that is a fact about the newest row and is read, not graded.
// The deleted sekiro station demonstrated exactly this shape — a held block sat
// beside matched deflect timing — and the block is the last piece of it that
// survives here. A hold= sibling on Q would be the opposite lesson: it would make
// the block a move, and the whole point is that it is not one.
//
// CLAIMED BUT UNMINTED — polled straight off the PlayerController or owned by the
// gym shell. They carry no move, appear in no move table, and the button map
// never mints them, so no row of the record names them and nothing can terminate
// on them:
//
//   A / S / D                          locomotion, polled  (CkPlaygroundGym_Pawn)
//   Mouse2D                            cursor aim, deprojected (CkPlaygroundGym_Pawn)
//   Tab                                gym menu, gym shell
//
// UNTOUCHABLE — the gym menu HUD reads these on every gym in the project, so a
// claimant here would break the map's navigation rather than its own exercise:
// the digit rows, the arrow keys, Home / End / PageUp / PageDown, Enter, Escape,
// Tab and BackSpace.
//
// SPOKEN FOR ELSEWHERE — F6 and F7 belong to the CkInput AutoTest battery.
//
// The two mouse buttons are the FIRST real device events this stack has been
// asked to carry through the Slate writer, and nothing upstream proves they
// arrive. That is why the pawn's diagnostics render with zero input rather than
// only once something lands: a dead button has to look different from a dead
// kit. Q's held run is quoted on the same line for the same reason.
//
// The deleted station gyms (fighting / souls / sekiro / debugger fodder) held the
// right-hand punctuation cluster, the function row, the numeric pad's operator
// quad and most of the pad face buttons. Every one of those is released. A future
// claimant may take one; it appends its row here, next to the constant that
// carries it.
//============================================================================

//----------------------------------------------------------------------------
// One recorded attempt. A consumer keeps the LAST one per move and renders it
// whether or not the player is still doing anything, so a viewer who stops
// pressing does not lose the answer.
//
// PressFrame and CompletionFrame are two different frames on purpose: the
// completion names the frame the wait ended on, the press names the row the
// terminal edge landed on, and the difference between them is the deferral this
// gym's hold siblings buy.
//----------------------------------------------------------------------------

USTRUCT()
struct FCkPlaygroundGym_Attempt
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

namespace playground_gym
{
    //------------------------------------------------------------------------
    // Shape durations
    //------------------------------------------------------------------------
    //
    // PMG reads a duration three ways and the sign is the whole of it: zero is
    // destroyed on the first tick, a positive value is a countdown the entity
    // runs itself, and a negative value persists until something destroys it.
    // A shape whose meaning is its LIFETIME carries a positive duration; a shape
    // that has to be re-transformed or recoloured for as long as a state lasts is
    // persistent and its owner is responsible for taking it down.

    const float32 k_ShapeDuration_Persistent = -1.0f;

    // Single-frame: re-issued on every tick the thing it describes is true, so it
    // is continuous while a player is producing it and costs nothing otherwise.
    const float32 k_ShapeDuration_SingleFrame = 0.0f;

    //------------------------------------------------------------------------
    // The layer band
    //------------------------------------------------------------------------
    //
    // Two layers may not share a priority on one source (CkInput/CLAUDE.md
    // anti-pattern 11), and a matcher only ever sees the events its layer is
    // allowed to see (CkIntent/CLAUDE.md anti-pattern 16). The combat kit is the
    // only claimant on this source today and it sits high, so a modal added later
    // has room above it without renumbering anything.

    const int32 k_LayerPriority_CombatKit = 250;

    //------------------------------------------------------------------------
    // The keys this gym reads
    //------------------------------------------------------------------------
    //
    // The full ledger is in the file header. These are the four constants; a key
    // the playground polls straight off the PlayerController lives beside its
    // poller and is never minted here.
    //
    // Three graded buttons and not one. The two mouse buttons each carry a hold
    // sibling and its bare rival — the light chain and the light charge are one
    // terminal's two answers, and the heavy pair is the other's — and the third,
    // forward, is graded only as the partner of a chord: nothing terminates on W
    // alone, and a press of it while the mouse button is up completes nothing.
    //
    // The fourth button is minted and graded by nothing. Block is a HELD SET read
    // off the newest record row (see the ledger note above), so Q needs a row in
    // the record and nothing else — no move table entry, no terminal, no verdict.

    const FKey k_Key_Light   = EKeys::LeftMouseButton;
    const FKey k_Key_Heavy   = EKeys::RightMouseButton;
    const FKey k_Key_Forward = EKeys::W;
    const FKey k_Key_Block   = EKeys::Q;

    //------------------------------------------------------------------------
    // Tuning
    //------------------------------------------------------------------------

    // Four seconds of history at the sampler's 60 Hz cadence. Wider than any hold
    // threshold this gym declares, which is what the backward scan behind a
    // terminal press needs; not a session log (CkIntent/CLAUDE.md anti-pattern 5).
    const int32 k_RingCapacity = 240;

    // Ten seconds. The default 20 frames decays a third of a second after the move
    // lands, which is fine for a consumer and useless for something a human is
    // reading — the kit compares completion FRAMES for freshness, so a long latch
    // costs it nothing (anti-pattern 15 is honoured by the frame comparison, not
    // by the decay window).
    const int32 k_LatchDecayFrames = 600;

    //------------------------------------------------------------------------
    // The player's input source, and the features every consumer reads off it
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

    // Every key any move in this gym terminates on, PLUS the one key that is read
    // rather than matched. Declared at Add rather than registered one at a time so
    // the map mints the whole vocabulary in the first derive pass, and a consumer
    // that arms later finds its keys already there.
    TArray<FKey> Get_AllPlaygroundKeys()
    {
        auto Keys = TArray<FKey>();

        Keys.Add(k_Key_Light);
        Keys.Add(k_Key_Heavy);
        Keys.Add(k_Key_Forward);
        Keys.Add(k_Key_Block);

        return Keys;
    }

    // Idempotent, and called from a TICK rather than once from a construct: the
    // source does not exist until the local player has a controller, so "compose
    // it when it appears" is the only shape that cannot race the engine's startup
    // order. Two callers is deliberate — the pawn and the PlayerController each
    // call it, and neither has to know which of them ran first.
    //
    // The sampler is composed with NO SOCD QUAD. An unnamed quad is the documented
    // unset state: both cleaned slots stay Neutral and no SOCD work runs. Nothing
    // in this gym matches a direction, so a quad would only mint four keys the
    // record carried rows for and nobody read.
    bool Request_EnsureSourceComposed()
    {
        auto Source = TryGet_PlayerSource();
        if (ck::Is_NOT_Valid(Source))
        { return false; }

        FCk_Handle SourceEntity = Source;

        if (utils_input_bias::DoCast(SourceEntity).IsSet() == false)
        { utils_input_bias::Add(SourceEntity, FCk_Fragment_InputBias_ParamsData()); }

        if (utils_input_button_map::DoCast(SourceEntity).IsSet() == false)
        { utils_input_button_map::Add(SourceEntity, FCk_Fragment_InputButtonMap_ParamsData(Get_AllPlaygroundKeys())); }

        if (utils_intent_sampler::DoCast(SourceEntity).IsSet() == false)
        { utils_intent_sampler::Add(SourceEntity, FCk_Fragment_IntentSampler_ParamsData(k_RingCapacity)); }

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
    // derived rather than spelled out — a literal would silently stop matching if
    // a key's name ever changed.
    FCk_Input_ButtonId Make_PhysicalButton(FKey InKey)
    {
        return FCk_Input_ButtonId(ECk_Input_ButtonTier::Physical, InKey.GetKeyName());
    }

    // The map is EMPTY on the calling stack of its own Add and fills in when its
    // derivation request drains, so a consumer waits for its terminals to be
    // minted rather than requesting a swap that would be rejected for keys that
    // only look unresolvable.
    bool Get_IsKeyMinted(FCk_Handle_InputButtonMap InButtonMap, FKey InKey)
    {
        if (ck::Is_NOT_Valid(InButtonMap))
        { return false; }

        return utils_input_button_map::Get_ButtonIdsForKey(InButtonMap, InKey).Num() > 0;
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

    // Offset 0 is the newest row, so the first press found walking forward from it
    // is the most recent one — which is the press a completion just behind it was
    // scanning back from.
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

    // DISPLAY ONLY, and the naming says so because the distinction is the whole of
    // CkIntent anti-pattern 23: this counts the rows the RECORD reports the button
    // down for, which is the physical fact and keeps counting straight through a
    // mask. The matcher's accumulator is the policy-applied count, it is not
    // readable, and it is the completions — not this number — that a consumer is
    // allowed to act on.
    //
    // The block is the one reader that acts on a run rather than displaying it,
    // and it is allowed to because there is no verdict to disagree with: nothing
    // grades Q, so the record's held rows are not a second opinion about it — they
    // are the only opinion.
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

    int32 Get_LiveFrameIndex(FCk_Handle_IntentSampler InSampler)
    {
        if (ck::Is_NOT_Valid(InSampler))
        { return -1; }

        return utils_intent_sampler::Get_LatestFrame(InSampler).Get_FrameIndex();
    }

    // Whether the kit's set is live. A swap is deferred and drains two groups
    // ahead of the scan, so polling straight after the request reads the OLD set
    // (CkIntent/CLAUDE.md anti-pattern 21) — this asks the matcher, not the layer,
    // because a capture edit is not visible on the layer for a frame
    // (anti-pattern 18).
    bool Get_IsArmed(FCk_Handle_IntentMatcher InMatcher, FKey InTerminalKey)
    {
        if (ck::Is_NOT_Valid(InMatcher))
        { return false; }

        if (utils_intent_matcher::Get_HasActiveSet(InMatcher) == false)
        { return false; }

        return utils_intent_matcher::Get_RegisteredCaptureKeys(InMatcher).Contains(InTerminalKey);
    }

    //------------------------------------------------------------------------
    // Formatting
    //------------------------------------------------------------------------

    // A raw bool in an interpolated string is not something a viewer of a status
    // line reads as a state.
    FString Format_Bool(bool InValue)
    {
        if (InValue)
        { return "yes"; }

        return "no";
    }

    //------------------------------------------------------------------------
    // Attempt bookkeeping — the anti-pattern-15 shape
    //------------------------------------------------------------------------
    //
    // `Completed` is LATCHED, so branching on the phase alone re-reads the same
    // completion every frame until it decays. The freshness test is the COMPLETION
    // FRAME against the one already recorded, which is exactly what the module's
    // doc prescribes. Keep one record PER MOVE — one shared record would see a
    // sibling's older latch as a fresh landing the moment a newer move overwrote
    // it.

    bool Request_RecordAttempt(
        FCkPlaygroundGym_Attempt& OutAttempt,
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
