USTRUCT()
struct FUnrealComponentGym_DisplaySpawnParams
{
	UPROPERTY()
	FTransform InitialTransform = FTransform::Identity;

	UPROPERTY()
	TWeakObjectPtr<ACk_UnrealComponentGym_Driver> LinkedDriver;
}

//============================================================================
// CkUnrealComponent Gym - Display Entity Script
//
// One per station. Reads the driver's runtime state and updates the station
// display each frame.
//============================================================================

class UCk_EntityScript_UnrealComponentGym_Display : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	UPROPERTY(ExposeOnSpawn)
	TWeakObjectPtr<ACk_UnrealComponentGym_Driver> LinkedDriver;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
	    auto _CkPerfScope = ck::ScopedStat();
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_UnrealComponentGym_Display");

		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"DisplayTick"));

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION()
	private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		auto Driver = LinkedDriver.Get();
		if (ck::IsValid(Driver) == false)
		{ return; }

		auto SelfEntity = ck::ToEntity(this);
		auto Type = Driver.ComponentType;

		auto TitleText = f"{Type}" + " (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";
		auto DisplayText = "";
		auto Instructions = "";

		auto IsReady = Driver.ComponentReady;
		UActorComponent Component = nullptr;
		if (ck::IsValid(Driver.ComponentHandle))
		{
			Component = utils_unreal_component::Get_Component(Driver.ComponentHandle);
		}
		auto ComponentValid = ck::IsValid(Component);

		auto OwningEntity = ck::IsValid(Driver.ComponentHandle)
			? utils_unreal_component::Get_OwningEntity(Driver.ComponentHandle)
			: FCk_Handle();
		auto OwnerValid = ck::IsValid(OwningEntity);

		auto LiveLocation = ck::IsValid(Driver.EcsEntity)
			? utils_transform::Get_EntityCurrentLocation(Driver.EcsEntity)
			: FVector::ZeroVector;

		DisplayText = f"Component class: {Get_TypeLabel(Type)}\n";
		DisplayText = f"{DisplayText}OnAdded fired: {Driver.OnAddedFireCount}x\n";
		DisplayText = f"{DisplayText}Component ready: {IsReady}\n";
		DisplayText = f"{DisplayText}Component ptr valid: {ComponentValid}\n";
		DisplayText = f"{DisplayText}OwningEntity valid: {OwnerValid}\n\n";
		DisplayText = f"{DisplayText}Entity location:\n";
		DisplayText = f"{DisplayText}  X: {LiveLocation.X}\n";
		DisplayText = f"{DisplayText}  Y: {LiveLocation.Y}\n";
		DisplayText = f"{DisplayText}  Z: {LiveLocation.Z}";

		Instructions = "Driver spawns an ECS entity with Transform.\n"
			+ "Calls utils_unreal_component::Add(...) to attach the\n"
			+ "named UActorComponent class - no AActor outer.\n"
			+ "OnAdded callback configures the component.\n"
			+ "Entity orbits, PushTransform processor mirrors that\n"
			+ "onto the SceneComponent every frame.";

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
	}

	private FString Get_TypeLabel(ECk_UnrealComponentGym_Type InType)
	{
		if (InType == ECk_UnrealComponentGym_Type::StaticMesh) { return "UStaticMeshComponent"; }
		if (InType == ECk_UnrealComponentGym_Type::PointLight) { return "UPointLightComponent"; }
		if (InType == ECk_UnrealComponentGym_Type::SpotLight)  { return "USpotLightComponent"; }
		if (InType == ECk_UnrealComponentGym_Type::TextRender) { return "UTextRenderComponent"; }
		if (InType == ECk_UnrealComponentGym_Type::Arrow)      { return "UArrowComponent"; }
		if (InType == ECk_UnrealComponentGym_Type::Box)        { return "UBoxComponent"; }
		if (InType == ECk_UnrealComponentGym_Type::Sphere)     { return "USphereComponent"; }
		if (InType == ECk_UnrealComponentGym_Type::Capsule)    { return "UCapsuleComponent"; }
		return "Unknown";
	}
}
