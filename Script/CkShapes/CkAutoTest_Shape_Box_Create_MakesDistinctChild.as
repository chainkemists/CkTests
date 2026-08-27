// Language=angelscript

//============================================================================
// CK SHAPES - AUTOMATION TEST: BOX CREATE MAKES A DISTINCT CHILD
//============================================================================
//
// Covers the child-making Create verb (counterpart to the stamp-self Add).
// Create(owner, params) spawns a NEW child entity carrying the ShapeBox
// feature: the returned handle is valid, Has(child) is true, and Has(owner)
// is FALSE - proving Create is child-making, not stamp-self like Add.
//
// The child is given a Transform so the Shapes setup processor (which reads
// the entity transform) is satisfied on subsequent ticks.
//============================================================================

class UCk_AutoTest_Shape_Box_Create_MakesDistinctChild : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto Dimensions = FCk_ShapeBox_Dimensions(FVector(50.0f, 25.0f, 10.0f));
        auto Params = FCk_Fragment_ShapeBox_ParamsData(Dimensions);

        auto Child = utils_shape_box::Create(Owner, Params);
        auto ChildEntity = FCk_Handle(Child);

        Assert_True(ck::IsValid(Child),
            "Create should return a valid FCk_Handle_ShapeBox");
        Assert_True(utils_shape_box::Has(ChildEntity),
            "The created child entity should carry the ShapeBox feature");
        Assert_True(!utils_shape_box::Has(Owner),
            "The owner must NOT carry the feature - Create is child-making, not stamp-self");

        auto Returned = utils_shape_box::Get_Dimensions(Child);
        auto HE = Returned.Get_HalfExtents();
        Assert_True(HE.X == 50.0f && HE.Y == 25.0f && HE.Z == 10.0f,
            f"Create should stamp the configured half-extents onto the child (50,25,10) (got {HE.X},{HE.Y},{HE.Z})");

        utils_transform::Add(ChildEntity, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        FinishSuccess();
    }
}
