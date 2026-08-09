// Language=angelscript

//============================================================================
// CK INTENT SOULS GYM — PlayerController
//
// Spawns the three stations and owns the one command that is genuinely gym-wide
// rather than station-scoped.
//
// THERE IS NO AUTO-DEMO TOGGLE, AND THAT IS DELIBERATE. Every other gym's
// `Ck_Gym*_Auto` pauses a state machine that is driving itself. Here the state
// machines advance on what the PLAYER does, so pausing one would freeze the
// instructions mid-sentence and make the gym look broken rather than held. A
// viewer who wants the panel to stop moving stops moving their hands.
//
// The menu on the third station is a KEY, not a command. A charge that a console
// command interrupted would prove the policy fires; a charge that the key under
// the player's own other hand interrupted proves it fires on the thing that
// actually happens in a game.
//============================================================================

class ACk_IntentGym_Souls_PlayerController : ACk_Gym_Base_PlayerController
{
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        Stations.Add(MakeStationPayload(n"Gym.Intent.SoulsTapVsHold", "Tap or Hold",
            "One button, two moves, and the frame the answer arrives on."));

        Stations.Add(MakeStationPayload(n"Gym.Intent.SoulsCharge", "The Charge",
            "Two seconds of holding, counted down in front of you."));

        Stations.Add(MakeStationPayload(n"Gym.Intent.SoulsDeliveryLoss", "The Menu Ate It",
            "What happens to a charge when something opens over it."));

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
        SpawnStation("Gym.Intent.SoulsTapVsHold", "TAP OR HOLD",
            UCk_EntityScript_IntentGym_Souls_TapVsHold,
            "Let go early and you get one move. Hold on and you get the other.");

        SpawnStation("Gym.Intent.SoulsCharge", "THE CHARGE",
            UCk_EntityScript_IntentGym_Souls_Charge,
            "Hold it down and watch the frames run out. Let go and start again.");

        SpawnStation("Gym.Intent.SoulsDeliveryLoss", "THE MENU ATE IT",
            UCk_EntityScript_IntentGym_Souls_DeliveryLoss,
            "Open a menu mid-charge, then try to carry on holding.");
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

    // When a panel says nothing at all, this says which of the three things it
    // depends on has not arrived: the player's source, the button space derived
    // from it, or the first sampled row.
    UFUNCTION(Exec, DisplayName = "Souls Gym - Why Is Nothing Happening")
    void Ck_GymSouls_Status()
    {
        auto Source = intent_gym::TryGet_PlayerSource();

        if (ck::Is_NOT_Valid(Source))
        {
            Print("[CkIntent Souls Gym] no input source for local player 0 yet", 8.0f);
            return;
        }

        auto ButtonMap = intent_gym::TryGet_ButtonMap();
        if (ck::Is_NOT_Valid(ButtonMap))
        {
            Print("[CkIntent Souls Gym] source is up, button map not composed yet", 8.0f);
            return;
        }

        auto Sampler = intent_gym::TryGet_Sampler();
        if (ck::Is_NOT_Valid(Sampler))
        {
            Print("[CkIntent Souls Gym] source and map are up, sampler not composed yet", 8.0f);
            return;
        }

        auto Buttons = utils_input_button_map::Get_AllButtons(ButtonMap).Num();
        auto Frames = utils_intent_sampler::Get_FrameCount(Sampler);

        Print(f"[CkIntent Souls Gym] buttons {Buttons}, rows recorded {Frames}", 8.0f);
    }
}
