// Language=angelscript

//============================================================================
// CK LIVETUNE — AUTOMATION TEST: Scope::Entity PROVENANCE REFUSAL
//============================================================================
//
// Scope::Entity rebuilds respawn the whole entity from its spawn recipe —
// which only RuntimeSpawned entities carry. A ConstructSpawned entity (as
// created here) must be refused LOUDLY, with zero partial state: no destroy,
// no queued rebuild, the link untouched.
//============================================================================

class UCk_AutoTest_LiveTune_RebuildScopeEntity_Refusal : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Self = InHandle;
        auto Asset = UCk_LiveTuneTest_Utils::Create_TuningAsset(0, 0);

        auto Entity = utils_entity_lifetime::Request_CreateEntity(Self);
        UCk_LiveTuneTest_Utils::Link(Entity, Asset, n"_EntityScopeParams");

        auto PendingBefore = UCk_LiveTuneTest_Utils::Get_PendingRebuildCount(Self);

        UCk_LiveTuneTest_Utils::Set_EntityScopeValue(Asset, 9);
        UCk_LiveTuneTest_Utils::SimulatePropertyChange(Self, Asset, n"_EntityScopeParams");

        Assert_Equals_Int(UCk_LiveTuneTest_Utils::Get_PendingRebuildCount(Self) - PendingBefore, 0,
            "a refused Scope::Entity rebuild must queue nothing");
        Assert_True(ck::IsValid(Entity),
            "a refused Scope::Entity rebuild must not destroy the entity");
        Assert_Equals_Int(UCk_LiveTuneTest_Utils::Get_LinkCount(Self, Asset, n"_EntityScopeParams"), 1,
            "the link must be untouched by the refusal");

        FinishSuccess();
    }
}

class ACk_AutoTest_LiveTune_RebuildScopeEntity_Refusal_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_LiveTune_RebuildScopeEntity_Refusal;

    // The refusal is a deliberate CK ensure (Error log); whitelist it so the automation framework
    // doesn't fail the test on its own expected output.
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("Scope::Entity rebuild refused");
        return Out;
    }
}
