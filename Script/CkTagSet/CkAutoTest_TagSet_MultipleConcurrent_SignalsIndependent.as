// Language=angelscript

//============================================================================
// CK TAG SET - AUTOMATION TEST: Two TagSets on different entities don't cross-fire
//============================================================================
//
// Pins the per-entity isolation of OnTagsChanged: two FCk_Handle_TagSet
// entities living concurrently in the world each fire their own
// OnTagsChanged independently, with no cross-contamination.
//
// Each TagSet's signal binding is per-source-entity (the TagSet's own
// entity). The processor broadcasts via the TagSet entity's handle as
// the signal source. Two TagSets on two entities => two independent
// signal channels.
//
// Flow:
//   1. Create child entities A and B under the AutoTest entity.
//   2. Add a TagSet to each, bind OnTagsChanged_A and OnTagsChanged_B
//      to separate counter delegates.
//   3. Request_AddTags on A only.
//   4. WaitOneFrame.
//   5. Assert: A's signal fired exactly once, B's never fired.
//
// Closes the last of four CkTagSet audit gaps (MultipleConcurrent).
//============================================================================

class UCk_AutoTest_TagSet_MultipleConcurrent_SignalsIndependent : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 2.0f;

    private FCk_Handle_TagSet _TagSetA;
    private FCk_Handle_TagSet _TagSetB;
    private int32 _FireCountA = 0;
    private int32 _FireCountB = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto EntityA = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto EntityB = utils_entity_lifetime::Request_CreateEntity(LocalHandle);

        auto Empty = FGameplayTagContainer();
        _TagSetA = utils_tag_set::Add(EntityA, Empty, ECk_Replication::DoesNotReplicate);
        _TagSetB = utils_tag_set::Add(EntityB, Empty, ECk_Replication::DoesNotReplicate);

        utils_tag_set::BindTo_OnTagsChanged(
            _TagSetA,
            FCk_Delegate_TagSet_OnTagsChanged(this, n"OnChanged_A"));
        utils_tag_set::BindTo_OnTagsChanged(
            _TagSetB,
            FCk_Delegate_TagSet_OnTagsChanged(this, n"OnChanged_B"));

        // Mutate ONLY A. B should remain unfired.
        auto AddContainer = FGameplayTagContainer();
        AddContainer.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.TagSet.MultipleConcurrent.OnA"));
        utils_tag_set::Request_AddTags(_TagSetA, AddContainer);

        WaitUntil(n"Check_SignalAFired", n"OnSettled");
    }

    UFUNCTION()
    private void Check_SignalAFired(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_FireCountA >= 1);
    }

    UFUNCTION()
    private void OnChanged_A(
        FCk_Handle_TagSet InTagSet,
        const FGameplayTagContainer&in InTagsAdded,
        const FGameplayTagContainer&in InTagsRemoved)
    {
        _FireCountA += 1;
    }

    UFUNCTION()
    private void OnChanged_B(
        FCk_Handle_TagSet InTagSet,
        const FGameplayTagContainer&in InTagsAdded,
        const FGameplayTagContainer&in InTagsRemoved)
    {
        _FireCountB += 1;
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        Assert_Equals_Int(_FireCountA, 1,
            "TagSet A's OnTagsChanged should fire exactly once (we added one tag)");
        Assert_Equals_Int(_FireCountB, 0,
            "TagSet B's OnTagsChanged should NOT fire - no mutations on B");

        FinishSuccess();
    }
}
