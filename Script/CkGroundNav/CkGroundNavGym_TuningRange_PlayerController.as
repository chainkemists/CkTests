class ACk_GroundNavGym_TuningRange_PlayerController : ACk_Gym_Base_PlayerController
{
    // ---- Scene constants -------------------------------------------------------------------------
    //
    // Every dimension here is chosen so that ONE tunable decides what the bake does with it. The
    // riser is the clearest case: at 20uu it sits between the default plane-fit tolerance (10) and
    // the next value the panel offers (25), so a single keypress flips the staircase between twelve
    // plates and six.

    private const FVector k_FloorLocation = FVector(0.0, 0.0, 0.0);

    // Z scale must stay >= 0.5 - thinner slabs bake to zero walkable tiles. The walkable surface is
    // at the actor origin, so the slab hangs below Z=0.
    private const FVector k_FloorScale = FVector(24.0, 24.0, 0.5);

    private const int32 k_StepCount   = 12;
    private const float k_StepRunUu   = 100.0f;
    private const float k_StepRiseUu  = 20.0f;
    private const float k_StairStartX = -500.0f;
    private const float k_StairWidthY = 600.0f;

    // Sits on top of the last step and reaches out over the floor. The floor underneath keeps 220uu
    // of headroom, which clears the default 180uu agent, so the region genuinely has two layers
    // rather than one layer with a hole in it.
    private const FVector k_PlatformCentre = FVector(1050.0, 0.0, 230.0);
    private const FVector k_PlatformScale  = FVector(7.0, 10.0, 0.2);

    // 75uu wide - three cells at the default 25uu lattice. Narrow enough that the ledge filter can
    // erase it outright, which is the only way to see what that filter costs.
    private const FVector k_CatwalkCentre = FVector(475.0, 450.0, 230.0);
    private const FVector k_CatwalkScale  = FVector(4.5, 0.75, 0.2);

    // Inner faces at Y = +/-80, so the gap is 160uu. Wide enough for the default 34uu-radius agent
    // and tight enough to be the only pinch in the clearance field.
    private const FVector k_PillarNorthCentre = FVector(-900.0, 180.0, 150.0);
    private const FVector k_PillarSouthCentre = FVector(-900.0, -180.0, 150.0);
    private const FVector k_PillarScale       = FVector(2.0, 2.0, 3.0);

    // The bake follows the pawn, so the starting viewpoint has to sit close enough to the middle of
    // the scene that the default region covers all of it.
    private const FVector  k_PlayerViewLocation = FVector(300.0, -900.0, 550.0);
    private const FRotator k_PlayerViewRotation = FRotator(-22.0, 75.0, 0.0);

    // ---- Control row indices ---------------------------------------------------------------------
    //
    // Header and Status rows never reach Request_ControlActivated but they DO occupy an index. These
    // constants sit next to each other so a row inserted in one place and not renumbered here is a
    // visible edit rather than a silent off-by-one.

    private const int32 k_Row_Bake        = 5;
    private const int32 k_Row_Mode        = 6;
    private const int32 k_Row_Clear       = 7;
    private const int32 k_Row_PlaneFit    = 9;
    private const int32 k_Row_NormalCone  = 10;
    private const int32 k_Row_Ledge       = 12;
    private const int32 k_Row_StepHeight  = 13;
    private const int32 k_Row_AgentHeight = 14;
    private const int32 k_Row_AgentRadius = 15;
    private const int32 k_Row_CellSize    = 17;
    private const int32 k_Row_Print       = 19;
    private const int32 k_Row_Reset       = 20;

    // ---- State -----------------------------------------------------------------------------------

    private FCk_Handle _PcEntity;
    private bool _GeometryIsBuilt = false;
    private int32 _BakeCount = 0;

    private int32 _ModeIndex = 0;
    private int32 _PlaneFitIndex = 1;
    private int32 _NormalConeIndex = 2;
    private int32 _LedgeIndex = 0;
    private int32 _StepHeightIndex = 2;
    private int32 _AgentHeightIndex = 1;
    private int32 _AgentRadiusIndex = 1;
    private int32 _CellSizeIndex = 1;

    // ---- Tunable value tables --------------------------------------------------------------------
    //
    // The gym owns these values and pushes them to the cvars; it never reads them back. Typing a
    // value straight into the console still works and still takes effect - the panel just will not
    // know about it until the next keypress pushes the gym value over the top.

    private TArray<float> Get_PlaneFitValues()
    {
        auto Values = TArray<float>();
        Values.Add(2.5f);
        Values.Add(10.0f);
        Values.Add(25.0f);
        Values.Add(50.0f);
        return Values;
    }

    private TArray<FString> Get_PlaneFitLabels()
    {
        auto Labels = TArray<FString>();
        Labels.Add("2.5 uu (near the quantization floor)");
        Labels.Add("10 uu (default - steps survive)");
        Labels.Add("25 uu (past the 20uu riser - steps merge)");
        Labels.Add("50 uu (the whole staircase flattens)");
        return Labels;
    }

    private TArray<float> Get_NormalConeValues()
    {
        auto Values = TArray<float>();
        Values.Add(1.0f);
        Values.Add(3.0f);
        Values.Add(10.0f);
        Values.Add(30.0f);
        return Values;
    }

    private TArray<FString> Get_NormalConeLabels()
    {
        auto Labels = TArray<FString>();
        Labels.Add("1 deg (fragments flat ground)");
        Labels.Add("3 deg (the narrow end where it still binds)");
        Labels.Add("10 deg (default)");
        Labels.Add("30 deg (no measurable effect)");
        return Labels;
    }

    private TArray<float> Get_LedgeValues()
    {
        auto Values = TArray<float>();
        Values.Add(1.0f);
        Values.Add(0.5f);
        Values.Add(0.34f);
        Values.Add(0.0f);
        return Values;
    }

    private TArray<FString> Get_LedgeLabels()
    {
        auto Labels = TArray<FString>();
        Labels.Add("1.0 - one dropping side (erases the catwalk)");
        Labels.Add("0.5 - two dropping sides");
        Labels.Add("0.34 - three dropping sides");
        Labels.Add("off - nothing is demoted");
        return Labels;
    }

    private TArray<float> Get_StepHeightValues()
    {
        auto Values = TArray<float>();
        Values.Add(10.0f);
        Values.Add(25.0f);
        Values.Add(40.0f);
        Values.Add(60.0f);
        return Values;
    }

    private TArray<FString> Get_StepHeightLabels()
    {
        auto Labels = TArray<FString>();
        Labels.Add("10 uu (below the 20uu riser - the stairs disconnect)");
        Labels.Add("25 uu (just clears the riser)");
        Labels.Add("40 uu (default)");
        Labels.Add("60 uu");
        return Labels;
    }

    private TArray<float> Get_AgentHeightValues()
    {
        auto Values = TArray<float>();
        Values.Add(120.0f);
        Values.Add(180.0f);
        Values.Add(220.0f);
        Values.Add(260.0f);
        return Values;
    }

    private TArray<FString> Get_AgentHeightLabels()
    {
        auto Labels = TArray<FString>();
        Labels.Add("120 uu");
        Labels.Add("180 uu (default)");
        Labels.Add("220 uu (exactly the platform headroom)");
        Labels.Add("260 uu (the floor under the platform is culled - one layer)");
        return Labels;
    }

    private TArray<float> Get_AgentRadiusValues()
    {
        auto Values = TArray<float>();
        Values.Add(17.0f);
        Values.Add(34.0f);
        Values.Add(60.0f);
        Values.Add(90.0f);
        return Values;
    }

    private TArray<FString> Get_AgentRadiusLabels()
    {
        auto Labels = TArray<FString>();
        Labels.Add("17 uu");
        Labels.Add("34 uu (default - fits the 160uu gap)");
        Labels.Add("60 uu");
        Labels.Add("90 uu (wider than the gap - the pinch closes)");
        return Labels;
    }

    private TArray<float> Get_CellSizeValues()
    {
        auto Values = TArray<float>();
        Values.Add(12.5f);
        Values.Add(25.0f);
        Values.Add(50.0f);
        Values.Add(100.0f);
        return Values;
    }

    private TArray<FString> Get_CellSizeLabels()
    {
        auto Labels = TArray<FString>();
        Labels.Add("12.5 uu (4x the cells - expect draw truncation)");
        Labels.Add("25 uu (default)");
        Labels.Add("50 uu (the 75uu catwalk is now 1.5 cells)");
        Labels.Add("100 uu (a whole tread is one cell)");
        return Labels;
    }

    private TArray<FString> Get_ModeLabels()
    {
        auto Labels = TArray<FString>();
        Labels.Add("0 Plates");
        Labels.Add("1 Clearance");
        Labels.Add("2 Layers");
        Labels.Add("3 Rejected (what the filters threw away)");
        return Labels;
    }

    // ---- Station ---------------------------------------------------------------------------------

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        if (HasAuthority() == false)
        { return TArray<FCkGym_Station_SpawnParams_Payload>(); }

        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(n"GroundNavTuningRange");
        Station.AutoSize = true;
        Station.Transform = FTransform(FRotator(0.0, 270.0, 0.0), FVector(300.0, 2600.0, 0.0), FVector::OneVector);
        Station.Title = FText::FromString("GroundNav - Tuning Range");

        auto Description = TArray<FText>();
        Description.Add(FText::FromString("A scene built so that each part of it is decided by exactly one bake tunable. Press R to bake around your pawn and read the summary that prints to the log; every other key changes a value and re-bakes."));
        Description.Add(FText::FromString("The staircase has 20uu risers. At the default plane-fit tolerance of 10uu you get one plate per tread; press F once to raise it past 20 and the treads merge into ramps. Watch the worst height spread in the summary - when it reaches 20 the steps have stopped existing."));
        Description.Add(FText::FromString("The platform leaves 220uu of headroom over the floor, so the region reports two layers. Raise the agent height past 220 with M and the floor beneath it is culled, dropping the count to one."));
        Description.Add(FText::FromString("The catwalk is 75uu wide and drops 240uu on both sides. Draw mode 3 shows what the ledge filter removed - at sensitivity 1.0 the whole catwalk goes red."));
        Description.Add(FText::FromString("Fail signatures: status BackendUnavailable = no Jolt static world in this PIE mode; NoGeometryInRegion = the scene did not bake into Jolt, or the pawn drifted outside the region."));
        Station.Description = Description;

        Stations.Add(Station);
        return Stations;
    }

    // ---- Startup ---------------------------------------------------------------------------------

    void Request_StartGym() override
    {
        if (HasAuthority() == false)
        { return; }

        _PcEntity = ck::ToEntity(this);
        if (ck::Is_NOT_Valid(_PcEntity))
        {
            ck::groundnav::Warning("GroundNav gym: PC entity invalid; cannot start");
            return;
        }

        _GeometryIsBuilt = DoBuildScene();

        if (_GeometryIsBuilt == false)
        {
            ck::Error("GroundNav gym: the scene failed to bake into the Jolt static world - every bake will report NoGeometryInRegion", n"GroundNavGym.Scene", 10.0);
        }

        DoPushAllTunables();

        DoBringPlayerToViewpoint();
        DoWaitOneFrame(n"OnViewpointSettle");

        ck::groundnav::Log("GroundNav gym: scene built - press R to bake");
    }

    // ---- Scene construction ----------------------------------------------------------------------

    private bool DoBuildScene()
    {
        if (DoSpawnFloor() == false)
        { return false; }

        for (int32 StepIndex = 0; StepIndex < k_StepCount; ++StepIndex)
        {
            // Each step is a solid block from the floor up to its own tread rather than a slab
            // floating at tread height: a floating slab would leave walkable floor underneath it and
            // read as a stack of layers instead of as a staircase.
            const auto TopZ = k_StepRiseUu * float(StepIndex + 1);
            const auto CentreX = k_StairStartX + (k_StepRunUu * (float(StepIndex) + 0.5f));

            const auto Centre = FVector(CentreX, 0.0, TopZ * 0.5);
            const auto Scale = FVector(k_StepRunUu / 100.0, k_StairWidthY / 100.0, TopZ / 100.0);

            if (DoSpawnBox(Centre, Scale) == false)
            { return false; }
        }

        if (DoSpawnBox(k_PlatformCentre, k_PlatformScale) == false)
        { return false; }

        if (DoSpawnBox(k_CatwalkCentre, k_CatwalkScale) == false)
        { return false; }

        if (DoSpawnBox(k_PillarNorthCentre, k_PillarScale) == false)
        { return false; }

        if (DoSpawnBox(k_PillarSouthCentre, k_PillarScale) == false)
        { return false; }

        return true;
    }

    private bool DoSpawnFloor()
    {
        auto Floor = SpawnActor(ACk_Gym_Floor, k_FloorLocation, FRotator::ZeroRotator, NAME_None, true);
        if (Floor == nullptr)
        {
            ck::groundnav::Warning("GroundNav gym: failed to spawn the floor actor");
            return false;
        }

        Floor.SetActorScale3D(k_FloorScale);
        FinishSpawningActor(Floor);

        // The floor has to be baked like everything else. The GroundNav backend reads the Jolt
        // static world, not the level collision - a floor that Recast can see is still nothing to
        // this bake until it has Jolt bodies.
        const auto NumBaked = utils_jolt_static_world::Request_BakeActor(Floor);
        if (NumBaked == 0)
        {
            ck::groundnav::Warning("GroundNav gym: the floor baked 0 Jolt bodies");
            return false;
        }

        return true;
    }

    private bool DoSpawnBox(FVector InCentre, FVector InScale)
    {
        auto BoxActor = Cast<AStaticMeshActor>(SpawnActor(AStaticMeshActor, InCentre));
        if (ck::Is_NOT_Valid(BoxActor))
        {
            ck::groundnav::Warning("GroundNav gym: failed to spawn a scene box");
            return false;
        }

        // A runtime-spawned AStaticMeshActor must be Movable BEFORE it will accept a mesh.
        BoxActor.StaticMeshComponent.SetMobility(EComponentMobility::Movable);

        auto CubeMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Cube.Cube"));
        if (CubeMesh == nullptr)
        {
            ck::groundnav::Warning("GroundNav gym: failed to load /Engine/BasicShapes/Cube.Cube");
            return false;
        }
        BoxActor.StaticMeshComponent.SetStaticMesh(CubeMesh);

        auto BoxMaterial = Cast<UMaterialInterface>(LoadObject(this, "/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));
        if (BoxMaterial != nullptr)
        { BoxActor.StaticMeshComponent.SetMaterial(0, BoxMaterial); }

        BoxActor.SetActorScale3D(InScale);
        BoxActor.StaticMeshComponent.SetCollisionProfileName(n"BlockAll");

        const auto NumBaked = utils_jolt_static_world::Request_BakeActor(BoxActor);
        if (NumBaked == 0)
        {
            ck::groundnav::Warning("GroundNav gym: a scene box baked 0 Jolt bodies - the bake would read it as free space");
            return false;
        }

        return true;
    }

    private void DoBringPlayerToViewpoint()
    {
        auto ViewPawn = GetControlledPawn();
        if (ck::Is_NOT_Valid(ViewPawn))
        { return; }

        ViewPawn.SetActorLocation(k_PlayerViewLocation);
        SetControlRotation(k_PlayerViewRotation);
    }

    // Mirrors the gym base private WaitOneFrame - a one-shot timer on the PC own entity.
    private void DoWaitOneFrame(FName InCallbackName)
    {
        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(0.05));
        Params.Set_StartingState(ECk_Timer_State::Running)
              .Set_Behavior(ECk_Timer_Behavior::StopOnDone);
        auto Timer = utils_timer::Add(_PcEntity, Params);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, InCallbackName));
    }

    UFUNCTION()
    private void OnViewpointSettle(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        // Retry - the pawn may not have been possessed yet when the gym started.
        DoBringPlayerToViewpoint();
    }

    // ---- Tunable plumbing ------------------------------------------------------------------------

    private void DoSetTunable(FString InName, float InValue)
    {
        System::ExecuteConsoleCommand(f"ck.GroundNav.Debug.{InName} {InValue}");
    }

    // Pushes the whole set rather than just the one that changed, so the cvars and the panel always
    // agree from the first keypress even if something else wrote them earlier in the session.
    private void DoPushAllTunables()
    {
        // The region has to be wide enough that the scene stays covered as the pawn moves around it,
        // and tall enough that a pawn hovering well above the floor still sees the floor.
        DoSetTunable("ExtentUu", 2000.0f);
        DoSetTunable("HeightUu", 900.0f);
        DoSetTunable("MaxCells", 40000.0f);

        DoSetTunable("Mode", float(_ModeIndex));
        DoSetTunable("PlaneFitToleranceUu", Get_PlaneFitValues()[_PlaneFitIndex]);
        DoSetTunable("NormalConeDegrees", Get_NormalConeValues()[_NormalConeIndex]);
        DoSetTunable("LedgeSensitivity", Get_LedgeValues()[_LedgeIndex]);
        DoSetTunable("StepHeightUu", Get_StepHeightValues()[_StepHeightIndex]);
        DoSetTunable("AgentHeightUu", Get_AgentHeightValues()[_AgentHeightIndex]);
        DoSetTunable("AgentRadiusUu", Get_AgentRadiusValues()[_AgentRadiusIndex]);
        DoSetTunable("CellSizeUu", Get_CellSizeValues()[_CellSizeIndex]);
    }

    private void DoBake()
    {
        DoPushAllTunables();
        System::ExecuteConsoleCommand("ck.GroundNav.Clear");
        System::ExecuteConsoleCommand("ck.GroundNav.Bake");
        _BakeCount += 1;
    }

    // ---- Control panel ---------------------------------------------------------------------------

    FString Get_ControlPanelTitle() override
    {
        return "GROUNDNAV: TUNING RANGE";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();

        Rows.Add(CkGym_Control::Header("SCENE"));
        Rows.Add(CkGym_Control::Status("Geometry",
            _GeometryIsBuilt ? "floor + 12 steps (20uu risers) + platform + 75uu catwalk + 160uu pinch"
                             : "NOT BAKED INTO JOLT - every bake will find nothing",
            _GeometryIsBuilt == false));
        Rows.Add(CkGym_Control::Status("Bake region", "follows your pawn, +/-2000uu wide, 900uu tall"));
        Rows.Add(CkGym_Control::Status("Bakes run", f"{_BakeCount}"));

        Rows.Add(CkGym_Control::Header("BAKE"));
        Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Bake now (summary prints to the log)"));
        Rows.Add(CkGym_Control::Cycle(EKeys::T, "T", "Draw mode", Get_ModeLabels()[_ModeIndex]));
        Rows.Add(CkGym_Control::Action(EKeys::B, "B", "Clear the drawing"));

        Rows.Add(CkGym_Control::Header("MERGE - how cells collapse into plates"));
        Rows.Add(CkGym_Control::Cycle(EKeys::F, "F", "Plane fit tolerance", Get_PlaneFitLabels()[_PlaneFitIndex]));
        Rows.Add(CkGym_Control::Cycle(EKeys::G, "G", "Normal cone", Get_NormalConeLabels()[_NormalConeIndex]));

        Rows.Add(CkGym_Control::Header("AGENT - what counts as walkable"));
        Rows.Add(CkGym_Control::Cycle(EKeys::N, "N", "Ledge sensitivity", Get_LedgeLabels()[_LedgeIndex]));
        Rows.Add(CkGym_Control::Cycle(EKeys::J, "J", "Step height", Get_StepHeightLabels()[_StepHeightIndex]));
        Rows.Add(CkGym_Control::Cycle(EKeys::M, "M", "Agent height", Get_AgentHeightLabels()[_AgentHeightIndex]));
        Rows.Add(CkGym_Control::Cycle(EKeys::L, "L", "Agent radius", Get_AgentRadiusLabels()[_AgentRadiusIndex]));

        Rows.Add(CkGym_Control::Header("LATTICE"));
        Rows.Add(CkGym_Control::Cycle(EKeys::K, "K", "Cell size", Get_CellSizeLabels()[_CellSizeIndex]));

        Rows.Add(CkGym_Control::Header("OTHER"));
        Rows.Add(CkGym_Control::Action(EKeys::P, "P", "Print every tunable to the log"));
        Rows.Add(CkGym_Control::Action(EKeys::O, "O", "Reset to the gym preset"));

        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (HasAuthority() == false)
        { return; }

        if (InRowIndex == k_Row_Bake)
        {
            DoBake();
            return;
        }

        if (InRowIndex == k_Row_Mode)
        {
            _ModeIndex = (_ModeIndex + 1) % Get_ModeLabels().Num();
            DoBake();
            return;
        }

        if (InRowIndex == k_Row_Clear)
        {
            System::ExecuteConsoleCommand("ck.GroundNav.Clear");
            return;
        }

        if (InRowIndex == k_Row_PlaneFit)
        {
            _PlaneFitIndex = (_PlaneFitIndex + 1) % Get_PlaneFitValues().Num();
            DoBake();
            return;
        }

        if (InRowIndex == k_Row_NormalCone)
        {
            _NormalConeIndex = (_NormalConeIndex + 1) % Get_NormalConeValues().Num();
            DoBake();
            return;
        }

        if (InRowIndex == k_Row_Ledge)
        {
            _LedgeIndex = (_LedgeIndex + 1) % Get_LedgeValues().Num();
            DoBake();
            return;
        }

        if (InRowIndex == k_Row_StepHeight)
        {
            _StepHeightIndex = (_StepHeightIndex + 1) % Get_StepHeightValues().Num();
            DoBake();
            return;
        }

        if (InRowIndex == k_Row_AgentHeight)
        {
            _AgentHeightIndex = (_AgentHeightIndex + 1) % Get_AgentHeightValues().Num();
            DoBake();
            return;
        }

        if (InRowIndex == k_Row_AgentRadius)
        {
            _AgentRadiusIndex = (_AgentRadiusIndex + 1) % Get_AgentRadiusValues().Num();
            DoBake();
            return;
        }

        if (InRowIndex == k_Row_CellSize)
        {
            _CellSizeIndex = (_CellSizeIndex + 1) % Get_CellSizeValues().Num();
            DoBake();
            return;
        }

        if (InRowIndex == k_Row_Print)
        {
            System::ExecuteConsoleCommand("ck.GroundNav.Print");
            return;
        }

        if (InRowIndex == k_Row_Reset)
        {
            DoResetTunables();
            return;
        }
    }

    private void DoResetTunables()
    {
        _ModeIndex = 0;
        _PlaneFitIndex = 1;
        _NormalConeIndex = 2;
        _LedgeIndex = 0;
        _StepHeightIndex = 2;
        _AgentHeightIndex = 1;
        _AgentRadiusIndex = 1;
        _CellSizeIndex = 1;

        DoBake();
        ck::groundnav::Log("GroundNav gym: tunables reset to the gym preset");
    }
}
