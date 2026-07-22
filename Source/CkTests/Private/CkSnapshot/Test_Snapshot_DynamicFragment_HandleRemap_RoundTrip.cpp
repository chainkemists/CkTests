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

    // Two dynamic fragments on the owner: one carrying a cross-entity handle (+ a handle array), one pure data.
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

#endif // WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
