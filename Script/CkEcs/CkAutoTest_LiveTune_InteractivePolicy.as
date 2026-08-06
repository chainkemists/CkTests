// Language=angelscript

//============================================================================
// CK LIVETUNE — AUTOMATION TEST: INTERACTIVE CHANGE-TYPE POLICY
//============================================================================
//
// Slider scrubs broadcast EPropertyChangeType::Interactive once per tick; a
// drag must never become a rebuild storm. Policy under test: Interactive
// changes dispatch to ViaReplace handlers ONLY (that IS the live-tuning
// feel); the withheld tiers get the value on the final ValueSet commit.
//============================================================================

class UCk_AutoTest_LiveTune_InteractivePolicy : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Self = InHandle;
        auto Asset = UCk_LiveTuneTest_Utils::Create_TuningAsset(1, 2);

        auto ReplaceEntity = utils_entity_lifetime::Request_CreateEntity(Self);
        UCk_LiveTuneTest_Utils::Add_ReplaceParams(ReplaceEntity, 1);
        UCk_LiveTuneTest_Utils::Link(ReplaceEntity, Asset, n"_ReplaceParams");

        auto RequestEntity = utils_entity_lifetime::Request_CreateEntity(Self);
        UCk_LiveTuneTest_Utils::Link(RequestEntity, Asset, n"_RequestParams");

        auto PostReplaceBefore = UCk_LiveTuneTest_Utils::Get_PostReplaceCount();
        auto ViaRequestBefore = UCk_LiveTuneTest_Utils::Get_ViaRequestCount();

        UCk_LiveTuneTest_Utils::Set_RequestValue(Asset, 3);
        UCk_LiveTuneTest_Utils::SimulatePropertyChange_Interactive(Self, Asset, n"_RequestParams");
        Assert_Equals_Int(UCk_LiveTuneTest_Utils::Get_ViaRequestCount() - ViaRequestBefore, 0,
            "an Interactive scrub must not reach a ViaRequest handler");

        UCk_LiveTuneTest_Utils::SimulatePropertyChange(Self, Asset, n"_RequestParams");
        Assert_Equals_Int(UCk_LiveTuneTest_Utils::Get_ViaRequestCount() - ViaRequestBefore, 1,
            "the final commit should deliver the scrubbed value to the ViaRequest handler");
        Assert_Equals_Int(UCk_LiveTuneTest_Utils::Get_RequestParamsValue(RequestEntity), 3,
            "the committed value should land on the entity");

        UCk_LiveTuneTest_Utils::Set_ReplaceValue(Asset, 4);
        UCk_LiveTuneTest_Utils::SimulatePropertyChange_Interactive(Self, Asset, n"_ReplaceParams");
        Assert_Equals_Int(UCk_LiveTuneTest_Utils::Get_PostReplaceCount() - PostReplaceBefore, 1,
            "an Interactive scrub SHOULD dispatch to ViaReplace — that is the live-tuning feel");
        Assert_Equals_Int(UCk_LiveTuneTest_Utils::Get_ReplaceParamsValue(ReplaceEntity), 4,
            "the scrubbed value should land on the ViaReplace entity immediately");

        FinishSuccess();
    }
}
