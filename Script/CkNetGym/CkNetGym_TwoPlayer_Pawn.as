// Language=angelscript

//============================================================================
// TWO-PLAYER NET GYM — PAWN
//============================================================================
// Possessable, replicated DefaultPawn. Inherits ADefaultPawn directly (mirroring
// ACk_Gym_Base_Pawn) rather than the gym base pawn, so that exactly ONE
// entity-script is bridged to the pawn. A single bridged entity makes the
// reverse lookup utils_owning_actor::TryGet_ActorEntityHandle(this) unambiguous
// on BOTH worlds.
//
// On authority it spawns the gym's replicated entity-script (which adds Health
// + SM and replicates to clients via the WithActor lifecycle). The WithActor
// Construct runs on the client too, so the reverse-lookup component exists on
// every world.
//
// The cadence is fully automatic (see the director). The director triggers state
// changes here via Client_AdvanceState (a Client RPC that runs on the owning
// client and issues the owning-client-authoritative transition). Damage is
// applied server-side by the director and needs no pawn RPC.
//============================================================================

class ACk_NetGym_TwoPlayer_Pawn : ADefaultPawn
{
    default Replicates = true;

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (!HasAuthority())
        { return; }

        auto SpawnParams = FCk_EntityScript_WithActor_SpawnParams();
        SpawnParams._OwningActor = this;
        utils_entity_script::Request_SpawnEntity(
            ck::TransientEntity(),
            UCk_NetGym_TwoPlayer_EntityScript,
            SpawnParams);
    }

    // Owning-client SM path. The server-only cadence director calls this Client RPC on the
    // pawn's owning client when it's this pawn's turn to advance. It runs on the owning client,
    // which broadcasts AdvanceState to its (client-world) bridged entity; the entity-script
    // requests the transition (owning-client authority commits locally and relays to the server).
    UFUNCTION(Client)
    void Client_AdvanceState()
    {
        Request_AdvanceState();
    }

    // Local broadcast of the AdvanceState message to this pawn's bridged entity (owning-client world).
    void Request_AdvanceState()
    {
        auto Entity = utils_owning_actor::TryGet_ActorEntityHandle(this);
        if (ck::Is_NOT_Valid(Entity))
        { return; }

        utils_messaging::Broadcast(Entity, FCk_Message_NetGym_AdvanceState());
    }
}
