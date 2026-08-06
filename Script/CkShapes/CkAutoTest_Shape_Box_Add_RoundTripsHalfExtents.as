// Language=angelscript

//============================================================================
// CK SHAPES — AUTOMATION TEST: BOX ADD ROUND-TRIPS HALF-EXTENTS
//============================================================================
//
// First-coverage seed for CkShapes. Adding a ShapeBox feature with
// configured half-extents round-trips through Get_Dimensions: the
// dimensions stored on the shape entity match what was passed to the
// FCk_ShapeBox_Spec ctor.
//============================================================================

class UCk_AutoTest_Shape_Box_Add_RoundTripsHalfExtents : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        auto Entity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);

        auto Dimensions = FCk_ShapeBox_Dimensions(FVector(50.0f, 25.0f, 10.0f));
        auto Params = FCk_ShapeBox_Spec(Dimensions);
        auto BoxHandle = utils_shape_box::Add(Entity, Params);

        Assert_True(ck::IsValid(BoxHandle),
            "utils_shape_box::Add should return a valid FCk_Handle_ShapeBox");
        Assert_True(utils_shape_box::Has(Entity),
            "After Add, Has on the owning entity should report true");

        auto Returned = utils_shape_box::Get_Dimensions(BoxHandle);
        auto HE = Returned.Get_HalfExtents();
        Assert_True(HE.X == 50.0f && HE.Y == 25.0f && HE.Z == 10.0f,
            f"Get_Dimensions should round-trip the configured half-extents (50,25,10) (got {HE.X},{HE.Y},{HE.Z})");

        FinishSuccess();
    }
}
