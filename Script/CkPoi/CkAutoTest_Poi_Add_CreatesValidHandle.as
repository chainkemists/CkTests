// Language=angelscript

//============================================================================
// CK POI — AUTOMATION TEST: Add creates valid handle
//============================================================================
//
// First-coverage seed for CkPoi. Adding a Poi to an entity that has the
// Transform feature returns a valid FCk_Handle_Poi, Has(owner) reports true,
// and the category round-trips through Get_Category.
//
// Placed at an isolated Y band (52000) so it never interacts with other
// autotests' world content.
//============================================================================

class UCk_AutoTest_Poi_Add_CreatesValidHandle : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Owner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        Owner.Request_OverrideToSelf();
        utils_transform::Add(Owner, FTransform(FRotator::ZeroRotator, FVector(0.0, 52000.0, 0.0)),
            ECk_Replication::DoesNotReplicate);

        auto Category = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Quest");
        auto Params = FCk_Fragment_Poi_ParamsData(Category);
        auto Poi = utils_poi::Add(Owner, Params);

        Assert_True(ck::IsValid(Poi),
            "utils_poi::Add should return a valid FCk_Handle_Poi");
        Assert_True(utils_poi::Has(Owner),
            "After Add, Has on the entity should report true");
        Assert_True(utils_poi::Get_Category(Poi) == Category,
            "Get_Category should round-trip the category tag passed at Add");
        Assert_True(utils_poi::Get_EnableDisable(Poi) == ECk_EnableDisable::Enable,
            "A freshly added Poi should be enabled by default");

        FinishSuccess();
    }
}
