#pragma once

#include "CkSnapshot/Inspection/CkSnapshot_Inspection.h"
#include "CkSnapshot/Inspection/CkSnapshot_Inspection_Data.h"
#include "CkSnapshot/SaveGame/CkSnapshot_Header.h"
#include "CkSnapshot/SaveGame/CkSnapshot_SaveGame.h"

#include "CkEcs/Snapshot/CkSnapshot_Context.h"
#include "CkEcs/Snapshot/CkSnapshot_HandleWalk.h"

#include "CkCore/Macros/CkMacros.h"

#include "Containers/StringConv.h"
#include "GameFramework/SaveGame.h"
#include "Serialization/BufferArchive.h"
#include "Serialization/MemoryWriter.h"
#include "Serialization/ObjectAndNameAsStringProxyArchive.h"

#include <StructUtils/InstancedStruct.h>

#include "Test_Snapshot_Inspection_Fixtures.generated.h"

// --------------------------------------------------------------------------------------------------------------------

// A save envelope that is NOT a CK snapshot. Inspect_SaveBytes must load the envelope, fail the cast, and report
// NotCkSnapshot while still recording the class it found — the only clue a foreign save offers.
UCLASS()
class UCk_Test_NotSnapshot_SaveGame : public USaveGame
{
    GENERATED_BODY()

public:
    UPROPERTY()
    int32 _Marker = 0;
};

// --------------------------------------------------------------------------------------------------------------------

// In-memory fixture builders for the CkSnapshot inspection suite. Every document under test is assembled from
// hand-built tables so a defect can be introduced exactly where the diagnostic under test claims to look; nothing
// here touches disk, a world, a registry or a real save slot.
namespace ck_test_snapshot_inspection
{
    inline auto
        Make_Entity(
            uint32 InSavedId,
            ECk_Snapshot_V3_Provenance InProvenance)
        -> FCk_Snapshot_V3_EntityEntry
    {
        auto Entry = FCk_Snapshot_V3_EntityEntry{};
        Entry.Set_SavedId(InSavedId)
             .Set_Provenance(InProvenance);
        return Entry;
    }

    inline auto
        Make_Payload(
            uint32 InOwnerSavedId,
            const FString& InTypePath,
            const TArray<uint8>& InBytes)
        -> FCk_Snapshot_V3_PayloadEntry
    {
        auto Entry = FCk_Snapshot_V3_PayloadEntry{};
        Entry.Set_OwnerSavedId(InOwnerSavedId)
             .Set_TypePath(InTypePath)
             .Set_PayloadBytes(InBytes);
        return Entry;
    }

    // ----------------------------------------------------------------------------------------------------------------

    // Same shape the capture writes with (FBufferArchive + tagged SerializeItem), so the inspection API's persistent
    // FMemoryReader consumes exactly what a real save carries.
    inline auto
        Get_TablesBytes(
            FCk_Snapshot_V3_Tables InTables)
        -> TArray<uint8>
    {
        auto Writer = FBufferArchive{};
        FCk_Snapshot_V3_Tables::StaticStruct()->SerializeItem(Writer, &InTables, /*Defaults=*/nullptr);
        return static_cast<TArray<uint8>&>(Writer);
    }

    inline auto
        Get_HeaderFor(
            const FCk_Snapshot_V3_Tables& InTables)
        -> FCk_Snapshot_HeaderV3
    {
        auto EngineOwnedCount = 0;
        auto ConstructSpawnedCount = 0;
        auto RuntimeSpawnedCount = 0;
        auto DefinitionBuiltCount = 0;

        for (const auto& Entry : InTables.Get_Entities())
        {
            switch (Entry.Get_Provenance())
            {
                case ECk_Snapshot_V3_Provenance::EngineOwned:      ++EngineOwnedCount;      break;
                case ECk_Snapshot_V3_Provenance::ConstructSpawned: ++ConstructSpawnedCount; break;
                case ECk_Snapshot_V3_Provenance::RuntimeSpawned:   ++RuntimeSpawnedCount;   break;
                case ECk_Snapshot_V3_Provenance::DefinitionBuilt:  ++DefinitionBuiltCount;  break;
            }
        }

        auto Header = FCk_Snapshot_HeaderV3{};
        Header.Set_EngineVersion(TEXT("CkTests-Inspection-Fixture"))
              .Set_TimestampUTC(FDateTime{2026, 8, 10})
              .Set_EntityCount(InTables.Get_Entities().Num())
              .Set_EngineOwnedCount(EngineOwnedCount)
              .Set_ConstructSpawnedCount(ConstructSpawnedCount)
              .Set_RuntimeSpawnedCount(RuntimeSpawnedCount)
              .Set_DefinitionBuiltCount(DefinitionBuiltCount)
              .Set_PayloadCount(InTables.Get_Payloads().Num());
        return Header;
    }

    inline auto
        Make_SaveGame(
            const FCk_Snapshot_HeaderV3& InHeader,
            const TArray<uint8>& InSnapshotBytes)
        -> UCk_Snapshot_SaveGame*
    {
        auto* SaveGame = NewObject<UCk_Snapshot_SaveGame>(GetTransientPackage());
        SaveGame->_HeaderV3 = InHeader;
        SaveGame->_SnapshotBytesV3 = InSnapshotBytes;
        return SaveGame;
    }

    /** The default route for a fixture: consistent header, serialized tables, SaveGame-object seam. */
    inline auto
        Inspect_Tables(
            const FCk_Snapshot_V3_Tables& InTables)
        -> FCk_SnapshotInspection_Document
    {
        const auto Bytes = Get_TablesBytes(InTables);
        return ck::snapshot::Inspect_SaveGameObject(Make_SaveGame(Get_HeaderFor(InTables), Bytes), TEXT("fixture"));
    }

    // ----------------------------------------------------------------------------------------------------------------

    // Save-mode blob writer, symmetric with ck::snapshot::SerializeInstancedStruct: the trailing uint32 stream carries
    // one raw saved id per non-Transient handle field, in WalkHandles positional order.
    inline auto
        SerializeBlob_Save(
            const FInstancedStruct& InStruct)
        -> TArray<uint8>
    {
        auto Blob = TArray<uint8>{};
        if (InStruct.GetScriptStruct() == nullptr)
        { return Blob; }

        auto Writer = FMemoryWriter{Blob, /*bIsPersistent=*/true};
        constexpr auto LoadIfFindFails = true;
        auto Proxy = FObjectAndNameAsStringProxyArchive{Writer, LoadIfFindFails};
        Proxy.ArIsSaveGame = false;
        Proxy.SetIsPersistent(true);

        auto Context = ck::FSnapshotContext{};
        auto Copy = FInstancedStruct{InStruct};
        Copy.Serialize(Proxy);
        ck::snapshot::RemapHandles(Copy.GetScriptStruct(), Copy.GetMutableMemory(), Proxy, Context);

        return Blob;
    }

    inline auto
        DoPatch_BytesOnce(
            TArray<uint8>& InOutBytes,
            const TArray<uint8>& InFind,
            const TArray<uint8>& InReplace)
        -> bool
    {
        if (InFind.IsEmpty() || InFind.Num() != InReplace.Num())
        { return false; }

        for (auto Index = 0; Index + InFind.Num() <= InOutBytes.Num(); ++Index)
        {
            auto Matches = true;
            for (auto Offset = 0; Offset < InFind.Num(); ++Offset)
            {
                if (InOutBytes[Index + Offset] != InFind[Offset])
                {
                    Matches = false;
                    break;
                }
            }

            if (NOT Matches)
            { continue; }

            for (auto Offset = 0; Offset < InFind.Num(); ++Offset)
            { InOutBytes[Index + Offset] = InReplace[Offset]; }

            return true;
        }

        return false;
    }

    inline auto
        Get_AnsiBytes(
            const FString& InString)
        -> TArray<uint8>
    {
        const auto Converted = StringCast<ANSICHAR>(*InString);

        auto Bytes = TArray<uint8>{};
        Bytes.Reserve(InString.Len());
        for (auto Index = 0; Index < InString.Len(); ++Index)
        { Bytes.Add(static_cast<uint8>(Converted.Get()[Index])); }
        return Bytes;
    }

    inline auto
        Get_Utf16LeBytes(
            const FString& InString)
        -> TArray<uint8>
    {
        auto Bytes = TArray<uint8>{};
        Bytes.Reserve(InString.Len() * 2);
        for (auto Index = 0; Index < InString.Len(); ++Index)
        {
            const auto Code = static_cast<uint16>(InString[Index]);
            Bytes.Add(static_cast<uint8>(Code & 0xFF));
            Bytes.Add(static_cast<uint8>((Code >> 8) & 0xFF));
        }
        return Bytes;
    }

    /** A struct/class path rides a save envelope and an FInstancedStruct blob as a length-prefixed FString. Rewriting
     *  it in place with an EQUAL-LENGTH replacement leaves every length prefix valid, which is the only way to
     *  fabricate a stream naming a type this editor cannot resolve without hand-authoring the wire format. A pure-ANSI
     *  string serializes as ANSI, but the UCS2 encoding is tried too so the fixture does not depend on that choice. */
    inline auto
        DoPatch_StringOnce(
            TArray<uint8>& InOutBytes,
            const FString& InFind,
            const FString& InReplace)
        -> bool
    {
        if (InFind.IsEmpty() || InFind.Len() != InReplace.Len())
        { return false; }

        if (DoPatch_BytesOnce(InOutBytes, Get_AnsiBytes(InFind), Get_AnsiBytes(InReplace)))
        { return true; }

        return DoPatch_BytesOnce(InOutBytes, Get_Utf16LeBytes(InFind), Get_Utf16LeBytes(InReplace));
    }

    /** A same-length path that resolves to nothing, so a decode reports TypeUnavailable rather than a wrong struct. */
    inline auto
        Get_UnresolvablePathFor(
            const FString& InRealPath)
        -> FString
    {
        return InRealPath.LeftChop(1) + TEXT("Z");
    }

    // ----------------------------------------------------------------------------------------------------------------

    inline auto
        TryGet_Diagnostic(
            const FCk_SnapshotInspection_Document& InDocument,
            ECk_SnapshotInspection_DiagnosticCode InCode)
        -> const FCk_SnapshotInspection_Diagnostic*
    {
        for (const auto& Diagnostic : InDocument.Get_Diagnostics())
        {
            if (Diagnostic.Get_Code() == InCode)
            { return &Diagnostic; }
        }
        return nullptr;
    }

    inline auto
        Get_DiagnosticCount(
            const FCk_SnapshotInspection_Document& InDocument,
            ECk_SnapshotInspection_DiagnosticCode InCode)
        -> int32
    {
        auto Count = 0;
        for (const auto& Diagnostic : InDocument.Get_Diagnostics())
        {
            if (Diagnostic.Get_Code() == InCode)
            { ++Count; }
        }
        return Count;
    }

    inline auto
        Get_DiagnosticSignature(
            const FCk_SnapshotInspection_Document& InDocument)
        -> TArray<FString>
    {
        auto Signature = TArray<FString>{};
        for (const auto& Diagnostic : InDocument.Get_Diagnostics())
        {
            Signature.Add(FString::Printf(TEXT("%s|%s|%s"),
                ck::snapshot::Get_SeverityText(Diagnostic.Get_Severity()),
                ck::snapshot::Get_DiagnosticCodeText(Diagnostic.Get_Code()),
                *Diagnostic.Get_Message()));
        }
        return Signature;
    }

    inline auto
        TryGet_ValueChild(
            const TSharedPtr<FCk_SnapshotInspection_ValueNode>& InNode,
            const FString& InFieldName)
        -> TSharedPtr<FCk_SnapshotInspection_ValueNode>
    {
        if (NOT InNode.IsValid())
        { return {}; }

        for (const auto& Child : InNode->Get_Children())
        {
            if (Child.IsValid() && Child->Get_FieldName() == InFieldName)
            { return Child; }
        }
        return {};
    }
}

// --------------------------------------------------------------------------------------------------------------------
