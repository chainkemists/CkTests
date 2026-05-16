// Language=angelscript
//
// CK ENTITY TAG — AUTOMATION TEST: TryGet_Tag on entity without fragment
// Calling TryGet_Tag on an entity that never had EntityTag added returns
// NAME_None (graceful default; no ensure).

class UCk_AutoTest_EntityTag_TryGetTagNoTagReturnsNone : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        // Deliberately do not call Add — pin the no-fragment-present contract.
        Assert_True(utils_entity_tag::TryGet_Tag(LocalHandle) == n"None",
            "TryGet_Tag on an entity without EntityTag should return NAME_None");

        FinishSuccess();
    }
}
