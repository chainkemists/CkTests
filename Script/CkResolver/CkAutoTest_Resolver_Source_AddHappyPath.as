// Language=angelscript
//
// CK RESOLVER — AUTOMATION TEST: ResolverSource Add happy path
// Add the ResolverSource feature with an empty resolution-phase list; the
// returned handle is valid.

class UCk_AutoTest_Resolver_Source_AddHappyPath : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Entity = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto Params = FCk_ResolverSource_Spec();
        auto SourceHandle = utils_resolver_source::Add(Entity, Params);

        Assert_True(utils_handle::Get_IsValid(SourceHandle),
            "ResolverSource Add should return a valid handle");
        Assert_True(utils_resolver_source::Has(Entity),
            "ResolverSource Has should return true after Add");

        FinishSuccess();
    }
}
