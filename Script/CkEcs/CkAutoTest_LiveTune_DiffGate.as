// Language=angelscript

//============================================================================
// CK LIVETUNE — AUTOMATION TEST: VALUE-DIFF GATE SUPPRESSION
//============================================================================
//
// The per-(asset, member) value-diff cache is mandatory: the AS hot-reload
// heal re-inits EVERY asset literal on every script save, so a change
// notification whose value did not actually change must never dispatch.
// Covers all three cache states: seeded-at-Link (the full-heal shape, before
// any dispatch), a real change (dispatches once), and a repeat notification
// of an already-dispatched value (suppressed).
//============================================================================

class UCk_AutoTest_LiveTune_DiffGate : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Self = InHandle;
        auto Asset = UCk_LiveTuneTest_Utils::Create_TuningAsset(5, 5);

        auto Entity = utils_entity_lifetime::Request_CreateEntity(Self);
        UCk_LiveTuneTest_Utils::Add_ReplaceParams(Entity, 5);
        UCk_LiveTuneTest_Utils::Link(Entity, Asset, n"_ReplaceParams");

        auto PostReplaceBefore = UCk_LiveTuneTest_Utils::Get_PostReplaceCount();

        UCk_LiveTuneTest_Utils::SimulatePropertyChange(Self, Asset, n"_ReplaceParams");
        Assert_Equals_Int(UCk_LiveTuneTest_Utils::Get_PostReplaceCount() - PostReplaceBefore, 0,
            "an unchanged value must not dispatch — the cache is seeded at Link (full-heal suppression)");

        UCk_LiveTuneTest_Utils::Set_ReplaceValue(Asset, 9);
        UCk_LiveTuneTest_Utils::SimulatePropertyChange(Self, Asset, n"_ReplaceParams");
        Assert_Equals_Int(UCk_LiveTuneTest_Utils::Get_PostReplaceCount() - PostReplaceBefore, 1,
            "a real value change should dispatch exactly once");
        Assert_Equals_Int(UCk_LiveTuneTest_Utils::Get_ReplaceParamsValue(Entity), 9,
            "the changed value should land on the entity");

        UCk_LiveTuneTest_Utils::SimulatePropertyChange(Self, Asset, n"_ReplaceParams");
        Assert_Equals_Int(UCk_LiveTuneTest_Utils::Get_PostReplaceCount() - PostReplaceBefore, 1,
            "re-notifying an already-dispatched value must be suppressed");

        FinishSuccess();
    }
}
