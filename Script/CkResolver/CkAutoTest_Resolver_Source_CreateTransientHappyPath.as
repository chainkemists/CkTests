// Language=angelscript
//
// CK RESOLVER - AUTOMATION TEST: ResolverSource Create_Transient
// The transient factory spawns a ResolverSource under the world's transient
// owner. WorldContextObject is auto-supplied by the AS binding.

class UCk_AutoTest_Resolver_Source_CreateTransientHappyPath : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto SourceHandle = utils_resolver_source::Create_Transient(
            FTransform::Identity,
            FCk_Fragment_ResolverSource_ParamsData(),
            ECk_Lifetime::UntilDestroyed);

        Assert_True(utils_handle::Get_IsValid(SourceHandle),
            "ResolverSource Create_Transient should return a valid handle");

        FinishSuccess();
    }
}
