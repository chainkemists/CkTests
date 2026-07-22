// Language=angelscript

//============================================================================
// CK POI — AUTOMATION TEST: Add creates valid handle
//============================================================================
//
// First-coverage seed for the CkPoi v2 meta-feature. Adding a Poi to an
// entity that has the Transform feature returns a valid FCk_Handle_Poi,
// Has(owner) reports true, and the category round-trips through
// Get_CategoryTags (a CkEntityTag-backed FGameplayTagContainer — the category
// materializes one pump after Add, so it is asserted after a settle frame).
// A freshly added POI carries no Poi.Disabled EntityTag (starts enabled).
//
// Placed at an isolated Y band (52000) so it never interacts with other
// autotests' world content.
//============================================================================

class UCk_AutoTest_Poi_Add_CreatesValidHandle : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private FCk_Handle _Owner;
    private FCk_Handle_Poi _Poi;
    private FGameplayTag _Category;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _Owner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        _Owner.Request_OverrideToSelf();
        utils_transform::Add(_Owner, FTransform(FRotator::ZeroRotator, FVector(0.0, 52000.0, 0.0)),
            ECk_Replication::DoesNotReplicate);

        _Category = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Quest");
        _Poi = utils_poi::Add(_Owner, FCk_Fragment_Poi_ParamsData(_Category));

        Assert_True(ck::IsValid(_Poi),
            "utils_poi::Add should return a valid FCk_Handle_Poi");
        Assert_True(utils_poi::Has(_Owner),
            "After Add, Has on the entity should report true");

        // Enabled means: no Poi.Disabled EntityTag. The disabled tag is never added here,
        // so this reads correctly without a settle (unlike the deferred category tag).
        auto DisabledTag = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Disabled");
        Assert_True(!utils_entity_tag::Has_UsingGameplayTag(_Owner, DisabledTag),
            "A freshly added Poi should be enabled by default (no Poi.Disabled tag)");

        WaitOneFrame(n"OnSettled_Category");
    }

    UFUNCTION()
    private void OnSettled_Category(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Categories = utils_poi::Get_CategoryTags(_Poi);
        Assert_True(Categories.HasTagExact(_Category),
            "Get_CategoryTags should round-trip the category tag passed at Add");

        FinishSuccess();
    }
}
