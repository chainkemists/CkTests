// Language=angelscript
//
// CK AGGRO — AUTOMATION TEST (P0): CreateTarget returns a typed child
// CreateTarget on an Aggro owner builds a valid AggroTarget child, bumps the
// tracked-target count to one, and the child reports the tracked entity it was
// created for.

class UCk_AutoTest_Aggro_CreateTarget_ReturnsTypedChild : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto Params = FCk_Fragment_Aggro_ParamsData();
        auto Aggro  = utils_aggro::Add(Owner, Params);

        auto TrackedEntity = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto TargetParams = FCk_Fragment_AggroTarget_ParamsData(TrackedEntity);
        auto Target       = Aggro.CreateTarget(TargetParams);

        Assert_True(ck::IsValid(Target),
            "CreateTarget should return a valid FCk_Handle_AggroTarget child");
        Assert_Equals_Int(Aggro.Get_NumTrackedTargets(), 1,
            "Owner should track exactly one target after CreateTarget");
        Assert_True(Target.Get_TrackedEntity() == TrackedEntity,
            "The created target should report the tracked entity it was created for");

        FinishSuccess();
    }
}
