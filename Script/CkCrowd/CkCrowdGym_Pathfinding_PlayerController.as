class ACk_CrowdGym_Pathfinding_PlayerController : ACk_Gym_Base_PlayerController
{
    private FCk_Handle _StationHandle;
    private FCk_Nav_PathResult _LastResult;
    private bool _BindingsAttached = false;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        if (HasAuthority() == false)
        { return TArray<FCkGym_Station_SpawnParams_Payload>(); }

        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Crowd.Pathfinding");
            Station.Title = FText::FromString("PATHFINDING");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Console: Ck_GymCrowd_Path_IssueGood / IssueBad / Status"));
            Description.Add(FText::FromString("Open the debugger:  ck.CrowdDebugger 1  (Navmesh Status panel populated)"));
            Description.Add(FText::FromString("Last path status: (issue a request)"));
            Station.Description = Description;
            Stations.Add(Station);
        }

        return Stations;
    }

    void Request_StartGym() override
    {
        if (HasAuthority() == false)
        { return; }

        SpawnFloor();

        _StationHandle = Get_StationHandle("Gym.Crowd.Pathfinding");
        if (ck::Is_NOT_Valid(_StationHandle))
        {
            ck::Warning("Pathfinding gym: station handle invalid at StartGym; bind deferred");
            return;
        }

        AttachBindings();
        ck::Trace("Pathfinding gym started. Run Ck_GymCrowd_Path_IssueGood from the console.");
    }

    private void SpawnFloor()
    {
        // 2000cm x 2000cm flat cube, top face at Z=0 (origin Z=-25, half-height = 25cm
        // from scale Z=0.5 over the engine cube's 100cm). Comfortably covers the 500cm
        // navmesh projection half-extent around origin and the 500cm IssueGood target,
        // without dominating the viewport.
        const auto FloorLocation = FVector(0.0, 0.0, -25.0);
        const auto FloorScale    = FVector(20.0, 20.0, 0.5);

        auto Floor = SpawnActor(ACk_CrowdGym_Floor, FloorLocation, FRotator::ZeroRotator, NAME_None, true);
        if (Floor == nullptr)
        {
            ck::Warning("Pathfinding gym: failed to spawn floor actor");
            return;
        }
        Floor.SetActorScale3D(FloorScale);
        FinishSpawningActor(Floor);

        ck::Trace(f"Pathfinding gym: floor spawned at {FloorLocation} scale={FloorScale}");
    }

    private void AttachBindings()
    {
        if (_BindingsAttached)
        { return; }

        if (ck::Is_NOT_Valid(_StationHandle))
        { return; }

        utils_nav::BindTo_OnPathReady(_StationHandle,
            FCk_Delegate_Nav_OnPathReady(this, n"OnPathReady"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_nav::BindTo_OnPathFailed(_StationHandle,
            FCk_Delegate_Nav_OnPathFailed(this, n"OnPathFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        _BindingsAttached = true;
        ck::Trace(f"Pathfinding gym: bindings attached on station handle {_StationHandle.ToString()}");
    }

    UFUNCTION()
    void OnPathReady(FCk_Handle InHandle, FCk_Nav_PathResult InResult)
    {
        _LastResult = InResult;
        ck::Trace(f"Pathfinding gym: OnPathReady — status={InResult.Get_Status()} waypoints={InResult.Get_Waypoints().Num()}");
        UpdateStationDisplay();
        DrawPathOverlay();
    }

    private void DrawPathOverlay()
    {
        // Draw the waypoints + connecting lines in the world for ~10s. Gives visual
        // confirmation that the path actually landed even if the station-text update
        // didn't render. Cyan = healthy path. Spheres at each waypoint, lines between.
        const auto Waypoints = _LastResult.Get_Waypoints();
        if (Waypoints.Num() == 0)
        { return; }

        const auto Color = FLinearColor(0.42, 0.85, 1.0, 1.0); // cyan
        const auto SphereRadius = 25.0f;
        const auto LineThickness = 4.0f;
        const auto Duration = 10.0f;

        for (int32 i = 0; i < Waypoints.Num(); ++i)
        {
            UCk_Utils_DebugDraw_UE::DrawDebugSphere(Waypoints[i], SphereRadius, 12, Color, Duration, LineThickness);
        }

        for (int32 i = 0; i < Waypoints.Num() - 1; ++i)
        {
            UCk_Utils_DebugDraw_UE::DrawDebugLine(Waypoints[i], Waypoints[i + 1], Color, Duration, LineThickness);
        }
    }

    UFUNCTION()
    void OnPathFailed(FCk_Handle InHandle)
    {
        _LastResult = utils_nav::Get_PathResult(_StationHandle);
        const auto Diag = _LastResult.Get_Diagnostics();

        // Surface the full projection picture in one log line so we don't need to chase
        // a separate diag command after every failure.
        ck::Warning(
            f"Pathfinding gym: OnPathFailed — reason={Diag.Get_LastFailReason()}\n" +
            f"  agent loc           = {Diag.Get_LastAgentLocation()}\n" +
            f"  target              = {Diag.Get_LastTargetLocation()}\n" +
            f"  start projected     = {Diag.Get_StartProjected()}  -> {Diag.Get_LastProjectedStart()}\n" +
            f"  end projected       = {Diag.Get_EndProjected()}    -> {Diag.Get_LastProjectedEnd()}\n" +
            f"  raw / extracted pts = {Diag.Get_RawPathPointCount()} / {Diag.Get_ExtractedWaypointCount()}\n" +
            f"  last query duration = {Diag.Get_LastQueryDurationMs()} ms");

        UpdateStationDisplay();
    }

    private void UpdateStationDisplay()
    {
        const auto Status = _LastResult.Get_Status();
        const auto WaypointCount = _LastResult.Get_Waypoints().Num();
        const auto FailReason = _LastResult.Get_Diagnostics().Get_LastFailReason();
        const auto QueryMs = _LastResult.Get_Diagnostics().Get_LastQueryDurationMs();

        const auto Description =
            FString("Console: Ck_GymCrowd_Path_IssueGood / IssueBad / Status\n") +
            FString("Open the debugger:  ck.CrowdDebugger 1\n") +
            f"Status: {Status}   Waypoints: {WaypointCount}\n" +
            f"Fail reason: {FailReason}\n" +
            f"Last query: {QueryMs} ms";

        CkGym_Common::Update_StationDisplay(_StationHandle, "PATHFINDING", Description, "");
    }

    UFUNCTION(Exec, DisplayName="Crowd Pathfinding - Issue Good Path")
    void Ck_GymCrowd_Path_IssueGood()
    {
        if (HasAuthority() == false) { return; }
        AttachBindings();
        if (ck::Is_NOT_Valid(_StationHandle))
        {
            ck::Warning("Pathfinding gym: no station yet");
            return;
        }

        // Project setting NavQuerySearchHalfExtent is 500cm; the navmesh must contain a
        // walkable area within this distance of (StationXY+500, StationZ). For the
        // CkTests_Level the floor extends well past 500cm so this should always succeed.
        // Use the station-anchor helper rather than casting the handle to a typesafe
        // transform — 'Cast' is an AS reserved word, and this avoids the conversion entirely.
        const auto StationXform = Get_StationAnchorTransform("Gym.Crowd.Pathfinding", ECk_GymStation_Anchor::FootprintCenter);
        const auto Target = StationXform.GetLocation() + FVector(500.0, 0.0, 0.0);

        auto Request = FCk_Request_Nav_FindPath(Target);
        utils_nav::Request_FindPath(_StationHandle, Request);

        ck::Trace(f"Pathfinding gym: enqueued FindPath -> {Target}");
    }

    UFUNCTION(Exec, DisplayName="Crowd Pathfinding - Issue Bad Path")
    void Ck_GymCrowd_Path_IssueBad()
    {
        if (HasAuthority() == false) { return; }
        AttachBindings();
        if (ck::Is_NOT_Valid(_StationHandle))
        {
            ck::Warning("Pathfinding gym: no station yet");
            return;
        }

        // Far outside any reasonable navmesh — should fail with EndProjectFailed.
        const auto Target = FVector(99999.0, 99999.0, 99999.0);

        auto Request = FCk_Request_Nav_FindPath(Target);
        utils_nav::Request_FindPath(_StationHandle, Request);

        ck::Trace(f"Pathfinding gym: enqueued failing FindPath -> {Target}");
    }

    UFUNCTION(Exec, DisplayName="Crowd Pathfinding - Print Status")
    void Ck_GymCrowd_Path_Status()
    {
        if (ck::Is_NOT_Valid(_StationHandle))
        {
            ck::Trace("Pathfinding gym: no station");
            return;
        }
        const auto Result = utils_nav::Get_PathResult(_StationHandle);
        ck::Trace(f"Pathfinding gym status: {Result.Get_Status()}  waypoints={Result.Get_Waypoints().Num()}  fail={Result.Get_Diagnostics().Get_LastFailReason()}  duration={Result.Get_Diagnostics().Get_LastQueryDurationMs()}ms");
    }

    UFUNCTION(Exec, DisplayName="Crowd Pathfinding - Diagnostics")
    void Ck_GymCrowd_Path_Diag()
    {
        ck::Trace("============ Pathfinding Gym Diagnostics ============");
        ck::Trace(f"  HasAuthority         : {HasAuthority()}");
        ck::Trace(f"  _StationHandle valid : {ck::IsValid(_StationHandle)}  ({_StationHandle.ToString()})");
        ck::Trace(f"  _BindingsAttached    : {_BindingsAttached}");

        if (ck::IsValid(_StationHandle))
        {
            ck::Trace(f"  Has PathResult      : {utils_nav::Has_Path(_StationHandle)}");
            ck::Trace(f"  Current PathStatus  : {utils_nav::Get_PathStatus(_StationHandle)}");

            const auto Result = utils_nav::Get_PathResult(_StationHandle);
            const auto Diag = Result.Get_Diagnostics();
            ck::Trace(f"  Last fail reason    : {Diag.Get_LastFailReason()}");
            ck::Trace(f"  Last target         : {Diag.Get_LastTargetLocation()}");
            ck::Trace(f"  Last agent loc      : {Diag.Get_LastAgentLocation()}");
            ck::Trace(f"  Start projected     : {Diag.Get_StartProjected()}  -> {Diag.Get_LastProjectedStart()}");
            ck::Trace(f"  End projected       : {Diag.Get_EndProjected()}  -> {Diag.Get_LastProjectedEnd()}");
            ck::Trace(f"  Raw / Extracted     : {Diag.Get_RawPathPointCount()} / {Diag.Get_ExtractedWaypointCount()}");
            ck::Trace(f"  Last query duration : {Diag.Get_LastQueryDurationMs()} ms");
            ck::Trace(f"  Waypoints           : {Result.Get_Waypoints().Num()} entries");
        }
        ck::Trace("=====================================================");
    }
}
