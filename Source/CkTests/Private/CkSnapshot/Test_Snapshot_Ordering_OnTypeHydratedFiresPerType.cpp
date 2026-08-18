// The per-TYPE hydration edge. A load used to broadcast DynamicFragment_OnRepNotify when it committed a
// fragment's restored value, which meant one signal carried two unrelated events: "the server sent you a new
// value" and "a save was loaded". A consumer bound one intent and silently received the other, and the failure
// mode is quiet in both directions — a net handler running on a load path, and an author reaching for
// BindTo_OnRepNotify to learn "my restored value is ready" and getting nothing on the authority.
//
// Two things are pinned here, and the second is the one a refactor breaks by accident:
//   1. Hydration_OnTypeHydrated fires once per hydrated TYPE, after every value in the entity's payload set is
//      committed. Two Durable fragments on one entity, so "per type" is distinguishable from "per entity".
//   2. OnRepNotify does NOT fire on the load path. It stays the net edge, broadcast from CkDynamic_Module.
//
// Registry-level (bare FEcsWorld), driving Produce -> serialize -> deserialize -> HydrationApply by hand in the
// style of the handle-remap round-trip beside it: the edge is raised inside HydrationApply, so a PIE world and a
// real travel would add an hour of machinery and observe the same call.
// Surface in Session Frontend: Ck.Snapshot.Ordering.OnTypeHydratedFiresPerType

#include "CkDynamic/CkDynamic_Fragment.h"      // ck::UUtils_Signal_DynamicFragment_OnRepNotify
#include "CkDynamic/CkDynamic_Fragment_Data.h" // FCk_SaveData_DynamicFragments
#include "CkDynamic/CkDynamic_Utils.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Persistence/CkPersistenceHandlerRegistry.h"
#include "CkEcs/Persistence/CkPersistenceHydration.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h" // FCk_RegistryHandle
#include "CkEcs/Signal/CkSignal_Macros.h"
#include "CkEcs/Snapshot/CkSnapshot_Context.h"
#include "CkEcs/Snapshot/CkSnapshot_HandleWalk.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "CkCore/Validation/CkIsValid.h"

#include "Test_Snapshot_DynamicFragment_Fixtures.h"

#include "Serialization/MemoryReader.h"
#include "Serialization/MemoryWriter.h"
#include "Serialization/ObjectAndNameAsStringProxyArchive.h"

#include "Misc/AutomationTest.h"

#include "UObject/StrongObjectPtr.h"

#include <StructUtils/InstancedStruct.h>

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_ontypehydrated
{
    constexpr auto SavedAlpha = 771;
    constexpr auto SavedBeta  = 442;

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

    auto DeserializeBlob(const TArray<uint8>& InBlob, FCk_RegistryHandle InRegistryHandle) -> FInstancedStruct
    {
        auto Restored = FInstancedStruct{};
        if (InBlob.Num() == 0)
        { return Restored; }

        auto Reader = FMemoryReader{InBlob, /*bIsPersistent=*/true};
        constexpr auto LoadIfFindFails = true;
        auto Proxy = FObjectAndNameAsStringProxyArchive{Reader, LoadIfFindFails};
        Proxy.ArIsSaveGame = false;
        Proxy.SetIsPersistent(true);

        Restored.Serialize(Proxy);

        const auto EmptyMap = TMap<uint32, FCk_Handle>{};
        auto Ctx = ck::FSnapshotContext{&EmptyMap, InRegistryHandle};
        ck::snapshot::RemapHandles(Restored.GetScriptStruct(), Restored.GetMutableMemory(), Proxy, Ctx);
        return Restored;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Ordering_OnTypeHydratedFiresPerType,
    "Ck.Snapshot.Ordering.OnTypeHydratedFiresPerType",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Ordering_OnTypeHydratedFiresPerType::
    RunTest(
        const FString& /*InParameters*/)
{
    using namespace ck_test_ontypehydrated;

    auto EcsWorld = ck::FEcsWorld{};
    auto& CkRegistry = EcsWorld.Get_Registry();
    const auto RegistryHandle = CkRegistry.Get_RegistryHandle();

    // ---- Save side: one entity, two Durable dynamic fragments -------------------------------------------
    auto SaveOwner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    {
        auto Alpha = FCk_Test_TypeHydrated_Alpha{};
        Alpha.Marker = SavedAlpha;
        UCk_Utils_DynamicFragment_UE::Add_Fragment(
            SaveOwner, FInstancedStruct::Make(Alpha), ECk_Replication::DoesNotReplicate);

        auto Beta = FCk_Test_TypeHydrated_Beta{};
        Beta.Marker = SavedBeta;
        UCk_Utils_DynamicFragment_UE::Add_Fragment(
            SaveOwner, FInstancedStruct::Make(Beta), ECk_Replication::DoesNotReplicate);
    }

    const auto* Handler = FCk_PersistenceHandlerRegistry::Find(FCk_SaveData_DynamicFragments::StaticStruct());
    if (NOT TestNotNull(TEXT("the dynamic-fragments handler is registered"), Handler))
    { return false; }

    const auto Produced = Handler->Produce(SaveOwner);
    if (NOT TestTrue(TEXT("Produce emitted a payload"), Produced.IsSet()))
    { return false; }

    const auto Blob = SerializeBlob_Save(Produced.GetValue());
    const auto Restored = DeserializeBlob(Blob, RegistryHandle);
    if (NOT TestTrue(TEXT("payload deserialized to the dynamic-fragments wrapper"),
        Restored.GetScriptStruct() == FCk_SaveData_DynamicFragments::StaticStruct()))
    { return false; }

    // ---- Load side: construction replay composed both fragments fresh ------------------------------------
    auto LoadOwner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    {
        UCk_Utils_DynamicFragment_UE::Add_Fragment(
            LoadOwner, FInstancedStruct::Make(FCk_Test_TypeHydrated_Alpha{}), ECk_Replication::DoesNotReplicate);
        UCk_Utils_DynamicFragment_UE::Add_Fragment(
            LoadOwner, FInstancedStruct::Make(FCk_Test_TypeHydrated_Beta{}), ECk_Replication::DoesNotReplicate);
    }

    auto Witness = TStrongObjectPtr<UCk_Test_TypeHydrated_Witness>{NewObject<UCk_Test_TypeHydrated_Witness>()};

    auto TypeHydratedDelegate = FCk_Delegate_Hydration_OnTypeHydrated{};
    TypeHydratedDelegate.BindUFunction(Witness.Get(), TEXT("HandleTypeHydrated"));
    CK_SIGNAL_BIND(ck::UUtils_Signal_Hydration_OnTypeHydrated, LoadOwner, TypeHydratedDelegate,
        ECk_Signal_BindingPolicy::IgnorePayloadInFlight, ECk_Signal_PostFireBehavior::DoNothing);

    auto RepNotifyDelegate = FCk_DynamicFragment_OnRepNotify{};
    RepNotifyDelegate.BindUFunction(Witness.Get(), TEXT("HandleRepNotify"));
    CK_SIGNAL_BIND(ck::UUtils_Signal_DynamicFragment_OnRepNotify, LoadOwner, RepNotifyDelegate,
        ECk_Signal_BindingPolicy::IgnorePayloadInFlight, ECk_Signal_PostFireBehavior::DoNothing);

    auto LoadOwnerRef = LoadOwner;
    const auto ApplyResult = Handler->HydrationApply(LoadOwnerRef, Restored, {});
    TestEqual(TEXT("HydrationApply returned Applied"),
        static_cast<int32>(ApplyResult), static_cast<int32>(ECk_Persistence_ApplyResult::Applied));

    // ---- The edge ----------------------------------------------------------------------------------------
    TestEqual(
        TEXT("Hydration_OnTypeHydrated fired once per hydrated TYPE"),
        Witness->_TypeHydratedCount, 2);

    TestEqual(
        TEXT("and the two edges named two DISTINCT types — one edge per entity would also count 2 if the "
             "same type were reported twice"),
        Witness->_TypeHydratedTypes.Num(), 2);

    TestTrue(
        TEXT("Alpha was named"),
        Witness->_TypeHydratedTypes.Contains(FCk_Test_TypeHydrated_Alpha::StaticStruct()));

    TestTrue(
        TEXT("Beta was named"),
        Witness->_TypeHydratedTypes.Contains(FCk_Test_TypeHydrated_Beta::StaticStruct()));

    TestEqual(
        TEXT("and OnRepNotify did NOT fire on the load path — it is the NET edge, and a load broadcasting it "
             "is what let a wire-update subscriber silently receive save-load events"),
        Witness->_RepNotifyCount, 0);

    // Every value is committed before the first edge, so a subscriber reading its sibling from inside the
    // callback sees the finished set — the same commit-then-notify guarantee the per-entity lift makes.
    const auto& HydratedAlpha = UCk_Utils_DynamicFragment_UE::Get_Fragment_TypeUnsafe(
        LoadOwner, FCk_Test_TypeHydrated_Alpha::StaticStruct()).Get<FCk_Test_TypeHydrated_Alpha>();
    const auto& HydratedBeta = UCk_Utils_DynamicFragment_UE::Get_Fragment_TypeUnsafe(
        LoadOwner, FCk_Test_TypeHydrated_Beta::StaticStruct()).Get<FCk_Test_TypeHydrated_Beta>();

    TestEqual(TEXT("Alpha hydrated to the saved value"), HydratedAlpha.Marker, SavedAlpha);
    TestEqual(TEXT("Beta hydrated to the saved value"), HydratedBeta.Marker, SavedBeta);

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
