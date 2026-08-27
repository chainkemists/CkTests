//============================================================================
// REPLICATION GYM - SHARED MESSAGES & CONSTANTS
//============================================================================
// Reproduces the "No container fragment entry found for type
// [Ck_RepData_IntegerAttributes] on Entity" ensure seen when a replicated
// actor (or a replicated pawn) spawns a UCk_EntityScript_WithActor_UE with
// ck::TransientEntity() as the lifetime owner and that script adds replicated
// Integer Attributes in its construct handler.
//============================================================================

USTRUCT()
struct FCk_Message_ReplicationGym_SetAttribute
{
    UPROPERTY()
    int32 Value;

    FCk_Message_ReplicationGym_SetAttribute(int32 InValue = 0)
    {
        Value = InValue;
    }
}
