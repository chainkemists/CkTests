// Language=angelscript
//
// CK AGGRO — AUTOMATION TEST: Get_AggroTarget round-trip
// Get_AggroTarget on a freshly added Aggro returns the target entity that
// was passed to Add.

class UCk_AutoTest_Aggro_GetTarget : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Aggressor = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto OwnerParams = FCk_Fragment_AggroOwner_Params();
        OwnerParams.Set_FilterByDistance(false);
        OwnerParams.Set_FilterByLoS(false);
        auto OwnerHandle = utils_aggro_owner::Add(Aggressor, OwnerParams);

        auto Target = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto AggroHandle = utils_aggro::Add(OwnerHandle, Target, FCk_Fragment_Aggro_Params());

        auto FoundTarget = utils_aggro::Get_AggroTarget(AggroHandle);
        Assert_True(utils_handle::IsEqual(FoundTarget, Target),
            "Get_AggroTarget should round-trip to the target passed at Add");

        FinishSuccess();
    }
}
