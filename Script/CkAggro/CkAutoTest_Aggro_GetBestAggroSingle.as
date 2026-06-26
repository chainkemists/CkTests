// Language=angelscript
//
// CK AGGRO — AUTOMATION TEST: Get_BestAggro stays invalid without scoring filters
// Get_BestAggro reads FFragment_AggroOwner_Current._BestAggro, which is only
// populated by FProcessor_Aggro_DistanceScore (gated on the Filter_Distance
// tag) feeding FProcessor_Aggro_UpdateBestAggro. With both filters disabled,
// nothing scores the Aggros and no "best" is ever picked.
//
// Pins the current contract so a future refactor that decouples
// best-aggro selection from the distance filter is caught by the failure.

class UCk_AutoTest_Aggro_GetBestAggroSingle : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle_AggroOwner _OwnerHandle;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Aggressor = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto OwnerParams = FCk_Fragment_AggroOwner_Params();
        OwnerParams.Set_FilterByDistance(false);
        OwnerParams.Set_FilterByLoS(false);
        _OwnerHandle = utils_aggro_owner::Add(Aggressor, OwnerParams);

        auto Target = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_aggro::Add(_OwnerHandle, Target, FCk_Fragment_Aggro_Params());

        // Let the scheduler tick — confirms that no processor populates
        // BestAggro when the score filters are disabled.
        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Best = utils_aggro_owner::Get_BestAggro(_OwnerHandle);
        Assert_True(!utils_handle::Get_IsValid(Best),
            "With FilterByDistance and FilterByLoS both disabled, no processor scores the Aggros and Get_BestAggro stays invalid");

        FinishSuccess();
    }
}
