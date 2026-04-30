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

        _StationHandle = Get_StationHandle("Gym.Crowd.Pathfinding");
        if (ck::Is_NOT_Valid(_StationHandle))
        {
            ck::Warning("Pathfinding gym: station handle invalid at StartGym; bind deferred");
            return;
        }

        AttachBindings();
        ck::Trace("Pathfinding gym started. Run Ck_GymCrowd_Path_IssueGood from the console.");
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
    }

    UFUNCTION()
    void OnPathReady(FCk_Handle InHandle, FCk_Nav_PathResult InResult)
    {
        _LastResult = InResult;
        ck::Trace(f"Pathfinding gym: OnPathReady — status={InResult.Get_Status()} waypoints={InResult.Get_Waypoints().Num()}");
        UpdateStationDisplay();
    }

    UFUNCTION()
    void OnPathFailed(FCk_Handle InHandle)
    {
        // Read the result back to surface the diagnostics fail-reason.
        _LastResult = utils_nav::Get_PathResult(_StationHandle);
        ck::Warning(f"Pathfinding gym: OnPathFailed — reason={_LastResult.Get_Diagnostics().Get_LastFailReason()}");
        UpdateStationDisplay();
    }

    private void UpdateStationDisplay()
    {
        const auto Status = _LastResult.Get_Status();
        const auto WaypointCount = _LastResult.Get_Waypoints().Num();
        const auto FailReason = _LastResult.Get_Diagnostics().Get_LastFailReason();
        const auto QueryMs = _LastResult.Get_Diagnostics().Get_LastQueryDurationMs();

        auto Description = TArray<FText>();
        Description.Add(FText::FromString("Console: Ck_GymCrowd_Path_IssueGood / IssueBad / Status"));
        Description.Add(FText::FromString("Open the debugger:  ck.CrowdDebugger 1"));
        Description.Add(FText::FromString(f"Status: {Status}   Waypoints: {WaypointCount}"));
        Description.Add(FText::FromString(f"Fail reason: {FailReason}"));
        Description.Add(FText::FromString(f"Last query: {QueryMs} ms"));

        CkGym_Common::Update_StationDisplay(_StationHandle, FText::FromString("PATHFINDING"), Description, FText());
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
        const auto StationXform = utils_transform::Get_EntityCurrentTransform(utils_transform::Cast(_StationHandle));
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
}
