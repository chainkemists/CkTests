// Language=angelscript

//============================================================================
// CK RAY SENSE — AUTOMATION TEST: RAYSENSE CREATE MAKES A DISTINCT CHILD
//============================================================================
//
// Covers the child-making Create verb (counterpart to the stamp-self Add).
// Create(owner, params) spawns a NEW child entity carrying the RaySense
// feature: the returned handle is valid, Has(child) is true, and Has(owner)
// is FALSE — proving Create is child-making, not stamp-self like Add.
//
// The child is given a Transform so the RaySense processor (which casts from
// the entity transform) is satisfied on subsequent ticks.
//============================================================================

class UCk_AutoTest_RaySense_Create_MakesDistinctChild : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto Params = FCk_RaySense_Spec(
            ECk_RaySense_CollisionQuality::Sweep, ECollisionChannel::ECC_Visibility);

        auto Child = utils_ray_sense::Create(Owner, Params);
        auto ChildEntity = FCk_Handle(Child);

        Assert_True(ck::IsValid(Child),
            "Create should return a valid FCk_Handle_RaySense");
        Assert_True(utils_ray_sense::Has(ChildEntity),
            "The created child entity should carry the RaySense feature");
        Assert_True(!utils_ray_sense::Has(Owner),
            "The owner must NOT carry the feature — Create is child-making, not stamp-self");

        utils_transform::Add(ChildEntity, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        FinishSuccess();
    }
}
