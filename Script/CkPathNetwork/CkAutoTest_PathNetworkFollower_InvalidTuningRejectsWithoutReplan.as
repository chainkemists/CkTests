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
            FCk_PathNetwork_Spec(Ribbons));

        // Ownership acquisition requires a namespaced logical-owner token even
        // when there is no follower to conflict with. The invalid request must
        // not compose a partial Params/Corridor feature pair.
        auto EmptyOwnerParams = FCk_PathNetworkFollower_Spec();
        EmptyOwnerParams.Set_Network(_Network);
        ECk_PathNetworkFollower_OwnershipResult OwnershipResult
            = ECk_PathNetworkFollower_OwnershipResult::RejectedInvalidInput;
        const auto EmptyOwnerFollower =
            utils_path_network_follower::Try_AddOrAdoptByOwnerToken(
                LocalHandle, EmptyOwnerParams, OwnershipResult);
        Assert_True(ck::Is_NOT_Valid(EmptyOwnerFollower),
            "empty ownership token rejects without returning a follower");
        Assert_True(OwnershipResult
                == ECk_PathNetworkFollower_OwnershipResult::RejectedInvalidInput,
            "empty ownership token reports explicit invalid input");
        Assert_True(utils_path_network_follower::Has(LocalHandle) == false,
            "empty ownership token composes no follower fragments");

        auto InvalidInitialParams = FCk_PathNetworkFollower_Spec();
        InvalidInitialParams.Set_CornerSmoothingDistance(-1.0f);
        const auto InvalidInitialFollower =
            utils_path_network_follower::Add(LocalHandle, InvalidInitialParams);
        Assert_True(
            ck::Is_NOT_Valid(InvalidInitialFollower),
            "invalid initial tuning must return no follower");
        Assert_True(
            utils_path_network_follower::Has(LocalHandle) == false,
            "invalid initial tuning must compose no follower fragments");

        auto Params = FCk_PathNetworkFollower_Spec();
        Params.Set_Network(_Network);
        Params.Set_OwnerToken(n"CkTests.PathNetwork.InvalidTuning");
        Params.Set_CorridorWaypointSpacing(100.0f);
        _Follower = utils_path_network_follower::Try_AddOrAdoptByOwnerToken(
            LocalHandle, Params, OwnershipResult);
        Assert_True(ck::IsValid(_Follower),
            "valid ownership params add a follower");
        Assert_True(OwnershipResult
                == ECk_PathNetworkFollower_OwnershipResult::Added,
            "new follower reports Added ownership result");

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

        // Request_FindRoute below needs a built network to route through — wait on that
        // rather than on a frame.
        WaitUntil(n"Check_NetworkBuilt", n"OnNetworkReady");
    }

    UFUNCTION()
    private void Check_NetworkBuilt(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_path_network::Get_IsBuilt(_Network));
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

        // A fresh state/script instance with the same logical owner must adopt
        // the exact feature without restamping its route, tuning, or corridor.
        FCk_Handle GenericFollowerOwner = _Follower;
        auto SameOwnerParams = FCk_PathNetworkFollower_Spec();
        SameOwnerParams.Set_Network(_Network);
        SameOwnerParams.Set_OwnerToken(n"CkTests.PathNetwork.InvalidTuning");
        SameOwnerParams.Set_OffPathCostMultiplier(12.0f);
        SameOwnerParams.Set_CorridorWaypointSpacing(50.0f);
        ECk_PathNetworkFollower_OwnershipResult OwnershipResult
            = ECk_PathNetworkFollower_OwnershipResult::RejectedInvalidInput;
        const auto AdoptedFollower =
            utils_path_network_follower::Try_AddOrAdoptByOwnerToken(
                GenericFollowerOwner, SameOwnerParams, OwnershipResult);
        Assert_True(AdoptedFollower == _Follower,
            "same owner token adopts the exact existing follower handle");
        Assert_True(OwnershipResult
                == ECk_PathNetworkFollower_OwnershipResult::Adopted,
            "same owner token reports Adopted");

        auto ForeignOwnerParams = FCk_PathNetworkFollower_Spec();
        ForeignOwnerParams.Set_Network(_Network);
        ForeignOwnerParams.Set_OwnerToken(n"CkTests.PathNetwork.ForeignOwner");
        ForeignOwnerParams.Set_OffPathCostMultiplier(12.0f);
        const auto ForeignOwnerFollower =
            utils_path_network_follower::Try_AddOrAdoptByOwnerToken(
                GenericFollowerOwner, ForeignOwnerParams, OwnershipResult);
        Assert_True(ck::Is_NOT_Valid(ForeignOwnerFollower),
            "different owner token cannot replace the existing follower");
        Assert_True(OwnershipResult
                == ECk_PathNetworkFollower_OwnershipResult::RejectedExistingOwner,
            "different owner token reports explicit existing-owner rejection");

        // An invalid endpoint policy input must reject before an existing
        // same-token follower is adopted or mutated. This pins the fail-closed
        // boundary separately from the invalid-tuning checks below.
        auto MalformedEndpointParams = FCk_PathNetworkFollower_Spec();
        MalformedEndpointParams.Set_OwnerToken(n"CkTests.PathNetwork.InvalidTuning");
        MalformedEndpointParams.Set_NearEndpointCostMultiplier(0.5f);
        const auto MalformedEndpointFollower =
            utils_path_network_follower::Try_AddOrAdoptByOwnerToken(
                GenericFollowerOwner, MalformedEndpointParams, OwnershipResult);
        Assert_True(ck::Is_NOT_Valid(MalformedEndpointFollower),
            "invalid endpoint policy cannot adopt or replace an existing follower");
        Assert_True(OwnershipResult
                == ECk_PathNetworkFollower_OwnershipResult::RejectedInvalidInput,
            "invalid endpoint policy reports explicit invalid input");

        auto MalformedNetworkGapParams =
            FCk_PathNetworkFollower_Spec();
        MalformedNetworkGapParams.Set_OwnerToken(
            n"CkTests.PathNetwork.InvalidTuning");
        MalformedNetworkGapParams.Set_NetworkGapCostMultiplier(0.5f);
        const auto MalformedNetworkGapFollower =
            utils_path_network_follower::Try_AddOrAdoptByOwnerToken(
                GenericFollowerOwner,
                MalformedNetworkGapParams,
                OwnershipResult);
        Assert_True(
            ck::Is_NOT_Valid(MalformedNetworkGapFollower),
            "invalid network-gap multiplier cannot adopt or replace an existing follower");
        Assert_True(
            OwnershipResult
                == ECk_PathNetworkFollower_OwnershipResult::RejectedInvalidInput,
            "invalid network-gap multiplier reports explicit invalid input");

        auto MalformedTransferParams =
            FCk_PathNetworkFollower_Spec();
        MalformedTransferParams.Set_OwnerToken(
            n"CkTests.PathNetwork.InvalidTuning");
        MalformedTransferParams.Set_ComponentTransferMaxDistance(-1.0f);
        const auto MalformedTransferFollower =
            utils_path_network_follower::Try_AddOrAdoptByOwnerToken(
                GenericFollowerOwner,
                MalformedTransferParams,
                OwnershipResult);
        Assert_True(
            ck::Is_NOT_Valid(MalformedTransferFollower),
            "negative component-transfer distance cannot adopt or replace an existing follower");
        Assert_True(
            OwnershipResult
                == ECk_PathNetworkFollower_OwnershipResult::RejectedInvalidInput,
            "negative component-transfer distance reports explicit invalid input");

        auto MalformedLocalShortcutParams =
            FCk_PathNetworkFollower_Spec();
        MalformedLocalShortcutParams.Set_OwnerToken(
            n"CkTests.PathNetwork.InvalidTuning");
        MalformedLocalShortcutParams.Set_LocalNetworkShortcutMaxDistance(
            -1.0f);
        const auto MalformedLocalShortcutFollower =
            utils_path_network_follower::Try_AddOrAdoptByOwnerToken(
                GenericFollowerOwner,
                MalformedLocalShortcutParams,
                OwnershipResult);
        Assert_True(
            ck::Is_NOT_Valid(MalformedLocalShortcutFollower),
            "negative local-shortcut distance cannot adopt or replace an existing follower");
        Assert_True(
            OwnershipResult
                == ECk_PathNetworkFollower_OwnershipResult::RejectedInvalidInput,
            "negative local-shortcut distance reports explicit invalid input");

        const auto OwnershipResultAfterRejections =
            utils_path_network_follower::Get_RouteResult(_Follower);
        Assert_True(utils_path_network_follower::Get_OwnerToken(_Follower)
                == n"CkTests.PathNetwork.InvalidTuning",
            "ownership boundary calls preserve the original logical-owner token");
        Assert_True(OwnershipResultAfterRejections.Get_Status()
                == ECk_PathNetwork_RouteStatus::Ready,
            "ownership boundary calls preserve the ready route state");
        Assert_Equals_Int(OwnershipResultAfterRejections.Get_TuningRevision(),
            _RevisionBeforeInvalid,
            "ownership boundary calls preserve the tuning revision");
        Assert_Equals_Int(OwnershipResultAfterRejections.Get_CompiledWaypoints().Num(),
            _WaypointCountBeforeInvalid,
            "ownership boundary calls preserve corridor identity");
        Assert_True(Math::IsNearlyEqual(
                OwnershipResultAfterRejections.Get_TotalCost(), _CostBeforeInvalid, 0.01),
            "ownership boundary calls preserve route cost");

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

        auto InvalidNetworkGap = FCk_PathNetworkFollower_Tuning();
        InvalidNetworkGap.Set_NetworkGapCostMultiplier(0.5f);
        Assert_Equals_Int(
            utils_path_network_follower::Request_UpdateTuningAndReplanByOwnerToken(
                _Context,
                n"CkTests.PathNetwork.InvalidTuning",
                InvalidNetworkGap),
            0,
            "invalid network-gap multiplier must report zero updated followers");
        utils_path_network_follower::Request_UpdateTuningAndReplan(
            _Follower,
            InvalidNetworkGap);

        auto InvalidTransfer = FCk_PathNetworkFollower_Tuning();
        InvalidTransfer.Set_ComponentTransferMaxDistance(-1.0f);
        Assert_Equals_Int(
            utils_path_network_follower::Request_UpdateTuningAndReplanByOwnerToken(
                _Context,
                n"CkTests.PathNetwork.InvalidTuning",
                InvalidTransfer),
            0,
            "negative component-transfer distance must report zero updated followers");
        utils_path_network_follower::Request_UpdateTuningAndReplan(
            _Follower,
            InvalidTransfer);

        auto InvalidLocalShortcut = FCk_PathNetworkFollower_Tuning();
        InvalidLocalShortcut.Set_LocalNetworkShortcutMaxDistance(-1.0f);
        Assert_Equals_Int(
            utils_path_network_follower::Request_UpdateTuningAndReplanByOwnerToken(
                _Context,
                n"CkTests.PathNetwork.InvalidTuning",
                InvalidLocalShortcut),
            0,
            "negative local-shortcut distance must report zero updated followers");
        utils_path_network_follower::Request_UpdateTuningAndReplan(
            _Follower,
            InvalidLocalShortcut);

        auto InvalidDirectSavings = FCk_PathNetworkFollower_Tuning();
        InvalidDirectSavings.Set_DirectRouteMinimumSavingsFraction(1.01f);
        Assert_Equals_Int(
            utils_path_network_follower::Request_UpdateTuningAndReplanByOwnerToken(
                _Context,
                n"CkTests.PathNetwork.InvalidTuning",
                InvalidDirectSavings),
            0,
            "direct-route savings above one must report zero updated followers");
        utils_path_network_follower::Request_UpdateTuningAndReplan(
            _Follower,
            InvalidDirectSavings);

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
        Out.Add("Try_AddOrAdoptByOwnerToken requires a non-empty owner token");
        Out.Add("Try_AddOrAdoptByOwnerToken received invalid follower tuning");
        Out.Add("Request_UpdateTuningAndReplanByOwnerToken received invalid tuning");
        Out.Add("Request_UpdateTuningAndReplan received invalid tuning");
        return Out;
    }
}
