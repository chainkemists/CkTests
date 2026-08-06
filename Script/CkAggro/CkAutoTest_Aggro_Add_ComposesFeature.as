// Language=angelscript
//
// CK AGGRO — AUTOMATION TEST (P0): Add composes the Aggro feature
// Adding Aggro onto an entity that has a Transform returns a valid typed handle,
// reports the feature as enabled, and starts with zero tracked targets.

class UCk_AutoTest_Aggro_Add_ComposesFeature : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto Params = FCk_Aggro_Spec();
        auto Aggro  = utils_aggro::Add(Owner, Params);

        Assert_True(ck::IsValid(Aggro),
            "Aggro Add should return a valid FCk_Handle_Aggro");
        Assert_True(Aggro.Get_IsEnabled(),
            "A freshly-added Aggro should be enabled");
        Assert_Equals_Int(Aggro.Get_NumTrackedTargets(), 0,
            "A freshly-added Aggro should track zero targets");

        FinishSuccess();
    }
}
