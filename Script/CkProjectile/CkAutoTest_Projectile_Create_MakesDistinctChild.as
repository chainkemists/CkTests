// Language=angelscript

//============================================================================
// CK PROJECTILE — AUTOMATION TEST: Projectile CREATE MAKES A DISTINCT CHILD
//============================================================================
//
// Verifies the child-making Create verb (counterpart to the stamp-self Add):
// Create(owner, ...) spawns a NEW child entity carrying the feature — the
// returned handle is valid, Has(child) is true, and Has(owner) is FALSE
// (proving Create is child-making, not stamp-self like Add).
//============================================================================

class UCk_AutoTest_Projectile_Create_MakesDistinctChild : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto VelocityParams = FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector(50.0f, 0.0f, 0.0f));
        auto AccelerationParams = FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector(0.0f, 0.0f, -980.0f));
        auto AutoReorientParams = FCk_Fragment_AutoReorient_ParamsData(ECk_AutoReorient_Policy::NoAutoReorient);
        auto ProjectileParams = FCk_Fragment_Projectile_ParamsData(VelocityParams, AccelerationParams, AutoReorientParams);

        auto Child = utils_projectile::Create(Owner, ProjectileParams, ECk_Replication::DoesNotReplicate);
        auto ChildEntity = FCk_Handle(Child);

        Assert_True(ck::IsValid(Child),
            "Create should return a valid FCk_Handle_Projectile");
        Assert_True(utils_projectile::Has(ChildEntity),
            "The created child entity should carry the Projectile feature");
        Assert_True(!utils_projectile::Has(Owner),
            "The owner must NOT carry the feature — Create is child-making, not stamp-self");

        utils_transform::Add(ChildEntity, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        FinishSuccess();
    }
}
