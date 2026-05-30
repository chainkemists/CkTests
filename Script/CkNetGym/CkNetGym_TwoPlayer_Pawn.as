// Language=angelscript

//============================================================================
// TWO-PLAYER NET GYM — PAWN
//============================================================================
// Possessable, replicated DefaultPawn. Inherits ADefaultPawn directly (mirroring
// ACk_Gym_Base_Pawn) rather than the gym base pawn, so that exactly ONE
// entity-script is bridged to the pawn. A single bridged entity makes the
// reverse lookup utils_owning_actor::TryGet_ActorEntityHandle(this) unambiguous
// on BOTH worlds — which both console-command paths rely on.
//
// On authority it spawns the gym's replicated entity-script (which adds Health
// + SM and replicates to clients via the WithActor lifecycle). The WithActor
// Construct runs on the client too, so the reverse-lookup component exists on
// every world.
//
// Console commands on the PlayerController call into this pawn:
//   - Server_ApplyDamage  : reliable Server RPC -> broadcast Damage on the server
//                           (server-authoritative attribute path).
//   - Request_AdvanceState: local -> broadcast AdvanceState on the owning client
//                           (owning-client-authoritative SM path).
//============================================================================

class ACk_NetGym_TwoPlayer_Pawn : ADefaultPawn
{
    default Replicates = true;

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        if (!HasAuthority())
        { return; }

        auto SpawnParams = FCk_EntityScript_WithActor_SpawnParams();
        SpawnParams._OwningActor = this;
        utils_entity_script::Request_SpawnEntity(
            ck::TransientEntity(),
            UCk_NetGym_TwoPlayer_EntityScript,
            SpawnParams);
    }

    // Server-authoritative attribute path. Runs on the server (RPC). Finds this
    // pawn's bridged entity and broadcasts the Damage message; the server-side
    // entity-script applies Request_Override and the value replicates to clients.
    UFUNCTION(Server)
    void Server_ApplyDamage(float InAmount)
    {
        auto Entity = utils_owning_actor::TryGet_ActorEntityHandle(this);
        if (ck::Is_NOT_Valid(Entity))
        { return; }

        utils_messaging::Broadcast(Entity, FCk_Message_NetGym_Damage(InAmount));
    }

    // Owning-client SM path. Runs locally on the owning client. Broadcasts the
    // AdvanceState message to this pawn's (client-world) bridged entity; the
    // entity-script requests the transition (owning-client authority commits
    // locally and relays to the server).
    void Request_AdvanceState()
    {
        auto Entity = utils_owning_actor::TryGet_ActorEntityHandle(this);
        if (ck::Is_NOT_Valid(Entity))
        { return; }

        utils_messaging::Broadcast(Entity, FCk_Message_NetGym_AdvanceState());
    }
}
