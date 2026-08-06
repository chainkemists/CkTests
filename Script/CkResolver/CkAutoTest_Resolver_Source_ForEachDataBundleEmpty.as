// Language=angelscript
//
// CK RESOLVER — AUTOMATION TEST: ResolverSource ForEach_ResolverDataBundle empty by default
// A freshly added ResolverSource has no DataBundles attached; ForEach returns
// an empty array.

class UCk_AutoTest_Resolver_Source_ForEachDataBundleEmpty : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Entity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto SourceHandle = utils_resolver_source::Add(Entity, FCk_ResolverSource_Spec());

        auto Bundles = utils_resolver_source::ForEach_ResolverDataBundle(
            SourceHandle, FInstancedStruct(), FCk_Lambda_InHandle());

        Assert_Equals_Int(Bundles.Num(), 0,
            "ResolverSource should have no DataBundles immediately after Add");

        FinishSuccess();
    }
}
