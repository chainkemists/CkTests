// Language=angelscript

//============================================================================
// CK ENTITY TAG — AUTOMATION TEST: ADD(NAME_None) IS REJECTED
//============================================================================
//
// Pins the boundary validation on Add: passing NAME_None (the empty FName)
// is rejected at the API boundary — no fragment is attached, Has returns
// false, and the entity is still pristine enough to accept a real tag
// afterwards.
//
// Prevents accidental "everyone has NAME_None" interference where an
// unset FName would otherwise register as a valid tag query key, polluting
// ForEach_Entity(NAME_None) with every entity that ever had EntityTag
// Add called with a default-initialised name.
//============================================================================

class UCk_AutoTest_EntityTag_AddEmptyName_Rejected : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle _Entity;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        _Entity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);

        utils_entity_tag::Add(_Entity, NAME_None);

        WaitOneFrame(n"AfterRejectedNoneAdd");
    }

    UFUNCTION()
    private void AfterRejectedNoneAdd(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_entity_tag::Has(_Entity, NAME_None) == false,
            "After Add(NAME_None), Has(entity, NAME_None) must be false — NAME_None is not a valid tag and Add should reject it");

        // Entity should still be usable for a valid tag after a rejected
        // NAME_None Add — the rejection must not poison the entity.
        utils_entity_tag::Add(_Entity, n"AutoTest_EntityTag_AfterRejectedNone");
        WaitOneFrame(n"AfterRealAdd");
    }

    UFUNCTION()
    private void AfterRealAdd(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_entity_tag::Has(_Entity, n"AutoTest_EntityTag_AfterRejectedNone"),
            "After a rejected Add(NAME_None), Add of a real tag must still succeed and Has should report it");

        FinishSuccess();
    }
}
