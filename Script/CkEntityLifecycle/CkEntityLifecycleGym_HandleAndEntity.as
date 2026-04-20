//============================================================================
// ENTITY LIFECYCLE GYM - HANDLE & ENTITY BASICS
// Tests: utils_handle, utils_entity
//============================================================================

class UCk_EntityScript_EntityLifecycleGym_HandleAndEntity : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	// Test results
	bool Pass_SetGetDebugName = false;
	bool Pass_IsValid_Self = false;
	bool Pass_IsValid_Invalid = false;
	bool Pass_HandleEqual_Self = false;
	bool Pass_HandleNotEqual_Invalid = false;
	bool Pass_BreakHandle = false;
	bool Pass_BreakEntity = false;
	bool Pass_TombstoneNotEqualSelf = false;
	bool Pass_EntityEqual_Self = false;
	bool Pass_EntityNotEqual_Tombstone = false;

	// Display values
	FString HandleString = "";
	FString EntityString = "";
	FString DebugNameResult = "";
	int32 EntityID = 0;
	int32 EntityNumber = 0;
	int32 EntityVersion = 0;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_LifecycleGym_HandleAndEntity");

		// Display tick
		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"DisplayTick"));

		// --- Run all tests ---

		// Test: Set/Get debug name
		utils_handle::Set_DebugName(InHandle, n"TestEntity");
		auto RetrievedName = utils_handle::Get_DebugName(InHandle);
		DebugNameResult = RetrievedName.ToString();
		Pass_SetGetDebugName = (RetrievedName == n"TestEntity");

		// Test: Handle validity
		Pass_IsValid_Self = utils_handle::Get_IsValid(InHandle);
		auto InvalidHandle = utils_handle::Get_InvalidHandle();
		Pass_IsValid_Invalid = (utils_handle::Get_IsValid(InvalidHandle) == false);

		// Test: Handle equality
		Pass_HandleEqual_Self = utils_handle::IsEqual(InHandle, InHandle);
		Pass_HandleNotEqual_Invalid = utils_handle::IsNotEqual(InHandle, InvalidHandle);

		// Test: Handle to string
		HandleString = utils_handle::Conv_HandleToString(InHandle);

		// Test: Break handle to entity
		auto SelfEntity = FCk_Entity();
		utils_handle::Break_Handle(InHandle, SelfEntity);
		Pass_BreakHandle = (utils_entity::Conv_EntityToString(SelfEntity).Len() > 0);

		// Test: Break entity to components
		utils_entity::Break_Entity(SelfEntity, EntityID, EntityNumber, EntityVersion);
		Pass_BreakEntity = (EntityID != 0 || EntityNumber != 0);

		// Test: Entity to string
		EntityString = utils_entity::Conv_EntityToString(SelfEntity);

		// Test: Tombstone entity
		auto Tombstone = utils_entity::Get_TombstoneEntity();
		Pass_TombstoneNotEqualSelf = utils_entity::IsNotEqual(SelfEntity, Tombstone);

		// Test: Entity equality
		Pass_EntityEqual_Self = utils_entity::IsEqual(SelfEntity, SelfEntity);
		Pass_EntityNotEqual_Tombstone = utils_entity::IsNotEqual(SelfEntity, Tombstone);

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION()
	private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		Request_UpdateDisplay();
	}

	void Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "HANDLE & ENTITY BASICS (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";

		auto D = "";

		D = f"{D}--- utils_handle ---\n";
		D = f"{D}" + (Pass_SetGetDebugName ? "[+] " : "[-] ") + f"Set/Get DebugName '{DebugNameResult}'\n";
		D = f"{D}" + (Pass_IsValid_Self ? "[+] " : "[-] ") + "IsValid(self) = true\n";
		D = f"{D}" + (Pass_IsValid_Invalid ? "[+] " : "[-] ") + "IsValid(invalid) = false\n";
		D = f"{D}" + (Pass_HandleEqual_Self ? "[+] " : "[-] ") + "IsEqual(self, self)\n";
		D = f"{D}" + (Pass_HandleNotEqual_Invalid ? "[+] " : "[-] ") + "IsNotEqual(self, invalid)\n";
		D = f"{D}    Conv_HandleToString: {HandleString}\n";
		D = f"{D}" + (Pass_BreakHandle ? "[+] " : "[-] ") + "Break_Handle -> entity valid\n\n";

		D = f"{D}--- utils_entity ---\n";
		D = f"{D}" + (Pass_BreakEntity ? "[+] " : "[-] ") + f"Break_Entity: ID={EntityID} Num={EntityNumber} Ver={EntityVersion}\n";
		D = f"{D}    Conv_EntityToString: {EntityString}\n";
		D = f"{D}" + (Pass_EntityEqual_Self ? "[+] " : "[-] ") + "IsEqual(self, self)\n";
		D = f"{D}" + (Pass_EntityNotEqual_Tombstone ? "[+] " : "[-] ") + "IsNotEqual(self, tombstone)\n";
		D = f"{D}" + (Pass_TombstoneNotEqualSelf ? "[+] " : "[-] ") + "Tombstone != self\n";

		auto AllPassed = Pass_SetGetDebugName && Pass_IsValid_Self && Pass_IsValid_Invalid
			&& Pass_HandleEqual_Self && Pass_HandleNotEqual_Invalid && Pass_BreakHandle
			&& Pass_BreakEntity && Pass_TombstoneNotEqualSelf && Pass_EntityEqual_Self
			&& Pass_EntityNotEqual_Tombstone;

		D = f"{D}\nRESULT: " + (AllPassed ? "ALL TESTS PASSED" : "SOME TESTS FAILED");

		auto Instructions = "Tests handle validity, debug names, entity decomposition,\n"
			+ "comparison, and string conversion.";

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, D, Instructions);
	}
}
