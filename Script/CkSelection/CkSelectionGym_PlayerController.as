// Language=angelscript

/** Standard mesh marker plus UTextRenderComponent label for fixture identification. */
class ACk_SelectionGym_LabelMarker : AActor
{
    UPROPERTY(DefaultComponent, RootComponent)
    USceneComponent RootComponent;

    UPROPERTY(DefaultComponent, Attach = RootComponent)
    UStaticMeshComponent Mesh;
    default Mesh.CollisionEnabled = ECollisionEnabled::NoCollision;

    UPROPERTY(DefaultComponent, Attach = RootComponent)
    UTextRenderComponent LabelText;
    default LabelText.RelativeLocation = FVector(0.0f, 0.0f, 105.0f);
    default LabelText.SetHorizontalAlignment(EHorizTextAligment::EHTA_Center);
    default LabelText.WorldSize = 32.0f;
    default LabelText.TextRenderColor = FColor::Cyan;

    void Set_Label(FString InLabel)
    {
        LabelText.SetText(FText::FromString(InLabel));
    }
}

class ACk_SelectionGym_PlayerController : ACk_Gym_Base_PlayerController
{
    private FVector _Origin = FVector::ZeroVector;
    private FCk_Handle _ScenarioRoot;
    private TArray<FCk_Handle> _TransientFixtureRoots;
    private FCk_Handle _MovingCandidate;
    private FCk_Handle _RespawnCandidate;
    private FCk_Handle_Transform _MovingTransform;
    private AActor _MovingVisual;
    private AActor _RespawnVisual;
    private TArray<AActor> _Visuals;
    private AActor _OcclusionWall;
    private int32 _ActiveScenario = 0;
    private float _MovingElapsed = 0.0f;
    private bool _TickStarted = false;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        if (HasAuthority() == false)
        { return TArray<FCkGym_Station_SpawnParams_Payload>(); }

        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();
        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(n"Gym.Selection");
        Station.Title = FText::FromString("DEBUG OVERLAY SELECTION");
        Station.AutoSize = true;

        auto Description = TArray<FText>();
        Description.Add(FText::FromString("Five ECS fixture banks exercise root labels, context roots, hierarchy, visibility, and lifecycle."));
        Description.Add(FText::FromString("Enable the Debug Overlay, then use Select / Next / Prev / Family while changing scenarios."));
        Description.Add(FText::FromString("Panel numbers replace the complete fixture bank; [R] rebuilds the active bank."));
        Station.Description = Description;
        Stations.Add(Station);
        return Stations;
    }

    void Request_StartGym() override
    {
        if (HasAuthority() == false)
        { return; }

        _Origin = Get_StationAnchorLocation("Gym.Selection", ECk_GymStation_Anchor::FootprintCenter);
        DoSelectScenario(0);

        if (_TickStarted == false)
        {
            _TickStarted = true;
            utils_timer::Create_Tick(ck::ToEntity(this), FCk_Delegate_Timer(this, n"OnFixtureTick"));
        }
    }

    UFUNCTION(BlueprintOverride)
    void EndPlay(EEndPlayReason EndPlayReason)
    {
        DoClearScenario();
    }

    private void DoSelectScenario(int32 InScenario)
    {
        _ActiveScenario = InScenario;
        DoClearScenario();
        _ScenarioRoot = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        _ScenarioRoot.Set_DebugName(n"Selection.Gym.FixtureRoot");

        if (InScenario == 0) { DoBuildTopology(); }
        else if (InScenario == 1) { DoBuildDistanceAndOverlap(); }
        else if (InScenario == 2) { DoBuildMixedHierarchy(); }
        else if (InScenario == 3) { DoBuildVisibilityAndOcclusion(); }
        else { DoBuildMovingRespawn(); }

        DoPositionViewer();
    }

    private void DoBuildTopology()
    {
        DoCreateTransientCandidate("Transient Root A", n"Selection.Topology.TransientA", FVector(-500.0f, -220.0f, 120.0f));
        DoCreateTransientCandidate("Transient Root B", n"Selection.Topology.TransientB", FVector(-500.0f, 220.0f, 120.0f));

        auto OrdinaryParent = selection_gym::Create_OrdinaryChild(_ScenarioRoot, n"Selection.Topology.OrdinaryParent");
        auto Nested = selection_gym::Create_Candidate(
            OrdinaryParent,
            n"Selection.Topology.NestedIndependent",
            _Origin + FVector(-720.0f, 0.0f, 120.0f));
        DoCreateVisual("Nested independent root", _Origin + FVector(-720.0f, 0.0f, 120.0f));
        Nested.Set_DebugName(n"Selection.Topology.NestedIndependent");
    }

    private void DoBuildDistanceAndOverlap()
    {
        DoCreateCandidate("Centered near", n"Selection.Distance.CenteredNear", FVector(-500.0f, 0.0f, 120.0f));
        DoCreateCandidate("Co-located A", n"Selection.Distance.CoLocatedA", FVector(-620.0f, -130.0f, 120.0f));
        DoCreateCandidate("Co-located B", n"Selection.Distance.CoLocatedB", FVector(-620.0f, -130.0f, 120.0f));
        DoCreateCandidate("Centered far", n"Selection.Distance.CenteredFar", FVector(-2400.0f, 0.0f, 120.0f));
    }

    private void DoBuildMixedHierarchy()
    {
        auto CompositeLocation = _Origin + FVector(-600.0f, 0.0f, 120.0f);
        selection_gym::Create_CompositeCandidate(_ScenarioRoot, CompositeLocation);
        DoCreateVisual("Composite root", CompositeLocation);
        DoCreateVisual("SceneNode descendant", CompositeLocation + FVector(0.0f, 150.0f, 100.0f));
        DoCreateVisual("Ordinary child", CompositeLocation + FVector(0.0f, -150.0f, 0.0f));
        DoCreateVisual("No-transform descendant", CompositeLocation + FVector(0.0f, -150.0f, 150.0f));
    }

    private void DoBuildVisibilityAndOcclusion()
    {
        auto Parent = selection_gym::Create_Candidate(
            _ScenarioRoot,
            n"Selection.Visibility.OffscreenParent",
            _Origin + FVector(900.0f, 0.0f, 120.0f));
        DoCreateVisual("Offscreen parent", _Origin + FVector(900.0f, 0.0f, 120.0f));

        selection_gym::Create_OrdinaryTransformChild(
            Parent,
            n"Selection.Visibility.VisibleChild",
            _Origin + FVector(-600.0f, -180.0f, 120.0f));
        DoCreateVisual("Visible ordinary child promotes parent", _Origin + FVector(-600.0f, -180.0f, 120.0f));

        DoCreateCandidate("Occluded root", n"Selection.Visibility.Occluded", FVector(-900.0f, 180.0f, 120.0f));
        _OcclusionWall = SpawnActor(ACk_Gym_ObstacleWall, _Origin + FVector(-550.0f, 180.0f, 150.0f), FRotator::ZeroRotator);
        if (ck::IsValid(_OcclusionWall))
        { _OcclusionWall.SetActorScale3D(FVector(0.25f, 2.4f, 2.0f)); }
    }

    private void DoBuildMovingRespawn()
    {
        auto StartLocation = _Origin + FVector(-650.0f, 0.0f, 120.0f);
        _MovingCandidate = selection_gym::Create_Candidate(_ScenarioRoot, n"Selection.Lifecycle.Moving", StartLocation);
        _MovingTransform = _MovingCandidate.As_Transform();
        _MovingVisual = DoCreateVisual("Moving root", StartLocation);

        _RespawnCandidate = selection_gym::Create_Candidate(
            _ScenarioRoot,
            n"Selection.Lifecycle.Respawnable",
            _Origin + FVector(-650.0f, 260.0f, 120.0f));
        _RespawnVisual = DoCreateVisual("Delete / respawn root", _Origin + FVector(-650.0f, 260.0f, 120.0f));
    }

    private void DoCreateCandidate(FString InLabel, FName InDebugName, FVector InOffset)
    {
        auto Location = _Origin + InOffset;
        selection_gym::Create_Candidate(_ScenarioRoot, InDebugName, Location);
        DoCreateVisual(InLabel, Location);
    }

    private void DoCreateTransientCandidate(FString InLabel, FName InDebugName, FVector InOffset)
    {
        auto Location = _Origin + InOffset;
        auto Candidate = selection_gym::Create_Candidate(ck::TransientEntity(), InDebugName, Location);
        _TransientFixtureRoots.Add(Candidate);
        DoCreateVisual(InLabel, Location);
    }

    private AActor DoCreateVisual(FString InLabel, FVector InLocation)
    {
        auto Visual = Cast<ACk_SelectionGym_LabelMarker>(SpawnActor(ACk_SelectionGym_LabelMarker, InLocation));
        if (ck::Is_NOT_Valid(Visual))
        {
            ck::Warning("Selection gym could not spawn its visual marker: " + InLabel);
            return nullptr;
        }

        Visual.Mesh.SetMobility(EComponentMobility::Movable);
        Visual.Mesh.SetCollisionEnabled(ECollisionEnabled::NoCollision);
        Visual.SetActorEnableCollision(false);
        auto Cube = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Cube.Cube"));
        if (ck::IsValid(Cube))
        { Visual.Mesh.SetStaticMesh(Cube); }
        Visual.Mesh.SetRelativeScale3D(FVector(0.35f, 0.35f, 0.35f));
        Visual.Set_Label(InLabel);
        _Visuals.Add(Visual);
        return Visual;
    }

    private void DoClearScenario()
    {
        for (auto Visual : _Visuals)
        {
            if (ck::IsValid(Visual))
            { Visual.DestroyActor(); }
        }
        _Visuals.Empty();

        for (auto FixtureRoot : _TransientFixtureRoots)
        {
            if (ck::IsValid(FixtureRoot))
            { utils_entity_lifetime::Request_DestroyEntity(FixtureRoot); }
        }
        _TransientFixtureRoots.Empty();

        if (ck::IsValid(_OcclusionWall))
        { _OcclusionWall.DestroyActor(); }
        _OcclusionWall = nullptr;

        if (ck::IsValid(_ScenarioRoot))
        { utils_entity_lifetime::Request_DestroyEntity(_ScenarioRoot); }
        _ScenarioRoot = FCk_Handle();
        _MovingCandidate = FCk_Handle();
        _RespawnCandidate = FCk_Handle();
        _MovingTransform = utils_transform::Get_InvalidHandle();
        _MovingVisual = nullptr;
        _RespawnVisual = nullptr;
        _MovingElapsed = 0.0f;
    }

    UFUNCTION()
    private void OnFixtureTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (_ActiveScenario != 4 || ck::Is_NOT_Valid(_MovingTransform))
        { return; }

        _MovingElapsed += float(InDeltaT.Get_Seconds());
        auto NewLocation = _Origin + FVector(-650.0f, Math::Sin(_MovingElapsed) * 280.0f, 120.0f);
        utils_transform::Request_SetLocation(_MovingTransform, NewLocation, ECk_LocalWorld::World);
        if (ck::IsValid(_MovingVisual))
        { _MovingVisual.SetActorLocation(NewLocation); }
    }

    private void DoPositionViewer()
    {
        auto ViewPawn = GetControlledPawn();
        if (ck::Is_NOT_Valid(ViewPawn))
        { return; }

        ViewPawn.SetActorLocation(_Origin + FVector(650.0f, 0.0f, 320.0f));
        SetControlRotation(FRotator(-12.0f, 180.0f, 0.0f));
    }

    private void DoDeleteAndRespawn()
    {
        if (_ActiveScenario != 4 || ck::Is_NOT_Valid(_ScenarioRoot))
        { return; }

        if (ck::IsValid(_RespawnCandidate))
        { utils_entity_lifetime::Request_DestroyEntity(_RespawnCandidate); }
        if (ck::IsValid(_RespawnVisual))
        { _RespawnVisual.DestroyActor(); }

        _RespawnCandidate = selection_gym::Create_Candidate(
            _ScenarioRoot,
            n"Selection.Lifecycle.Respawned",
            _Origin + FVector(-650.0f, 260.0f, 120.0f));
        _RespawnVisual = DoCreateVisual("Respawned root", _Origin + FVector(-650.0f, 260.0f, 120.0f));
    }

    FString Get_ControlPanelTitle() override
    {
        return "SELECTION FIXTURES";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Header("SCENARIO"));
        Rows.Add(CkGym_Control::Status("Active", DoGetScenarioLabel()));
        Rows.Add(CkGym_Control::Numbered(0, "Topology and context roots", _ActiveScenario == 0));
        Rows.Add(CkGym_Control::Numbered(1, "Distance and overlap", _ActiveScenario == 1));
        Rows.Add(CkGym_Control::Numbered(2, "Mixed ECS hierarchy", _ActiveScenario == 2));
        Rows.Add(CkGym_Control::Numbered(3, "Visibility and occlusion", _ActiveScenario == 3));
        Rows.Add(CkGym_Control::Numbered(4, "Moving and respawn", _ActiveScenario == 4));
        Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Rebuild active scenario"));
        Rows.Add(CkGym_Control::Action(EKeys::X, "X", "Delete and respawn target", _ActiveScenario == 4));
        Rows.Add(CkGym_Control::Action(EKeys::O, "O", "Enable Debug Overlay"));
        Rows.Add(CkGym_Control::Action(EKeys::P, "P", "Open overlay settings"));
        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex >= 2 && InRowIndex <= 6)
        { DoSelectScenario(InRowIndex - 2); }
        else if (InRowIndex == 7)
        { DoSelectScenario(_ActiveScenario); }
        else if (InRowIndex == 8)
        { DoDeleteAndRespawn(); }
        else if (InRowIndex == 9)
        { System::ExecuteConsoleCommand("ck.DebugOverlay 1"); }
        else if (InRowIndex == 10)
        { System::ExecuteConsoleCommand("ck.DebugOverlay.Settings"); }
    }

    private FString DoGetScenarioLabel() const
    {
        if (_ActiveScenario == 0) { return "Topology"; }
        if (_ActiveScenario == 1) { return "Distance"; }
        if (_ActiveScenario == 2) { return "Hierarchy"; }
        if (_ActiveScenario == 3) { return "Visibility"; }
        return "Lifecycle";
    }
}
