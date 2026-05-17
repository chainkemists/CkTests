// Language=angelscript
//
// CK ENTITY EXTENSION — AUTOMATION TEST: Remove leaves siblings intact
// Attach two extensions A and B; remove A; B is still reported in ForEach.

class UCk_AutoTest_EntityExtension_RemoveLeavesOthers : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle _Owner;
    private FCk_Handle_EntityExtension _ExtA;
    private FCk_Handle_EntityExtension _ExtB;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto ChildA = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto ChildB = utils_entity_lifetime::Request_CreateEntity(InHandle);

        _ExtA = utils_entity_extension::Add(_Owner, ChildA);
        _ExtB = utils_entity_extension::Add(_Owner, ChildB);

        utils_entity_extension::Remove(_Owner, _ExtA);

        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Remaining = utils_entity_extension::ForEach_EntityExtension(
            _Owner, FInstancedStruct(), FCk_Lambda_InHandle());

        Assert_Equals_Int(Remaining.Num(), 1,
            "After removing one of two extensions, exactly one should remain");
        Assert_True(utils_handle::IsEqual(Remaining[0], _ExtB),
            "The remaining extension should be the unremoved one (ExtB)");

        FinishSuccess();
    }
}
