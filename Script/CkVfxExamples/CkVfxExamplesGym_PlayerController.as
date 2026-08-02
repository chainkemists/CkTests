// --------------------------------------------------------------------------------------------------------------------
// CkVfxExamples gym PlayerController ("VfxExamples"): an objective A/B fidelity harness. Every ported
// Vefects effect gets a PAIR of adjacent stations — the CkParticles recreation (text-authored HLSL, spawned
// through the normal CkParticles path) beside the ORIGINAL Niagara system, resolved at runtime from candidate
// path strings. Ck_GymVfxExamples_RestartAll re-fires both sides in sync so the t=0 flashes can be compared.
//
// Pairs live in CkVfxExamplesGym_Shared.as. Adding a port is a data edit there, not a change here.
// --------------------------------------------------------------------------------------------------------------------

class ACk_VfxExamplesGym_PlayerController : ACk_Gym_Base_PlayerController
{
    private TArray<UNiagaraComponent> _Spawned;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        for (auto Pair : CkVfxExamples::Get_Pairs())
        {
            Stations.Add(Make_Station(Pair.CkStationTag,
                Pair.DisplayName + " - CKPARTICLES",
                f"Recreation: CkParticles behavior {Pair.BehaviorId}.",
                "Text-authored HLSL, no Niagara graph."));

            Stations.Add(Make_Station(Pair.OriginalStationTag,
                Pair.DisplayName + " - ORIGINAL",
                Pair.Credit,
                "Niagara asset, resolved at runtime."));
        }

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
        Description.Add(FText::FromString("Ck_GymVfxExamples_RestartAll"));
        Station.Description = Description;
        Station.AutoSize = true;
        return Station;
    }

    void Request_StartGym() override
    {
        Request_SpawnAllPairs();
    }

    void Request_SpawnAllPairs()
    {
        // Clear any prior spawns (supports restart of both sides in sync).
        for (auto Existing : _Spawned)
        {
            if (ck::IsValid(Existing)) { Existing.DestroyComponent(); }
        }
        _Spawned.Empty();

        auto Pairs = CkVfxExamples::Get_Pairs();

        for (auto Pair : Pairs)
        {
            Request_SpawnCkSide(Pair);
            Request_SpawnOriginalSide(Pair);
        }

        // Logged HERE rather than in Request_StartGym so a restart is observable too — the
        // start-only trace made an invoked restart indistinguishable from one that never ran.
        ck::Trace(f"🟣 VfxExamples Gym - {Pairs.Num()} A/B pair(s) spawned from t=0");
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

    UFUNCTION(Exec, DisplayName="VfxExamples Gym - Restart All Pairs")
    void Ck_GymVfxExamples_RestartAll()
    {
        Request_SpawnAllPairs();
    }
}
