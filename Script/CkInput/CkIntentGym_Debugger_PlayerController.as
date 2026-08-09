// Language=angelscript

//============================================================================
// CK INTENT DEBUGGER GYM — PlayerController
//
// Spawns the four stations and owns the two commands that are genuinely
// gym-wide rather than station-scoped.
//
// THERE IS NO AUTO-DEMO TOGGLE, AND THAT IS DELIBERATE. Every other gym's
// `Ck_Gym*_Auto` pauses a state machine that is driving itself. Here the state
// machines advance on what the PLAYER does, so pausing one would freeze the
// instructions mid-sentence and make the gym look broken rather than held.
//
// The diagnostics switch is offered here as well as being armed by the
// near-miss station, because it is a global CVar: somebody who turned it on by
// hand needs one obvious place to turn it back off, and the station's own
// teardown only covers the case where they left the gym.
//============================================================================

class ACk_IntentGym_Debugger_PlayerController : ACk_Gym_Base_PlayerController
{
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        Stations.Add(MakeStationPayload(n"Gym.Intent.DebuggerTimeline", "Timeline & Episodes",
            "Open a wait on demand, and watch the timeline account for it."));

        Stations.Add(MakeStationPayload(n"Gym.Intent.DebuggerLayerStack", "Layer Stack & Masking",
            "Two layers, one masker, and who received your last press."));

        Stations.Add(MakeStationPayload(n"Gym.Intent.DebuggerOctant", "Octant Sweep & Key State",
            "Sweep the stick and check the rosette against the recorded octant."));

        Stations.Add(MakeStationPayload(n"Gym.Intent.DebuggerNearMiss", "Near-Miss Corpus",
            "One motion, three windows, three rows in the near-miss list."));

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
        SpawnStation("Gym.Intent.DebuggerTimeline", "TIMELINE & EPISODES",
            UCk_EntityScript_IntentGym_Debugger_Timeline,
            "Two ways to make a press wait, and the lane that says so.");

        SpawnStation("Gym.Intent.DebuggerLayerStack", "LAYER STACK & MASKING",
            UCk_EntityScript_IntentGym_Debugger_LayerStack,
            "Arm a masker over this station and watch the press stop arriving.");

        SpawnStation("Gym.Intent.DebuggerOctant", "OCTANT SWEEP & KEY STATE",
            UCk_EntityScript_IntentGym_Debugger_Octant,
            "A slow circle on the left stick, read two ways at once.");

        SpawnStation("Gym.Intent.DebuggerNearMiss", "NEAR-MISS CORPUS",
            UCk_EntityScript_IntentGym_Debugger_NearMiss,
            "One unhurried motion fills the near-miss list with three verdicts.");
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

    UFUNCTION(Exec, DisplayName = "Debugger Gym - Near-Miss Recording On/Off")
    void Ck_GymDebugger_Diagnostics(int32 InEnabled = 1)
    {
        if (InEnabled != 0)
        {
            System::ExecuteConsoleCommand("ck.Intent.RecordScanDiagnostics 1");
            Print("[CkIntent Debugger Gym] near-miss recording ON", 6.0f);
            return;
        }

        System::ExecuteConsoleCommand("ck.Intent.RecordScanDiagnostics 0");
        Print("[CkIntent Debugger Gym] near-miss recording OFF", 6.0f);
    }

    // When a panel says nothing at all, this says which of the three things it
    // depends on has not arrived: the player's source, the button space derived
    // from it, or the first sampled row.
    UFUNCTION(Exec, DisplayName = "Debugger Gym - Why Is Nothing Happening")
    void Ck_GymDebugger_Status()
    {
        auto Source = intent_gym::TryGet_PlayerSource();

        if (ck::Is_NOT_Valid(Source))
        {
            Print("[CkIntent Debugger Gym] no input source for local player 0 yet", 8.0f);
            return;
        }

        auto ButtonMap = intent_gym::TryGet_ButtonMap();
        if (ck::Is_NOT_Valid(ButtonMap))
        {
            Print("[CkIntent Debugger Gym] source is up, button map not composed yet", 8.0f);
            return;
        }

        auto Sampler = intent_gym::TryGet_Sampler();
        if (ck::Is_NOT_Valid(Sampler))
        {
            Print("[CkIntent Debugger Gym] source and map are up, sampler not composed yet", 8.0f);
            return;
        }

        auto Buttons = utils_input_button_map::Get_AllButtons(ButtonMap).Num();
        auto Frames = utils_intent_sampler::Get_FrameCount(Sampler);
        auto Octant = intent_gym::Format_Octant(intent_gym::Get_LiveOctant(Sampler));

        Print(f"[CkIntent Debugger Gym] buttons {Buttons}, rows recorded {Frames}, stick {Octant}", 8.0f);
    }
}
