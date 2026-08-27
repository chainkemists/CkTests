//============================================================================
// CkSnapshot AS SaveGame-field round-trip fixture (spec 4B.3)
//
// A minimal AngelScript EntityScript exercising the framework FCk_SaveData_EntityScriptFields
// handler (CkEcs). The C++ gate Test_Snapshot_AS_SaveFields_Gate.spec.cpp spawns this as a
// RuntimeSpawned child of the M2a probe, mutates the fields by reflection, saves, loads, then
// asserts the SaveGame fields survived and the non-SaveGame field reset to its class default.
//
// UPROPERTY(SaveGame) sets the REAL CPF_SaveGame flag on the engine-fork AngelScript path. The
// inert meta=(SaveGame) form (see Script/ECS/CosmeticOwnership/BB_CosmeticOwnership_Feature.as)
// is DELIBERATELY not used here - the gate precondition-asserts CPF_SaveGame on these fields.
//============================================================================

class UCkSnapshot_AsSaveFields_EntityScript : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	// SaveGame-tagged - MUST round-trip a v3 rebuild+hydrate load.
	UPROPERTY(SaveGame)
	int32 SavedInt = 0;

	UPROPERTY(SaveGame)
	FString SavedString;

	UPROPERTY(SaveGame)
	TArray<int32> SavedArray;

	// Negation control - NOT SaveGame-tagged; MUST reset to the class default (0) on load.
	UPROPERTY()
	int32 PlainInt = 0;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
	DoConstruct(
		FCk_Handle& InHandle)
	{
		return ECk_EntityScript_ConstructionFlow::Finished;
	}
}
