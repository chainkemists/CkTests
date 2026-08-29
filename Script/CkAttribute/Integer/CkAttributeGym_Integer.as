//============================================================================
// INTEGER ATTRIBUTE GYM - PLAYER CONTROLLER & GAME MODE
//============================================================================

class ACk_IntegerAttributeGym_PlayerController : ACk_Gym_Base_PlayerController
{
	// Preset-ring positions for the panel rows; each press applies the NEXT value, chosen to
	// exercise the auto-clamping (over-max, below-min) each station demonstrates.
	private int32 _HealthPresetIndex = -1;
	private int32 _ArmorPresetIndex = -1;
	private int32 _ExperiencePresetIndex = -1;
	private int32 _MinPresetIndex = -1;
	private int32 _MaxPresetIndex = -1;
	private int32 _CurrentPresetIndex = -1;
	private int32 _ResourcePresetIndex = -1;
	private int32 _WeaponBonusIndex = -1;
	private int32 _BuffBonusIndex = -1;

	// Mirrors of each station's auto-cycle state - it lives in the entity scripts behind a
	// broadcast message with no readback, so the panel mirrors it here (all start true: every
	// station auto-runs).
	private bool _AutoAllEnabled = true;
	private bool _AutoBasic = true;
	private bool _AutoMinMaxCurrent = true;
	private bool _AutoModifiers = true;
	private bool _AutoClamping = true;

	TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
	{
		auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

		// Basic Integer Attributes Station
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.Attribute.IntegerBasic");
			Station.Title = FText::FromString("INTEGER BASIC ATTRIBUTES");
			Station.AutoSize = true;
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Tests integer attributes: Health (0-100), Armor (0-50), Experience (0+)."));
			Description.Add(FText::FromString("Auto-cycles through 6 phases every 2s."));
			Description.Add(FText::FromString("Panel: [1] auto - [5] Health - [6] Armor - [7] Experience"));
			Station.Description = Description;
			Stations.Add(Station);
		}

		// Min/Max/Current Station
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.Attribute.IntegerMinMaxCurrent");
			Station.Title = FText::FromString("INTEGER MIN/MAX/CURRENT");
			Station.AutoSize = true;
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Displays all three attribute components independently."));
			Description.Add(FText::FromString("Shows how Min, Max, and Current values interact and update."));
			Description.Add(FText::FromString("Panel: [2] auto - [8] Min - [9] Max - [0] Current"));
			Station.Description = Description;
			Stations.Add(Station);
		}

		// Modifiers Station
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.Attribute.IntegerModifiers");
			Station.Title = FText::FromString("INTEGER MODIFIERS");
			Station.AutoSize = true;
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Tests attribute modifier system with add/remove operations."));
			Description.Add(FText::FromString("Demonstrates weapon and buff modifier stacking."));
			Description.Add(FText::FromString("Panel: [3] auto - [I]/[O] add bonus - [J]/[K] remove - [M] clear all"));
			Station.Description = Description;
			Stations.Add(Station);
		}

		// Clamping & Signals Station
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.Attribute.IntegerClamping");
			Station.Title = FText::FromString("INTEGER CLAMPING & SIGNALS");
			Station.AutoSize = true;
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Tests automatic value clamping and signal callbacks."));
			Description.Add(FText::FromString("Monitors OnMinClamped, OnMaxClamped events."));
			Description.Add(FText::FromString("Panel: [4] auto - [U] Resource preset - [B] test boundaries - [R] reset"));
			Station.Description = Description;
			Stations.Add(Station);
		}

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
		auto StationTransform = Get_StationAnchorTransform("Gym.Attribute.IntegerBasic", ECk_GymStation_Anchor::PanelCenter);
		auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Attribute.IntegerBasic"),
			UCk_EntityScript_IntegerGym_Basic,
			FInstancedStruct::Make(SpawnParams)
		);
	}

	void Request_StartMinMaxCurrentStation()
	{
		auto StationTransform = Get_StationAnchorTransform("Gym.Attribute.IntegerMinMaxCurrent", ECk_GymStation_Anchor::PanelCenter);
		auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Attribute.IntegerMinMaxCurrent"),
			UCk_EntityScript_IntegerGym_MinMaxCurrent,
			FInstancedStruct::Make(SpawnParams)
		);
	}

	void Request_StartModifiersStation()
	{
		auto StationTransform = Get_StationAnchorTransform("Gym.Attribute.IntegerModifiers", ECk_GymStation_Anchor::PanelCenter);
		auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Attribute.IntegerModifiers"),
			UCk_EntityScript_IntegerGym_Modifiers,
			FInstancedStruct::Make(SpawnParams)
		);
	}

	void Request_StartClampingStation()
	{
		auto StationTransform = Get_StationAnchorTransform("Gym.Attribute.IntegerClamping", ECk_GymStation_Anchor::PanelCenter);
		auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Attribute.IntegerClamping"),
			UCk_EntityScript_IntegerGym_Clamping,
			FInstancedStruct::Make(SpawnParams)
		);
	}

	//------------------------------------------------------------------------
	// Control panel
	//------------------------------------------------------------------------

	TArray<FCkGym_ControlRow> Get_ControlRows() override
	{
		auto Rows = TArray<FCkGym_ControlRow>();
		Rows.Add(CkGym_Control::Header("INTEGER ATTRIBUTE GYM"));
		Rows.Add(CkGym_Control::Toggle(EKeys::T, "T", "Auto-cycle all stations", _AutoAllEnabled));

		Rows.Add(CkGym_Control::Header("AUTO PER STATION"));
		Rows.Add(CkGym_Control::Numbered(0, "Basic", _AutoBasic));
		Rows.Add(CkGym_Control::Numbered(1, "Min/Max/Current", _AutoMinMaxCurrent));
		Rows.Add(CkGym_Control::Numbered(2, "Modifiers", _AutoModifiers));
		Rows.Add(CkGym_Control::Numbered(3, "Clamping", _AutoClamping));

		Rows.Add(CkGym_Control::Header("BASIC STATION"));
		Rows.Add(CkGym_Control::Cycle(EKeys::Five,  "5", "Health preset",     DoGet_PresetLabel(_HealthPresetIndex,     "100 / 50 / 10 / -10 / 150")));
		Rows.Add(CkGym_Control::Cycle(EKeys::Six,   "6", "Armor preset",      DoGet_PresetLabel(_ArmorPresetIndex,      "50 / 25 / 5 / -5 / 80")));
		Rows.Add(CkGym_Control::Cycle(EKeys::Seven, "7", "Experience preset", DoGet_PresetLabel(_ExperiencePresetIndex, "0 / 500 / 2000 / -100")));

		Rows.Add(CkGym_Control::Header("MIN/MAX/CURRENT STATION"));
		Rows.Add(CkGym_Control::Cycle(EKeys::Eight, "8", "Min preset",     DoGet_PresetLabel(_MinPresetIndex,     "10 / 20 / 60 / 120")));
		Rows.Add(CkGym_Control::Cycle(EKeys::Nine,  "9", "Max preset",     DoGet_PresetLabel(_MaxPresetIndex,     "100 / 80 / 40 / 5")));
		Rows.Add(CkGym_Control::Cycle(EKeys::Zero,  "0", "Current preset", DoGet_PresetLabel(_CurrentPresetIndex, "50 / 75 / 150 / -20")));

		Rows.Add(CkGym_Control::Header("MODIFIERS STATION"));
		Rows.Add(CkGym_Control::Cycle(EKeys::I, "I", "Weapon bonus", DoGet_PresetLabel(_WeaponBonusIndex, "+25 / +50 / -25 / -200")));
		Rows.Add(CkGym_Control::Cycle(EKeys::O, "O", "Buff bonus",   DoGet_PresetLabel(_BuffBonusIndex,   "+10 / +40 / -10 / -150")));
		Rows.Add(CkGym_Control::Action(EKeys::J, "J", "Remove weapon bonus"));
		Rows.Add(CkGym_Control::Action(EKeys::K, "K", "Remove buff bonus"));
		Rows.Add(CkGym_Control::Action(EKeys::M, "M", "Clear all modifiers"));

		Rows.Add(CkGym_Control::Header("CLAMPING STATION"));
		Rows.Add(CkGym_Control::Cycle(EKeys::U, "U", "Resource preset", DoGet_PresetLabel(_ResourcePresetIndex, "50 / 0 / 100 / 150 / -50")));
		Rows.Add(CkGym_Control::Action(EKeys::B, "B", "Test boundaries"));
		Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Reset clamping station"));

		Rows.Add(CkGym_Control::Header("GLOBAL"));
		Rows.Add(CkGym_Control::Action(EKeys::N, "N", "Reset all stations"));
		return Rows;
	}

	void Request_ControlActivated(int32 InRowIndex) override
	{
		if (InRowIndex == 1)
		{
			_AutoAllEnabled = !_AutoAllEnabled;
			_AutoBasic = _AutoAllEnabled;
			_AutoMinMaxCurrent = _AutoAllEnabled;
			_AutoModifiers = _AutoAllEnabled;
			_AutoClamping = _AutoAllEnabled;

			for (auto Tag : Get_AllStationTags())
			{
				DoBroadcastToStation(Tag, FCk_Message_Gym_AutoSet(_AutoAllEnabled));
			}
		}
		else if (InRowIndex == 3)
		{
			_AutoBasic = !_AutoBasic;
			DoBroadcastToStation(n"TAG_IntegerGym_Basic", FCk_Message_Gym_AutoSet(_AutoBasic));
		}
		else if (InRowIndex == 4)
		{
			_AutoMinMaxCurrent = !_AutoMinMaxCurrent;
			DoBroadcastToStation(n"TAG_IntegerGym_MinMaxCurrent", FCk_Message_Gym_AutoSet(_AutoMinMaxCurrent));
		}
		else if (InRowIndex == 5)
		{
			_AutoModifiers = !_AutoModifiers;
			DoBroadcastToStation(n"TAG_IntegerGym_Modifiers", FCk_Message_Gym_AutoSet(_AutoModifiers));
		}
		else if (InRowIndex == 6)
		{
			_AutoClamping = !_AutoClamping;
			DoBroadcastToStation(n"TAG_IntegerGym_Clamping", FCk_Message_Gym_AutoSet(_AutoClamping));
		}
		else if (InRowIndex == 8)
		{
			_HealthPresetIndex = (_HealthPresetIndex + 1) % 5;
			auto Values = TArray<int32>();
			Values.Add(100); Values.Add(50); Values.Add(10); Values.Add(-10); Values.Add(150);
			DoBroadcastToStation(n"TAG_IntegerGym_Basic", FCk_Message_IntegerGym_SetHealth(Values[_HealthPresetIndex]));
		}
		else if (InRowIndex == 9)
		{
			_ArmorPresetIndex = (_ArmorPresetIndex + 1) % 5;
			auto Values = TArray<int32>();
			Values.Add(50); Values.Add(25); Values.Add(5); Values.Add(-5); Values.Add(80);
			DoBroadcastToStation(n"TAG_IntegerGym_Basic", FCk_Message_IntegerGym_SetArmor(Values[_ArmorPresetIndex]));
		}
		else if (InRowIndex == 10)
		{
			_ExperiencePresetIndex = (_ExperiencePresetIndex + 1) % 4;
			auto Values = TArray<int32>();
			Values.Add(0); Values.Add(500); Values.Add(2000); Values.Add(-100);
			DoBroadcastToStation(n"TAG_IntegerGym_Basic", FCk_Message_IntegerGym_SetExperience(Values[_ExperiencePresetIndex]));
		}
		else if (InRowIndex == 12)
		{
			_MinPresetIndex = (_MinPresetIndex + 1) % 4;
			auto Values = TArray<int32>();
			Values.Add(10); Values.Add(20); Values.Add(60); Values.Add(120);
			DoBroadcastToStation(n"TAG_IntegerGym_MinMaxCurrent", FCk_Message_IntegerGym_SetValue(Values[_MinPresetIndex], ECk_MinMaxCurrent::Min));
		}
		else if (InRowIndex == 13)
		{
			_MaxPresetIndex = (_MaxPresetIndex + 1) % 4;
			auto Values = TArray<int32>();
			Values.Add(100); Values.Add(80); Values.Add(40); Values.Add(5);
			DoBroadcastToStation(n"TAG_IntegerGym_MinMaxCurrent", FCk_Message_IntegerGym_SetValue(Values[_MaxPresetIndex], ECk_MinMaxCurrent::Max));
		}
		else if (InRowIndex == 14)
		{
			_CurrentPresetIndex = (_CurrentPresetIndex + 1) % 4;
			auto Values = TArray<int32>();
			Values.Add(50); Values.Add(75); Values.Add(150); Values.Add(-20);
			DoBroadcastToStation(n"TAG_IntegerGym_MinMaxCurrent", FCk_Message_IntegerGym_SetValue(Values[_CurrentPresetIndex], ECk_MinMaxCurrent::Current));
		}
		else if (InRowIndex == 16)
		{
			_WeaponBonusIndex = (_WeaponBonusIndex + 1) % 4;
			auto Values = TArray<int32>();
			Values.Add(25); Values.Add(50); Values.Add(-25); Values.Add(-200);
			auto ModifierTag = utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon");
			DoBroadcastToStation(n"TAG_IntegerGym_Modifiers", FCk_Message_IntegerGym_AddModifier(ModifierTag, Values[_WeaponBonusIndex], ECk_MinMaxCurrent::Current));
		}
		else if (InRowIndex == 17)
		{
			_BuffBonusIndex = (_BuffBonusIndex + 1) % 4;
			auto Values = TArray<int32>();
			Values.Add(10); Values.Add(40); Values.Add(-10); Values.Add(-150);
			auto ModifierTag = utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Buff");
			DoBroadcastToStation(n"TAG_IntegerGym_Modifiers", FCk_Message_IntegerGym_AddModifier(ModifierTag, Values[_BuffBonusIndex], ECk_MinMaxCurrent::Current));
		}
		else if (InRowIndex == 18)
		{
			auto ModifierTag = utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon");
			DoBroadcastToStation(n"TAG_IntegerGym_Modifiers", FCk_Message_IntegerGym_RemoveModifier(ModifierTag, ECk_MinMaxCurrent::Current));
		}
		else if (InRowIndex == 19)
		{
			auto ModifierTag = utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Buff");
			DoBroadcastToStation(n"TAG_IntegerGym_Modifiers", FCk_Message_IntegerGym_RemoveModifier(ModifierTag, ECk_MinMaxCurrent::Current));
		}
		else if (InRowIndex == 20)
		{
			DoBroadcastToStation(n"TAG_IntegerGym_Modifiers", FCk_Message_IntegerGym_ClearModifiers());
		}
		else if (InRowIndex == 22)
		{
			_ResourcePresetIndex = (_ResourcePresetIndex + 1) % 5;
			auto Values = TArray<int32>();
			Values.Add(50); Values.Add(0); Values.Add(100); Values.Add(150); Values.Add(-50);
			DoBroadcastToStation(n"TAG_IntegerGym_Clamping", FCk_Message_IntegerGym_SetResource(Values[_ResourcePresetIndex]));
		}
		else if (InRowIndex == 23)
		{
			DoBroadcastToStation(n"TAG_IntegerGym_Clamping", FCk_Message_AttributeGym_TestBoundaries());
		}
		else if (InRowIndex == 24)
		{
			DoBroadcastToStation(n"TAG_IntegerGym_Clamping", FCk_Message_AttributeGym_ResetAttributes());
		}
		else if (InRowIndex == 26)
		{
			for (auto Tag : Get_AllStationTags())
			{
				DoBroadcastToStation(Tag, FCk_Message_AttributeGym_ResetAttributes());
			}

			_HealthPresetIndex = -1;
			_ArmorPresetIndex = -1;
			_ExperiencePresetIndex = -1;
			_MinPresetIndex = -1;
			_MaxPresetIndex = -1;
			_CurrentPresetIndex = -1;
			_ResourcePresetIndex = -1;
			_WeaponBonusIndex = -1;
			_BuffBonusIndex = -1;
		}
	}

	private FString DoGet_PresetLabel(int32 InIndex, FString InRing)
	{
		return InIndex < 0 ? f"({InRing})" : f"step {InIndex + 1}";
	}

	private TArray<FName> Get_AllStationTags()
	{
		auto StationTags = TArray<FName>();
		StationTags.Add(n"TAG_IntegerGym_Basic");
		StationTags.Add(n"TAG_IntegerGym_MinMaxCurrent");
		StationTags.Add(n"TAG_IntegerGym_Modifiers");
		StationTags.Add(n"TAG_IntegerGym_Clamping");
		return StationTags;
	}

	private void DoBroadcastToStation(FName InTag, FCk_Message_Gym_AutoSet InMessage)
	{
		for (auto Entity : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag))
		{
			utils_messaging::Broadcast(Entity, InMessage);
		}
	}

	private void DoBroadcastToStation(FName InTag, FCk_Message_IntegerGym_SetHealth InMessage)
	{
		for (auto Entity : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag))
		{
			utils_messaging::Broadcast(Entity, InMessage);
		}
	}

	private void DoBroadcastToStation(FName InTag, FCk_Message_IntegerGym_SetArmor InMessage)
	{
		for (auto Entity : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag))
		{
			utils_messaging::Broadcast(Entity, InMessage);
		}
	}

	private void DoBroadcastToStation(FName InTag, FCk_Message_IntegerGym_SetExperience InMessage)
	{
		for (auto Entity : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag))
		{
			utils_messaging::Broadcast(Entity, InMessage);
		}
	}

	private void DoBroadcastToStation(FName InTag, FCk_Message_IntegerGym_SetValue InMessage)
	{
		for (auto Entity : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag))
		{
			utils_messaging::Broadcast(Entity, InMessage);
		}
	}

	private void DoBroadcastToStation(FName InTag, FCk_Message_IntegerGym_SetResource InMessage)
	{
		for (auto Entity : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag))
		{
			utils_messaging::Broadcast(Entity, InMessage);
		}
	}

	private void DoBroadcastToStation(FName InTag, FCk_Message_IntegerGym_AddModifier InMessage)
	{
		for (auto Entity : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag))
		{
			utils_messaging::Broadcast(Entity, InMessage);
		}
	}

	private void DoBroadcastToStation(FName InTag, FCk_Message_IntegerGym_RemoveModifier InMessage)
	{
		for (auto Entity : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag))
		{
			utils_messaging::Broadcast(Entity, InMessage);
		}
	}

	private void DoBroadcastToStation(FName InTag, FCk_Message_IntegerGym_ClearModifiers InMessage)
	{
		for (auto Entity : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag))
		{
			utils_messaging::Broadcast(Entity, InMessage);
		}
	}

	private void DoBroadcastToStation(FName InTag, FCk_Message_AttributeGym_TestBoundaries InMessage)
	{
		for (auto Entity : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag))
		{
			utils_messaging::Broadcast(Entity, InMessage);
		}
	}

	private void DoBroadcastToStation(FName InTag, FCk_Message_AttributeGym_ResetAttributes InMessage)
	{
		for (auto Entity : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag))
		{
			utils_messaging::Broadcast(Entity, InMessage);
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
