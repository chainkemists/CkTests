// SHA-256 vectors and whole-document determinism. The digests are the identity a save is quoted by in a bug report,
// so they are pinned against FIPS 180-4 known answers rather than against the implementation's own output, and two
// inspections of identical bytes must agree on every observable field — hashes, census, and the diagnostic sequence.

#include "CkSnapshot/Inspection/CkSnapshot_Inspection.h"
#include "CkSnapshot/Inspection/CkSnapshot_Inspection_Sha256.h"
#include "CkSnapshot/SaveGame/CkSnapshot_Header.h"
#include "CkSnapshot/SaveGame/CkSnapshot_SaveGame.h"

#include "Test_Snapshot_DynamicFragment_Fixtures.h"
#include "Test_Snapshot_Inspection_Fixtures.h"

#include "CkCore/Macros/CkMacros.h"

#include "Kismet/GameplayStatics.h"
#include "Misc/AutomationTest.h"

#include <StructUtils/InstancedStruct.h>

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_snapshot_inspection_sha
{
    auto
        Get_BytesFor(
            const FString& InAscii)
        -> TArray<uint8>
    {
        auto Bytes = TArray<uint8>{};
        Bytes.Reserve(InAscii.Len());
        for (auto Index = 0; Index < InAscii.Len(); ++Index)
        { Bytes.Add(static_cast<uint8>(InAscii[Index])); }
        return Bytes;
    }

    auto
        Get_RepeatedBytes(
            uint8 InValue,
            int32 InCount)
        -> TArray<uint8>
    {
        auto Bytes = TArray<uint8>{};
        Bytes.Init(InValue, InCount);
        return Bytes;
    }

    auto
        Get_IsLowercaseHexDigest(
            const FString& InDigest)
        -> bool
    {
        if (InDigest.Len() != 64)
        { return false; }

        for (auto Index = 0; Index < InDigest.Len(); ++Index)
        {
            const auto Character = InDigest[Index];
            const auto IsDigit = Character >= TEXT('0') && Character <= TEXT('9');
            const auto IsLowerHex = Character >= TEXT('a') && Character <= TEXT('f');

            if (NOT IsDigit && NOT IsLowerHex)
            { return false; }
        }
        return true;
    }

    // A save with one of every severity, so the determinism comparison has a non-trivial sequence to reproduce.
    auto
        Make_NoisyTables()
        -> FCk_Snapshot_V3_Tables
    {
        const auto SharedKey = FGuid{0x0A0A0A0A, 0x0B0B0B0B, 0x0C0C0C0C, 0x0D0D0D0D};

        auto First = ck_test_snapshot_inspection::Make_Entity(10u, ECk_Snapshot_V3_Provenance::EngineOwned);
        First.Set_SaveKey(SharedKey);

        auto Second = ck_test_snapshot_inspection::Make_Entity(20u, ECk_Snapshot_V3_Provenance::EngineOwned);
        Second.Set_SaveKey(SharedKey);

        auto PureData = FCk_Test_DynFrag_PureData{};
        PureData.Count = 4;
        PureData.Label = TEXT("noisy");

        const auto RealPath = FCk_Test_DynFrag_PureData::StaticStruct()->GetPathName();

        auto Tables = FCk_Snapshot_V3_Tables{};
        Tables.Get_Entities().Add(First);
        Tables.Get_Entities().Add(Second);
        Tables.Get_Payloads().Add(ck_test_snapshot_inspection::Make_Payload(10u, RealPath,
            ck_test_snapshot_inspection::SerializeBlob_Save(FInstancedStruct::Make(PureData))));
        Tables.Get_Payloads().Add(ck_test_snapshot_inspection::Make_Payload(20u, RealPath, TArray<uint8>{}));
        Tables.Get_Payloads().Add(ck_test_snapshot_inspection::Make_Payload(20u,
            ck_test_snapshot_inspection::Get_UnresolvablePathFor(RealPath),
            ck_test_snapshot_inspection::SerializeBlob_Save(FInstancedStruct::Make(PureData))));

        return Tables;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_Sha256KnownVectors_Test,
    "Ck.Snapshot.Inspection.Sha256KnownVectors",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_Sha256KnownVectors_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    TestEqual(TEXT("Empty input matches the FIPS 180-4 empty-string digest"),
        ck::snapshot::Get_Sha256Hex(TArray<uint8>{}),
        FString{TEXT("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")});

    TestEqual(TEXT("\"abc\" matches the FIPS 180-4 digest"),
        ck::snapshot::Get_Sha256Hex(ck_test_snapshot_inspection_sha::Get_BytesFor(TEXT("abc"))),
        FString{TEXT("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")});

    // 55 / 56 / 64 / 65 bytes straddle the padding edge: 55 still fits its length field in the first block, 56 forces
    // a second, and 64/65 cross the block boundary outright.
    const auto Digest55 = ck::snapshot::Get_Sha256Hex(ck_test_snapshot_inspection_sha::Get_RepeatedBytes(0x61, 55));
    const auto Digest56 = ck::snapshot::Get_Sha256Hex(ck_test_snapshot_inspection_sha::Get_RepeatedBytes(0x61, 56));
    const auto Digest64 = ck::snapshot::Get_Sha256Hex(ck_test_snapshot_inspection_sha::Get_RepeatedBytes(0x61, 64));
    const auto Digest65 = ck::snapshot::Get_Sha256Hex(ck_test_snapshot_inspection_sha::Get_RepeatedBytes(0x61, 65));

    TestTrue(TEXT("55-byte digest is 64 lowercase hex characters"),
        ck_test_snapshot_inspection_sha::Get_IsLowercaseHexDigest(Digest55));
    TestTrue(TEXT("56-byte digest is 64 lowercase hex characters"),
        ck_test_snapshot_inspection_sha::Get_IsLowercaseHexDigest(Digest56));
    TestTrue(TEXT("64-byte digest is 64 lowercase hex characters"),
        ck_test_snapshot_inspection_sha::Get_IsLowercaseHexDigest(Digest64));
    TestTrue(TEXT("65-byte digest is 64 lowercase hex characters"),
        ck_test_snapshot_inspection_sha::Get_IsLowercaseHexDigest(Digest65));

    TestFalse(TEXT("55 and 56 bytes hash differently"), Digest55 == Digest56);
    TestFalse(TEXT("56 and 64 bytes hash differently"), Digest56 == Digest64);
    TestFalse(TEXT("64 and 65 bytes hash differently"), Digest64 == Digest65);

    TestEqual(TEXT("Hashing is stable across calls"),
        ck::snapshot::Get_Sha256Hex(ck_test_snapshot_inspection_sha::Get_RepeatedBytes(0x61, 65)), Digest65);

    // The streaming form must agree with the one-shot form regardless of where the chunk boundaries fall.
    const auto Message = ck_test_snapshot_inspection_sha::Get_RepeatedBytes(0x5A, 200);

    auto Streaming = ck::snapshot::FCk_Snapshot_Sha256{};
    Streaming.Update(Message.GetData(), 3);
    Streaming.Update(Message.GetData() + 3, 61);
    Streaming.Update(Message.GetData() + 64, 136);

    TestEqual(TEXT("Chunked updates match the one-shot digest"),
        Streaming.Finalize_ToHexString(), ck::snapshot::Get_Sha256Hex(Message));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_Determinism_Test,
    "Ck.Snapshot.Inspection.Determinism",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_Determinism_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    const auto Tables = ck_test_snapshot_inspection_sha::Make_NoisyTables();
    auto* SaveGame = ck_test_snapshot_inspection::Make_SaveGame(
        ck_test_snapshot_inspection::Get_HeaderFor(Tables), ck_test_snapshot_inspection::Get_TablesBytes(Tables));

    auto EnvelopeBytes = TArray<uint8>{};
    if (NOT TestTrue(TEXT("Fixture serialized to an engine save envelope"),
        UGameplayStatics::SaveGameToMemory(SaveGame, EnvelopeBytes)))
    { return false; }

    const auto First = ck::snapshot::Inspect_SaveBytes(EnvelopeBytes, TEXT("determinism"));
    const auto Second = ck::snapshot::Inspect_SaveBytes(EnvelopeBytes, TEXT("determinism"));

    if (NOT TestEqual(TEXT("Both inspections read the save"),
        static_cast<int32>(First.Get_ReadStatus()), static_cast<int32>(ECk_SnapshotInspection_ReadStatus::Success)))
    { return false; }

    TestEqual(TEXT("Source hashes agree"), First.Get_SourceHashHex(), Second.Get_SourceHashHex());
    TestEqual(TEXT("Snapshot hashes agree"), First.Get_SnapshotHashHex(), Second.Get_SnapshotHashHex());
    TestTrue(TEXT("Source hash is a lowercase hex digest"),
        ck_test_snapshot_inspection_sha::Get_IsLowercaseHexDigest(First.Get_SourceHashHex()));
    TestTrue(TEXT("Snapshot hash is a lowercase hex digest"),
        ck_test_snapshot_inspection_sha::Get_IsLowercaseHexDigest(First.Get_SnapshotHashHex()));

    TestEqual(TEXT("Entity counts agree"), First.Get_Census().Get_EntityCount(), Second.Get_Census().Get_EntityCount());
    TestEqual(TEXT("Payload counts agree"), First.Get_Census().Get_PayloadCount(), Second.Get_Census().Get_PayloadCount());
    TestEqual(TEXT("Error counts agree"), First.Get_ErrorCount(), Second.Get_ErrorCount());
    TestEqual(TEXT("Warning counts agree"), First.Get_WarningCount(), Second.Get_WarningCount());

    // The fixture is deliberately noisy — a determinism claim over an empty diagnostic list proves nothing.
    TestTrue(TEXT("The fixture produced diagnostics to compare"), First.Get_Diagnostics().Num() >= 3);

    const auto FirstSignature = ck_test_snapshot_inspection::Get_DiagnosticSignature(First);
    const auto SecondSignature = ck_test_snapshot_inspection::Get_DiagnosticSignature(Second);

    if (NOT TestEqual(TEXT("The diagnostic sequence has the same length"),
        FirstSignature.Num(), SecondSignature.Num()))
    { return false; }

    for (auto Index = 0; Index < FirstSignature.Num(); ++Index)
    {
        TestEqual(*FString::Printf(TEXT("Diagnostic [%d] is identical (severity, code and message)"), Index),
            FirstSignature[Index], SecondSignature[Index]);
    }

    if (NOT TestEqual(TEXT("The payload table has the same length"),
        First.Get_Payloads().Num(), Second.Get_Payloads().Num()))
    { return false; }

    for (auto Index = 0; Index < First.Get_Payloads().Num(); ++Index)
    {
        TestEqual(*FString::Printf(TEXT("Payload [%d] hash is identical"), Index),
            First.Get_Payloads()[Index].Get_PayloadHashHex(), Second.Get_Payloads()[Index].Get_PayloadHashHex());
        TestTrue(*FString::Printf(TEXT("Payload [%d] availability is identical"), Index),
            First.Get_Payloads()[Index].Get_TypeAvailable() == Second.Get_Payloads()[Index].Get_TypeAvailable());
    }

    if (NOT TestEqual(TEXT("The entity table has the same length"),
        First.Get_Entities().Num(), Second.Get_Entities().Num()))
    { return false; }

    for (auto Index = 0; Index < First.Get_Entities().Num(); ++Index)
    {
        TestEqual(*FString::Printf(TEXT("Entity [%d] identity is identical"), Index),
            First.Get_Entities()[Index].Get_IdentityText(), Second.Get_Entities()[Index].Get_IdentityText());
        TestTrue(*FString::Printf(TEXT("Entity [%d] problem flag is identical"), Index),
            First.Get_Entities()[Index].Get_HasProblems() == Second.Get_Entities()[Index].Get_HasProblems());
    }

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
