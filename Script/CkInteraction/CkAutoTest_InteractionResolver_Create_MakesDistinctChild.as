// Language=angelscript

//============================================================================
// CK INTERACTION — AUTOMATION TEST: InteractionResolver CREATE MAKES A DISTINCT CHILD
//============================================================================
//
// Verifies the child-making Create verb (counterpart to the stamp-self Add):
// Create(owner, ...) spawns a NEW child entity carrying the feature — the
// returned handle is valid, Has(child) is true, and Has(owner) is FALSE
// (proving Create is child-making, not stamp-self like Add).
//============================================================================

class UCk_AutoTest_InteractionResolver_Create_MakesDistinctChild : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto Channels = TArray<FGameplayTag>();
        Channels.Add(interaction_gym_helpers::DefaultChannel());
        Channels.Add(interaction_gym_helpers::SecondaryChannel());

        auto Mapping = FCk_InteractionResolver_IntentChannelMapping(
            interaction_gym_helpers::UseIntent(),
            Channels
        );
        Mapping.Set_DistanceSorting(ECk_InteractionResolver_DistanceSorting::Enabled);
        Mapping.Set_MaxConcurrentInteractions(1);

        auto Mappings = TArray<FCk_InteractionResolver_IntentChannelMapping>();
        Mappings.Add(Mapping);

        auto ResolverParams = FCk_InteractionResolver_Spec(Mappings);

        auto Child = utils_interaction_resolver::Create(Owner, ResolverParams);
        auto ChildEntity = FCk_Handle(Child);

        Assert_True(ck::IsValid(Child),
            "Create should return a valid FCk_Handle_InteractionResolver");
        Assert_True(utils_interaction_resolver::Has(ChildEntity),
            "The created child entity should carry the InteractionResolver feature");
        Assert_True(!utils_interaction_resolver::Has(Owner),
            "The owner must NOT carry the feature — Create is child-making, not stamp-self");

        FinishSuccess();
    }
}
