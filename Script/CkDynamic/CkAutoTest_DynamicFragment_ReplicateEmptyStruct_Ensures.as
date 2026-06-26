// Language=angelscript

//============================================================================
// CK DYNAMIC — AUTOMATION TEST: REPLICATING A TAG / SIZE-0 STRUCT ENSURES
//============================================================================
//
// Adding a dynamic fragment whose struct carries no reflected properties with
// ECk_Replication::Replicates must trip the size-0 guard ensure in
// DoSetupReplication — replicating a payload with no data is meaningless.
//
// The ensure is diagnostic-only (it does not halt), so the test reaches the
// end normally; the hand-authored wrapper registers the expected log substring
// so the automation framework does not auto-fail on the deliberate diagnostic.
//============================================================================

class UCk_AutoTest_DynamicFragment_ReplicateEmptyStruct_Ensures : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 2.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Entity = InHandle;

        auto TagPayload = FCk_Fragment_DynamicTest_TagPayload();
        Entity.Add_Fragment(TagPayload, ECk_Replication::Replicates);

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR — registers the deliberate-ensure log pattern.
//============================================================================

class ACk_AutoTest_DynamicFragment_ReplicateEmptyStruct_Ensures_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_DynamicFragment_ReplicateEmptyStruct_Ensures;
    default _TimeoutSeconds = 2.0f;

    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("carries no data and is meaningless");
        return Out;
    }
}
