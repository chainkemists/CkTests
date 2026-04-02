//============================================================================
// ENTITY LIFECYCLE GYM - ACTOR BRIDGE
// Tests: utils_owning_actor, utils_entity_bridge
//============================================================================

class UCk_EntityScript_EntityLifecycleGym_ActorBridge : UCk_EntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	// Test results
	bool Pass_GetOwnerEntity = false;
	bool Pass_GetEntityOwningActor = false;
	bool Pass_ActorHandleRoundtrip = false;
	bool Pass_TryGetRecursive = false;
	bool Pass_IsActorEcsReady = false;
	bool Pass_HasOwningActor = false;
	bool Pass_OwningActorInChain = false;

	// Display values
	FString OwnerHandleString = "";
	FString ActorName = "";
	FString ReplicationStatus = "";

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_LifecycleGym_ActorBridge");

		// Display tick
		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"DisplayTick"));

		// --- Run all tests ---

		// Get owner entity (the station entity)
		auto OwnerHandle = ck::OwnerEntity(this);
		Pass_GetOwnerEntity = utils_handle::Get_IsValid(OwnerHandle);
		OwnerHandleString = utils_handle::Conv_HandleToString(OwnerHandle);

		// Get owning actor from owner handle
		auto StationActor = utils_owning_actor::Get_EntityOwningActor(OwnerHandle);
		Pass_GetEntityOwningActor = ck::IsValid(StationActor);
		if (ck::IsValid(StationActor))
		{
			ActorName = StationActor.GetName().ToString();
		}

		// Roundtrip: actor -> handle -> should equal owner handle
		if (ck::IsValid(StationActor))
		{
			auto RoundtripHandle = utils_owning_actor::Get_ActorEntityHandle(StationActor);
			Pass_ActorHandleRoundtrip = utils_handle::IsEqual(RoundtripHandle, OwnerHandle);
		}

		// Recursive: from self entity script's entity, walk up to find station actor
		auto RecursiveActor = utils_owning_actor::TryGet_EntityOwningActor_Recursive(InHandle);
		Pass_TryGetRecursive = ck::IsValid(RecursiveActor);

		// ECS readiness
		if (ck::IsValid(StationActor))
		{
			Pass_IsActorEcsReady = utils_owning_actor::Get_IsActorEcsReady(StationActor);
		}

		// Has owning actor component
		Pass_HasOwningActor = utils_owning_actor::Has(OwnerHandle);

		// Find owning actor entity in ownership chain
		auto OwnerInChain = utils_owning_actor::TryGet_Entity_OwningActor_InOwnershipChain(InHandle);
		Pass_OwningActorInChain = utils_handle::Get_IsValid(OwnerInChain);

		// Entity bridge: replication status
		if (ck::IsValid(StationActor))
		{
			auto ReplStatus = utils_entity_bridge::Get_DoesActorEntityReplicate(StationActor);
			ReplicationStatus = f"{ReplStatus}";
		}

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
		auto TitleText = "ACTOR BRIDGE (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";

		auto D = "";

		D = f"{D}--- utils_owning_actor ---\n";
		D = f"{D}" + (Pass_GetOwnerEntity ? "[+] " : "[-] ") + f"Owner handle valid: {OwnerHandleString}\n";
		D = f"{D}" + (Pass_GetEntityOwningActor ? "[+] " : "[-] ") + f"GetEntityOwningActor: {ActorName}\n";
		D = f"{D}" + (Pass_ActorHandleRoundtrip ? "[+] " : "[-] ") + "Actor->Handle roundtrip\n";
		D = f"{D}" + (Pass_TryGetRecursive ? "[+] " : "[-] ") + "TryGet_Recursive (self->station)\n";
		D = f"{D}" + (Pass_IsActorEcsReady ? "[+] " : "[-] ") + "IsActorEcsReady\n";
		D = f"{D}" + (Pass_HasOwningActor ? "[+] " : "[-] ") + "Has(ownerHandle)\n";
		D = f"{D}" + (Pass_OwningActorInChain ? "[+] " : "[-] ") + "OwningActor in chain\n\n";

		D = f"{D}--- utils_entity_bridge ---\n";
		D = f"{D}    Replication status: {ReplicationStatus}\n";

		auto AllPassed = Pass_GetOwnerEntity && Pass_GetEntityOwningActor
			&& Pass_ActorHandleRoundtrip && Pass_TryGetRecursive
			&& Pass_IsActorEcsReady && Pass_HasOwningActor && Pass_OwningActorInChain;

		D = f"{D}\nRESULT: " + (AllPassed ? "ALL TESTS PASSED" : "SOME TESTS FAILED");

		auto Instructions = "Tests actor-to-entity handle roundtrip, recursive actor lookup,\n"
			+ "ECS readiness, and replication status.";

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, D, Instructions);
	}
}
