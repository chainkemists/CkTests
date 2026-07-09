// Language=angelscript

//============================================================================
// CK PHYSICS — AUTOMATION TEST: ACCELERATION CREATE MAKES A DISTINCT CHILD
//============================================================================
//
// Covers the child-making Create verb (counterpart to the stamp-self Add).
// Create(owner, params, DoesNotReplicate) spawns a NEW child entity carrying
// the Acceleration feature: the returned handle is valid, Has(child) is true,
// Has(owner) is FALSE (proving Create is child-making, not stamp-self), and
// the configured starting acceleration round-trips on the child.
//
// The child is given a Transform so the Acceleration setup processor is
// satisfied on subsequent ticks.
//============================================================================

class UCk_AutoTest_Acceleration_Create_MakesDistinctChild : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private const FVector StartingAcceleration = FVector(100.0f, -50.0f, 25.0f);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto Params = FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, StartingAcceleration);

        auto Child = utils_acceleration::Create(Owner, Params, ECk_Replication::DoesNotReplicate);
        auto ChildEntity = FCk_Handle(Child);

        Assert_True(ck::IsValid(Child),
            "Create should return a valid FCk_Handle_Acceleration");
        Assert_True(utils_acceleration::Has(ChildEntity),
            "The created child entity should carry the Acceleration feature");
        Assert_True(!utils_acceleration::Has(Owner),
            "The owner must NOT carry the feature — Create is child-making, not stamp-self");

        auto Returned = utils_acceleration::Get_CurrentAcceleration(Child);
        Assert_True(Returned.X == StartingAcceleration.X && Returned.Y == StartingAcceleration.Y && Returned.Z == StartingAcceleration.Z,
            f"Create should stamp the configured StartingAcceleration onto the child (got {Returned.X},{Returned.Y},{Returned.Z})");

        utils_transform::Add(ChildEntity, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        FinishSuccess();
    }
}
