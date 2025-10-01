//============================================================================
// BYTE ATTRIBUTE GYM - PLAYER CONTROLLER & GAME MODE
//============================================================================

class ACk_ByteAttributeGym_PlayerController : ACk_Gym_Base_PlayerController
{
    void Request_StartGym() override
    {
        Request_StartByteClamping();
        Request_StartByteModifiers();
        Request_StartByteMinMaxCurrent();
        Request_StartByteMultiple();
        Request_StartByteValues();
        Request_StartByteSignals();
    }

    void Request_StartByteClamping()
    {
        auto StationTransform = Get_StationTransform("Gym.Attribute.ByteClamping");
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.ByteClamping"),
            UCk_EntityScript_AttributeGym_ByteClamping,
            FInstancedStruct::Make(SpawnParams)
        );
	}

    void Request_StartByteModifiers()
    {
        auto StationTransform = Get_StationTransform("Gym.Attribute.ByteModifiers");
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.ByteModifiers"),
            UCk_EntityScript_AttributeGym_ByteModifiers,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    void Request_StartByteMinMaxCurrent()
    {
        auto StationTransform = Get_StationTransform("Gym.Attribute.ByteMinMaxCurrent");
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.ByteMinMaxCurrent"),
            UCk_EntityScript_AttributeGym_ByteMinMaxCurrent,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    void Request_StartByteMultiple()
    {
        auto StationTransform = Get_StationTransform("Gym.Attribute.ByteMultiple");
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.ByteMultiple"),
            UCk_EntityScript_AttributeGym_ByteMultiple,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    void Request_StartByteValues()
    {
        auto StationTransform = Get_StationTransform("Gym.Attribute.ByteValues");
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.ByteValues"),
            UCk_EntityScript_AttributeGym_ByteValues,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    void Request_StartByteSignals()
    {
        auto StationTransform = Get_StationTransform("Gym.Attribute.ByteSignals");
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.ByteSignals"),
            UCk_EntityScript_AttributeGym_ByteSignals,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    // Clamping station commands
    UFUNCTION(Exec, DisplayName="Byte Gym - Test Boundaries")
    void Ck_GymByte_TestBoundaries()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::SelfEntity(this), n"TAG_AttributeGym_ByteClamping");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_AttributeGym_TestBoundaries());
        }
    }

    // Global commands
    UFUNCTION(Exec, DisplayName="Byte Gym - Reset All")
    void Ck_GymByte_ResetAll()
    {
        auto ClampingEntities = utils_entity_tag::ForEach_Entity(ck::SelfEntity(this), n"TAG_AttributeGym_ByteClamping");
        for (auto Entity : ClampingEntities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_AttributeGym_ResetAttributes());
        }

        auto ModifierEntities = utils_entity_tag::ForEach_Entity(ck::SelfEntity(this), n"TAG_AttributeGym_ByteModifiers");
        for (auto Entity : ModifierEntities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_AttributeGym_ResetAttributes());
        }
    }
}

//============================================================================
// GAME MODE
//============================================================================

class ACk_ByteAttributeGym_GameMode : ACk_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_ByteAttributeGym_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}