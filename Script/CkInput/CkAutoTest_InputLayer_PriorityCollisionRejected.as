// Language=angelscript

//============================================================================
// CK INPUT LAYER - AUTOMATION TEST: A PRIORITY COLLISION IS REJECTED LOUDLY
//============================================================================
//
// Entities have no inherent order, so a layer's place in its stack is an
// explicit priority. Two layers sharing one on the same source would make
// arbitration order undefined - which is precisely the defect already sitting
// in the Slate preprocessor list, where two registrations at index 0 quietly
// tie-break by luck.
//
// So the second registration is REJECTED: it ensures, returns an invalid
// handle, and composes nothing. Atomicity is what the last three legs check
// the incumbent still holds the slot, the same priority is free on a DIFFERENT
// source (the collision is per-stack, not global), and a different priority on
// the same source is still accepted.
//============================================================================

class UCk_AutoTest_InputLayer_PriorityCollisionRejected : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle             _Owner;
    private FCk_Handle_InputSource _Source;
    private FCk_Handle_InputSource _OtherSource;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto SourceOwner      = utils_entity_lifetime::Request_CreateEntity(_Owner);
        auto OtherSourceOwner = utils_entity_lifetime::Request_CreateEntity(_Owner);

        _Source      = utils_input_source::Add(SourceOwner,      FCk_Fragment_InputSource_ParamsData(0));
        _OtherSource = utils_input_source::Add(OtherSourceOwner, FCk_Fragment_InputSource_ParamsData(1));

        auto Incumbent = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 50));

        Assert_True(ck::IsValid(Incumbent),
            "the first layer to claim a priority must be accepted");

        auto Contender = utils_entity_lifetime::Request_CreateEntity(_Owner);
        auto Rejected  = utils_input_layer::Add(Contender, FCk_Fragment_InputLayer_ParamsData(_Source, 50));

        Assert_True(!ck::IsValid(Rejected),
            "a second layer claiming a live priority on the same source must be rejected");
        Assert_True(utils_input_layer::TryGet_LayerWithPriority(_Source, 50) == Incumbent,
            "a rejected registration must leave the incumbent holding the priority");
        Assert_Equals_Int(utils_input_layer::Get_NumCaptures(Incumbent), 0,
            "a rejected registration must not disturb the incumbent's capture set");

        auto OnOtherSource = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_OtherSource, 50));

        Assert_True(ck::IsValid(OnOtherSource),
            "the same priority on a DIFFERENT source is a different stack slot and must be accepted");

        auto Neighbour = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 51));

        Assert_True(ck::IsValid(Neighbour),
            "a free priority on the same source must still be accepted after a rejection");

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR - registers the deliberate-ensure log pattern.
//============================================================================

class ACk_AutoTest_InputLayer_PriorityCollisionRejected_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_InputLayer_PriorityCollisionRejected;
    default _TimeoutSeconds = 6.0f;

    // The collision leg deliberately trips the CK_ENSURE_IF_NOT guarding layer
    // registration; register the substring so the automation framework does not
    // auto-fail the run on it.
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("InputLayer priority collision");
        return Out;
    }
}
