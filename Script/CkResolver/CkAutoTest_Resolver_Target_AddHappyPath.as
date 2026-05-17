// Language=angelscript
//
// CK RESOLVER — AUTOMATION TEST: ResolverTarget Add happy path

class UCk_AutoTest_Resolver_Target_AddHappyPath : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto Params = FCk_Fragment_ResolverTarget_ParamsData();
        auto TargetHandle = utils_resolver_target::Add(Entity, Params);

        Assert_True(utils_handle::Get_IsValid(TargetHandle),
            "ResolverTarget Add should return a valid handle");
        Assert_True(utils_resolver_target::Has(Entity),
            "ResolverTarget Has should return true after Add");

        FinishSuccess();
    }
}
