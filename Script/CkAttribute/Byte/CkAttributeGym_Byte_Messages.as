//============================================================================
// MESSAGE STRUCTURES FOR BYTE ATTRIBUTE GYM
//============================================================================
// Note: FCk_Message_AttributeGym_ResetAttributes and
//       FCk_Message_AttributeGym_TestBoundaries are shared across all
//       attribute gyms and live in CkAttributeGym_Common.as.

USTRUCT()
struct FCk_Message_ByteGym_AddModifier
{
	FCk_Message_ByteGym_AddModifier() {}
}

USTRUCT()
struct FCk_Message_ByteGym_ClearModifiers
{
	FCk_Message_ByteGym_ClearModifiers() {}
}

USTRUCT()
struct FCk_Message_ByteGym_SetValue
{
	UPROPERTY()
	uint8 Value;

	UPROPERTY()
	ECk_MinMaxCurrent Component;

	FCk_Message_ByteGym_SetValue(uint8 InValue = 100, ECk_MinMaxCurrent InComponent = ECk_MinMaxCurrent::Current)
	{
		Value = InValue;
		Component = InComponent;
	}
}

USTRUCT()
struct FCk_Message_ByteGym_AddBatch
{
	FCk_Message_ByteGym_AddBatch() {}
}

USTRUCT()
struct FCk_Message_ByteGym_ClearBatch
{
	FCk_Message_ByteGym_ClearBatch() {}
}
