//============================================================================
// INTEGER ATTRIBUTE GYM - PLAYER CONTROLLER & GAME MODE
//============================================================================

class ACk_IntegerAttributeGym_PlayerController : ACk_Gym_Base_PlayerController
{
	TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
	{
		auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

		// Basic Integer Attributes Station
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.Attribute.IntegerBasic");
			Station.Title = FText::FromString("INTEGER BASIC ATTRIBUTES");
			Station.Height = gym_auto::EstimateStationHeight(6, 4, 14);
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Tests integer attributes: Health (0-100), Armor (0-50), Experience (0+)."));
			Description.Add(FText::FromString("Auto-cycles through 6 phases every 2s."));
			Description.Add(FText::FromString("Console: SetHealth / SetArmor / SetExperience / AutoOn / AutoOff"));
			Station.Description = Description;
			Stations.Add(Station);
		}

		// Min/Max/Current Station
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.Attribute.IntegerMinMaxCurrent");
			Station.Title = FText::FromString("INTEGER MIN/MAX/CURRENT");
			Station.Height = gym_auto::EstimateStationHeight(6, 3, 16);
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Displays all three attribute components independently."));
			Description.Add(FText::FromString("Shows how Min, Max, and Current values interact and update."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		// Modifiers Station
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.Attribute.IntegerModifiers");
			Station.Title = FText::FromString("INTEGER MODIFIERS");
			Station.Height = gym_auto::EstimateStationHeight(4, 5, 12);
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Tests attribute modifier system with add/remove operations."));
			Description.Add(FText::FromString("Demonstrates weapon and buff modifier stacking."));
			Description.Add(FText::FromString("Console: AddWeaponBonus / AddBuffBonus / RemoveWeaponBonus / RemoveBuffBonus / ClearAllModifiers"));
			Station.Description = Description;
			Stations.Add(Station);
		}

		// Clamping & Signals Station
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.Attribute.IntegerClamping");
			Station.Title = FText::FromString("INTEGER CLAMPING & SIGNALS");
			Station.Height = gym_auto::EstimateStationHeight(1, 3, 10);
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Tests automatic value clamping and signal callbacks."));
			Description.Add(FText::FromString("Monitors OnMinClamped, OnMaxClamped events."));
			Description.Add(FText::FromString("Console: TestBoundaries / ResetClamping"));
			Station.Description = Description;
			Stations.Add(Station);
		}

		gym_auto::NormalizeStationHeights(Stations);
		return Stations;
	}

	void Request_StartGym() override
	{
		Request_StartBasicStation();
		Request_StartMinMaxCurrentStation();
		Request_StartModifiersStation();
		Request_StartClampingStation();
	}

	//------------------------------------------------------------------------
	// STATION STARTUP FUNCTIONS
	//------------------------------------------------------------------------

	void Request_StartBasicStation()
	{
		auto StationTransform = Get_StationTransform("Gym.Attribute.IntegerBasic");
		auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Attribute.IntegerBasic"),
			UCk_EntityScript_IntegerGym_Basic,
			FInstancedStruct::Make(SpawnParams)
		);
	}

	void Request_StartMinMaxCurrentStation()
	{
		auto StationTransform = Get_StationTransform("Gym.Attribute.IntegerMinMaxCurrent");
		auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Attribute.IntegerMinMaxCurrent"),
			UCk_EntityScript_IntegerGym_MinMaxCurrent,
			FInstancedStruct::Make(SpawnParams)
		);
	}

	void Request_StartModifiersStation()
	{
		auto StationTransform = Get_StationTransform("Gym.Attribute.IntegerModifiers");
		auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Attribute.IntegerModifiers"),
			UCk_EntityScript_IntegerGym_Modifiers,
			FInstancedStruct::Make(SpawnParams)
		);
	}

	void Request_StartClampingStation()
	{
		auto StationTransform = Get_StationTransform("Gym.Attribute.IntegerClamping");
		auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Attribute.IntegerClamping"),
			UCk_EntityScript_IntegerGym_Clamping,
			FInstancedStruct::Make(SpawnParams)
		);
	}

	//------------------------------------------------------------------------
	// BASIC STATION COMMANDS
	//------------------------------------------------------------------------

	UFUNCTION(Exec, DisplayName="Integer Gym - Set Health")
	void Ck_GymInteger_SetHealth(int32 InValue)
	{
		auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_Basic");
		for (auto Entity : Entities)
		{
			utils_messaging::Broadcast(Entity, FCk_Message_IntegerGym_SetHealth(InValue));
		}
	}

	UFUNCTION(Exec, DisplayName="Integer Gym - Set Armor")
	void Ck_GymInteger_SetArmor(int32 InValue)
	{
		auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_Basic");
		for (auto Entity : Entities)
		{
			utils_messaging::Broadcast(Entity, FCk_Message_IntegerGym_SetArmor(InValue));
		}
	}

	UFUNCTION(Exec, DisplayName="Integer Gym - Set Experience")
	void Ck_GymInteger_SetExperience(int32 InValue)
	{
		auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_Basic");
		for (auto Entity : Entities)
		{
			utils_messaging::Broadcast(Entity, FCk_Message_IntegerGym_SetExperience(InValue));
		}
	}

	UFUNCTION(Exec, DisplayName="Integer Gym - Auto")
	void Ck_GymInteger_Auto(int32 InEnabled = 1)
	{
		auto AllTags = TArray<FName>();
		AllTags.Add(n"TAG_IntegerGym_Basic");
		AllTags.Add(n"TAG_IntegerGym_MinMaxCurrent");
		AllTags.Add(n"TAG_IntegerGym_Modifiers");
		AllTags.Add(n"TAG_IntegerGym_Clamping");

		for (auto Tag : AllTags)
		{
			auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), Tag);
			for (auto Entity : Entities)
			{
				utils_messaging::Broadcast(Entity, FCk_Message_Gym_AutoSet(InEnabled != 0));
			}
		}
	}

	UFUNCTION(Exec, DisplayName="Integer Gym - Auto Basic")
	void Ck_GymInteger_AutoBasic()
	{
		auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_Basic");
		for (auto Entity : Entities) { utils_messaging::Broadcast(Entity, FCk_Message_Gym_AutoSet(true)); }
	}

	UFUNCTION(Exec, DisplayName="Integer Gym - Auto MinMaxCurrent")
	void Ck_GymInteger_AutoMinMaxCurrent()
	{
		auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_MinMaxCurrent");
		for (auto Entity : Entities) { utils_messaging::Broadcast(Entity, FCk_Message_Gym_AutoSet(true)); }
	}

	UFUNCTION(Exec, DisplayName="Integer Gym - Auto Modifiers")
	void Ck_GymInteger_AutoModifiers()
	{
		auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_Modifiers");
		for (auto Entity : Entities) { utils_messaging::Broadcast(Entity, FCk_Message_Gym_AutoSet(true)); }
	}

	UFUNCTION(Exec, DisplayName="Integer Gym - Auto Clamping")
	void Ck_GymInteger_AutoClamping()
	{
		auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_Clamping");
		for (auto Entity : Entities) { utils_messaging::Broadcast(Entity, FCk_Message_Gym_AutoSet(true)); }
	}

	//------------------------------------------------------------------------
	// MINMAXCURRENT STATION COMMANDS
	//------------------------------------------------------------------------

	UFUNCTION(Exec, DisplayName="Integer Gym - Set Min")
	void Ck_GymInteger_SetMin(int32 InValue = 20)
	{
		for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_MinMaxCurrent"))
		{ utils_messaging::Broadcast(E, FCk_Message_IntegerGym_SetValue(InValue, ECk_MinMaxCurrent::Min)); }
	}

	UFUNCTION(Exec, DisplayName="Integer Gym - Set Max")
	void Ck_GymInteger_SetMax(int32 InValue = 80)
	{
		for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_MinMaxCurrent"))
		{ utils_messaging::Broadcast(E, FCk_Message_IntegerGym_SetValue(InValue, ECk_MinMaxCurrent::Max)); }
	}

	UFUNCTION(Exec, DisplayName="Integer Gym - Set Current")
	void Ck_GymInteger_SetCurrent(int32 InValue = 50)
	{
		for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_MinMaxCurrent"))
		{ utils_messaging::Broadcast(E, FCk_Message_IntegerGym_SetValue(InValue, ECk_MinMaxCurrent::Current)); }
	}

	//------------------------------------------------------------------------
	// CLAMPING STATION COMMANDS — SetResource
	//------------------------------------------------------------------------

	UFUNCTION(Exec, DisplayName="Integer Gym - Set Resource")
	void Ck_GymInteger_SetResource(int32 InValue = 50)
	{
		for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_Clamping"))
		{ utils_messaging::Broadcast(E, FCk_Message_IntegerGym_SetResource(InValue)); }
	}

	//------------------------------------------------------------------------
	// MODIFIER STATION COMMANDS
	//------------------------------------------------------------------------

	UFUNCTION(Exec, DisplayName="Integer Gym - Add Weapon Bonus")
	void Ck_GymInteger_AddWeaponBonus(int32 InDelta)
	{
		auto ModifierTag = utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon");
		auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_Modifiers");
		for (auto Entity : Entities)
		{
			utils_messaging::Broadcast(Entity, FCk_Message_IntegerGym_AddModifier(ModifierTag, InDelta, ECk_MinMaxCurrent::Current));
		}
	}

	UFUNCTION(Exec, DisplayName="Integer Gym - Add Buff Bonus")
	void Ck_GymInteger_AddBuffBonus(int32 InDelta)
	{
		auto ModifierTag = utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Buff");
		auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_Modifiers");
		for (auto Entity : Entities)
		{
			utils_messaging::Broadcast(Entity, FCk_Message_IntegerGym_AddModifier(ModifierTag, InDelta, ECk_MinMaxCurrent::Current));
		}
	}

	UFUNCTION(Exec, DisplayName="Integer Gym - Remove Weapon Bonus")
	void Ck_GymInteger_RemoveWeaponBonus()
	{
		auto ModifierTag = utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon");
		auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_Modifiers");
		for (auto Entity : Entities)
		{
			utils_messaging::Broadcast(Entity, FCk_Message_IntegerGym_RemoveModifier(ModifierTag, ECk_MinMaxCurrent::Current));
		}
	}

	UFUNCTION(Exec, DisplayName="Integer Gym - Remove Buff Bonus")
	void Ck_GymInteger_RemoveBuffBonus()
	{
		auto ModifierTag = utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Buff");
		auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_Modifiers");
		for (auto Entity : Entities)
		{
			utils_messaging::Broadcast(Entity, FCk_Message_IntegerGym_RemoveModifier(ModifierTag, ECk_MinMaxCurrent::Current));
		}
	}

	UFUNCTION(Exec, DisplayName="Integer Gym - Clear All Modifiers")
	void Ck_GymInteger_ClearAllModifiers()
	{
		auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_Modifiers");
		for (auto Entity : Entities)
		{
			utils_messaging::Broadcast(Entity, FCk_Message_IntegerGym_ClearModifiers());
		}
	}

	//------------------------------------------------------------------------
	// CLAMPING STATION COMMANDS
	//------------------------------------------------------------------------

	UFUNCTION(Exec, DisplayName="Integer Gym - Test Boundaries")
	void Ck_GymInteger_TestBoundaries()
	{
		auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_Clamping");
		for (auto Entity : Entities)
		{
			utils_messaging::Broadcast(Entity, FCk_Message_AttributeGym_TestBoundaries());
		}
	}

	UFUNCTION(Exec, DisplayName="Integer Gym - Reset Clamping")
	void Ck_GymInteger_ResetClamping()
	{
		auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_Clamping");
		for (auto Entity : Entities)
		{
			utils_messaging::Broadcast(Entity, FCk_Message_AttributeGym_ResetAttributes());
		}
	}

	//------------------------------------------------------------------------
	// GLOBAL COMMANDS
	//------------------------------------------------------------------------

	UFUNCTION(Exec, DisplayName="Integer Gym - Reset All Stations")
	void Ck_GymInteger_ResetAll()
	{
		auto AllTags = TArray<FName>();
		AllTags.Add(n"TAG_IntegerGym_Basic");
		AllTags.Add(n"TAG_IntegerGym_MinMaxCurrent");
		AllTags.Add(n"TAG_IntegerGym_Modifiers");
		AllTags.Add(n"TAG_IntegerGym_Clamping");

		for (auto Tag : AllTags)
		{
			auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), Tag);
			for (auto Entity : Entities)
			{
				utils_messaging::Broadcast(Entity, FCk_Message_AttributeGym_ResetAttributes());
			}
		}
	}
}

//============================================================================
// GAME MODE
//============================================================================

class ACk_IntegerAttributeGym_GameMode : ACkTests_Gym_Base_GameMode
{
	default PlayerControllerClass = ACk_IntegerAttributeGym_PlayerController;
	default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
