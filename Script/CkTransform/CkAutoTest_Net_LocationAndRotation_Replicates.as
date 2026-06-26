// Language=angelscript

//============================================================================
// CK TRANSFORM — NET AUTOMATION TEST: COMBINED Location + Rotation Replicates
//============================================================================
//
// Server issues a single Request_SetLocationAndRotation; the processor sets
// both location and rotation in one tick, marks both
// ECk_TransformComponents flags, and FProcessor_Transform_Replicate writes
// both FCk_RepData_Location and FCk_RepData_Rotation in the same rep cycle.
//
// Client must observe BOTH at the post-mutation values. Tolerance is permissive
// because rotation round-trips through FQuat (same as the Rotation-only test).
//============================================================================

class UCk_AutoTest_Net_LocationAndRotation_Replicates : UCk_AutoTest_NetBase
{
    private const FVector  kTargetLocation = FVector(-150.0f, 200.0f, 75.0f);
    private const FRotator kTargetRotation = FRotator(15.0f, -45.0f, 90.0f);
    private const float32  kLocTolerance = 1.0f;
    private const float32  kRotTolerance = 0.5f;

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
            auto Req = FCk_Request_Transform_SetLocationAndRotation(kTargetLocation, kTargetRotation);
            Req.Set_LocalWorld(ECk_LocalWorld::World);
            Subject.Request_SetLocationAndRotation(Req);
        }

        WaitOneFrame(n"OnPoll");
    }

    UFUNCTION()
    private void OnPoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { WaitOneFrame(n"OnPoll"); return; }

        auto Loc = Subject.Get_EntityCurrentLocation();
        auto Rot = Subject.Get_EntityCurrentRotation();

        if (Loc.Equals(kTargetLocation, kLocTolerance) &&
            Rot.Equals(kTargetRotation, kRotTolerance))
        {
            FinishSuccess();
            return;
        }

        WaitOneFrame(n"OnPoll");
    }
}
