// Language=angelscript
//
// CK AGGRO — AUTOMATION TEST: ForEach_Aggro respects exclusion policy
// After Request_Exclude, ForEach_Aggro with IgnoreExcluded drops the entry
// while ForEach_Aggro with All still surfaces it.

class UCk_AutoTest_Aggro_ForEachExclusionPolicy : UCk_AutoTest_Base
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

        // Pre-exclude: both policies should surface the single Aggro.
        auto BeforeAll = utils_aggro_owner::ForEach_Aggro(
            OwnerHandle, ECk_Aggro_ExclusionPolicy::All, FInstancedStruct(), FCk_Lambda_InHandle());
        Assert_Equals_Int(BeforeAll.Num(), 1,
            "Pre-exclude: ExclusionPolicy::All should include the Aggro");

        auto BeforeIgnore = utils_aggro_owner::ForEach_Aggro(
            OwnerHandle, ECk_Aggro_ExclusionPolicy::IgnoreExcluded, FInstancedStruct(), FCk_Lambda_InHandle());
        Assert_Equals_Int(BeforeIgnore.Num(), 1,
            "Pre-exclude: ExclusionPolicy::IgnoreExcluded should include the Aggro");

        utils_aggro::Request_Exclude(AggroHandle);

        // Post-exclude: All still surfaces; IgnoreExcluded drops it.
        auto AfterAll = utils_aggro_owner::ForEach_Aggro(
            OwnerHandle, ECk_Aggro_ExclusionPolicy::All, FInstancedStruct(), FCk_Lambda_InHandle());
        Assert_Equals_Int(AfterAll.Num(), 1,
            "Post-exclude: ExclusionPolicy::All should still include the (now-excluded) Aggro");

        auto AfterIgnore = utils_aggro_owner::ForEach_Aggro(
            OwnerHandle, ECk_Aggro_ExclusionPolicy::IgnoreExcluded, FInstancedStruct(), FCk_Lambda_InHandle());
        Assert_Equals_Int(AfterIgnore.Num(), 0,
            "Post-exclude: ExclusionPolicy::IgnoreExcluded should drop the excluded Aggro");

        FinishSuccess();
    }
}
