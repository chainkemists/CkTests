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

// Payload carrying a RAW FCk_Handle property. Control case for the dynamic-handle repro: a raw
// handle replicates via the named "Ck_Handle" Iris NetSerializer (rep-driver object reference),
// so the client should both fire OnRepNotify AND resolve the handle. Paired with the
// DynHandlePayload below, which carries the SAME logical handle typed as a dynamic handle.
struct FCk_Fragment_DynamicTest_RawHandlePayload
{
    UPROPERTY()
    int32 Value = 0;

    UPROPERTY()
    FCk_Handle TheHandle;
}

// "Dumb" marker fragment required by FCk_Handle_TESTONLY_NetSubject (see DynamicHandleTypes.TESTONLY.json).
// A dynamic handle's IsValid()/As_X()/Cast are FRAGMENT-VALIDATED: they only succeed when the entity holds
// every RequiredFragment. Giving the test handle a real requirement exercises that validated path instead of
// the degenerate permissive (empty-requirements) case. Carries one trivial field so it is unambiguously a
// non-empty reflected struct.
struct FCk_Fragment_TESTONLY_HandleMarker
{
    UPROPERTY()
    int32 Tag = 0;
}

// Payload carrying a DYNAMIC-handle property (FCk_Handle_TESTONLY_NetSubject — registered from the
// merged DynamicHandleTypes.TESTONLY.json). This is the reported-broken shape: same wire intent as
// the raw-handle payload, but the member is a dynamic handle type. The matching AutoTest asserts
// whether OnRepNotify fires and whether the handle resolves on the client.
struct FCk_Fragment_DynamicTest_DynHandlePayload
{
    UPROPERTY()
    int32 Value = 0;

    UPROPERTY()
    FCk_Handle_TESTONLY_NetSubject TheHandle;
}

//============================================================================
// StoreDriver-shaped repro (separate replicated entity + empty->filled carrier)
//============================================================================
//
// Mirrors BB_StoreDriver's RepStoreCustomization carrier: driver A carries a SEPARATE
// replicated entity B's dynamic typesafe handle in a replicated dynamic fragment that is
// added EMPTY on both worlds and filled on the server when B constructs. The earlier
// payloads point the handle at the SAME entity (already-mapped, trivial); this one points
// at an independently-replicated child, which is the shape that flagged the bug.

// Feature marker composed by the test subordinate entity script (B) in its DoConstruct (runs on
// both worlds). Required by FCk_Handle_TESTONLY_Subordinate so the validated IsValid()/As_X()
// succeeds only when B has actually composed on THIS machine.
struct FCk_Fragment_TESTONLY_SubordinateFeature
{
    UPROPERTY()
    int32 Tag = 0;
}

// Replicated carrier — single dynamic typesafe handle to the separate replicated entity B.
// Added empty (Replicates) on both worlds; server sets Handle = B + MarkReplicationDirty.
struct FCk_Fragment_TESTONLY_DriverCarrier
{
    UPROPERTY()
    FCk_Handle_TESTONLY_Subordinate Handle;
}

//============================================================================
// Script-processor pump-drain repro (see CkAutoTest_ScriptProcessor_PumpDrainsSameFrame)
//============================================================================

// MarkedDirtyBy marker consumed by UCk_TESTONLY_ScriptProcessor_PumpCascade. RemainingCascades > 0
// makes the processor re-add the marker after consuming it — each re-add lands AFTER the
// processor's own tick, so draining the whole chain within one frame REQUIRES the scheduler's
// pump passes to observe dynamic-marker mutations (the dirty-marker version bump in
// UCk_Utils_DynamicFragment_UE's mutation paths).
struct FCk_Fragment_DynamicTest_PumpCascadeMarker
{
    UPROPERTY()
    int32 RemainingCascades = 0;
}

// Per-generation consumption log written by the processor and asserted by the AutoTest: all
// entries equal ⇒ the cascade settled in one frame (pump), entries differ ⇒ generations slipped
// to later frames' main passes (the pre-fix pump-deaf behavior).
struct FCk_Fragment_DynamicTest_PumpCascadeResults
{
    UPROPERTY()
    TArray<int64> ConsumedFrames;
}
