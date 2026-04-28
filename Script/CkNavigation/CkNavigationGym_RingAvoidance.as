//============================================================================
// CkNavigationGym_RingAvoidance
//
// Spawns N CrowdAgents evenly distributed on a circle around the station.
// Each agent targets the diametric opposite point on the ring; when it
// arrives, LoopBackOnArrival flips it back to its origin and it heads home.
// All agents converge through the centre simultaneously, exercising
// dtCrowd's inter-agent avoidance.
//============================================================================

USTRUCT()
struct FCkNavigationGym_RingAvoidanceSpawnParams
{
	UPROPERTY()
	FTransform InitialTransform = FTransform::Identity;

	UPROPERTY()
	FString StationTitle;

	UPROPERTY()
	FString StationDescription;

	UPROPERTY()
	int32 AgentCount = 12;

	UPROPERTY()
	float RingRadius = 800.0f;
}

// ====================================================================================================================

class UCk_EntityScript_NavigationGym_RingAvoidance : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn) FTransform InitialTransform = FTransform::Identity;
	UPROPERTY(ExposeOnSpawn) FString StationTitle;
	UPROPERTY(ExposeOnSpawn) FString StationDescription;
	UPROPERTY(ExposeOnSpawn) int32 AgentCount = 12;
	UPROPERTY(ExposeOnSpawn) float RingRadius = 800.0f;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
	DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

		// Ring + targets are computed in the station's LOCAL frame, then routed through
		// TransformPosition so the grid-layout 180° yaw doesn't mirror them out of view.
		// The ring is symmetric so it'd look the same either way, but consistent with the
		// other nav stations (and correct if a station is ever placed at a non-180 yaw).
		const auto TwoPi = 6.28318530718;

		for (int32 i = 0; i < AgentCount; ++i)
		{
			const auto Angle = float(TwoPi * float(i) / float(AgentCount));
			const auto Cos = Math::Cos(Angle);
			const auto Sin = Math::Sin(Angle);

			const auto Spawn  = InitialTransform.TransformPosition(FVector( Cos * RingRadius,  Sin * RingRadius, 0.0));
			const auto Target = InitialTransform.TransformPosition(FVector(-Cos * RingRadius, -Sin * RingRadius, 0.0));

			Spawn_Agent(InHandle, Spawn, Target);
		}

		Request_UpdateDisplay();

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	private void Spawn_Agent(FCk_Handle& InOwner, FVector InSpawnLocation, FVector InTargetLocation)
	{
		auto Params = FCkNavigationGym_CrowdAgentSpawnParams();
		Params.InitialTransform   = FTransform(InSpawnLocation);
		Params.TargetLocation     = InTargetLocation;
		Params.LoopBackOnArrival  = true;
		Params.MarkerColour       = FLinearColor(0.0, 1.0, 1.0, 0.45);   // cyan

		utils_entity_script::Request_SpawnEntity(
			InOwner,
			UCk_EntityScript_NavigationGym_CrowdAgent,
			FInstancedStruct::Make(Params));
	}

	private void Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto Display = f"Agents: {AgentCount}    Ring radius: {RingRadius :.0} cm\n";
		Display = f"{Display}Looping forever — each agent ping-pongs to the opposite\n";
		Display = f"{Display}side of the ring, all converging through the centre.";

		CkGym_Common::Update_StationDisplay(SelfEntity, StationTitle, Display, StationDescription);
	}
}
