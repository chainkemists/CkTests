// Language=angelscript
//
// CK AGGRO — AUTOMATION TEST: Request_Include restores excluded Aggro
// After Exclude→Include, ForEach_Aggro with IgnoreExcluded surfaces the
// Aggro again.

class UCk_AutoTest_Aggro_RequestIncludeRestores : UCk_AutoTest_Base
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
        auto AggroHandle = utils_aggro::Add(OwnerHandle, Target, FCk_Fragment_Aggro_Params());

        utils_aggro::Request_Exclude(AggroHandle);

        auto AfterExclude = utils_aggro_owner::ForEach_Aggro(
            OwnerHandle, ECk_Aggro_ExclusionPolicy::IgnoreExcluded, FInstancedStruct(), FCk_Lambda_InHandle());
        Assert_Equals_Int(AfterExclude.Num(), 0,
            "Post-Exclude: IgnoreExcluded should drop the Aggro");

        utils_aggro::Request_Include(AggroHandle);

        auto AfterInclude = utils_aggro_owner::ForEach_Aggro(
            OwnerHandle, ECk_Aggro_ExclusionPolicy::IgnoreExcluded, FInstancedStruct(), FCk_Lambda_InHandle());
        Assert_Equals_Int(AfterInclude.Num(), 1,
            "Post-Include: IgnoreExcluded should restore the previously-excluded Aggro");

        FinishSuccess();
    }
}
