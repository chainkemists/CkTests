// T-C1-8 — the entity-script UPROPERTY(SaveGame) fence.
//
// Fragment posture is fragment-granular, with one deliberate exception: an entity script's own CPF_SaveGame
// properties, which a generic save-only handler reflect-walks off the script CLASS. That mechanism is the ONE
// sanctioned field-granular persistence path ("spawn recipe fields"), and it carries two silent failures a
// posture fence over UScriptStructs structurally cannot see:
//
//   1. meta=(SaveGame) sets a METADATA STRING, not the CPF_SaveGame flag. The reflect walk keys on the flag, so
//      the field never persists — and metadata is stripped behind WITH_METADATA in cooked Game targets, so the
//      spelling is not merely inert, it is invisible. Only the bare UPROPERTY(SaveGame) spelling works.
//   2. Handles inside a SaveGame blob are NEVER remapped. The blob is serialized opaquely through
//      FObjectAndNameAsStringProxyArchive, so the outer snapshot handle walk cannot reach into it; a saved
//      handle comes back naming an entity id from the torn-down world. The same is true of a delegate (it names
//      objects that no longer exist) and of a request payload (a queue that re-arms a processor on load).
//
// Both are red here, over every UCk_EntityScript_UE subclass in the build, not only over the fixtures.

#include "CkCore/Macros/CkMacros.h"

#include "CkEcs/EntityScript/CkEntityScript.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Request/CkRequest_Data.h"

#include "Misc/AutomationTest.h"

#include "UObject/Class.h"
#include "UObject/UnrealType.h"
#include "UObject/UObjectIterator.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_entity_script_savefield_coverage
{
    // What a CPF_SaveGame field must not reach, and why each one cannot survive the round trip.
    struct FVerdict
    {
        bool    IsIllegal = false;
        FString Reason;
    };

    auto Analyze_SaveGameProperty(const FProperty* InProperty, TSet<const UStruct*>& InOutActive) -> FVerdict;

    auto Analyze_SaveGameStruct(const UScriptStruct* InStruct, TSet<const UStruct*>& InOutActive) -> FVerdict
    {
        if (InStruct == nullptr || InOutActive.Contains(InStruct))
        { return {}; }

        if (InStruct->IsChildOf(FCk_Handle::StaticStruct()))
        {
            return {true, TEXT("it reaches an FCk_Handle, and handles inside a SaveGame blob are never remapped — "
                "the blob is opaque to the snapshot handle walk, so the value comes back naming an entity from "
                "the torn-down world")};
        }

        if (InStruct->IsChildOf(FCk_Request_Base::StaticStruct()))
        {
            return {true, TEXT("it reaches a request payload; a persisted request queue re-arms its processor on "
                "load, replaying work the save already recorded the result of")};
        }

        InOutActive.Add(InStruct);

        auto Verdict = FVerdict{};
        for (TFieldIterator<FProperty> It{InStruct, EFieldIterationFlags::IncludeSuper}; It && NOT Verdict.IsIllegal; ++It)
        { Verdict = Analyze_SaveGameProperty(*It, InOutActive); }

        InOutActive.Remove(InStruct);

        return Verdict;
    }

    auto Analyze_SaveGameProperty(const FProperty* InProperty, TSet<const UStruct*>& InOutActive) -> FVerdict
    {
        if (InProperty == nullptr)
        { return {}; }

        if (CastField<const FDelegateProperty>(InProperty) != nullptr ||
            CastField<const FMulticastDelegateProperty>(InProperty) != nullptr)
        {
            return {true, TEXT("it reaches a delegate, whose saved form names objects from the torn-down world "
                "while the live value holds the subscribers that bound during the rebuild")};
        }

        if (const auto* ArrayProperty = CastField<const FArrayProperty>(InProperty))
        { return Analyze_SaveGameProperty(ArrayProperty->Inner, InOutActive); }

        if (const auto* SetProperty = CastField<const FSetProperty>(InProperty))
        { return Analyze_SaveGameProperty(SetProperty->ElementProp, InOutActive); }

        if (const auto* MapProperty = CastField<const FMapProperty>(InProperty))
        {
            const auto KeyVerdict = Analyze_SaveGameProperty(MapProperty->KeyProp, InOutActive);
            return KeyVerdict.IsIllegal ? KeyVerdict : Analyze_SaveGameProperty(MapProperty->ValueProp, InOutActive);
        }

        if (const auto* StructProperty = CastField<const FStructProperty>(InProperty))
        { return Analyze_SaveGameStruct(StructProperty->Struct, InOutActive); }

        return {};
    }

    // The metadata spelling exists only in editor builds, which is exactly why it is a trap: it compiles
    // everywhere and does nothing anywhere.
    auto Has_InertSaveGameMetadata(const FProperty* InProperty) -> bool
    {
#if WITH_METADATA
        return InProperty->HasMetaData(TEXT("SaveGame")) && NOT InProperty->HasAnyPropertyFlags(CPF_SaveGame);
#else
        return false;
#endif
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_EntityScriptSaveFieldCoverage_MetaTest,
    "Ck.Snapshot.Meta.EntityScriptSaveFieldCoverage",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_EntityScriptSaveFieldCoverage_MetaTest::
    RunTest(
        const FString& /*InParameters*/)
{
    using namespace ck_entity_script_savefield_coverage;

    auto ClassesScanned  = 0;
    auto SaveFieldsFound = 0;

    for (TObjectIterator<UClass> It; It; ++It)
    {
        auto* Class = *It;
        if (Class == nullptr || NOT Class->IsChildOf(UCk_EntityScript_UE::StaticClass()))
        { continue; }

        // A script recompile leaves the previous generation root-set under a renamed class.
        if (Class->GetName().Contains(TEXT("_REPLACED_"), ESearchCase::CaseSensitive))
        { continue; }

        ++ClassesScanned;

        for (TFieldIterator<FProperty> PropIt{Class, EFieldIterationFlags::None}; PropIt; ++PropIt)
        {
            const auto* Property = *PropIt;

            if (Has_InertSaveGameMetadata(Property))
            {
                AddError(FString::Printf(
                    TEXT("Entity script [%s] field [%s] uses meta=(SaveGame), which sets a metadata string and NOT ")
                    TEXT("the CPF_SaveGame flag the save walk keys on — the field silently does not persist, and in ")
                    TEXT("a cooked build the metadata is stripped entirely. Use the bare UPROPERTY(SaveGame)."),
                    *Class->GetName(), *Property->GetName()));
                continue;
            }

            if (NOT Property->HasAnyPropertyFlags(CPF_SaveGame))
            { continue; }

            ++SaveFieldsFound;

            auto Active  = TSet<const UStruct*>{};
            const auto Verdict = Analyze_SaveGameProperty(Property, Active);

            if (NOT Verdict.IsIllegal)
            { continue; }

            AddError(FString::Printf(
                TEXT("Entity script [%s] field [%s] is UPROPERTY(SaveGame) but %s. Spawn-recipe fields carry plain ")
                TEXT("values only; anything a rebuild must re-derive belongs in the feature's setup path, not in ")
                TEXT("the saved blob."),
                *Class->GetName(), *Property->GetName(), *Verdict.Reason));
        }
    }

    AddInfo(FString::Printf(TEXT("Entity-script SaveGame coverage: classes=[%d] CPF_SaveGame fields=[%d]"),
        ClassesScanned, SaveFieldsFound));

    // A fence that scanned nothing would pass for the worst possible reason.
    TestTrue(TEXT("at least one entity-script class was reachable to scan"), ClassesScanned > 0);

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
