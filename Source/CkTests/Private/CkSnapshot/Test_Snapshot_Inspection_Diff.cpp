// Save-diff analysis for the CkSnapshot offline inspection API. Saved ids are not stable across captures, so the
// whole comparison rests on the identity path: these tests pin the path strings themselves, then the grouping,
// counting and payload aggregation built on top of them. A malformed or unreadable side is expected input and must
// report an invalid diff rather than fire an ensure.

#include "CkSnapshot/Inspection/CkSnapshot_Inspection.h"
#include "CkSnapshot/Inspection/CkSnapshot_Inspection_Diff.h"
#include "CkSnapshot/SaveGame/CkSnapshot_Header.h"

#include "Test_Snapshot_Inspection_Fixtures.h"

#include "CkCore/Format/CkFormat.h"
#include "CkCore/Macros/CkMacros.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_snapshot_inspection_diff
{
    constexpr auto k_OwnerId = 100u;
    constexpr auto k_AbsentId = 999u;

    // FGuid{1, 2, 3, 4} rendered as EGuidFormats::Digits — the identity path pins the digit form, not the default.
    constexpr auto k_OwnerKeyDigits = TEXT("00000001000000020000000300000004");

    constexpr auto k_TypeA = TEXT("/Script/CkTests.Fixture_PayloadA");
    constexpr auto k_TypeB = TEXT("/Script/CkTests.Fixture_PayloadB");

    auto
        Get_OwnerKey()
        -> FGuid
    {
        return FGuid{1, 2, 3, 4};
    }

    auto
        Get_OwnerPath()
        -> FString
    {
        return FString{TEXT("~/key:")} + k_OwnerKeyDigits;
    }

    auto
        Make_KeyedOwner(
            uint32 InSavedId,
            const FGuid& InKey)
        -> FCk_Snapshot_V3_EntityEntry
    {
        auto Entry = ck_test_snapshot_inspection::Make_Entity(InSavedId, ECk_Snapshot_V3_Provenance::EngineOwned);
        Entry.Set_SaveKey(InKey);
        return Entry;
    }

    auto
        TryGet_Group(
            const FCk_SnapshotInspection_Diff& InDiff,
            const FString& InIdentityPath)
        -> const FCk_SnapshotInspection_DiffEntityGroup*
    {
        for (const auto& Group : InDiff.Get_EntityGroups())
        {
            if (Group.Get_IdentityPath() == InIdentityPath)
            { return &Group; }
        }
        return nullptr;
    }

    auto
        TryGet_PayloadRow(
            const TArray<FCk_SnapshotInspection_DiffPayloadTypeRow>& InRows,
            const FString& InTypePath)
        -> const FCk_SnapshotInspection_DiffPayloadTypeRow*
    {
        for (const auto& Row : InRows)
        {
            if (Row.Get_TypePath() == InTypePath)
            { return &Row; }
        }
        return nullptr;
    }

    // Every ordered, value-bearing field of a diff flattened into comparable text, so "field-identical" is asserted
    // rather than sampled.
    auto
        Get_DiffSignature(
            const FCk_SnapshotInspection_Diff& InDiff)
        -> TArray<FString>
    {
        const auto Get_PayloadRowText = [](const FCk_SnapshotInspection_DiffPayloadTypeRow& InRow) -> FString
        {
            return ck::Format_UE(TEXT("{}:{}:{}:{}:{}:{}"),
                InRow.Get_TypePath(), InRow.Get_CountBaseline(), InRow.Get_CountCurrent(),
                InRow.Get_BytesBaseline(), InRow.Get_BytesCurrent(),
                static_cast<int32>(InRow.Get_ContentDiffers()));
        };

        auto Signature = TArray<FString>{};

        for (const auto& Group : InDiff.Get_EntityGroups())
        {
            auto Line = ck::Format_UE(TEXT("{}|{}|{}|{}|{}|{}|{}|{}"),
                Group.Get_IdentityPath(),
                Group.Get_DisplayName(),
                ck::snapshot::Get_ProvenanceText(Group.Get_Provenance()),
                ck::snapshot::Get_DiffGroupKindText(Group.Get_Kind()),
                Group.Get_CountBaseline(),
                Group.Get_CountCurrent(),
                Group.Get_PayloadBytesBaseline(),
                Group.Get_PayloadBytesCurrent());

            for (const auto SavedId : Group.Get_SavedIdsBaseline())
            { Line += ck::Format_UE(TEXT("|b{}"), SavedId); }

            for (const auto SavedId : Group.Get_SavedIdsCurrent())
            { Line += ck::Format_UE(TEXT("|c{}"), SavedId); }

            for (const auto& Row : Group.Get_PayloadTypes())
            { Line += ck::Format_UE(TEXT("|{}"), Get_PayloadRowText(Row)); }

            Signature.Add(MoveTemp(Line));
        }

        for (const auto& Row : InDiff.Get_PayloadTypes())
        { Signature.Add(ck::Format_UE(TEXT("scope|{}"), Get_PayloadRowText(Row))); }

        for (const auto& Row : InDiff.Get_Census())
        {
            Signature.Add(ck::Format_UE(TEXT("census|{}:{}:{}"),
                ck::snapshot::Get_ProvenanceText(Row.Get_Provenance()),
                Row.Get_CountBaseline(), Row.Get_CountCurrent()));
        }

        return Signature;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_Diff_IdentityPaths_Test,
    "Ck.Snapshot.Inspection.Diff.IdentityPaths",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_Diff_IdentityPaths_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    const auto RootPath = ck_test_snapshot_inspection_diff::Get_OwnerPath();
    const auto ChildPath = RootPath + TEXT("/label:Fixture.Child");
    const auto GrandChildPath = ChildPath
        + TEXT("/script:/Script/CkTests.Fixture_Script|actor:|label:Fixture.GrandChild");
    const auto ContextChildPath = RootPath + TEXT("/script:/Script/CkTests.Fixture_Ctx|actor:|label:");

    const auto Root = ck_test_snapshot_inspection_diff::Make_KeyedOwner(
        ck_test_snapshot_inspection_diff::k_OwnerId, ck_test_snapshot_inspection_diff::Get_OwnerKey());

    auto Child = ck_test_snapshot_inspection::Make_Entity(101u, ECk_Snapshot_V3_Provenance::ConstructSpawned);
    Child.Set_LifetimeOwnerSavedId(ck_test_snapshot_inspection_diff::k_OwnerId)
         .Set_Label(TEXT("Fixture.Child"));

    auto GrandChild = ck_test_snapshot_inspection::Make_Entity(102u, ECk_Snapshot_V3_Provenance::RuntimeSpawned);
    GrandChild.Set_LifetimeOwnerSavedId(101u)
              .Set_ScriptClassPath(TEXT("/Script/CkTests.Fixture_Script"))
              .Set_Label(TEXT("Fixture.GrandChild"));

    // The lifetime owner is absent from the table, so the hop must fall through to the context owner's row.
    auto ContextChild = ck_test_snapshot_inspection::Make_Entity(103u, ECk_Snapshot_V3_Provenance::RuntimeSpawned);
    ContextChild.Set_LifetimeOwnerSavedId(ck_test_snapshot_inspection_diff::k_AbsentId)
                .Set_ContextOwnerSavedId(ck_test_snapshot_inspection_diff::k_OwnerId)
                .Set_ScriptClassPath(TEXT("/Script/CkTests.Fixture_Ctx"));

    const auto Unkeyed = ck_test_snapshot_inspection::Make_Entity(104u, ECk_Snapshot_V3_Provenance::EngineOwned);

    // Its own context root — the normal transient-owned shape. This is a ROOT, never a self-cycle.
    auto SelfContext = ck_test_snapshot_inspection::Make_Entity(105u, ECk_Snapshot_V3_Provenance::RuntimeSpawned);
    SelfContext.Set_LifetimeOwnerSavedId(ck_test_snapshot_inspection_diff::k_AbsentId)
               .Set_ContextOwnerSavedId(105u)
               .Set_ScriptClassPath(TEXT("/Script/CkTests.Fixture_SelfCtx"));

    auto Tables = FCk_Snapshot_V3_Tables{};
    Tables.Get_Entities().Add(Root);
    Tables.Get_Entities().Add(Child);
    Tables.Get_Entities().Add(GrandChild);
    Tables.Get_Entities().Add(ContextChild);
    Tables.Get_Entities().Add(Unkeyed);
    Tables.Get_Entities().Add(SelfContext);

    const auto Document = ck_test_snapshot_inspection::Inspect_Tables(Tables);

    TestEqual(TEXT("A transient-owned root hangs off the root marker"),
        ck::snapshot::Get_IdentityPathForEntity(Document, 0), RootPath);
    TestEqual(TEXT("A ConstructSpawned child is keyed by label under its owner"),
        ck::snapshot::Get_IdentityPathForEntity(Document, 1), ChildPath);
    TestEqual(TEXT("A RuntimeSpawned grandchild carries script, actor and label"),
        ck::snapshot::Get_IdentityPathForEntity(Document, 2), GrandChildPath);
    TestEqual(TEXT("An absent lifetime owner falls through to the context owner"),
        ck::snapshot::Get_IdentityPathForEntity(Document, 3), ContextChildPath);
    TestEqual(TEXT("An EngineOwned row with no key and no player id is unmatchable"),
        ck::snapshot::Get_IdentityPathForEntity(Document, 4), FString{TEXT("~/engine:?")});
    TestEqual(TEXT("A self-context root is a root, not a cycle"),
        ck::snapshot::Get_IdentityPathForEntity(Document, 5),
        FString{TEXT("~/script:/Script/CkTests.Fixture_SelfCtx|actor:|label:")});

    TestEqual(TEXT("An INDEX_NONE index yields an empty path"),
        ck::snapshot::Get_IdentityPathForEntity(Document, INDEX_NONE), FString{});
    TestEqual(TEXT("A past-the-end index yields an empty path"),
        ck::snapshot::Get_IdentityPathForEntity(Document, Document.Get_Entities().Num()), FString{});

    // Two mutually-owning rows: the walk must cut the cycle instead of chasing it forever.
    auto First = ck_test_snapshot_inspection_diff::Make_KeyedOwner(20u, FGuid{5, 0, 0, 0});
    First.Set_LifetimeOwnerSavedId(21u);

    auto Second = ck_test_snapshot_inspection_diff::Make_KeyedOwner(21u, FGuid{6, 0, 0, 0});
    Second.Set_LifetimeOwnerSavedId(20u);

    auto CyclicTables = FCk_Snapshot_V3_Tables{};
    CyclicTables.Get_Entities().Add(First);
    CyclicTables.Get_Entities().Add(Second);

    const auto CyclicDocument = ck_test_snapshot_inspection::Inspect_Tables(CyclicTables);

    const auto FirstPath = ck::snapshot::Get_IdentityPathForEntity(CyclicDocument, 0);
    const auto SecondPath = ck::snapshot::Get_IdentityPathForEntity(CyclicDocument, 1);

    TestTrue(TEXT("A cyclic row still produces a path"), NOT FirstPath.IsEmpty() && NOT SecondPath.IsEmpty());
    TestTrue(TEXT("The cycle is announced on the first row"), FirstPath.StartsWith(TEXT("cycle~")));
    TestTrue(TEXT("The cycle is announced on the second row"), SecondPath.StartsWith(TEXT("cycle~")));
    TestNotEqual(TEXT("Cycle members stay distinguishable"), FirstPath, SecondPath);

    const auto CyclicDiff = ck::snapshot::Diff_Documents(CyclicDocument, CyclicDocument);

    TestTrue(TEXT("A cyclic save still diffs"), CyclicDiff.Get_Valid());
    TestEqual(TEXT("Both cycle members are grouped"), CyclicDiff.Get_EntityGroups().Num(), 2);
    TestEqual(TEXT("A cyclic save diffed against itself is unchanged throughout"),
        CyclicDiff.Get_GroupCountOfKind(ECk_SnapshotInspection_DiffGroupKind::Unchanged), 2);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_Diff_LeakCounts_Test,
    "Ck.Snapshot.Inspection.Diff.LeakCounts",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_Diff_LeakCounts_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    // Identical spawns collapse into one group whose count delta IS the leak signal — the saved ids differ between
    // two captures and carry no information at all.
    const auto Make_Tables = [](int32 InSpawnCount) -> FCk_Snapshot_V3_Tables
    {
        auto Tables = FCk_Snapshot_V3_Tables{};
        Tables.Get_Entities().Add(ck_test_snapshot_inspection_diff::Make_KeyedOwner(
            ck_test_snapshot_inspection_diff::k_OwnerId, ck_test_snapshot_inspection_diff::Get_OwnerKey()));

        for (auto Index = 0; Index < InSpawnCount; ++Index)
        {
            auto Spawn = ck_test_snapshot_inspection::Make_Entity(
                200u + static_cast<uint32>(Index), ECk_Snapshot_V3_Provenance::RuntimeSpawned);
            Spawn.Set_LifetimeOwnerSavedId(ck_test_snapshot_inspection_diff::k_OwnerId)
                 .Set_ScriptClassPath(TEXT("/Script/CkTests.Fixture_Leaked"));

            Tables.Get_Entities().Add(Spawn);
        }

        return Tables;
    };

    const auto Baseline = ck_test_snapshot_inspection::Inspect_Tables(Make_Tables(2));
    const auto Current = ck_test_snapshot_inspection::Inspect_Tables(Make_Tables(5));

    const auto Diff = ck::snapshot::Diff_Documents(Baseline, Current);

    if (NOT TestTrue(TEXT("Two readable saves produce a valid diff"), Diff.Get_Valid()))
    { return false; }

    TestEqual(TEXT("Identical spawns collapse into one group beside their owner"),
        Diff.Get_EntityGroups().Num(), 2);

    const auto LeakPath = ck_test_snapshot_inspection_diff::Get_OwnerPath()
        + TEXT("/script:/Script/CkTests.Fixture_Leaked|actor:|label:");

    const auto* Leak = ck_test_snapshot_inspection_diff::TryGet_Group(Diff, LeakPath);
    if (NOT TestNotNull(TEXT("The leaked identity is grouped"), Leak))
    { return false; }

    TestEqual(TEXT("The baseline count is the two original spawns"), Leak->Get_CountBaseline(), 2);
    TestEqual(TEXT("The current count is the five live spawns"), Leak->Get_CountCurrent(), 5);
    TestEqual(TEXT("A population change reads as CountChanged"),
        static_cast<int32>(Leak->Get_Kind()), static_cast<int32>(ECk_SnapshotInspection_DiffGroupKind::CountChanged));
    TestEqual(TEXT("A label-less spawn is named by its class"),
        Leak->Get_DisplayName(), FString{TEXT("Fixture_Leaked")});
    TestEqual(TEXT("The group carries its members' provenance"),
        static_cast<int32>(Leak->Get_Provenance()), static_cast<int32>(ECk_Snapshot_V3_Provenance::RuntimeSpawned));

    TestEqual(TEXT("Every baseline member is reported"), Leak->Get_SavedIdsBaseline().Num(), 2);
    TestEqual(TEXT("Every current member is reported"), Leak->Get_SavedIdsCurrent().Num(), 5);
    TestEqual(TEXT("Member ids are ascending"),
        static_cast<int64>(Leak->Get_SavedIdsCurrent()[0]), static_cast<int64>(200));
    TestEqual(TEXT("Member ids are ascending"),
        static_cast<int64>(Leak->Get_SavedIdsCurrent()[4]), static_cast<int64>(204));

    // The biggest population change reads first, so a leak is never buried under the rows that did not move.
    TestEqual(TEXT("The leaking group sorts first"), Diff.Get_EntityGroups()[0].Get_IdentityPath(), LeakPath);

    const auto* Owner = ck_test_snapshot_inspection_diff::TryGet_Group(
        Diff, ck_test_snapshot_inspection_diff::Get_OwnerPath());
    if (NOT TestNotNull(TEXT("The owner is still grouped"), Owner))
    { return false; }

    TestEqual(TEXT("The untouched owner reads as Unchanged"),
        static_cast<int32>(Owner->Get_Kind()), static_cast<int32>(ECk_SnapshotInspection_DiffGroupKind::Unchanged));
    TestEqual(TEXT("A keyed owner with no label or class is named by its key"),
        Owner->Get_DisplayName(), FString{ck_test_snapshot_inspection_diff::k_OwnerKeyDigits});

    TestEqual(TEXT("The baseline entity total follows the tables"), Diff.Get_EntityCountBaseline(), 3);
    TestEqual(TEXT("The current entity total follows the tables"), Diff.Get_EntityCountCurrent(), 6);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_Diff_AddedRemoved_Test,
    "Ck.Snapshot.Inspection.Diff.AddedRemoved",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_Diff_AddedRemoved_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    const auto Make_Tables = [](uint32 InChildSavedId, const TCHAR* InChildLabel) -> FCk_Snapshot_V3_Tables
    {
        auto Child = ck_test_snapshot_inspection::Make_Entity(
            InChildSavedId, ECk_Snapshot_V3_Provenance::ConstructSpawned);
        Child.Set_LifetimeOwnerSavedId(ck_test_snapshot_inspection_diff::k_OwnerId)
             .Set_Label(InChildLabel);

        auto Tables = FCk_Snapshot_V3_Tables{};
        Tables.Get_Entities().Add(ck_test_snapshot_inspection_diff::Make_KeyedOwner(
            ck_test_snapshot_inspection_diff::k_OwnerId, ck_test_snapshot_inspection_diff::Get_OwnerKey()));
        Tables.Get_Entities().Add(Child);
        return Tables;
    };

    const auto Baseline = ck_test_snapshot_inspection::Inspect_Tables(Make_Tables(300u, TEXT("Only.Baseline")));
    const auto Current = ck_test_snapshot_inspection::Inspect_Tables(Make_Tables(301u, TEXT("Only.Current")));

    const auto Diff = ck::snapshot::Diff_Documents(Baseline, Current);

    if (NOT TestTrue(TEXT("Two readable saves produce a valid diff"), Diff.Get_Valid()))
    { return false; }

    const auto RemovedPath = ck_test_snapshot_inspection_diff::Get_OwnerPath() + TEXT("/label:Only.Baseline");
    const auto AddedPath = ck_test_snapshot_inspection_diff::Get_OwnerPath() + TEXT("/label:Only.Current");

    const auto* Removed = ck_test_snapshot_inspection_diff::TryGet_Group(Diff, RemovedPath);
    const auto* Added = ck_test_snapshot_inspection_diff::TryGet_Group(Diff, AddedPath);

    if (NOT TestNotNull(TEXT("The baseline-only identity is grouped"), Removed))
    { return false; }
    if (NOT TestNotNull(TEXT("The current-only identity is grouped"), Added))
    { return false; }

    TestEqual(TEXT("An identity only in the baseline reads as Removed"),
        static_cast<int32>(Removed->Get_Kind()), static_cast<int32>(ECk_SnapshotInspection_DiffGroupKind::Removed));
    TestEqual(TEXT("The removed group has no current members"), Removed->Get_CountCurrent(), 0);
    TestEqual(TEXT("The removed group names its baseline member"), Removed->Get_SavedIdsBaseline().Num(), 1);
    TestEqual(TEXT("The removed member is the baseline child"),
        static_cast<int64>(Removed->Get_SavedIdsBaseline()[0]), static_cast<int64>(300));
    TestEqual(TEXT("The removed group is named by its label"),
        Removed->Get_DisplayName(), FString{TEXT("Only.Baseline")});

    TestEqual(TEXT("An identity only in the current save reads as Added"),
        static_cast<int32>(Added->Get_Kind()), static_cast<int32>(ECk_SnapshotInspection_DiffGroupKind::Added));
    TestEqual(TEXT("The added group has no baseline members"), Added->Get_CountBaseline(), 0);
    TestEqual(TEXT("The added group names its current member"), Added->Get_SavedIdsCurrent().Num(), 1);
    TestEqual(TEXT("The added member is the current child"),
        static_cast<int64>(Added->Get_SavedIdsCurrent()[0]), static_cast<int64>(301));

    // The diff documents what did NOT move as well: the shared owner is present and explicitly unchanged.
    const auto* Owner = ck_test_snapshot_inspection_diff::TryGet_Group(
        Diff, ck_test_snapshot_inspection_diff::Get_OwnerPath());
    if (NOT TestNotNull(TEXT("The untouched owner is still reported"), Owner))
    { return false; }

    TestEqual(TEXT("The untouched owner reads as Unchanged"),
        static_cast<int32>(Owner->Get_Kind()), static_cast<int32>(ECk_SnapshotInspection_DiffGroupKind::Unchanged));

    TestEqual(TEXT("Exactly one group was added"),
        Diff.Get_GroupCountOfKind(ECk_SnapshotInspection_DiffGroupKind::Added), 1);
    TestEqual(TEXT("Exactly one group was removed"),
        Diff.Get_GroupCountOfKind(ECk_SnapshotInspection_DiffGroupKind::Removed), 1);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_Diff_PayloadContentDiffers_Test,
    "Ck.Snapshot.Inspection.Diff.PayloadContentDiffers",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_Diff_PayloadContentDiffers_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    // Same entity, same payload sizes, different values: only the hash multiset can see this.
    const auto Make_Tables = [](const TArray<uint8>& InTypeABytes) -> FCk_Snapshot_V3_Tables
    {
        auto Tables = FCk_Snapshot_V3_Tables{};
        Tables.Get_Entities().Add(ck_test_snapshot_inspection_diff::Make_KeyedOwner(
            ck_test_snapshot_inspection_diff::k_OwnerId, ck_test_snapshot_inspection_diff::Get_OwnerKey()));

        Tables.Get_Payloads().Add(ck_test_snapshot_inspection::Make_Payload(
            ck_test_snapshot_inspection_diff::k_OwnerId, ck_test_snapshot_inspection_diff::k_TypeA, InTypeABytes));
        Tables.Get_Payloads().Add(ck_test_snapshot_inspection::Make_Payload(
            ck_test_snapshot_inspection_diff::k_OwnerId, ck_test_snapshot_inspection_diff::k_TypeB,
            TArray<uint8>{7, 7, 7}));

        return Tables;
    };

    const auto Baseline = ck_test_snapshot_inspection::Inspect_Tables(Make_Tables(TArray<uint8>{1, 2, 3, 4}));
    const auto Current = ck_test_snapshot_inspection::Inspect_Tables(Make_Tables(TArray<uint8>{9, 9, 9, 9}));

    const auto Diff = ck::snapshot::Diff_Documents(Baseline, Current);

    if (NOT TestTrue(TEXT("Two readable saves produce a valid diff"), Diff.Get_Valid()))
    { return false; }

    const auto* Owner = ck_test_snapshot_inspection_diff::TryGet_Group(
        Diff, ck_test_snapshot_inspection_diff::Get_OwnerPath());
    if (NOT TestNotNull(TEXT("The payload owner is grouped"), Owner))
    { return false; }

    TestEqual(TEXT("An equal-count group whose payload content moved reads as PayloadsChanged"),
        static_cast<int32>(Owner->Get_Kind()),
        static_cast<int32>(ECk_SnapshotInspection_DiffGroupKind::PayloadsChanged));

    const auto* RowA = ck_test_snapshot_inspection_diff::TryGet_PayloadRow(
        Owner->Get_PayloadTypes(), ck_test_snapshot_inspection_diff::k_TypeA);
    const auto* RowB = ck_test_snapshot_inspection_diff::TryGet_PayloadRow(
        Owner->Get_PayloadTypes(), ck_test_snapshot_inspection_diff::k_TypeB);

    if (NOT TestNotNull(TEXT("The changed type has a row"), RowA))
    { return false; }
    if (NOT TestNotNull(TEXT("The untouched type has a row"), RowB))
    { return false; }

    TestEqual(TEXT("The byte total is identical on both sides"),
        RowA->Get_BytesBaseline(), RowA->Get_BytesCurrent());
    TestEqual(TEXT("The row count is identical on both sides"),
        RowA->Get_CountBaseline(), RowA->Get_CountCurrent());
    TestTrue(TEXT("A same-size value change is still caught"), RowA->Get_ContentDiffers());
    TestFalse(TEXT("An identical type is not flagged"), RowB->Get_ContentDiffers());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_Diff_PayloadTypeTotals_Test,
    "Ck.Snapshot.Inspection.Diff.PayloadTypeTotals",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_Diff_PayloadTypeTotals_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto BaselineTables = FCk_Snapshot_V3_Tables{};
    BaselineTables.Get_Entities().Add(ck_test_snapshot_inspection_diff::Make_KeyedOwner(
        ck_test_snapshot_inspection_diff::k_OwnerId, ck_test_snapshot_inspection_diff::Get_OwnerKey()));
    BaselineTables.Get_Payloads().Add(ck_test_snapshot_inspection::Make_Payload(
        ck_test_snapshot_inspection_diff::k_OwnerId, ck_test_snapshot_inspection_diff::k_TypeA,
        TArray<uint8>{1, 2, 3}));
    BaselineTables.Get_Payloads().Add(ck_test_snapshot_inspection::Make_Payload(
        ck_test_snapshot_inspection_diff::k_OwnerId, ck_test_snapshot_inspection_diff::k_TypeA,
        TArray<uint8>{4, 5, 6, 7, 8}));
    // Owned by a saved id with no entity row: it belongs to no group, but the whole-save table still has to see it.
    BaselineTables.Get_Payloads().Add(ck_test_snapshot_inspection::Make_Payload(
        ck_test_snapshot_inspection_diff::k_AbsentId, ck_test_snapshot_inspection_diff::k_TypeB,
        TArray<uint8>{1, 1, 1, 1, 1, 1, 1}));

    auto CurrentTables = FCk_Snapshot_V3_Tables{};
    CurrentTables.Get_Entities().Add(ck_test_snapshot_inspection_diff::Make_KeyedOwner(
        ck_test_snapshot_inspection_diff::k_OwnerId, ck_test_snapshot_inspection_diff::Get_OwnerKey()));
    CurrentTables.Get_Payloads().Add(ck_test_snapshot_inspection::Make_Payload(
        ck_test_snapshot_inspection_diff::k_OwnerId, ck_test_snapshot_inspection_diff::k_TypeA,
        TArray<uint8>{1, 2, 3}));
    CurrentTables.Get_Payloads().Add(ck_test_snapshot_inspection::Make_Payload(
        ck_test_snapshot_inspection_diff::k_AbsentId, ck_test_snapshot_inspection_diff::k_TypeB,
        TArray<uint8>{1, 1, 1, 1, 1, 1, 1}));
    CurrentTables.Get_Payloads().Add(ck_test_snapshot_inspection::Make_Payload(
        ck_test_snapshot_inspection_diff::k_AbsentId, ck_test_snapshot_inspection_diff::k_TypeB,
        TArray<uint8>{2, 2, 2, 2, 2, 2, 2}));

    const auto Diff = ck::snapshot::Diff_Documents(
        ck_test_snapshot_inspection::Inspect_Tables(BaselineTables),
        ck_test_snapshot_inspection::Inspect_Tables(CurrentTables));

    if (NOT TestTrue(TEXT("Two readable saves produce a valid diff"), Diff.Get_Valid()))
    { return false; }

    TestEqual(TEXT("The baseline payload total follows the tables"), Diff.Get_PayloadCountBaseline(), 3);
    TestEqual(TEXT("The current payload total follows the tables"), Diff.Get_PayloadCountCurrent(), 3);
    TestEqual(TEXT("Both types appear at diff scope"), Diff.Get_PayloadTypes().Num(), 2);

    const auto* ScopeA = ck_test_snapshot_inspection_diff::TryGet_PayloadRow(
        Diff.Get_PayloadTypes(), ck_test_snapshot_inspection_diff::k_TypeA);
    const auto* ScopeB = ck_test_snapshot_inspection_diff::TryGet_PayloadRow(
        Diff.Get_PayloadTypes(), ck_test_snapshot_inspection_diff::k_TypeB);

    if (NOT TestNotNull(TEXT("The owned type has a diff-scope row"), ScopeA))
    { return false; }
    if (NOT TestNotNull(TEXT("The owner-less type has a diff-scope row"), ScopeB))
    { return false; }

    TestEqual(TEXT("Baseline count for the owned type"), ScopeA->Get_CountBaseline(), 2);
    TestEqual(TEXT("Baseline bytes for the owned type"), ScopeA->Get_BytesBaseline(), static_cast<int64>(8));
    TestEqual(TEXT("Current count for the owned type"), ScopeA->Get_CountCurrent(), 1);
    TestEqual(TEXT("Current bytes for the owned type"), ScopeA->Get_BytesCurrent(), static_cast<int64>(3));

    TestEqual(TEXT("Baseline count for the owner-less type"), ScopeB->Get_CountBaseline(), 1);
    TestEqual(TEXT("Baseline bytes for the owner-less type"), ScopeB->Get_BytesBaseline(), static_cast<int64>(7));
    TestEqual(TEXT("Current count for the owner-less type"), ScopeB->Get_CountCurrent(), 2);
    TestEqual(TEXT("Current bytes for the owner-less type"), ScopeB->Get_BytesCurrent(), static_cast<int64>(14));

    // Biggest byte delta first: the owner-less type moved 7 bytes, the owned type 5.
    TestEqual(TEXT("The largest byte delta reads first"),
        Diff.Get_PayloadTypes()[0].Get_TypePath(), FString{ck_test_snapshot_inspection_diff::k_TypeB});

    const auto* Owner = ck_test_snapshot_inspection_diff::TryGet_Group(
        Diff, ck_test_snapshot_inspection_diff::Get_OwnerPath());
    if (NOT TestNotNull(TEXT("The payload owner is grouped"), Owner))
    { return false; }

    TestEqual(TEXT("Only the owned type reaches the group"), Owner->Get_PayloadTypes().Num(), 1);
    TestNull(TEXT("An owner-less payload belongs to no group"),
        ck_test_snapshot_inspection_diff::TryGet_PayloadRow(
            Owner->Get_PayloadTypes(), ck_test_snapshot_inspection_diff::k_TypeB));

    TestEqual(TEXT("Group payload bytes cover the group's members only — baseline"),
        Owner->Get_PayloadBytesBaseline(), static_cast<int64>(8));
    TestEqual(TEXT("Group payload bytes cover the group's members only — current"),
        Owner->Get_PayloadBytesCurrent(), static_cast<int64>(3));
    TestEqual(TEXT("An entity count that held but whose payloads moved reads as PayloadsChanged"),
        static_cast<int32>(Owner->Get_Kind()),
        static_cast<int32>(ECk_SnapshotInspection_DiffGroupKind::PayloadsChanged));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_Diff_CensusAndDeterminism_Test,
    "Ck.Snapshot.Inspection.Diff.CensusAndDeterminism",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_Diff_CensusAndDeterminism_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto BuildStep = FCk_Snapshot_V3_BuildStep{};
    BuildStep.Set_ScriptClassPath(TEXT("/Script/CkTests.Fixture_Definition"));

    const auto Make_Tables = [&BuildStep](int32 InRuntimeCount, int32 InBuiltCount) -> FCk_Snapshot_V3_Tables
    {
        auto Tables = FCk_Snapshot_V3_Tables{};
        Tables.Get_Entities().Add(ck_test_snapshot_inspection_diff::Make_KeyedOwner(
            ck_test_snapshot_inspection_diff::k_OwnerId, ck_test_snapshot_inspection_diff::Get_OwnerKey()));

        // No key, no player id, no label, no class — the last humanization tier is the provenance itself.
        Tables.Get_Entities().Add(ck_test_snapshot_inspection::Make_Entity(
            101u, ECk_Snapshot_V3_Provenance::EngineOwned));

        auto Constructed = ck_test_snapshot_inspection::Make_Entity(
            102u, ECk_Snapshot_V3_Provenance::ConstructSpawned);
        Constructed.Set_LifetimeOwnerSavedId(ck_test_snapshot_inspection_diff::k_OwnerId)
                   .Set_Label(TEXT("Fixture.Constructed"));
        Tables.Get_Entities().Add(Constructed);

        for (auto Index = 0; Index < InRuntimeCount; ++Index)
        {
            auto Spawn = ck_test_snapshot_inspection::Make_Entity(
                200u + static_cast<uint32>(Index), ECk_Snapshot_V3_Provenance::RuntimeSpawned);
            Spawn.Set_LifetimeOwnerSavedId(ck_test_snapshot_inspection_diff::k_OwnerId)
                 .Set_ScriptClassPath(TEXT("/Script/CkTests.Fixture_Runtime"));
            Tables.Get_Entities().Add(Spawn);
        }

        for (auto Index = 0; Index < InBuiltCount; ++Index)
        {
            auto Built = ck_test_snapshot_inspection::Make_Entity(
                300u + static_cast<uint32>(Index), ECk_Snapshot_V3_Provenance::DefinitionBuilt);
            Built.Set_LifetimeOwnerSavedId(ck_test_snapshot_inspection_diff::k_OwnerId)
                 .Set_BuildRecipe(TArray<FCk_Snapshot_V3_BuildStep>{BuildStep});
            Tables.Get_Entities().Add(Built);
        }

        Tables.Get_Payloads().Add(ck_test_snapshot_inspection::Make_Payload(
            ck_test_snapshot_inspection_diff::k_OwnerId, ck_test_snapshot_inspection_diff::k_TypeA,
            TArray<uint8>{1, 2, 3}));

        return Tables;
    };

    const auto Baseline = ck_test_snapshot_inspection::Inspect_Tables(Make_Tables(1, 1));
    const auto Current = ck_test_snapshot_inspection::Inspect_Tables(Make_Tables(3, 0));

    const auto Diff = ck::snapshot::Diff_Documents(Baseline, Current);

    if (NOT TestTrue(TEXT("Two readable saves produce a valid diff"), Diff.Get_Valid()))
    { return false; }

    if (NOT TestEqual(TEXT("The census carries one row per provenance"), Diff.Get_Census().Num(), 4))
    { return false; }

    TestEqual(TEXT("Census row 0 is EngineOwned"),
        static_cast<int32>(Diff.Get_Census()[0].Get_Provenance()),
        static_cast<int32>(ECk_Snapshot_V3_Provenance::EngineOwned));
    TestEqual(TEXT("Census row 1 is ConstructSpawned"),
        static_cast<int32>(Diff.Get_Census()[1].Get_Provenance()),
        static_cast<int32>(ECk_Snapshot_V3_Provenance::ConstructSpawned));
    TestEqual(TEXT("Census row 2 is RuntimeSpawned"),
        static_cast<int32>(Diff.Get_Census()[2].Get_Provenance()),
        static_cast<int32>(ECk_Snapshot_V3_Provenance::RuntimeSpawned));
    TestEqual(TEXT("Census row 3 is DefinitionBuilt"),
        static_cast<int32>(Diff.Get_Census()[3].Get_Provenance()),
        static_cast<int32>(ECk_Snapshot_V3_Provenance::DefinitionBuilt));

    TestEqual(TEXT("EngineOwned baseline count"), Diff.Get_Census()[0].Get_CountBaseline(), 2);
    TestEqual(TEXT("EngineOwned current count"), Diff.Get_Census()[0].Get_CountCurrent(), 2);
    TestEqual(TEXT("ConstructSpawned baseline count"), Diff.Get_Census()[1].Get_CountBaseline(), 1);
    TestEqual(TEXT("ConstructSpawned current count"), Diff.Get_Census()[1].Get_CountCurrent(), 1);
    TestEqual(TEXT("RuntimeSpawned baseline count"), Diff.Get_Census()[2].Get_CountBaseline(), 1);
    TestEqual(TEXT("RuntimeSpawned current count"), Diff.Get_Census()[2].Get_CountCurrent(), 3);
    TestEqual(TEXT("DefinitionBuilt baseline count"), Diff.Get_Census()[3].Get_CountBaseline(), 1);
    TestEqual(TEXT("DefinitionBuilt current count"), Diff.Get_Census()[3].Get_CountCurrent(), 0);

    const auto* Unmatchable = ck_test_snapshot_inspection_diff::TryGet_Group(Diff, FString{TEXT("~/engine:?")});
    if (NOT TestNotNull(TEXT("The unmatchable EngineOwned row is grouped"), Unmatchable))
    { return false; }

    TestEqual(TEXT("A row with no label, class or key falls back to its provenance text"),
        Unmatchable->Get_DisplayName(), FString{TEXT("EngineOwned")});

    const auto KindTotal =
          Diff.Get_GroupCountOfKind(ECk_SnapshotInspection_DiffGroupKind::Added)
        + Diff.Get_GroupCountOfKind(ECk_SnapshotInspection_DiffGroupKind::Removed)
        + Diff.Get_GroupCountOfKind(ECk_SnapshotInspection_DiffGroupKind::CountChanged)
        + Diff.Get_GroupCountOfKind(ECk_SnapshotInspection_DiffGroupKind::PayloadsChanged)
        + Diff.Get_GroupCountOfKind(ECk_SnapshotInspection_DiffGroupKind::Unchanged);

    TestEqual(TEXT("Every group is accounted for by exactly one kind"), KindTotal, Diff.Get_EntityGroups().Num());
    TestEqual(TEXT("The DefinitionBuilt identity is gone from the current save"),
        Diff.Get_GroupCountOfKind(ECk_SnapshotInspection_DiffGroupKind::Removed), 1);
    TestEqual(TEXT("The runtime population change is the only count change"),
        Diff.Get_GroupCountOfKind(ECk_SnapshotInspection_DiffGroupKind::CountChanged), 1);

    // Identical inputs must produce a field-identical diff: nothing time-, pointer- or container-order-derived may
    // reach the output.
    const auto Repeat = ck::snapshot::Diff_Documents(Baseline, Current);

    const auto FirstSignature = ck_test_snapshot_inspection_diff::Get_DiffSignature(Diff);
    const auto SecondSignature = ck_test_snapshot_inspection_diff::Get_DiffSignature(Repeat);

    if (NOT TestEqual(TEXT("A repeated diff has the same row count"),
        FirstSignature.Num(), SecondSignature.Num()))
    { return false; }

    for (auto Index = 0; Index < FirstSignature.Num(); ++Index)
    {
        TestEqual(*ck::Format_UE(TEXT("Diff row [{}] is field-identical"), Index),
            FirstSignature[Index], SecondSignature[Index]);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_Diff_InvalidInputs_Test,
    "Ck.Snapshot.Inspection.Diff.InvalidInputs",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_Diff_InvalidInputs_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto Tables = FCk_Snapshot_V3_Tables{};
    Tables.Get_Entities().Add(ck_test_snapshot_inspection_diff::Make_KeyedOwner(
        ck_test_snapshot_inspection_diff::k_OwnerId, ck_test_snapshot_inspection_diff::Get_OwnerKey()));

    const auto Readable = ck_test_snapshot_inspection::Inspect_Tables(Tables);

    // An unreadable save is the expected diet of an offline inspector — no ensure fires, so no expected error is
    // registered here on purpose.
    const auto Garbage = ck::snapshot::Inspect_SaveBytes(TArray<uint8>{0xDE, 0xAD, 0xBE, 0xEF}, TEXT("garbage"));

    TestNotEqual(TEXT("The garbage document did not read"),
        static_cast<int32>(Garbage.Get_ReadStatus()),
        static_cast<int32>(ECk_SnapshotInspection_ReadStatus::Success));

    const auto BadBaseline = ck::snapshot::Diff_Documents(Garbage, Readable);

    TestFalse(TEXT("A diff against an unreadable baseline is invalid"), BadBaseline.Get_Valid());
    TestTrue(TEXT("The reason names the baseline"), BadBaseline.Get_InvalidReason().Contains(TEXT("baseline")));
    TestTrue(TEXT("The reason names the blocking status"), BadBaseline.Get_InvalidReason().Contains(
        ck::snapshot::Get_ReadStatusText(Garbage.Get_ReadStatus())));
    TestFalse(TEXT("The readable side is not blamed"), BadBaseline.Get_InvalidReason().Contains(TEXT("current")));

    // Every other field stays defaulted on an invalid diff — a caller must never read half a comparison.
    TestEqual(TEXT("No baseline entity count"), BadBaseline.Get_EntityCountBaseline(), 0);
    TestEqual(TEXT("No current entity count"), BadBaseline.Get_EntityCountCurrent(), 0);
    TestEqual(TEXT("No baseline payload count"), BadBaseline.Get_PayloadCountBaseline(), 0);
    TestEqual(TEXT("No current payload count"), BadBaseline.Get_PayloadCountCurrent(), 0);
    TestEqual(TEXT("No baseline snapshot bytes"), BadBaseline.Get_SnapshotBytesBaseline(), static_cast<int64>(0));
    TestEqual(TEXT("No current snapshot bytes"), BadBaseline.Get_SnapshotBytesCurrent(), static_cast<int64>(0));
    TestEqual(TEXT("No census"), BadBaseline.Get_Census().Num(), 0);
    TestEqual(TEXT("No entity groups"), BadBaseline.Get_EntityGroups().Num(), 0);
    TestEqual(TEXT("No payload types"), BadBaseline.Get_PayloadTypes().Num(), 0);

    const auto BadCurrent = ck::snapshot::Diff_Documents(Readable, FCk_SnapshotInspection_Document{});

    TestFalse(TEXT("A diff against an unreadable current save is invalid"), BadCurrent.Get_Valid());
    TestTrue(TEXT("The reason names the current side"), BadCurrent.Get_InvalidReason().Contains(TEXT("current")));
    TestFalse(TEXT("The readable baseline is not blamed"),
        BadCurrent.Get_InvalidReason().Contains(TEXT("baseline")));

    const auto BothBad = ck::snapshot::Diff_Documents(Garbage, FCk_SnapshotInspection_Document{});

    TestFalse(TEXT("Two unreadable saves make an invalid diff"), BothBad.Get_Valid());
    TestTrue(TEXT("Both sides are named"),
        BothBad.Get_InvalidReason().Contains(TEXT("baseline"))
        && BothBad.Get_InvalidReason().Contains(TEXT("current")));

    TestTrue(TEXT("Two readable saves still diff"),
        ck::snapshot::Diff_Documents(Readable, Readable).Get_Valid());

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
