// Lazy-decode and value-tree projection for the CkSnapshot offline inspection API. The load-bearing property here is
// that decoding is entirely offline: the source entities' registry is destroyed before any decode runs, and a
// handle-typed field still projects as a SavedEntityRef carrying the RAW saved id — never a live handle, never a
// registry lookup. Every malformed blob reports an explicit status instead of firing an ensure.

#include "CkSnapshot/Inspection/CkSnapshot_Inspection.h"
#include "CkSnapshot/SaveGame/CkSnapshot_Header.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "Test_Snapshot_DynamicFragment_Fixtures.h"
#include "Test_Snapshot_Inspection_Fixtures.h"

#include "CkCore/Macros/CkMacros.h"

#include "GameFramework/SaveGame.h"
#include "Misc/AutomationTest.h"

#include <StructUtils/InstancedStruct.h>

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_snapshot_inspection_decode
{
    constexpr auto k_OwnerId = 100u;

    auto
        Make_OwnerOnlyTables()
        -> FCk_Snapshot_V3_Tables
    {
        auto Tables = FCk_Snapshot_V3_Tables{};
        Tables.Get_Entities().Add(ck_test_snapshot_inspection::Make_Entity(
            k_OwnerId, ECk_Snapshot_V3_Provenance::EngineOwned));
        return Tables;
    }

    auto
        Get_PureDataBlob()
        -> TArray<uint8>
    {
        auto PureData = FCk_Test_DynFrag_PureData{};
        PureData.Count = 12;
        PureData.Label = TEXT("decoded");
        return ck_test_snapshot_inspection::SerializeBlob_Save(FInstancedStruct::Make(PureData));
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_PayloadValueTree_Test,
    "Ck.Snapshot.Inspection.PayloadValueTree",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_PayloadValueTree_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto SingleId = 0u;
    auto ArrayElementId = 0u;
    auto Blob = TArray<uint8>{};

    // The world lives only long enough to mint the saved ids and write the blob. Everything below runs against a
    // registry that no longer exists, which is the whole offline contract.
    {
        auto EcsWorld = ck::FEcsWorld{};
        auto& CkRegistry = EcsWorld.Get_Registry();

        auto SingleTarget = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
        auto ArrayTarget = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);

        SingleId = static_cast<uint32>(SingleTarget.Get_Entity().Get_ID());
        ArrayElementId = static_cast<uint32>(ArrayTarget.Get_Entity().Get_ID());

        auto Fragment = FCk_Test_DynFrag_WithHandle{};
        Fragment.Marker = 42;
        Fragment.TargetHandle = SingleTarget;
        Fragment.TargetArray = { ArrayTarget };

        Blob = ck_test_snapshot_inspection::SerializeBlob_Save(FInstancedStruct::Make(Fragment));
    }

    if (NOT TestTrue(TEXT("Fixture blob is non-empty"), Blob.Num() > 0))
    { return false; }

    const auto TypePath = FCk_Test_DynFrag_WithHandle::StaticStruct()->GetPathName();

    auto Tables = ck_test_snapshot_inspection_decode::Make_OwnerOnlyTables();
    Tables.Get_Payloads().Add(ck_test_snapshot_inspection::Make_Payload(
        ck_test_snapshot_inspection_decode::k_OwnerId, TypePath, Blob));

    const auto Document = ck_test_snapshot_inspection::Inspect_Tables(Tables);
    const auto Result = ck::snapshot::TryDecode_Payload(
        Document, 0, ECk_SnapshotInspection_DecodePolicy::AvailableTypesOnly);

    TestEqual(TEXT("The payload decoded"),
        static_cast<int32>(Result.Get_Status()), static_cast<int32>(ECk_SnapshotInspection_DecodeStatus::Decoded));
    TestEqual(TEXT("Declared type path is carried through"), Result.Get_DeclaredTypePath(), TypePath);
    TestEqual(TEXT("Decoded type path matches the declaration"), Result.Get_DecodedTypePath(), TypePath);
    TestTrue(TEXT("Decode reported no error text"), Result.Get_ErrorText().IsEmpty());

    const auto Root = Result.Get_ValueTreeRoot();
    if (NOT TestTrue(TEXT("A value tree was produced"), Root.IsValid()))
    { return false; }

    TestEqual(TEXT("Root is a struct node"),
        static_cast<int32>(Root->Get_Kind()), static_cast<int32>(ECk_SnapshotInspection_ValueKind::Struct));
    TestEqual(TEXT("Root carries the decoded type path"), Root->Get_TypeName(), TypePath);
    TestEqual(TEXT("Root has one node per reflected field"), Root->Get_Children().Num(), 3);

    const auto MarkerNode = ck_test_snapshot_inspection::TryGet_ValueChild(Root, TEXT("Marker"));
    if (NOT TestTrue(TEXT("Scalar field projected"), MarkerNode.IsValid()))
    { return false; }

    TestEqual(TEXT("Scalar field is an Int"),
        static_cast<int32>(MarkerNode->Get_Kind()), static_cast<int32>(ECk_SnapshotInspection_ValueKind::Int));
    TestEqual(TEXT("Scalar field round-tripped its value"), MarkerNode->Get_ValueText(), FString{TEXT("42")});

    const auto SingleNode = ck_test_snapshot_inspection::TryGet_ValueChild(Root, TEXT("TargetHandle"));
    if (NOT TestTrue(TEXT("Handle field projected"), SingleNode.IsValid()))
    { return false; }

    TestEqual(TEXT("Handle field is a SavedEntityRef leaf"),
        static_cast<int32>(SingleNode->Get_Kind()),
        static_cast<int32>(ECk_SnapshotInspection_ValueKind::SavedEntityRef));
    TestEqual(TEXT("Handle field carries the source entity's raw saved id"),
        static_cast<int64>(SingleNode->Get_SavedId()), static_cast<int64>(SingleId));
    TestTrue(TEXT("Handle field renders as a saved reference"),
        SingleNode->Get_ValueText().Contains(TEXT("SavedEntityRef:")));
    TestEqual(TEXT("A SavedEntityRef leaf has no children"), SingleNode->Get_Children().Num(), 0);

    const auto ArrayNode = ck_test_snapshot_inspection::TryGet_ValueChild(Root, TEXT("TargetArray"));
    if (NOT TestTrue(TEXT("Handle array projected"), ArrayNode.IsValid()))
    { return false; }

    TestEqual(TEXT("Handle array is an Array node"),
        static_cast<int32>(ArrayNode->Get_Kind()), static_cast<int32>(ECk_SnapshotInspection_ValueKind::Array));
    if (NOT TestEqual(TEXT("Handle array kept its single element"), ArrayNode->Get_Children().Num(), 1))
    { return false; }

    const auto ElementNode = ArrayNode->Get_Children()[0];
    TestEqual(TEXT("Array element is a SavedEntityRef leaf"),
        static_cast<int32>(ElementNode->Get_Kind()),
        static_cast<int32>(ECk_SnapshotInspection_ValueKind::SavedEntityRef));
    TestEqual(TEXT("Array element carries its source entity's raw saved id"),
        static_cast<int64>(ElementNode->Get_SavedId()), static_cast<int64>(ArrayElementId));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_SpawnParamsDecode_Test,
    "Ck.Snapshot.Inspection.SpawnParamsDecode",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_SpawnParamsDecode_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    const auto Blob = ck_test_snapshot_inspection_decode::Get_PureDataBlob();

    auto Runtime = ck_test_snapshot_inspection::Make_Entity(300u, ECk_Snapshot_V3_Provenance::RuntimeSpawned);
    Runtime.Set_ScriptClassPath(USaveGame::StaticClass()->GetPathName())
           .Set_SpawnParamsBytes(Blob);

    auto Tables = FCk_Snapshot_V3_Tables{};
    Tables.Get_Entities().Add(Runtime);

    const auto Document = ck_test_snapshot_inspection::Inspect_Tables(Tables);

    TestEqual(TEXT("Spawn-params byte count is surfaced on the summary"),
        Document.Get_Entities()[0].Get_SpawnParamsByteCount(), Blob.Num());

    const auto Result = ck::snapshot::TryDecode_SpawnParams(
        Document, 0, ECk_SnapshotInspection_DecodePolicy::AvailableTypesOnly);

    TestEqual(TEXT("Spawn params decoded"),
        static_cast<int32>(Result.Get_Status()), static_cast<int32>(ECk_SnapshotInspection_DecodeStatus::Decoded));

    // Spawn params declare no type path, so the mismatch outcome cannot arise on this route.
    TestTrue(TEXT("Spawn params declare no type"), Result.Get_DeclaredTypePath().IsEmpty());
    TestEqual(TEXT("The stream still names the struct it holds"),
        Result.Get_DecodedTypePath(), FCk_Test_DynFrag_PureData::StaticStruct()->GetPathName());

    const auto Root = Result.Get_ValueTreeRoot();
    if (NOT TestTrue(TEXT("A value tree was produced"), Root.IsValid()))
    { return false; }

    const auto CountNode = ck_test_snapshot_inspection::TryGet_ValueChild(Root, TEXT("Count"));
    const auto LabelNode = ck_test_snapshot_inspection::TryGet_ValueChild(Root, TEXT("Label"));

    if (NOT TestTrue(TEXT("Both fields projected"), CountNode.IsValid() && LabelNode.IsValid()))
    { return false; }

    TestEqual(TEXT("Int field round-tripped"), CountNode->Get_ValueText(), FString{TEXT("12")});
    TestEqual(TEXT("String field is a String node"),
        static_cast<int32>(LabelNode->Get_Kind()), static_cast<int32>(ECk_SnapshotInspection_ValueKind::String));
    TestEqual(TEXT("String field round-tripped"), LabelNode->Get_ValueText(), FString{TEXT("decoded")});

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_TransientHandleField_Test,
    "Ck.Snapshot.Inspection.TransientHandleField",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_TransientHandleField_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto Blob = TArray<uint8>{};
    {
        auto EcsWorld = ck::FEcsWorld{};
        auto& CkRegistry = EcsWorld.Get_Registry();
        auto RuntimeChild = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);

        auto Fragment = FCk_Test_DynFrag_MixedTransient{};
        Fragment.DurableMarker = 9;
        Fragment.RuntimeMarker = 77;
        Fragment.RuntimeChild = RuntimeChild;

        Blob = ck_test_snapshot_inspection::SerializeBlob_Save(FInstancedStruct::Make(Fragment));
    }

    auto Tables = ck_test_snapshot_inspection_decode::Make_OwnerOnlyTables();
    Tables.Get_Payloads().Add(ck_test_snapshot_inspection::Make_Payload(
        ck_test_snapshot_inspection_decode::k_OwnerId,
        FCk_Test_DynFrag_MixedTransient::StaticStruct()->GetPathName(), Blob));

    const auto Document = ck_test_snapshot_inspection::Inspect_Tables(Tables);
    const auto Result = ck::snapshot::TryDecode_Payload(
        Document, 0, ECk_SnapshotInspection_DecodePolicy::AvailableTypesOnly);

    TestEqual(TEXT("The payload decoded"),
        static_cast<int32>(Result.Get_Status()), static_cast<int32>(ECk_SnapshotInspection_DecodeStatus::Decoded));

    const auto Root = Result.Get_ValueTreeRoot();
    if (NOT TestTrue(TEXT("A value tree was produced"), Root.IsValid()))
    { return false; }

    const auto DurableNode = ck_test_snapshot_inspection::TryGet_ValueChild(Root, TEXT("DurableMarker"));
    if (NOT TestTrue(TEXT("Durable field projected"), DurableNode.IsValid()))
    { return false; }

    TestEqual(TEXT("Durable field round-tripped"), DurableNode->Get_ValueText(), FString{TEXT("9")});

    // The save's handle walk skips CPF_Transient fields on both sides, so the file holds no id for this field and the
    // projection must say so rather than report the freshly-constructed in-place value as a saved reference.
    const auto TransientNode = ck_test_snapshot_inspection::TryGet_ValueChild(Root, TEXT("RuntimeChild"));
    if (NOT TestTrue(TEXT("Transient handle field projected"), TransientNode.IsValid()))
    { return false; }

    TestEqual(TEXT("Transient handle field is still a SavedEntityRef kind"),
        static_cast<int32>(TransientNode->Get_Kind()),
        static_cast<int32>(ECk_SnapshotInspection_ValueKind::SavedEntityRef));
    TestEqual(TEXT("Transient handle field declares that it was not persisted"),
        TransientNode->Get_ValueText(), FString{TEXT("transient - not persisted")});
    TestEqual(TEXT("Transient handle field carries no saved id"),
        static_cast<int64>(TransientNode->Get_SavedId()), static_cast<int64>(ck::snapshot::k_NoSavedEntity));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_DeclaredTypeMismatch_Test,
    "Ck.Snapshot.Inspection.DeclaredTypeMismatch",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_DeclaredTypeMismatch_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto Fragment = FCk_Test_DynFrag_WithHandle{};
    Fragment.Marker = 5;

    const auto Blob = ck_test_snapshot_inspection::SerializeBlob_Save(FInstancedStruct::Make(Fragment));
    const auto DeclaredPath = FCk_Test_DynFrag_PureData::StaticStruct()->GetPathName();
    const auto ActualPath = FCk_Test_DynFrag_WithHandle::StaticStruct()->GetPathName();

    auto Tables = ck_test_snapshot_inspection_decode::Make_OwnerOnlyTables();
    Tables.Get_Payloads().Add(ck_test_snapshot_inspection::Make_Payload(
        ck_test_snapshot_inspection_decode::k_OwnerId, DeclaredPath, Blob));

    const auto Document = ck_test_snapshot_inspection::Inspect_Tables(Tables);
    const auto Result = ck::snapshot::TryDecode_Payload(
        Document, 0, ECk_SnapshotInspection_DecodePolicy::AvailableTypesOnly);

    TestEqual(TEXT("A blob that is not what the row declares reports DeclaredTypeMismatch"),
        static_cast<int32>(Result.Get_Status()),
        static_cast<int32>(ECk_SnapshotInspection_DecodeStatus::DeclaredTypeMismatch));
    TestEqual(TEXT("Both paths are reported — declared"), Result.Get_DeclaredTypePath(), DeclaredPath);
    TestEqual(TEXT("Both paths are reported — decoded"), Result.Get_DecodedTypePath(), ActualPath);
    TestFalse(TEXT("Decode error text is populated"), Result.Get_ErrorText().IsEmpty());

    // A tree whose type claim is a lie is worse than no tree.
    TestFalse(TEXT("No value tree is offered for a mismatched type"), Result.Get_ValueTreeRoot().IsValid());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_TrailingBlobBytes_Test,
    "Ck.Snapshot.Inspection.TrailingBlobBytes",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_TrailingBlobBytes_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto WithTrailing = ck_test_snapshot_inspection_decode::Get_PureDataBlob();
    WithTrailing.Append(TArray<uint8>{0xAA, 0xBB, 0xCC, 0xDD});

    auto Tables = ck_test_snapshot_inspection_decode::Make_OwnerOnlyTables();
    Tables.Get_Payloads().Add(ck_test_snapshot_inspection::Make_Payload(
        ck_test_snapshot_inspection_decode::k_OwnerId,
        FCk_Test_DynFrag_PureData::StaticStruct()->GetPathName(), WithTrailing));

    const auto Document = ck_test_snapshot_inspection::Inspect_Tables(Tables);
    const auto Result = ck::snapshot::TryDecode_Payload(
        Document, 0, ECk_SnapshotInspection_DecodePolicy::AvailableTypesOnly);

    // A healthy blob is exactly [tagged payload][one uint32 per handle]; leftovers mean it is not the struct claimed.
    TestEqual(TEXT("Trailing bytes report DeserializeFailed"),
        static_cast<int32>(Result.Get_Status()),
        static_cast<int32>(ECk_SnapshotInspection_DecodeStatus::DeserializeFailed));
    TestTrue(TEXT("The error text names the trailing bytes"),
        Result.Get_ErrorText().Contains(TEXT("trailing")));
    TestFalse(TEXT("No value tree is offered"), Result.Get_ValueTreeRoot().IsValid());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_EmptyBlobDecode_Test,
    "Ck.Snapshot.Inspection.EmptyBlobDecode",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_EmptyBlobDecode_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto Tables = ck_test_snapshot_inspection_decode::Make_OwnerOnlyTables();
    Tables.Get_Payloads().Add(ck_test_snapshot_inspection::Make_Payload(
        ck_test_snapshot_inspection_decode::k_OwnerId,
        FCk_Test_DynFrag_PureData::StaticStruct()->GetPathName(), TArray<uint8>{}));

    const auto Document = ck_test_snapshot_inspection::Inspect_Tables(Tables);
    const auto Result = ck::snapshot::TryDecode_Payload(
        Document, 0, ECk_SnapshotInspection_DecodePolicy::AvailableTypesOnly);

    TestEqual(TEXT("An empty blob reports DeserializeFailed"),
        static_cast<int32>(Result.Get_Status()),
        static_cast<int32>(ECk_SnapshotInspection_DecodeStatus::DeserializeFailed));
    TestEqual(TEXT("The error text names the empty blob"),
        Result.Get_ErrorText(), FString{TEXT("empty blob")});

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_DecodeTypeUnavailable_Test,
    "Ck.Snapshot.Inspection.DecodeTypeUnavailable",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_DecodeTypeUnavailable_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    const auto RealPath = FCk_Test_DynFrag_PureData::StaticStruct()->GetPathName();
    const auto UnresolvablePath = ck_test_snapshot_inspection::Get_UnresolvablePathFor(RealPath);

    // The struct path rides the blob as a plain ANSI string; rewriting it with an equal-length replacement is the
    // only way to fabricate a payload naming a type this editor genuinely cannot resolve.
    auto OpaqueBlob = ck_test_snapshot_inspection_decode::Get_PureDataBlob();
    if (NOT TestTrue(TEXT("Blob type path patched to an unresolvable one"),
        ck_test_snapshot_inspection::DoPatch_StringOnce(OpaqueBlob, RealPath, UnresolvablePath)))
    { return false; }

    auto Tables = ck_test_snapshot_inspection_decode::Make_OwnerOnlyTables();
    Tables.Get_Payloads().Add(ck_test_snapshot_inspection::Make_Payload(
        ck_test_snapshot_inspection_decode::k_OwnerId, UnresolvablePath, OpaqueBlob));
    Tables.Get_Payloads().Add(ck_test_snapshot_inspection::Make_Payload(
        ck_test_snapshot_inspection_decode::k_OwnerId, RealPath,
        ck_test_snapshot_inspection_decode::Get_PureDataBlob()));

    const auto Document = ck_test_snapshot_inspection::Inspect_Tables(Tables);

    const auto OpaqueResult = ck::snapshot::TryDecode_Payload(
        Document, 0, ECk_SnapshotInspection_DecodePolicy::AvailableTypesOnly);

    // AvailableTypesOnly never loads a package, so an absent type is an environment fact, not a broken file.
    TestEqual(TEXT("An unresolvable struct reports TypeUnavailable"),
        static_cast<int32>(OpaqueResult.Get_Status()),
        static_cast<int32>(ECk_SnapshotInspection_DecodeStatus::TypeUnavailable));
    TestEqual(TEXT("The declared path is still reported"), OpaqueResult.Get_DeclaredTypePath(), UnresolvablePath);
    TestFalse(TEXT("No value tree is offered"), OpaqueResult.Get_ValueTreeRoot().IsValid());
    TestFalse(TEXT("Decode error text is populated"), OpaqueResult.Get_ErrorText().IsEmpty());

    // One opaque row never blocks the rest of the document.
    const auto SiblingResult = ck::snapshot::TryDecode_Payload(
        Document, 1, ECk_SnapshotInspection_DecodePolicy::AvailableTypesOnly);

    TestEqual(TEXT("The sibling payload still decodes"),
        static_cast<int32>(SiblingResult.Get_Status()),
        static_cast<int32>(ECk_SnapshotInspection_DecodeStatus::Decoded));
    TestTrue(TEXT("The sibling payload still projects a tree"), SiblingResult.Get_ValueTreeRoot().IsValid());
    TestEqual(TEXT("The document still reports both rows"), Document.Get_Payloads().Num(), 2);
    TestEqual(TEXT("The opaque row raised no error"), Document.Get_ErrorCount(), 0);

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
