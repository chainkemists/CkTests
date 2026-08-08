// Language=angelscript

//============================================================================
// CK INPUT BIAS — AUTOMATION TEST: AN OUT-OF-RANGE DECLARATION CHANGES NOTHING
//============================================================================
//
// Every conditioning parameter has a range whose violation is silent rather
// than loud if it is clamped instead of rejected: a deadzone of 1 leaves the
// axis permanently dead and makes the rescale divide by zero, an exponent of
// 0 flattens every deflection to full, and a negative sensitivity flips the
// axis in a way the inversion field exists to express honestly.
//
// So both entry boundaries reject rather than clamp, and both do it BEFORE
// anything is written. This asserts the three things that make that claim
// mean something:
//
//   1. The caller is told, and told the right thing — Failed_NotEnqueued, on
//      the calling stack, because nothing was ever queued.
//   2. Nothing partial survives. The conditioning table is still empty after
//      five rejected retunes, and an entity whose composition was rejected
//      can still be composed cleanly afterwards — which it could not if a
//      fragment had been left on it.
//   3. Nothing lands late. The settle at the end exists so a request that was
//      wrongly enqueued has a chance to drain and be caught.
//
// Composition is atomic per DECLARATION, not per row: the duplicate-axis case
// rejects the whole table, because keeping one of two rows for the same axis
// would make which one arbitrary.
//============================================================================

class UCk_AutoTest_InputBias_InvalidDeclarationRejectedAtomically : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle             _Owner;
    private FCk_Handle_InputSource _Source;
    private FCk_Handle_InputBias   _Bias;

    private FCk_Handle             _OtherOwner;
    private FCk_Handle_InputSource _OtherSource;

    private int32 _RejectFires = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));
        _Bias   = utils_input_bias::Add(_Owner, FCk_Fragment_InputBias_ParamsData());

        Assert_True(ck::IsValid(_Bias),
            "the bias must compose for the rejection legs to have a target");
        Assert_Equals_Int(utils_input_bias::Get_AxisBiases(_Bias).Num(), 0,
            "the table starts empty");

        DoRunRetuneRejectionLegs();
        DoRunCompositionRejectionLeg(InHandle);

        Assert_Equals_Int(_RejectFires, 5,
            "each of the five out-of-range retunes must complete on the calling stack");
        Assert_Equals_Int(utils_input_bias::Get_AxisBiases(_Bias).Num(), 0,
            "five rejected retunes must leave the conditioning table exactly as they found it");

        // MUST stay a settle: every assertion in OnSettled is a NEGATIVE — that nothing drained, nothing
        // completed a second time — and each is already true here. The window exists to give a wrongly
        // enqueued request a drain pass in which to be caught.
        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(utils_input_bias::Get_AxisBiases(_Bias).Num(), 0,
            "no rejected retune may reach the drain and land a row a frame later");
        Assert_Equals_Int(_RejectFires, 5,
            "a rejected retune completes exactly once — never again from a drain");
        Assert_Equals_Float(utils_input_bias::Get_ConditionedAxisValue(_Bias, EKeys::Gamepad_LeftX), 0.0f, 0.0001f,
            "a rejected declaration must not have produced a conditioned reading out of nothing");

        FinishSuccess();
    }

    //------------------------------------------------------------------------

    private void DoRunRetuneRejectionLegs()
    {
        auto DeadzoneAtOne = FCk_InputBias_AxisBias(EKeys::Gamepad_LeftX);
        DeadzoneAtOne.Set_Deadzone(1.0f);
        DoRequestRetune(DeadzoneAtOne);

        auto DeadzoneNegative = FCk_InputBias_AxisBias(EKeys::Gamepad_LeftX);
        DeadzoneNegative.Set_Deadzone(-0.1f);
        DoRequestRetune(DeadzoneNegative);

        auto ExponentZero = FCk_InputBias_AxisBias(EKeys::Gamepad_LeftX);
        ExponentZero.Set_Exponent(0.0f);
        DoRequestRetune(ExponentZero);

        auto SensitivityNegative = FCk_InputBias_AxisBias(EKeys::Gamepad_LeftX);
        SensitivityNegative.Set_Sensitivity(-1.0f);
        DoRequestRetune(SensitivityNegative);

        // A default-constructed row names no key at all — a bias that could never match an event.
        auto NoAxisKey = FCk_InputBias_AxisBias();
        DoRequestRetune(NoAxisKey);
    }

    private void DoRunCompositionRejectionLeg(FCk_Handle InHandle)
    {
        _OtherOwner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _OtherSource = utils_input_source::Add(_OtherOwner, FCk_Fragment_InputSource_ParamsData(1));

        Assert_True(ck::IsValid(_OtherSource),
            "the second entity must be an InputSource before a bias can be composed onto it");

        auto OutOfRange = FCk_InputBias_AxisBias(EKeys::Gamepad_RightY);
        OutOfRange.Set_Deadzone(1.5f);

        auto OutOfRangeRows = TArray<FCk_InputBias_AxisBias>();
        OutOfRangeRows.Add(OutOfRange);

        auto RejectedForRange = utils_input_bias::Add(_OtherOwner, FCk_Fragment_InputBias_ParamsData(OutOfRangeRows));

        Assert_True(!ck::IsValid(RejectedForRange),
            "a composition declaring an out-of-range row must return an invalid handle");

        auto DuplicateRows = TArray<FCk_InputBias_AxisBias>();
        DuplicateRows.Add(FCk_InputBias_AxisBias(EKeys::Gamepad_RightY));
        DuplicateRows.Add(FCk_InputBias_AxisBias(EKeys::Gamepad_RightY));

        auto RejectedForDuplicate = utils_input_bias::Add(_OtherOwner, FCk_Fragment_InputBias_ParamsData(DuplicateRows));

        Assert_True(!ck::IsValid(RejectedForDuplicate),
            "an axis declared twice in one table must reject the whole declaration");

        auto GoodRows = TArray<FCk_InputBias_AxisBias>();
        GoodRows.Add(FCk_InputBias_AxisBias(EKeys::Gamepad_RightY));

        auto Accepted = utils_input_bias::Add(_OtherOwner, FCk_Fragment_InputBias_ParamsData(GoodRows));

        Assert_True(ck::IsValid(Accepted),
            "the entity must still be composable — a rejected composition that left a fragment behind would be refused here");
        Assert_Equals_Int(utils_input_bias::Get_AxisBiases(Accepted).Num(), 1,
            "the accepted table holds only its own row, none from the two rejected declarations");
    }

    private void DoRequestRetune(FCk_InputBias_AxisBias InAxisBias)
    {
        utils_input_bias::Request_SetAxisBias(_Bias, FCk_Request_InputBias_SetAxisBias(InAxisBias),
            FCk_Delegate_Request_OnCompleted(this, n"OnRetuneRejected"));
    }

    UFUNCTION()
    private void OnRetuneRejected(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (IsFinished()) { return; }

        _RejectFires += 1;

        Assert_True(InResult == ECk_Request_OperationResult::Failed_NotEnqueued,
            f"a retune rejected before enqueue must report Failed_NotEnqueued (got {InResult})");
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR — registers the deliberate-ensure log pattern.
//============================================================================

class ACk_AutoTest_InputBias_InvalidDeclarationRejectedAtomically_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_InputBias_InvalidDeclarationRejectedAtomically;
    default _TimeoutSeconds = 6.0f;

    // Every leg deliberately trips a CK_ENSURE_IF_NOT on the InputBias validation boundary; register the
    // substring so the automation framework does not auto-fail the run on them.
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("InputBias");
        return Out;
    }
}
