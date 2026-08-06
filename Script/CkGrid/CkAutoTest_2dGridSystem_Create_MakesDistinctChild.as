// Language=angelscript

//============================================================================
// CK GRID — AUTOMATION TEST: 2dGridSystem CREATE MAKES A DISTINCT CHILD
//============================================================================
//
// Verifies the child-making Create verb (counterpart to the stamp-self Add):
// Create(owner, ...) spawns a NEW child entity carrying the feature — the
// returned handle is valid, Has(child) is true, and Has(owner) is FALSE
// (proving Create is child-making, not stamp-self like Add).
//
// Note: Create stamps the child's Transform internally (Ck2dGridSystem_Utils.cpp:102),
// so no post-assert utils_transform::Add is needed — a second Add would double-stamp
// the Transform fragment and fire an ensure.
//============================================================================

class UCk_AutoTest_2dGridSystem_Create_MakesDistinctChild : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto Params = FCk_2dGridSystem_Spec(
            FIntPoint(4, 3), FVector2D(100.0f, 100.0f));
        Params.Set_DefaultCellState(ECk_EnableDisable::Enable);

        auto Child = utils_2d_grid_system::Create(Owner, FTransform::Identity, Params);
        auto ChildEntity = FCk_Handle(Child);

        Assert_True(ck::IsValid(Child),
            "Create should return a valid FCk_Handle_2dGridSystem");
        Assert_True(utils_2d_grid_system::Has(ChildEntity),
            "The created child entity should carry the 2dGridSystem feature");
        Assert_True(!utils_2d_grid_system::Has(Owner),
            "The owner must NOT carry the feature — Create is child-making, not stamp-self");

        FinishSuccess();
    }
}
