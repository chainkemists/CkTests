#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkEcs/EntityScript/CkEntityScript.h"
#include "CkEcs/Subsystem/CkEntityScript_Subsystem.h"

#include <AssetRegistry/AssetData.h>
#include <AssetRegistry/IAssetRegistry.h>
#include <Editor.h>
#include <ISourceControlModule.h>
#include <ISourceControlProvider.h>
#include <HAL/FileManager.h>
#include <Engine/Blueprint.h>
#include <Engine/BlueprintGeneratedClass.h>
#include <EdGraph/EdGraphPin.h>
#include <Kismet2/BlueprintEditorUtils.h>
#include <Kismet2/KismetEditorUtilities.h>
#include <Kismet2/StructureEditorUtils.h>
#include <Misc/Guid.h>
#include <Misc/ScopeExit.h>
#include <Subsystems/EditorAssetSubsystem.h>
#include <UObject/Package.h>
#include <Misc/PackageName.h>
#include <UObject/ObjectSaveContext.h>
#include <UObject/StrongObjectPtr.h>
#include <UObject/UnrealType.h>

namespace ck_test_entityscript_editor_services
{
    constexpr auto kTestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_EntityScript_EditorServices,
    "Ck.EntityScript.EditorServices.PendingAssetRename",
    ck_test_entityscript_editor_services::kTestFlags)

bool FCkTest_EntityScript_EditorServices::RunTest(const FString& Parameters)
{
    if (NOT TestNotNull(TEXT("editor is available before the scoped startup-state check"), GEditor))
    { return false; }
    if (NOT TestNotNull(TEXT("engine is available before fixture setup"), GEngine))
    { return false; }
    auto& Editor = *GEditor;

    if (NOT TestNotNull(TEXT("editor asset subsystem is available for fixture cleanup"),
        Editor.GetEditorSubsystem<UEditorAssetSubsystem>()))
    { return false; }
    auto& EditorAssets = *Editor.GetEditorSubsystem<UEditorAssetSubsystem>();

    if (NOT TestNotNull(TEXT("production EntityScript subsystem exists"),
        GEngine->GetEngineSubsystem<UCk_EntityScript_Subsystem_UE>()))
    { return false; }
    auto& EntityScripts = *GEngine->GetEngineSubsystem<UCk_EntityScript_Subsystem_UE>();

    auto& SourceControl = ISourceControlModule::Get();
    const auto OriginalProvider = SourceControl.GetProvider().GetName();
    SourceControl.SetProvider(FName(TEXT("None")));
    ON_SCOPE_EXIT { SourceControl.SetProvider(OriginalProvider); };

    const auto Suffix = FGuid::NewGuid().ToString(EGuidFormats::Digits);
    const auto AssetRoot = FString::Printf(TEXT("/Game/__CkEntityScriptEditorServices_%s"), *Suffix);
    const auto OldBlueprintName = FName(*FString::Printf(TEXT("CkEntityScriptEditorServices_%s_Old"), *Suffix));
    const auto NewBlueprintName = FName(*FString::Printf(TEXT("CkEntityScriptEditorServices_%s_New"), *Suffix));
    const auto FinalBlueprintName = FName(*FString::Printf(TEXT("CkEntityScriptEditorServices_%s_Final"), *Suffix));
    auto OldPackage = TStrongObjectPtr<UPackage>{CreatePackage(*(AssetRoot / OldBlueprintName.ToString()))};

    if (NOT TestNotNull(TEXT("owned Blueprint package exists"), OldPackage.Get()))
    { return false; }

    auto Blueprint = TStrongObjectPtr<UBlueprint>{FKismetEditorUtilities::CreateBlueprint(
        UCk_EntityScript_UE::StaticClass(), OldPackage.Get(), OldBlueprintName,
        BPTYPE_Normal, UBlueprint::StaticClass(), UBlueprintGeneratedClass::StaticClass())};

    if (NOT TestNotNull(TEXT("owned EntityScript Blueprint exists"), Blueprint.Get()))
    { return false; }

    const auto OldBlueprintPath = Blueprint->GetPathName();
    const auto NewBlueprintPath = AssetRoot / NewBlueprintName.ToString() + TEXT(".") + NewBlueprintName.ToString();
    const auto FinalBlueprintPath = AssetRoot / FinalBlueprintName.ToString() + TEXT(".") + FinalBlueprintName.ToString();
    auto CleanupBlueprintPath = OldBlueprintPath;
    auto CleanupSpawnParamsPath = FString{};
    auto CleanupIntermediateSpawnParamsPath = FString{};
    auto CleanupRenamedSpawnParamsPath = FString{};
    auto bFinalSpawnParamsRemoved = false;
    auto SpawnParams = TStrongObjectPtr<UUserDefinedStruct>{};
    ON_SCOPE_EXIT
    {
        SpawnParams.Reset();
        Blueprint.Reset();
        OldPackage.Reset();
        const auto DeleteOwnedAssetIfPhysical = [&EditorAssets, &CleanupRenamedSpawnParamsPath,
            &bFinalSpawnParamsRemoved](const FString& ObjectPath)
        {
            if (ObjectPath.IsEmpty())
            { return; }
            if (bFinalSpawnParamsRemoved && ObjectPath == CleanupRenamedSpawnParamsPath)
            { return; }
            const auto PackagePath = FPackageName::ObjectPathToPackageName(ObjectPath);
            if (NOT FPackageName::DoesPackageExist(PackagePath) &&
                NOT IsValid(FindObject<UObject>(nullptr, *ObjectPath)))
            { return; }
            if (EditorAssets.DoesAssetExist(ObjectPath))
            { EditorAssets.DeleteAsset(ObjectPath); }
        };
        DeleteOwnedAssetIfPhysical(CleanupBlueprintPath);
        DeleteOwnedAssetIfPhysical(OldBlueprintPath);
        DeleteOwnedAssetIfPhysical(NewBlueprintPath);
        DeleteOwnedAssetIfPhysical(CleanupSpawnParamsPath);
        DeleteOwnedAssetIfPhysical(CleanupIntermediateSpawnParamsPath);
        DeleteOwnedAssetIfPhysical(CleanupRenamedSpawnParamsPath);
        for (const auto& OwnedObjectPath : TArray<FString>{
            OldBlueprintPath, NewBlueprintPath, FinalBlueprintPath,
            CleanupSpawnParamsPath, CleanupIntermediateSpawnParamsPath, CleanupRenamedSpawnParamsPath})
        {
            if (OwnedObjectPath.IsEmpty())
            { continue; }
            const auto SidecarFilename = FPackageName::LongPackageNameToFilename(
                FPackageName::ObjectPathToPackageName(OwnedObjectPath), TEXT(".ckexport"));
            IFileManager::Get().Delete(*SidecarFilename, false, true, true);
        }
    };

    FKismetEditorUtilities::CompileBlueprint(Blueprint.Get());

    const auto OldClass = TWeakObjectPtr<UClass>{Blueprint->GeneratedClass};
    if (NOT TestNotNull(TEXT("old Blueprint has a generated EntityScript class"), OldClass.Get()))
    { return false; }

    SpawnParams = TStrongObjectPtr<UUserDefinedStruct>{
        EntityScripts.GetOrCreate_SpawnParamsStructForEntity(OldClass.Get())};
    if (NOT TestNotNull(TEXT("production API creates SpawnParams for the old Blueprint"), SpawnParams.Get()))
    { return false; }

    const auto OldStructName = SpawnParams->GetFName();
    CleanupSpawnParamsPath = SpawnParams->GetPathName();
    if (NOT TestTrue(TEXT("production cache owns the old SpawnParams entry"),
        EntityScripts._EntitySpawnParams_StructsByName.FindRef(OldStructName) == SpawnParams.Get()))
    { return false; }

    // The production factory creates the UDS in its package without announcing it to the
    // registry. Register the bare owned assets before the exposed-property update saves it.
    if (NOT EditorAssets.DoesAssetExist(OldBlueprintPath))
    { IAssetRegistry::GetChecked().AssetCreated(Blueprint.Get()); }
    if (NOT EditorAssets.DoesAssetExist(CleanupSpawnParamsPath))
    { IAssetRegistry::GetChecked().AssetCreated(SpawnParams.Get()); }

    auto ExposedPin = FEdGraphPinType{};
    ExposedPin.PinCategory = FName(TEXT("int"));
    const auto ExposedValueName = FName(TEXT("ExposedValue"));
    if (NOT TestTrue(TEXT("owned Blueprint has an exposed field"),
        FBlueprintEditorUtils::AddMemberVariable(Blueprint.Get(), ExposedValueName, ExposedPin)))
    { return false; }
    FBlueprintEditorUtils::SetBlueprintOnlyEditableFlag(Blueprint.Get(), ExposedValueName, false);
    FBlueprintEditorUtils::SetBlueprintVariableMetaData(
        Blueprint.Get(), ExposedValueName, nullptr, FName(TEXT("ExposeOnSpawn")), TEXT("true"));
    FKismetEditorUtilities::CompileBlueprint(Blueprint.Get());
    if (NOT TestTrue(TEXT("production updates the existing SpawnParams after exposed-field compilation"),
        EntityScripts.GetOrCreate_SpawnParamsStructForEntity(Blueprint->GeneratedClass, true) == SpawnParams.Get()))
    { return false; }

    auto StructPin = FEdGraphPinType{};
    StructPin.PinCategory = FName(TEXT("struct"));
    StructPin.PinSubCategoryObject = SpawnParams.Get();
    if (NOT TestTrue(TEXT("owned Blueprint references its generated SpawnParams struct"),
        FBlueprintEditorUtils::AddMemberVariable(Blueprint.Get(), FName(TEXT("StructReference")), StructPin)))
    { return false; }
    FKismetEditorUtilities::CompileBlueprint(Blueprint.Get());
    if (NOT TestTrue(TEXT("live Blueprint exposes the editable field"),
        FindFProperty<FProperty>(Blueprint->GeneratedClass, ExposedValueName) != nullptr))
    { return false; }
    const auto GeneratedFields = FStructureEditorUtils::GetVarDesc(SpawnParams.Get());
    auto ExposedFieldGuid = FGuid{};
    for (const auto& Field : GeneratedFields)
    {
        if (Field.FriendlyName == ExposedValueName.ToString())
        { ExposedFieldGuid = Field.VarGuid; }
    }
    if (NOT TestTrue(TEXT("generated SpawnParams keeps the exposed field"),
        ExposedFieldGuid.IsValid()))
    { return false; }
    if (NOT TestTrue(TEXT("production sees the latest Blueprint generated class"),
        EntityScripts.GetOrCreate_SpawnParamsStructForEntity(Blueprint->GeneratedClass, true) == SpawnParams.Get()))
    { return false; }

    const auto HasPendingSave = EntityScripts._EntitySpawnParams_StructsToSave.Contains(SpawnParams.Get());
    TestTrue(TEXT("production exposed-field update leaves a struct save pending"), HasPendingSave);

    if (HasPendingSave)
    {
        // Exercise the real pre-save collector with an owned Blueprint reference. GEditor is
        // absent only for the callback, then restored before editor asset work or ticking.
        auto SaveContextData = FObjectSaveContextData{};
        auto SaveContext = FObjectPreSaveContext{SaveContextData};
        {
            ON_SCOPE_EXIT { GEditor = &Editor; };
            GEditor = nullptr;
            EntityScripts.OnObjectSaved(Blueprint.Get(), SaveContext);
        }
        TestTrue(TEXT("unavailable editor services retain the generated struct for a later save"),
            EntityScripts._EntitySpawnParams_StructsToSave.Contains(SpawnParams.Get()));
    }

    {
        auto& Engine = *GEngine;
        ON_SCOPE_EXIT { GEngine = &Engine; };
        GEngine = nullptr;
        TestFalse(TEXT("null engine rejects direct SpawnParams save"),
            UCk_EntityScript_Subsystem_UE::SaveStruct(SpawnParams.Get()));
    }

    if (NOT TestTrue(TEXT("owned Blueprint asset saves before the rename"),
        EditorAssets.SaveAsset(OldBlueprintPath)))
    { return false; }
    if (EntityScripts._EntitySpawnParams_StructsToSave.Contains(SpawnParams.Get()))
    { FTSTicker::GetCoreTicker().Tick(1.0f); }
    TestFalse(TEXT("restored services drain the production pending struct save"),
        EntityScripts._EntitySpawnParams_StructsToSave.Contains(SpawnParams.Get()));
    TestTrue(TEXT("replayed SpawnParams save persists the owned package"),
        FPackageName::DoesPackageExist(FPackageName::ObjectPathToPackageName(CleanupSpawnParamsPath)));

    if (NOT TestNotNull(TEXT("asset registry is available"), IAssetRegistry::Get()))
    { return false; }
    auto& AssetRegistry = *IAssetRegistry::Get();

    // Rename the real owned Blueprint while disconnecting only this callback. The generated
    // SpawnParams stays at its old path, which is the production pre-event state under test.
    // Cleanup both names even if RenameAsset moves the object but reports failure.
    CleanupBlueprintPath = NewBlueprintPath;
    AssetRegistry.OnAssetRenamed().Remove(EntityScripts._OnAssetRenamed_DelegateHandle);
    {
        ON_SCOPE_EXIT
        {
            EntityScripts._OnAssetRenamed_DelegateHandle = AssetRegistry.OnAssetRenamed().AddUObject(
                &EntityScripts, &UCk_EntityScript_Subsystem_UE::OnAssetRenamed);
        };
        if (NOT TestTrue(TEXT("owned Blueprint is renamed by the editor asset subsystem"),
            EditorAssets.RenameAsset(OldBlueprintPath, NewBlueprintPath)))
        { return false; }
    }
    const auto RenamedClass = TWeakObjectPtr<UClass>{Blueprint->GeneratedClass};
    if (NOT TestNotNull(TEXT("renamed Blueprint retains its generated class"), RenamedClass.Get()))
    { return false; }
    const auto NewStructName = FName(*FString::Printf(TEXT("EntitySpawnParams_CkEntityScriptEditorServices_%s_New"), *Suffix));
    CleanupRenamedSpawnParamsPath = CleanupSpawnParamsPath.Replace(
        *OldStructName.ToString(), *NewStructName.ToString());
    CleanupIntermediateSpawnParamsPath = CleanupRenamedSpawnParamsPath;
    if (NOT TestTrue(TEXT("generated class takes the new Blueprint name"),
        RenamedClass->GetName().Contains(NewBlueprintName.ToString()) && NewStructName != OldStructName))
    { return false; }

    // Real AssetData and the production callback, with the editor global scoped to its startup
    // absence. Restore it before any ticker or other world work.
    {
        ON_SCOPE_EXIT { GEditor = &Editor; };
        GEditor = nullptr;
        EntityScripts.OnAssetRenamed(FAssetData{Blueprint.Get()}, OldBlueprintPath);
    }

    TestTrue(TEXT("unavailable editor services leave the original cache entry untouched"),
        EntityScripts._EntitySpawnParams_StructsByName.FindRef(OldStructName) == SpawnParams.Get());
    TestTrue(TEXT("unavailable editor services publish no renamed cache entry"),
        NOT EntityScripts._EntitySpawnParams_StructsByName.Contains(NewStructName));

    // Move the Blueprint again before replay. Its struct has never moved from the original
    // package, so the queued operation must retarget Old -> Final without loading New.
    CleanupBlueprintPath = FinalBlueprintPath;
    AssetRegistry.OnAssetRenamed().Remove(EntityScripts._OnAssetRenamed_DelegateHandle);
    {
        ON_SCOPE_EXIT
        {
            EntityScripts._OnAssetRenamed_DelegateHandle = AssetRegistry.OnAssetRenamed().AddUObject(
                &EntityScripts, &UCk_EntityScript_Subsystem_UE::OnAssetRenamed);
        };
        if (NOT TestTrue(TEXT("owned Blueprint is renamed a second time"),
            EditorAssets.RenameAsset(NewBlueprintPath, FinalBlueprintPath)))
        { return false; }
    }
    const auto FinalStructName = FName(*FString::Printf(TEXT("EntitySpawnParams_CkEntityScriptEditorServices_%s_Final"), *Suffix));
    const auto FinalStructPath = CleanupSpawnParamsPath.Replace(
        *OldStructName.ToString(), *FinalStructName.ToString());
    {
        ON_SCOPE_EXIT { GEditor = &Editor; };
        GEditor = nullptr;
        EntityScripts.OnAssetRenamed(FAssetData{Blueprint.Get()}, NewBlueprintPath);
    }
    TestTrue(TEXT("chained unavailable rename retains original cache identity"),
        EntityScripts._EntitySpawnParams_StructsByName.FindRef(OldStructName) == SpawnParams.Get());
    TestTrue(TEXT("pending chain resolves the live Blueprint to its original SpawnParams"),
        EntityScripts.GetOrCreate_SpawnParamsStructForEntity(Blueprint->GeneratedClass) == SpawnParams.Get());

    // A pending operation is retried by the production ticker once editor services exist.
    FTSTicker::GetCoreTicker().Tick(1.0f);
    TestTrue(TEXT("restored services replay the chained rename from the original asset"),
        SpawnParams->GetPathName() == FinalStructPath);
    TestTrue(TEXT("rename preserves the exposed SpawnParams field GUID"),
        FStructureEditorUtils::GetVarDesc(SpawnParams.Get()).ContainsByPredicate(
            [&ExposedValueName, &ExposedFieldGuid](const FStructVariableDescription& Field)
            { return Field.FriendlyName == ExposedValueName.ToString() && Field.VarGuid == ExposedFieldGuid; }));
    TestFalse(TEXT("intermediate SpawnParams path was never materialized"),
        EditorAssets.DoesAssetExist(CleanupRenamedSpawnParamsPath));
    CleanupRenamedSpawnParamsPath = FinalStructPath;

    // The owned Blueprint is then removed while this one delegate is disconnected. Replay of
    // its actual AssetData must remove the generated struct after editor services return.
    const auto RemovedBlueprintData = FAssetData{Blueprint.Get()};
    AssetRegistry.OnAssetRemoved().Remove(EntityScripts._OnAssetRemoved_DelegateHandle);
    {
        ON_SCOPE_EXIT
        {
            EntityScripts._OnAssetRemoved_DelegateHandle = AssetRegistry.OnAssetRemoved().AddUObject(
                &EntityScripts, &UCk_EntityScript_Subsystem_UE::OnAssetRemoved);
        };
        if (NOT TestTrue(TEXT("owned Blueprint asset is removed"),
            EditorAssets.DeleteAsset(FinalBlueprintPath)))
        { return false; }
    }
    CleanupBlueprintPath.Empty();

    {
        ON_SCOPE_EXIT { GEditor = &Editor; };
        GEditor = nullptr;
        EntityScripts.OnAssetRemoved(RemovedBlueprintData);
    }
    FTSTicker::GetCoreTicker().Tick(1.0f);
    bFinalSpawnParamsRemoved = NOT FPackageName::DoesPackageExist(
        FPackageName::ObjectPathToPackageName(CleanupRenamedSpawnParamsPath));
    TestTrue(TEXT("restored editor services replay SpawnParams removal"), bFinalSpawnParamsRemoved);

    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
