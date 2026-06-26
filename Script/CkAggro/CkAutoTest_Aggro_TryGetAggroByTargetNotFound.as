// Language=angelscript
//
// CK AGGRO — AUTOMATION TEST: TryGet_AggroByTarget returns invalid for unknown target
// A target that has never been Added to this AggroOwner yields an invalid
// Aggro handle.

class UCk_AutoTest_Aggro_TryGetAggroByTargetNotFound : UCk_AutoTest_Base
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

        auto AddedTarget = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_aggro::Add(OwnerHandle, AddedTarget, FCk_Fragment_Aggro_Params());

        auto UnknownTarget = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto Found = utils_aggro_owner::TryGet_AggroByTarget(OwnerHandle, UnknownTarget);
        Assert_True(!utils_handle::Get_IsValid(Found),
            "TryGet_AggroByTarget should return invalid for a target that was never Added");

        FinishSuccess();
    }
}
