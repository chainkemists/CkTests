//============================================================================
// CkNavigationGym_CrowdAgent
//
// One nav agent that:
//   - Registers with dtCrowd via utils_nav::Add (Radius=35, Height=144 to
//     match SupportedAgents in DefaultEngine.ini).
//   - Issues a path to TargetLocation on construction.
//   - Each tick reads dtCrowd's steered velocity and integrates it into the
//     entity transform via Request_SetTransform.
//   - Owns a small PMG sphere visual that follows the entity each tick (the
//     marker is its own child entity owned by the agent — cascade-destroys).
//
// LoopBackOnArrival: when true, on arrival (speed < threshold for one frame)
// the agent flips to the opposite waypoint (TargetLocation ↔ Origin) and
// re-issues the path. Used by the Ring + CounterFlow scenarios.
//
// Set_Target(NewTarget) is the public API directors call to override the
// target externally — used by ClusterTarget when the moving target marker
// shifts and all agents need a new path.
//============================================================================

USTRUCT()
struct FCkNavigationGym_CrowdAgentSpawnParams
{
	UPROPERTY()
	FTransform InitialTransform = FTransform::Identity;

	UPROPERTY()
	FVector TargetLocation = FVector::ZeroVector;

	UPROPERTY()
	bool LoopBackOnArrival = false;

	UPROPERTY()
	FLinearColor MarkerColour = FLinearColor(0.0, 1.0, 1.0, 0.4);
}

// ====================================================================================================================

class UCk_EntityScript_NavigationGym_CrowdAgent : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn) FTransform InitialTransform = FTransform::Identity;
	UPROPERTY(ExposeOnSpawn) FVector TargetLocation = FVector::ZeroVector;
	UPROPERTY(ExposeOnSpawn) bool LoopBackOnArrival = false;
	UPROPERTY(ExposeOnSpawn) FLinearColor MarkerColour = FLinearColor(0.0, 1.0, 1.0, 0.4);

	// Tunables — kept private const-ish (AS class fields, defaults only).
	private float AgentRadius = 35.0;
	private float AgentHeight = 144.0;
	private float ArrivalSpeedThreshold = 25.0;
	private float MarkerRadius = 30.0;

	private FCk_Handle_Transform _TransformH;
	private FCk_Handle_NavAgent _NavH;
	private FCk_Handle_Pmg_DebugShape _MarkerH;

	private FVector _Origin = FVector::ZeroVector;
	private FVector _CurrentTarget = FVector::ZeroVector;
	private bool _MovingToTarget = true;
	private bool _HasArrivedOnce = false;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
	DoConstruct(FCk_Handle& InHandle)
	{
		_TransformH = utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

		auto AgentParams = FCk_Nav_AgentParams();
		AgentParams.Set_Radius(AgentRadius);
		AgentParams.Set_Height(AgentHeight);
		_NavH = utils_nav::Add(_TransformH, AgentParams);

		_Origin = InitialTransform.GetLocation();
		_CurrentTarget = TargetLocation;

		// Visual marker — separate child entity owned by the agent so it
		// cascade-destroys, manually moved each tick to follow.
		_MarkerH = UCk_Utils_Pmg_BasicShapes::Create_Sphere(
			InHandle,
			FTransform(_Origin),
			MarkerRadius,
			12, 12,
			ECk_Plane_Axis::XY,
			MarkerColour,
			true,    // wireframe overlay (PMG idiom)
			2.0f,
			-1.0f);  // persistent

		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));
		Request_PathToCurrentTarget();

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	// Director-facing API: re-target the agent. Resets the arrival latch so
	// the agent will re-detect arrival at the new destination.
	UFUNCTION()
	void Set_Target(FVector InTarget)
	{
		_CurrentTarget = InTarget;
		_HasArrivedOnce = false;
		_MovingToTarget = true;
		Request_PathToCurrentTarget();
	}

	private void Request_PathToCurrentTarget()
	{
		if (ck::IsValid(_NavH) == false) { return; }
		utils_nav::Request_FindPath(_NavH, FCk_Request_Nav_FindPath(_CurrentTarget));
	}

	UFUNCTION()
	private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		auto Dt = float(InDeltaT.Get_Seconds());

		if (utils_nav::Get_IsCrowdRegistered(_NavH) == false) { return; }
		if (utils_nav::Get_HasPath(_NavH) == false) { return; }

		auto Velocity = utils_nav::Get_CurrentVelocity(_NavH);
		auto Speed = Velocity.Size();

		// Integrate velocity into the entity transform.
		auto Current = utils_transform::Get_EntityCurrentTransform(_TransformH).GetLocation();
		auto NewLoc = Current + Velocity * Dt;
		utils_transform::Request_SetTransform(
			_TransformH,
			FCk_Request_Transform_SetTransform(FTransform(NewLoc)));

		// Move marker to match. FCk_Handle_Pmg_DebugShape is its own entity with
		// a transform — utils_transform works directly on the handle.
		utils_transform::Request_SetLocation(_MarkerH, NewLoc, ECk_LocalWorld::World);

		// Arrival detection — dtCrowd ramps velocity to ~0 as the agent reaches its destination.
		if (Speed < ArrivalSpeedThreshold && _HasArrivedOnce == false)
		{
			_HasArrivedOnce = true;
			if (LoopBackOnArrival)
			{
				_MovingToTarget = !_MovingToTarget;
				_CurrentTarget = _MovingToTarget ? TargetLocation : _Origin;
				Request_PathToCurrentTarget();
			}
		}
		else if (Speed >= ArrivalSpeedThreshold)
		{
			_HasArrivedOnce = false;
		}
	}
}
