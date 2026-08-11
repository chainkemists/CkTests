// Diagnostics matrix for the CkSnapshot offline inspection API. Every test perturbs exactly one thing in an
// otherwise-healthy table set and pins the code, the severity and the ids the diagnostic points at — a defect that
// reports the wrong row is as useless as one that goes unreported. Environment observations (a type or class this
// editor cannot see) stay Info and must never mark a row as a problem.

#include "CkSnapshot/Inspection/CkSnapshot_Inspection.h"
#include "CkSnapshot/SaveGame/CkSnapshot_Header.h"

#include "Test_Snapshot_DynamicFragment_Fixtures.h"
#include "Test_Snapshot_Inspection_Fixtures.h"

#include "CkCore/Format/CkFormat.h"
#include "CkCore/Macros/CkMacros.h"

#include "GameFramework/SaveGame.h"
#include "Misc/AutomationTest.h"

#include <StructUtils/InstancedStruct.h>

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_snapshot_inspection_diagnostics
{
    constexpr auto k_OwnerId = 100u;
    constexpr auto k_AbsentId = 999u;

    auto
        Get_PureDataBlob()
        -> TArray<uint8>
    {
        auto PureData = FCk_Test_DynFrag_PureData{};
        PureData.Count = 1;
        PureData.Label = TEXT("payload");
        return ck_test_snapshot_inspection::SerializeBlob_Save(FInstancedStruct::Make(PureData));
    }

    auto
        Get_PureDataPath()
        -> FString
    {
        return FCk_Test_DynFrag_PureData::StaticStruct()->GetPathName();
    }

    auto
        Make_Owner()
        -> FCk_Snapshot_V3_EntityEntry
    {
        auto Owner = ck_test_snapshot_inspection::Make_Entity(k_OwnerId, ECk_Snapshot_V3_Provenance::EngineOwned);
        Owner.Set_SaveKey(FGuid{0x0A0A0A0A, 0x0B0B0B0B, 0x0C0C0C0C, 0x0D0D0D0D});
        return Owner;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_HeaderCensusMismatch_Test,
    "Ck.Snapshot.Inspection.HeaderCensusMismatch",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_HeaderCensusMismatch_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto Tables = FCk_Snapshot_V3_Tables{};
    Tables.Get_Entities().Add(ck_test_snapshot_inspection_diagnostics::Make_Owner());

    auto Header = ck_test_snapshot_inspection::Get_HeaderFor(Tables);
    Header.Set_EntityCount(42);

    const auto Document = ck::snapshot::Inspect_SaveGameObject(
        ck_test_snapshot_inspection::Make_SaveGame(Header, ck_test_snapshot_inspection::Get_TablesBytes(Tables)),
        TEXT("census-mismatch"));

    // The tables themselves parsed fine — a lying header is a defect IN a readable file, not a read failure.
    TestEqual(TEXT("Read status is still Success"),
        static_cast<int32>(Document.Get_ReadStatus()), static_cast<int32>(ECk_SnapshotInspection_ReadStatus::Success));
    TestEqual(TEXT("Exactly one census mismatch"), ck_test_snapshot_inspection::Get_DiagnosticCount(
        Document, ECk_SnapshotInspection_DiagnosticCode::HeaderCensusMismatch), 1);

    const auto* Diagnostic = ck_test_snapshot_inspection::TryGet_Diagnostic(
        Document, ECk_SnapshotInspection_DiagnosticCode::HeaderCensusMismatch);
    if (NOT TestNotNull(TEXT("Census mismatch diagnostic present"), Diagnostic))
    { return false; }

    TestEqual(TEXT("Census mismatch is an Error"),
        static_cast<int32>(Diagnostic->Get_Severity()), static_cast<int32>(ECk_SnapshotInspection_Severity::Error));
    TestEqual(TEXT("The computed census reflects the tables, not the header"),
        Document.Get_Census().Get_EntityCount(), 1);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_DuplicateSavedId_Test,
    "Ck.Snapshot.Inspection.DuplicateSavedId",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_DuplicateSavedId_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto Tables = FCk_Snapshot_V3_Tables{};
    Tables.Get_Entities().Add(ck_test_snapshot_inspection::Make_Entity(
        ck_test_snapshot_inspection_diagnostics::k_OwnerId, ECk_Snapshot_V3_Provenance::EngineOwned));
    Tables.Get_Entities().Add(ck_test_snapshot_inspection::Make_Entity(
        ck_test_snapshot_inspection_diagnostics::k_OwnerId, ECk_Snapshot_V3_Provenance::EngineOwned));

    const auto Document = ck_test_snapshot_inspection::Inspect_Tables(Tables);

    const auto* Diagnostic = ck_test_snapshot_inspection::TryGet_Diagnostic(
        Document, ECk_SnapshotInspection_DiagnosticCode::DuplicateSavedId);
    if (NOT TestNotNull(TEXT("Duplicate saved id reported"), Diagnostic))
    { return false; }

    TestEqual(TEXT("Duplicate saved id is an Error"),
        static_cast<int32>(Diagnostic->Get_Severity()), static_cast<int32>(ECk_SnapshotInspection_Severity::Error));
    TestEqual(TEXT("Reported once, at the colliding row"), ck_test_snapshot_inspection::Get_DiagnosticCount(
        Document, ECk_SnapshotInspection_DiagnosticCode::DuplicateSavedId), 1);
    TestEqual(TEXT("The diagnostic names the colliding id"), Diagnostic->Get_RelatedSavedIds().Num(), 1);
    TestEqual(TEXT("The colliding id is the fixture's"),
        static_cast<int64>(Diagnostic->Get_RelatedSavedIds()[0]),
        static_cast<int64>(ck_test_snapshot_inspection_diagnostics::k_OwnerId));

    TestTrue(TEXT("Both colliding rows are flagged as problems"),
        Document.Get_Entities()[0].Get_HasProblems() && Document.Get_Entities()[1].Get_HasProblems());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_OwnerNotPersisted_Test,
    "Ck.Snapshot.Inspection.OwnerNotPersisted",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_OwnerNotPersisted_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    // An owner id absent from the entity table is the format's encoding of "owned by a non-persisted entity"
    // (usually the saving world's transient root). Severity must mirror the loader's per-provenance consequence:
    // RuntimeSpawned and EngineOwned rows are the normal world-root shape (Info); a ConstructSpawned row orphans
    // and an ownerless DefinitionBuilt row drops (Warning). None of them is an Error.
    constexpr auto k_TransientOwnerId = uint32{0};

    auto BuildStep = FCk_Snapshot_V3_BuildStep{};
    BuildStep.Set_ScriptClassPath(TEXT("/Script/CkTests.Fixture_ConstructionScript"));

    auto RuntimeRoot = ck_test_snapshot_inspection::Make_Entity(10, ECk_Snapshot_V3_Provenance::RuntimeSpawned);
    RuntimeRoot.Set_LifetimeOwnerSavedId(k_TransientOwnerId)
               .Set_ScriptClassPath(TEXT("/Script/CkTests.Fixture_EntityScript"));

    auto EngineRow = ck_test_snapshot_inspection::Make_Entity(11, ECk_Snapshot_V3_Provenance::EngineOwned);
    EngineRow.Set_LifetimeOwnerSavedId(k_TransientOwnerId)
             .Set_ContextOwnerSavedId(k_TransientOwnerId)
             .Set_SaveKey(FGuid{1, 2, 3, 4});

    auto Adoptee = ck_test_snapshot_inspection::Make_Entity(12, ECk_Snapshot_V3_Provenance::ConstructSpawned);
    Adoptee.Set_LifetimeOwnerSavedId(k_TransientOwnerId)
           .Set_Label(TEXT("Fixture.Adoptee"));

    auto ItemWithContext = ck_test_snapshot_inspection::Make_Entity(13, ECk_Snapshot_V3_Provenance::DefinitionBuilt);
    ItemWithContext.Set_LifetimeOwnerSavedId(k_TransientOwnerId)
                   .Set_ContextOwnerSavedId(11)
                   .Set_BuildRecipe(TArray<FCk_Snapshot_V3_BuildStep>{BuildStep});

    auto ItemDropped = ck_test_snapshot_inspection::Make_Entity(14, ECk_Snapshot_V3_Provenance::DefinitionBuilt);
    ItemDropped.Set_LifetimeOwnerSavedId(k_TransientOwnerId)
               .Set_BuildRecipe(TArray<FCk_Snapshot_V3_BuildStep>{BuildStep});

    auto ItemContextOnly = ck_test_snapshot_inspection::Make_Entity(15, ECk_Snapshot_V3_Provenance::DefinitionBuilt);
    ItemContextOnly.Set_ContextOwnerSavedId(k_TransientOwnerId)
                   .Set_BuildRecipe(TArray<FCk_Snapshot_V3_BuildStep>{BuildStep});

    auto Tables = FCk_Snapshot_V3_Tables{};
    Tables.Get_Entities().Add(RuntimeRoot);
    Tables.Get_Entities().Add(EngineRow);
    Tables.Get_Entities().Add(Adoptee);
    Tables.Get_Entities().Add(ItemWithContext);
    Tables.Get_Entities().Add(ItemDropped);
    Tables.Get_Entities().Add(ItemContextOnly);

    const auto Document = ck_test_snapshot_inspection::Inspect_Tables(Tables);

    const auto TryGet_ForRow = [&Document](ECk_SnapshotInspection_DiagnosticCode InCode, uint32 InSavedId)
        -> const FCk_SnapshotInspection_Diagnostic*
    {
        for (const auto& Diagnostic : Document.Get_Diagnostics())
        {
            if (Diagnostic.Get_Code() == InCode &&
                Diagnostic.Get_RelatedSavedIds().Num() > 0 &&
                Diagnostic.Get_RelatedSavedIds()[0] == InSavedId)
            { return &Diagnostic; }
        }
        return nullptr;
    };

    const auto ExpectSeverity = [&](ECk_SnapshotInspection_DiagnosticCode InCode, uint32 InSavedId,
        ECk_SnapshotInspection_Severity InSeverity, const TCHAR* InWhat) -> bool
    {
        const auto* Diagnostic = TryGet_ForRow(InCode, InSavedId);
        if (NOT TestNotNull(InWhat, Diagnostic))
        { return false; }

        TestEqual(InWhat, static_cast<int32>(Diagnostic->Get_Severity()), static_cast<int32>(InSeverity));
        return true;
    };

    auto Ok = true;
    Ok &= ExpectSeverity(ECk_SnapshotInspection_DiagnosticCode::OwnerNotPersisted, 10,
        ECk_SnapshotInspection_Severity::Info, TEXT("RuntimeSpawned absent owner is Info (world-root shape)"));
    Ok &= ExpectSeverity(ECk_SnapshotInspection_DiagnosticCode::OwnerNotPersisted, 11,
        ECk_SnapshotInspection_Severity::Info, TEXT("EngineOwned absent owner is Info (rendezvous by key)"));
    Ok &= ExpectSeverity(ECk_SnapshotInspection_DiagnosticCode::OwnerNotPersisted, 12,
        ECk_SnapshotInspection_Severity::Warning, TEXT("ConstructSpawned absent owner is Warning (row orphans)"));
    Ok &= ExpectSeverity(ECk_SnapshotInspection_DiagnosticCode::OwnerNotPersisted, 13,
        ECk_SnapshotInspection_Severity::Info, TEXT("DefinitionBuilt absent owner with persisted context is Info"));
    Ok &= ExpectSeverity(ECk_SnapshotInspection_DiagnosticCode::OwnerNotPersisted, 14,
        ECk_SnapshotInspection_Severity::Warning, TEXT("DefinitionBuilt absent owner without context is Warning (row drops)"));
    Ok &= ExpectSeverity(ECk_SnapshotInspection_DiagnosticCode::ContextOwnerNotPersisted, 11,
        ECk_SnapshotInspection_Severity::Info, TEXT("Absent context owner is Info (rebuild-time context kept)"));
    Ok &= ExpectSeverity(ECk_SnapshotInspection_DiagnosticCode::ContextOwnerNotPersisted, 15,
        ECk_SnapshotInspection_Severity::Warning, TEXT("DefinitionBuilt absent context with no lifetime owner is Warning (row drops)"));

    if (NOT Ok)
    { return false; }

    // Both ends of every link are named, so a UI can select either the row or the id it points at.
    const auto* RuntimeDiagnostic = TryGet_ForRow(ECk_SnapshotInspection_DiagnosticCode::OwnerNotPersisted, 10);
    TestEqual(TEXT("Diagnostic names both ends"), RuntimeDiagnostic->Get_RelatedSavedIds().Num(), 2);
    TestEqual(TEXT("The absent owner is named second"),
        static_cast<int64>(RuntimeDiagnostic->Get_RelatedSavedIds()[1]), static_cast<int64>(k_TransientOwnerId));

    // Only the Warning rows read as problems — a save whose whole top level is transient-owned stays clean.
    for (const auto& Summary : Document.Get_Entities())
    {
        const auto SavedId = Summary.Get_Entry().Get_SavedId();
        const auto ExpectProblem = SavedId == 12 || SavedId == 14 || SavedId == 15;
        TestEqual(ck::Format_UE(TEXT("Entity [{}] problem flag"), SavedId), Summary.Get_HasProblems(), ExpectProblem);
    }

    TestEqual(TEXT("No absent-owner diagnostic is an Error"), Document.Get_ErrorCount(), 0);

    // An absent owner cannot also be an ordering violation — the row it names does not exist.
    TestEqual(TEXT("No dependent-before-owner is claimed for an absent owner"),
        ck_test_snapshot_inspection::Get_DiagnosticCount(
            Document, ECk_SnapshotInspection_DiagnosticCode::DependentBeforeOwner), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_OwnerCycle_Test,
    "Ck.Snapshot.Inspection.OwnerCycle",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_OwnerCycle_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto First = ck_test_snapshot_inspection::Make_Entity(10u, ECk_Snapshot_V3_Provenance::EngineOwned);
    First.Set_LifetimeOwnerSavedId(20u);

    auto Second = ck_test_snapshot_inspection::Make_Entity(20u, ECk_Snapshot_V3_Provenance::EngineOwned);
    Second.Set_LifetimeOwnerSavedId(10u);

    auto Tables = FCk_Snapshot_V3_Tables{};
    Tables.Get_Entities().Add(First);
    Tables.Get_Entities().Add(Second);

    // The walk must terminate: a cyclic chain is exactly the input that turns an unguarded owner walk into a hang.
    const auto Document = ck_test_snapshot_inspection::Inspect_Tables(Tables);

    const auto* Diagnostic = ck_test_snapshot_inspection::TryGet_Diagnostic(
        Document, ECk_SnapshotInspection_DiagnosticCode::OwnerCycle);
    if (NOT TestNotNull(TEXT("Owner cycle reported"), Diagnostic))
    { return false; }

    TestEqual(TEXT("Owner cycle is an Error"),
        static_cast<int32>(Diagnostic->Get_Severity()), static_cast<int32>(ECk_SnapshotInspection_Severity::Error));
    TestEqual(TEXT("The cycle is reported exactly once"), ck_test_snapshot_inspection::Get_DiagnosticCount(
        Document, ECk_SnapshotInspection_DiagnosticCode::OwnerCycle), 1);
    TestEqual(TEXT("Both cycle members are named"), Diagnostic->Get_RelatedSavedIds().Num(), 2);
    TestTrue(TEXT("The cycle names the first member"), Diagnostic->Get_RelatedSavedIds().Contains(10u));
    TestTrue(TEXT("The cycle names the second member"), Diagnostic->Get_RelatedSavedIds().Contains(20u));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_DependentBeforeOwner_Test,
    "Ck.Snapshot.Inspection.DependentBeforeOwner",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_DependentBeforeOwner_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto Dependent = ck_test_snapshot_inspection::Make_Entity(200u, ECk_Snapshot_V3_Provenance::EngineOwned);
    Dependent.Set_LifetimeOwnerSavedId(ck_test_snapshot_inspection_diagnostics::k_OwnerId);

    auto Tables = FCk_Snapshot_V3_Tables{};
    Tables.Get_Entities().Add(Dependent);
    Tables.Get_Entities().Add(ck_test_snapshot_inspection_diagnostics::Make_Owner());

    const auto Document = ck_test_snapshot_inspection::Inspect_Tables(Tables);

    const auto* Diagnostic = ck_test_snapshot_inspection::TryGet_Diagnostic(
        Document, ECk_SnapshotInspection_DiagnosticCode::DependentBeforeOwner);
    if (NOT TestNotNull(TEXT("Row-order violation reported"), Diagnostic))
    { return false; }

    TestEqual(TEXT("Row-order violation is an Error"),
        static_cast<int32>(Diagnostic->Get_Severity()), static_cast<int32>(ECk_SnapshotInspection_Severity::Error));
    TestEqual(TEXT("Reported once"), ck_test_snapshot_inspection::Get_DiagnosticCount(
        Document, ECk_SnapshotInspection_DiagnosticCode::DependentBeforeOwner), 1);
    TestEqual(TEXT("Both rows are named"), Diagnostic->Get_RelatedSavedIds().Num(), 2);
    TestEqual(TEXT("No cycle is claimed for a straight chain"), ck_test_snapshot_inspection::Get_DiagnosticCount(
        Document, ECk_SnapshotInspection_DiagnosticCode::OwnerCycle), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_DuplicateSaveKey_Test,
    "Ck.Snapshot.Inspection.DuplicateSaveKey",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_DuplicateSaveKey_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    const auto SharedKey = FGuid{0x0A0A0A0A, 0x0B0B0B0B, 0x0C0C0C0C, 0x0D0D0D0D};

    auto First = ck_test_snapshot_inspection::Make_Entity(10u, ECk_Snapshot_V3_Provenance::EngineOwned);
    First.Set_SaveKey(SharedKey);

    auto Second = ck_test_snapshot_inspection::Make_Entity(20u, ECk_Snapshot_V3_Provenance::EngineOwned);
    Second.Set_SaveKey(SharedKey);

    // A third row with no key at all must not be swept into the group — an unset GUID is not an identity.
    const auto Unkeyed = ck_test_snapshot_inspection::Make_Entity(30u, ECk_Snapshot_V3_Provenance::EngineOwned);

    auto Tables = FCk_Snapshot_V3_Tables{};
    Tables.Get_Entities().Add(First);
    Tables.Get_Entities().Add(Second);
    Tables.Get_Entities().Add(Unkeyed);

    const auto Document = ck_test_snapshot_inspection::Inspect_Tables(Tables);

    const auto* Diagnostic = ck_test_snapshot_inspection::TryGet_Diagnostic(
        Document, ECk_SnapshotInspection_DiagnosticCode::DuplicateSaveKey);
    if (NOT TestNotNull(TEXT("Duplicate SaveKey reported"), Diagnostic))
    { return false; }

    TestEqual(TEXT("Duplicate SaveKey is an Error"),
        static_cast<int32>(Diagnostic->Get_Severity()), static_cast<int32>(ECk_SnapshotInspection_Severity::Error));
    TestEqual(TEXT("One group, not one diagnostic per row"), ck_test_snapshot_inspection::Get_DiagnosticCount(
        Document, ECk_SnapshotInspection_DiagnosticCode::DuplicateSaveKey), 1);
    TestEqual(TEXT("The group names both keyed rows"), Diagnostic->Get_RelatedSavedIds().Num(), 2);
    TestFalse(TEXT("The unkeyed row is untouched"), Document.Get_Entities()[2].Get_HasProblems());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_DuplicateAdoptKey_Test,
    "Ck.Snapshot.Inspection.DuplicateAdoptKey",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_DuplicateAdoptKey_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto MakeChild = [](uint32 InSavedId) -> FCk_Snapshot_V3_EntityEntry
    {
        auto Child = ck_test_snapshot_inspection::Make_Entity(InSavedId, ECk_Snapshot_V3_Provenance::ConstructSpawned);
        Child.Set_LifetimeOwnerSavedId(ck_test_snapshot_inspection_diagnostics::k_OwnerId)
             .Set_Label(TEXT("Test.Inspection.Collide"));
        return Child;
    };

    auto Tables = FCk_Snapshot_V3_Tables{};
    Tables.Get_Entities().Add(ck_test_snapshot_inspection_diagnostics::Make_Owner());
    Tables.Get_Entities().Add(MakeChild(200u));
    Tables.Get_Entities().Add(MakeChild(201u));

    const auto Document = ck_test_snapshot_inspection::Inspect_Tables(Tables);

    const auto* Diagnostic = ck_test_snapshot_inspection::TryGet_Diagnostic(
        Document, ECk_SnapshotInspection_DiagnosticCode::DuplicateAdoptKey);
    if (NOT TestNotNull(TEXT("Duplicate adopt key reported"), Diagnostic))
    { return false; }

    TestEqual(TEXT("Duplicate adopt key is an Error"),
        static_cast<int32>(Diagnostic->Get_Severity()), static_cast<int32>(ECk_SnapshotInspection_Severity::Error));
    TestEqual(TEXT("One group for the colliding (owner, label) pair"),
        ck_test_snapshot_inspection::Get_DiagnosticCount(
            Document, ECk_SnapshotInspection_DiagnosticCode::DuplicateAdoptKey), 1);
    TestEqual(TEXT("Both children are named"), Diagnostic->Get_RelatedSavedIds().Num(), 2);
    TestFalse(TEXT("The owner row itself is clean"), Document.Get_Entities()[0].Get_HasProblems());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_ConstructSpawnedNoLabel_Test,
    "Ck.Snapshot.Inspection.ConstructSpawnedNoLabel",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_ConstructSpawnedNoLabel_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto Child = ck_test_snapshot_inspection::Make_Entity(200u, ECk_Snapshot_V3_Provenance::ConstructSpawned);
    Child.Set_LifetimeOwnerSavedId(ck_test_snapshot_inspection_diagnostics::k_OwnerId);

    auto Tables = FCk_Snapshot_V3_Tables{};
    Tables.Get_Entities().Add(ck_test_snapshot_inspection_diagnostics::Make_Owner());
    Tables.Get_Entities().Add(Child);

    const auto Document = ck_test_snapshot_inspection::Inspect_Tables(Tables);

    const auto* Diagnostic = ck_test_snapshot_inspection::TryGet_Diagnostic(
        Document, ECk_SnapshotInspection_DiagnosticCode::ConstructSpawnedNoLabel);
    if (NOT TestNotNull(TEXT("Unlabeled ConstructSpawned row reported"), Diagnostic))
    { return false; }

    TestEqual(TEXT("An unlabeled ConstructSpawned row is an Error"),
        static_cast<int32>(Diagnostic->Get_Severity()), static_cast<int32>(ECk_SnapshotInspection_Severity::Error));
    TestEqual(TEXT("The unlabeled row is named"), Diagnostic->Get_RelatedSavedIds().Num(), 1);
    TestEqual(TEXT("The unlabeled row is the child"),
        static_cast<int64>(Diagnostic->Get_RelatedSavedIds()[0]), static_cast<int64>(200));
    TestTrue(TEXT("The child row is flagged as a problem"), Document.Get_Entities()[1].Get_HasProblems());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_RuntimeSpawnedNoRecipe_Test,
    "Ck.Snapshot.Inspection.RuntimeSpawnedNoRecipe",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_RuntimeSpawnedNoRecipe_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto Tables = FCk_Snapshot_V3_Tables{};
    Tables.Get_Entities().Add(ck_test_snapshot_inspection::Make_Entity(
        300u, ECk_Snapshot_V3_Provenance::RuntimeSpawned));

    const auto Document = ck_test_snapshot_inspection::Inspect_Tables(Tables);

    const auto* Diagnostic = ck_test_snapshot_inspection::TryGet_Diagnostic(
        Document, ECk_SnapshotInspection_DiagnosticCode::RuntimeSpawnedNoRecipe);
    if (NOT TestNotNull(TEXT("Recipe-less RuntimeSpawned row reported"), Diagnostic))
    { return false; }

    TestEqual(TEXT("A recipe-less RuntimeSpawned row is an Error"),
        static_cast<int32>(Diagnostic->Get_Severity()), static_cast<int32>(ECk_SnapshotInspection_Severity::Error));
    TestEqual(TEXT("The row is named"), Diagnostic->Get_RelatedSavedIds().Num(), 1);
    TestEqual(TEXT("The row is the recipe-less one"),
        static_cast<int64>(Diagnostic->Get_RelatedSavedIds()[0]), static_cast<int64>(300));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_DefinitionBuiltDefects_Test,
    "Ck.Snapshot.Inspection.DefinitionBuiltDefects",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_DefinitionBuiltDefects_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto Tables = FCk_Snapshot_V3_Tables{};
    Tables.Get_Entities().Add(ck_test_snapshot_inspection::Make_Entity(
        400u, ECk_Snapshot_V3_Provenance::DefinitionBuilt));

    const auto Document = ck_test_snapshot_inspection::Inspect_Tables(Tables);

    const auto* NoOwner = ck_test_snapshot_inspection::TryGet_Diagnostic(
        Document, ECk_SnapshotInspection_DiagnosticCode::DefinitionBuiltNoOwner);
    const auto* NoStep = ck_test_snapshot_inspection::TryGet_Diagnostic(
        Document, ECk_SnapshotInspection_DiagnosticCode::DefinitionBuiltNoUsableStep);

    if (NOT TestNotNull(TEXT("Owner-less DefinitionBuilt row reported"), NoOwner))
    { return false; }
    if (NOT TestNotNull(TEXT("Step-less DefinitionBuilt row reported"), NoStep))
    { return false; }

    TestEqual(TEXT("Missing build owner is an Error"),
        static_cast<int32>(NoOwner->Get_Severity()), static_cast<int32>(ECk_SnapshotInspection_Severity::Error));
    TestEqual(TEXT("Missing usable step is an Error"),
        static_cast<int32>(NoStep->Get_Severity()), static_cast<int32>(ECk_SnapshotInspection_Severity::Error));
    TestEqual(TEXT("Two errors on one row"), Document.Get_ErrorCount(), 2);

    // A recipe carrying only an archetype and no script class is still unbuildable.
    auto ArchetypeOnlyStep = FCk_Snapshot_V3_BuildStep{};
    ArchetypeOnlyStep.Set_ArchetypePath(TEXT("/Game/Test/Inspection/DoesNotMatter.DoesNotMatter"));

    auto Built = ck_test_snapshot_inspection::Make_Entity(401u, ECk_Snapshot_V3_Provenance::DefinitionBuilt);
    Built.Set_LifetimeOwnerSavedId(ck_test_snapshot_inspection_diagnostics::k_OwnerId);
    Built.Get_BuildRecipe().Add(ArchetypeOnlyStep);

    auto StepTables = FCk_Snapshot_V3_Tables{};
    StepTables.Get_Entities().Add(ck_test_snapshot_inspection_diagnostics::Make_Owner());
    StepTables.Get_Entities().Add(Built);

    const auto StepDocument = ck_test_snapshot_inspection::Inspect_Tables(StepTables);

    TestEqual(TEXT("An archetype-only recipe still has no usable step"),
        ck_test_snapshot_inspection::Get_DiagnosticCount(
            StepDocument, ECk_SnapshotInspection_DiagnosticCode::DefinitionBuiltNoUsableStep), 1);
    TestEqual(TEXT("An owned DefinitionBuilt row raises no owner error"),
        ck_test_snapshot_inspection::Get_DiagnosticCount(
            StepDocument, ECk_SnapshotInspection_DiagnosticCode::DefinitionBuiltNoOwner), 0);
    TestEqual(TEXT("The build step count is surfaced on the summary"),
        StepDocument.Get_Entities()[1].Get_BuildStepCount(), 1);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_DuplicateRecipeIdentity_Test,
    "Ck.Snapshot.Inspection.DuplicateRecipeIdentity",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_DuplicateRecipeIdentity_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    // A resolvable class path keeps this test about the duplicate predicate rather than about what this editor can see.
    const auto ScriptClassPath = USaveGame::StaticClass()->GetPathName();

    auto MakeRuntime = [&ScriptClassPath](uint32 InSavedId) -> FCk_Snapshot_V3_EntityEntry
    {
        auto Entry = ck_test_snapshot_inspection::Make_Entity(InSavedId, ECk_Snapshot_V3_Provenance::RuntimeSpawned);
        Entry.Set_ScriptClassPath(ScriptClassPath);
        return Entry;
    };

    auto Tables = FCk_Snapshot_V3_Tables{};
    Tables.Get_Entities().Add(MakeRuntime(300u));
    Tables.Get_Entities().Add(MakeRuntime(301u));

    const auto Document = ck_test_snapshot_inspection::Inspect_Tables(Tables);

    const auto* Diagnostic = ck_test_snapshot_inspection::TryGet_Diagnostic(
        Document, ECk_SnapshotInspection_DiagnosticCode::DuplicateRecipeIdentity);
    if (NOT TestNotNull(TEXT("Duplicate recipe identity reported"), Diagnostic))
    { return false; }

    // A repeated recipe is suspicious, not proof of corruption — a save may legitimately hold two identical spawns.
    TestEqual(TEXT("Duplicate recipe identity is a Warning, not an Error"),
        static_cast<int32>(Diagnostic->Get_Severity()), static_cast<int32>(ECk_SnapshotInspection_Severity::Warning));
    TestEqual(TEXT("Both rows are named"), Diagnostic->Get_RelatedSavedIds().Num(), 2);
    TestEqual(TEXT("No errors are raised"), Document.Get_ErrorCount(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_PayloadOwnerMissing_Test,
    "Ck.Snapshot.Inspection.PayloadOwnerMissing",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_PayloadOwnerMissing_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto Tables = FCk_Snapshot_V3_Tables{};
    Tables.Get_Entities().Add(ck_test_snapshot_inspection_diagnostics::Make_Owner());
    Tables.Get_Payloads().Add(ck_test_snapshot_inspection::Make_Payload(
        ck_test_snapshot_inspection_diagnostics::k_AbsentId,
        ck_test_snapshot_inspection_diagnostics::Get_PureDataPath(),
        ck_test_snapshot_inspection_diagnostics::Get_PureDataBlob()));

    const auto Document = ck_test_snapshot_inspection::Inspect_Tables(Tables);

    const auto* Diagnostic = ck_test_snapshot_inspection::TryGet_Diagnostic(
        Document, ECk_SnapshotInspection_DiagnosticCode::PayloadOwnerMissing);
    if (NOT TestNotNull(TEXT("Orphaned payload reported"), Diagnostic))
    { return false; }

    TestEqual(TEXT("An orphaned payload is an Error"),
        static_cast<int32>(Diagnostic->Get_Severity()), static_cast<int32>(ECk_SnapshotInspection_Severity::Error));
    TestEqual(TEXT("The absent owner id is named"), Diagnostic->Get_RelatedSavedIds().Num(), 1);
    TestEqual(TEXT("The payload row is named"), Diagnostic->Get_RelatedPayloadIndices().Num(), 1);
    TestEqual(TEXT("The named payload row is row zero"), Diagnostic->Get_RelatedPayloadIndices()[0], 0);
    TestTrue(TEXT("The payload row is flagged as a problem"), Document.Get_Payloads()[0].Get_HasProblems());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_PayloadBytesEmpty_Test,
    "Ck.Snapshot.Inspection.PayloadBytesEmpty",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_PayloadBytesEmpty_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto Tables = FCk_Snapshot_V3_Tables{};
    Tables.Get_Entities().Add(ck_test_snapshot_inspection_diagnostics::Make_Owner());
    Tables.Get_Payloads().Add(ck_test_snapshot_inspection::Make_Payload(
        ck_test_snapshot_inspection_diagnostics::k_OwnerId,
        ck_test_snapshot_inspection_diagnostics::Get_PureDataPath(),
        TArray<uint8>{}));

    const auto Document = ck_test_snapshot_inspection::Inspect_Tables(Tables);

    const auto* Diagnostic = ck_test_snapshot_inspection::TryGet_Diagnostic(
        Document, ECk_SnapshotInspection_DiagnosticCode::PayloadBytesEmpty);
    if (NOT TestNotNull(TEXT("Empty payload reported"), Diagnostic))
    { return false; }

    TestEqual(TEXT("An empty payload is a Warning"),
        static_cast<int32>(Diagnostic->Get_Severity()), static_cast<int32>(ECk_SnapshotInspection_Severity::Warning));
    TestEqual(TEXT("No errors"), Document.Get_ErrorCount(), 0);
    TestEqual(TEXT("Byte count is surfaced as zero"), Document.Get_Payloads()[0].Get_ByteCount(), 0);
    TestTrue(TEXT("A Warning still flags the row"), Document.Get_Payloads()[0].Get_HasProblems());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_PayloadTypePathEmpty_Test,
    "Ck.Snapshot.Inspection.PayloadTypePathEmpty",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_PayloadTypePathEmpty_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto Tables = FCk_Snapshot_V3_Tables{};
    Tables.Get_Entities().Add(ck_test_snapshot_inspection_diagnostics::Make_Owner());
    Tables.Get_Payloads().Add(ck_test_snapshot_inspection::Make_Payload(
        ck_test_snapshot_inspection_diagnostics::k_OwnerId,
        FString{},
        ck_test_snapshot_inspection_diagnostics::Get_PureDataBlob()));

    const auto Document = ck_test_snapshot_inspection::Inspect_Tables(Tables);

    const auto* Diagnostic = ck_test_snapshot_inspection::TryGet_Diagnostic(
        Document, ECk_SnapshotInspection_DiagnosticCode::PayloadTypePathEmpty);
    if (NOT TestNotNull(TEXT("Type-path-less payload reported"), Diagnostic))
    { return false; }

    TestEqual(TEXT("A missing type path is a Warning"),
        static_cast<int32>(Diagnostic->Get_Severity()), static_cast<int32>(ECk_SnapshotInspection_Severity::Warning));

    // "No declared type" and "declared a type this editor cannot see" are different facts; only the first applies.
    TestEqual(TEXT("No availability observation is made for an absent declaration"),
        ck_test_snapshot_inspection::Get_DiagnosticCount(
            Document, ECk_SnapshotInspection_DiagnosticCode::PayloadTypeUnavailable), 0);
    TestFalse(TEXT("An undeclared type is not available"), Document.Get_Payloads()[0].Get_TypeAvailable());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Inspection_PayloadTypeUnavailable_Test,
    "Ck.Snapshot.Inspection.PayloadTypeUnavailable",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Inspection_PayloadTypeUnavailable_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    const auto UnresolvablePath = ck_test_snapshot_inspection::Get_UnresolvablePathFor(
        ck_test_snapshot_inspection_diagnostics::Get_PureDataPath());

    auto Tables = FCk_Snapshot_V3_Tables{};
    Tables.Get_Entities().Add(ck_test_snapshot_inspection_diagnostics::Make_Owner());
    Tables.Get_Payloads().Add(ck_test_snapshot_inspection::Make_Payload(
        ck_test_snapshot_inspection_diagnostics::k_OwnerId,
        UnresolvablePath,
        ck_test_snapshot_inspection_diagnostics::Get_PureDataBlob()));
    Tables.Get_Payloads().Add(ck_test_snapshot_inspection::Make_Payload(
        ck_test_snapshot_inspection_diagnostics::k_OwnerId,
        ck_test_snapshot_inspection_diagnostics::Get_PureDataPath(),
        ck_test_snapshot_inspection_diagnostics::Get_PureDataBlob()));

    const auto Document = ck_test_snapshot_inspection::Inspect_Tables(Tables);

    const auto* Diagnostic = ck_test_snapshot_inspection::TryGet_Diagnostic(
        Document, ECk_SnapshotInspection_DiagnosticCode::PayloadTypeUnavailable);
    if (NOT TestNotNull(TEXT("Unavailable payload type reported"), Diagnostic))
    { return false; }

    // What this editor can see is not a property of the file: the observation is Info and marks nothing as broken.
    TestEqual(TEXT("An unavailable type is an Info observation"),
        static_cast<int32>(Diagnostic->Get_Severity()), static_cast<int32>(ECk_SnapshotInspection_Severity::Info));
    TestEqual(TEXT("No errors"), Document.Get_ErrorCount(), 0);
    TestEqual(TEXT("No warnings"), Document.Get_WarningCount(), 0);
    TestFalse(TEXT("The opaque row is not flagged as a problem"), Document.Get_Payloads()[0].Get_HasProblems());
    TestFalse(TEXT("The opaque row reports its type as unavailable"), Document.Get_Payloads()[0].Get_TypeAvailable());

    // The rest of the document stays fully usable — one opaque row never blocks the others.
    TestEqual(TEXT("Only the opaque row is observed"), ck_test_snapshot_inspection::Get_DiagnosticCount(
        Document, ECk_SnapshotInspection_DiagnosticCode::PayloadTypeUnavailable), 1);
    TestTrue(TEXT("The sibling row's type is still available"), Document.Get_Payloads()[1].Get_TypeAvailable());
    TestEqual(TEXT("Both payload rows are present"), Document.Get_Payloads().Num(), 2);
    TestEqual(TEXT("The entity table is untouched"), Document.Get_Entities().Num(), 1);

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
