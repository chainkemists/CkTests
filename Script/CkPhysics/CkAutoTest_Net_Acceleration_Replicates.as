// Language=angelscript

//============================================================================
// CK PHYSICS — NET AUTOMATION TEST: ACCELERATION REPLICATES
//============================================================================
//
// The default NetSubject's entity-script adds a Replicates Acceleration (World
// coords, zero starting) on both worlds and stashes the handle on the actor as
// `_TestAcceleration`. The server Request_OverrideAcceleration's a distinctive
// vector; the client polls Get_CurrentAcceleration for it via the
// FCk_RepData_Acceleration container handler (OnChange -> Request_Override on the
// client). Acceleration is single-per-entity, so the actor-stash avoids a by-tag
// lookup (mirrors the CkTagSet net test).
//
// Surface: Ck.Physics.Net.AS_Acceleration_Replicates
//============================================================================

class UCk_AutoTest_Net_Acceleration_Replicates : UCk_AutoTest_NetBase
{
    private FVector _ExpectedValue = FVector(111.0, 222.0, 333.0);
    private float32 _Tolerance = 0.01f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { FinishFailure("subject entity not found"); return; }

        auto SubjectActor = utils_owning_actor::Get_EntityOwningActor(Subject);
        auto NetSubject = Cast<ACk_AutoTest_NetSubject>(SubjectActor);
        if (NetSubject == nullptr)
        { FinishFailure("actor cast to ACk_AutoTest_NetSubject failed"); return; }

        auto Acceleration = NetSubject._TestAcceleration;
        if (ck::Is_NOT_Valid(Acceleration))
        { FinishFailure("Acceleration handle null — entity-script Construct didn't stash it?"); return; }

        if (utils_net::Get_HasAuthority(Subject))
        {
            utils_acceleration::Request_OverrideAcceleration(Acceleration, _ExpectedValue);
            FinishSuccess();
            return;
        }

        WaitOneFrame(n"OnPollValue");
    }

    private int _PollCount = 0;
    private const int kPollBudget = 400;

    UFUNCTION()
    private void OnPollValue(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _PollCount++;

        auto Subject = Get_SubjectEntity();
        auto SubjectActor = utils_owning_actor::Get_EntityOwningActor(Subject);
        auto NetSubject = Cast<ACk_AutoTest_NetSubject>(SubjectActor);
        if (NetSubject == nullptr)
        { WaitOneFrame(n"OnPollValue"); return; }

        auto Acceleration = NetSubject._TestAcceleration;
        if (ck::Is_NOT_Valid(Acceleration))
        { WaitOneFrame(n"OnPollValue"); return; }

        if (utils_acceleration::Get_CurrentAcceleration(Acceleration).Equals(_ExpectedValue, _Tolerance))
        {
            FinishSuccess();
            return;
        }
        if (_PollCount > kPollBudget)
        { FinishFailure("client Acceleration never gained the replicated value"); return; }

        WaitOneFrame(n"OnPollValue");
    }
}
