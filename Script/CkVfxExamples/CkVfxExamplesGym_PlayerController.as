// --------------------------------------------------------------------------------------------------------------------
// CkVfxExamples gym PlayerController ("VfxExamples"): an objective A/B fidelity harness. Every ported
// Vefects effect gets a PAIR of adjacent stations — the CkParticles recreation (text-authored HLSL, spawned
// through the normal CkParticles path) beside the ORIGINAL Niagara system, resolved at runtime from candidate
// path strings. Ck_GymVfxExamples_RestartAll re-fires both sides in sync so the t=0 flashes can be compared.
//
// ONE pair exists at a time — stations included. All 31 pairs simulating at once (~370 emitter instances
// with the originals installed) collapsed editor frame times to minutes, and 62 pedestals made the live
// pair impossible to find. Only the active pair's two stations are spawned, always at the SAME two spots
// (the default grid layout of a 2-station gym), so switching swaps the world in place around the viewer.
// The pair selector lives in ACk_VfxExamplesGym_HUD (V), with PgUp/PgDn cycling and R restarting hands-free.
//
// Pairs live in CkVfxExamplesGym_Shared.as. Adding a port is a data edit there, not a change here.
// --------------------------------------------------------------------------------------------------------------------

class ACk_VfxExamplesGym_PlayerController : ACk_Gym_Base_PlayerController
{
    private TArray<UNiagaraComponent> _Spawned;
    private int32 _ActivePairIndex = 0;
    private bool _bViewerPlaced = false;

    // A pair switch is a multi-frame flow (station destroy + spawn + a settle frame before
    // Request_StartGym fires); further switch requests during it are dropped, not queued.
    private bool _bSwitchInFlight = false;

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

    // The restart command is printed on every station: this gym's stations are the only place
    // that names it, and reaching for the neighbouring gym's Ck_GymParticles_RestartAll (which
    // this PlayerController does not implement) silently does nothing.
    private FCkGym_Station_SpawnParams_Payload Make_Station(FName InTag, FString InTitle, FString InLine1, FString InLine2)
    {
        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(InTag);
        Station.Title = FText::FromString(InTitle);
        auto Description = TArray<FText>();
        Description.Add(FText::FromString(InLine1));
        Description.Add(FText::FromString(InLine2));
        Description.Add(FText::FromString("V selector | PgUp/PgDn cycle | Ck_GymVfxExamples_RestartAll"));
        Station.Description = Description;
        Station.AutoSize = true;
        return Station;
    }

    // Runs at gym boot AND at the end of every pair switch — the switch flow routes back
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

        Request_DestroyActivePair();
        _ActivePairIndex = WrappedIndex;

        // Base flow: lay out + spawn the (new) required stations, await construction,
        // settle one frame, then call Request_StartGym — which spawns the VFX.
        Request_EnsureStationsExist();
    }

    private void Request_DestroyActivePair()
    {
        for (auto Existing : _Spawned)
        {
            if (ck::IsValid(Existing)) { Existing.DestroyComponent(); }
        }
        _Spawned.Empty();

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

    private void Request_SpawnActivePair()
    {
        // Clear any prior spawns (supports restart of both sides in sync).
        for (auto Existing : _Spawned)
        {
            if (ck::IsValid(Existing)) { Existing.DestroyComponent(); }
        }
        _Spawned.Empty();

        auto Pairs = CkVfxExamples::Get_Pairs();
        if (_ActivePairIndex < 0 || _ActivePairIndex >= Pairs.Num())
        { return; }

        auto Pair = Pairs[_ActivePairIndex];
        Request_SpawnCkSide(Pair);
        Request_SpawnOriginalSide(Pair);

        // Logged HERE rather than in Request_StartGym so a restart is observable too — the
        // start-only trace made an invoked restart indistinguishable from one that never ran.
        ck::Trace(f"🟣 VfxExamples Gym - [{_ActivePairIndex}/{Pairs.Num()}] {Pair.DisplayName} live from t=0");
    }

    // Places the viewer between the pair's two agent-spawn front anchors, backed off far
    // enough to frame both pedestals, looking at the midpoint of the two stations. Runs
    // ONCE at gym boot — the stations sit at the same two spots for every pair, so after
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
        }
        else
        {
            ck::Error(f"❌ VfxExamples gym: failed to spawn CkParticles BehaviorId {InPair.BehaviorId}");
        }
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
            // infinitely (NS_Lightning_Range) never fires this — binding it is harmless.
            Component.OnSystemFinished.AddUFunction(this, n"OnOriginalSystemFinished");
        }
    }

    UFUNCTION()
    private void OnOriginalSystemFinished(UNiagaraComponent PSystem)
    {
        CkVfxExamples::Request_RestartComponent(PSystem);
    }

    // An absent Vefects install is an expected state, not a defect — this branch stays
    // silent at Warning/Error level and says what to install on the station itself.
    private void Show_MissingOriginalPlaceholder(FCk_VfxExamples_Pair InPair)
    {
        auto Display = FCkGym_Station_TitleAndDescription();
        Display.Title = FText::FromString(InPair.DisplayName + " - ORIGINAL");
        Display.Description = FText::FromString(
            InPair.Credit + "\nadd the Vefects content plugin to view the original vfx"
            + "\nCk_GymVfxExamples_RestartAll");
        Set_StationTitleAndDescription(InPair.OriginalStationTag.ToString(), Display);
    }

    // Name kept from the all-pairs era: every cookbook recipe's §12 walk cites it, and its
    // job — re-fire both sides of what you are looking at in sync — is unchanged; only the
    // set of live pairs shrank to one.
    UFUNCTION(Exec, DisplayName="VfxExamples Gym - Restart Active Pair")
    void Ck_GymVfxExamples_RestartAll()
    {
        Request_SpawnActivePair();
    }

    UFUNCTION(Exec, DisplayName="VfxExamples Gym - Next Pair")
    void Ck_GymVfxExamples_Next()
    {
        Request_ActivatePair(_ActivePairIndex + 1);
    }

    UFUNCTION(Exec, DisplayName="VfxExamples Gym - Previous Pair")
    void Ck_GymVfxExamples_Prev()
    {
        Request_ActivatePair(_ActivePairIndex - 1);
    }

    UFUNCTION(Exec, DisplayName="VfxExamples Gym - Go To Pair")
    void Ck_GymVfxExamples_GoTo(int32 InPairIndex)
    {
        Request_ActivatePair(InPairIndex);
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
