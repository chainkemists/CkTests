#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkGroundNavEditor/Cook/CkGroundNavCook_FieldCooker.h"

#include "CkCore/Macros/CkMacros.h"
#include "CkGroundNav/Backend/CkGroundNav_GeometryBackend_Jolt.h"
#include "CkGroundNav/Bake/CkGroundNav_AgentProfile.h"
#include "CkGroundNav/Bake/CkGroundNav_BakeTypes.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Field/CkGroundNav_FieldSerialize.h"
#include "CkGroundNav/Field/CkGroundNav_TileBake.h"
#include "CkGroundNav/Volume/CkGroundNavVolume_EntityScript.h"
#include "CkGroundNav/Volume/CkGroundNavVolume_Utils.h"
#include "CkJolt/Settings/CkJolt_ProjectSettings.h"
#include "CkJolt/StaticWorld/CkJoltStaticWorld_Subsystem.h"

#include "CkEntitySpawner/CkEntitySpawner_Actor.h"
#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

#include <Components/StaticMeshComponent.h>
#include <Algo/AllOf.h>
#include <Engine/StaticMesh.h>
#include <Engine/StaticMeshActor.h>
#include <Engine/World.h>
#include <Misc/ScopeExit.h>
#include <NativeGameplayTags.h>
#include <UObject/UnrealType.h>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_groundnav_cook_driver
{
    constexpr auto kTestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;
    constexpr auto InformEngineOfWorld = false;

    auto Spawn_Floor(UWorld& InWorld) -> AStaticMeshActor*
    {
        auto* Cube = LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Cube.Cube"));
        if (Cube == nullptr)
        { return nullptr; }

        auto* Floor = InWorld.SpawnActor<AStaticMeshActor>();
        if (Floor == nullptr)
        { return nullptr; }

        auto* Mesh = Floor->GetStaticMeshComponent();
        Mesh->SetMobility(EComponentMobility::Static);
        Mesh->SetStaticMesh(Cube);
        Mesh->SetWorldScale3D(FVector{8.0, 8.0, 0.1});
        Mesh->SetCollisionProfileName(TEXT("BlockAll"));
        Floor->RegisterAllComponents();
        return Floor;
    }

    auto Set_ScriptParams(
        UCk_GroundNavVolume_EntityScript& InScript,
        const FCk_Fragment_GroundNavVolume_ParamsData& InParams) -> bool
    {
        auto* Property = FindFProperty<FStructProperty>(InScript.GetClass(), TEXT("_Params"));
        if (Property == nullptr || Property->Struct != FCk_Fragment_GroundNavVolume_ParamsData::StaticStruct())
        { return false; }

        auto* Target = Property->ContainerPtrToValuePtr<FCk_Fragment_GroundNavVolume_ParamsData>(&InScript);
        if (Target == nullptr)
        { return false; }

        *Target = InParams;
        return true;
    }
}

// --------------------------------------------------------------------------------------------------------------------

UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_GroundNavCook_Duplicate, "CkTests.GroundNav.Cook.Duplicate");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_GroundNavCook_Crawler, "CkTests.GroundNav.Cook.Crawler");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_GroundNavCook_Climber, "CkTests.GroundNav.Cook.Climber");

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNavCook_Driver,
    "Ck.GroundNav.Cook.Driver",
    ck_test_groundnav_cook_driver::kTestFlags)

bool FCkTest_GroundNavCook_Driver::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cook_driver;

    auto* Settings = GetMutableDefault<UCk_Jolt_ProjectSettings_UE>();
    if (NOT TestNotNull(TEXT("the Jolt settings CDO resolves"), Settings))
    { return false; }

    const auto RestoreMode = Settings->Get_EditorStaticWorldMode();
    ON_SCOPE_EXIT { Settings->TestOnly_Set_EditorStaticWorldMode(RestoreMode); };
    Settings->TestOnly_Set_EditorStaticWorldMode(ECk_Jolt_EditorStaticWorldMode::LiveExtract);

    auto* World = UWorld::CreateWorld(EWorldType::Editor, InformEngineOfWorld, TEXT("GroundNavCookDriver"));
    if (NOT TestNotNull(TEXT("a hermetic editor world is created"), World))
    { return false; }
    ON_SCOPE_EXIT { World->DestroyWorld(InformEngineOfWorld); };

    if (NOT TestNotNull(TEXT("a static floor is created"), Spawn_Floor(*World)))
    { return false; }

    if (NOT TestTrue(TEXT("the shared cook geometry preparation succeeds"),
        ck::groundnav::cook::FCk_GroundNav_FieldCooker::Prepare_WorldGeometry(*World)))
    { return false; }

    auto* Spawner = World->SpawnActor<ACk_EntitySpawner_UE>();
    if (NOT TestNotNull(TEXT("a GroundNav spawner is created"), Spawner))
    { return false; }
    Spawner->EditorOnly_InitializeEntityScript(UCk_GroundNavVolume_EntityScript::StaticClass());

    auto* Script = Cast<UCk_GroundNavVolume_EntityScript>(Spawner->Get_EntityScript());
    if (NOT TestNotNull(TEXT("the spawner owns the GroundNav script"), Script))
    { return false; }

    auto Config = FCk_GroundNav_BakeConfig{25.0f, 10.0f};
    Config.Set_TileSizeUu(400.0f);
    const auto Profile = FCk_GroundNav_AgentProfile{
        FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};
    auto Params = FCk_Fragment_GroundNavVolume_ParamsData{
        FBox{FVector{-700.0, -700.0, -200.0}, FVector{700.0, 700.0, 300.0}}, Config, Profile};
    Params.Set_CookKey(TEXT("Driver"));

    if (NOT TestTrue(TEXT("the script accepts the authored params"), Set_ScriptParams(*Script, Params)))
    { return false; }

    auto Plans = TArray<ck::groundnav::cook::FCk_GroundNav_CookFieldPlan>{};
    const auto Stats = ck::groundnav::cook::FCk_GroundNav_FieldCooker::Cook_Volume(*World,
        ck::groundnav::Get_PlacedVolumeParams(Script->Get_Params(), Spawner->GetActorTransform()),
        FName{TEXT("/Game/Tests/GroundNavCookDriver")}, ck::groundnav::cook::ECk_GroundNav_CookMode::DryRun, Plans);

    if (NOT TestTrue(TEXT("the dry run completes"), Stats._Success) ||
        NOT TestEqual(TEXT("the dry run writes no assets"), Stats._NumAssetsWritten, 0) ||
        NOT TestEqual(TEXT("the default profile yields one planned field"), Plans.Num(), 1))
    { return false; }

    TestEqual(TEXT("the legacy dry-run plan retains its legacy streaming identity"),
        Plans[0]._StreamingVolumeId, INDEX_NONE);
    TestTrue(TEXT("the legacy dry-run plan retains the canonical collect-all selector"),
        Plans[0]._DataLayerSelector.Get_IsAll() && Plans[0]._DataLayerSelector.Get_IsCanonical());
    TestTrue(TEXT("every planned tile records its exact published-world bounds"),
        Algo::AllOf(Plans[0]._Tiles, [&Params](const ck::groundnav::cook::FCk_GroundNav_CookTilePlan& InTile)
        {
            const auto Coord = ck::groundnav::FCk_GroundNav_TileCoord{InTile._Coord.X, InTile._Coord.Y};
            return InTile._WorldBounds == ck::groundnav::Get_TileBounds(
                ck::groundnav::Get_VolumeFieldParams(Params, {}, {}).Get_TileBakeParams(
                    Coord, ck::groundnav::FCk_GroundNav_Epoch{}));
        }));

    auto Backend = ck::groundnav::FCk_GroundNav_GeometryBackend_Jolt{World};
    if (NOT TestTrue(TEXT("the shared preparation exposes the authored floor to the bake backend"),
        Backend.Get_HasGeometryInBounds(Params.Get_VolumeBounds())))
    { return false; }

    auto DirectField = ck::groundnav::FCk_GroundNav_Field{};
    const auto DirectParams = ck::groundnav::Get_VolumeFieldParams(Params, {}, {});
    if (NOT TestTrue(TEXT("the direct pure bake completes"),
        ck::groundnav::DoBake_Field(Backend, DirectParams, ck::groundnav::FCk_GroundNav_Epoch{1}, DirectField).Get_IsCompleted()))
    { return false; }

    auto DirectBytes = TArray<uint8>{};
    ck::groundnav::Write_Field(DirectField, DirectBytes);
    TestTrue(TEXT("DryRun field bytes match the direct pure bake"), Plans[0]._SerializedField == DirectBytes);

    auto LayerSelector = ck::groundnav::FCk_GroundNav_DataLayerSelector{};
    const auto LayerNames = TArray<FName>{TEXT("/Game/DataLayers/Beta.Beta"), TEXT("/Game/DataLayers/Alpha.Alpha"),
        TEXT("/Game/DataLayers/Beta.Beta")};
    if (NOT TestTrue(TEXT("the authored layer selector is canonicalized before cook planning"),
        ck::groundnav::TryMake_DataLayerSelector(LayerNames, LayerSelector)))
    { return false; }

    auto LayerParams = Params;
    LayerParams.Set_DataLayerSelector(LayerSelector);
    auto LayerPlans = TArray<ck::groundnav::cook::FCk_GroundNav_CookFieldPlan>{};
    const auto LayerStats = ck::groundnav::cook::FCk_GroundNav_FieldCooker::Cook_Volume(*World, LayerParams,
        FName{TEXT("/Game/Tests/GroundNavCookDriver")}, ck::groundnav::cook::ECk_GroundNav_CookMode::DryRun,
        LayerPlans);
    if (NOT TestTrue(TEXT("the selector-specific dry run completes"), LayerStats._Success) ||
        NOT TestEqual(TEXT("the selector-specific dry run yields one plan"), LayerPlans.Num(), 1))
    { return false; }

    TestEqual(TEXT("the plan preserves the canonical selector"),
        LayerPlans[0]._DataLayerSelector.Get_LayerNames(), LayerSelector.Get_LayerNames());
    TestNotEqual(TEXT("a different selector changes the cook fingerprint"),
        LayerPlans[0]._Fingerprint, Plans[0]._Fingerprint);
    TestNotEqual(TEXT("a different selector gets a distinct index path"),
        ck::groundnav::Get_CookedIndexAssetPath(ck::groundnav::kCookedDataRootPath,
            TEXT("/Game/Tests/GroundNavCookDriver"), Params.Get_CookKey()),
        ck::groundnav::Get_CookedIndexAssetPath(ck::groundnav::kCookedDataRootPath,
            TEXT("/Game/Tests/GroundNavCookDriver"), LayerParams.Get_CookKey(), {}, LayerSelector));

    auto DuplicateProfiles = Params;
    DuplicateProfiles.Get_ProfileVariants().Emplace(TAG_CkTests_GroundNavCook_Duplicate, Params.Get_Profile());
    DuplicateProfiles.Get_ProfileVariants().Emplace(TAG_CkTests_GroundNavCook_Duplicate, Params.Get_Profile());

    auto DuplicatePlans = TArray<ck::groundnav::cook::FCk_GroundNav_CookFieldPlan>{};
    AddExpectedError(TEXT("GroundNavCook: cook key [Driver] repeats profile tag"), EAutomationExpectedErrorFlags::Contains,
        -1, /*IsRegex=*/false);
    const auto DuplicateStats = ck::groundnav::cook::FCk_GroundNav_FieldCooker::Cook_Volume(*World,
        DuplicateProfiles, FName{TEXT("/Game/Tests/GroundNavCookDriver")},
        ck::groundnav::cook::ECk_GroundNav_CookMode::DryRun, DuplicatePlans);
    TestFalse(TEXT("duplicate profile identities are rejected"), DuplicateStats._Success);
    TestEqual(TEXT("rejected duplicate profiles produce no plans"), DuplicatePlans.Num(), 0);

    auto* DuplicateSpawner = World->SpawnActor<ACk_EntitySpawner_UE>();
    if (NOT TestNotNull(TEXT("a second GroundNav spawner is created"), DuplicateSpawner))
    { return false; }
    DuplicateSpawner->EditorOnly_InitializeEntityScript(UCk_GroundNavVolume_EntityScript::StaticClass());

    auto* DuplicateScript = Cast<UCk_GroundNavVolume_EntityScript>(DuplicateSpawner->Get_EntityScript());
    if (NOT TestNotNull(TEXT("the second spawner owns the GroundNav script"), DuplicateScript) ||
        NOT TestTrue(TEXT("the second script accepts the duplicate cook key"), Set_ScriptParams(*DuplicateScript, Params)))
    { return false; }

    const auto DuplicateIdentities = TArray<ck::groundnav::cook::FCk_GroundNav_CookIdentity>{
        {FName{TEXT("/Game/Tests/GroundNavCookDriver")}, Script->Get_Params().Get_CookKey()},
        {FName{TEXT("/Game/Tests/GroundNavCookDriver")}, DuplicateScript->Get_Params().Get_CookKey()}};
    TestFalse(TEXT("two spawners sharing one source-level cook key are refused before plan output"),
        ck::groundnav::cook::FCk_GroundNav_FieldCooker::Get_AreCookIdentitiesUnique(DuplicateIdentities));

    const auto SelectorDuplicateIdentities = TArray<ck::groundnav::cook::FCk_GroundNav_CookIdentity>{
        {FName{TEXT("/Game/Tests/GroundNavCookDriver")}, Params.Get_CookKey(), INDEX_NONE, {}},
        {FName{TEXT("/Game/Tests/GroundNavCookDriver")}, Params.Get_CookKey(), INDEX_NONE, LayerSelector}};
    TestFalse(TEXT("a selector-specific path does not authorize a duplicate live cook owner"),
        ck::groundnav::cook::FCk_GroundNav_FieldCooker::Get_AreCookIdentitiesUnique(
            SelectorDuplicateIdentities));

    const auto DuplicateStreamingIdentities = TArray<ck::groundnav::cook::FCk_GroundNav_CookIdentity>{
        {FName{TEXT("/Game/Tests/GroundNavCookDriver")}, FName{TEXT("StreamA")}, 17, {}},
        {FName{TEXT("/Game/Tests/GroundNavCookDriver")}, FName{TEXT("StreamB")}, 17, {}}};
    TestFalse(TEXT("two source-level cook owners cannot claim one positive streaming volume id"),
        ck::groundnav::cook::FCk_GroundNav_FieldCooker::Get_AreCookIdentitiesUnique(
            DuplicateStreamingIdentities));

    auto VariantParams = Params;
    auto Crawler = Params.Get_Profile();
    Crawler.Set_StepHeightUu(25.0f);
    auto Climber = Params.Get_Profile();
    Climber.Set_StepHeightUu(75.0f);
    VariantParams.Get_ProfileVariants().Emplace(TAG_CkTests_GroundNavCook_Crawler, Crawler);
    VariantParams.Get_ProfileVariants().Emplace(TAG_CkTests_GroundNavCook_Climber, Climber);

    auto VariantPlans = TArray<ck::groundnav::cook::FCk_GroundNav_CookFieldPlan>{};
    const auto VariantStats = ck::groundnav::cook::FCk_GroundNav_FieldCooker::Cook_Volume(*World,
        VariantParams, FName{TEXT("/Game/Tests/GroundNavCookDriver")},
        ck::groundnav::cook::ECk_GroundNav_CookMode::DryRun, VariantPlans);
    if (NOT TestTrue(TEXT("the two-variant dry run completes"), VariantStats._Success) ||
        NOT TestEqual(TEXT("default and two profile variants yield three plans"), VariantPlans.Num(), 3))
    { return false; }

    const auto DirectProfiles = TArray<FCk_GroundNav_AgentProfile>{Params.Get_Profile(), Crawler, Climber};
    const auto ExpectedTags = TArray<FGameplayTag>{FGameplayTag{}, TAG_CkTests_GroundNavCook_Crawler,
        TAG_CkTests_GroundNavCook_Climber};
    for (auto Index = 0; Index < VariantPlans.Num(); ++Index)
    {
        auto ProfileParams = ck::groundnav::Get_VolumeFieldParams(VariantParams, {}, {});
        ProfileParams._Profile = DirectProfiles[Index];
        auto ProfileField = ck::groundnav::FCk_GroundNav_Field{};
        if (NOT TestTrue(TEXT("each direct profile bake completes"),
            ck::groundnav::DoBake_Field(Backend, ProfileParams, ck::groundnav::FCk_GroundNav_Epoch{1}, ProfileField).Get_IsCompleted()))
        { return false; }

        auto ProfileBytes = TArray<uint8>{};
        ck::groundnav::Write_Field(ProfileField, ProfileBytes);
        TestEqual(TEXT("each plan keeps its profile tag"), VariantPlans[Index]._ProfileTag, ExpectedTags[Index]);
        TestTrue(TEXT("each planned profile bytes match its direct bake"), VariantPlans[Index]._SerializedField == ProfileBytes);
    }
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
