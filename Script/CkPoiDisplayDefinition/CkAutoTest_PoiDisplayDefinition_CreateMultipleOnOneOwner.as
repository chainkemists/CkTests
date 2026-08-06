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
    private FCk_Handle _SelfHandle;
    private FCk_Handle_Poi _Owner;
    private FCk_Handle_PoiDisplayDefinition _ChildCompass;
    private FCk_Handle_PoiDisplayDefinition _ChildMinimap;
    private FGameplayTag _ConsumerCompass;
    private FGameplayTag _ConsumerMinimap;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _SelfHandle = InHandle;

        // Create/TryGet take FCk_Handle_Poi, so the owner is a POI even though nothing projects here.
        auto OwnerEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        OwnerEntity.Request_OverrideToSelf();
        utils_transform::Add(OwnerEntity, FTransform(), ECk_Replication::DoesNotReplicate);
        _Owner = utils_poi::Add(OwnerEntity, FCk_Poi_Spec(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Landmark")));

        _ConsumerCompass = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Consumer.TestCompass");
        _ConsumerMinimap = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Consumer.TestMinimap");

        auto ParamsCompass = FCk_PoiDisplayDefinition_Spec(_ConsumerCompass);
        _ChildCompass = utils_poi_display_definition::Create(_Owner, ParamsCompass);

        auto ParamsMinimap = FCk_PoiDisplayDefinition_Spec(_ConsumerMinimap);
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

        // Add (which Create composes each child through) also stamps a CkLabel carrying the
        // _Consumer. Load-bearing and otherwise invisible: Request_Connect indexes children into
        // _RecordEntriesTagNamePairs BY THAT LABEL, while TryGet above matches the Params field —
        // so a regression in the label would break record-by-name lookups with every assertion
        // above still green.
        Assert_True(utils_gameplay_label::Get_Label(_ChildCompass) == _ConsumerCompass,
            "The compass child's CkLabel should be its own _Consumer tag");
        Assert_True(utils_gameplay_label::Get_Label(_ChildMinimap) == _ConsumerMinimap,
            "The minimap child's CkLabel should be its own _Consumer tag");

        FinishSuccess();
    }
}
