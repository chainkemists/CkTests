// Language=angelscript

//============================================================================
// CK PATH NETWORK — AUTOMATION TEST: INVALID LIVE TUNING FAILS CLOSED
//============================================================================
//
// An invalid tuning request must diagnose and return before enqueueing any
// mutation. The existing Ready result remains byte-observably unchanged and no
// second Ready/Failed callback fires during the settle window.
//============================================================================

class UCk_AutoTest_PathNetworkFollower_InvalidTuningRejectsWithoutReplan
    : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_PathNetwork _Network;
    private FCk_Handle_PathNetworkFollower _Follower;
    private FCk_Handle _Context;
    private int32 _ReadyCount = 0;
    private int32 _FailedCount = 0;
    private int32 _RevisionBeforeInvalid = 0;
    private int32 _WaypointCountBeforeInvalid = 0;
    private float _CostBeforeInvalid = 0.0f;
    private const FVector Goal = FVector(450.0, 0.0, 0.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _Context = InHandle;

        utils_transform::Add(
            LocalHandle,
            FTransform(
                FRotator::ZeroRotator,
                FVector(-50.0, 0.0, 0.0),
                FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        TArray<FCk_PathNetwork_RibbonPoint> Points;
        Points.Add(FCk_PathNetwork_RibbonPoint(FVector(-50.0, 0.0, 0.0), 100.0));
        Points.Add(FCk_PathNetwork_RibbonPoint(FVector(450.0, 0.0, 0.0), 100.0));

        TArray<FCk_PathNetwork_Ribbon> Ribbons;
        Ribbons.Add(FCk_PathNetwork_Ribbon(Points));
        _Network = utils_path_network::Add(
            LocalHandle,
            FCk_Fragment_PathNetwork_ParamsData(Ribbons));

        auto InvalidInitialParams = FCk_Fragment_PathNetworkFollower_ParamsData();
        InvalidInitialParams.Set_CornerSmoothingDistance(-1.0f);
        const auto InvalidInitialFollower =
            utils_path_network_follower::Add(LocalHandle, InvalidInitialParams);
        Assert_True(
            ck::Is_NOT_Valid(InvalidInitialFollower),
            "invalid initial tuning must return no follower");
        Assert_True(
            utils_path_network_follower::Has(LocalHandle) == false,
            "invalid initial tuning must compose no follower fragments");

        auto Params = FCk_Fragment_PathNetworkFollower_ParamsData();
        Params.Set_Network(_Network);
        Params.Set_OwnerToken(n"CkTests.PathNetwork.InvalidTuning");
        Params.Set_CorridorWaypointSpacing(100.0f);
        _Follower = utils_path_network_follower::Add(LocalHandle, Params);

        utils_path_network_follower::BindTo_OnRouteReady(
            _Follower,
            FCk_Delegate_PathNetworkFollower_OnRouteReady(this, n"OnRouteReady"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_path_network_follower::BindTo_OnRouteFailed(
            _Follower,
            FCk_Delegate_PathNetworkFollower_OnRouteFailed(this, n"OnRouteFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        WaitOneFrame(n"OnNetworkReady");
    }

    UFUNCTION()
    private void OnNetworkReady(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        utils_path_network_follower::Request_FindRoute(
            _Follower,
            FCk_Request_PathNetworkFollower_FindRoute(Goal));
    }

    UFUNCTION()
    private void OnRouteReady(
        FCk_Handle_PathNetworkFollower InFollower,
        FCk_PathNetwork_RouteResult InResult)
    {
        if (IsFinished()) { return; }

        _ReadyCount++;
        if (_ReadyCount > 1)
        {
            FinishFailure("invalid tuning unexpectedly triggered a second Ready callback");
            return;
        }

        _RevisionBeforeInvalid = InResult.Get_TuningRevision();
        _WaypointCountBeforeInvalid = InResult.Get_CompiledWaypoints().Num();
        _CostBeforeInvalid = InResult.Get_TotalCost();

        auto InvalidTuning = FCk_PathNetworkFollower_Tuning();
        InvalidTuning.Set_OffPathCostMultiplier(0.5f);
        InvalidTuning.Set_SideKeepingFraction(1.5f);
        InvalidTuning.Set_CorridorWaypointSpacing(10.0f);
        const auto BatchUpdated =
            utils_path_network_follower::Request_UpdateTuningAndReplanByOwnerToken(
                _Context,
                n"CkTests.PathNetwork.InvalidTuning",
                InvalidTuning);
        Assert_Equals_Int(BatchUpdated, 0,
            "invalid batch tuning must report zero updated followers");
        utils_path_network_follower::Request_UpdateTuningAndReplan(
            _Follower, InvalidTuning);

        auto InvalidSmoothing = FCk_PathNetworkFollower_Tuning();
        InvalidSmoothing.Set_CornerSmoothingDistance(-1.0f);
        Assert_Equals_Int(
            utils_path_network_follower::Request_UpdateTuningAndReplanByOwnerToken(
                _Context,
                n"CkTests.PathNetwork.InvalidTuning",
                InvalidSmoothing),
            0,
            "negative smoothing must report zero updated followers");
        utils_path_network_follower::Request_UpdateTuningAndReplan(
            _Follower, InvalidSmoothing);

        auto InvalidClearance = FCk_PathNetworkFollower_Tuning();
        InvalidClearance.Set_DesiredNavmeshClearance(-1.0f);
        Assert_Equals_Int(
            utils_path_network_follower::Request_UpdateTuningAndReplanByOwnerToken(
                _Context,
                n"CkTests.PathNetwork.InvalidTuning",
                InvalidClearance),
            0,
            "negative clearance must report zero updated followers");
        utils_path_network_follower::Request_UpdateTuningAndReplan(
            _Follower, InvalidClearance);

        WaitOneFrame(n"OnInvalidRequestSettled");
    }

    UFUNCTION()
    private void OnInvalidRequestSettled(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        const auto Result =
            utils_path_network_follower::Get_RouteResult(_Follower);
        Assert_Equals_Int(_ReadyCount, 1, "invalid tuning must not emit another Ready");
        Assert_Equals_Int(_FailedCount, 0, "invalid tuning must not emit Failed");
        Assert_True(
            Result.Get_Status() == ECk_PathNetwork_RouteStatus::Ready,
            "invalid tuning must leave the prior Ready route installed");
        Assert_Equals_Int(
            Result.Get_TuningRevision(),
            _RevisionBeforeInvalid,
            "invalid tuning must not increment the revision");
        Assert_Equals_Int(
            Result.Get_CompiledWaypoints().Num(),
            _WaypointCountBeforeInvalid,
            "invalid tuning must not replace corridor geometry");
        Assert_True(
            Math::IsNearlyEqual(Result.Get_TotalCost(), _CostBeforeInvalid, 0.01),
            "invalid tuning must not change route cost");
        FinishSuccess();
    }

    UFUNCTION()
    private void OnRouteFailed(
        FCk_Handle_PathNetworkFollower InFollower)
    {
        if (IsFinished()) { return; }
        _FailedCount++;
    }
}

class ACk_AutoTest_PathNetworkFollower_InvalidTuningRejectsWithoutReplan_Actor
    : ACk_AutoTestRunner
{
    default _TestEntityScriptClass =
        UCk_AutoTest_PathNetworkFollower_InvalidTuningRejectsWithoutReplan;

    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("PathNetworkFollower parameters contain invalid tuning");
        Out.Add("Request_UpdateTuningAndReplanByOwnerToken received invalid tuning");
        Out.Add("Request_UpdateTuningAndReplan received invalid tuning");
        return Out;
    }
}
