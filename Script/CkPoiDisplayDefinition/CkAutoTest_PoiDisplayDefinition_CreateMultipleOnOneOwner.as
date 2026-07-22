// Language=angelscript

//============================================================================
// CK POI DISPLAY DEFINITION — AUTOMATION TEST: multiple Creates on one owner
//============================================================================
//
// Two Creates with DISTINCT _Consumer tags on a single owner compose two
// consumer-keyed child definitions under the owner's RecordOfPoiDisplayDefinitions.
// VERIFIED here:
//   - Both Create handles are valid and DISTINCT.
//   - TryGet_PoiDisplayDefinition_ByConsumer resolves each consumer to the
//     correct child.
//   - TryGet with an unused consumer returns an INVALID handle.
//
// Create's Request_Connect (wiring the child into the owner's record) is
// DEFERRED, so TryGet — which walks that record — is asserted after one
// WaitOneFrame to let the connect settle.
//============================================================================

class UCk_AutoTest_PoiDisplayDefinition_CreateMultipleOnOneOwner : UCk_AutoTest_Base
{
    private FCk_Handle _Owner;
    private FCk_Handle_PoiDisplayDefinition _ChildCompass;
    private FCk_Handle_PoiDisplayDefinition _ChildMinimap;
    private FGameplayTag _ConsumerCompass;
    private FGameplayTag _ConsumerMinimap;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _Owner = LocalHandle;

        _ConsumerCompass = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Consumer.TestCompass");
        _ConsumerMinimap = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Consumer.TestMinimap");

        auto ParamsCompass = FCk_Fragment_PoiDisplayDefinition_ParamsData(_ConsumerCompass);
        _ChildCompass = utils_poi_display_definition::Create(_Owner, ParamsCompass);

        auto ParamsMinimap = FCk_Fragment_PoiDisplayDefinition_ParamsData(_ConsumerMinimap);
        _ChildMinimap = utils_poi_display_definition::Create(_Owner, ParamsMinimap);

        WaitOneFrame(n"OnConnectsSettled");
    }

    UFUNCTION()
    private void OnConnectsSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(ck::IsValid(_ChildCompass),
            "First Create should produce a valid child definition");
        Assert_True(ck::IsValid(_ChildMinimap),
            "Second Create should produce a valid child definition");
        Assert_True(!(_ChildCompass == _ChildMinimap),
            "Two Creates with different consumers should produce DISTINCT child entities");

        auto ResolvedCompass = utils_poi_display_definition::TryGet_PoiDisplayDefinition_ByConsumer(_Owner, _ConsumerCompass);
        Assert_True(ResolvedCompass == _ChildCompass,
            "The compass consumer should resolve to the compass child");

        auto ResolvedMinimap = utils_poi_display_definition::TryGet_PoiDisplayDefinition_ByConsumer(_Owner, _ConsumerMinimap);
        Assert_True(ResolvedMinimap == _ChildMinimap,
            "The minimap consumer should resolve to the minimap child");

        auto ResolvedUnused = utils_poi_display_definition::TryGet_PoiDisplayDefinition_ByConsumer(
            _Owner, utils_gameplay_tag::ResolveGameplayTag(n"Poi.Consumer.TestUnused"));
        Assert_True(ck::Is_NOT_Valid(ResolvedUnused),
            "An unused consumer should resolve to an INVALID handle");

        FinishSuccess();
    }
}
