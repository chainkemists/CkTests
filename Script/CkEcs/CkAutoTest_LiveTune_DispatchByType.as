// Language=angelscript

//============================================================================
// CK LIVETUNE — AUTOMATION TEST: REGISTRY DISPATCH BY TYPE (FULL PIPELINE)
//============================================================================
//
// Two entities link two different members of one tuning asset (a ViaReplace
// params type and a ViaRequest params type). A simulated property change on
// one member must dispatch through THAT member's handler only: the fresh
// value lands on the linked entity, and the other tier's handler never runs.
// The simulate seam broadcasts a real FPropertyChangedEvent through
// FCoreUObjectDelegates, so this covers subscription -> member extraction ->
// reverse map -> type-keyed handler dispatch end to end.
//============================================================================

class UCk_AutoTest_LiveTune_DispatchByType : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Self = InHandle;
        auto Asset = UCk_LiveTuneTest_Utils::Create_TuningAsset(1, 2);

        auto EntityA = utils_entity_lifetime::Request_CreateEntity(Self);
        UCk_LiveTuneTest_Utils::Add_ReplaceParams(EntityA, 1);
        UCk_LiveTuneTest_Utils::Link(EntityA, Asset, n"_ReplaceParams");

        auto EntityB = utils_entity_lifetime::Request_CreateEntity(Self);
        UCk_LiveTuneTest_Utils::Link(EntityB, Asset, n"_RequestParams");

        Assert_Equals_Int(UCk_LiveTuneTest_Utils::Get_LinkCount(Self, Asset, n"_ReplaceParams"), 1,
            "linking _ReplaceParams should register exactly one entity");
        Assert_Equals_Int(UCk_LiveTuneTest_Utils::Get_LinkCount(Self, Asset, n"_RequestParams"), 1,
            "linking _RequestParams should register exactly one entity");
        Assert_True(UCk_LiveTuneTest_Utils::Get_HasLiveTuneStamp(EntityA),
            "a linked entity should carry the LiveTune stamp");

        auto PostReplaceBefore = UCk_LiveTuneTest_Utils::Get_PostReplaceCount();
        auto ViaRequestBefore = UCk_LiveTuneTest_Utils::Get_ViaRequestCount();

        UCk_LiveTuneTest_Utils::Set_ReplaceValue(Asset, 42);
        UCk_LiveTuneTest_Utils::SimulatePropertyChange(Self, Asset, n"_ReplaceParams");

        Assert_Equals_Int(UCk_LiveTuneTest_Utils::Get_ReplaceParamsValue(EntityA), 42,
            "ViaReplace dispatch should land the fresh value on the linked entity");
        Assert_Equals_Int(UCk_LiveTuneTest_Utils::Get_PostReplaceCount() - PostReplaceBefore, 1,
            "the PostReplace fixup should run exactly once");
        Assert_Equals_Int(UCk_LiveTuneTest_Utils::Get_ViaRequestCount() - ViaRequestBefore, 0,
            "a _ReplaceParams edit must never reach the ViaRequest handler");

        UCk_LiveTuneTest_Utils::Set_RequestValue(Asset, 7);
        UCk_LiveTuneTest_Utils::SimulatePropertyChange(Self, Asset, n"_RequestParams");

        Assert_Equals_Int(UCk_LiveTuneTest_Utils::Get_ViaRequestCount() - ViaRequestBefore, 1,
            "a _RequestParams edit should dispatch to the ViaRequest handler exactly once");
        Assert_Equals_Int(UCk_LiveTuneTest_Utils::Get_RequestParamsValue(EntityB), 7,
            "the ViaRequest handler should receive and apply the fresh value");
        Assert_Equals_Int(UCk_LiveTuneTest_Utils::Get_ReplaceParamsValue(EntityA), 42,
            "a _RequestParams edit must not touch the ViaReplace entity");

        FinishSuccess();
    }
}
