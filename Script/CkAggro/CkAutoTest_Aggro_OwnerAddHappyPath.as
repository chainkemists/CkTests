// Language=angelscript
//
// CK AGGRO — AUTOMATION TEST: AggroOwner Add happy path
// Add the AggroOwner feature with distance + LoS filters disabled; the
// returned handle is valid.

class UCk_AutoTest_Aggro_OwnerAddHappyPath : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Aggressor = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto Params = FCk_Fragment_AggroOwner_Params();
        Params.Set_FilterByDistance(false);
        Params.Set_FilterByLoS(false);

        auto OwnerHandle = utils_aggro_owner::Add(Aggressor, Params);

        Assert_True(utils_handle::Get_IsValid(OwnerHandle),
            "AggroOwner Add should return a valid FCk_Handle_AggroOwner");

        FinishSuccess();
    }
}
