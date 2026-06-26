// Language=angelscript
//
// CK RESOLVER — AUTOMATION TEST: ResolverSource Create (owned, with transform)
// The Create factory spawns a new child entity under the owner with the
// ResolverSource feature already added.

class UCk_AutoTest_Resolver_Source_CreateHappyPath : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto SourceHandle = utils_resolver_source::Create(
            Owner,
            FTransform::Identity,
            FCk_Fragment_ResolverSource_ParamsData(),
            ECk_Lifetime::UntilDestroyed);

        Assert_True(utils_handle::Get_IsValid(SourceHandle),
            "ResolverSource Create should return a valid handle");

        FinishSuccess();
    }
}
