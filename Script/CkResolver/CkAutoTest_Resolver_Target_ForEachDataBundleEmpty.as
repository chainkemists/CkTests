// Language=angelscript
//
// CK RESOLVER — AUTOMATION TEST: ResolverTarget ForEach_ResolverDataBundle empty by default

class UCk_AutoTest_Resolver_Target_ForEachDataBundleEmpty : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Entity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto TargetHandle = utils_resolver_target::Add(Entity, FCk_ResolverTarget_Spec());

        auto Bundles = utils_resolver_target::ForEach_ResolverDataBundle(
            TargetHandle, FInstancedStruct(), FCk_Lambda_InHandle());

        Assert_Equals_Int(Bundles.Num(), 0,
            "ResolverTarget should have no DataBundles immediately after Add");

        FinishSuccess();
    }
}
