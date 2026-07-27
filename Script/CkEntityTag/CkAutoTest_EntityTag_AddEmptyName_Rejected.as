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
//
// The rejection is SYNCHRONOUS — Add returns early on IsNone without
// enqueueing anything (CkEntityTag_Utils.cpp:138-143) — so there is no
// deferred work to settle for and no event a wait could ever observe. The
// previous version settled a frame before asserting Has(NAME_None) == false,
// which was true from birth and would have stayed true even if the guard were
// deleted: the assertion could not fail. It now runs after a real tag has
// landed on the same entity, which proves the pump processed this entity's
// request array; NAME_None still being absent then means something.
//============================================================================

class UCk_AutoTest_EntityTag_AddEmptyName_Rejected : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle _Entity;
    private FName _RealTag = n"AutoTest_EntityTag_AfterRejectedNone";

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _Entity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);

        Add_Step(          "add NAME_None — must be rejected at the boundary", n"Step_AddNone");
        Add_Step(          "add a real tag to the same entity",                n"Step_AddReal");
        Add_Step_WaitUntil("the real tag lands, proving the pump ran",         n"Check_RealPresent");
        Add_Step(          "assert NAME_None never registered",                n"Step_AssertNoneAbsent");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AddNone(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_entity_tag::Add(_Entity, NAME_None);
    }

    UFUNCTION()
    private void Step_AddReal(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_entity_tag::Add(_Entity, _RealTag);
    }

    UFUNCTION()
    private void Step_AssertNoneAbsent(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_entity_tag::Has(_Entity, NAME_None) == false,
            "After Add(NAME_None), Has(entity, NAME_None) must be false — NAME_None is not a valid tag and Add should reject it");
        Assert_True(utils_entity_tag::Has(_Entity, _RealTag),
            "After a rejected Add(NAME_None), Add of a real tag must still succeed and Has should report it");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_RealPresent(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_entity_tag::Has(_Entity, _RealTag));
    }
}
