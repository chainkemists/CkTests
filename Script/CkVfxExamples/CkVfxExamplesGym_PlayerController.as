// --------------------------------------------------------------------------------------------------------------------
// CkVfxExamples gym PlayerController ("VfxExamples"): an objective A/B fidelity harness. Every ported
// Vefects effect gets a PAIR of adjacent stations - the CkParticles recreation (text-authored HLSL, spawned
// through the normal CkParticles path) beside the ORIGINAL Niagara system, resolved at runtime from candidate
// path strings. The panel R row re-fires both sides in sync so the t=0 flashes can be compared.
//
// ONE pair exists at a time - stations included. All 31 pairs simulating at once (~370 emitter instances
// with the originals installed) collapsed editor frame times to minutes, and 62 pedestals made the live
// pair impossible to find. Only the active pair's two stations are spawned, always at the SAME two spots
// (the default grid layout of a 2-station gym), so switching swaps the world in place around the viewer.
// The pair selector lives in ACk_VfxExamplesGym_HUD (V), with PgUp/PgDn cycling and R restarting hands-free.
//
// Pairs live in CkVfxExamplesGym_Shared.as. Adding a port is a data edit there, not a change here.
//
// Ck_GymVfxExamples_Tune retunes the live recreation without a respawn - an OVERLAY on top of the
// behavior's per-behavior tuning DataAsset, which the spawn path applies. It stays on the console because
// four free-range floats are what a panel row cannot express; the panel T row drops the overlay and
// restarts the pair, because only a respawn brings the asset's values back.
// The chosen pair is remembered across PIE sessions (CkVfxExamplesGym_SaveGame.as).
//
// The FIRST activation of a pair in a session can block the game thread for minutes with nothing logged
// and nothing drawn. Two things follow from that. (1) The spawn is split in two: Request_SpawnActivePair
// decides and announces, Request_SpawnActivePair_Immediate blocks - with a frame in between, so the
// warning is painted while the thread is still alive. The trigger is the pair's own measured duration
// from a previous session, also carried in the SaveGame slot. (2) Every phase is wall-clock bracketed and
// summarised into one greppable `[VfxSetup]` Print, because a block that logs nothing cannot be attributed
// to a phase after the fact.
// --------------------------------------------------------------------------------------------------------------------

class ACk_VfxExamplesGym_PlayerController : ACk_Gym_Base_PlayerController
{
    private TArray<UNiagaraComponent> _Spawned;
    private int32 _ActivePairIndex = 0;
    private bool _bViewerPlaced = false;

    // The recreation half, held apart from _Spawned so live tuning can reach it without also
    // hitting the original standing beside it. _Spawned still owns the destroy sweep.
    private UNiagaraComponent _CkSideComponent;

    // Session-scoped look knobs, re-applied on every respawn of the recreation - but ONLY while the
    // overlay is active. Off, the recreation keeps whatever its per-behavior tuning DataAsset gave it.
    private float32 _TuningSize = 1.0f;
    private float32 _TuningColor = 1.0f;
    private float32 _TuningAlpha = 1.0f;
    private float32 _TuningSpeed = 1.0f;

    // Whether the exec overlay is in force. Identity values are NOT the same thing as "no overlay":
    // writing identity is itself a write, and it would stomp the asset-resolved tuning.
    private bool _bTuneOverlayActive = false;

    // A pair switch is a multi-frame flow (station destroy + spawn + a settle frame before
    // Request_StartGym fires); further switch requests during it are dropped, not queued.
    private bool _bSwitchInFlight = false;

    // A pair whose CkParticles template is still compiling (the first run after a regen) is NOT spawned yet
    // a component spawned into an unfinished compile renders nothing and reads as a broken port. True while a
    // readiness poll is outstanding; the HUD announces it so the empty pedestal is explained.
    private bool _bWaitingForCompile = false;
    private FString _CompileWaitText = "";

    // The pair the outstanding poll was armed for. A switch moves _ActivePairIndex and re-enters the spawn flow
    // on its own, so a poll that no longer matches must drop out instead of spawning a pair nobody selected.
    private int32 _CompileWaitPairIndex = -1;

    // Exactly one poll timer at a time. _bWaitingForCompile cannot carry this on its own: it is cleared the
    // moment a spawn succeeds, and a poll armed before that is still in flight.
    private bool _bCompilePollOutstanding = false;

    // The first activation of a pair in a session can block the game thread for MINUTES inside the spawn
    // calls, silently - nothing draws while it is blocked, so a banner raised at the blocking call is a
    // banner nobody ever sees. Below this many recorded seconds the spawn is indistinguishable from a
    // normal hitch and a banner would be noise.
    private const float32 SetupFreezeThresholdSeconds = 1.0f;

    // The pre-announced freeze banner. Pending means "the text is up, the spawn is one frame away";
    // the TEXT deliberately outlives the pending flag, because it is the only thing on screen for the
    // whole block and must stay until the block ends.
    private bool _bSetupBannerPending = false;
    private FString _SetupBannerText = "";
    private int32 _SetupBannerPairIndex = -1;
    private bool _bSetupBannerTimerOutstanding = false;

    // Phase stamps in wall seconds (FDateTime::UtcNow, NOT UWorld::GetRealTimeSeconds - the world clock
    // is refreshed once per tick, so every stamp taken inside one frame would read identical and the
    // two spawn brackets would both report 0ms). Reset per activation.
    private float64 _SetupEnterStamp = 0.0;
    private float64 _SetupImmediateStamp = 0.0;
    private float64 _SetupCkDoneStamp = 0.0;
    private float64 _SetupOriginalDoneStamp = 0.0;

    // Set on the FIRST entry into the spawn flow for an activation and held across the compile wait and
    // the banner defer, so the gate phase measures the whole pre-spawn cost rather than the last re-entry.
    private bool _bSetupEnterStamped = false;

    // Same staleness + single-outstanding invariants as the compile poll, for the measurement timer.
    private int32 _SetupMeasurePairIndex = -1;
    private bool _bSetupMeasureOutstanding = false;

    // Super starts the base flow, which reaches Get_RequiredStations() below and bakes the
    // active index into the stations it lays out - so the remembered pair must be restored
    // before Super runs, not in Request_StartGym.
    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto _CkPerfScope = ck::ScopedStat();
        _ActivePairIndex = CkVfxExamplesGym_Save::TryLoad_ActivePairIndex(_ActivePairIndex);
        Super::BeginPlay();
    }

    // Only the ACTIVE pair's stations. The base flow lays a 2-station gym out at the same
    // two grid spots every time, which is what keeps switches in-place for the viewer.
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        auto Pairs = CkVfxExamples::Get_Pairs();
        if (_ActivePairIndex < 0 || _ActivePairIndex >= Pairs.Num())
        { return Stations; }

        auto Pair = Pairs[_ActivePairIndex];

        Stations.Add(Make_Station(Pair.CkStationTag,
            Pair.DisplayName + " - CKPARTICLES",
            f"Recreation: CkParticles behavior {Pair.BehaviorId}.",
            "Text-authored HLSL, no Niagara graph."));

        Stations.Add(Make_Station(Pair.OriginalStationTag,
            Pair.DisplayName + " - ORIGINAL",
            Pair.Credit,
            "Niagara asset, resolved at runtime."));

        return Stations;
    }

    // The restart control is printed on every station: this gym's stations are the only place
    // that names it.
    private FCkGym_Station_SpawnParams_Payload Make_Station(FName InTag, FString InTitle, FString InLine1, FString InLine2)
    {
        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(InTag);
        Station.Title = FText::FromString(InTitle);
        auto Description = TArray<FText>();
        Description.Add(FText::FromString(InLine1));
        Description.Add(FText::FromString(InLine2));
        Description.Add(FText::FromString("V selector | PgUp/PgDn cycle | R restarts"));
        Station.Description = Description;
        Station.AutoSize = true;
        return Station;
    }

    // Runs at gym boot AND at the end of every pair switch - the switch flow routes back
    // through Request_EnsureStationsExist, which lands here once the new stations settle.
    void Request_StartGym() override
    {
        _bSwitchInFlight = false;
        Request_SpawnActivePair();

        if (_bViewerPlaced == false)
        {
            _bViewerPlaced = true;
            Request_TeleportToActivePair();
        }
    }

    int32 Get_ActivePairIndex()
    {
        return _ActivePairIndex;
    }

    bool Get_IsTuneOverlayActive()
    {
        return _bTuneOverlayActive;
    }

    bool Get_IsWaitingForCompile()
    {
        return _bWaitingForCompile;
    }

    FString Get_CompileWaitText()
    {
        return _CompileWaitText;
    }

    // Non-empty for the deferring frame AND for the whole freeze that follows it. The HUD draws it
    // unconditionally on that basis - see Request_SpawnActivePair for why one frame has to pass first.
    FString Get_SetupBannerText()
    {
        return _SetupBannerText;
    }

    FString Get_TuningReadout()
    {
        return f"TUNE size {_TuningSize :.1} | color {_TuningColor :.1} | alpha {_TuningAlpha :.1} | speed {_TuningSpeed :.1}";
    }

    // Switches which pair exists. Out-of-range indices wrap so Next/Prev cycle endlessly.
    // Re-activating the CURRENT index is a restart-in-place: both sides respawn in sync
    // from t=0, stations untouched, camera unmoved.
    void Request_ActivatePair(int32 InPairIndex)
    {
        auto Pairs = CkVfxExamples::Get_Pairs();
        if (Pairs.Num() == 0)
        { return; }

        auto WrappedIndex = InPairIndex % Pairs.Num();
        if (WrappedIndex < 0) { WrappedIndex += Pairs.Num(); }

        if (WrappedIndex == _ActivePairIndex)
        {
            Request_SpawnActivePair();
            return;
        }

        if (_bSwitchInFlight)
        { return; }
        _bSwitchInFlight = true;

        Request_ResetSetupTracking();
        Request_DestroyActivePair();
        _ActivePairIndex = WrappedIndex;
        CkVfxExamplesGym_Save::Request_SaveActivePairIndex(_ActivePairIndex);

        // Base flow: lay out + spawn the (new) required stations, await construction,
        // settle one frame, then call Request_StartGym - which spawns the VFX.
        Request_EnsureStationsExist();
    }

    private void Request_DestroyActivePair()
    {
        for (auto Existing : _Spawned)
        {
            if (ck::IsValid(Existing)) { Existing.DestroyComponent(); }
        }
        _Spawned.Empty();
        _CkSideComponent = nullptr;

        auto Pairs = CkVfxExamples::Get_Pairs();
        if (_ActivePairIndex < 0 || _ActivePairIndex >= Pairs.Num())
        { return; }

        auto Pair = Pairs[_ActivePairIndex];
        Request_DestroyStation(Pair.CkStationTag);
        Request_DestroyStation(Pair.OriginalStationTag);
    }

    private void Request_DestroyStation(FName InStationTag)
    {
        auto Handle = Get_StationHandle(InStationTag.ToString());
        if (ck::IsValid(Handle))
        {
            utils_entity_lifetime::Request_DestroyEntity(Handle);
        }
    }

    // The gate half of the spawn flow: readiness, then the freeze-banner decision. Everything that can
    // block the game thread lives in Request_SpawnActivePair_Immediate below, so this half is always
    // cheap enough to return and let a frame render.
    private void Request_SpawnActivePair()
    {
        // Held across the compile wait and the banner defer - the gate phase is the whole pre-spawn cost
        // of THIS activation, not of the last re-entry into it.
        if (_bSetupEnterStamped == false)
        {
            _bSetupEnterStamped = true;
            _SetupEnterStamp = Get_SetupWallSeconds();
        }

        // Clear any prior spawns (supports restart of both sides in sync).
        for (auto Existing : _Spawned)
        {
            if (ck::IsValid(Existing)) { Existing.DestroyComponent(); }
        }
        _Spawned.Empty();
        _CkSideComponent = nullptr;

        auto Pairs = CkVfxExamples::Get_Pairs();
        if (_ActivePairIndex < 0 || _ActivePairIndex >= Pairs.Num())
        {
            _bSetupEnterStamped = false;
            return;
        }

        auto Pair = Pairs[_ActivePairIndex];

        // Neither side spawns until the recreation's template has compiled: spawning the original alone would
        // put the A/B out of phase, and the whole point of the harness is that both start at t=0 together.
        if (utils_particles::Get_IsBehaviorTemplateReady(Pair.BehaviorId) == false)
        {
            Request_BeginCompileWait(Pair);
            return;
        }

        _bWaitingForCompile = false;
        _CompileWaitText = "";

        // A pair that froze the game thread last session freezes it again. Nothing draws during the block,
        // so the warning has to reach the screen BEFORE the blocking call - which costs a frame: this one
        // only sets the text, and the timer below spawns on the next.
        auto RecordedSeconds = CkVfxExamplesGym_Save::TryGet_PairSetupSeconds(_ActivePairIndex);
        if (RecordedSeconds > SetupFreezeThresholdSeconds)
        {
            Request_BeginSetupBannerWait(Pair, RecordedSeconds);
            return;
        }

        Request_SpawnActivePair_Immediate();
    }

    // The half that can disappear for minutes. Split out so the banner above can be PAINTED first;
    // reached either directly (nothing recorded) or one frame later from OnSetupBannerElapsed.
    private void Request_SpawnActivePair_Immediate()
    {
        auto Pairs = CkVfxExamples::Get_Pairs();
        if (_ActivePairIndex < 0 || _ActivePairIndex >= Pairs.Num())
        {
            _bSetupEnterStamped = false;
            return;
        }

        auto Pair = Pairs[_ActivePairIndex];

        // Bracketed per side: the whole point of the instrumentation is to say WHICH of the two spawn
        // paths owns the block, which a single total cannot.
        _SetupImmediateStamp = Get_SetupWallSeconds();
        Request_SpawnCkSide(Pair);
        _SetupCkDoneStamp = Get_SetupWallSeconds();
        Request_SpawnOriginalSide(Pair);
        _SetupOriginalDoneStamp = Get_SetupWallSeconds();

        // Logged HERE rather than in Request_StartGym so a restart is observable too - the
        // start-only trace made an invoked restart indistinguishable from one that never ran.
        ck::Trace(f"🟣 VfxExamples Gym - [{_ActivePairIndex}/{Pairs.Num()}] {Pair.DisplayName} live from t=0");

        Request_BeginSetupMeasure();
    }

    // Wall clock, not world clock. UWorld::GetRealTimeSeconds is refreshed once per tick, so it cannot
    // separate two stamps taken inside the same frame - which is every stamp in the spawn body.
    private float64 Get_SetupWallSeconds()
    {
        auto SinceEpoch = FDateTime::UtcNow() - FDateTime::MinValue();
        return SinceEpoch.GetTotalSeconds();
    }

    // Arms the deferring frame. Same single-outstanding + staleness invariants as the compile poll, and
    // like it, deliberately leaves _bSwitchInFlight alone so the selector stays live during the wait.
    private void Request_BeginSetupBannerWait(FCk_VfxExamples_Pair InPair, float32 InRecordedSeconds)
    {
        _bSetupBannerPending = true;
        _SetupBannerPairIndex = _ActivePairIndex;
        _SetupBannerText = f"SETTING UP {InPair.DisplayName} — took ~{InRecordedSeconds :.0}s last time; editor will freeze, effect appears when done";

        if (_bSetupBannerTimerOutstanding)
        { return; }

        _bSetupBannerTimerOutstanding = true;

        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(0.05));
        Params.Set_StartingState(ECk_Timer_State::Running)
              .Set_Behavior(ECk_Timer_Behavior::StopOnDone);
        auto Timer = utils_timer::Add(ck::ToEntity(this), Params);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnSetupBannerElapsed"));
    }

    UFUNCTION()
    private void OnSetupBannerElapsed(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        _bSetupBannerTimerOutstanding = false;

        if (_bSetupBannerPending == false)
        { return; }

        _bSetupBannerPending = false;

        // A switch superseded this activation - its own flow spawns whatever is selected now. Nothing is
        // cleared on the way out: Request_ResetSetupTracking already did that for the OLD activation, and
        // the NEW one has since re-armed the same members. Touching them here would clobber it.
        if (_SetupBannerPairIndex != _ActivePairIndex)
        { return; }

        // _SetupBannerText is NOT cleared here: the block starts on the next line and nothing will draw
        // again until it ends, so the text has to survive into the freeze. The measurement clears it.
        Request_SpawnActivePair_Immediate();
    }

    // The frame after the spawn calls only ARRIVES once the game thread unblocks, so this timer's fire
    // time is the honest end of the freeze - nothing measurable from inside the spawn call can say that.
    // Costs a ~50ms floor on the firstFrameAfter figure when there is no block, which is the same idiom
    // (and the same floor) the compile poll runs on.
    private void Request_BeginSetupMeasure()
    {
        _SetupMeasurePairIndex = _ActivePairIndex;

        if (_bSetupMeasureOutstanding)
        { return; }

        _bSetupMeasureOutstanding = true;

        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(0.05));
        Params.Set_StartingState(ECk_Timer_State::Running)
              .Set_Behavior(ECk_Timer_Behavior::StopOnDone);
        auto Timer = utils_timer::Add(ck::ToEntity(this), Params);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnSetupMeasureElapsed"));
    }

    UFUNCTION()
    private void OnSetupMeasureElapsed(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        _bSetupMeasureOutstanding = false;

        // Superseded - these stamps describe a pair that is no longer live, and recording them under the
        // CURRENT index would poison the next session's banner decision with another pair's number. Drops
        // out WITHOUT clearing anything: the switch that superseded it already reset the tracking, and the
        // activation now in flight has re-armed those same members.
        if (_SetupMeasurePairIndex != _ActivePairIndex)
        { return; }

        auto Now = Get_SetupWallSeconds();

        auto GateMs          = (_SetupImmediateStamp - _SetupEnterStamp) * 1000.0;
        auto CkSpawnMs       = (_SetupCkDoneStamp - _SetupImmediateStamp) * 1000.0;
        auto OriginalSpawnMs = (_SetupOriginalDoneStamp - _SetupCkDoneStamp) * 1000.0;
        auto FirstFrameMs    = (Now - _SetupOriginalDoneStamp) * 1000.0;
        auto TotalMs         = (Now - _SetupEnterStamp) * 1000.0;

        auto Pairs = CkVfxExamples::Get_Pairs();
        FString DisplayName = "?";
        if (_ActivePairIndex >= 0 && _ActivePairIndex < Pairs.Num())
        { DisplayName = Pairs[_ActivePairIndex].DisplayName; }

        // Print rather than ck::Trace: this line's job is to be greppable in the full log
        // (LogBlueprintUserMessages), not to be legible on screen during a session.
        Print(f"[VfxSetup] pair={_ActivePairIndex} {DisplayName} gate={GateMs :.0}ms ckSpawn={CkSpawnMs :.0}ms originalSpawn={OriginalSpawnMs :.0}ms firstFrameAfter={FirstFrameMs :.0}ms total={TotalMs :.0}ms");

        // What the banner predicts is the FREEZE, so the recorded figure excludes the gate: compile-wait
        // time is long, already announced by its own banner, and would double-count as a freeze warning.
        auto SetupSeconds = float32(Now - _SetupImmediateStamp);
        CkVfxExamplesGym_Save::Request_SavePairSetupSeconds(_ActivePairIndex, SetupSeconds);

        _SetupBannerText = "";
        _bSetupEnterStamped = false;
    }

    // A switch abandons whatever the previous activation was measuring: the stamps describe a pair that is
    // no longer live, and the banner would keep warning about a freeze that has already happened. The
    // outstanding timers are left alone - their own staleness guards drop them.
    private void Request_ResetSetupTracking()
    {
        _bSetupEnterStamped = false;
        _bSetupBannerPending = false;
        _SetupBannerText = "";
    }

    // Arms (or re-aims) the readiness poll. Deliberately leaves _bSwitchInFlight alone: Request_StartGym clears
    // that flag BEFORE it reaches the spawn, so the selector stays live for the whole wait - switching pairs
    // while one compiles is exactly the case that has to keep working.
    private void Request_BeginCompileWait(FCk_VfxExamples_Pair InPair)
    {
        _bWaitingForCompile = true;
        _CompileWaitPairIndex = _ActivePairIndex;
        _CompileWaitText = f"{InPair.DisplayName} (behavior {InPair.BehaviorId})";

        if (_bCompilePollOutstanding)
        { return; }

        _bCompilePollOutstanding = true;

        // Mirrors the base PC's WaitOneFrame, which is private to it. Hosted on the PC's OWN entity rather than
        // on a station, because a switch destroys the stations and a poll that died with one would strand the
        // wait flag.
        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(0.05));
        Params.Set_StartingState(ECk_Timer_State::Running)
              .Set_Behavior(ECk_Timer_Behavior::StopOnDone);
        auto Timer = utils_timer::Add(ck::ToEntity(this), Params);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnCompileWaitPoll"));
    }

    UFUNCTION()
    private void OnCompileWaitPoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        _bCompilePollOutstanding = false;

        if (_bWaitingForCompile == false)
        { return; }

        // A switch superseded this spawn - its own flow spawns whatever is selected now. Dropping out silently
        // is the whole guard; re-entering would spawn the pair the viewer just moved off.
        if (_CompileWaitPairIndex != _ActivePairIndex)
        {
            _bWaitingForCompile = false;
            _CompileWaitText = "";
            return;
        }

        Request_SpawnActivePair();
    }

    // Places the viewer between the pair's two agent-spawn front anchors, backed off far
    // enough to frame both pedestals, looking at the midpoint of the two stations. Runs
    // ONCE at gym boot - the stations sit at the same two spots for every pair, so after
    // a switch the viewer is already exactly where they chose to stand.
    private void Request_TeleportToActivePair()
    {
        auto Pairs = CkVfxExamples::Get_Pairs();
        if (_ActivePairIndex < 0 || _ActivePairIndex >= Pairs.Num())
        { return; }

        auto Pair = Pairs[_ActivePairIndex];
        auto ViewPawn = GetControlledPawn();
        if (ck::Is_NOT_Valid(ViewPawn))
        { return; }

        auto CkStation = Get_StationTransform(Pair.CkStationTag.ToString());
        auto OriginalStation = Get_StationTransform(Pair.OriginalStationTag.ToString());
        auto Focus = (CkStation.Location + OriginalStation.Location) * 0.5 + FVector(0, 0, 140);

        auto Standpoint = (Get_StationAnchorLocation(Pair.CkStationTag.ToString(), ECk_GymStation_Anchor::AgentSpawnFront)
                         + Get_StationAnchorLocation(Pair.OriginalStationTag.ToString(), ECk_GymStation_Anchor::AgentSpawnFront)) * 0.5;

        auto BackOff = Standpoint - Focus;
        BackOff.Z = 0.0;
        BackOff = BackOff.GetSafeNormal();
        Standpoint += BackOff * 350.0 + FVector(0, 0, 90);

        ViewPawn.SetActorLocation(Standpoint);

        auto Eye = Standpoint + FVector(0, 0, 60);
        SetControlRotation((Focus - Eye).Rotation());
    }

    private void Request_SpawnCkSide(FCk_VfxExamples_Pair InPair)
    {
        auto StationTransform = Get_StationTransform(InPair.CkStationTag.ToString());
        auto Location = StationTransform.Location + InPair.SpawnOffset;

        auto Component = UCk_Utils_Particles_UE::Spawn_BehaviorAtLocation(
            InPair.BehaviorId, Location, FRotator::ZeroRotator,
            FVector(InPair.Scale, InPair.Scale, InPair.Scale), InPair.TextureName);

        if (ck::IsValid(Component))
        {
            _Spawned.Add(Component);
            _CkSideComponent = Component;

            // The one place the recreation becomes live, so every path that respawns it
            // gym boot, pair switch, the panel R row - re-applies the stored
            // tuning here rather than each calling site remembering to.
            Request_ApplyTuningToCkSide();
        }
        else
        {
            ck::Error(f"[FAIL] VfxExamples gym: failed to spawn CkParticles BehaviorId {InPair.BehaviorId}");
        }
    }

    // Tuning shifts only the RECREATION half of the A/B: the Vefects original has no
    // User.CkTuning parameter to write, so it deliberately stays at its authored values
    // and remains the reference the recreation is judged against.
    private void Request_ApplyTuningToCkSide()
    {
        // An inactive overlay writes NOTHING, leaving the per-behavior tuning DataAsset's values
        // applied by the spawn path - in force. Writing identity here would silently erase them.
        if (_bTuneOverlayActive == false)
        { return; }

        if (ck::Is_NOT_Valid(_CkSideComponent))
        { return; }

        utils_particles::Request_ApplyTuningValues(
            _CkSideComponent, _TuningSize, _TuningColor, _TuningAlpha, _TuningSpeed);
    }

    private void Request_SpawnOriginalSide(FCk_VfxExamples_Pair InPair)
    {
        auto System = CkVfxExamples::TryLoad_OriginalSystem(InPair);

        if (ck::Is_NOT_Valid(System))
        {
            Show_MissingOriginalPlaceholder(InPair);
            return;
        }

        auto StationTransform = Get_StationTransform(InPair.OriginalStationTag.ToString());
        auto Location = StationTransform.Location + InPair.SpawnOffset;

        auto AutoDestroy = false;
        auto AutoActivate = true;
        auto PreCullCheck = true;

        auto Component = Niagara::SpawnSystemAtLocation(
            System, Location, FRotator::ZeroRotator,
            FVector(InPair.Scale, InPair.Scale, InPair.Scale),
            AutoDestroy, AutoActivate, ENCPoolMethod::None, PreCullCheck);

        if (ck::IsValid(Component))
        {
            _Spawned.Add(Component);

            // The originals are FINISHING systems; the CkParticles templates loop by design.
            // Without this re-arm the original pedestal plays once and then sits inactive
            // forever, which is useless for an A/B comparison. A system whose emitters loop
            // infinitely (NS_Lightning_Range) never fires this - binding it is harmless.
            Component.OnSystemFinished.AddUFunction(this, n"OnOriginalSystemFinished");
        }
    }

    UFUNCTION()
    private void OnOriginalSystemFinished(UNiagaraComponent PSystem)
    {
        CkVfxExamples::Request_RestartComponent(PSystem);
    }

    // An absent Vefects install is an expected state, not a defect - this branch stays
    // silent at Warning/Error level and says what to install on the station itself.
    private void Show_MissingOriginalPlaceholder(FCk_VfxExamples_Pair InPair)
    {
        auto Display = FCkGym_Station_TitleAndDescription();
        Display.Title = FText::FromString(InPair.DisplayName + " - ORIGINAL");
        Display.Description = FText::FromString(
            InPair.Credit + "\nadd the Vefects content plugin to view the original vfx"
            + "\npanel [R] restarts both sides in sync");
        Set_StationTitleAndDescription(InPair.OriginalStationTag.ToString(), Display);
    }

    //--------------------------------------------------------------------------------------------------------------------------
    // CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
    //
    // The hands-on-viewport shortcuts, which used to be polled loose in the HUD and advertised as one line
    // of text. They live here now so there is ONE place that says which keys this gym takes. V stays in the
    // HUD because it opens a HUD-owned menu that returns before the panel is ever reached.
    //--------------------------------------------------------------------------------------------------------------------------

    FString Get_ControlPanelTitle() override
    {
        return "VFX PAIRS";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();

        Rows.Add(CkGym_Control::Action(EKeys::PageDown, "PgDn", "Next pair"));
        Rows.Add(CkGym_Control::Action(EKeys::PageUp, "PgUp", "Previous pair"));
        Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Restart both sides in sync"));
        Rows.Add(CkGym_Control::Status("V opens the searchable pair list"));
        Rows.Add(CkGym_Control::Action(EKeys::T, "T", "Drop the tuning overlay"));

        Rows.Add(CkGym_Control::Header("CONSOLE (free-range input the panel cannot express)"));
        Rows.Add(CkGym_Control::Status("Tune the live recreation", "Ck_GymVfxExamples_Tune <size> <color> <alpha> <speed>"));
        Rows.Add(CkGym_Control::Status("Jump to a pair by index", "Ck_GymVfxExamples_GoTo <index>"));
        Rows.Add(CkGym_Control::Status("List every pair to the log", "Ck_GymVfxExamples_List"));

        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex == 0) { Request_ActivatePair(Get_ActivePairIndex() + 1); }
        else if (InRowIndex == 1) { Request_ActivatePair(Get_ActivePairIndex() - 1); }
        else if (InRowIndex == 2) { Request_SpawnActivePair(); }
        else if (InRowIndex == 4) { Request_ResetTuning(); }
    }

    UFUNCTION(Exec, DisplayName="VfxExamples Gym - Go To Pair")
    void Ck_GymVfxExamples_GoTo(int32 InPairIndex)
    {
        Request_ActivatePair(InPairIndex);
    }

    UFUNCTION(Exec, DisplayName="VfxExamples Gym - Tune Active Pair")
    void Ck_GymVfxExamples_Tune(float32 InSizeMultiplier = 1.0f, float32 InColorIntensity = 1.0f, float32 InAlphaMultiplier = 1.0f, float32 InPlaybackSpeed = 1.0f)
    {
        _bTuneOverlayActive = true;

        _TuningSize = InSizeMultiplier;
        _TuningColor = InColorIntensity;
        _TuningAlpha = InAlphaMultiplier;
        _TuningSpeed = InPlaybackSpeed;

        Request_ApplyTuningToCkSide();
    }

    // Dropping the overlay RESPAWNS the pair rather than writing identity: the asset's values only
    // reach the component through the spawn path, so a live identity write cannot restore them.
    private void Request_ResetTuning()
    {
        _bTuneOverlayActive = false;

        _TuningSize = 1.0f;
        _TuningColor = 1.0f;
        _TuningAlpha = 1.0f;
        _TuningSpeed = 1.0f;

        Request_SpawnActivePair();
    }

    UFUNCTION(Exec, DisplayName="VfxExamples Gym - List Pairs")
    void Ck_GymVfxExamples_List()
    {
        auto Pairs = CkVfxExamples::Get_Pairs();
        for (int32 i = 0; i < Pairs.Num(); i++)
        {
            auto Marker = (i == _ActivePairIndex) ? "  *" : "";
            ck::Trace(f"[{i}] {Pairs[i].DisplayName}{Marker}");
        }
    }
}
