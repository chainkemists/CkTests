// Language=angelscript

//============================================================================
// ENTITY SCRIPT SPAWN GYM - PLAYER CONTROLLER
//============================================================================

class ACk_EntityScriptGym_Spawn_PlayerController : ACk_Gym_Base_PlayerController
{
    FName ExpectedTestName = n"GymTestEntity";
    int32 ExpectedTestInt = 42;
    float32 ExpectedTestFloat = 3.14f;

    private FString StationTitle = "ENTITY SCRIPT SPAWN";
    private TArray<FText> StationDescriptionLines;

    private TArray<FText> Get_StationDescriptionLines()
    {
        if (StationDescriptionLines.Num() == 0)
        {
            StationDescriptionLines.Add(FText::FromString("Verifies that ExposeOnSpawn properties are correctly injected"));
            StationDescriptionLines.Add(FText::FromString("during entity script spawning."));
            StationDescriptionLines.Add(FText::FromString("Console: Ck_GymEntityScript_RestartSpawnTest"));
        }
        return StationDescriptionLines;
    }

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.EntityScript.Spawn");
            Station.Title = FText::FromString(StationTitle);
            Station.Description = Get_StationDescriptionLines();
            Station.Description.Add(FText::FromString(""));
            Station.Description.Add(FText::FromString("Waiting for entity to spawn..."));
            Stations.Add(Station);
        }

        return Stations;
    }

    void Request_StartGym() override
    {
        Request_StartSpawnTest();
        ck::Trace("Entity Script Spawn Gym started");
    }

    void Request_StartSpawnTest()
    {
        auto SpawnParams = FEntityScriptGym_SpawnParams();
        SpawnParams.InitialTransform = Get_StationTransform("Gym.EntityScript.Spawn");
        SpawnParams.TestName = ExpectedTestName;
        SpawnParams.TestInt = ExpectedTestInt;
        SpawnParams.TestFloat = ExpectedTestFloat;

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.EntityScript.Spawn"),
            UCk_EntityScript_EntityScriptGym_Spawn,
            FInstancedStruct::Make(SpawnParams)
        );

        if (ck::IsValid(SpawnRequest))
        {
            utils_pending_entity_script::Promise_OnConstructed(SpawnRequest, FCk_Delegate_EntityScript_Constructed(this, n"OnSpawnTestConstructed"));
        }
        else
        {
            ck::Error("Failed to spawn EntityScript Spawn test entity");
        }
    }

    UFUNCTION()
    private void OnSpawnTestConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        const auto& Received = InEntityScriptHandle.Get_Fragment(FEntityScriptGym_SpawnParams);

        auto NamePass = (Received.TestName == ExpectedTestName);
        auto IntPass = (Received.TestInt == ExpectedTestInt);
        auto FloatPass = (Math::Abs(Received.TestFloat - ExpectedTestFloat) < 0.001f);
        auto AllPassed = NamePass && IntPass && FloatPass;

        auto DisplayText = "";
        for (auto Line : Get_StationDescriptionLines())
        {
            DisplayText = f"{DisplayText}{Line}\n";
        }
        DisplayText = f"{DisplayText}\n";
        DisplayText = f"{DisplayText}FName TestName:    {Received.TestName}  (Expected: {ExpectedTestName})  " + (NamePass ? "[PASS]" : "[FAIL]") + "\n";
        DisplayText = f"{DisplayText}int32 TestInt:     {Received.TestInt}  (Expected: {ExpectedTestInt})  " + (IntPass ? "[PASS]" : "[FAIL]") + "\n";
        DisplayText = f"{DisplayText}float TestFloat:   {Received.TestFloat}  (Expected: {ExpectedTestFloat})  " + (FloatPass ? "[PASS]" : "[FAIL]") + "\n";
        DisplayText = f"{DisplayText}\n";
        DisplayText = f"{DisplayText}RESULT: " + (AllPassed ? "ALL TESTS PASSED" : "SOME TESTS FAILED");

        auto StationDisplay = FCkGym_Station_TitleAndDescription();
        StationDisplay.Title = FText::FromString(StationTitle);
        StationDisplay.Description = FText::FromString(DisplayText);
        Set_StationTitleAndDescription("Gym.EntityScript.Spawn", StationDisplay);
    }

    UFUNCTION(Exec, DisplayName="EntityScript Gym - Restart Spawn Test")
    void Ck_GymEntityScript_RestartSpawnTest()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_EntityScriptGym_Spawn");
        for (auto Entity : Entities)
        {
            utils_entity_lifetime::Request_DestroyEntity(Entity);
        }

        Request_StartSpawnTest();
    }
}
