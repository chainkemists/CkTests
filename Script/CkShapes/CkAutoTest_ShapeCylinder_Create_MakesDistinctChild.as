// Language=angelscript

//============================================================================
// CK SHAPES — AUTOMATION TEST: ShapeCylinder CREATE MAKES A DISTINCT CHILD
//============================================================================
//
// Verifies the child-making Create verb (counterpart to the stamp-self Add):
// Create(owner, ...) spawns a NEW child entity carrying the feature — the
// returned handle is valid, Has(child) is true, and Has(owner) is FALSE
// (proving Create is child-making, not stamp-self like Add).
//============================================================================

class UCk_AutoTest_ShapeCylinder_Create_MakesDistinctChild : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto Dimensions = FCk_ShapeCylinder_Dimensions(120.0f, 30.0f);
        auto Params = FCk_Fragment_ShapeCylinder_ParamsData(Dimensions);

        auto Child = utils_shape_cylinder::Create(Owner, Params);
        auto ChildEntity = FCk_Handle(Child);

        Assert_True(ck::IsValid(Child),
            "Create should return a valid FCk_Handle_ShapeCylinder");
        Assert_True(utils_shape_cylinder::Has(ChildEntity),
            "The created child entity should carry the ShapeCylinder feature");
        Assert_True(!utils_shape_cylinder::Has(Owner),
            "The owner must NOT carry the feature — Create is child-making, not stamp-self");

        utils_transform::Add(ChildEntity, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        FinishSuccess();
    }
}
