#include "CkGroundNavStreamingAcceptance_EditorUtils.h"

#include "CkTestsEditor/CkTestsEditor_Log.h"

#include "CkEntitySpawner/CkEntitySpawner_Actor.h"
#include "CkGroundNav/Volume/CkGroundNavVolume_EntityScript.h"
#include "CkPathNetwork/Actor/CkPathNetwork_Actor.h"
#include "CkPathNetwork/Network/CkPathNetwork_Types.h"
#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include <Editor.h>
#include <EditorLevelUtils.h>
#include <Engine/Level.h>
#include <Engine/LevelStreaming.h>
#include <Engine/LevelStreamingDynamic.h>
#include <Engine/World.h>
#include <FileHelpers.h>
#include <Misc/PackageName.h>
#include <UObject/Package.h>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_groundnav_streaming_acceptance_editor_utils
{
    constexpr auto kFixtureRoot = TEXT("/CkTests/GroundNavAcceptance");

    auto GetEditorWorld() -> UWorld*
    {
        return GEditor != nullptr ? GEditor->GetEditorWorldContext().World() : nullptr;
    }

    auto GetIsFixtureLevelPackage(const FString& InPackageName) -> bool
    {
        return FPackageName::IsValidLongPackageName(InPackageName) &&
            (InPackageName == kFixtureRoot || InPackageName.StartsWith(FString{kFixtureRoot} + TEXT("/")));
    }

    auto FindLoadedLevel(UWorld& InWorld, const FString& InPackageName) -> ULevel*
    {
        for (auto* Level : InWorld.GetLevels())
        {
            if (Level != nullptr && Level->GetOutermost()->GetName() == InPackageName)
            { return Level; }
        }
        return nullptr;
    }

    auto FindStreamingLevel(UWorld& InWorld, const FString& InPackageName) -> ULevelStreaming*
    {
        for (auto* Level : InWorld.GetStreamingLevels())
        {
            if (Level != nullptr && Level->GetWorldAssetPackageName() == InPackageName)
            { return Level; }
        }
        return nullptr;
    }
}

// --------------------------------------------------------------------------------------------------------------------

auto UCk_GroundNavStreamingAcceptance_EditorUtils::CreatePathNetworkActor() -> ACk_PathNetwork_UE*
{
    using namespace ck_groundnav_streaming_acceptance_editor_utils;

    auto* World = GetEditorWorld();
    if (World == nullptr || World->PersistentLevel == nullptr || World->GetCurrentLevel() != World->PersistentLevel)
    {
        ck::tests_editor::Error(TEXT("GroundNav acceptance PathNetwork requires the persistent fixture level to be current"));
        return nullptr;
    }

    auto SpawnParams = FActorSpawnParameters{};
    SpawnParams.OverrideLevel = World->PersistentLevel;
    auto* Actor = World->SpawnActor<ACk_PathNetwork_UE>(FVector::ZeroVector, FRotator::ZeroRotator, SpawnParams);
    if (Actor == nullptr)
    {
        ck::tests_editor::Error(TEXT("GroundNav acceptance could not spawn its PathNetwork actor"));
        return nullptr;
    }

    auto Points = TArray<FCk_PathNetwork_RibbonPoint>{};
    Points.Add(FCk_PathNetwork_RibbonPoint{FVector{-600.0f, 0.0f, 150.0f}, 100.0f});
    Points.Add(FCk_PathNetwork_RibbonPoint{FVector{0.0f, -400.0f, 300.0f}, 100.0f});
    Points.Add(FCk_PathNetwork_RibbonPoint{FVector{0.0f, 500.0f, 500.0f}, 100.0f});
    Points.Add(FCk_PathNetwork_RibbonPoint{FVector{0.0f, 1200.0f, 500.0f}, 100.0f});
    Actor->Set_Ribbons({FCk_PathNetwork_Ribbon{MoveTemp(Points)}});
    Actor->SetActorLabel(TEXT("GroundNavAcceptance_PathNetwork"));
    Actor->MarkPackageDirty();
    return Actor;
}

// --------------------------------------------------------------------------------------------------------------------

auto UCk_GroundNavStreamingAcceptance_EditorUtils::CreateVolumeSpawner() -> ACk_EntitySpawner_UE*
{
    using namespace ck_groundnav_streaming_acceptance_editor_utils;

    auto* World = GetEditorWorld();
    if (World == nullptr || World->PersistentLevel == nullptr || World->GetCurrentLevel() != World->PersistentLevel)
    {
        ck::tests_editor::Error(TEXT("GroundNav acceptance volume requires the persistent fixture level to be current"));
        return nullptr;
    }

    auto SpawnParams = FActorSpawnParameters{};
    SpawnParams.OverrideLevel = World->PersistentLevel;
    auto* Spawner = World->SpawnActor<ACk_EntitySpawner_UE>(FVector::ZeroVector, FRotator::ZeroRotator, SpawnParams);
    if (Spawner == nullptr)
    {
        ck::tests_editor::Error(TEXT("GroundNav acceptance could not spawn its volume owner"));
        return nullptr;
    }

    Spawner->EditorOnly_InitializeEntityScript(UCk_GroundNavVolume_EntityScript::StaticClass());
    auto* Script = Cast<UCk_GroundNavVolume_EntityScript>(Spawner->Get_EntityScript());
    if (Script == nullptr)
    {
        Spawner->Destroy();
        ck::tests_editor::Error(TEXT("GroundNav acceptance could not initialize its volume EntityScript"));
        return nullptr;
    }

    auto Config = FCk_GroundNav_BakeConfig{25.0f, 10.0f};
    Config.Set_TileSizeUu(800.0f);
    const auto Profile = FCk_GroundNav_AgentProfile{
        FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};
    auto Params = FCk_Fragment_GroundNavVolume_ParamsData{
        FBox{FVector{-800.0f, -800.0f, -100.0f}, FVector{800.0f, 800.0f, 500.0f}},
        Config, Profile};
    Params.Set_AutoBuildOnSetup(ECk_EnableDisable::Disable);
    Params.Set_CookKey(FName{TEXT("GroundNavStreamingAcceptance")});
    Params.Set_StreamingVolumeId(71001);
    Params.Set_StreamingBuildScope(ECk_GroundNav_StreamingBuildScope::ManifestDriven);
    Script->EditorOnly_SetParams(Params);
    Spawner->EditorOnly_RebuildEntity();
    Spawner->SetActorLabel(TEXT("GroundNavAcceptance_Volume"));
    Spawner->MarkPackageDirty();
    return Spawner;
}

// --------------------------------------------------------------------------------------------------------------------

auto UCk_GroundNavStreamingAcceptance_EditorUtils::CreateOrAddStreamingLevel(
    const FString& InLevelPackageName) -> bool
{
    using namespace ck_groundnav_streaming_acceptance_editor_utils;

    if (NOT GetIsFixtureLevelPackage(InLevelPackageName))
    {
        ck::tests_editor::Error(TEXT("GroundNav acceptance refused non-fixture level [{}]"), InLevelPackageName);
        return false;
    }

    auto* World = GetEditorWorld();
    if (World == nullptr)
    {
        ck::tests_editor::Error(TEXT("GroundNav acceptance could not resolve the editor world"));
        return false;
    }

    if (FindStreamingLevel(*World, InLevelPackageName) != nullptr)
    { return true; }

    const auto Filename = FPackageName::LongPackageNameToFilename(
        InLevelPackageName, FPackageName::GetMapPackageExtension());
    const auto LevelAlreadyExists = FPackageName::DoesPackageExist(InLevelPackageName);
    auto* Streaming = LevelAlreadyExists
        ? UEditorLevelUtils::AddLevelToWorld(World, *InLevelPackageName, ULevelStreamingDynamic::StaticClass())
        : UEditorLevelUtils::CreateNewStreamingLevelForWorld(
            *World, ULevelStreamingDynamic::StaticClass(), Filename, false, nullptr, false);
    if (Streaming == nullptr)
    {
        ck::tests_editor::Error(TEXT("GroundNav acceptance could not add streaming level [{}]"), InLevelPackageName);
        return false;
    }
    return true;
}

auto UCk_GroundNavStreamingAcceptance_EditorUtils::MakeNamedLevelCurrent(
    const FString& InLevelPackageName) -> bool
{
    using namespace ck_groundnav_streaming_acceptance_editor_utils;

    auto* World = GetEditorWorld();
    auto* Level = World != nullptr ? FindLoadedLevel(*World, InLevelPackageName) : nullptr;
    if (World == nullptr || Level == nullptr)
    {
        ck::tests_editor::Error(TEXT("GroundNav acceptance could not make level [{}] current"), InLevelPackageName);
        return false;
    }
    UEditorLevelUtils::MakeLevelCurrent(Level);
    return World->GetCurrentLevel() == Level;
}

auto UCk_GroundNavStreamingAcceptance_EditorUtils::RestorePersistentCurrentLevel() -> bool
{
    using namespace ck_groundnav_streaming_acceptance_editor_utils;

    auto* World = GetEditorWorld();
    if (World == nullptr || World->PersistentLevel == nullptr)
    {
        ck::tests_editor::Error(TEXT("GroundNav acceptance could not restore the persistent level"));
        return false;
    }
    UEditorLevelUtils::MakeLevelCurrent(World->PersistentLevel);
    return World->GetCurrentLevel() == World->PersistentLevel;
}

auto UCk_GroundNavStreamingAcceptance_EditorUtils::DeleteOwnedActorsInCurrentLevel(
    const FName InOwnershipTag) -> int32
{
    using namespace ck_groundnav_streaming_acceptance_editor_utils;

    auto* World = GetEditorWorld();
    auto* Level = World != nullptr ? World->GetCurrentLevel() : nullptr;
    if (Level == nullptr || NOT GetIsFixtureLevelPackage(Level->GetOutermost()->GetName()))
    {
        ck::tests_editor::Error(TEXT("GroundNav acceptance refused actor cleanup outside a current fixture level"));
        return 0;
    }

    auto OwnedActors = TArray<TWeakObjectPtr<AActor>>{};
    for (const auto& ActorPtr : Level->Actors)
    {
        auto* Actor = ActorPtr.Get();
        if (Actor != nullptr && Actor->Tags.Contains(InOwnershipTag))
        { OwnedActors.Add(Actor); }
    }

    auto DeletedCount = 0;
    for (const auto& WeakActor : OwnedActors)
    {
        if (auto* Actor = WeakActor.Get(); Actor != nullptr && World->EditorDestroyActor(Actor, true))
        { ++DeletedCount; }
    }
    return DeletedCount;
}

auto UCk_GroundNavStreamingAcceptance_EditorUtils::SaveDirtyFixtureLevels() -> bool
{
    using namespace ck_groundnav_streaming_acceptance_editor_utils;

    auto* World = GetEditorWorld();
    if (World == nullptr)
    {
        ck::tests_editor::Error(TEXT("GroundNav acceptance could not save: no editor world"));
        return false;
    }

    auto Packages = TArray<UPackage*>{};
    for (auto* Level : World->GetLevels())
    {
        if (Level == nullptr)
        { continue; }
        auto* Package = Level->GetOutermost();
        if (Package != nullptr && Package->IsDirty() && GetIsFixtureLevelPackage(Package->GetName()))
        { Packages.Add(Package); }
    }
    return UEditorLoadingAndSavingUtils::SavePackages(Packages, true);
}

// --------------------------------------------------------------------------------------------------------------------
