// Language=angelscript
//
// CK RESOLVER — AUTOMATION TEST: ResolverSource Has is false before Add

class UCk_AutoTest_Resolver_Source_HasFalseBeforeAdd : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Entity = utils_entity_lifetime::Request_CreateEntity(InHandle);

        Assert_True(!utils_resolver_source::Has(Entity),
            "Pre-Add: ResolverSource Has should be false on a fresh entity");

        utils_resolver_source::Add(Entity, FCk_Fragment_ResolverSource_ParamsData());

        Assert_True(utils_resolver_source::Has(Entity),
            "Post-Add: ResolverSource Has should be true");

        FinishSuccess();
    }
}
