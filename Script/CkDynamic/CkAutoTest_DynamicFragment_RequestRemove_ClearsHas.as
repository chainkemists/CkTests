// Language=angelscript

//============================================================================
// CK DYNAMIC — AUTOMATION TEST: Request_Remove clears Has_Fragment
//============================================================================
//
// Pins the remove side of the dynamic-fragment lifecycle: after Add then
// Request_Remove on the same struct type, Has_Fragment must return false.
// Captures the basic add/remove cycle as a regression.
//============================================================================

class UCk_AutoTest_DynamicFragment_RequestRemove_ClearsHas : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 2.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Entity = InHandle;

        auto Payload = FCk_Fragment_DynamicTest_Payload();
        Payload.Value = 7;
        Entity.Add_Fragment(Payload);

        Assert_True(Entity.Has_Fragment(FCk_Fragment_DynamicTest_Payload),
            "Precondition: Has_Fragment should be true after Add");

        Entity.Request_Remove(FCk_Fragment_DynamicTest_Payload);

        Assert_True(Entity.Has_Fragment(FCk_Fragment_DynamicTest_Payload) == false,
            "After Request_Remove, Has_Fragment should report false");

        FinishSuccess();
    }
}
