// Language=angelscript

//============================================================================
// CK EQS - AUTOMATION TEST: REQUEST COMPLETION CANCELLED ON TEARDOWN
//============================================================================
//
// Pins the NON-VARIANT branch of ck::request::FireCancelledForPending. CkEqs
// keeps its pending requests as a plain TArray<FCk_Request_Eqs_RunQuery> on
// FFragment_EqsQuery_Requests, not as a TArray<std::variant<...>> like most
// features - so the arm that calls TryFireCompletion directly, WITHOUT
// std::visit, is the one exercised here. CkTimer only ever drives the variant
// arm, leaving this one unexecuted at runtime.
//   1. Create a querier entity and enqueue a deferred RunQuery on it, carrying
//      a completion delegate.
//   2. Destroy the querier in the same frame, before FProcessor_Eqs_HandleRequests
//      (FGroup_PostTransform) can drain it - that view excludes
//      FTag_DestroyEntity_Initiate, which Request_DestroyEntity applies
//      synchronously.
//   3. FProcessor_Eqs_CancelPendingRequests (FGroup_EndPlay) must complete the
//      queued request with Failed_Cancelled and report the querier as owner.
//   4. Settle past the whole destruction pipeline and assert exactly one fire.
//============================================================================

class UCk_AutoTest_Eqs_RequestCompletion_CancelledOnTeardown : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle _Querier;
    private int _FireCount = 0;
    private int _SettleFrames = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        _Querier = utils_entity_lifetime::Request_CreateEntity(LocalHandle);

        auto Generator = FCk_Eqs_GeneratorParams();
        Generator.Set_GeneratorType(ECk_Eqs_GeneratorType::SimpleGrid);
        Generator.Set_SpaceBetween(100.0f);
        Generator.Set_GridHalfSize(100.0f);

        auto DistanceTest = FCk_Eqs_TestParams();
        DistanceTest.Set_TestType(ECk_Eqs_TestType::Distance);
        DistanceTest.Set_Purpose(ECk_Eqs_TestPurpose::Score);

        auto Tests = TArray<FCk_Eqs_TestParams>();
        Tests.Add(DistanceTest);

        auto Params = FCk_Eqs_QueryParams(_Querier, Generator, Tests);
        auto Request = FCk_Request_Eqs_RunQuery(Params);

        utils_eqs::Request_RunQuery(_Querier, Request,
            FCk_Delegate_Request_OnCompleted(this, n"OnCompleted"));

        utils_entity_lifetime::Request_DestroyEntity(_Querier);

        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (IsFinished()) { return; }

        _FireCount += 1;

        Assert_True(InResult == ECk_Request_OperationResult::Failed_Cancelled,
            f"A request whose owner is destroyed before draining must complete with Failed_Cancelled (got {InResult})");

        Assert_True(InRequestOwner == _Querier,
            "Cancellation must report the request's owner entity");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _SettleFrames += 1;

        // The destruction pipeline spans three ticks (Initiate/EndPlay -> Await ->
        // Finalize). Waiting all of them out is what makes "exactly once" meaningful.
        if (_SettleFrames < 3)
        {
            WaitOneFrame(n"OnSettled");
            return;
        }

        Assert_Equals_Int(_FireCount, 1,
            "Completion delegate must fire exactly once for a cancelled request");

        FinishSuccess();
    }
}
