// Language=angelscript

//============================================================================
// CK DYNAMIC - AUTOMATION TEST: Add -> Get round-trip preserves payload
//============================================================================
//
// Verifies that the data added via Add_Fragment(Payload) is observable
// through Get_Fragment with the original field values intact. Pins the
// contract that the type-erased dynamic-fragment storage doesn't drop or
// reset reflected fields.
//============================================================================

class UCk_AutoTest_DynamicFragment_AddGet_RoundTripsValue : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 2.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Entity = InHandle;

        auto Payload = FCk_Fragment_DynamicTest_Payload();
        Payload.Value = 12345;
        Payload.Label = "round-trip";
        Entity.Add_Fragment(Payload);

        const auto& Retrieved = Entity.Get_Fragment(FCk_Fragment_DynamicTest_Payload);
        Assert_Equals_Int(Retrieved.Value, 12345,
            "Get_Fragment should return the same integer value that was added");
        Assert_Equals_String(Retrieved.Label, "round-trip",
            "Get_Fragment should return the same FString label that was added");

        FinishSuccess();
    }
}
