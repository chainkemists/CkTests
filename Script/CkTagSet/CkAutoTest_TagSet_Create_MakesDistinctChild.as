// Language=angelscript

//============================================================================
// CK TAG SET - AUTOMATION TEST: TagSet CREATE MAKES A DISTINCT CHILD
//============================================================================
//
// Verifies the child-making Create verb (counterpart to the stamp-self Add):
// Create(owner, ...) spawns a NEW child entity carrying the feature - the
// returned handle is valid, the child carries the feature (its typed-handle
// getters return the seeded data), and the owner does NOT carry the feature
// (proving Create is child-making, not stamp-self like Add).
//
// NOTE: UCk_Utils_TagSet_UE::Has is a plain C++ static (no UFUNCTION), so it
// is not bound to AngelScript. Feature-presence on the child is therefore
// asserted via Get_NumTags/HasTag on the typed FCk_Handle_TagSet, and the
// owner-is-distinct property via DoCast(Owner) returning an empty optional.
//============================================================================

class UCk_AutoTest_TagSet_Create_MakesDistinctChild : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto FlammableTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.TagSet.Flammable");
        auto HeavyTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.TagSet.Heavy");

        auto Initial = FGameplayTagContainer();
        Initial.AddTag(FlammableTag);
        Initial.AddTag(HeavyTag);

        auto Child = utils_tag_set::Create(Owner, Initial, ECk_Replication::DoesNotReplicate);

        Assert_True(ck::IsValid(Child),
            "Create should return a valid FCk_Handle_TagSet");

        Assert_Equals_Int(utils_tag_set::Get_NumTags(Child), 2,
            "The created child entity should carry the TagSet feature seeded with the 2 initial tags");
        Assert_True(utils_tag_set::HasTag(Child, FlammableTag),
            "The child's TagSet should contain the first initial tag");

        Assert_True(!utils_tag_set::DoCast(Owner).IsSet(),
            "The owner must NOT carry the feature - Create is child-making, not stamp-self");

        FinishSuccess();
    }
}
