// Language=angelscript

//============================================================================
// TWO-PLAYER NET GYM — SHARED MESSAGES & CONSTANTS
//============================================================================
// Console commands on the PlayerController route to the pawn, which broadcasts
// one of these messages to its (server- or owning-client-side) entity-script.
//============================================================================

namespace CkNetGym
{
    // Reuse the already-registered FloatAttribute.Health tag (see Config/DefaultGameplayTags.ini).
    const FName HealthTagName = n"FloatAttribute.Health";

    const float StartingHealth = 100.0f;
    const float MinHealth      = 0.0f;
    const float MaxHealth      = 100.0f;
    const float DefaultDamage  = 10.0f;
}

// Server-auth attribute path: broadcast on the SERVER inside the pawn's Server RPC.
USTRUCT()
struct FCk_Message_NetGym_Damage
{
    UPROPERTY()
    float Amount;

    FCk_Message_NetGym_Damage(float InAmount = 10.0f)
    {
        Amount = InAmount;
    }
}

// Owning-client SM path: broadcast LOCALLY on the owning client (no meaningful payload).
// No explicit constructor — a default-arg ctor would be ambiguous with the implicit
// default ctor when this is constructed as `FCk_Message_NetGym_AdvanceState()`.
USTRUCT()
struct FCk_Message_NetGym_AdvanceState
{
    UPROPERTY()
    int32 Unused;
}
