// Language=angelscript
//
// CK AGGRO — AUTOMATION TEST: TryGet_AggroByTarget finds the match
// After Add, querying the AggroOwner with the target handle returns the
// Aggro handle that Add returned.

class UCk_AutoTest_Aggro_TryGetAggroByTargetFound : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Aggressor = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto OwnerParams = FCk_Fragment_AggroOwner_Params();
        OwnerParams.Set_FilterByDistance(false);
        OwnerParams.Set_FilterByLoS(false);
        auto OwnerHandle = utils_aggro_owner::Add(Aggressor, OwnerParams);

        auto Target = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto Added = utils_aggro::Add(OwnerHandle, Target, FCk_Fragment_Aggro_Params());

        auto Found = utils_aggro_owner::TryGet_AggroByTarget(OwnerHandle, Target);
        Assert_True(utils_handle::Get_IsValid(Found),
            "TryGet_AggroByTarget should return a valid Aggro for an added target");
        Assert_True(utils_handle::IsEqual(Found, Added),
            "TryGet_AggroByTarget should yield the same handle Add returned");

        FinishSuccess();
    }
}
