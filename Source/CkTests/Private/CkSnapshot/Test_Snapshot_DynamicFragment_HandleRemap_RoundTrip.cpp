// Phase 5B end-to-end handler tests for dynamic-fragment persistence (G2). Registry-level (bare FEcsWorld) so they run
// headless with no world travel: drive the real Produce -> save-serialize -> map-mode deserialize -> HydrationApply
// pipeline by hand, mirroring Ck.Snapshot.V3.InstancedStructDiskSmoke. Proves the G2 handler (CkDynamic_Fragment.cpp)
// AND the 5B.0 HandleWalk FInstancedStruct recursion together: every dynamic fragment on an entity round-trips a save,
// and a handle nested in one re-resolves to the rebuilt target.

#include "CkDynamic/CkDynamic_Utils.h"        // UCk_Utils_DynamicFragment_UE + ECk_Replication (transitive)
#include "CkDynamic/CkDynamic_Fragment_Data.h" // FCk_SaveData_DynamicFragments

#include "CkEcs/World/CkEcsWorld.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h" // FCk_RegistryHandle
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Snapshot/CkSnapshot_Context.h"
#include "CkEcs/Snapshot/CkSnapshot_HandleWalk.h"
#include "CkEcs/Net/ReplicatedFragmentContainer/CkReplicatedFragmentContainer.h"

#include "CkCore/Validation/CkIsValid.h"

#include "Test_Snapshot_DynamicFragment_Fixtures.h"

#include "Serialization/MemoryReader.h"
#include "Serialization/MemoryWriter.h"
#include "Serialization/ObjectAndNameAsStringProxyArchive.h"

#include "Misc/AutomationTest.h"

#include "UObject/StrongObjectPtr.h" // rooting the delegate-preservation test's listener

#include <StructUtils/InstancedStruct.h>

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_dynfrag_roundtrip
{
    // Save-mode serialize (mirrors ck::snapshot::SerializeInstancedStruct): tagged props via the object proxy, then
    // RemapHandles writes each handle's RAW saved id -- including handles nested in the payload's FInstancedStructs
    // now that the HandleWalk recurses into them (5B.0).
    auto SerializeBlob_Save(const FInstancedStruct& InStruct) -> TArray<uint8>
    {
        auto Blob = TArray<uint8>{};
        if (InStruct.GetScriptStruct() == nullptr)
        { return Blob; }

        auto Writer = FMemoryWriter{Blob, /*bIsPersistent=*/true};
        constexpr auto LoadIfFindFails = true;
        auto Proxy = FObjectAndNameAsStringProxyArchive{Writer, LoadIfFindFails};
        Proxy.ArIsSaveGame = false;
        Proxy.SetIsPersistent(true);

        auto Ctx = ck::FSnapshotContext{};
        auto Copy = FInstancedStruct{InStruct};
        Copy.Serialize(Proxy);
        ck::snapshot::RemapHandles(Copy.GetScriptStruct(), Copy.GetMutableMemory(), Proxy, Ctx);
        return Blob;
    }

    // Load-mode deserialize through the v3 saved-id -> live-handle map (the Phase-3B FSnapshotContext mode).
    auto DeserializeBlob_Mapped(const TArray<uint8>& InBytes, const TMap<uint32, FCk_Handle>& InMap,
                                FCk_RegistryHandle InReg) -> FInstancedStruct
    {
        auto Reader = FMemoryReader{InBytes, /*bIsPersistent=*/true};
        constexpr auto LoadIfFindFails = true;
        auto Proxy = FObjectAndNameAsStringProxyArchive{Reader, LoadIfFindFails};
        Proxy.ArIsSaveGame = false;
        Proxy.SetIsPersistent(true);

        auto Ctx = ck::FSnapshotContext{&InMap, InReg};
        auto Out = FInstancedStruct{};
        Out.Serialize(Proxy);
        ck::snapshot::RemapHandles(Out.GetScriptStruct(), Out.GetMutableMemory(), Proxy, Ctx);
        return Out;
    }

}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_V3_DynamicFragment_HandleRemapRoundTrip_Test,
    "Ck.Snapshot.V3.DynamicFragment.HandleRemapRoundTrip",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_V3_DynamicFragment_HandleRemapRoundTrip_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto EcsWorld = ck::FEcsWorld{};
    auto& CkRegistry = EcsWorld.Get_Registry();
    const auto RegistryHandle = CkRegistry.Get_RegistryHandle();

    // Owner + a handle target ("persisted" siblings). TargetRebuilt is the DISTINCT live entity the loader maps the
    // saved target-id onto -- proves remap actually redirects (not a coincidental same-id match).
    auto Owner         = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    auto Target        = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    auto TargetRebuilt = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    const auto TargetSavedId = static_cast<uint32>(Target.Get_Entity().Get_ID());

    // Two durable dynamic fragments plus one explicitly runtime-only request fragment.
    {
        auto WithHandle = FCk_Test_DynFrag_WithHandle{};
        WithHandle.Marker      = 7;
        WithHandle.TargetHandle = Target;
        WithHandle.TargetArray  = { Target };
        UCk_Utils_DynamicFragment_UE::Add_Fragment(Owner, FInstancedStruct::Make(WithHandle), ECk_Replication::DoesNotReplicate);

        auto PureData = FCk_Test_DynFrag_PureData{};
        PureData.Count = 3;
        PureData.Label = TEXT("hello");
        UCk_Utils_DynamicFragment_UE::Add_Fragment(Owner, FInstancedStruct::Make(PureData), ECk_Replication::DoesNotReplicate);

        auto RuntimeOnly = FCk_Test_DynFrag_SnapshotTransient{};
        RuntimeOnly.RequestCount = 11;
        UCk_Utils_DynamicFragment_UE::Add_Fragment(
            Owner, FInstancedStruct::Make(RuntimeOnly), ECk_Replication::DoesNotReplicate);
    }

    // Mutate at runtime: bump Marker in place, proving the CURRENT value is captured (not the add-time value).
    {
        auto& Stored = UCk_Utils_DynamicFragment_UE::Get_Fragment_TypeUnsafe(Owner, FCk_Test_DynFrag_WithHandle::StaticStruct());
        Stored.GetMutable<FCk_Test_DynFrag_WithHandle>().Marker = 42;
    }

    // Resolve the G2 handler (its registrar ran at static init; Find() forces lazy pending-resolution).
    const auto* Handler = FCk_PersistenceHandlerRegistry::Find(FCk_SaveData_DynamicFragments::StaticStruct());
    if (NOT TestNotNull(TEXT("G2 dynamic-fragments handler is registered"), Handler))
    { return false; }
    if (NOT TestTrue(TEXT("G2 handler pairs Produce with HydrationApply"),
        static_cast<bool>(Handler->Produce) && static_cast<bool>(Handler->HydrationApply)))
    { return false; }

    // ---- Save: Produce the payload, serialize save-mode (raw ids) ----
    const auto Produced = Handler->Produce(Owner);
    if (NOT TestTrue(TEXT("Produce emitted a payload for the owner"), Produced.IsSet()))
    { return false; }
    {
        const auto& SaveData = Produced.GetValue().Get<FCk_SaveData_DynamicFragments>();
        TestEqual(TEXT("Produce captured BOTH dynamic fragments"), SaveData.Get_Fragments().Num(), 2);
        TestFalse(TEXT("Produce excluded CkSnapshotTransient runtime state"), SaveData.Get_Fragments().ContainsByPredicate(
            [](const FInstancedStruct& InEntry)
            {
                return InEntry.GetScriptStruct() == FCk_Test_DynFrag_SnapshotTransient::StaticStruct();
            }));
    }

    const auto Blob = ck_test_dynfrag_roundtrip::SerializeBlob_Save(Produced.GetValue());
    if (NOT TestTrue(TEXT("payload blob non-empty"), Blob.Num() > 0))
    { return false; }

    // ---- Load: remap the saved target-id onto the REBUILT target, deserialize, hydrate onto a fresh owner ----
    auto Map = TMap<uint32, FCk_Handle>{};
    Map.Add(TargetSavedId, TargetRebuilt);

    const auto Restored = ck_test_dynfrag_roundtrip::DeserializeBlob_Mapped(Blob, Map, RegistryHandle);
    if (NOT TestTrue(TEXT("payload deserialized to the G2 wrapper"),
        Restored.GetScriptStruct() == FCk_SaveData_DynamicFragments::StaticStruct()))
    { return false; }

    auto NewOwner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry); // rebuilt entity: no dynamic fragments yet
    auto NewOwnerRef = NewOwner;
    const auto ApplyResult = Handler->HydrationApply(NewOwnerRef, Restored, {});
    TestEqual(TEXT("HydrationApply returned Applied"),
        static_cast<int32>(ApplyResult), static_cast<int32>(ECk_Persistence_ApplyResult::Applied));

    // ---- Assert: both fragments restored, data equal, handle re-resolves to the rebuilt target ----
    TestTrue(TEXT("WithHandle fragment restored on the new owner"),
        UCk_Utils_DynamicFragment_UE::Has_Fragment(NewOwner, FCk_Test_DynFrag_WithHandle::StaticStruct()));
    TestTrue(TEXT("PureData fragment restored on the new owner"),
        UCk_Utils_DynamicFragment_UE::Has_Fragment(NewOwner, FCk_Test_DynFrag_PureData::StaticStruct()));
    TestFalse(TEXT("snapshot-transient request fragment was not restored"),
        UCk_Utils_DynamicFragment_UE::Has_Fragment(NewOwner, FCk_Test_DynFrag_SnapshotTransient::StaticStruct()));

    const auto& RestoredWithHandle = UCk_Utils_DynamicFragment_UE::Get_Fragment_TypeUnsafe(
        NewOwner, FCk_Test_DynFrag_WithHandle::StaticStruct()).Get<FCk_Test_DynFrag_WithHandle>();

    TestEqual(TEXT("mutated Marker round-tripped"), RestoredWithHandle.Marker, 42);
    TestEqual(TEXT("single handle remapped to the rebuilt target"),
        static_cast<int64>(RestoredWithHandle.TargetHandle.Get_Entity().Get_ID()),
        static_cast<int64>(TargetRebuilt.Get_Entity().Get_ID()));
    TestTrue(TEXT("remapped single handle is valid"), ck::IsValid(RestoredWithHandle.TargetHandle));

    if (TestEqual(TEXT("handle-array length round-tripped"), RestoredWithHandle.TargetArray.Num(), 1))
    {
        TestEqual(TEXT("array handle remapped to the rebuilt target"),
            static_cast<int64>(RestoredWithHandle.TargetArray[0].Get_Entity().Get_ID()),
            static_cast<int64>(TargetRebuilt.Get_Entity().Get_ID()));
    }

    const auto& RestoredPure = UCk_Utils_DynamicFragment_UE::Get_Fragment_TypeUnsafe(
        NewOwner, FCk_Test_DynFrag_PureData::StaticStruct()).Get<FCk_Test_DynFrag_PureData>();
    TestEqual(TEXT("PureData Count round-tripped"), RestoredPure.Count, 3);
    TestEqual(TEXT("PureData Label round-tripped"), RestoredPure.Label, FString{TEXT("hello")});

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_V3_DynamicFragment_HydrateDriftSkip_Test,
    "Ck.Snapshot.V3.DynamicFragment.HydrateDriftSkip",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_V3_DynamicFragment_HydrateDriftSkip_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto EcsWorld = ck::FEcsWorld{};
    auto& CkRegistry = EcsWorld.Get_Registry();

    const auto* Handler = FCk_PersistenceHandlerRegistry::Find(FCk_SaveData_DynamicFragments::StaticStruct());
    if (NOT TestNotNull(TEXT("G2 dynamic-fragments handler is registered"), Handler))
    { return false; }

    // A payload whose FIRST entry has an UNRESOLVED type (a default FInstancedStruct with a null script struct -- the
    // observable shape of an AngelScript struct deleted since the save was written), followed by one valid entry.
    auto SaveData = FCk_SaveData_DynamicFragments{};
    {
        auto Frags = TArray<FInstancedStruct>{};
        Frags.Add(FInstancedStruct{}); // unresolved type -> must be SKIPPED with a Warning (not an ensure)

        auto Valid = FCk_Test_DynFrag_PureData{};
        Valid.Count = 9;
        Valid.Label = TEXT("survivor");
        Frags.Add(FInstancedStruct::Make(Valid));

        SaveData.Set_Fragments(Frags);
    }

    // The skip path logs a recoverable-drift Warning; whitelist it so the harness does not treat it as a failure. The
    // hard assertions below prove load COMPLETED and the other fragment still applied.
    AddExpectedError(TEXT("has an unresolved type"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    auto OwnerRef = Owner;
    const auto ApplyResult = Handler->HydrationApply(OwnerRef, FInstancedStruct::Make(SaveData), {});

    TestEqual(TEXT("HydrationApply completed with Applied despite the drift entry"),
        static_cast<int32>(ApplyResult), static_cast<int32>(ECk_Persistence_ApplyResult::Applied));
    TestTrue(TEXT("the valid fragment was still applied (drift entry skipped, not fatal)"),
        UCk_Utils_DynamicFragment_UE::Has_Fragment(Owner, FCk_Test_DynFrag_PureData::StaticStruct()));

    const auto& RestoredPure = UCk_Utils_DynamicFragment_UE::Get_Fragment_TypeUnsafe(
        Owner, FCk_Test_DynFrag_PureData::StaticStruct()).Get<FCk_Test_DynFrag_PureData>();
    TestEqual(TEXT("surviving fragment data intact"), RestoredPure.Count, 9);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_V3_DynamicFragment_HydrateSnapshotTransientSkip_Test,
    "Ck.Snapshot.V3.DynamicFragment.HydrateSnapshotTransientSkip",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_V3_DynamicFragment_HydrateSnapshotTransientSkip_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto EcsWorld = ck::FEcsWorld{};
    auto& CkRegistry = EcsWorld.Get_Registry();

    const auto* Handler = FCk_PersistenceHandlerRegistry::Find(FCk_SaveData_DynamicFragments::StaticStruct());
    if (NOT TestNotNull(TEXT("G2 dynamic-fragments handler is registered"), Handler))
    { return false; }

    auto Durable = FCk_Test_DynFrag_PureData{};
    Durable.Count = 12;
    Durable.Label = TEXT("durable");
    auto RuntimeOnly = FCk_Test_DynFrag_SnapshotTransient{};
    RuntimeOnly.RequestCount = 99;

    auto SaveData = FCk_SaveData_DynamicFragments{};
    SaveData.Set_Fragments({FInstancedStruct::Make(RuntimeOnly), FInstancedStruct::Make(Durable)});

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    auto OwnerRef = Owner;
    const auto ApplyResult = Handler->HydrationApply(OwnerRef, FInstancedStruct::Make(SaveData), {});

    TestEqual(TEXT("legacy wrapper applies its durable entries"),
        static_cast<int32>(ApplyResult), static_cast<int32>(ECk_Persistence_ApplyResult::Applied));
    TestFalse(TEXT("legacy snapshot-transient entry is ignored"),
        UCk_Utils_DynamicFragment_UE::Has_Fragment(Owner, FCk_Test_DynFrag_SnapshotTransient::StaticStruct()));
    TestTrue(TEXT("durable sibling still applies"),
        UCk_Utils_DynamicFragment_UE::Has_Fragment(Owner, FCk_Test_DynFrag_PureData::StaticStruct()));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_V3_DynamicFragment_HydrateInvalidInputFailsClosed_Test,
    "Ck.Snapshot.V3.DynamicFragment.HydrateInvalidInputFailsClosed",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_V3_DynamicFragment_HydrateInvalidInputFailsClosed_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    const auto* Handler = FCk_PersistenceHandlerRegistry::Find(FCk_SaveData_DynamicFragments::StaticStruct());
    if (NOT TestNotNull(TEXT("G2 dynamic-fragments handler is registered"), Handler))
    { return false; }

    AddExpectedError(
        TEXT("Dynamic Fragment hydration received the wrong wrapper type"),
        EAutomationExpectedErrorFlags::Contains, 0);
    auto InvalidEntity = FCk_Handle{};
    const auto WrongWrapperResult = Handler->HydrationApply(
        InvalidEntity, FInstancedStruct::Make(FCk_Test_DynFrag_PureData{}), {});
    TestEqual(TEXT("wrong wrapper is rejected before entity access"),
        static_cast<int32>(WrongWrapperResult), static_cast<int32>(ECk_Persistence_ApplyResult::Rejected));

    auto SaveData = FCk_SaveData_DynamicFragments{};
    SaveData.Set_Fragments({FInstancedStruct::Make(FCk_Test_DynFrag_PureData{})});

    AddExpectedError(
        TEXT("Dynamic Fragment hydration received an invalid entity"),
        EAutomationExpectedErrorFlags::Contains, 0);
    const auto InvalidEntityResult = Handler->HydrationApply(
        InvalidEntity, FInstancedStruct::Make(SaveData), {});
    TestEqual(TEXT("invalid entity is rejected before fragment storage mutation"),
        static_cast<int32>(InvalidEntityResult), static_cast<int32>(ECk_Persistence_ApplyResult::Rejected));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_V3_DynamicFragment_HydratePreservesTransientFields_Test,
    "Ck.Snapshot.V3.DynamicFragment.HydratePreservesTransientFields",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_V3_DynamicFragment_HydratePreservesTransientFields_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto EcsWorld = ck::FEcsWorld{};
    auto& CkRegistry = EcsWorld.Get_Registry();
    const auto RegistryHandle = CkRegistry.Get_RegistryHandle();

    // Save-side owner: durable value set, transient values ALSO set (they must not leak into the payload).
    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    auto OldChild = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    {
        auto Mixed = FCk_Test_DynFrag_MixedTransient{};
        Mixed.DurableMarker = 42;
        Mixed.RuntimeMarker = 111;
        Mixed.RuntimeChild  = OldChild;
        UCk_Utils_DynamicFragment_UE::Add_Fragment(Owner, FInstancedStruct::Make(Mixed), ECk_Replication::DoesNotReplicate);
    }

    const auto* Handler = FCk_PersistenceHandlerRegistry::Find(FCk_SaveData_DynamicFragments::StaticStruct());
    if (NOT TestNotNull(TEXT("G2 dynamic-fragments handler is registered"), Handler))
    { return false; }

    const auto Produced = Handler->Produce(Owner);
    if (NOT TestTrue(TEXT("Produce emitted a payload for the owner"), Produced.IsSet()))
    { return false; }

    const auto Blob = ck_test_dynfrag_roundtrip::SerializeBlob_Save(Produced.GetValue());
    if (NOT TestTrue(TEXT("payload blob non-empty"), Blob.Num() > 0))
    { return false; }

    const auto Restored = ck_test_dynfrag_roundtrip::DeserializeBlob_Mapped(Blob, TMap<uint32, FCk_Handle>{}, RegistryHandle);
    if (NOT TestTrue(TEXT("payload deserialized to the G2 wrapper"),
        Restored.GetScriptStruct() == FCk_SaveData_DynamicFragments::StaticStruct()))
    { return false; }

    // Load-side owner: construction replay already composed the fragment with FRESH live-session
    // values — a freshly created child handle and runtime bookkeeping. Hydration must overwrite the
    // durable field and PRESERVE these.
    auto NewOwner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    auto FreshChild = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    {
        auto Fresh = FCk_Test_DynFrag_MixedTransient{};
        Fresh.DurableMarker = 0;
        Fresh.RuntimeMarker = 999;
        Fresh.RuntimeChild  = FreshChild;
        UCk_Utils_DynamicFragment_UE::Add_Fragment(NewOwner, FInstancedStruct::Make(Fresh), ECk_Replication::DoesNotReplicate);
    }

    auto NewOwnerRef = NewOwner;
    const auto ApplyResult = Handler->HydrationApply(NewOwnerRef, Restored, {});
    TestEqual(TEXT("HydrationApply returned Applied"),
        static_cast<int32>(ApplyResult), static_cast<int32>(ECk_Persistence_ApplyResult::Applied));

    const auto& Hydrated = UCk_Utils_DynamicFragment_UE::Get_Fragment_TypeUnsafe(
        NewOwner, FCk_Test_DynFrag_MixedTransient::StaticStruct()).Get<FCk_Test_DynFrag_MixedTransient>();

    TestEqual(TEXT("durable field hydrated from the save"), Hydrated.DurableMarker, 42);
    TestEqual(TEXT("transient scalar preserved (not stomped to the deserialized default)"), Hydrated.RuntimeMarker, 999);
    TestTrue(TEXT("transient handle preserved and still valid"), ck::IsValid(Hydrated.RuntimeChild));
    TestEqual(TEXT("transient handle still points at the FRESH construction-written child"),
        static_cast<int64>(Hydrated.RuntimeChild.Get_Entity().Get_ID()),
        static_cast<int64>(FreshChild.Get_Entity().Get_ID()));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_V3_DynamicFragment_HydratePreservesDelegateBindings_Test,
    "Ck.Snapshot.V3.DynamicFragment.HydratePreservesDelegateBindings",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_V3_DynamicFragment_HydratePreservesDelegateBindings_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto EcsWorld = ck::FEcsWorld{};
    auto& CkRegistry = EcsWorld.Get_Registry();
    const auto RegistryHandle = CkRegistry.Get_RegistryHandle();

    // Save-side owner: durable value only. Whatever the archive records for the delegate belongs to a world that
    // no longer exists by the time the payload is applied.
    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    {
        auto Signals = FCk_Test_DynFrag_WithDelegate{};
        Signals.DurableMarker = 42;
        UCk_Utils_DynamicFragment_UE::Add_Fragment(Owner, FInstancedStruct::Make(Signals), ECk_Replication::DoesNotReplicate);
    }

    const auto* Handler = FCk_PersistenceHandlerRegistry::Find(FCk_SaveData_DynamicFragments::StaticStruct());
    if (NOT TestNotNull(TEXT("G2 dynamic-fragments handler is registered"), Handler))
    { return false; }

    const auto Produced = Handler->Produce(Owner);
    if (NOT TestTrue(TEXT("Produce emitted a payload for the owner"), Produced.IsSet()))
    { return false; }

    const auto Blob = ck_test_dynfrag_roundtrip::SerializeBlob_Save(Produced.GetValue());
    const auto Restored = ck_test_dynfrag_roundtrip::DeserializeBlob_Mapped(Blob, TMap<uint32, FCk_Handle>{}, RegistryHandle);
    if (NOT TestTrue(TEXT("payload deserialized to the G2 wrapper"),
        Restored.GetScriptStruct() == FCk_SaveData_DynamicFragments::StaticStruct()))
    { return false; }

    // Load-side owner: construction replay composed the fragment, then a consumer (a HUD widget, in production)
    // subscribed. That subscription is the thing hydration must not destroy.
    auto NewOwner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    {
        auto Fresh = FCk_Test_DynFrag_WithDelegate{};
        Fresh.DurableMarker = 0;
        UCk_Utils_DynamicFragment_UE::Add_Fragment(NewOwner, FInstancedStruct::Make(Fresh), ECk_Replication::DoesNotReplicate);
    }

    auto Listener = TStrongObjectPtr<UCk_Test_DynFrag_SignalListener>{NewObject<UCk_Test_DynFrag_SignalListener>()};
    {
        auto* Storage = UCk_Utils_DynamicFragment_UE::TryAddOrGet_Fragment_TypeUnsafe(
            NewOwner, FCk_Test_DynFrag_WithDelegate::StaticStruct());
        if (NOT TestNotNull(TEXT("live fragment storage resolved"), Storage))
        { return false; }

        Storage->GetMutable<FCk_Test_DynFrag_WithDelegate>().OnSignal.AddDynamic(
            Listener.Get(), &UCk_Test_DynFrag_SignalListener::HandleSignal);
    }

    auto NewOwnerRef = NewOwner;
    const auto ApplyResult = Handler->HydrationApply(NewOwnerRef, Restored, {});
    TestEqual(TEXT("HydrationApply returned Applied"),
        static_cast<int32>(ApplyResult), static_cast<int32>(ECk_Persistence_ApplyResult::Applied));

    const auto& Hydrated = UCk_Utils_DynamicFragment_UE::Get_Fragment_TypeUnsafe(
        NewOwner, FCk_Test_DynFrag_WithDelegate::StaticStruct()).Get<FCk_Test_DynFrag_WithDelegate>();

    TestEqual(TEXT("durable field hydrated from the save"), Hydrated.DurableMarker, 42);
    TestTrue(TEXT("live delegate binding survived hydration"), Hydrated.OnSignal.IsBound());

    // IsBound() alone would pass on a delegate holding a stale entry — broadcast to prove it still DELIVERS.
    Hydrated.OnSignal.Broadcast(7);
    TestEqual(TEXT("surviving binding still delivers"), Listener->_CallCount, 1);
    TestEqual(TEXT("surviving binding delivered the broadcast payload"), Listener->_Received, 7);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_V3_DynamicFragment_HydrateKeepsUnresolvedHandleFresh_Test,
    "Ck.Snapshot.V3.DynamicFragment.HydrateKeepsUnresolvedHandleFresh",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_V3_DynamicFragment_HydrateKeepsUnresolvedHandleFresh_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto EcsWorld = ck::FEcsWorld{};
    auto& CkRegistry = EcsWorld.Get_Registry();
    const auto RegistryHandle = CkRegistry.Get_RegistryHandle();

    // The save-side child stands in for an unlabeled ConstructSpawned node (a SceneNode, a probe, an
    // Interactable). Capture rule 3 classifies those save-transient, so the loader never maps their saved
    // id -- the empty map below reproduces exactly that. The field is NOT Transient, which is the whole
    // point: this is the un-audited case the backstop exists for.
    auto Owner        = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    auto SkippedChild = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    {
        auto WithHandle = FCk_Test_DynFrag_WithHandle{};
        WithHandle.Marker       = 7;
        WithHandle.TargetHandle = SkippedChild;
        UCk_Utils_DynamicFragment_UE::Add_Fragment(Owner, FInstancedStruct::Make(WithHandle), ECk_Replication::DoesNotReplicate);
    }

    const auto* Handler = FCk_PersistenceHandlerRegistry::Find(FCk_SaveData_DynamicFragments::StaticStruct());
    if (NOT TestNotNull(TEXT("G2 dynamic-fragments handler is registered"), Handler))
    { return false; }

    const auto Produced = Handler->Produce(Owner);
    if (NOT TestTrue(TEXT("Produce emitted a payload for the owner"), Produced.IsSet()))
    { return false; }

    const auto Blob = ck_test_dynfrag_roundtrip::SerializeBlob_Save(Produced.GetValue());
    const auto Restored = ck_test_dynfrag_roundtrip::DeserializeBlob_Mapped(Blob, TMap<uint32, FCk_Handle>{}, RegistryHandle);
    if (NOT TestTrue(TEXT("payload deserialized to the G2 wrapper"),
        Restored.GetScriptStruct() == FCk_SaveData_DynamicFragments::StaticStruct()))
    { return false; }

    // Construction replay already composed the fragment with a FRESH child. Hydration must take the
    // durable scalar from the save and leave the handle alone.
    auto NewOwner   = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    auto FreshChild = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    {
        auto Fresh = FCk_Test_DynFrag_WithHandle{};
        Fresh.Marker       = 0;
        Fresh.TargetHandle = FreshChild;
        UCk_Utils_DynamicFragment_UE::Add_Fragment(NewOwner, FInstancedStruct::Make(Fresh), ECk_Replication::DoesNotReplicate);
    }

    auto NewOwnerRef = NewOwner;
    const auto ApplyResult = Handler->HydrationApply(NewOwnerRef, Restored, {});
    TestEqual(TEXT("HydrationApply returned Applied"),
        static_cast<int32>(ApplyResult), static_cast<int32>(ECk_Persistence_ApplyResult::Applied));

    const auto& Hydrated = UCk_Utils_DynamicFragment_UE::Get_Fragment_TypeUnsafe(
        NewOwner, FCk_Test_DynFrag_WithHandle::StaticStruct()).Get<FCk_Test_DynFrag_WithHandle>();

    TestEqual(TEXT("durable scalar still hydrates from the save"), Hydrated.Marker, 7);
    TestTrue(TEXT("the unresolved saved handle did not stomp the live one"), ck::IsValid(Hydrated.TargetHandle));
    TestEqual(TEXT("the handle still points at the construction-fresh child"),
        static_cast<int64>(Hydrated.TargetHandle.Get_Entity().Get_ID()),
        static_cast<int64>(FreshChild.Get_Entity().Get_ID()));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_V3_DynamicFragment_HydrateBackstopStandsDownOnLayoutDrift_Test,
    "Ck.Snapshot.V3.DynamicFragment.HydrateBackstopStandsDownOnLayoutDrift",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_V3_DynamicFragment_HydrateBackstopStandsDownOnLayoutDrift_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    // Pins the DOCUMENTED LIMIT of the unresolved-handle backstop, so nobody widens it by accident. The
    // backstop pairs handles positionally; a saved container of a different length shifts every later slot,
    // so correspondence is gone and it must stand down rather than write a handle into the wrong field.
    // The saved (unresolvable) values win there — a field in that shape needs UPROPERTY(Transient).
    auto EcsWorld = ck::FEcsWorld{};
    auto& CkRegistry = EcsWorld.Get_Registry();
    const auto RegistryHandle = CkRegistry.Get_RegistryHandle();

    auto Owner       = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    auto SkippedA    = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    auto SkippedB    = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    {
        auto WithHandle = FCk_Test_DynFrag_WithHandle{};
        WithHandle.Marker       = 5;
        WithHandle.TargetHandle = SkippedA;
        WithHandle.TargetArray  = { SkippedA, SkippedB }; // 3 handle slots on the save side
        UCk_Utils_DynamicFragment_UE::Add_Fragment(Owner, FInstancedStruct::Make(WithHandle), ECk_Replication::DoesNotReplicate);
    }

    const auto* Handler = FCk_PersistenceHandlerRegistry::Find(FCk_SaveData_DynamicFragments::StaticStruct());
    if (NOT TestNotNull(TEXT("G2 dynamic-fragments handler is registered"), Handler))
    { return false; }

    const auto Produced = Handler->Produce(Owner);
    if (NOT TestTrue(TEXT("Produce emitted a payload for the owner"), Produced.IsSet()))
    { return false; }

    const auto Blob = ck_test_dynfrag_roundtrip::SerializeBlob_Save(Produced.GetValue());
    const auto Restored = ck_test_dynfrag_roundtrip::DeserializeBlob_Mapped(Blob, TMap<uint32, FCk_Handle>{}, RegistryHandle);

    // Fresh side carries ONE handle slot (empty array) against the save's three.
    auto NewOwner   = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    auto FreshChild = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    {
        auto Fresh = FCk_Test_DynFrag_WithHandle{};
        Fresh.TargetHandle = FreshChild;
        UCk_Utils_DynamicFragment_UE::Add_Fragment(NewOwner, FInstancedStruct::Make(Fresh), ECk_Replication::DoesNotReplicate);
    }

    auto NewOwnerRef = NewOwner;
    const auto ApplyResult = Handler->HydrationApply(NewOwnerRef, Restored, {});
    TestEqual(TEXT("HydrationApply returned Applied"),
        static_cast<int32>(ApplyResult), static_cast<int32>(ECk_Persistence_ApplyResult::Applied));

    const auto& Hydrated = UCk_Utils_DynamicFragment_UE::Get_Fragment_TypeUnsafe(
        NewOwner, FCk_Test_DynFrag_WithHandle::StaticStruct()).Get<FCk_Test_DynFrag_WithHandle>();

    TestEqual(TEXT("durable scalar still hydrates from the save"), Hydrated.Marker, 5);
    TestEqual(TEXT("the saved container length wins, which is what breaks positional pairing"),
        Hydrated.TargetArray.Num(), 2);
    TestFalse(TEXT("backstop stood down, so the unresolved saved handle survives (documented limit)"),
        ck::IsValid(Hydrated.TargetHandle));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_V3_DynamicFragment_UnresolvedHandleBackstopWarns_Test,
    "Ck.Snapshot.V3.DynamicFragment.UnresolvedHandleBackstopWarns",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_V3_DynamicFragment_UnresolvedHandleBackstopWarns_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto EcsWorld = ck::FEcsWorld{};
    auto& CkRegistry = EcsWorld.Get_Registry();

    const auto* Handler = FCk_PersistenceHandlerRegistry::Find(FCk_SaveData_DynamicFragments::StaticStruct());
    if (NOT TestNotNull(TEXT("G2 dynamic-fragments handler is registered"), Handler))
    { return false; }

    // Occurrences 0 means "at least one, however many" -- and it is the ASSERTION as much as the suppression:
    // HasMetExpectedErrors() below is false unless each pattern actually arrived. Only Warning-or-worse enters
    // the expected-error machinery at all, so a silent regression to Verbose reds this test rather than passing
    // it quietly, which a plain suppression could not do.
    AddExpectedError(TEXT("keeping the construction-fresh handle"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/0);
    AddExpectedError(TEXT("skipping the unresolved-handle backstop"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/0);

    // The child a replayed construction writes fresh. Its saved counterpart cannot resolve, which is the shape the
    // backstop exists for: an unlabeled construct-spawned child is never persisted, so its saved id is a tombstone.
    auto FreshChild = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    {
        auto Live = FCk_Test_DynFrag_WithHandle{};
        Live.Marker       = 1;
        Live.TargetHandle = FreshChild;
        Live.TargetArray  = {FreshChild};
        UCk_Utils_DynamicFragment_UE::Add_Fragment(
            Owner, FInstancedStruct::Make(Live), ECk_Replication::DoesNotReplicate);
    }

    const auto MakePayload = [](const FCk_Test_DynFrag_WithHandle& InSaved) -> FInstancedStruct
    {
        auto SaveData = FCk_SaveData_DynamicFragments{};
        SaveData.Set_Fragments({FInstancedStruct::Make(InSaved)});
        return FInstancedStruct::Make(SaveData);
    };

    // Matching layouts, so the backstop runs: every saved handle arrives invalid and keeps the fresh value instead.
    {
        auto Saved = FCk_Test_DynFrag_WithHandle{};
        Saved.Marker      = 99;
        Saved.TargetArray = {FCk_Handle{}};

        auto OwnerRef = Owner;
        const auto ApplyResult = Handler->HydrationApply(OwnerRef, MakePayload(Saved), {});
        TestEqual(TEXT("HydrationApply returned Applied"),
            static_cast<int32>(ApplyResult), static_cast<int32>(ECk_Persistence_ApplyResult::Applied));

        const auto& Hydrated = UCk_Utils_DynamicFragment_UE::Get_Fragment_TypeUnsafe(
            Owner, FCk_Test_DynFrag_WithHandle::StaticStruct()).Get<FCk_Test_DynFrag_WithHandle>();

        TestEqual(TEXT("the durable field still hydrated from the save"), Hydrated.Marker, 99);
        TestTrue(TEXT("the kept handle is live, not the tombstone the save carried"),
            ck::IsValid(Hydrated.TargetHandle));

        TestEqual(TEXT("the construction-fresh handle was kept where the saved one did not resolve"),
            static_cast<int64>(Hydrated.TargetHandle.Get_Entity().Get_ID()),
            static_cast<int64>(FreshChild.Get_Entity().Get_ID()));
    }

    // A saved array of a different length shifts every later slot, so positional correspondence is gone and the
    // backstop stands down -- the branch that leaves a dead handle in place, which is the louder of the two.
    {
        auto Saved = FCk_Test_DynFrag_WithHandle{};
        Saved.Marker      = 7;
        Saved.TargetArray = {FCk_Handle{}, FCk_Handle{}};

        auto OwnerRef = Owner;
        Handler->HydrationApply(OwnerRef, MakePayload(Saved), {});
    }

    // Both branches of the backstop reported, at a verbosity a reader is actually shown. A firing is a fragment
    // whose posture nobody declared, so silence here is the defect this promotion exists to remove.
    TestTrue(TEXT("both backstop diagnostics were emitted at Warning-or-worse"), HasMetExpectedErrors());

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
