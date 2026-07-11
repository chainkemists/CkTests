// Fidelity-oracle Tier-1 harness (spec §5, campaign Phase 0).
//
// Proves the structural oracle sees a Model-A save->wipe->restore round-trip as identity: capture a structural
// image, round-trip the registry through Model A, capture again, diff. Because Model A only round-trips
// REGISTERED-snapshotable fragments, the capture is taken through the registered-hash filter (an unfiltered diff
// would legitimately show the unregistered fragments Model A drops — not a bug).
//
// Mirrors Test_Snapshot_Core_RoundTrip.cpp's standalone-FEcsWorld setup.

#include "CkSnapshot/Snapshot/CkSnapshot_Capture.h"
#include "CkSnapshot/Snapshot/CkSnapshot_Restore.h"
#include "CkSnapshot/SaveGame/CkSnapshot_Header.h"
#include "CkSnapshot/Snapshot/CkSnapshot_LoadReport.h"

#include "CkEcs/Snapshot/CkSnapshot_Context.h"
#include "CkEcs/Snapshot/CkSnapshot_FragmentRegistry.h"
#include "CkEcs/Snapshot/CkSnapshot_FidelityOracle.h"
#include "CkEcs/Snapshot/CkSnapshot_Archive_Writer.h"
#include "CkEcs/Snapshot/CkSnapshot_Archive_Reader.h"

#include "CkEcs/World/CkEcsWorld.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"

#include "CkCore/Macros/CkMacros.h"

#include "Serialization/BufferArchive.h"
#include "Serialization/MemoryReader.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS && CK_WITH_FIDELITY_ORACLE

// --------------------------------------------------------------------------------------------------------------------
// Test-only snapshotable fragments (Tier-C). Distinct names from Test_Snapshot_Core_RoundTrip's so the CkTests
// unity build cannot collide file-scope symbols.
// --------------------------------------------------------------------------------------------------------------------

struct FFragment_SnapshotOracleTest_Value
{
    CK_GENERATED_BODY(FFragment_SnapshotOracleTest_Value);
    using IsSnapshotable = void;

public:
    int32 _Value = 0;

public:
    auto SerializeSnapshot(FArchive& InAr, ck::FSnapshotContext& /*InCtx*/) -> void
    {
        InAr << _Value;
    }
};

struct FFragment_SnapshotOracleTest_Ref
{
    CK_GENERATED_BODY(FFragment_SnapshotOracleTest_Ref);
    using IsSnapshotable = void;

public:
    FCk_Handle _Target;

public:
    auto SerializeSnapshot(FArchive& InAr, ck::FSnapshotContext& InCtx) -> void
    {
        InCtx.Snapshot_Handle(InAr, _Target);
    }
};

CK_REGISTER_SNAPSHOTABLE(FFragment_SnapshotOracleTest_Value);
CK_REGISTER_SNAPSHOTABLE(FFragment_SnapshotOracleTest_Ref);

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Oracle_StructuralBaseline_Test,
    "Ck.Snapshot.Oracle.StructuralBaseline",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Oracle_StructuralBaseline_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    constexpr auto KnownValue = 4242;

    // ---- Arrange: a private ECS world with two fragment-carrying entities --------------------------------------
    auto EcsWorld = ck::FEcsWorld{};

    auto* RawRegistry = ck::registry_table::TryResolve(EcsWorld.Get_Registry().Get_RegistryHandle());
    if (NOT TestNotNull(TEXT("Resolved raw entt registry from FEcsWorld"), RawRegistry))
    { return false; }

    auto TargetEntity   = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry());
    auto ReferrerEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry());

    if (NOT TestTrue(TEXT("Both entities valid"), ck::IsValid(TargetEntity) && ck::IsValid(ReferrerEntity)))
    { return false; }

    TargetEntity.Add<FFragment_SnapshotOracleTest_Value>().  _Value  = KnownValue;
    ReferrerEntity.Add<FFragment_SnapshotOracleTest_Ref>().  _Target = TargetEntity;

    // ---- Registered-hash filter (Model A only round-trips registered types) ------------------------------------
    auto RegisteredHashes = TSet<uint32>{};
    for (const auto& Registered : ck::FCk_Snapshot_FragmentRegistry::Get().Get_All())
    { RegisteredHashes.Add(Registered._EnttTypeHash); }

    // ---- Capture BEFORE ----------------------------------------------------------------------------------------
    const auto Before = ck::snapshot_oracle::Capture_Structural(*RawRegistry, &RegisteredHashes);
    TestTrue(TEXT("Before image is non-empty (fixture entities registered)"), Before._Entities.Num() >= 2);

    // ---- Model-A round trip: capture -> wipe/restore -----------------------------------------------------------
    auto Buffer = FBufferArchive{};
    auto Header = FCk_Snapshot_Header{};
    const auto CaptureResult = ck::snapshot::Run_Capture_Registry(*RawRegistry, Buffer, Header);
    if (NOT TestEqual(TEXT("Model-A capture Success"),
            static_cast<uint8>(CaptureResult), static_cast<uint8>(ECk_SnapshotResult::Success)))
    { return false; }

    auto Reader = FMemoryReader{Buffer, /*bIsPersistent=*/true};
    const auto Report = ck::snapshot::Run_Restore_Registry(*RawRegistry, Reader, Header);
    if (NOT TestEqual(TEXT("Model-A restore Success"),
            static_cast<uint8>(Report.Get_Result()), static_cast<uint8>(ECk_SnapshotResult::Success)))
    { return false; }

    // ---- Capture AFTER + diff ----------------------------------------------------------------------------------
    const auto After = ck::snapshot_oracle::Capture_Structural(*RawRegistry, &RegisteredHashes);

    auto Annotated = TArray<FString>{};
    const auto Diff = ck::snapshot_oracle::Diff_Structural(Before, After, /*Allowlist=*/{}, Annotated);

    if (Diff.Num() != 0)
    {
        for (const auto& Line : Diff)
        { AddError(FString::Printf(TEXT("Structural diff (filtered) after Model-A round-trip: %s"), *Line)); }
    }

    TestEqual(TEXT("Filtered structural diff is empty after a Model-A round-trip"), Diff.Num(), 0);

    return Diff.Num() == 0;
}

#endif // WITH_DEV_AUTOMATION_TESTS && CK_WITH_FIDELITY_ORACLE

// --------------------------------------------------------------------------------------------------------------------
