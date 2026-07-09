// Language=angelscript

//============================================================================
// CK PHYSICS — AUTOMATION TEST: VELOCITY CREATE MAKES A DISTINCT CHILD
//============================================================================
//
// Covers the child-making Create verb (counterpart to the stamp-self Add).
// Create(owner, params, DoesNotReplicate) spawns a NEW child entity carrying
// the Velocity feature: the returned handle is valid, Has(child) is true,
// Has(owner) is FALSE (proving Create is child-making, not stamp-self), and
// the configured starting velocity round-trips on the child.
//
// The child is given a Transform so the Velocity setup processor is
// satisfied on subsequent ticks.
//============================================================================

class UCk_AutoTest_Velocity_Create_MakesDistinctChild : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private const FVector StartingVelocity = FVector(50.0f, -25.0f, 10.0f);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto Params = FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, StartingVelocity);

        auto Child = utils_velocity::Create(Owner, Params, ECk_Replication::DoesNotReplicate);
        auto ChildEntity = FCk_Handle(Child);

        Assert_True(ck::IsValid(Child),
            "Create should return a valid FCk_Handle_Velocity");
        Assert_True(utils_velocity::Has(ChildEntity),
            "The created child entity should carry the Velocity feature");
        Assert_True(!utils_velocity::Has(Owner),
            "The owner must NOT carry the feature — Create is child-making, not stamp-self");

        auto Returned = utils_velocity::Get_CurrentVelocity(Child);
        Assert_True(Returned.X == StartingVelocity.X && Returned.Y == StartingVelocity.Y && Returned.Z == StartingVelocity.Z,
            f"Create should stamp the configured StartingVelocity onto the child (got {Returned.X},{Returned.Y},{Returned.Z})");

        utils_transform::Add(ChildEntity, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        FinishSuccess();
    }
}
