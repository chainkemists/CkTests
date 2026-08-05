// Language=angelscript

// Voice-chat gym PC: composes a loopback VoiceTalker on the player pawn and drives
// push-to-talk off the V key (poll + edge-detect - the gym framework carries no input
// bindings of its own). Each transmit edge flashes on screen: the machine-visible half of
// the roger-beep recipe (module Claude.md, "Consumer recipes") - a consumer binds a cue to
// exactly these edges. Requires [Voice] bEnabled=true in the host project's DefaultEngine.ini
// or the capture source never opens (the standing P2 prerequisite).
class ACk_VoiceChatGym_PlayerController : ACk_Gym_Base_PlayerController
{
    private FCk_Handle_VoiceTalker _GymTalker;
    private bool _PttWasDown = false;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(n"Gym.VoiceChat.MicLoopback");
        Station.Title = FText::FromString("VOICE CHAT — MIC LOOPBACK + TRANSMIT EDGES");
        auto Description = TArray<FText>();
        Description.Add(FText::FromString("HOLD V to talk. Your microphone loops back through the full capture -> VAD -> encode -> jitter -> decode -> synth pipeline: you hear yourself."));
        Description.Add(FText::FromString("Each transmit edge flashes on screen - bind a cue to those signals for a roger beep (recipe: Source/CkVoiceChat/Claude.md, Consumer recipes)."));
        Description.Add(FText::FromString("Prerequisite: [Voice] bEnabled=true in DefaultEngine.ini. Silence with the flash working means the capture source never opened - check that line first."));
        Description.Add(FText::FromString("Spatialization / per-channel attenuation / HybridRadio need a second machine or PIE client - steps live in the campaign's Gate_4.md [EDITOR-VERIFY] block."));
        Station.Description = Description;
        Stations.Add(Station);

        return Stations;
    }

    void Request_StartGym() override
    {
        auto ControlledPawn = GetControlledPawn();

        if (!System::IsValid(ControlledPawn))
        {
            ck::Trace("VoiceChat Gym - no controlled pawn; talker not composed");
            return;
        }

        auto PawnEntity = ck::ToEntity(ControlledPawn);

        if (ck::Is_NOT_Valid(PawnEntity))
        {
            ck::Trace("VoiceChat Gym - pawn has no entity yet; talker not composed");
            return;
        }

        auto Params = FCk_Fragment_VoiceTalker_ParamsData();
        Params.Set_Loopback(ECk_EnableDisable::Enable);
        _GymTalker = utils_voice_talker::Add(PawnEntity, Params);

        utils_voice_talker::BindTo_OnTransmitStarted(_GymTalker,
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_VoiceTalker(this, n"OnTransmitStarted"));
        utils_voice_talker::BindTo_OnTransmitStopped(_GymTalker,
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_VoiceTalker(this, n"OnTransmitStopped"));

        ck::Trace("VoiceChat Gym - loopback talker composed on the pawn; HOLD V to talk");
    }

    UFUNCTION(BlueprintOverride)
    void Tick(float DeltaSeconds)
    {
        if (ck::Is_NOT_Valid(_GymTalker))
        { return; }

        auto PttIsDown = IsInputKeyDown(EKeys::V);

        if (PttIsDown == _PttWasDown)
        { return; }

        _PttWasDown = PttIsDown;

        if (PttIsDown)
        { utils_voice_talker::Request_StartTransmit(_GymTalker, FCk_Request_VoiceTalker_StartTransmit()); }
        else
        { utils_voice_talker::Request_StopTransmit(_GymTalker); }
    }

    UFUNCTION()
    private void OnTransmitStarted(FCk_Handle_VoiceTalker InTalker)
    {
        PrintToScreen("TX START — a roger-beep cue binds HERE", 1.5, FLinearColor::Green);
    }

    UFUNCTION()
    private void OnTransmitStopped(FCk_Handle_VoiceTalker InTalker)
    {
        PrintToScreen("TX END — squelch-close beep binds HERE", 1.5, FLinearColor::Yellow);
    }

    // Console fallbacks for machines where the key poll misbehaves (gym spec convention).
    UFUNCTION(Exec)
    void Ck_GymVoiceChat_TalkStart()
    {
        if (ck::IsValid(_GymTalker))
        { utils_voice_talker::Request_StartTransmit(_GymTalker, FCk_Request_VoiceTalker_StartTransmit()); }
    }

    UFUNCTION(Exec)
    void Ck_GymVoiceChat_TalkStop()
    {
        if (ck::IsValid(_GymTalker))
        { utils_voice_talker::Request_StopTransmit(_GymTalker); }
    }
}
