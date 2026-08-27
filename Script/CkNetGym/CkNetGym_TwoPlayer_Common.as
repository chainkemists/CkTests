// Language=angelscript

//============================================================================
// TWO-PLAYER NET GYM - SHARED MESSAGES & CONSTANTS
//============================================================================
// The server-only cadence director drives these messages on a beat: Damage is
// broadcast on a pawn's entity server-side (server-authoritative attribute);
// AdvanceState is broadcast locally on the owning client (owning-client SM).
//============================================================================

namespace CkNetGym
{
    // Reuse the already-registered FloatAttribute.Health tag (see Config/DefaultGameplayTags.ini).
    const FName HealthTagName = n"FloatAttribute.Health";

    const float StartingHealth = 100.0f;
    const float MinHealth      = 0.0f;
    const float MaxHealth      = 100.0f;
    const float DefaultDamage  = 10.0f;

    // Auto-cadence: the server-only director ticks a Beat counter every BeatSeconds and schedules
    // interleaved actions by Beat % BeatPeriod. State changes are issued on each pawn's owning
    // client (owning-client authority); damage is applied on the server.
    const float BeatSeconds = 1.0f;   // heartbeat granularity
    const int   BeatPeriod  = 10;     // full interleave cycle (beats)

    // Slot-0 pawn = the host's own pawn (server-locally-controlled); slot-1 = the remote client's.
    // Phases are offset so a state change and a damage tick never land on the same beat.
    const int BeatPhase_State_Slot0  = 5;  // host pawn advances state
    const int BeatPhase_State_Slot1  = 0;  // client pawn advances state (5s after the host's)
    const int BeatPhase_Damage_Slot0 = 2;  // host pawn takes damage
    const int BeatPhase_Damage_Slot1 = 7;  // client pawn takes damage

    // The server-only director is found from anywhere via this EntityTag; pawns carry PlayerPawnTag.
    const FName DirectorTag   = n"TAG_NetGym_Director";
    const FName PlayerPawnTag = n"TAG_NetGym_PlayerPawn";
}

// Server-auth attribute path: broadcast on the SERVER by the director on a damage beat.
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
// No explicit constructor - a default-arg ctor would be ambiguous with the implicit
// default ctor when this is constructed as `FCk_Message_NetGym_AdvanceState()`.
USTRUCT()
struct FCk_Message_NetGym_AdvanceState
{
    UPROPERTY()
    int32 Unused;
}
