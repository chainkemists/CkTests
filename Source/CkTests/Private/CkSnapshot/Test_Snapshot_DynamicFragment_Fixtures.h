#pragma once

#include "CkDynamic/CkDynamic_Fragment_Data.h"

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Handle/CkHandle_TypeSafe.h"
#include "CkEcs/Persistence/CkPersistenceHydration.h" // FCk_Hydration_TypeInfo
#include "CkEcs/Request/CkRequest_Data.h"
#include "CkEcs/Snapshot/CkSnapshot_Posture.h"

#include <StructUtils/InstancedStruct.h>
#include "Templates/SubclassOf.h"
#include "UObject/Object.h"

#include "Test_Snapshot_DynamicFragment_Fixtures.generated.h"

// --------------------------------------------------------------------------------------------------------------------

// Test-only USTRUCT used AS a dynamic fragment (the same mechanism AngelScript fragments use): a UScriptStruct
// wrapped in an FInstancedStruct and added via UCk_Utils_DynamicFragment_UE::Add_Fragment. Mirrors the shape of a
// real AS fragment such as FBb_Fragment_QuickUseSelector — scalar data plus a cross-entity handle. The companion
// test (Test_Snapshot_DynamicFragment_HandleRemap_RoundTrip.cpp) uses it to prove whether a dynamic fragment
// survives a CkSnapshot round-trip AND whether its handle is remapped to the restored entity.
USTRUCT()
struct FCk_Test_DynFrag_WithHandle
{
    GENERATED_BODY()

    // Plain scalar — verifies the fragment's non-handle data round-trips. SaveGame is the real CPF_SaveGame
    // specifier (NOT meta=(SaveGame), which only writes a metadata string — see the SaveKey round-trip test).
    UPROPERTY(SaveGame)
    int32 Marker = 0;

    // Cross-entity handle — verifies single-handle remap on restore (the entity it points at gets a new id post-wipe).
    UPROPERTY(SaveGame)
    FCk_Handle TargetHandle;

    // Array of cross-entity handles — mirrors FBb_Fragment_QuickUseSelector's TArray<FCk_Handle_Inventory>.
    // Verifies that handles inside a container remap (and that the array length round-trips so save/load stay aligned).
    UPROPERTY(SaveGame)
    TArray<FCk_Handle> TargetArray;
};

// --------------------------------------------------------------------------------------------------------------------

// A SECOND, distinct handle-bearing dynamic-fragment type. Used to prove that MULTIPLE dynamic-fragment types on the
// SAME entity (each in its own named storage) all survive a round-trip -- the core of the named-storage enumeration.
USTRUCT()
struct FCk_Test_DynFrag_OtherHandle
{
    GENERATED_BODY()

    UPROPERTY(SaveGame)
    FCk_Handle OtherTarget;
};

// --------------------------------------------------------------------------------------------------------------------

// A dynamic fragment with NO handles -- isolates the data round-trip from handle remap.
USTRUCT()
struct FCk_Test_DynFrag_PureData
{
    GENERATED_BODY()

    UPROPERTY(SaveGame)
    int32 Count = 0;

    UPROPERTY(SaveGame)
    FString Label;
};

// --------------------------------------------------------------------------------------------------------------------

// A nested struct holding a handle, plus a wrapper that contains it -- exercises the recursive handle walk
// (a handle one struct level deep must still be remapped).
USTRUCT()
struct FCk_Test_DynFrag_Inner
{
    GENERATED_BODY()

    UPROPERTY(SaveGame)
    FCk_Handle InnerHandle;
};

USTRUCT()
struct FCk_Test_DynFrag_Nested
{
    GENERATED_BODY()

    UPROPERTY(SaveGame)
    int32 Tag = 0;

    UPROPERTY(SaveGame)
    FCk_Test_DynFrag_Inner Inner;
};

// --------------------------------------------------------------------------------------------------------------------

// A TYPED handle, declared exactly like every production typesafe handle (FCk_Handle_Inventory,
// FCk_Handle_IntegerAttribute, ...). Its reflected FStructProperty::Struct is FCk_Test_TypedHandle::StaticStruct(),
// NOT FCk_Handle::StaticStruct() — the shape the remap walk's original exact-equality test silently skipped.
USTRUCT()
struct FCk_Test_TypedHandle : public FCk_Handle_TypeSafe
{
    GENERATED_BODY()
    CK_GENERATED_BODY_HANDLE_TYPESAFE(FCk_Test_TypedHandle);
};

// The REAL shape of production AS fragments: TYPED handles (single + array — the actual FBb_Fragment_QuickUseSelector
// shape; the bare-FCk_Handle fixtures above never covered it) plus handle-bearing containers (TSet / TMap with handle
// keys and values — the FBb_Fragment_GridPlacement shape). The companion test proves each remaps across a round-trip
// and that in-place key remap rehashes the containers so lookups still work.
USTRUCT()
struct FCk_Test_DynFrag_TypedAndContainers
{
    GENERATED_BODY()

    UPROPERTY(SaveGame)
    FCk_Test_TypedHandle TypedSingle;

    UPROPERTY(SaveGame)
    TArray<FCk_Test_TypedHandle> TypedArray;

    UPROPERTY(SaveGame)
    TSet<FCk_Handle> HandleSet;

    UPROPERTY(SaveGame)
    TMap<FCk_Handle, int32> HandleKeyMap;

    UPROPERTY(SaveGame)
    TMap<int32, FCk_Test_TypedHandle> TypedValueMap;
};

// --------------------------------------------------------------------------------------------------------------------

// A wrapper holding a TArray<FInstancedStruct> -- the exact shape of the G2 save payload
// (FCk_SaveData_DynamicFragments). Used by the HandleWalk unit test to prove the remap walk recurses INTO each
// FInstancedStruct element and reaches a handle nested in the stored struct. Before the FInstancedStruct-recursion
// fix, the walk treated an instanced struct as opaque -- handles inside a dynamic-fragment payload were never visited.
USTRUCT()
struct FCk_Test_InstancedStructArrayWrapper
{
    GENERATED_BODY()

    UPROPERTY()
    TArray<FInstancedStruct> Payloads;
};

// Fixture used to verify that the reflected holder enumerates an object nested in an FInstancedStruct payload.
USTRUCT()
struct FCk_Test_HydrationPayloadWithObject
{
    GENERATED_BODY()

    UPROPERTY()
    TObjectPtr<UObject> Object;
};

// Explicit runtime-only dynamic state, declared by DERIVATION — the C++ half of the marker contract (the
// AngelScript half carries it as a field, since script structs cannot inherit). Capture must omit it, and
// hydration must ignore a legacy payload that still carries one.
USTRUCT()
struct FCk_Test_DynFrag_SessionMarker : public FCk_Snapshot_Session
{
    GENERATED_BODY()

    UPROPERTY(SaveGame)
    int32 RequestCount = 0;
};

// A fragment mixing durable and CPF_Transient fields, DECLARED Durable — the un-split FBb_Fragment_Shelf_State
// shape. The Transient fields hold live-session values (a freshly constructed child handle, in-flight
// bookkeeping) the persistent archive never writes, and there is no longer any guard that rescues them: the
// resolver reds the declaration and demands the split below, and hydration assigns the whole saved payload.
USTRUCT()
struct FCk_Test_DynFrag_MixedTransient : public FCk_Snapshot_Durable
{
    GENERATED_BODY()

    UPROPERTY(SaveGame)
    int32 DurableMarker = 0;

    UPROPERTY(Transient)
    int32 RuntimeMarker = 0;

    UPROPERTY(Transient)
    FCk_Handle RuntimeChild;
};

// The SPLIT of the fixture above — the shape BusterBlock's Shelf/ClawMachine/EmployeeManager fragments took. The
// durable half is captured and assigned whole; the session half is skipped on both sides, which is what makes the
// live child handle survive. The declaration is the preservation mechanism.
USTRUCT()
struct FCk_Test_DynFrag_SplitDurable : public FCk_Snapshot_Durable
{
    GENERATED_BODY()

    UPROPERTY(SaveGame)
    int32 DurableMarker = 0;
};

USTRUCT()
struct FCk_Test_DynFrag_SplitSession : public FCk_Snapshot_Session
{
    GENERATED_BODY()

    UPROPERTY()
    int32 RuntimeMarker = 0;

    UPROPERTY()
    FCk_Handle RuntimeChild;
};

DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FCk_Test_DynFrag_OnSignal, int32, InValue);

// The shape of every AngelScript "<Feature>_Signals" fragment, DECLARED Durable: durable data alongside a
// multicast delegate whose subscribers bound during the REBUILT world's construction. The saved delegate is stale
// or empty by construction (it named objects belonging to the torn-down world), and hydration now assigns it
// wholesale — the feature keeps correct state and never notifies again. The resolver reds the declaration for
// exactly that reason; a delegate carrier is Session, or is split so the delegate lives in a Session half.
USTRUCT()
struct FCk_Test_DynFrag_WithDelegate : public FCk_Snapshot_Durable
{
    GENERATED_BODY()

    UPROPERTY(SaveGame)
    int32 DurableMarker = 0;

    UPROPERTY()
    FCk_Test_DynFrag_OnSignal OnSignal;
};

// Subscriber for the fixture above — records the last broadcast so a test can prove the surviving binding still
// DELIVERS, not merely that IsBound() reports true.
UCLASS()
class UCk_Test_DynFrag_SignalListener : public UObject
{
    GENERATED_BODY()

public:
    UFUNCTION()
    void
    HandleSignal(
        int32 InValue)
    {
        _Received = InValue;
        ++_CallCount;
    }

public:
    int32 _Received = 0;
    int32 _CallCount = 0;
};

// --------------------------------------------------------------------------------------------------------------------

USTRUCT()
struct FCk_Test_UntracedSafeObjectRefs
{
    GENERATED_BODY()

    UPROPERTY()
    TWeakObjectPtr<UObject> WeakObject;

    UPROPERTY()
    TSoftObjectPtr<UObject> SoftObject;
};

USTRUCT()
struct FCk_Test_UntracedNestedStrongObject
{
    GENERATED_BODY()

    UPROPERTY()
    TArray<FCk_Test_HydrationPayloadWithObject> Values;
};

USTRUCT()
struct FCk_Test_UntracedOpaqueEmpty
{
    GENERATED_BODY()
};

// --------------------------------------------------------------------------------------------------------------------
// Snapshot-posture fixtures (Test_Snapshot_FragmentPosture.cpp). Each one exists to pin ONE resolution rule; the markers
// are carried as FIELDS rather than by derivation because that is the AngelScript spelling every production
// fragment uses (script structs cannot inherit) and it is the branch a top-level-only check would miss.
// --------------------------------------------------------------------------------------------------------------------

// T-C1-2 — a Durable declaration over a top-level delegate. The delegate DERIVATION wins: a fragment whose content
// names objects from the torn-down world cannot round-trip, whatever it declares.
USTRUCT()
struct FCk_Test_Posture_DurableWithDelegate
{
    GENERATED_BODY()

    UPROPERTY()
    FCk_Snapshot_Durable Posture;

    UPROPERTY(SaveGame)
    int32 DurableMarker = 0;

    UPROPERTY()
    FCk_Test_DynFrag_OnSignal OnSignal;
};

// A delegate one array + one struct level down. C++ reflection rejects a container OF delegates, so the deep case is
// spelled the way BB's FBb_Fragment_StoreInventory_Watches reaches it — through an array of carriers. Strictly
// deeper than a TArray of delegates, and the same walk regression it guards against.
USTRUCT()
struct FCk_Test_Posture_DelegateCarrier
{
    GENERATED_BODY()

    UPROPERTY()
    FCk_Test_DynFrag_OnSignal OnSignal;
};

USTRUCT()
struct FCk_Test_Posture_DurableWithNestedDelegate
{
    GENERATED_BODY()

    UPROPERTY()
    FCk_Snapshot_Durable Posture;

    UPROPERTY()
    TArray<FCk_Test_Posture_DelegateCarrier> Carriers;
};

// T-C1-3 — the AngelScript arm: the fragment name ends in "Requests" and every field is a request payload, itself
// recognised by the AS naming convention (FBb_Request_* -> reflected Bb_Request_*), NOT by inheritance, because no
// AngelScript struct inherits anything.
USTRUCT()
struct FCk_Test_Posture_Request_Probe
{
    GENERATED_BODY()

    UPROPERTY()
    int32 Amount = 0;
};

USTRUCT()
struct FCk_Test_Posture_ProbeRequests
{
    GENERATED_BODY()

    UPROPERTY()
    TArray<FCk_Test_Posture_Request_Probe> Pending;
};

// T-C1-3 — the C++ arm: no "Requests" suffix, so only the FCk_Request_Base type test can classify it.
USTRUCT()
struct FCk_Test_Posture_DerivedRequest : public FCk_Request_Base
{
    GENERATED_BODY()

    CK_GENERATED_BODY(FCk_Test_Posture_DerivedRequest);

    UPROPERTY()
    int32 Amount = 0;
};

USTRUCT()
struct FCk_Test_Posture_CppQueue
{
    GENERATED_BODY()

    UPROPERTY()
    TArray<FCk_Test_Posture_DerivedRequest> Pending;
};

// T-C1-5 — both markers. Neither wins.
USTRUCT()
struct FCk_Test_Posture_Contradiction
{
    GENERATED_BODY()

    UPROPERTY()
    FCk_Snapshot_Durable DurablePosture;

    UPROPERTY()
    FCk_Snapshot_Session SessionPosture;

    UPROPERTY(SaveGame)
    int32 DurableMarker = 0;
};

// T-C1-6 — a Durable declaration plus the retired field-level opt-out.
USTRUCT()
struct FCk_Test_Posture_DurableWithTransientField
{
    GENERATED_BODY()

    UPROPERTY()
    FCk_Snapshot_Durable Posture;

    UPROPERTY(SaveGame)
    int32 DurableMarker = 0;

    UPROPERTY(Transient)
    int32 RuntimeMarker = 0;
};

// T-C1-9 — derived-Session shapes that ALSO carry durable value fields. Their real-world instances are
// int32 SwingWhiffs (FBb_Fragment_WhackAGull_Requests) and int32 MaxCapacityDelta
// (FBb_Fragment_Occupancy_Requests): accumulators a silent derive would have deleted.
USTRUCT()
struct FCk_Test_Posture_MixedRequests
{
    GENERATED_BODY()

    UPROPERTY()
    TArray<FCk_Test_Posture_Request_Probe> Pending;

    UPROPERTY(SaveGame)
    int32 Accumulator = 0;
};

USTRUCT()
struct FCk_Test_Posture_MixedDelegate
{
    GENERATED_BODY()

    UPROPERTY(SaveGame)
    int32 Accumulator = 0;

    UPROPERTY()
    FCk_Test_DynFrag_OnSignal OnSignal;
};

// The clean poles, so the tests above are read against something that is NOT red.
USTRUCT()
struct FCk_Test_Posture_PlainDurable
{
    GENERATED_BODY()

    UPROPERTY()
    FCk_Snapshot_Durable Posture;

    UPROPERTY(SaveGame)
    int32 DurableMarker = 0;

    UPROPERTY(SaveGame)
    FCk_Handle Target;
};

USTRUCT()
struct FCk_Test_Posture_PlainSession
{
    GENERATED_BODY()

    UPROPERTY()
    FCk_Snapshot_Session Posture;

    UPROPERTY(SaveGame)
    int32 RuntimeMarker = 0;
};

// A field-less fragment declaring NO posture — the tag derivation. It can only be RESOLVED, never added to an
// entity: a NATIVE zero-reflection struct fails the dynamic-fragment schema gate closed
// (ck::Analyze_UntracedStructSafety's UnprovenOpaque branch), so the only tags that ever reach dynamic storage
// are script-declared ones. The capture half of the tag test therefore drives a script tag instead.
USTRUCT()
struct FCk_Test_Posture_BareTag
{
    GENERATED_BODY()
};

// --------------------------------------------------------------------------------------------------------------------

// Two Durable dynamic fragments, distinct types, both carried by one entity. The per-type hydration edge has to
// fire once for each, so a single-type fixture could not tell "one edge per type" from "one edge per entity".
USTRUCT()
struct FCk_Test_TypeHydrated_Alpha
{
    GENERATED_BODY()

    UPROPERTY()
    FCk_Snapshot_Durable Posture;

    UPROPERTY(SaveGame)
    int32 Marker = 0;
};

USTRUCT()
struct FCk_Test_TypeHydrated_Beta
{
    GENERATED_BODY()

    UPROPERTY()
    FCk_Snapshot_Durable Posture;

    UPROPERTY(SaveGame)
    int32 Marker = 0;
};

// Counts both edges a hydrating dynamic fragment could raise. The OnRepNotify count is the load-bearing one: it
// must stay at zero, because the load path naming itself as replication is the defect the split fixed, and a
// regression there is silent — every subscriber keeps working, they just start hearing about the wrong event.
UCLASS()
class UCk_Test_TypeHydrated_Witness : public UObject
{
    GENERATED_BODY()

public:
    UFUNCTION()
    void
    HandleTypeHydrated(
        FCk_Handle InHandle,
        FCk_Hydration_TypeInfo InInfo)
    {
        ++_TypeHydratedCount;
        _TypeHydratedTypes.Add(InInfo.HydratedType);
    }

    UFUNCTION()
    void
    HandleRepNotify(
        FCk_Handle InHandle,
        FCk_DynamicFragment_RepNotifyInfo InInfo)
    {
        ++_RepNotifyCount;
    }

public:
    int32 _TypeHydratedCount = 0;
    int32 _RepNotifyCount = 0;
    TSet<TObjectPtr<UScriptStruct>> _TypeHydratedTypes;
};

// --------------------------------------------------------------------------------------------------------------------

// The two shapes the durable-payload object-ref fence deliberately ACCEPTS, kept beside the hard-ref fixture
// (FCk_Test_HydrationPayloadWithObject) it is contrasted against. A soft ref is dangle-proof by weak-ptr serial;
// a class ref is accepted by an explicit, documented narrowing rather than because it is unreachable.
USTRUCT()
struct FCk_Test_DurablePayload_SoftRef
{
    GENERATED_BODY()

    UPROPERTY()
    TSoftObjectPtr<UObject> Asset;
};

USTRUCT()
struct FCk_Test_DurablePayload_ClassRef
{
    GENERATED_BODY()

    UPROPERTY()
    TSubclassOf<UObject> Class;
};

// A concrete, field-less UObject to be collected on purpose. UObject itself is ABSTRACT, so NewObject<UObject> is
// not a way to mint a throwaway subject — it ensures and nulls the result.
UCLASS()
class UCk_Test_CollectableSubject : public UObject
{
    GENERATED_BODY()
};
