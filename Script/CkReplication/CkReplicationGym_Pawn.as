//============================================================================
// REPLICATION GYM — PAWN (Scenario B driver)
//============================================================================
// Extends the gym base pawn. After the base pawn's own WithActor entity has
// been constructed, we attach a SECOND WithActor entity script using
// ck::TransientEntity() as the lifetime owner — mirroring the
// BB_PlayerCharacter shape where the ensure was hit after re-ordering.
//============================================================================

class ACk_ReplicationGym_Pawn : ACk_Gym_Base_Pawn
{
    void Request_OnPawnReady() override
    {
        if (!HasAuthority())
        { return; }

        auto SpawnParams = FCk_EntityScript_WithActor_SpawnParams();
        SpawnParams._OwningActor = this;
        auto PendingEntity = utils_entity_script::Request_SpawnEntity(
            ck::TransientEntity(),
            UCk_ReplicationGym_PawnExtra_EntityScript,
            SpawnParams);
        utils_pending_entity_script::Promise_OnConstructed(
            PendingEntity, FCk_Delegate_EntityScript_Constructed(this, n"OnPawnExtraConstructed"));
    }

    UFUNCTION()
    private void OnPawnExtraConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        ck::Trace("[ReplicationGym] Pawn extra entity script constructed");
    }
}
