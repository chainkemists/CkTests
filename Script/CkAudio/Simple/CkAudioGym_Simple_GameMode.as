class ACk_AudioGym_Simple_GameMode : ACk_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_AudioGym_Simple_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;

    FString Get_GymName() override
    {
        return "Simple Audio Gym";
    }

    FString Get_GymDescription() override
    {
        return "Tests basic AudioCue functionality: background music and spatial audio";
    }

    TArray<FString> Get_RequiredStationTags() override
    {
        auto RequiredTags = TArray<FString>();
        RequiredTags.Add("Gym.Audio.BackgroundMusic");
        RequiredTags.Add("Gym.Audio.SpatialAudio");
        return RequiredTags;
    }
}