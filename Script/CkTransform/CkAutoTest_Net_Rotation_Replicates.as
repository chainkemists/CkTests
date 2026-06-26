// Language=angelscript

//============================================================================
// CK TRANSFORM — NET AUTOMATION TEST: ROTATION REPLICATES
//============================================================================
//
// Server issues Request_SetRotation on the subject; FCk_RepData_Rotation
// container handler replicates to the client, which re-issues the request
// against the client-side Transform fragment.
//
// Rotation values round-trip through FQuat on the wire (rep payload stores
// FQuat, OnChange converts back to FRotator) — use Equals tolerance, not ==.
// See the standalone CkAutoTest_Transform_SetRotation.as for the same gotcha.
//============================================================================

class UCk_AutoTest_Net_Rotation_Replicates : UCk_AutoTest_NetBase
{
    private const FRotator kTargetRotation = FRotator(30.0f, 60.0f, 45.0f);
    private const float32 kTolerance = 0.5f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { FinishFailure("DIAG-A: subject entity not found"); return; }

        if (!utils_transform::Has(Subject))
        { FinishFailure("DIAG-B: subject has no Transform fragment"); return; }

        if (utils_net::Get_HasAuthority(Subject))
        {
            auto Req = FCk_Request_Transform_SetRotation(kTargetRotation);
            Req.Set_LocalWorld(ECk_LocalWorld::World);
            Subject.Request_SetRotation(Req);
        }

        WaitOneFrame(n"OnPollRotation");
    }

    UFUNCTION()
    private void OnPollRotation(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { WaitOneFrame(n"OnPollRotation"); return; }

        auto Rot = Subject.Get_EntityCurrentRotation();
        if (Rot.Equals(kTargetRotation, kTolerance))
        {
            FinishSuccess();
            return;
        }

        WaitOneFrame(n"OnPollRotation");
    }
}
