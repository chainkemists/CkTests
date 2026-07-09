// Language=angelscript

//============================================================================
// CK PHYSICS — AUTOMATION TEST: AutoReorient CREATE MAKES A DISTINCT CHILD
//============================================================================
//
// Verifies the child-making Create verb (counterpart to the stamp-self Add):
// Create(owner, params) spawns a NEW child entity carrying the feature — the
// returned handle is valid, Has(child) is true, and Has(owner) is FALSE
// (proving Create is child-making, not stamp-self like Add).
//
// The child is given a Transform so the AutoReorient setup processor is
// satisfied on subsequent ticks.
//============================================================================

class UCk_AutoTest_AutoReorient_Create_MakesDistinctChild : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto Params = FCk_Fragment_AutoReorient_ParamsData(ECk_AutoReorient_Policy::OrientTowardsVelocity);

        auto Child = utils_auto_reorient::Create(Owner, Params);
        auto ChildEntity = FCk_Handle(Child);

        Assert_True(ck::IsValid(Child),
            "Create should return a valid FCk_Handle_AutoReorient");
        Assert_True(utils_auto_reorient::Has(ChildEntity),
            "The created child entity should carry the AutoReorient feature");
        Assert_True(!utils_auto_reorient::Has(Owner),
            "The owner must NOT carry the feature — Create is child-making, not stamp-self");

        utils_transform::Add(ChildEntity, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        FinishSuccess();
    }
}
