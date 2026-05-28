// Language=angelscript

//============================================================================
// CK TRANSFORM — NET AUTOMATION TEST: LOCATION REPLICATES
//============================================================================
//
// Server issues Request_SetLocation on the subject's Transform fragment;
// FProcessor_Transform_Replicate marks FCk_RepData_Location dirty and Iris
// delivers it to the client, whose OnChange handler re-issues the request
// against the client-side Transform fragment.
//
// Symmetric setup: both worlds get the Transform fragment auto-added via
// UCk_EntityScript_WithActor_UE::Construct (the NetSubject actor now carries
// a USceneComponent root with Movable mobility). No custom NetSubject subclass
// needed — the default one is sufficient because the FCk_RepData_Location
// container handler delivers the post-mutation snapshot.
//
// Single mutation → no settle-between-mutations needed (snapshot-not-deltas
// only matters for back-to-back changes within one rep cycle).
//============================================================================

class UCk_AutoTest_Net_Location_Replicates : UCk_AutoTest_NetBase
{
    private const FVector kTargetLocation = FVector(250.0f, -100.0f, 50.0f);
    private const float32 kTolerance = 1.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { FinishFailure("DIAG-A: subject entity not found"); return; }

        if (!utils_transform::Has(Subject))
        { FinishFailure("DIAG-B: subject has no Transform fragment — WithActor::Construct guard tripped?"); return; }

        if (utils_net::Get_HasAuthority(Subject))
        {
            auto Req = FCk_Request_Transform_SetLocation(kTargetLocation);
            Req.Set_LocalWorld(ECk_LocalWorld::World);
            Subject.Request_SetLocation(Req);
        }

        WaitOneFrame(n"OnPollLocation");
    }

    UFUNCTION()
    private void OnPollLocation(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { WaitOneFrame(n"OnPollLocation"); return; }

        auto Loc = Subject.Get_EntityCurrentLocation();
        if (Loc.Equals(kTargetLocation, kTolerance))
        {
            FinishSuccess();
            return;
        }

        WaitOneFrame(n"OnPollLocation");
    }
}
