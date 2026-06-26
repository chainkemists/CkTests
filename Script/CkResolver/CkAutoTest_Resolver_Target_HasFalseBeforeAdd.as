// Language=angelscript
//
// CK RESOLVER — AUTOMATION TEST: ResolverTarget Has is false before Add

class UCk_AutoTest_Resolver_Target_HasFalseBeforeAdd : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Entity = utils_entity_lifetime::Request_CreateEntity(InHandle);

        Assert_True(!utils_resolver_target::Has(Entity),
            "Pre-Add: ResolverTarget Has should be false");

        utils_resolver_target::Add(Entity, FCk_Fragment_ResolverTarget_ParamsData());

        Assert_True(utils_resolver_target::Has(Entity),
            "Post-Add: ResolverTarget Has should be true");

        FinishSuccess();
    }
}
