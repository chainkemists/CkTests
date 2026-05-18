// Language=angelscript

//============================================================================
// CK DYNAMIC — AUTOMATION TEST: Add_Fragment → Has_Fragment returns true
//============================================================================
//
// First-coverage seed for CkDynamic. Verifies the round-trip of the
// type-erased dynamic-fragment surface:
//
//   Handle.Add_Fragment(Payload)            (mixin form, AS-only)
//   → Handle.Has_Fragment(StructType) == true
//
// Uses the test-local FCk_Fragment_DynamicTest_Payload USTRUCT
// (shared across CkDynamic AutoTests) as the dynamic payload.
//============================================================================

class UCk_AutoTest_DynamicFragment_Add_HasReturnsTrue : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 2.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Entity = InHandle;

        Assert_True(Entity.Has_Fragment(FCk_Fragment_DynamicTest_Payload) == false,
            "Before Add, the test entity should not carry the dynamic test fragment");

        auto Payload = FCk_Fragment_DynamicTest_Payload();
        Payload.Value = 42;
        Payload.Label = "hello-dynamic";
        Entity.Add_Fragment(Payload);

        Assert_True(Entity.Has_Fragment(FCk_Fragment_DynamicTest_Payload),
            "After Add_Fragment, Has_Fragment should report true");

        FinishSuccess();
    }
}
