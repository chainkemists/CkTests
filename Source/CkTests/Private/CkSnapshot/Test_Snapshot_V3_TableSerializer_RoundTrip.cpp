// The v3 table structs carry hand-authored native serializers (WithSerializer) rather than riding tagged
// properties, because FArrayProperty's bulk path is gated on unversioned property serialization and a save
// archive never uses it -- a TArray<uint8> UPROPERTY was walked one virtual call per BYTE.
//
// The cost of that speed is that the field list is no longer reflection-driven: adding a UPROPERTY without
// also editing Serialize() drops it from every save, silently. These gates populate EVERY field with a
// distinctive non-default value and assert it survives a round trip, so an omitted field fails here rather
// than as an unexplained restore bug.

#include "CkSnapshot/SaveGame/CkSnapshot_Header.h"

#include "Misc/AutomationTest.h"

#include "Serialization/BufferArchive.h"
#include "Serialization/MemoryReader.h"
#include "Serialization/MemoryWriter.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_snapshot_v3_tableserializer_tests
{
    auto
        Make_Bytes(
            uint8 InSeed,
            int32 InCount)
        -> TArray<uint8>
    {
        auto Result = TArray<uint8>{};
        Result.Reserve(InCount);
        for (auto Index = 0; Index < InCount; ++Index)
        { Result.Add(static_cast<uint8>(InSeed + Index)); }
        return Result;
    }

    // Deliberately asymmetric on every axis so a swapped rotation/translation/scale cannot pass.
    auto
        Make_Transform(
            double InSeed)
        -> FTransform
    {
        return FTransform
        {
            FRotator{InSeed, InSeed * 2.0, InSeed * 3.0}.Quaternion(),
            FVector{InSeed, InSeed + 1.0, InSeed + 2.0},
            FVector{InSeed + 3.0, InSeed + 4.0, InSeed + 5.0}
        };
    }

    auto
        Make_PopulatedEntityEntry()
        -> FCk_Snapshot_V3_EntityEntry
    {
        auto BuildStep = FCk_Snapshot_V3_BuildStep{};
        BuildStep.Set_ScriptClassPath(TEXT("/Script/CkTests.StepScriptClass"));
        BuildStep.Set_ArchetypePath(TEXT("/Game/CkTests/StepArchetype.StepArchetype"));

        auto SecondStep = FCk_Snapshot_V3_BuildStep{};
        SecondStep.Set_ScriptClassPath(TEXT("/Script/CkTests.SecondStepScriptClass"));

        auto Entry = FCk_Snapshot_V3_EntityEntry{};
        Entry.Set_SavedId(1234u);
        Entry.Set_Provenance(ECk_Snapshot_V3_Provenance::DefinitionBuilt);
        Entry.Set_LifetimeOwnerSavedId(5678u);
        Entry.Set_SaveKey(FGuid{0x11111111, 0x22222222, 0x33333333, 0x44444444});
        Entry.Set_PlayerId(TEXT("player-unique-id"));
        Entry.Set_Label(TEXT("EntryLabel"));
        Entry.Set_ScriptClassPath(TEXT("/Script/CkTests.EntryScriptClass"));
        Entry.Set_SpawnParamsBytes(Make_Bytes(0x10, 64));
        Entry.Set_ContextOwnerSavedId(9012u);
        Entry.Set_ActorClassPath(TEXT("/Script/Engine.Actor"));
        Entry.Set_ActorSaveFieldBytes(Make_Bytes(0x40, 32));
        Entry.Set_ActorSpawnTransform(Make_Transform(7.0));
        Entry.Set_SavedWorldTransform(Make_Transform(13.0));
        Entry.Set_BuildRecipe({BuildStep, SecondStep});
        return Entry;
    }

    auto
        Test_EntityEntryEquals(
            FAutomationTestBase& InTest,
            const FCk_Snapshot_V3_EntityEntry& InActual,
            const FCk_Snapshot_V3_EntityEntry& InExpected,
            const FString& InWhich)
        -> void
    {
        InTest.TestEqual(*(InWhich + TEXT(": saved id")),
            static_cast<int64>(InActual.Get_SavedId()), static_cast<int64>(InExpected.Get_SavedId()));
        InTest.TestEqual(*(InWhich + TEXT(": provenance")),
            static_cast<int32>(InActual.Get_Provenance()), static_cast<int32>(InExpected.Get_Provenance()));
        InTest.TestEqual(*(InWhich + TEXT(": lifetime owner")),
            static_cast<int64>(InActual.Get_LifetimeOwnerSavedId()),
            static_cast<int64>(InExpected.Get_LifetimeOwnerSavedId()));
        InTest.TestTrue(*(InWhich + TEXT(": save key")), InActual.Get_SaveKey() == InExpected.Get_SaveKey());
        InTest.TestEqual(*(InWhich + TEXT(": player id")), InActual.Get_PlayerId(), InExpected.Get_PlayerId());
        InTest.TestEqual(*(InWhich + TEXT(": label")), InActual.Get_Label(), InExpected.Get_Label());
        InTest.TestEqual(*(InWhich + TEXT(": script class path")),
            InActual.Get_ScriptClassPath(), InExpected.Get_ScriptClassPath());
        InTest.TestTrue(*(InWhich + TEXT(": spawn params bytes")),
            InActual.Get_SpawnParamsBytes() == InExpected.Get_SpawnParamsBytes());
        InTest.TestEqual(*(InWhich + TEXT(": context owner")),
            static_cast<int64>(InActual.Get_ContextOwnerSavedId()),
            static_cast<int64>(InExpected.Get_ContextOwnerSavedId()));
        InTest.TestEqual(*(InWhich + TEXT(": actor class path")),
            InActual.Get_ActorClassPath(), InExpected.Get_ActorClassPath());
        InTest.TestTrue(*(InWhich + TEXT(": actor save field bytes")),
            InActual.Get_ActorSaveFieldBytes() == InExpected.Get_ActorSaveFieldBytes());

        InTest.TestTrue(*(InWhich + TEXT(": actor spawn transform")),
            InActual.Get_ActorSpawnTransform().Equals(InExpected.Get_ActorSpawnTransform()));
        InTest.TestTrue(*(InWhich + TEXT(": saved world transform")),
            InActual.Get_SavedWorldTransform().Equals(InExpected.Get_SavedWorldTransform()));

        InTest.TestEqual(*(InWhich + TEXT(": build recipe step count")),
            InActual.Get_BuildRecipe().Num(), InExpected.Get_BuildRecipe().Num());

        const auto StepCount = FMath::Min(InActual.Get_BuildRecipe().Num(), InExpected.Get_BuildRecipe().Num());
        for (auto Index = 0; Index < StepCount; ++Index)
        {
            InTest.TestEqual(*FString::Printf(TEXT("%s: build step [%d] script class"), *InWhich, Index),
                InActual.Get_BuildRecipe()[Index].Get_ScriptClassPath(),
                InExpected.Get_BuildRecipe()[Index].Get_ScriptClassPath());
            InTest.TestEqual(*FString::Printf(TEXT("%s: build step [%d] archetype"), *InWhich, Index),
                InActual.Get_BuildRecipe()[Index].Get_ArchetypePath(),
                InExpected.Get_BuildRecipe()[Index].Get_ArchetypePath());
        }
    }

    auto
        RoundTrip(
            const FCk_Snapshot_V3_Tables& InTables)
        -> FCk_Snapshot_V3_Tables
    {
        auto ByteWriter = FBufferArchive{};
        auto Source = InTables;
        FCk_Snapshot_V3_Tables::StaticStruct()->SerializeItem(ByteWriter, &Source, /*Defaults=*/nullptr);

        auto Restored = FCk_Snapshot_V3_Tables{};
        auto Reader = FMemoryReader{ByteWriter, /*bIsPersistent=*/true};
        FCk_Snapshot_V3_Tables::StaticStruct()->SerializeItem(Reader, &Restored, /*Defaults=*/nullptr);
        return Restored;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_V3_TableSerializerRoundTrip_Test,
    "Ck.Snapshot.V3.TableSerializer.RoundTrip",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_V3_TableSerializerRoundTrip_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    using namespace ck_snapshot_v3_tableserializer_tests;

    const auto PopulatedEntry = Make_PopulatedEntityEntry();

    // A defaulted entry alongside the populated one: the serializer must not depend on any field being set,
    // and an empty byte array must round-trip as empty rather than as a stale length.
    const auto DefaultEntry = FCk_Snapshot_V3_EntityEntry{};

    auto FirstPayload = FCk_Snapshot_V3_PayloadEntry{};
    FirstPayload.Set_OwnerSavedId(1234u);
    FirstPayload.Set_TypePath(TEXT("/Script/CkDynamic.Ck_SaveData_DynamicFragments"));
    FirstPayload.Set_PayloadBytes(Make_Bytes(0x80, 512));

    auto EmptyPayload = FCk_Snapshot_V3_PayloadEntry{};
    EmptyPayload.Set_OwnerSavedId(4321u);
    EmptyPayload.Set_TypePath(TEXT("/Script/CkRelationship.Ck_RepData_Team"));

    auto Tables = FCk_Snapshot_V3_Tables{};
    Tables.Get_Entities() = {PopulatedEntry, DefaultEntry};
    Tables.Get_Payloads() = {FirstPayload, EmptyPayload};

    const auto Restored = RoundTrip(Tables);

    TestEqual(TEXT("entity count survives"), Restored.Get_Entities().Num(), 2);
    TestEqual(TEXT("payload count survives"), Restored.Get_Payloads().Num(), 2);

    if (Restored.Get_Entities().Num() == 2)
    {
        Test_EntityEntryEquals(*this, Restored.Get_Entities()[0], PopulatedEntry, TEXT("populated entity"));
        Test_EntityEntryEquals(*this, Restored.Get_Entities()[1], DefaultEntry, TEXT("default entity"));
    }

    if (Restored.Get_Payloads().Num() == 2)
    {
        TestEqual(TEXT("payload owner"),
            static_cast<int64>(Restored.Get_Payloads()[0].Get_OwnerSavedId()),
            static_cast<int64>(FirstPayload.Get_OwnerSavedId()));
        TestEqual(TEXT("payload type path"), Restored.Get_Payloads()[0].Get_TypePath(), FirstPayload.Get_TypePath());
        TestTrue(TEXT("payload bytes"),
            Restored.Get_Payloads()[0].Get_PayloadBytes() == FirstPayload.Get_PayloadBytes());

        TestEqual(TEXT("empty payload owner"),
            static_cast<int64>(Restored.Get_Payloads()[1].Get_OwnerSavedId()),
            static_cast<int64>(EmptyPayload.Get_OwnerSavedId()));
        TestEqual(TEXT("empty payload bytes stay empty"),
            Restored.Get_Payloads()[1].Get_PayloadBytes().Num(), 0);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_V3_TableSerializerEmptyTables_Test,
    "Ck.Snapshot.V3.TableSerializer.EmptyTables",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_V3_TableSerializerEmptyTables_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    using namespace ck_snapshot_v3_tableserializer_tests;

    const auto Restored = RoundTrip(FCk_Snapshot_V3_Tables{});

    TestEqual(TEXT("empty entity table round-trips empty"), Restored.Get_Entities().Num(), 0);
    TestEqual(TEXT("empty payload table round-trips empty"), Restored.Get_Payloads().Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// The count prefix is read before any allocation, so a corrupt stream must set the archive's error flag
// rather than hand a negative length to SetNumUninitialized.
IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_V3_TableSerializerCorruptStream_Test,
    "Ck.Snapshot.V3.TableSerializer.CorruptStreamFailsClosed",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_V3_TableSerializerCorruptStream_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto Corrupt = TArray<uint8>{};
    auto Writer = FMemoryWriter{Corrupt, /*bIsPersistent=*/true};
    auto NegativeCount = int32{-1};
    Writer << NegativeCount;

    auto Restored = FCk_Snapshot_V3_Tables{};
    auto Reader = FMemoryReader{Corrupt, /*bIsPersistent=*/true};
    FCk_Snapshot_V3_Tables::StaticStruct()->SerializeItem(Reader, &Restored, /*Defaults=*/nullptr);

    TestTrue(TEXT("a negative entry count sets the archive error flag"), Reader.IsError());
    TestEqual(TEXT("no entities were allocated"), Restored.Get_Entities().Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif
