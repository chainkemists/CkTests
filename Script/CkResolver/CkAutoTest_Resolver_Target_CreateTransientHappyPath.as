// Language=angelscript
//
// CK RESOLVER — AUTOMATION TEST: ResolverTarget Create_Transient

class UCk_AutoTest_Resolver_Target_CreateTransientHappyPath : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto TargetHandle = utils_resolver_target::Create_Transient(
            FTransform::Identity,
            FCk_Fragment_ResolverTarget_ParamsData(),
            ECk_Lifetime::UntilDestroyed);

        Assert_True(utils_handle::Get_IsValid(TargetHandle),
            "ResolverTarget Create_Transient should return a valid handle");

        FinishSuccess();
    }
}
