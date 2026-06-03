// Language=angelscript

//============================================================================
// CK DYNAMIC — SHARED TEST STRUCTS
//============================================================================
//
// Lightweight test-only USTRUCT used by the CkDynamic AutoTests. Carries
// two reflected fields so we can verify the dynamic-fragment Add→Get
// round-trip preserves payload data.
//============================================================================

struct FCk_Fragment_DynamicTest_Payload
{
    UPROPERTY()
    int32 Value = 0;

    UPROPERTY()
    FString Label = "";
}

// Tag / size-0 payload: deliberately carries NO reflected fields. Used to verify that requesting
// replication of an empty dynamic fragment trips the size-0 guard ensure in DoSetupReplication.
struct FCk_Fragment_DynamicTest_TagPayload
{
}
