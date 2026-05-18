// Language=angelscript

//============================================================================
// CK DYNAMIC — AUTOMATION TEST: Request_TryRemove on absent returns Failed
//============================================================================
//
// Pins the contract that Request_TryRemove on an entity that does not
// carry the requested struct type returns Failed (rather than ensuring
// or silently succeeding).
//============================================================================

class UCk_AutoTest_DynamicFragment_TryRemove_OnAbsent_ReturnsFailed : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 2.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Entity = InHandle;

        Assert_True(Entity.Has_Fragment(FCk_Fragment_DynamicTest_Payload) == false,
            "Precondition: test entity must not carry the test fragment");

        auto Result = Entity.Request_TryRemove(FCk_Fragment_DynamicTest_Payload);
        Assert_True(Result == ECk_SucceededFailed::Failed,
            f"Request_TryRemove on absent fragment should return Failed (got {Result})");

        FinishSuccess();
    }
}
