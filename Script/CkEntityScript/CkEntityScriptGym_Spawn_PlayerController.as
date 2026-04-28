// Language=angelscript

//============================================================================
// ENTITY SCRIPT SPAWN GYM - PLAYER CONTROLLER
//============================================================================

class ACk_EntityScriptGym_Spawn_PlayerController : ACk_Gym_Base_PlayerController
{
    FName ExpectedTestName = n"GymTestEntity";
    int32 ExpectedTestInt = 42;
    float32 ExpectedTestFloat = 3.14f;

    //------------------------------------------------------------------------
    // STATION DESCRIPTIONS
    //------------------------------------------------------------------------

    private FString SpawnStationTitle = "ENTITY SCRIPT SPAWN";
    private TArray<FText> SpawnStationDescriptionLines;

    private TArray<FText> Get_SpawnStationDescriptionLines()
    {
        if (SpawnStationDescriptionLines.Num() == 0)
        {
            SpawnStationDescriptionLines.Add(FText::FromString("Verifies that ExposeOnSpawn properties are correctly injected"));
            SpawnStationDescriptionLines.Add(FText::FromString("during entity script spawning."));
            SpawnStationDescriptionLines.Add(FText::FromString("Console: Ck_GymEntityScript_RestartSpawnTest"));
        }
        return SpawnStationDescriptionLines;
    }

    private FString ReplicatedStationTitle = "ENTITY SCRIPT SPAWN (REPLICATED)";
    private TArray<FText> ReplicatedStationDescriptionLines;

    private TArray<FText> Get_ReplicatedStationDescriptionLines()
    {
        if (ReplicatedStationDescriptionLines.Num() == 0)
        {
            ReplicatedStationDescriptionLines.Add(FText::FromString("Verifies that ExposeOnSpawn properties survive replication."));
            ReplicatedStationDescriptionLines.Add(FText::FromString("Entity script uses ECk_Replication::Replicates."));
            ReplicatedStationDescriptionLines.Add(FText::FromString("Console: Ck_GymEntityScript_RestartReplicatedSpawnTest"));
        }
        return ReplicatedStationDescriptionLines;
    }

    //------------------------------------------------------------------------
    // STATION SETUP
    //------------------------------------------------------------------------

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.EntityScript.Spawn");
            Station.Title = FText::FromString(SpawnStationTitle);
            Station.Description = Get_SpawnStationDescriptionLines();
            Station.Description.Add(FText::FromString(""));
            Station.Description.Add(FText::FromString("Waiting for entity to spawn..."));
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.EntityScript.SpawnReplicated");
            Station.Title = FText::FromString(ReplicatedStationTitle);
            Station.Description = Get_ReplicatedStationDescriptionLines();
            Station.Description.Add(FText::FromString(""));
            Station.Description.Add(FText::FromString("Waiting for entity to spawn..."));
            Stations.Add(Station);
        }

        return Stations;
    }

    //------------------------------------------------------------------------
    // GYM STARTUP
    //------------------------------------------------------------------------

    void Request_StartGym() override
    {
        auto ThisEntity = ck::ToEntity(this);
        if (utils_net::Get_IsEntityNetMode_Host(ThisEntity))
        {
            Request_StartSpawnTest();
            Request_StartReplicatedSpawnTest();
            ck::Trace("Entity Script Spawn Gym started");
        }
    }

    //------------------------------------------------------------------------
    // SPAWN TEST (NON-REPLICATED)
    //------------------------------------------------------------------------

    void Request_StartSpawnTest()
    {
        auto SpawnParams = UCk_EntityScript_EntityScriptGym_Spawn::Params();
        SpawnParams.InitialTransform = Get_StationAnchorTransform("Gym.EntityScript.Spawn", ECk_GymStation_Anchor::PanelCenter);
        SpawnParams.TestName = ExpectedTestName;
        SpawnParams.TestInt = ExpectedTestInt;
        SpawnParams.TestFloat = ExpectedTestFloat;

        const auto StationEntity = Get_StationHandle("Gym.EntityScript.Spawn");

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            StationEntity,
            UCk_EntityScript_EntityScriptGym_Spawn,
            SpawnParams
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
        Request_VerifyAndDisplayResults(InEntityScriptHandle, "Gym.EntityScript.Spawn", SpawnStationTitle, Get_SpawnStationDescriptionLines());
    }

    //------------------------------------------------------------------------
    // SPAWN TEST (REPLICATED)
    //------------------------------------------------------------------------

    void Request_StartReplicatedSpawnTest()
    {
        auto SpawnParams = UCk_EntityScript_EntityScriptGym_SpawnReplicated::Params();
        SpawnParams.InitialTransform = Get_StationAnchorTransform("Gym.EntityScript.SpawnReplicated", ECk_GymStation_Anchor::PanelCenter);
        SpawnParams.TestName = ExpectedTestName;
        SpawnParams.TestInt = ExpectedTestInt;
        SpawnParams.TestFloat = ExpectedTestFloat;

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.EntityScript.SpawnReplicated"),
            UCk_EntityScript_EntityScriptGym_SpawnReplicated,
            SpawnParams
        );

        if (ck::IsValid(SpawnRequest))
        {
            utils_pending_entity_script::Promise_OnConstructed(SpawnRequest, FCk_Delegate_EntityScript_Constructed(this, n"OnReplicatedSpawnTestConstructed"));
        }
        else
        {
            ck::Error("Failed to spawn EntityScript Replicated Spawn test entity");
        }
    }

    UPROPERTY(ReplicatedUsing=OnRep_ReplicatedSpawnTestEntityScriptHandle)
    FCk_Handle_EntityScript ReplicatedSpawnTestEntityScriptHandle;

    UFUNCTION()
    private void OnRep_ReplicatedSpawnTestEntityScriptHandle()
    {
        if (ck::IsValid(ReplicatedSpawnTestEntityScriptHandle))
        {
            Request_VerifyAndDisplayResults(ReplicatedSpawnTestEntityScriptHandle, "Gym.EntityScript.SpawnReplicated", ReplicatedStationTitle, Get_ReplicatedStationDescriptionLines());
        }
    }

    UFUNCTION()
    private void OnReplicatedSpawnTestConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        ReplicatedSpawnTestEntityScriptHandle = InEntityScriptHandle;
        Request_VerifyAndDisplayResults(InEntityScriptHandle, "Gym.EntityScript.SpawnReplicated", ReplicatedStationTitle, Get_ReplicatedStationDescriptionLines());
    }

    //------------------------------------------------------------------------
    // SHARED VERIFICATION
    //------------------------------------------------------------------------

    private void Request_VerifyAndDisplayResults(FCk_Handle_EntityScript InHandle, FString InStationTag, FString InTitle, TArray<FText> InDescriptionLines)
    {
        const auto& Received = InHandle.Get_Fragment(FEntityScriptGym_SpawnParams);

        auto NamePass = (Received.TestName == ExpectedTestName);
        auto IntPass = (Received.TestInt == ExpectedTestInt);
        auto FloatPass = (Math::Abs(Received.TestFloat - ExpectedTestFloat) < 0.001f);
        auto AllPassed = NamePass && IntPass && FloatPass;

        auto DisplayText = "";
        for (auto Line : InDescriptionLines)
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
        StationDisplay.Title = FText::FromString(InTitle);
        StationDisplay.Description = FText::FromString(DisplayText);
        Set_StationTitleAndDescription(InStationTag, StationDisplay);
    }

    //------------------------------------------------------------------------
    // CONSOLE COMMANDS
    //------------------------------------------------------------------------

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

    UFUNCTION(Exec, DisplayName="EntityScript Gym - Restart Replicated Spawn Test")
    void Ck_GymEntityScript_RestartReplicatedSpawnTest()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_EntityScriptGym_SpawnReplicated");
        for (auto Entity : Entities)
        {
            utils_entity_lifetime::Request_DestroyEntity(Entity);
        }

        Request_StartReplicatedSpawnTest();
    }
}
