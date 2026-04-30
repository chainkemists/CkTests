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

	// Seconds to wait before re-issuing a path request after a failure. Tuned to comfortably
	// exceed the 0.5s nav-regen debounce so a navmesh-not-ready-yet failure on the first
	// request resolves on the next attempt. Same idea covers dynamic-nav rebake hiccups.
	private float RetryDelaySeconds = 1.0f;

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

	// Movement-state guard for arrival detection. dtCrowd needs a frame or two to ramp
	// velocity from 0 once a target is set, so we'd otherwise mistake "haven't started yet"
	// for "arrived" and flip targets immediately. Only after Speed exceeds the threshold
	// at least once is the next dip below the threshold a real arrival.
	private bool HasStartedMoving = false;

	// Retry bookkeeping for failed path queries (initial-spawn case where the navmesh isn't
	// ready yet, plus any later transient failures).
	private float TimeSinceLastFailedRequest = 0.0f;

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
		// Reset arrival/retry state so the new path can be detected as arriving naturally.
		HasArrivedOnce = false;
		HasStartedMoving = false;
		TimeSinceLastFailedRequest = 0.0f;
		Request_UpdateDisplay();
	}

	UFUNCTION()
	private void OnNavPathFailed(FCk_Handle_NavAgent InHandle)
	{
		LastStatus = ECk_Nav_PathStatus::Failed;
		LastWaypointCount = 0;
		// OnTick will count up TimeSinceLastFailedRequest and re-issue once it exceeds
		// RetryDelaySeconds. Avoids spinning a re-request every frame while the navmesh
		// is still being built.
		TimeSinceLastFailedRequest = 0.0f;
		Request_UpdateDisplay();
	}

	UFUNCTION()
	private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		auto DeltaSeconds = float(InDeltaT.Get_Seconds());

		// FindPath retry runs INDEPENDENT of dtCrowd registration. Path queries go through
		// FProcessor_Nav_HandleRequests which doesn't touch dtCrowd at all — gating retry
		// on IsCrowdRegistered means a navmesh-not-yet-baked spawn keeps the agent stuck
		// even after the navmesh comes up, because crowd setup and path retry are coupled.
		if (LastStatus == ECk_Nav_PathStatus::Failed && utils_nav::Get_HasPath(NavAgentHandle) == false)
		{
			TimeSinceLastFailedRequest += DeltaSeconds;
			if (TimeSinceLastFailedRequest >= RetryDelaySeconds)
			{
				TimeSinceLastFailedRequest = 0.0f;
				Request_PathToCurrentTarget();
			}
		}

		// dtCrowd hasn't registered the agent yet (one-frame setup latency, P3-3 debounce, etc.).
		if (utils_nav::Get_IsCrowdRegistered(NavAgentHandle) == false)
		{
			Request_UpdateDisplay();
			return;
		}

		// No usable path yet — waiting for OnNavPathReady (the retry block above keeps
		// re-issuing if the last attempt failed).
		if (utils_nav::Get_HasPath(NavAgentHandle) == false)
		{
			Request_UpdateDisplay();
			return;
		}

		LastVelocity = utils_nav::Get_CurrentVelocity(NavAgentHandle);
		auto Speed = LastVelocity.Size();

		// Latch HasStartedMoving the first time the agent crosses the speed threshold —
		// only then is "speed dipped below the threshold" a meaningful arrival signal.
		// Without this guard, the spawn-frame Speed=0 fires arrival immediately, flips
		// the target back to TargetA (which equals the spawn location → degenerate path
		// → fails), and the agent gets stuck forever.
		if (Speed >= ArrivalSpeedThreshold)
		{
			HasStartedMoving = true;
			HasArrivedOnce = false;
		}

		if (HasStartedMoving && Speed < ArrivalSpeedThreshold && HasArrivedOnce == false)
		{
			HasArrivedOnce = true;
			HasStartedMoving = false;
			ArrivalCount++;
			MovingTowardB = !MovingTowardB;
			Request_PathToCurrentTarget();
			Request_UpdateDisplay();
			return;
		}

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
