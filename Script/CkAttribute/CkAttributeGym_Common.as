USTRUCT()
struct FCk_Message_AttributeGym_ResetAttributes
{
};

//--------------------------------------------------------------------------------------------------------------------------

USTRUCT()
struct FCk_Message_AttributeGym_UpdateAttributes
{
};

//--------------------------------------------------------------------------------------------------------------------------

USTRUCT()
struct FCk_Message_AttributeGym_TestBoundaries
{
};

//--------------------------------------------------------------------------------------------------------------------------

USTRUCT()
struct FCk_Message_AttributeGym_SetStamina
{
    UPROPERTY()
    uint8 Value;

    FCk_Message_AttributeGym_SetStamina(uint8 InValue)
    {
        Value = InValue;
    }
};

//--------------------------------------------------------------------------------------------------------------------------

USTRUCT()
struct FCk_Message_AttributeGym_SetMana
{
    UPROPERTY()
    float32 Value;

    FCk_Message_AttributeGym_SetMana(float32 InValue)
    {
        Value = InValue;
    }
};

//--------------------------------------------------------------------------------------------------------------------------
