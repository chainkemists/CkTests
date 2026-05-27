// Language=angelscript

//============================================================================
// CK AUTOMATION TEST — NETWORKED TEAM ID REPLICATION
//============================================================================
//
// Server calls utils_team::Assign; assert the replicated value lands on the
// client via the FCk_RepData_Team rep handler. Mirror shape of the Player ID
// test (CkAutoTest_Net_Player_SetReplicates).
//
// Surface: Ck.Relationship.Net.AS_Team_SetReplicates
//============================================================================

class UCk_AutoTest_Net_Team_SetReplicates : UCk_AutoTest_NetBase
{
    // Override the harness's spawn-subject class. The generator reads this from
    // the CDO and emits the matching SpawnActor in the Replicated-mode C++ stub.
    default _NetSubjectClass = ACk_AutoTest_NetSubject_Relationship_UE;

    // Target Team ID the server applies. Distinct from the default Unassigned
    // so the client's poll has an unambiguous "did it change" signal.
    private const ECk_Team_ID TargetTeamID = ECk_Team_ID::One;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { FinishFailure("subject not found — harness misconfigured?"); return; }

        auto Team = utils_team::TryGet_Entity_Team_InOwnershipChain(Subject);
        if (ck::Is_NOT_Valid(Team))
        { FinishFailure("Team child entity missing — entity-script Add failed?"); return; }

        if (utils_net::Get_HasAuthority(Subject))
        {
            utils_team::Assign(Team, TargetTeamID);
            FinishSuccess();
            return;
        }

        WaitOneFrame(n"OnTeamIDPollTick");
    }

    UFUNCTION()
    private void OnTeamIDPollTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Subject = Get_SubjectEntity();
        auto Team    = utils_team::TryGet_Entity_Team_InOwnershipChain(Subject);
        if (ck::Is_NOT_Valid(Team))
        {
            WaitOneFrame(n"OnTeamIDPollTick");
            return;
        }

        auto Current = utils_team::Get_ID(Team);
        if (Current == TargetTeamID)
        {
            Assert_True(true, "Team ID replicated to client");
            FinishSuccess();
            return;
        }

        WaitOneFrame(n"OnTeamIDPollTick");
    }
}
