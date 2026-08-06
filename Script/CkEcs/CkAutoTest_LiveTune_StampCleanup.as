// Language=angelscript

//============================================================================
// CK LIVETUNE — AUTOMATION TEST: STAMP CLEANUP ON ENTITY DESTROY
//============================================================================
//
// A linked entity's reverse-map registration must unregister when the entity
// destroys (the subsystem listens to the stamp fragment's EnTT on_destroy
// sink), so a later edit of the same (asset, member) dispatches nowhere —
// a stale entry re-applying onto a dead handle must be impossible. The wait
// keys on the actual unregistration, never on a tick count: destroy is a
// multi-tick pipeline.
//============================================================================

class UCk_AutoTest_LiveTune_StampCleanup : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private UCk_LiveTuneTest_TuningAsset _Asset;
    private FCk_Handle _Child;
    private int _PostReplaceBefore;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Self = InHandle;
        _Asset = UCk_LiveTuneTest_Utils::Create_TuningAsset(1, 2);

        _Child = utils_entity_lifetime::Request_CreateEntity(Self);
        UCk_LiveTuneTest_Utils::Add_ReplaceParams(_Child, 1);
        UCk_LiveTuneTest_Utils::Link(_Child, _Asset, n"_ReplaceParams");

        Assert_Equals_Int(UCk_LiveTuneTest_Utils::Get_LinkCount(Self, _Asset, n"_ReplaceParams"), 1,
            "the link should be registered before the destroy");
        Assert_True(UCk_LiveTuneTest_Utils::Get_HasLiveTuneStamp(_Child),
            "the linked entity should carry the LiveTune stamp");

        _PostReplaceBefore = UCk_LiveTuneTest_Utils::Get_PostReplaceCount();

        auto Child = _Child;
        utils_entity_lifetime::Request_DestroyEntity(Child);

        Add_Step_WaitUntil("the link unregisters when the entity destroys", n"Check_LinkGone");
        Add_Step("edits after the destroy dispatch nowhere", n"Step_EditAfterDestroy");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_LinkGone(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Self = InHandle;
        auto Res = OutResult;
        Res.Set(UCk_LiveTuneTest_Utils::Get_LinkCount(Self, _Asset, n"_ReplaceParams") == 0);
    }

    UFUNCTION()
    private void Step_EditAfterDestroy(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Self = InHandle;

        Assert_False(UCk_LiveTuneTest_Utils::Get_HasLiveTuneStamp(_Child),
            "the destroyed entity's stamp must be gone");

        UCk_LiveTuneTest_Utils::Set_ReplaceValue(_Asset, 99);
        UCk_LiveTuneTest_Utils::SimulatePropertyChange(Self, _Asset, n"_ReplaceParams");

        Assert_Equals_Int(UCk_LiveTuneTest_Utils::Get_PostReplaceCount() - _PostReplaceBefore, 0,
            "no dispatch may reach a destroyed entity's link");
    }
}
