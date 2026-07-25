// Language=angelscript

//============================================================================
// CK POI DISPLAY DEFINITION — AUTOMATION TEST: direct-attach Add
//============================================================================
//
// Add composes ONE display definition DIRECTLY onto the test entity (no child
// entity). VERIFIED here:
//   - Add returns a valid FCk_Handle_PoiDisplayDefinition.
//   - Get_Consumer / Get_Priority / Get_OffscreenPolicy echo the params.
//   - TryGet_PoiDisplayDefinition_ByConsumer(entity, thatConsumer) resolves to
//     the entity itself (the AS-visible proxy for "Has is true" — the C++
//     Has() is not a UFUNCTION, so it has no generated AS binding).
//   - TryGet with an UNUSED consumer tag returns an INVALID handle.
//
// Direct-attach Add is synchronous (immediate fragment add), so no settle
// frames are needed — everything is asserted inline in DoBeginPlay.
//
// The owner is a POI: Add/Create/TryGet take FCk_Handle_Poi, so the owner needs
// the Transform + Poi composition even though nothing here projects.
//============================================================================

class UCk_AutoTest_PoiDisplayDefinition_AddDirectAttach : UCk_AutoTest_Base
{
    private FCk_Handle _SelfHandle;
    private FCk_Handle_Poi _Owner;
    private FCk_Handle_PoiDisplayDefinition _Def;
    private FGameplayTag _Consumer;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _SelfHandle = InHandle;

        auto OwnerEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        OwnerEntity.Request_OverrideToSelf();
        utils_transform::Add(OwnerEntity, FTransform(), ECk_Replication::DoesNotReplicate);
        _Owner = utils_poi::Add(OwnerEntity, FCk_Fragment_Poi_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Landmark")));

        _Consumer = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Consumer.TestCompass");

        auto Params = FCk_Fragment_PoiDisplayDefinition_ParamsData(_Consumer);
        Params.Set_Priority(7);
        Params.Set_OffscreenPolicy(ECk_Poi_OffscreenPolicy::ClampToEdge);
        _Def = utils_poi_display_definition::Add(_Owner, Params);

        Assert_True(ck::IsValid(_Def),
            "Add should return a valid PoiDisplayDefinition handle");

        Assert_True(utils_poi_display_definition::Get_Consumer(_Def) == _Consumer,
            "Get_Consumer should echo the Consumer param passed to Add");

        Assert_Equals_Int(utils_poi_display_definition::Get_Priority(_Def), 7,
            "Get_Priority should echo the Priority param");

        Assert_True(utils_poi_display_definition::Get_OffscreenPolicy(_Def) == ECk_Poi_OffscreenPolicy::ClampToEdge,
            "Get_OffscreenPolicy should echo the OffscreenPolicy param");

        // Has-is-true proxy: a direct-attach definition is resolved by the owner's own
        // consumer, and TryGet returns the entity itself (Has(InOwner) branch in C++).
        auto Resolved = utils_poi_display_definition::TryGet_PoiDisplayDefinition_ByConsumer(_Owner, _Consumer);
        Assert_True(Resolved == _Def,
            "TryGet by the same consumer should resolve to the direct-attach definition on the entity itself");

        // An unused consumer must resolve to an INVALID handle (house TryGet_* contract).
        auto ResolvedUnused = utils_poi_display_definition::TryGet_PoiDisplayDefinition_ByConsumer(
            _Owner, utils_gameplay_tag::ResolveGameplayTag(n"Poi.Consumer.TestUnused"));
        Assert_True(ck::Is_NOT_Valid(ResolvedUnused),
            "TryGet by an unused consumer should return an INVALID handle");

        FinishSuccess();
    }
}
