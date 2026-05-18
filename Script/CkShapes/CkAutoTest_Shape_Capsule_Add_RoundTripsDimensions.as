// Language=angelscript

//============================================================================
// CK SHAPES — AUTOMATION TEST: CAPSULE ADD ROUND-TRIPS DIMENSIONS
//============================================================================
//
// Capsule variant. Capsule has two parameters (half-height + radius);
// both must round-trip through Get_Dimensions.
//============================================================================

class UCk_AutoTest_Shape_Capsule_Add_RoundTripsDimensions : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        auto Entity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);

        auto Dimensions = FCk_ShapeCapsule_Dimensions(120.0f, 30.0f);
        auto Params = FCk_Fragment_ShapeCapsule_ParamsData(Dimensions);
        auto CapsuleHandle = utils_shape_capsule::Add(Entity, Params);

        Assert_True(ck::IsValid(CapsuleHandle),
            "utils_shape_capsule::Add should return a valid FCk_Handle_ShapeCapsule");
        Assert_True(utils_shape_capsule::Has(Entity),
            "After Add, Has on the owning entity should report true");

        auto Returned = utils_shape_capsule::Get_Dimensions(CapsuleHandle);
        Assert_True(Returned.Get_HalfHeight() == 120.0f,
            f"Get_Dimensions should round-trip the configured half-height (120) (got {Returned.Get_HalfHeight()})");
        Assert_True(Returned.Get_Radius() == 30.0f,
            f"Get_Dimensions should round-trip the configured radius (30) (got {Returned.Get_Radius()})");

        FinishSuccess();
    }
}
