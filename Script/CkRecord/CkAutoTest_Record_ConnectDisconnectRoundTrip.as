// Language=angelscript

//============================================================================
// CK RECORD — AUTOMATION TEST: CONNECT + DISCONNECT ROUND-TRIP
//============================================================================
//
// Pins the basic Record-of-Entities lifecycle: an entry connected to a
// Record should show up in `Get_ContainsEntry`; after Disconnect it should
// be gone. The contract every feature module's Record-of-X depends on.
//
// Setup:
//   - Create an owner entity and add the generic Record feature.
//   - Create a labeled child entry entity (label required by default policy).
//   - Connect → ContainsEntry true.
//   - Disconnect → ContainsEntry false.
//============================================================================

class UCk_AutoTest_Record_ConnectDisconnectRoundTrip : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto RecordOwner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        utils_record_of_entities::Add(RecordOwner);

        auto Entry = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        utils_gameplay_label::Add(Entry,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Record.Entry.A"));

        Assert_True(!utils_record_of_entities::Get_ContainsEntry(RecordOwner, Entry),
            "Record should NOT contain the entry before Connect");

        utils_record_of_entities::Request_Connect(RecordOwner, Entry);

        Assert_True(utils_record_of_entities::Get_ContainsEntry(RecordOwner, Entry),
            "Record should contain the entry after Request_Connect");

        utils_record_of_entities::Request_Disconnect(RecordOwner, Entry);

        Assert_True(!utils_record_of_entities::Get_ContainsEntry(RecordOwner, Entry),
            "Record should NOT contain the entry after Request_Disconnect");

        FinishSuccess();
    }
}
