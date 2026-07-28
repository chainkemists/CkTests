// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: PRE-CLAMP ASYMMETRY (DIRECTIONLESS ACCESSOR)
//============================================================================
//
// Pins the directionless `Get_PreClampFinalValue` contract in
// CkAttribute/CLAUDE.md (Pre-clamp / overflow polling section):
//
//   The attribute system writes a TFragment_Attribute_PreClampFinalValue<T,Dir>
//   per direction at clamp time. Min and Max Clamp processors run sequentially
//   — each capturing _Final at *its own* start — so the two fragments do NOT
//   symmetrically capture the pre-any-clamp value.
//
//   |                       | PreClamp<Min>          | PreClamp<Max>          |
//   | Value overshoots Max  | raw value              | raw value              |
//   | Value undershoots Min | raw value              | already min-clamped    |
//
// The directionless `Get_PreClampFinalValue(attr)` accessor abstracts over
// this asymmetry: it returns the fragment that actually captured the
// pre-clamp state.
//
// Test:
//   Range [0,100], starting at 50.
//   Step 1: Override(200) -> overshoots Max. PreClamp accessor must return 200.
//   Step 2: Override(-50) -> undershoots Min. PreClamp accessor must return -50.
//
// If the implementation read the wrong fragment direction, Step 2 would
// return 0 (the min-clamped intermediate) instead of -50.
//
// Pattern A (signal-driven step machine), per gotcha #10.
//============================================================================

class UCk_AutoTest_Attribute_PreClampAsymmetry : UCk_AutoTest_Base
{
    private FCk_Handle_IntegerAttribute _Attribute;
    private int32 _Step = 0;
    private bool _MaxObserved = false;
    private bool _MinObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Params = FCk_Fragment_IntegerAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.Health"),
            50);
        Params.Set_MinMax(ECk_MinMax::MinMax);
        Params.Set_MinValue(0);
        Params.Set_MaxValue(100);

        auto LocalHandle = InHandle;
        _Attribute = utils_integer_attribute::Add(LocalHandle, Params);

        utils_integer_attribute::BindTo_OnMaxClamped(_Attribute,
            FCk_Delegate_IntegerAttribute_OnClamped(this, n"OnMaxClamped"));
        utils_integer_attribute::BindTo_OnMinClamped(_Attribute,
            FCk_Delegate_IntegerAttribute_OnClamped(this, n"OnMinClamped"));

        Step1_OverrideAboveMax();
    }

    private void Step1_OverrideAboveMax()
    {
        _Step = 1;
        utils_integer_attribute::Request_Override(_Attribute, 200, ECk_MinMaxCurrent::Current);
    }

    private void Step2_OverrideBelowMin()
    {
        _Step = 2;
        utils_integer_attribute::Request_Override(_Attribute, -50, ECk_MinMaxCurrent::Current);
    }

    UFUNCTION()
    private void OnMaxClamped(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_IntegerAttribute_OnClamped InPayload)
    {
        if (IsFinished()) { return; }

        if (_Step == 1 && _MaxObserved == false)
        {
            _MaxObserved = true;
            Assert_Equals_Int(utils_integer_attribute::Get_PreClampFinalValue(_Attribute), 200,
                "After overriding to 200, Get_PreClampFinalValue should return raw 200");
            Assert_Equals_Int(utils_integer_attribute::Get_ClampOverflow(_Attribute), 100,
                "ClampOverflow should be +100 (positive = over max)");
            Step2_OverrideBelowMin();
        }
    }

    UFUNCTION()
    private void OnMinClamped(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_IntegerAttribute_OnClamped InPayload)
    {
        if (IsFinished()) { return; }

        if (_Step == 2 && _MinObserved == false)
        {
            _MinObserved = true;
            Assert_Equals_Int(utils_integer_attribute::Get_PreClampFinalValue(_Attribute), -50,
                "After overriding to -50, Get_PreClampFinalValue should return raw -50 (NOT 0 — directionless accessor must abstract over fragment asymmetry)");
            Assert_Equals_Int(utils_integer_attribute::Get_ClampOverflow(_Attribute), -50,
                "ClampOverflow should be -50 (negative = under min)");
            FinishSuccess();
        }
    }
}
