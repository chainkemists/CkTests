// Language=angelscript

//============================================================================
// CK SHAPES - AUTOMATION TEST: Shapes CREATE MAKES A DISTINCT CHILD
//============================================================================
//
// Verifies the child-making Create verb (counterpart to the stamp-self Add):
// Create(owner, ...) spawns a NEW child entity carrying the feature - the
// returned handle is valid, Has(child) is true, and Has(owner) is FALSE
// (proving Create is child-making, not stamp-self like Add).
//============================================================================

class UCk_AutoTest_Shapes_Create_MakesDistinctChild : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto Dimensions = FCk_ShapeBox_Dimensions(FVector(50.0f, 25.0f, 10.0f));
        auto Params = utils_shapes::Make_Box(Dimensions);

        auto Child = utils_shapes::Create(Owner, Params);
        auto ChildEntity = FCk_Handle(Child);

        Assert_True(ck::IsValid(Child),
            "Create should return a valid FCk_Handle_Shape");
        Assert_True(utils_shapes::Has(ChildEntity),
            "The created child entity should carry the Shapes feature");
        Assert_True(!utils_shapes::Has(Owner),
            "The owner must NOT carry the feature - Create is child-making, not stamp-self");

        utils_transform::Add(ChildEntity, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        FinishSuccess();
    }
}
