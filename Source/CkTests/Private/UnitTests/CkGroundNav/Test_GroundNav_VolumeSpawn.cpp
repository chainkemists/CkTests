#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/Macros/CkMacros.h"
#include "CkCore/Validation/CkIsValid.h"
#include "CkEcs/Registry/CkRegistry.h"
#include "CkEcs/Subsystem/CkEcsEditor_Subsystem.h"
#include "CkEntitySpawner/CkEntitySpawner_Actor.h"
#include "CkGroundNav/Cook/CkGroundNav_CookedFieldIndex.h"
#include "CkGroundNav/Volume/CkGroundNavVolume_EntityScript.h"
#include "CkGroundNav/Volume/CkGroundNavVolume_Fragment.h"
#include "CkJolt/Settings/CkJolt_ProjectSettings.h"

#include <Engine/World.h>
#include <Misc/CoreDelegates.h>
#include <Misc/ScopeExit.h>
#include <UObject/UnrealType.h>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_groundnav_volume_spawn
{
    constexpr auto kTestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;
    constexpr auto InformEngineOfWorld = false;

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

    auto Make_ValidParams() -> FCk_Fragment_GroundNavVolume_ParamsData
    {
        auto Config = FCk_GroundNav_BakeConfig{25.0f, 10.0f};
        Config.Set_TileSizeUu(400.0f);
        auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};
        auto Params = FCk_Fragment_GroundNavVolume_ParamsData{
            FBox{FVector{-40.0, -20.0, -10.0}, FVector{80.0, 60.0, 30.0}}, Config, Profile};
        Params.Set_ProbeBudgetPerTick(1);
        return Params;
    }

    auto Tick_Construction(UCk_EditorEcsWorld_Subsystem_UE& InSubsystem) -> void
    {
        // EntitySpawner deliberately defers preview construction to the frame boundary. The following ticks are the
        // editor scheduler's ordinary request/EntityScript construction path, not a hand-built ECS fixture.
        FCoreDelegates::OnEndFrame.Broadcast();
        for (auto Index = 0; Index < 4; ++Index)
        { InSubsystem.Tick(1.0f / 60.0f); }
    }

    auto Get_VolumeParams(const FCk_Registry& InRegistry) -> TArray<FCk_Fragment_GroundNavVolume_ParamsData>
    {
        auto Ret = TArray<FCk_Fragment_GroundNavVolume_ParamsData>{};
        InRegistry.View<ck::FFragment_GroundNavVolume_Params>().ForEach(
            [&Ret](const FCk_Entity&, const ck::FFragment_GroundNavVolume_Params& InParams)
            {
                Ret.Add(InParams);
            });
        return Ret;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_VolumeSpawn,
    "Ck.GroundNav.VolumeSpawn.EntitySpawnerPlacementAndValidation",
    ck_test_groundnav_volume_spawn::kTestFlags)

bool FCkTest_GroundNav_VolumeSpawn::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_volume_spawn;

    auto* Settings = GetMutableDefault<UCk_Jolt_ProjectSettings_UE>();
    if (NOT TestNotNull(TEXT("the Jolt settings CDO resolves"), Settings))
    { return false; }

    const auto RestoreMode = Settings->Get_EditorStaticWorldMode();
    ON_SCOPE_EXIT { Settings->TestOnly_Set_EditorStaticWorldMode(RestoreMode); };
    Settings->TestOnly_Set_EditorStaticWorldMode(ECk_Jolt_EditorStaticWorldMode::Disabled);

    auto* World = UWorld::CreateWorld(EWorldType::Editor, InformEngineOfWorld, TEXT("GroundNavVolumeSpawn"));
    if (NOT TestNotNull(TEXT("a hermetic editor world is created"), World))
    { return false; }
    ON_SCOPE_EXIT { World->DestroyWorld(InformEngineOfWorld); };

    auto* EditorSubsystem = World->GetSubsystem<UCk_EditorEcsWorld_Subsystem_UE>();
    if (NOT TestNotNull(TEXT("the editor ECS world subsystem exists"), EditorSubsystem) ||
        NOT TestTrue(TEXT("the editor ECS registry is mutation safe"), EditorSubsystem->Get_IsEditorEcsMutationSafe()))
    { return false; }

    auto* Spawner = World->SpawnActor<ACk_EntitySpawner_UE>();
    if (NOT TestNotNull(TEXT("a volume spawner is created"), Spawner))
    { return false; }

    const auto Placement = FTransform{FQuat::Identity, FVector{1000.0, -500.0, 200.0}, FVector{2.0, 3.0, 4.0}};
    Spawner->SetActorTransform(Placement);
    Spawner->EditorOnly_InitializeEntityScript(UCk_GroundNavVolume_EntityScript::StaticClass());

    auto* Script = Cast<UCk_GroundNavVolume_EntityScript>(Spawner->Get_EntityScript());
    if (NOT TestNotNull(TEXT("the spawner owns a GroundNav volume script"), Script))
    { return false; }

    const auto AuthoredParams = Make_ValidParams();
    if (NOT TestTrue(TEXT("the script accepts authored volume params"), Set_ScriptParams(*Script, AuthoredParams)))
    { return false; }

    Spawner->EditorOnly_RebuildEntity();
    Tick_Construction(*EditorSubsystem);

    const auto SourceLevelPackage = Spawner->GetLevel()->GetOutermost()->GetFName();
    TestTrue(TEXT("the spawner injects its full actor transform into the script"),
        Script->Get_SpawnTransform().Equals(Placement));
    TestEqual(TEXT("the spawner injects its source level package into the script"),
        Script->Get_SpawnLevelPackage(), SourceLevelPackage);

    const auto VolumeParams = Get_VolumeParams(EditorSubsystem->Get_Registry());
    if (NOT TestEqual(TEXT("valid construction composes one GroundNav volume child"), VolumeParams.Num(), 1))
    { return false; }

    const auto ExpectedBounds = AuthoredParams.Get_VolumeBounds().ShiftBy(Placement.GetTranslation());
    TestTrue(TEXT("the composed volume shifts local authored bounds by the spawner translation only"),
        VolumeParams[0].Get_VolumeBounds().Min.Equals(ExpectedBounds.Min) &&
        VolumeParams[0].Get_VolumeBounds().Max.Equals(ExpectedBounds.Max));
    TestEqual(TEXT("the composed volume retains the injected source-level cook package"),
        VolumeParams[0].Get_CookLevelPackage(),
        ck::groundnav::Get_PackageLookupKey(SourceLevelPackage.ToString()));

    auto* InvalidSpawner = World->SpawnActor<ACk_EntitySpawner_UE>();
    if (NOT TestNotNull(TEXT("an invalid volume spawner is created"), InvalidSpawner))
    { return false; }

    InvalidSpawner->EditorOnly_InitializeEntityScript(UCk_GroundNavVolume_EntityScript::StaticClass());
    auto* InvalidScript = Cast<UCk_GroundNavVolume_EntityScript>(InvalidSpawner->Get_EntityScript());
    if (NOT TestNotNull(TEXT("the invalid spawner owns a GroundNav volume script"), InvalidScript))
    { return false; }

    auto InvalidParams = Make_ValidParams();
    InvalidParams.Set_VolumeBounds(FBox{FVector{10.0, 0.0, 0.0}, FVector{0.0, 10.0, 10.0}});
    if (NOT TestTrue(TEXT("the invalid script accepts the malformed authored data for construction validation"),
        Set_ScriptParams(*InvalidScript, InvalidParams)))
    { return false; }

    AddExpectedError(TEXT("GroundNavVolume EntityScript requires valid bounds, bake settings, volume identity and unique profiles."),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);
    InvalidSpawner->EditorOnly_RebuildEntity();
    Tick_Construction(*EditorSubsystem);

    TestEqual(TEXT("invalid construction adds no partial GroundNav volume child"),
        Get_VolumeParams(EditorSubsystem->Get_Registry()).Num(), 1);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
