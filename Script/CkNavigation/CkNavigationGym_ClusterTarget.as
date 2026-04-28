//============================================================================
// CkNavigationGym_ClusterTarget
//
// Spawns N CrowdAgents around the station and issues paths to a single
// shared target marker. Every TargetMoveIntervalSeconds the director picks
// a new target position, moves the marker, and re-issues paths to every
// agent — letting us watch dtCrowd handle a constantly-shifting goal and
// repeated re-pathing under a tight cluster.
//
// Re-targeting bypasses the agent's own arrival-flip logic (agents are
// configured with LoopBackOnArrival=false) and pushes the new path
// directly via utils_nav::Request_FindPath on each agent's NavAgent handle.
// Director collects those handles via Promise_OnConstructed as each agent
// is spawned.
//============================================================================

USTRUCT()
struct FCkNavigationGym_ClusterTargetSpawnParams
{
	UPROPERTY()
	FTransform InitialTransform = FTransform::Identity;

	UPROPERTY()
	FString StationTitle;

	UPROPERTY()
	FString StationDescription;

	UPROPERTY()
	int32 AgentCount = 12;

	// Radius of the agent cluster spawn ring around the station origin (cm).
	UPROPERTY()
	float ClusterRadius = 250.0f;

	// Distance from the station origin to each candidate target slot (cm).
	UPROPERTY()
	float TargetMoveDistance = 900.0f;

	UPROPERTY()
	float TargetMoveIntervalSeconds = 5.0f;
}

// ====================================================================================================================

class UCk_EntityScript_NavigationGym_ClusterTarget : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn) FTransform InitialTransform = FTransform::Identity;
	UPROPERTY(ExposeOnSpawn) FString StationTitle;
	UPROPERTY(ExposeOnSpawn) FString StationDescription;
	UPROPERTY(ExposeOnSpawn) int32 AgentCount = 12;
	UPROPERTY(ExposeOnSpawn) float ClusterRadius = 250.0f;
	UPROPERTY(ExposeOnSpawn) float TargetMoveDistance = 900.0f;
	UPROPERTY(ExposeOnSpawn) float TargetMoveIntervalSeconds = 5.0f;

	private TArray<FCk_Handle_NavAgent> _AgentNavs;
	private FVector _CurrentTarget = FVector::ZeroVector;
	private FCk_Handle_Pmg_DebugShape _TargetMarker;
	private float _ElapsedSinceLastMove = 0.0;
	private int32 _MoveCount = 0;

	private float TargetMarkerRadius = 60.0;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
	DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

		// Both agent ring + target sit in the station's LOCAL frame, then route through
		// TransformPosition so the grid-layout 180° yaw plants the cluster in front of
		// the player rather than mirrored behind the station.
		_CurrentTarget = InitialTransform.TransformPosition(Pick_TargetLocalForMove(0));

		// Yellow target marker — bigger than the agent markers so it's easy to spot.
		_TargetMarker = UCk_Utils_Pmg_BasicShapes::Create_Sphere(
			InHandle,
			FTransform(_CurrentTarget),
			TargetMarkerRadius,
			16, 16,
			ECk_Plane_Axis::XY,
			FLinearColor(1.0, 0.85, 0.0, 0.55),    // golden yellow
			true,
			3.0f,
			-1.0f);

		// Spawn agents around the station origin in a small ring. Each will
		// path to _CurrentTarget initially; subsequent re-targets happen via
		// the director's tick.
		const auto TwoPi = 6.28318530718;
		for (int32 i = 0; i < AgentCount; ++i)
		{
			const auto Angle = float(TwoPi * float(i) / float(AgentCount));
			const auto Spawn = InitialTransform.TransformPosition(FVector(Math::Cos(Angle) * ClusterRadius, Math::Sin(Angle) * ClusterRadius, 0.0));

			Spawn_Agent(InHandle, Spawn, _CurrentTarget);
		}

		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));
		Request_UpdateDisplay();

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	private void Spawn_Agent(FCk_Handle& InOwner, FVector InSpawn, FVector InTarget)
	{
		auto Params = FCkNavigationGym_CrowdAgentSpawnParams();
		Params.InitialTransform  = FTransform(InSpawn);
		Params.TargetLocation    = InTarget;
		Params.LoopBackOnArrival = false;        // director owns re-targeting
		Params.MarkerColour      = FLinearColor(0.4, 0.5, 1.0, 0.45);   // light blue

		auto Pending = utils_entity_script::Request_SpawnEntity(
			InOwner,
			UCk_EntityScript_NavigationGym_CrowdAgent,
			FInstancedStruct::Make(Params));

		utils_pending_entity_script::Promise_OnConstructed(
			Pending,
			FCk_Delegate_EntityScript_Constructed(this, n"OnAgentConstructed"));
	}

	UFUNCTION()
	private void OnAgentConstructed(FCk_Handle_EntityScript InAgentScript)
	{
		auto AgentEntity = FCk_Handle(InAgentScript);
		auto NavH = AgentEntity.As_NavAgent();
		_AgentNavs.Add(NavH);
	}

	UFUNCTION()
	private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		_ElapsedSinceLastMove = _ElapsedSinceLastMove + float(InDeltaT.Get_Seconds());
		if (_ElapsedSinceLastMove < TargetMoveIntervalSeconds) { return; }

		_ElapsedSinceLastMove = 0.0;
		_MoveCount = _MoveCount + 1;

		_CurrentTarget = InitialTransform.TransformPosition(Pick_TargetLocalForMove(_MoveCount));

		// Move the target marker.
		utils_transform::Request_SetLocation(_TargetMarker, _CurrentTarget, ECk_LocalWorld::World);

		// Re-issue paths for every agent we've collected so far. Direct
		// utils_nav::Request_FindPath bypasses the agent's arrival latch —
		// since LoopBackOnArrival=false, agents otherwise sit idle once they
		// reach a target.
		for (int32 i = 0; i < _AgentNavs.Num(); ++i)
		{
			utils_nav::Request_FindPath(_AgentNavs[i], FCk_Request_Nav_FindPath(_CurrentTarget));
		}

		Request_UpdateDisplay();
	}

	// Picks a deterministic-but-varied target offset (in the station's LOCAL frame) using
	// golden-angle rotation so successive moves don't land in obvious patterns. Caller
	// composes the world location via InitialTransform.TransformPosition.
	private FVector Pick_TargetLocalForMove(int32 InMoveIndex)
	{
		const auto GoldenAngle = 2.39996323;    // radians (137.5 degrees)
		const auto Angle = float(GoldenAngle * float(InMoveIndex));
		return FVector(Math::Cos(Angle) * TargetMoveDistance, Math::Sin(Angle) * TargetMoveDistance, 0.0);
	}

	private void Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto Display = f"Agents: {AgentCount}    Cluster radius: {ClusterRadius :.0} cm\n";
		Display = f"{Display}Target moves every {TargetMoveIntervalSeconds :.1}s    Moves so far: {_MoveCount}\n";
		Display = f"{Display}Director re-issues paths to every agent on each move.";

		CkGym_Common::Update_StationDisplay(SelfEntity, StationTitle, Display, StationDescription);
	}
}
