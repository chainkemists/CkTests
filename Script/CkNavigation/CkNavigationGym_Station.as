USTRUCT()
struct FCkNavigationGym_StationSpawnParams
{
	UPROPERTY()
	FTransform InitialTransform = FTransform::Identity;

	UPROPERTY()
	FString StationTitle;

	UPROPERTY()
	FString StationDescription;

	// Target offset relative to the station transform's location.
	UPROPERTY()
	FVector TargetOffset = FVector(500.0f, 0.0f, 0.0f);

	// How often to re-issue Request_FindPath (also re-fires after a failed query).
	UPROPERTY()
	float RepathIntervalSeconds = 5.0f;
}

// ====================================================================================================================

class UCk_EntityScript_NavigationGym_Station : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	UPROPERTY(ExposeOnSpawn)
	FString StationTitle;

	UPROPERTY(ExposeOnSpawn)
	FString StationDescription;

	UPROPERTY(ExposeOnSpawn)
	FVector TargetOffset = FVector(500.0f, 0.0f, 0.0f);

	UPROPERTY(ExposeOnSpawn)
	float RepathIntervalSeconds = 5.0f;

	private FCk_Handle_NavAgent NavAgentHandle;

	// Display state
	private int32 RequestCount = 0;
	private int32 LastWaypointCount = 0;
	private ECk_Nav_PathStatus LastStatus = ECk_Nav_PathStatus::None;
	private float TimeSinceLastRequest = 0.0f;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
	DoConstruct(FCk_Handle& InHandle)
	{
		auto TransformHandle = utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

		auto AgentParams = FCk_Nav_AgentParams();
		// MUST match the navmesh-build agent (DefaultEngine.ini SupportedAgents entry: 35/144).
		// FindPathSync rejects queries where the agent radius exceeds the build radius (the agent
		// won't fit on polys near the navmesh edges). Default FCk_Nav_AgentParams (42/192) fails
		// silently with Status=Failed even though both points project to the navmesh.
		AgentParams.Set_Radius(35.0);
		AgentParams.Set_Height(144.0);

		NavAgentHandle = utils_nav::Add(TransformHandle, AgentParams);

		// Bind completion delegates so the display reflects what HandleRequests broadcasts.
		auto OnReady = FCk_Delegate_Nav_OnPathReady(this, n"OnNavPathReady");
		utils_nav::BindTo_OnPathReady(
			NavAgentHandle,
			OnReady,
			ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
			ECk_Signal_PostFireBehavior::DoNothing);

		auto OnFailed = FCk_Delegate_Nav_OnPathFailed(this, n"OnNavPathFailed");
		utils_nav::BindTo_OnPathFailed(
			NavAgentHandle,
			OnFailed,
			ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
			ECk_Signal_PostFireBehavior::DoNothing);

		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

		Request_IssueFindPath();
		Request_UpdateDisplay();

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	private void Request_IssueFindPath()
	{
		if (ck::IsValid(NavAgentHandle) == false)
		{ return; }

		auto Target = InitialTransform.GetLocation() + TargetOffset;
		auto Request = FCk_Request_Nav_FindPath(Target);

		utils_nav::Request_FindPath(NavAgentHandle, Request);
		RequestCount++;
		TimeSinceLastRequest = 0.0f;
	}

	UFUNCTION()
	private void OnNavPathReady(FCk_Handle_NavAgent InHandle, FCk_Nav_PathResult InResult)
	{
		LastStatus = InResult.Get_Status();
		LastWaypointCount = InResult.Get_Waypoints().Num();
		Request_UpdateDisplay();
	}

	UFUNCTION()
	private void OnNavPathFailed(FCk_Handle_NavAgent InHandle)
	{
		LastStatus = ECk_Nav_PathStatus::Failed;
		LastWaypointCount = utils_nav::Get_Waypoints(NavAgentHandle).Num();
		Request_UpdateDisplay();
	}

	UFUNCTION()
	private void OnDisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		auto DeltaSeconds = float(InDeltaT.Get_Seconds());
		TimeSinceLastRequest += DeltaSeconds;

		if (TimeSinceLastRequest >= RepathIntervalSeconds)
		{
			Request_IssueFindPath();
		}

		Request_UpdateDisplay();
	}

	private void Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto StatusStr = GetStatusString(LastStatus);

		auto SecondsLeft = int(RepathIntervalSeconds - TimeSinceLastRequest) + 1;
		if (SecondsLeft < 0) { SecondsLeft = 0; }

		auto Display = f"Status: {StatusStr}    Request #{RequestCount}\n";
		Display = f"{Display}Waypoints: {LastWaypointCount}\n";
		Display = f"{Display}Target offset: ({TargetOffset.X}, {TargetOffset.Y}, {TargetOffset.Z})\n";
		Display = f"{Display}\nNext request in {SecondsLeft}s";

		CkGym_Common::Update_StationDisplay(SelfEntity, StationTitle, Display, StationDescription);
	}

	private FString GetStatusString(ECk_Nav_PathStatus InStatus)
	{
		if (InStatus == ECk_Nav_PathStatus::None)    { return "NONE (no query yet)"; }
		if (InStatus == ECk_Nav_PathStatus::Pending) { return "PENDING"; }
		if (InStatus == ECk_Nav_PathStatus::Ready)   { return "READY"; }
		if (InStatus == ECk_Nav_PathStatus::Failed)  { return "FAILED (no navmesh? destination off-mesh?)"; }
		if (InStatus == ECk_Nav_PathStatus::Partial) { return "PARTIAL"; }
		return "UNKNOWN";
	}
}
