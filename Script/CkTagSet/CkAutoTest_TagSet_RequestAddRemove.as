// Language=angelscript

//============================================================================
// CK TAG SET — AUTOMATION TEST: REQUEST ADD AND REMOVE TAGS
//============================================================================
//
// Verifies the runtime mutation API on a TagSet:
//   1. Add a TagSet with one initial tag (Flammable).
//   2. Request_AddTags adds two more tags (Heavy, Sticky).
//   3. Poll until Get_NumTags == 3 and HasTag returns true for the new ones.
//   4. Request_RemoveTags removes Heavy.
//   5. Poll until Get_NumTags == 2 and HasTag(Heavy) == false; Flammable
//      and Sticky remain.
//
// Pins down the deferred mutation contract — both operations are
// authority-only request structures.
//============================================================================

class UCk_AutoTest_TagSet_RequestAddRemove : UCk_AutoTest_Base
{
    private FCk_Handle_TagSet _TagSet;
    private FGameplayTag _Flammable;
    private FGameplayTag _Heavy;
    private FGameplayTag _Sticky;
    private FGameplayTagContainer _AddContainer;
    private FGameplayTagContainer _RemoveContainer;

    private bool _AddObserved = false;
    private bool _RemoveRequested = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        _Flammable = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.TagSet.Flammable");
        _Heavy     = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.TagSet.Heavy");
        _Sticky    = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.TagSet.Sticky");

        auto Initial = FGameplayTagContainer();
        Initial.AddTag(_Flammable);
        _TagSet = utils_tag_set::Add(LocalHandle, Initial, ECk_Replication::DoesNotReplicate);

        _AddContainer = FGameplayTagContainer();
        _AddContainer.AddTag(_Heavy);
        _AddContainer.AddTag(_Sticky);
        utils_tag_set::Request_AddTags(_TagSet, _AddContainer);

        _RemoveContainer = FGameplayTagContainer();
        _RemoveContainer.AddTag(_Heavy);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (!_AddObserved)
        {
            if (utils_tag_set::Get_NumTags(_TagSet) >= 3 &&
                utils_tag_set::HasTag(_TagSet, _Heavy) &&
                utils_tag_set::HasTag(_TagSet, _Sticky))
            {
                _AddObserved = true;
                Assert_Equals_Int(utils_tag_set::Get_NumTags(_TagSet), 3,
                    "After Request_AddTags(Heavy+Sticky), tag count should be 3 (Flammable+Heavy+Sticky)");

                utils_tag_set::Request_RemoveTags(_TagSet, _RemoveContainer);
                _RemoveRequested = true;
            }
            return;
        }

        if (_RemoveRequested && !utils_tag_set::HasTag(_TagSet, _Heavy))
        {
            Assert_Equals_Int(utils_tag_set::Get_NumTags(_TagSet), 2,
                "After Request_RemoveTags(Heavy), tag count should drop to 2 (Flammable+Sticky)");
            Assert_True(utils_tag_set::HasTag(_TagSet, _Flammable),
                "Flammable should still be present after removing Heavy");
            Assert_True(utils_tag_set::HasTag(_TagSet, _Sticky),
                "Sticky should still be present after removing Heavy");
            FinishSuccess();
        }
    }
}
