USTRUCT()
struct FCkNavigationGym_MovingAgentSpawnParams
{
	UPROPERTY()
	FTransform InitialTransform = FTransform::Identity;

	UPROPERTY()
	FString StationTitle;

	UPROPERTY()
	FString StationDescription;

	// Distance to ping-pong between (along +X). Two waypoints alternate:
	//   TargetA = InitialLocation
	//   TargetB = InitialLocation + (PingPongDistance, 0, 0)
	UPROPERTY()
	float PingPongDistance = 600.0f;

	// Velocity magnitude (cm/s) below which the agent is considered "arrived" — flips
	// the target. dtCrowd ramps velocity to ~0 as the agent approaches its destination.
	UPROPERTY()
	float ArrivalSpeedThreshold = 25.0f;
}

// ====================================================================================================================
// Exercises the full crowd loop end-to-end:
//   Add → CrowdSetup (next frame, registers with dtCrowd)
//   Request_FindPath → HandleRequests (path lands same frame)
//   FTag_Nav_MoveTargetDirty → CrowdUpdateTarget (pushes destination to dtCrowd same frame)
//   each tick: CrowdStep (advances simulation) → CrowdReadVelocity (writes velocity fragment)
//   each tick (this script): read velocity → integrate → Request_SetLocation
//
// Visual indicator: the entity transform visibly moves between two waypoints. If the agent
// stays still, the path either failed (check Status) or the entity isn't crowd-registered
// yet (check CrowdRegistered). Both surface in the display.
// ====================================================================================================================

class UCk_EntityScript_NavigationGym_MovingAgent : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	UPROPERTY(ExposeOnSpawn)
	FString StationTitle;

	UPROPERTY(ExposeOnSpawn)
	FString StationDescription;

	UPROPERTY(ExposeOnSpawn)
	float PingPongDistance = 600.0f;

	UPROPERTY(ExposeOnSpawn)
	float ArrivalSpeedThreshold = 25.0f;

	private FCk_Handle_Transform TransformHandle;
	private FCk_Handle_NavAgent NavAgentHandle;

	// Ping-pong state
	private FVector TargetA = FVector::ZeroVector;
	private FVector TargetB = FVector::ZeroVector;
	private bool MovingTowardB = true;

	// Display state
	private ECk_Nav_PathStatus LastStatus = ECk_Nav_PathStatus::None;
	private int32 LastWaypointCount = 0;
	private FVector LastVelocity = FVector::ZeroVector;
	private bool HasArrivedOnce = false;
	private int32 ArrivalCount = 0;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
	DoConstruct(FCk_Handle& InHandle)
	{
		TransformHandle = utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

		auto AgentParams = FCk_Nav_AgentParams();
		// MUST match SupportedAgents in DefaultEngine.ini (35/144) — see existing FindPath
		// station for the rationale.
		AgentParams.Set_Radius(35.0);
		AgentParams.Set_Height(144.0);

		NavAgentHandle = utils_nav::Add(TransformHandle, AgentParams);

		// TargetB is offset along the station's LOCAL +X (ping-pong forward of the alcove).
		// The grid layout yaws the station 180° so we route through TransformPosition to
		// flip this into world space — agent walks toward the player, not behind the wall.
		TargetA = InitialTransform.GetLocation();
		TargetB = InitialTransform.TransformPosition(FVector(PingPongDistance, 0.0, 0.0));

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

		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));

		// Issue the first path request. We aim for TargetB; on arrival we'll flip and head back.
		Request_PathToCurrentTarget();
		Request_UpdateDisplay();

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	private void Request_PathToCurrentTarget()
	{
		if (ck::IsValid(NavAgentHandle) == false)
		{ return; }

		auto Target = MovingTowardB ? TargetB : TargetA;
		auto Request = FCk_Request_Nav_FindPath(Target);
		utils_nav::Request_FindPath(NavAgentHandle, Request);
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
		LastWaypointCount = 0;
		Request_UpdateDisplay();
	}

	UFUNCTION()
	private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		auto DeltaSeconds = float(InDeltaT.Get_Seconds());

		// dtCrowd hasn't registered the agent yet (one-frame setup latency, P3-3 debounce, etc.).
		if (utils_nav::Get_IsCrowdRegistered(NavAgentHandle) == false)
		{
			Request_UpdateDisplay();
			return;
		}

		// No usable path — wait for the next OnNavPathReady before integrating velocity.
		// (Reading velocity without a path produces near-zero noise; harmless but pointless.)
		if (utils_nav::Get_HasPath(NavAgentHandle) == false)
		{
			Request_UpdateDisplay();
			return;
		}

		LastVelocity = utils_nav::Get_CurrentVelocity(NavAgentHandle);
		auto Speed = LastVelocity.Size();

		// Arrival detection: dtCrowd ramps velocity to zero as the agent reaches its destination.
		// Below the threshold for a frame → flip target and re-issue path.
		if (Speed < ArrivalSpeedThreshold && HasArrivedOnce == false)
		{
			HasArrivedOnce = true;
			ArrivalCount++;
			MovingTowardB = !MovingTowardB;
			Request_PathToCurrentTarget();
			Request_UpdateDisplay();
			return;
		}

		// Reset arrival latch once we're moving again so the next destination's arrival is detected.
		if (Speed >= ArrivalSpeedThreshold)
		{ HasArrivedOnce = false; }

		// Integrate: NewLocation = CurrentLocation + Velocity * DeltaSeconds.
		// CrowdPushPosition reads this transform back next frame; below TeleportThresholdUu
		// (default 10cm) it's a no-op, so dtCrowd's npos stays in sync without a rebuild.
		auto Current = utils_transform::Get_EntityCurrentTransform(TransformHandle).GetLocation();
		auto NewLocation = Current + LastVelocity * DeltaSeconds;
		utils_transform::Request_SetTransform(
			TransformHandle,
			FCk_Request_Transform_SetTransform(FTransform(NewLocation)));

		Request_UpdateDisplay();
	}

	private void Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto StatusStr = GetStatusString(LastStatus);
		auto Registered = utils_nav::Get_IsCrowdRegistered(NavAgentHandle);
		auto RegisteredStr = Registered ? "YES" : "NO (waiting for CrowdSetup)";
		auto TargetLabel = MovingTowardB ? "B (forward)" : "A (back)";
		auto Speed = LastVelocity.Size();

		auto Display = f"Path: {StatusStr}  Waypoints: {LastWaypointCount}\n";
		Display = f"{Display}Crowd Registered: {RegisteredStr}\n";
		Display = f"{Display}Heading to: {TargetLabel}\n";
		Display = f"{Display}Speed: {Speed :.1} cm/s    Arrivals: {ArrivalCount}";

		CkGym_Common::Update_StationDisplay(SelfEntity, StationTitle, Display, StationDescription);
	}

	private FString GetStatusString(ECk_Nav_PathStatus InStatus)
	{
		if (InStatus == ECk_Nav_PathStatus::None)    { return "NONE"; }
		if (InStatus == ECk_Nav_PathStatus::Pending) { return "PENDING"; }
		if (InStatus == ECk_Nav_PathStatus::Ready)   { return "READY"; }
		if (InStatus == ECk_Nav_PathStatus::Failed)  { return "FAILED"; }
		if (InStatus == ECk_Nav_PathStatus::Partial) { return "PARTIAL"; }
		return "UNKNOWN";
	}
}
