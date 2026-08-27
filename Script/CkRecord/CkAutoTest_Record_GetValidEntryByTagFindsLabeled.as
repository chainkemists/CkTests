// Language=angelscript

//============================================================================
// CK RECORD - AUTOMATION TEST: GET VALID ENTRY BY TAG
//============================================================================
//
// Pins the label-based lookup contract: an entry connected to a Record with
// a specific GameplayLabel must be retrievable via `Get_ValidEntry_ByTag`
// using that label. The mechanism every feature module relies on to
// distinguish "which BGM track" from "which SFX track" within one Record.
//
// Setup:
//   - Owner with Record feature.
//   - Connect two labeled entries: TagA and TagB.
//   - Query Get_ValidEntry_ByTag(TagA) - returns EntryA.
//   - Query Get_ValidEntry_ByTag(TagB) - returns EntryB.
//   - Query for a non-existent tag - returns invalid handle.
//============================================================================

class UCk_AutoTest_Record_GetValidEntryByTagFindsLabeled : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto RecordOwner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        utils_record_of_entities::Add(RecordOwner);

        auto TagA = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Record.ByTag.A");
        auto TagB = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Record.ByTag.B");
        auto TagMissing = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Record.ByTag.Missing");

        auto EntryA = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        utils_gameplay_label::Add(EntryA, TagA);
        utils_record_of_entities::Request_Connect(RecordOwner, EntryA);

        auto EntryB = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        utils_gameplay_label::Add(EntryB, TagB);
        utils_record_of_entities::Request_Connect(RecordOwner, EntryB);

        auto FoundA = utils_record_of_entities::Get_ValidEntry_ByTag(RecordOwner, TagA);
        Assert_True(utils_handle::IsEqual(FoundA, EntryA),
            "Get_ValidEntry_ByTag(TagA) should return EntryA");

        auto FoundB = utils_record_of_entities::Get_ValidEntry_ByTag(RecordOwner, TagB);
        Assert_True(utils_handle::IsEqual(FoundB, EntryB),
            "Get_ValidEntry_ByTag(TagB) should return EntryB");

        auto FoundMissing = utils_record_of_entities::Get_ValidEntry_ByTag(RecordOwner, TagMissing);
        Assert_True(!utils_handle::Get_IsValid(FoundMissing),
            "Get_ValidEntry_ByTag for an unconnected tag should return an invalid handle");

        FinishSuccess();
    }
}
