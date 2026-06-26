// Language=angelscript
//
// CK ENTITY EXTENSION — AUTOMATION TEST: Remove happy path
// Add then Remove an extension; after one frame the owner's ForEach list
// no longer includes the removed extension.

class UCk_AutoTest_EntityExtension_RemoveHappyPath : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle _Owner;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto Child = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto Extension = utils_entity_extension::Add(_Owner, Child);

        auto Before = utils_entity_extension::ForEach_EntityExtension(
            _Owner, FInstancedStruct(), FCk_Lambda_InHandle());
        Assert_Equals_Int(Before.Num(), 1,
            "Pre-remove: owner should report 1 extension");

        utils_entity_extension::Remove(_Owner, Extension);

        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto After = utils_entity_extension::ForEach_EntityExtension(
            _Owner, FInstancedStruct(), FCk_Lambda_InHandle());
        Assert_Equals_Int(After.Num(), 0,
            "Post-remove: owner should report 0 extensions");

        FinishSuccess();
    }
}
