//============================================================================
// ENTITY LIFECYCLE GYM - SCRIPT SPAWN & CAST
// Tests: utils_entity_script, utils_pending_entity_script
//============================================================================

//----------------------------------------------------------------------------
// Helper entity script - minimal target for spawning
//----------------------------------------------------------------------------

class UCk_EntityScript_EntityLifecycleGym_SpawnTarget : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_LifecycleGym_SpawnTarget");

		return ECk_EntityScript_ConstructionFlow::Finished;
	}
}

//----------------------------------------------------------------------------
// Main station entity script
//----------------------------------------------------------------------------

class UCk_EntityScript_EntityLifecycleGym_ScriptSpawnCast : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	// Test results
	bool Pass_SpawnRequest = false;
	bool Pass_PendingIsValid = false;
	bool Pass_ConstructedCallback = false;
	bool Pass_Has = false;
	bool Pass_GetScriptClass = false;
	bool Pass_DoCast = false;
	bool Pass_DoCastChecked = false;
	bool Pass_ScriptInChain = false;

	// Display values
	FString ScriptClassName = "";
	bool TestsComplete = false;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_LifecycleGym_ScriptSpawnCast");

		// Display tick
		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"DisplayTick"));

		// Spawn helper entity script
		auto SpawnParams = FCk_Gym_TransformSpawnParams(InitialTransform);
		auto PendingHandle = utils_entity_script::Request_SpawnEntity(
			InHandle,
			UCk_EntityScript_EntityLifecycleGym_SpawnTarget,
			FInstancedStruct::Make(SpawnParams));

		Pass_SpawnRequest = utils_pending_entity_script::Get_IsValid(PendingHandle);
		Pass_PendingIsValid = Pass_SpawnRequest;

		if (Pass_SpawnRequest)
		{
			// Register construction callback
			utils_pending_entity_script::Promise_OnConstructed(
				PendingHandle,
				FCk_Delegate_EntityScript_Constructed(this, n"OnSpawnTargetConstructed"));
		}

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION()
	private void OnSpawnTargetConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
	{
		Pass_ConstructedCallback = true;

		auto EntityHandle = FCk_Handle(InEntityScriptHandle);

		// Test: Has entity script
		Pass_Has = utils_entity_script::Has(EntityHandle);

		// Test: Get script class
		auto ScriptClass = utils_entity_script::Get_ScriptClass(InEntityScriptHandle);
		ScriptClassName = f"{ScriptClass}";
		Pass_GetScriptClass = ck::IsValid(ScriptClass);

		// Test: DoCast
		auto CastResult = utils_entity_script::DoCast(EntityHandle);
		Pass_DoCast = CastResult.IsSet();

		// Test: DoCastChecked
		auto CastCheckedResult = utils_entity_script::DoCastChecked(EntityHandle);
		Pass_DoCastChecked = utils_handle::Get_IsValid(FCk_Handle(CastCheckedResult));

		// Test: Find entity script in ownership chain
		auto ScriptInChain = utils_entity_script::TryGet_Entity_EntityScript_InOwnershipChain(EntityHandle);
		Pass_ScriptInChain = utils_handle::Get_IsValid(ScriptInChain);

		TestsComplete = true;
	}

	UFUNCTION()
	private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		Request_UpdateDisplay();
	}

	void Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "SCRIPT SPAWN & CAST (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";

		auto D = "";

		D = f"{D}--- utils_pending_entity_script ---\n";
		D = f"{D}" + (Pass_SpawnRequest ? "[+] " : "[-] ") + "Request_SpawnEntity valid\n";
		D = f"{D}" + (Pass_PendingIsValid ? "[+] " : "[-] ") + "Pending Get_IsValid\n";
		D = f"{D}" + (Pass_ConstructedCallback ? "[+] " : "[-] ") + "Promise_OnConstructed fired\n\n";

		D = f"{D}--- utils_entity_script ---\n";
		D = f"{D}" + (Pass_Has ? "[+] " : "[-] ") + "Has(entity)\n";
		D = f"{D}" + (Pass_GetScriptClass ? "[+] " : "[-] ") + f"Get_ScriptClass: {ScriptClassName}\n";
		D = f"{D}" + (Pass_DoCast ? "[+] " : "[-] ") + "DoCast succeeded\n";
		D = f"{D}" + (Pass_DoCastChecked ? "[+] " : "[-] ") + "DoCastChecked valid\n";
		D = f"{D}" + (Pass_ScriptInChain ? "[+] " : "[-] ") + "ScriptEntity in chain\n";

		if (TestsComplete)
		{
			auto AllPassed = Pass_SpawnRequest && Pass_PendingIsValid && Pass_ConstructedCallback
				&& Pass_Has && Pass_GetScriptClass && Pass_DoCast
				&& Pass_DoCastChecked && Pass_ScriptInChain;

			D = f"{D}\nRESULT: " + (AllPassed ? "ALL TESTS PASSED" : "SOME TESTS FAILED");
		}
		else
		{
			D = f"{D}\nWaiting for construction callback...";
		}

		auto Instructions = "Tests entity script spawning, construction callbacks,\n"
			+ "type queries, and handle casting.";

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, D, Instructions);
	}
}
