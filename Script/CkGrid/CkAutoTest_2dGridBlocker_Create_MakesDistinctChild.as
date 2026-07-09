// Language=angelscript

//============================================================================
// CK GRID — AUTOMATION TEST: 2dGridBlocker CREATE MAKES A DISTINCT CHILD
//============================================================================
//
// Verifies the child-making Create verb (counterpart to the stamp-self Add):
// Create(owner, ...) spawns a NEW child entity carrying the feature — the
// returned handle is valid, Has(child) is true, and Has(owner) is FALSE
// (proving Create is child-making, not stamp-self like Add).
//============================================================================

class UCk_AutoTest_2dGridBlocker_Create_MakesDistinctChild : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);

        // The blocker params reference a live grid; build one exactly as the
        // Add test does (grid owner needs a Transform — the grid is spatial).
        auto GridOwner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto GridOwnerT = utils_transform::Add(
            GridOwner, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        auto GP = FCk_Fragment_2dGridSystem_ParamsData(FIntPoint(10, 10), FVector2D(100.0f, 100.0f));
        GP.Set_DefaultCellState(ECk_EnableDisable::Enable);
        auto Grid = utils_2d_grid_system::Add(GridOwnerT, GP);

        auto Params = FCk_Fragment_2dGridBlocker_ParamsData(Grid, FIntPoint(2, 2), FIntPoint(2, 2));

        auto Child = utils_2d_grid_blocker::Create(Owner, Params);
        auto ChildEntity = FCk_Handle(Child);

        Assert_True(ck::IsValid(Child),
            "Create should return a valid FCk_Handle_2dGridBlocker");
        Assert_True(utils_2d_grid_blocker::Has(ChildEntity),
            "The created child entity should carry the 2dGridBlocker feature");
        Assert_True(!utils_2d_grid_blocker::Has(Owner),
            "The owner must NOT carry the feature — Create is child-making, not stamp-self");

        FinishSuccess();
    }
}
