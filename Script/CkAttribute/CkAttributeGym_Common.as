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

USTRUCT()
struct FCk_Message_AttributeGym_SetHealth
{
    UPROPERTY()
    float32 Value;

    FCk_Message_AttributeGym_SetHealth(float32 InValue = 100.0f)
    {
        Value = InValue;
    }
};

//--------------------------------------------------------------------------------------------------------------------------

USTRUCT()
struct FCk_Message_AttributeGym_SetArmor
{
    UPROPERTY()
    uint8 Value;

    FCk_Message_AttributeGym_SetArmor(uint8 InValue = 150)
    {
        Value = InValue;
    }
};

//--------------------------------------------------------------------------------------------------------------------------

USTRUCT()
struct FCk_Message_AttributeGym_SetVelocity
{
    UPROPERTY()
    FVector Value;

    FCk_Message_AttributeGym_SetVelocity(FVector InValue = FVector(100.0f, 50.0f, 0.0f))
    {
        Value = InValue;
    }
};

//--------------------------------------------------------------------------------------------------------------------------

USTRUCT()
struct FCk_Message_AttributeGym_AutoSet
{
    UPROPERTY()
    bool Enabled;

    FCk_Message_AttributeGym_AutoSet(bool InEnabled = true)
    {
        Enabled = InEnabled;
    }
};

//--------------------------------------------------------------------------------------------------------------------------

USTRUCT()
struct FCk_Message_FloatGym_ToggleRefill
{
};

//--------------------------------------------------------------------------------------------------------------------------