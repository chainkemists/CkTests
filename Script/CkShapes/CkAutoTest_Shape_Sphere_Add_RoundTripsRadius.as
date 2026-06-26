// Language=angelscript

//============================================================================
// CK SHAPES — AUTOMATION TEST: SPHERE ADD ROUND-TRIPS RADIUS
//============================================================================
//
// Sphere variant of the ShapeBox round-trip seed: adding a ShapeSphere
// with a configured radius round-trips through Get_Dimensions.
//============================================================================

class UCk_AutoTest_Shape_Sphere_Add_RoundTripsRadius : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        auto Entity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);

        auto Dimensions = FCk_ShapeSphere_Dimensions(75.0f);
        auto Params = FCk_Fragment_ShapeSphere_ParamsData(Dimensions);
        auto SphereHandle = utils_shape_sphere::Add(Entity, Params);

        Assert_True(ck::IsValid(SphereHandle),
            "utils_shape_sphere::Add should return a valid FCk_Handle_ShapeSphere");
        Assert_True(utils_shape_sphere::Has(Entity),
            "After Add, Has on the owning entity should report true");

        auto Returned = utils_shape_sphere::Get_Dimensions(SphereHandle);
        Assert_True(Returned.Get_Radius() == 75.0f,
            f"Get_Dimensions should round-trip the configured radius (75) (got {Returned.Get_Radius()})");

        FinishSuccess();
    }
}
