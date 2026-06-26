// Language=angelscript
//
// CK AGGRO — AUTOMATION TEST: Aggro Add happy path
// With an AggroOwner set up on an aggressor and a target entity, Add returns
// a valid FCk_Handle_Aggro.

class UCk_AutoTest_Aggro_AddHappyPath : UCk_AutoTest_Base
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

        auto AggroParams = FCk_Fragment_Aggro_Params();
        auto AggroHandle = utils_aggro::Add(OwnerHandle, Target, AggroParams);

        Assert_True(utils_handle::Get_IsValid(AggroHandle),
            "Aggro Add should return a valid FCk_Handle_Aggro");

        FinishSuccess();
    }
}
