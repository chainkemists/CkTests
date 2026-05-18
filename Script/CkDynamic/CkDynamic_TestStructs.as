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
