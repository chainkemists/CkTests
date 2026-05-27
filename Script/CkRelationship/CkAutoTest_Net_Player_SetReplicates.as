// Language=angelscript

//============================================================================
// CK AUTOMATION TEST — NETWORKED PLAYER ID REPLICATION
//============================================================================
//
// Verifies that calling Assign on the server propagates the new Player ID to
// the client via the FCk_RepData_Player rep handler. Server and client both
// have Player + Team child entities (added symmetrically by
// UCk_AutoTest_NetSubject_RelationshipEntityScript_UE during Construct).
//
// Surface: Ck.Relationship.Net.AS_Player_SetReplicates
//============================================================================

class UCk_AutoTest_Net_Player_SetReplicates : UCk_AutoTest_NetBase
{
    // Override the harness's spawn-subject class. The generator reads this from
    // the CDO and emits the matching SpawnActor in the Replicated-mode C++ stub.
    default _NetSubjectClass = ACk_AutoTest_NetSubject_Relationship_UE;

    // Target Player ID the server applies. Distinct from the default Unassigned
    // so the client's poll has an unambiguous "did it change" signal.
    private const ECk_Player_ID TargetPlayerID = ECk_Player_ID::One;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { FinishFailure("subject not found — harness misconfigured?"); return; }

        auto Player = utils_player::TryGet_Entity_Player_InOwnershipChain(Subject);
        if (ck::Is_NOT_Valid(Player))
        { FinishFailure("Player child entity missing — entity-script Add failed?"); return; }

        if (utils_net::Get_HasAuthority(Subject))
        {
            utils_player::Assign(Player, TargetPlayerID);
            FinishSuccess();
            return;
        }

        WaitOneFrame(n"OnPlayerIDPollTick");
    }

    UFUNCTION()
    private void OnPlayerIDPollTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Subject = Get_SubjectEntity();
        auto Player  = utils_player::TryGet_Entity_Player_InOwnershipChain(Subject);
        if (ck::Is_NOT_Valid(Player))
        {
            WaitOneFrame(n"OnPlayerIDPollTick");
            return;
        }

        auto Current = utils_player::Get_ID(Player);
        if (Current == TargetPlayerID)
        {
            Assert_True(true, "Player ID replicated to client");
            FinishSuccess();
            return;
        }

        WaitOneFrame(n"OnPlayerIDPollTick");
    }
}
