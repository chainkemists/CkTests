// Language=angelscript

//============================================================================
// MESSAGE STRUCTURES FOR INTEGER ATTRIBUTE GYM
//============================================================================

USTRUCT()
struct FCk_Message_IntegerGym_SetHealth
{
    UPROPERTY()
    int32 Value;

    FCk_Message_IntegerGym_SetHealth(int32 InValue = 100)
    {
        Value = InValue;
    }
}

USTRUCT()
struct FCk_Message_IntegerGym_SetArmor
{
    UPROPERTY()
    int32 Value;

    FCk_Message_IntegerGym_SetArmor(int32 InValue = 50)
    {
        Value = InValue;
    }
}

USTRUCT()
struct FCk_Message_IntegerGym_SetExperience
{
    UPROPERTY()
    int32 Value;

    FCk_Message_IntegerGym_SetExperience(int32 InValue = 0)
    {
        Value = InValue;
    }
}

USTRUCT()
struct FCk_Message_IntegerGym_AddModifier
{
    UPROPERTY()
    FGameplayTag ModifierName;
    
    UPROPERTY()
    int32 Delta;
    
    UPROPERTY()
    ECk_MinMaxCurrent Component;

    FCk_Message_IntegerGym_AddModifier(FGameplayTag InName = FGameplayTag(), int32 InDelta = 0, ECk_MinMaxCurrent InComponent = ECk_MinMaxCurrent::Current)
    {
        ModifierName = InName;
        Delta = InDelta;
        Component = InComponent;
    }
}

USTRUCT()
struct FCk_Message_IntegerGym_RemoveModifier
{
    UPROPERTY()
    FGameplayTag ModifierName;
    
    UPROPERTY()
    ECk_MinMaxCurrent Component;

    FCk_Message_IntegerGym_RemoveModifier(FGameplayTag InName = FGameplayTag(), ECk_MinMaxCurrent InComponent = ECk_MinMaxCurrent::Current)
    {
        ModifierName = InName;
        Component = InComponent;
    }
}

USTRUCT()
struct FCk_Message_IntegerGym_ResetAttributes
{
    FCk_Message_IntegerGym_ResetAttributes() {}
}

USTRUCT()
struct FCk_Message_IntegerGym_TestBoundaries
{
    FCk_Message_IntegerGym_TestBoundaries() {}
}

USTRUCT()
struct FCk_Message_IntegerGym_ClearModifiers
{
    FCk_Message_IntegerGym_ClearModifiers() {}
}
