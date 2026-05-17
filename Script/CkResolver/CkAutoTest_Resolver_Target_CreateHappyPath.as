// Language=angelscript
//
// CK RESOLVER — AUTOMATION TEST: ResolverTarget Create (owned, with transform)

class UCk_AutoTest_Resolver_Target_CreateHappyPath : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto TargetHandle = utils_resolver_target::Create(
            Owner,
            FTransform::Identity,
            FCk_Fragment_ResolverTarget_ParamsData(),
            ECk_Lifetime::UntilDestroyed);

        Assert_True(utils_handle::Get_IsValid(TargetHandle),
            "ResolverTarget Create should return a valid handle");

        FinishSuccess();
    }
}
