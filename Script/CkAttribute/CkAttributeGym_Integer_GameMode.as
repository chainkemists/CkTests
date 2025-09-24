// Language=angelscript

//============================================================================
// INTEGER ATTRIBUTE GYM - GAME MODE
//============================================================================

class ACk_IntegerAttributeGym_GameMode : ACk_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_IntegerAttributeGym_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;

    FString Get_GymName() override
    {
        return "Integer Attribute Testing Gym";
    }

    FString Get_GymDescription() override
    {
        return "Comprehensive testing of Integer Attributes: basic operations, min/max/current components, modifiers, and clamping signals";
    }

    TArray<FString> Get_RequiredStationTags() override
    {
        auto RequiredTags = TArray<FString>();
        RequiredTags.Add("Gym.Attribute.IntegerBasic");
        RequiredTags.Add("Gym.Attribute.IntegerMinMaxCurrent");
        RequiredTags.Add("Gym.Attribute.IntegerModifiers");
        RequiredTags.Add("Gym.Attribute.IntegerClamping");
        return RequiredTags;
    }
}