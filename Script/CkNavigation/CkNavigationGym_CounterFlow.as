//============================================================================
// CkNavigationGym_CounterFlow
//
// Two columns of CrowdAgents walking past each other. Left column at -X
// targets +X; right column at +X targets -X. They collide in the middle —
// classic dtCrowd separation stress test. LoopBackOnArrival ping-pongs
// each agent forever.
//============================================================================

USTRUCT()
struct FCkNavigationGym_CounterFlowSpawnParams
{
	UPROPERTY()
	FTransform InitialTransform = FTransform::Identity;

	UPROPERTY()
	FString StationTitle;

	UPROPERTY()
	FString StationDescription;

	// Number of agents PER COLUMN (total = 2 × this).
	UPROPERTY()
	int32 AgentsPerColumn = 8;

	// Distance from the station centre out to each column (cm). Each column
	// will be at ±ColumnHalfDistance along X.
	UPROPERTY()
	float ColumnHalfDistance = 600.0f;

	// Spacing between agents within a column (cm along Y).
	UPROPERTY()
	float ColumnSpacing = 80.0f;
}

// ====================================================================================================================

class UCk_EntityScript_NavigationGym_CounterFlow : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn) FTransform InitialTransform = FTransform::Identity;
	UPROPERTY(ExposeOnSpawn) FString StationTitle;
	UPROPERTY(ExposeOnSpawn) FString StationDescription;
	UPROPERTY(ExposeOnSpawn) int32 AgentsPerColumn = 8;
	UPROPERTY(ExposeOnSpawn) float ColumnHalfDistance = 600.0f;
	UPROPERTY(ExposeOnSpawn) float ColumnSpacing = 80.0f;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
	DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

		const auto Center = InitialTransform.GetLocation();
		// Y offset so the column is centred on the station.
		const auto ColumnLength = float(AgentsPerColumn - 1) * ColumnSpacing;
		const auto ColumnYStart = -ColumnLength * 0.5;

		// Left column: at -X, walking toward +X. Magenta.
		// Right column: at +X, walking toward -X. Yellow.
		for (int32 i = 0; i < AgentsPerColumn; ++i)
		{
			const auto Y = ColumnYStart + float(i) * ColumnSpacing;

			const auto LeftSpawn  = Center + FVector(-ColumnHalfDistance, Y, 0.0);
			const auto LeftTarget = Center + FVector( ColumnHalfDistance, Y, 0.0);
			Spawn_Agent(InHandle, LeftSpawn, LeftTarget, FLinearColor(1.0, 0.0, 1.0, 0.45));   // magenta

			const auto RightSpawn  = Center + FVector( ColumnHalfDistance, Y, 0.0);
			const auto RightTarget = Center + FVector(-ColumnHalfDistance, Y, 0.0);
			Spawn_Agent(InHandle, RightSpawn, RightTarget, FLinearColor(1.0, 1.0, 0.0, 0.45)); // yellow
		}

		Request_UpdateDisplay();

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	private void Spawn_Agent(FCk_Handle& InOwner, FVector InSpawn, FVector InTarget, FLinearColor InColour)
	{
		auto Params = FCkNavigationGym_CrowdAgentSpawnParams();
		Params.InitialTransform  = FTransform(InSpawn);
		Params.TargetLocation    = InTarget;
		Params.LoopBackOnArrival = true;
		Params.MarkerColour      = InColour;

		utils_entity_script::Request_SpawnEntity(
			InOwner,
			UCk_EntityScript_NavigationGym_CrowdAgent,
			FInstancedStruct::Make(Params));
	}

	private void Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		const auto Total = AgentsPerColumn * 2;
		auto Display = f"Agents: {Total}  ({AgentsPerColumn} per column)\n";
		Display = f"{Display}Column distance: ±{ColumnHalfDistance :.0} cm    Spacing: {ColumnSpacing :.0} cm\n";
		Display = f"{Display}Looping forever — magenta walks +X, yellow walks -X.";

		CkGym_Common::Update_StationDisplay(SelfEntity, StationTitle, Display, StationDescription);
	}
}
