//============================================================================
// CkNavigationGym_DensityStress
//
// Spawns N CrowdAgents packed tightly into a small spawn box, all targeting
// a single point in the distance. Tests dtCrowd's separation behaviour
// under high density — agents must spread out to fit through gaps without
// clipping each other. One-shot: agents arrive and idle (no LoopBack).
//============================================================================

USTRUCT()
struct FCkNavigationGym_DensityStressSpawnParams
{
	UPROPERTY()
	FTransform InitialTransform = FTransform::Identity;

	UPROPERTY()
	FString StationTitle;

	UPROPERTY()
	FString StationDescription;

	UPROPERTY()
	int32 AgentCount = 24;

	// Spawn area is a square at the station origin with this side length (cm).
	// Smaller = denser pack.
	UPROPERTY()
	float SpawnAreaSize = 300.0f;

	// Distance to the shared target along +X (cm).
	UPROPERTY()
	float TargetDistance = 1500.0f;
}

// ====================================================================================================================

class UCk_EntityScript_NavigationGym_DensityStress : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn) FTransform InitialTransform = FTransform::Identity;
	UPROPERTY(ExposeOnSpawn) FString StationTitle;
	UPROPERTY(ExposeOnSpawn) FString StationDescription;
	UPROPERTY(ExposeOnSpawn) int32 AgentCount = 24;
	UPROPERTY(ExposeOnSpawn) float SpawnAreaSize = 300.0f;
	UPROPERTY(ExposeOnSpawn) float TargetDistance = 1500.0f;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
	DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

		// All offsets here are LOCAL to the station. Routed through TransformPosition so
		// the grid-layout 180° yaw plants the dense pack in front of the player and the
		// shared target ahead of them — not behind the alcove.
		const auto Target = InitialTransform.TransformPosition(FVector(TargetDistance, 0.0, 0.0));

		// Lay agents out in a roughly-square grid across the spawn area.
		// SideCount = ceil(sqrt(N)) so we always have enough cells.
		const auto SideCountF = Math::Sqrt(float(AgentCount));
		auto SideCount = int32(SideCountF);
		if (float(SideCount) < SideCountF) { SideCount = SideCount + 1; }
		if (SideCount < 1) { SideCount = 1; }

		const auto Step = SpawnAreaSize / float(SideCount);
		const auto HalfArea = SpawnAreaSize * 0.5;

		int32 Spawned = 0;
		for (int32 ix = 0; ix < SideCount; ++ix)
		{
			for (int32 iy = 0; iy < SideCount; ++iy)
			{
				if (Spawned >= AgentCount) { break; }

				const auto X = -HalfArea + (float(ix) + 0.5) * Step;
				const auto Y = -HalfArea + (float(iy) + 0.5) * Step;
				const auto Spawn = InitialTransform.TransformPosition(FVector(X, Y, 0.0));

				Spawn_Agent(InHandle, Spawn, Target);
				Spawned = Spawned + 1;
			}
		}

		Request_UpdateDisplay();

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	private void Spawn_Agent(FCk_Handle& InOwner, FVector InSpawn, FVector InTarget)
	{
		auto Params = FCkNavigationGym_CrowdAgentSpawnParams();
		Params.InitialTransform  = FTransform(InSpawn);
		Params.TargetLocation    = InTarget;
		Params.LoopBackOnArrival = false;
		Params.MarkerColour      = FLinearColor(0.2, 1.0, 0.2, 0.45);   // green

		utils_entity_script::Request_SpawnEntity(
			InOwner,
			UCk_EntityScript_NavigationGym_CrowdAgent,
			FInstancedStruct::Make(Params));
	}

	private void Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		const auto Density = float(AgentCount) / (SpawnAreaSize * SpawnAreaSize) * 10000.0;   // agents per m²
		auto Display = f"Agents: {AgentCount}    Spawn area: {SpawnAreaSize :.0}×{SpawnAreaSize :.0} cm\n";
		Display = f"{Display}Density: {Density :.2} agents/m²    Target: +X {TargetDistance :.0} cm\n";
		Display = f"{Display}One-shot — agents arrive and idle.";

		CkGym_Common::Update_StationDisplay(SelfEntity, StationTitle, Display, StationDescription);
	}
}
