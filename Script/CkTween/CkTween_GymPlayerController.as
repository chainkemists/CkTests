class ACk_TweenTest_GymPlayerController : ACk_Gym_Base_PlayerController
{
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        // Create a station for each easing method type
        auto EasingCount = int32(ECk_TweenEasing::ECk_MAX);

        for (int32 Index = 0; Index < EasingCount; ++Index)
        {
            auto EasingMethod = ECk_TweenEasing(Index);
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(FName(f"Gym.Tween.{EasingMethod}"));
            Station.Title = FText::FromString(f"{EasingMethod}");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Demonstrates tween easing behavior."));
            Description.Add(FText::FromString("Cube oscillates vertically using this easing function."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        return Stations;
    }

    void Request_StartGym() override
    {
        auto EasingCount = int32(ECk_TweenEasing::ECk_MAX);

        for (int32 Index = 0; Index < EasingCount; ++Index)
        {
            auto EasingMethod = ECk_TweenEasing(Index);
            Request_SpawnTweenActor(EasingMethod);
        }

        ck::Trace("✅ Tween Gym - All easing methods started");
    }

    void Request_SpawnTweenActor(ECk_TweenEasing InEasingMethod)
    {
        auto StationTag = "Gym.Tween." + f"{InEasingMethod}";
        auto StationTransform = Get_StationAnchorTransform(StationTag, ECk_GymStation_Anchor::PanelCenter);

        auto SpawnedActor = SpawnActor(ACk_TweenTest_GymActor, StationTransform.GetLocation(), FRotator(0, 180, 0), NAME_None, true);
        SpawnedActor.TweenEasingMethod = InEasingMethod;
        FinishSpawningActor(SpawnedActor);
    }

    UFUNCTION(Exec, DisplayName="Tween Gym - Restart All")
    void Ck_GymTween_RestartAll()
    {
        Request_StartGym();
    }
};