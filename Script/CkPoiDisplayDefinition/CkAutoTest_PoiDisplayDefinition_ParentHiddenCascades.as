// Language=angelscript

//============================================================================
// CK POI DISPLAY DEFINITION — AUTOMATION TEST: parent-hidden cascade
//============================================================================
//
// The owner composes CkVisibleRange (MaxRange 500, UpdateInterval 0 → evaluate
// every tick). Two display-definition children are created under it; ONE of the
// two ALSO composes its OWN VisibleRange kept deliberately IN range. Driving the
// OWNER out of range must cascade FTag_PoiDisplayDefinition_ParentHidden onto
// BOTH children — including the one whose own range says "visible". That is the
// PARENT-WINS proof (PROMPT success criterion #3): the child's own in-range vote
// cannot keep it visible while its parent is hidden.
//
// VERIFIED:
//   - Owner out of range  → BOTH children Get_IsParentHidden == true.
//   - The child WITHOUT its own VisibleRange has Get_IsEffectivelyHidden mirror
//     Get_IsParentHidden (folds the parent cascade).
//   - Owner back in range → BOTH children Get_IsParentHidden == false.
//
// Settle window is TWO chained WaitOneFrames per transition: the VisibleRange
// processor flips FTag_VisibleRange_Hidden and broadcasts OnHiddenChanged on the
// first frame; the bound cascade handler's delivery + ParentHidden application
// may land the same frame or the next — two frames is the deterministic window.
//============================================================================

class UCk_AutoTest_PoiDisplayDefinition_ParentHiddenCascades : UCk_AutoTest_Base
{
    private FCk_Handle _Owner;
    private FCk_Handle_VisibleRange _OwnerVR;
    private FCk_Handle_PoiDisplayDefinition _ChildPlain;        // no own VisibleRange
    private FCk_Handle_PoiDisplayDefinition _ChildWithOwnRange; // own VisibleRange, kept in range

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _Owner = LocalHandle;

        // Owner composes VisibleRange, evaluated every tick.
        auto OwnerVRParams = FCk_Fragment_VisibleRange_ParamsData(500.0f);
        OwnerVRParams.Set_UpdateInterval(FCk_Time(0.0));
        _OwnerVR = utils_visible_range::Add(_Owner, OwnerVRParams);

        // Two display-definition children under the owner. Create binds the owner's
        // VisibleRange->child ParentHidden cascade once, on the first Create.
        auto ParamsPlain = FCk_Fragment_PoiDisplayDefinition_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Consumer.TestCompass"));
        _ChildPlain = utils_poi_display_definition::Create(_Owner, ParamsPlain);

        auto ParamsOwnRange = FCk_Fragment_PoiDisplayDefinition_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Consumer.TestMinimap"));
        _ChildWithOwnRange = utils_poi_display_definition::Create(_Owner, ParamsOwnRange);

        // Second child ALSO composes its OWN VisibleRange, kept IN range (distance 100 <
        // MaxRange 500). Its own vote therefore says "visible" — the parent-wins discriminator.
        // (FCk_Handle_PoiDisplayDefinition implicitly converts to FCk_Handle for Add's owner param.)
        auto ChildVRParams = FCk_Fragment_VisibleRange_ParamsData(500.0f);
        ChildVRParams.Set_UpdateInterval(FCk_Time(0.0));
        auto ChildVR = utils_visible_range::Add(_ChildWithOwnRange, ChildVRParams);
        utils_visible_range::Update_Distance(ChildVR, 100.0f);

        // Drive the OWNER out of range → the cascade should hide BOTH children.
        utils_visible_range::Update_Distance(_OwnerVR, 1000.0f);
        WaitOneFrame(n"OnOwnerHidden_Frame1");
    }

    UFUNCTION()
    private void OnOwnerHidden_Frame1(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        WaitOneFrame(n"OnOwnerHidden_Frame2");
    }

    UFUNCTION()
    private void OnOwnerHidden_Frame2(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_poi_display_definition::Get_IsParentHidden(_ChildPlain),
            "Child (no own range) should be ParentHidden once the owner goes hidden");
        Assert_True(utils_poi_display_definition::Get_IsParentHidden(_ChildWithOwnRange),
            "Parent-wins: child WITH its own in-range VisibleRange must STILL be ParentHidden");

        // For the child without its own VisibleRange, IsEffectivelyHidden folds to the
        // parent cascade alone.
        Assert_True(utils_poi_display_definition::Get_IsEffectivelyHidden(_ChildPlain),
            "Get_IsEffectivelyHidden should mirror Get_IsParentHidden for the child with no own VisibleRange");

        // Drive the owner back in range → the cascade should clear both children.
        utils_visible_range::Update_Distance(_OwnerVR, 100.0f);
        WaitOneFrame(n"OnOwnerShown_Frame1");
    }

    UFUNCTION()
    private void OnOwnerShown_Frame1(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        WaitOneFrame(n"OnOwnerShown_Frame2");
    }

    UFUNCTION()
    private void OnOwnerShown_Frame2(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(!utils_poi_display_definition::Get_IsParentHidden(_ChildPlain),
            "Child (no own range) should clear ParentHidden once the owner is shown again");
        Assert_True(!utils_poi_display_definition::Get_IsParentHidden(_ChildWithOwnRange),
            "Child (with own range) should clear ParentHidden once the owner is shown again");

        FinishSuccess();
    }
}
