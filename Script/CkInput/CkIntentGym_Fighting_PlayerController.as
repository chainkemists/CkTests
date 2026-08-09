// Language=angelscript

//============================================================================
// CK INTENT FIGHTING GYM — PlayerController
//
// Spawns the three stations and owns the two commands that are genuinely
// gym-wide rather than station-scoped.
//
// THERE IS NO AUTO-DEMO TOGGLE, AND THAT IS DELIBERATE. Every other gym's
// `Ck_Gym*_Auto` pauses a state machine that is driving itself. Here the state
// machines advance on what the PLAYER does, so pausing one would freeze the
// instructions mid-sentence and make the gym look broken rather than held. A
// viewer who wants the panel to stop moving stops moving their hands.
//
// The diagnostics switch is offered here as well as being armed by the near-miss
// station, because it is a global CVar: somebody who turned it on by hand needs
// one obvious place to turn it back off, and the station's own teardown only
// covers the case where they left the gym.
//============================================================================

class ACk_IntentGym_Fighting_PlayerController : ACk_Gym_Base_PlayerController
{
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        Stations.Add(MakeStationPayload(n"Gym.Intent.DeferralCounter", "Deferral Counter",
            "How many frames pass between your press and the move coming out."));

        Stations.Add(MakeStationPayload(n"Gym.Intent.DeferredVsInstant", "Waits vs Answers",
            "One button that has to hesitate, one that never does."));

        Stations.Add(MakeStationPayload(n"Gym.Intent.NearMiss", "Near Miss",
            "Why the move you just did did not come out."));

        return Stations;
    }

    private FCkGym_Station_SpawnParams_Payload MakeStationPayload(FName InTag, FString InTitle, FString InDesc)
    {
        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(InTag);
        Station.Title = FText::FromString(InTitle);
        auto Desc = TArray<FText>();
        Desc.Add(FText::FromString(InDesc));
        Station.Description = Desc;
        Station.AutoSize = true;
        return Station;
    }

    void Request_StartGym() override
    {
        SpawnStation("Gym.Intent.DeferralCounter", "DEFERRAL COUNTER",
            UCk_EntityScript_IntentGym_DeferralCounter,
            "Do a quarter-circle and punch. The delay must read zero.");

        SpawnStation("Gym.Intent.DeferredVsInstant", "WAITS VS ANSWERS",
            UCk_EntityScript_IntentGym_DeferredVsInstant,
            "Two buttons in one move set, answered on different frames.");

        SpawnStation("Gym.Intent.NearMiss", "NEAR MISS",
            UCk_EntityScript_IntentGym_NearMiss,
            "Miss on purpose, and read back exactly what was missing.");
    }

    private void SpawnStation(
        FString InTag,
        FString InTitle,
        TSubclassOf<UCk_EntityScript_UE> InStationClass,
        FString InDescription)
    {
        auto Params = FCkIntentGym_StationSpawnParams();
        Params.InitialTransform = Get_StationAnchorTransform(InTag, ECk_GymStation_Anchor::PanelCenter);
        Params.StationTitle = InTitle;
        Params.StationDescription = InDescription;

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle(InTag),
            InStationClass,
            FInstancedStruct::Make(Params));
    }

    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName = "Intent Gym - Near-Miss Recording On/Off")
    void Ck_GymIntent_Diagnostics(int32 InEnabled = 1)
    {
        if (InEnabled != 0)
        {
            System::ExecuteConsoleCommand("ck.Intent.RecordScanDiagnostics 1");
            Print("[CkIntent Gym] near-miss recording ON", 6.0f);
            return;
        }

        System::ExecuteConsoleCommand("ck.Intent.RecordScanDiagnostics 0");
        Print("[CkIntent Gym] near-miss recording OFF", 6.0f);
    }

    // When a panel says nothing at all, this says which of the three things it
    // depends on has not arrived: the player's source, the button space derived
    // from it, or the first sampled row.
    UFUNCTION(Exec, DisplayName = "Intent Gym - Why Is Nothing Happening")
    void Ck_GymIntent_Status()
    {
        auto Source = intent_gym::TryGet_PlayerSource();

        if (ck::Is_NOT_Valid(Source))
        {
            Print("[CkIntent Gym] no input source for local player 0 yet", 8.0f);
            return;
        }

        auto ButtonMap = intent_gym::TryGet_ButtonMap();
        if (ck::Is_NOT_Valid(ButtonMap))
        {
            Print("[CkIntent Gym] source is up, button map not composed yet", 8.0f);
            return;
        }

        auto Sampler = intent_gym::TryGet_Sampler();
        if (ck::Is_NOT_Valid(Sampler))
        {
            Print("[CkIntent Gym] source and map are up, sampler not composed yet", 8.0f);
            return;
        }

        auto Buttons = utils_input_button_map::Get_AllButtons(ButtonMap).Num();
        auto Frames = utils_intent_sampler::Get_FrameCount(Sampler);
        auto Octant = intent_gym::Format_Octant(intent_gym::Get_LiveOctant(Sampler));

        Print(f"[CkIntent Gym] buttons {Buttons}, rows recorded {Frames}, stick {Octant}", 8.0f);
    }
}
