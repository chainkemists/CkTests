// Read-status matrix for the CkSnapshot offline inspection API. One test per row of the status table: a healthy
// current-format save, both entry routes (SaveGame object seam and engine envelope bytes), and every way a file can
// be absent, foreign, stale or corrupt. Nothing here is expected to fire an ensure — malformed input is the
// inspector's normal diet, so any ensure that DOES fire logs an Error and reds the test on its own.

#include "CkSnapshot/Inspection/CkSnapshot_Inspection.h"
#include "CkSnapshot/Inspection/CkSnapshot_Inspection_Sha256.h"
#include "CkSnapshot/SaveGame/CkSnapshot_Header.h"
#include "CkSnapshot/SaveGame/CkSnapshot_SaveGame.h"

#include "Test_Snapshot_DynamicFragment_Fixtures.h"
#include "Test_Snapshot_Inspection_Fixtures.h"

#include "CkCore/Macros/CkMacros.h"

#include "Kismet/GameplayStatics.h"
#include "Misc/AutomationTest.h"
#include "Misc/Paths.h"

#include <StructUtils/InstancedStruct.h>

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_snapshot_inspection_envelope
{
    constexpr auto k_EngineOwnedId = 100u;
    constexpr auto k_ConstructSpawnedId = 200u;

    const auto k_FixtureSaveKey = FGuid{0x11111111, 0x22222222, 0x33333333, 0x44444444};

    // One owner, one labeled child under it, one decodable payload on the child: the smallest table set that is
    // healthy against every intrinsic-defect rule at once.
    auto
        Make_HealthyTables()
        -> FCk_Snapshot_V3_Tables
    {
        auto Owner = ck_test_snapshot_inspection::Make_Entity(
            k_EngineOwnedId, ECk_Snapshot_V3_Provenance::EngineOwned);
        Owner.Set_SaveKey(k_FixtureSaveKey);

        auto Child = ck_test_snapshot_inspection::Make_Entity(
            k_ConstructSpawnedId, ECk_Snapshot_V3_Provenance::ConstructSpawned);
        Child.Set_LifetimeOwnerSavedId(k_EngineOwnedId)
             .Set_Label(TEXT("Test.Inspection.Child"));

        auto PureData = FCk_Test_DynFrag_PureData{};
        PureData.Count = 3;
        PureData.Label = TEXT("healthy");

        auto Tables = FCk_Snapshot_V3_Tables{};
        Tables.Get_Entities().Add(Owner);
        Tables.Get_Entities().Add(Child);
        Tables.Get_Payloads().Add(ck_test_snapshot_inspection::Make_Payload(
            k_ConstructSpawnedId,
            FCk_Test_DynFrag_PureData::StaticStruct()->GetPathName(),
            ck_test_snapshot_inspection::SerializeBlob_Save(FInstancedStruct::Make(PureData))));

        return Tables;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_ValidDocument_Test,
    "Ck.Snapshot.Inspection.ValidDocument",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_ValidDocument_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    const auto Tables = ck_test_snapshot_inspection_envelope::Make_HealthyTables();
    const auto Bytes = ck_test_snapshot_inspection::Get_TablesBytes(Tables);
    const auto Document = ck::snapshot::Inspect_SaveGameObject(
        ck_test_snapshot_inspection::Make_SaveGame(ck_test_snapshot_inspection::Get_HeaderFor(Tables), Bytes),
        TEXT("valid-document"));

    TestEqual(TEXT("Read status is Success"),
        static_cast<int32>(Document.Get_ReadStatus()), static_cast<int32>(ECk_SnapshotInspection_ReadStatus::Success));
    TestEqual(TEXT("Compatibility is Current"),
        static_cast<int32>(Document.Get_Compatibility()), static_cast<int32>(ECk_SnapshotInspection_Compatibility::Current));
    TestTrue(TEXT("Header recovered"), Document.Get_HeaderRecovered());
    TestTrue(TEXT("Table parse attempted"), Document.Get_TableParseAttempted());
    TestTrue(TEXT("Table parse succeeded"), Document.Get_TableParseSucceeded());

    TestEqual(TEXT("Two entity summaries in table order"), Document.Get_Entities().Num(), 2);
    TestEqual(TEXT("One payload summary"), Document.Get_Payloads().Num(), 1);
    TestEqual(TEXT("A healthy save raises no diagnostics at all"), Document.Get_Diagnostics().Num(), 0);
    TestEqual(TEXT("No errors"), Document.Get_ErrorCount(), 0);
    TestEqual(TEXT("No warnings"), Document.Get_WarningCount(), 0);

    const auto& Census = Document.Get_Census();
    TestEqual(TEXT("Census entity count"), Census.Get_EntityCount(), 2);
    TestEqual(TEXT("Census EngineOwned count"), Census.Get_EngineOwnedCount(), 1);
    TestEqual(TEXT("Census ConstructSpawned count"), Census.Get_ConstructSpawnedCount(), 1);
    TestEqual(TEXT("Census RuntimeSpawned count"), Census.Get_RuntimeSpawnedCount(), 0);
    TestEqual(TEXT("Census DefinitionBuilt count"), Census.Get_DefinitionBuiltCount(), 0);
    TestEqual(TEXT("Census payload count"), Census.Get_PayloadCount(), 1);

    // The SaveGame-object seam never sees an envelope, so the SOURCE byte count and hash stay unset while the
    // snapshot-stream ones are always recorded.
    TestEqual(TEXT("SaveGame-object route records no source byte count"),
        static_cast<int32>(Document.Get_SourceByteCount()), 0);
    TestTrue(TEXT("SaveGame-object route records no source hash"), Document.Get_SourceHashHex().IsEmpty());
    TestEqual(TEXT("Snapshot byte count matches the serialized tables"),
        static_cast<int32>(Document.Get_SnapshotByteCount()), Bytes.Num());
    TestEqual(TEXT("Snapshot hash is the SHA-256 of the table bytes"),
        Document.Get_SnapshotHashHex(), ck::snapshot::Get_Sha256Hex(Bytes));

    TestEqual(TEXT("Owner identity renders as its SaveKey"),
        Document.Get_Entities()[0].Get_IdentityText(),
        ck_test_snapshot_inspection_envelope::k_FixtureSaveKey.ToString());
    TestEqual(TEXT("Child identity renders as its label"),
        Document.Get_Entities()[1].Get_IdentityText(), FString{TEXT("Test.Inspection.Child")});
    TestFalse(TEXT("Owner row has no problems"), Document.Get_Entities()[0].Get_HasProblems());
    TestFalse(TEXT("Child row has no problems"), Document.Get_Entities()[1].Get_HasProblems());

    TestEqual(TEXT("Owner is indexable by saved id"),
        Document.TryGet_EntityIndexForSavedId(ck_test_snapshot_inspection_envelope::k_EngineOwnedId), 0);
    TestEqual(TEXT("Child is indexable by saved id"),
        Document.TryGet_EntityIndexForSavedId(ck_test_snapshot_inspection_envelope::k_ConstructSpawnedId), 1);
    TestEqual(TEXT("An absent saved id resolves to INDEX_NONE"),
        Document.TryGet_EntityIndexForSavedId(0xDEADBEEFu), INDEX_NONE);

    const auto& Payload = Document.Get_Payloads()[0];
    TestTrue(TEXT("Payload type is available in this editor"), Payload.Get_TypeAvailable());
    TestTrue(TEXT("Payload carries bytes"), Payload.Get_ByteCount() > 0);
    TestEqual(TEXT("Payload hash is the SHA-256 of its blob"),
        Payload.Get_PayloadHashHex(), ck::snapshot::Get_Sha256Hex(Payload.Get_Entry().Get_PayloadBytes()));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_EnvelopeRoute_Test,
    "Ck.Snapshot.Inspection.EnvelopeRoute",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_EnvelopeRoute_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    const auto Tables = ck_test_snapshot_inspection_envelope::Make_HealthyTables();
    auto* SaveGame = ck_test_snapshot_inspection::Make_SaveGame(
        ck_test_snapshot_inspection::Get_HeaderFor(Tables), ck_test_snapshot_inspection::Get_TablesBytes(Tables));

    auto EnvelopeBytes = TArray<uint8>{};
    if (NOT TestTrue(TEXT("Fixture serialized to an engine save envelope"),
        UGameplayStatics::SaveGameToMemory(SaveGame, EnvelopeBytes)))
    { return false; }

    const auto Document = ck::snapshot::Inspect_SaveBytes(EnvelopeBytes, TEXT("envelope-route"));

    TestEqual(TEXT("Read status is Success"),
        static_cast<int32>(Document.Get_ReadStatus()), static_cast<int32>(ECk_SnapshotInspection_ReadStatus::Success));
    TestEqual(TEXT("Source kind is Bytes"),
        static_cast<int32>(Document.Get_SourceKind()), static_cast<int32>(ECk_SnapshotInspection_SourceKind::Bytes));
    TestEqual(TEXT("Source byte count is the envelope size"),
        static_cast<int32>(Document.Get_SourceByteCount()), EnvelopeBytes.Num());
    TestEqual(TEXT("Source hash is the SHA-256 of the envelope"),
        Document.Get_SourceHashHex(), ck::snapshot::Get_Sha256Hex(EnvelopeBytes));
    TestEqual(TEXT("Envelope route records the save class"),
        Document.Get_SaveGameClassPath(), UCk_Snapshot_SaveGame::StaticClass()->GetPathName());

    TestEqual(TEXT("Census survives the envelope round-trip"), Document.Get_Census().Get_EntityCount(), 2);
    TestEqual(TEXT("Payload census survives the envelope round-trip"), Document.Get_Census().Get_PayloadCount(), 1);
    TestEqual(TEXT("Envelope route raises no diagnostics"), Document.Get_Diagnostics().Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_MissingFile_Test,
    "Ck.Snapshot.Inspection.MissingFile",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_MissingFile_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    const auto AbsentPath = FPaths::ConvertRelativePathToFull(
        FPaths::ProjectIntermediateDir() / TEXT("CkTests_Inspection_ThisFileDoesNotExist.sav"));

    const auto Document = ck::snapshot::Inspect_SaveFile(AbsentPath);

    TestEqual(TEXT("Read status is FileNotFound"),
        static_cast<int32>(Document.Get_ReadStatus()), static_cast<int32>(ECk_SnapshotInspection_ReadStatus::FileNotFound));
    TestEqual(TEXT("Source kind is File"),
        static_cast<int32>(Document.Get_SourceKind()), static_cast<int32>(ECk_SnapshotInspection_SourceKind::File));
    TestEqual(TEXT("Source description is the requested path"), Document.Get_SourceDescription(), AbsentPath);
    TestFalse(TEXT("No header recovered"), Document.Get_HeaderRecovered());
    TestFalse(TEXT("No table parse attempted"), Document.Get_TableParseAttempted());
    TestEqual(TEXT("No entity rows"), Document.Get_Entities().Num(), 0);
    TestEqual(TEXT("No diagnostics"), Document.Get_Diagnostics().Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_NotCkSnapshotBytes_Test,
    "Ck.Snapshot.Inspection.NotCkSnapshotBytes",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_NotCkSnapshotBytes_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    // Random content never carries the engine envelope tag, so the route stops before any UObject is created.
    auto RandomBytes = TArray<uint8>{};
    for (auto Index = 0; Index < 512; ++Index)
    { RandomBytes.Add(static_cast<uint8>((Index * 37 + 11) & 0xFF)); }

    const auto RandomDocument = ck::snapshot::Inspect_SaveBytes(RandomBytes, TEXT("random-bytes"));
    TestEqual(TEXT("Random bytes report NotCkSnapshot"),
        static_cast<int32>(RandomDocument.Get_ReadStatus()),
        static_cast<int32>(ECk_SnapshotInspection_ReadStatus::NotCkSnapshot));
    TestTrue(TEXT("Random bytes recover no save class"), RandomDocument.Get_SaveGameClassPath().IsEmpty());
    TestEqual(TEXT("Random bytes still record their source size"),
        static_cast<int32>(RandomDocument.Get_SourceByteCount()), RandomBytes.Num());

    // Fewer than four bytes cannot even hold the tag — the peek must short-circuit rather than read past the end.
    const auto ShortDocument = ck::snapshot::Inspect_SaveBytes(TArray<uint8>{0x47, 0x56, 0x41}, TEXT("short-bytes"));
    TestEqual(TEXT("A three-byte array reports NotCkSnapshot"),
        static_cast<int32>(ShortDocument.Get_ReadStatus()),
        static_cast<int32>(ECk_SnapshotInspection_ReadStatus::NotCkSnapshot));

    const auto EmptyDocument = ck::snapshot::Inspect_SaveBytes(TArray<uint8>{}, TEXT("empty-bytes"));
    TestEqual(TEXT("An empty array reports NotCkSnapshot"),
        static_cast<int32>(EmptyDocument.Get_ReadStatus()),
        static_cast<int32>(ECk_SnapshotInspection_ReadStatus::NotCkSnapshot));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_ForeignSaveGameClass_Test,
    "Ck.Snapshot.Inspection.ForeignSaveGameClass",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_ForeignSaveGameClass_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto* Foreign = NewObject<UCk_Test_NotSnapshot_SaveGame>(GetTransientPackage());
    Foreign->_Marker = 7;

    auto EnvelopeBytes = TArray<uint8>{};
    if (NOT TestTrue(TEXT("Foreign save serialized to an envelope"),
        UGameplayStatics::SaveGameToMemory(Foreign, EnvelopeBytes)))
    { return false; }

    const auto Document = ck::snapshot::Inspect_SaveBytes(EnvelopeBytes, TEXT("foreign-class"));

    TestEqual(TEXT("A foreign save class reports NotCkSnapshot"),
        static_cast<int32>(Document.Get_ReadStatus()),
        static_cast<int32>(ECk_SnapshotInspection_ReadStatus::NotCkSnapshot));
    TestEqual(TEXT("The foreign class is recorded — the only clue the file offers"),
        Document.Get_SaveGameClassPath(), UCk_Test_NotSnapshot_SaveGame::StaticClass()->GetPathName());
    TestFalse(TEXT("No header recovered from a foreign save"), Document.Get_HeaderRecovered());
    TestEqual(TEXT("No entity rows"), Document.Get_Entities().Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_CorruptEnvelope_Test,
    "Ck.Snapshot.Inspection.CorruptEnvelope",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_CorruptEnvelope_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    const auto Tables = ck_test_snapshot_inspection_envelope::Make_HealthyTables();
    auto* SaveGame = ck_test_snapshot_inspection::Make_SaveGame(
        ck_test_snapshot_inspection::Get_HeaderFor(Tables), ck_test_snapshot_inspection::Get_TablesBytes(Tables));

    auto EnvelopeBytes = TArray<uint8>{};
    if (NOT TestTrue(TEXT("Fixture serialized to an engine save envelope"),
        UGameplayStatics::SaveGameToMemory(SaveGame, EnvelopeBytes)))
    { return false; }

    // The envelope names its save class as a plain ANSI path. Rewriting one character of the class NAME (the package
    // is left intact, so nothing is asked to load) makes the envelope unloadable without disturbing its framing.
    const auto RealClassPath = UCk_Snapshot_SaveGame::StaticClass()->GetPathName();
    if (NOT TestTrue(TEXT("Envelope class path patched"),
        ck_test_snapshot_inspection::DoPatch_StringOnce(EnvelopeBytes, RealClassPath,
            ck_test_snapshot_inspection::Get_UnresolvablePathFor(RealClassPath))))
    { return false; }

    const auto Document = ck::snapshot::Inspect_SaveBytes(EnvelopeBytes, TEXT("corrupt-envelope"));

    TestEqual(TEXT("An unloadable envelope reports CorruptEnvelope"),
        static_cast<int32>(Document.Get_ReadStatus()),
        static_cast<int32>(ECk_SnapshotInspection_ReadStatus::CorruptEnvelope));
    TestFalse(TEXT("No header recovered"), Document.Get_HeaderRecovered());
    TestEqual(TEXT("No entity rows"), Document.Get_Entities().Num(), 0);
    TestEqual(TEXT("The source hash is still recorded"),
        Document.Get_SourceHashHex(), ck::snapshot::Get_Sha256Hex(EnvelopeBytes));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_UnsupportedFormat_Test,
    "Ck.Snapshot.Inspection.UnsupportedFormat",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_UnsupportedFormat_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    const auto Tables = ck_test_snapshot_inspection_envelope::Make_HealthyTables();
    const auto Bytes = ck_test_snapshot_inspection::Get_TablesBytes(Tables);

    // Version 5: readable metadata, but the current table struct must never be fed an older layout — it would
    // deserialize nonsense and report success.
    auto OlderHeader = ck_test_snapshot_inspection::Get_HeaderFor(Tables);
    OlderHeader.Set_FormatVersion(static_cast<uint16>(5));

    const auto OlderDocument = ck::snapshot::Inspect_SaveGameObject(
        ck_test_snapshot_inspection::Make_SaveGame(OlderHeader, Bytes), TEXT("format-5"));

    TestEqual(TEXT("Version 5 reports UnsupportedFormat"),
        static_cast<int32>(OlderDocument.Get_ReadStatus()),
        static_cast<int32>(ECk_SnapshotInspection_ReadStatus::UnsupportedFormat));
    TestEqual(TEXT("Version 5 is Older"),
        static_cast<int32>(OlderDocument.Get_Compatibility()),
        static_cast<int32>(ECk_SnapshotInspection_Compatibility::Older));
    TestTrue(TEXT("Header is still recovered"), OlderDocument.Get_HeaderRecovered());
    TestEqual(TEXT("Header metadata is retained"),
        OlderDocument.Get_Header().Get_EngineVersion(), FString{TEXT("CkTests-Inspection-Fixture")});
    TestEqual(TEXT("Header format version is retained verbatim"),
        static_cast<int32>(OlderDocument.Get_Header().Get_FormatVersion()), 5);
    TestEqual(TEXT("Raw snapshot bytes are still measured"),
        static_cast<int32>(OlderDocument.Get_SnapshotByteCount()), Bytes.Num());
    TestEqual(TEXT("Raw snapshot bytes are still hashed"),
        OlderDocument.Get_SnapshotHashHex(), ck::snapshot::Get_Sha256Hex(Bytes));
    TestFalse(TEXT("Tables are NOT parsed for an incompatible stream"), OlderDocument.Get_TableParseAttempted());
    TestEqual(TEXT("No entity rows from an unparsed table"), OlderDocument.Get_Entities().Num(), 0);
    TestEqual(TEXT("No diagnostics from an unparsed table"), OlderDocument.Get_Diagnostics().Num(), 0);

    auto NewerHeader = ck_test_snapshot_inspection::Get_HeaderFor(Tables);
    NewerHeader.Set_FormatVersion(static_cast<uint16>(FCk_Snapshot_HeaderV3::CurrentFormatVersion + 1));

    const auto NewerDocument = ck::snapshot::Inspect_SaveGameObject(
        ck_test_snapshot_inspection::Make_SaveGame(NewerHeader, Bytes), TEXT("format-next"));

    TestEqual(TEXT("A future version reports UnsupportedFormat"),
        static_cast<int32>(NewerDocument.Get_ReadStatus()),
        static_cast<int32>(ECk_SnapshotInspection_ReadStatus::UnsupportedFormat));
    TestEqual(TEXT("A future version is Newer"),
        static_cast<int32>(NewerDocument.Get_Compatibility()),
        static_cast<int32>(ECk_SnapshotInspection_Compatibility::Newer));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_CorruptTables_Test,
    "Ck.Snapshot.Inspection.CorruptTables",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_CorruptTables_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    // Feeding a truncated stream to the engine's tagged-property SerializeItem makes LogClass emit
    // "Failed loading tagged ..." at Error severity before the reader's error flag lands. Those lines come from
    // the ENGINE, are the expected companion of corrupt input, and do not indicate a product defect. Occurrences
    // -1: tolerated in any count — the CorruptTables status below is the assertion, not the engine's log shape.
    AddExpectedError(TEXT("Failed loading tagged"), EAutomationExpectedErrorFlags::Contains, -1);

    const auto Tables = ck_test_snapshot_inspection_envelope::Make_HealthyTables();
    const auto Bytes = ck_test_snapshot_inspection::Get_TablesBytes(Tables);
    const auto Header = ck_test_snapshot_inspection::Get_HeaderFor(Tables);

    auto Truncated = Bytes;
    Truncated.SetNum(Bytes.Num() / 2);

    const auto TruncatedDocument = ck::snapshot::Inspect_SaveGameObject(
        ck_test_snapshot_inspection::Make_SaveGame(Header, Truncated), TEXT("truncated-tables"));

    TestEqual(TEXT("A truncated table stream reports CorruptTables"),
        static_cast<int32>(TruncatedDocument.Get_ReadStatus()),
        static_cast<int32>(ECk_SnapshotInspection_ReadStatus::CorruptTables));
    TestTrue(TEXT("The parse was attempted"), TruncatedDocument.Get_TableParseAttempted());
    TestFalse(TEXT("The parse did not succeed"), TruncatedDocument.Get_TableParseSucceeded());
    TestEqual(TEXT("No entity rows survive a failed parse"), TruncatedDocument.Get_Entities().Num(), 0);
    TestEqual(TEXT("No diagnostics are produced without tables"), TruncatedDocument.Get_Diagnostics().Num(), 0);

    // Trailing bytes past the table struct mean the stream is not what the header claims, even though every byte the
    // struct wanted was there.
    auto WithTrailing = Bytes;
    WithTrailing.Append(TArray<uint8>{0xAA, 0xBB, 0xCC, 0xDD});

    const auto TrailingDocument = ck::snapshot::Inspect_SaveGameObject(
        ck_test_snapshot_inspection::Make_SaveGame(Header, WithTrailing), TEXT("trailing-tables"));

    TestEqual(TEXT("Trailing table bytes report CorruptTables"),
        static_cast<int32>(TrailingDocument.Get_ReadStatus()),
        static_cast<int32>(ECk_SnapshotInspection_ReadStatus::CorruptTables));
    TestTrue(TEXT("The trailing-byte parse was attempted"), TrailingDocument.Get_TableParseAttempted());
    TestFalse(TEXT("The trailing-byte parse did not succeed"), TrailingDocument.Get_TableParseSucceeded());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_EmptySnapshotBytes_Test,
    "Ck.Snapshot.Inspection.EmptySnapshotBytes",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_EmptySnapshotBytes_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    const auto Tables = ck_test_snapshot_inspection_envelope::Make_HealthyTables();
    const auto Header = ck_test_snapshot_inspection::Get_HeaderFor(Tables);

    const auto Document = ck::snapshot::Inspect_SaveGameObject(
        ck_test_snapshot_inspection::Make_SaveGame(Header, TArray<uint8>{}), TEXT("empty-snapshot-bytes"));

    TestEqual(TEXT("An empty table stream reports CorruptEnvelope"),
        static_cast<int32>(Document.Get_ReadStatus()),
        static_cast<int32>(ECk_SnapshotInspection_ReadStatus::CorruptEnvelope));
    TestTrue(TEXT("Header is still recovered"), Document.Get_HeaderRecovered());
    TestEqual(TEXT("Compatibility is Current"),
        static_cast<int32>(Document.Get_Compatibility()),
        static_cast<int32>(ECk_SnapshotInspection_Compatibility::Current));
    TestFalse(TEXT("No parse is attempted on an empty stream"), Document.Get_TableParseAttempted());
    TestEqual(TEXT("Snapshot byte count is zero"), static_cast<int32>(Document.Get_SnapshotByteCount()), 0);
    TestEqual(TEXT("An empty stream still hashes to the empty-input digest"), Document.Get_SnapshotHashHex(),
        FString{TEXT("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")});

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_NullSaveGameObject_Test,
    "Ck.Snapshot.Inspection.NullSaveGameObject",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_NullSaveGameObject_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    const auto Document = ck::snapshot::Inspect_SaveGameObject(nullptr, TEXT("null-save-game"));

    TestEqual(TEXT("A null save object reports NotCkSnapshot"),
        static_cast<int32>(Document.Get_ReadStatus()),
        static_cast<int32>(ECk_SnapshotInspection_ReadStatus::NotCkSnapshot));
    TestEqual(TEXT("Source kind is SaveGameObject"),
        static_cast<int32>(Document.Get_SourceKind()),
        static_cast<int32>(ECk_SnapshotInspection_SourceKind::SaveGameObject));
    TestFalse(TEXT("No header recovered"), Document.Get_HeaderRecovered());

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
