// Language=angelscript

//============================================================================
// CK LIVETUNE — AUTOMATION TEST: AS-RELOAD HEAL TRANSPORT
//============================================================================
//
// The AngelScript hot reload re-initializes EVERY asset literal in place on
// every script save, with no per-member signal — LiveTune closes that gap
// with the OnAssetsReinitialized delegate fired at the end of the heal sweep.
// Driven here through the REAL delegate: a heal with nothing changed must be
// fully suppressed by the value-diff cache (the world-wide-rebuild storm the
// cache exists to prevent), and a heal with one changed member dispatches
// exactly that member. Linking goes through utils_live_tune — the generated
// AS surface — so this test is also the tri-environment proof for Link.
//============================================================================

class UCk_AutoTest_LiveTune_AsReloadHeal : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Self = InHandle;
        auto Asset = UCk_LiveTuneTest_Utils::Create_TuningAsset(5, 2);

        auto ReplaceEntity = utils_entity_lifetime::Request_CreateEntity(Self);
        UCk_LiveTuneTest_Utils::Add_ReplaceParams(ReplaceEntity, 5);
        utils_live_tune::Link(ReplaceEntity, Asset, n"_ReplaceParams");

        auto RequestEntity = utils_entity_lifetime::Request_CreateEntity(Self);
        utils_live_tune::Link(RequestEntity, Asset, n"_RequestParams");

        Assert_Equals_Int(UCk_LiveTuneTest_Utils::Get_LinkCount(Self, Asset, n"_ReplaceParams"), 1,
            "utils_live_tune::Link should register exactly like the C++ surface");

        auto PostReplaceBefore = UCk_LiveTuneTest_Utils::Get_PostReplaceCount();
        auto ViaRequestBefore = UCk_LiveTuneTest_Utils::Get_ViaRequestCount();

        UCk_LiveTuneTest_Utils::Broadcast_AssetsReinitialized(Asset);
        Assert_Equals_Int(UCk_LiveTuneTest_Utils::Get_PostReplaceCount() - PostReplaceBefore, 0,
            "a heal with nothing changed must be fully suppressed");
        Assert_Equals_Int(UCk_LiveTuneTest_Utils::Get_ViaRequestCount() - ViaRequestBefore, 0,
            "a heal with nothing changed must not reach any tier");

        UCk_LiveTuneTest_Utils::Set_ReplaceValue(Asset, 9);
        UCk_LiveTuneTest_Utils::Broadcast_AssetsReinitialized(Asset);

        Assert_Equals_Int(UCk_LiveTuneTest_Utils::Get_ReplaceParamsValue(ReplaceEntity), 9,
            "the healed member's fresh value should land on the linked entity");
        Assert_Equals_Int(UCk_LiveTuneTest_Utils::Get_PostReplaceCount() - PostReplaceBefore, 1,
            "only the changed member dispatches");
        Assert_Equals_Int(UCk_LiveTuneTest_Utils::Get_ViaRequestCount() - ViaRequestBefore, 0,
            "the unchanged member stays suppressed through the heal");

        FinishSuccess();
    }
}
