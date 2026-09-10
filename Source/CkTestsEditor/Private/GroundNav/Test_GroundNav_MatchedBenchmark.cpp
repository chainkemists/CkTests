#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Editor.h"
#include "Editor/UnrealEdEngine.h"
#include "FileHelpers.h"
#include "Engine/Engine.h"
#include "Engine/StaticMesh.h"
#include "Engine/StaticMeshActor.h"
#include "EngineUtils.h"
#include "GameFramework/WorldSettings.h"
#include "AI/NavigationSystemConfig.h"
#include "Builders/CubeBuilder.h"
#include "ActorFactories/ActorFactory.h"
#include "Misc/PackageName.h"
#include "Engine/World.h"
#include "NavigationSystem.h"
#include "NavMesh/NavMeshBoundsVolume.h"
#include "NavMesh/RecastNavMesh.h"
#include "PlayInEditorDataTypes.h"
#include "Settings/LevelEditorPlaySettings.h"
#include "HAL/PlatformTime.h"
#include "UObject/Package.h"
#include "UObject/UnrealType.h"

#include "CkCore/Validation/CkIsValid.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"
#include "CkTests/GroundNav/CkGroundNav_BenchmarkNavigationConfig.h"
#include "CkTests/GroundNav/CkGroundNav_MatchedBenchmarkActor.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

// The benchmark intentionally owns one small, authored map rather than borrowing AutoTests or a gym.
// Its mesh tags are also the runtime actor's Jolt-bake selection contract.
namespace ck_groundnav_matched_benchmark
{
    constexpr TCHAR kMapPath[] = TEXT("/CkTests/GroundNavBenchmark/Maps/GroundNavMatchedBenchmark");
    constexpr TCHAR kHarnessTag[] = TEXT("CkTests.GroundNavBenchmark.Harness");
    constexpr TCHAR kFloorTag[] = TEXT("CkTests.GroundNavBenchmark.Floor");
    constexpr TCHAR kPillarTags[][40] = {
        TEXT("CkTests.GroundNavBenchmark.Pillar0"),
        TEXT("CkTests.GroundNavBenchmark.Pillar1"),
        TEXT("CkTests.GroundNavBenchmark.Pillar2"),
        TEXT("CkTests.GroundNavBenchmark.Pillar3")};

    constexpr float kAgentRadiusUu = 42.0f;
    constexpr float kAgentHeightUu = 192.0f;
    constexpr float kRecastCellHeightUu = 1.0f;
    constexpr float kToleranceUu = 0.01f;
    const FVector kPillarCentres[] = {
        FVector{-350.0f, -350.0f, 150.0f}, FVector{-350.0f, 350.0f, 150.0f},
        FVector{350.0f, -350.0f, 150.0f}, FVector{350.0f, 350.0f, 150.0f}};

    auto ProviderName(const ECk_NavSurface_Provider InProvider) -> const TCHAR*
    { return InProvider == ECk_NavSurface_Provider::GroundNav ? TEXT("GroundNav") : TEXT("Recast"); }

    auto ModeName(const ECk_GroundNav_BenchmarkMode InMode) -> const TCHAR*
    { return InMode == ECk_GroundNav_BenchmarkMode::CrowdConvergence240 ? TEXT("CrowdConvergence240") : TEXT("QueryBurst128"); }

    auto SetRecastGenerationDimension(ARecastNavMesh& InRecast, const FName InName, const float InValue) -> bool
    {
        auto* Property = FindFProperty<FFloatProperty>(InRecast.GetClass(), InName);
        if (Property == nullptr)
        { return false; }
        Property->SetPropertyValue_InContainer(&InRecast, InValue);
        return true;
    }

    auto GetRecastGenerationDimension(const ARecastNavMesh& InRecast, const FName InName, float& OutValue) -> bool
    {
        auto* Property = FindFProperty<FFloatProperty>(InRecast.GetClass(), InName);
        if (Property == nullptr)
        { return false; }
        OutValue = Property->GetPropertyValue_InContainer(&InRecast);
        return true;
    }

    auto SetRecastGenerationCellHeight(ARecastNavMesh& InRecast, const float InValue) -> bool
    {
        auto* Property = FindFProperty<FStructProperty>(InRecast.GetClass(), TEXT("NavMeshResolutionParams"));
        if (Property == nullptr || Property->Struct != FNavMeshResolutionParam::StaticStruct() || Property->ArrayDim == 0)
        { return false; }
        for (int32 Index = 0; Index < Property->ArrayDim; ++Index)
        { Property->ContainerPtrToValuePtr<FNavMeshResolutionParam>(&InRecast, Index)->CellHeight = InValue; }
        return true;
    }

    auto HasRecastGenerationCellHeight(const ARecastNavMesh& InRecast, const float InValue) -> bool
    {
        auto* Property = FindFProperty<FStructProperty>(InRecast.GetClass(), TEXT("NavMeshResolutionParams"));
        if (Property == nullptr || Property->Struct != FNavMeshResolutionParam::StaticStruct() || Property->ArrayDim == 0)
        { return false; }
        for (int32 Index = 0; Index < Property->ArrayDim; ++Index)
        {
            if (!FMath::IsNearlyEqual(Property->ContainerPtrToValuePtr<FNavMeshResolutionParam>(&InRecast, Index)->CellHeight, InValue, kToleranceUu))
            { return false; }
        }
        return true;
    }

    auto SetWorldNavigationConfig(AWorldSettings& InWorldSettings, UNavigationSystemConfig& InConfig) -> bool
    {
        auto* Property = FindFProperty<FObjectProperty>(InWorldSettings.GetClass(), TEXT("NavigationSystemConfig"));
        if (Property == nullptr || !Property->PropertyClass->IsChildOf(UNavigationSystemConfig::StaticClass()))
        { return false; }
        Property->SetObjectPropertyValue_InContainer(&InWorldSettings, &InConfig);
        return true;
    }

    auto ValidateFixtureNavigationConfig(FAutomationTestBase& InTest, UWorld& InWorld) -> bool
    {
        auto* WorldSettings = InWorld.GetWorldSettings();
        auto* Config = WorldSettings != nullptr
            ? Cast<UCk_GroundNav_BenchmarkNavigationConfig>(WorldSettings->GetNavigationSystemConfig())
            : nullptr;
        auto Passed = InTest.TestNotNull(TEXT("the benchmark WorldSettings persist its fixture navigation config"), Config);
        auto* NavigationSystem = FNavigationSystem::GetCurrent<UNavigationSystemV1>(&InWorld);
        Passed &= InTest.TestNotNull(TEXT("the benchmark world has its fixture navigation system"), NavigationSystem);
        if (NavigationSystem != nullptr)
        {
            const auto& SupportedAgents = NavigationSystem->GetSupportedAgents();
            Passed &= InTest.TestEqual(TEXT("the fixture navigation system has exactly one supported agent"), SupportedAgents.Num(), 1);
            if (SupportedAgents.Num() == 1)
            {
                const auto& Agent = SupportedAgents[0];
                Passed &= InTest.TestEqual(TEXT("the fixture supported-agent name is Default"), Agent.Name, FName{TEXT("Default")});
                Passed &= InTest.TestEqual(TEXT("the fixture supported-agent radius is 42"), Agent.AgentRadius, kAgentRadiusUu);
                Passed &= InTest.TestEqual(TEXT("the fixture supported-agent height is 192"), Agent.AgentHeight, kAgentHeightUu);
                Passed &= InTest.TestTrue(TEXT("the fixture supported-agent uses Recast"),
                    Agent.GetNavDataClass<ANavigationData>().Get() == ARecastNavMesh::StaticClass());
            }
        }
        return Passed;
    }

    struct FStandalonePlaySettings
    {
        int32 _NumClients = 1;
        EPlayNetMode _NetMode = EPlayNetMode::PIE_Standalone;
        bool _LaunchSeparateServer = false;
    };
    TOptional<FStandalonePlaySettings> GStandalonePlaySettings;

    auto RestoreStandalonePlaySettings() -> void
    {
        if (!GStandalonePlaySettings.IsSet())
        { return; }
        if (auto* Settings = GetMutableDefault<ULevelEditorPlaySettings>())
        {
            Settings->SetPlayNumberOfClients(GStandalonePlaySettings->_NumClients);
            Settings->SetPlayNetMode(GStandalonePlaySettings->_NetMode);
            Settings->bLaunchSeparateServer = GStandalonePlaySettings->_LaunchSeparateServer;
        }
        GStandalonePlaySettings.Reset();
    }

    auto GetStandalonePIEWorld() -> UWorld*
    {
        if (GEngine == nullptr)
        { return nullptr; }
        for (const auto& Context : GEngine->GetWorldContexts())
        {
            if (Context.WorldType == EWorldType::PIE && Context.World() != nullptr)
            { return Context.World(); }
        }
        return nullptr;
    }

    auto FindTaggedActor(UWorld& InWorld, const FName InTag) -> AActor*
    {
        AActor* Found = nullptr;
        for (TActorIterator<AActor> It{&InWorld}; It; ++It)
        {
            if (It->ActorHasTag(InTag))
            {
                if (Found != nullptr)
                { return nullptr; } // Duplicate fixture ownership is invalid, never pick an arbitrary actor.
                Found = *It;
            }
        }
        return Found;
    }

    auto ValidateStaticMeshActor(
        FAutomationTestBase& InTest,
        UWorld& InWorld,
        const FName InTag,
        const FVector& InLocation,
        const FVector& InScale) -> bool
    {
        auto* Actor = Cast<AStaticMeshActor>(FindTaggedActor(InWorld, InTag));
        auto Passed = InTest.TestNotNull(*FString::Printf(TEXT("fixture actor tagged %s exists exactly once"), *InTag.ToString()), Actor);
        if (Actor == nullptr)
        { return false; }

        Passed &= InTest.TestTrue(*FString::Printf(TEXT("fixture actor %s is static"), *InTag.ToString()),
            Actor->GetStaticMeshComponent()->Mobility == EComponentMobility::Static);
        Passed &= InTest.TestTrue(*FString::Printf(TEXT("fixture actor %s blocks navigation collision"), *InTag.ToString()),
            Actor->GetStaticMeshComponent()->GetCollisionProfileName() == TEXT("BlockAll"));
        Passed &= InTest.TestTrue(*FString::Printf(TEXT("fixture actor %s is nav relevant"), *InTag.ToString()),
            Actor->GetStaticMeshComponent()->CanEverAffectNavigation());
        Passed &= InTest.TestTrue(*FString::Printf(TEXT("fixture actor %s has zero rotation"), *InTag.ToString()),
            Actor->GetActorRotation().IsNearlyZero(kToleranceUu));
        Passed &= InTest.TestTrue(*FString::Printf(TEXT("fixture actor %s location is pinned"), *InTag.ToString()),
            Actor->GetActorLocation().Equals(InLocation, kToleranceUu));
        Passed &= InTest.TestTrue(*FString::Printf(TEXT("fixture actor %s scale is pinned"), *InTag.ToString()),
            Actor->GetActorScale3D().Equals(InScale, kToleranceUu));
        return Passed;
    }

    auto ValidateMap(FAutomationTestBase& InTest, UWorld& InWorld, UStaticMesh& InCube) -> bool
    {
        auto Passed = ValidateFixtureNavigationConfig(InTest, InWorld);
        Passed &= ValidateStaticMeshActor(InTest, InWorld, FName{kFloorTag}, FVector{0.0f, 0.0f, -50.0f}, FVector{36.0f, 24.0f, 1.0f});
        for (auto Index = 0; Index < UE_ARRAY_COUNT(kPillarCentres); ++Index)
        {
            Passed &= ValidateStaticMeshActor(InTest, InWorld, FName{kPillarTags[Index]}, kPillarCentres[Index], FVector{1.5f, 1.5f, 3.0f});
        }

        auto ExpectedGeometryTags = TSet<FName>{FName{kFloorTag}};
        for (const auto& Tag : kPillarTags)
        { ExpectedGeometryTags.Add(FName{Tag}); }
        auto NavRelevantMeshCount = 0;
        for (TActorIterator<AStaticMeshActor> It{&InWorld}; It; ++It)
        {
            const auto* Mesh = It->GetStaticMeshComponent();
            if (Mesh == nullptr || Mesh->GetCollisionEnabled() == ECollisionEnabled::NoCollision || !Mesh->CanEverAffectNavigation())
            { continue; }
            ++NavRelevantMeshCount;
            Passed &= InTest.TestTrue(TEXT("no extra collision geometry contaminates the benchmark"),
                It->Tags.ContainsByPredicate([&ExpectedGeometryTags](const FName Tag) { return ExpectedGeometryTags.Contains(Tag); }));
            Passed &= InTest.TestTrue(TEXT("benchmark geometry uses the engine cube identity"), Mesh->GetStaticMesh() == &InCube);
        }
        Passed &= InTest.TestEqual(TEXT("the benchmark has exactly its floor and four pillars as nav geometry"), NavRelevantMeshCount, 5);

        auto* Harness = Cast<ACk_GroundNav_MatchedBenchmarkActor>(FindTaggedActor(InWorld, FName{kHarnessTag}));
        Passed &= InTest.TestNotNull(TEXT("the unique benchmark harness actor exists"), Harness);

        auto* NavBounds = static_cast<ANavMeshBoundsVolume*>(nullptr);
        for (TActorIterator<ANavMeshBoundsVolume> It{&InWorld}; It; ++It)
        {
            if (It->GetActorLabel() == TEXT("GroundNavMatchedBenchmark_NavBounds"))
            {
                if (NavBounds != nullptr)
                { NavBounds = nullptr; break; }
                NavBounds = *It;
            }
        }
        Passed &= InTest.TestNotNull(TEXT("the benchmark has its own Recast navigation bounds"), NavBounds);
        if (NavBounds != nullptr)
        {
            const auto NavBoundsBox = NavBounds->GetComponentsBoundingBox(/*bNonColliding=*/true);
            Passed &= InTest.TestTrue(TEXT("the authored NavMeshBounds brush covers the floor and agent height"),
                NavBoundsBox.IsValid && NavBoundsBox.IsInsideOrOn(FVector{-3600.0f, -2400.0f, -100.0f}) &&
                NavBoundsBox.IsInsideOrOn(FVector{3600.0f, 2400.0f, 500.0f}));
        }

        auto* NavigationSystem = FNavigationSystem::GetCurrent<UNavigationSystemV1>(&InWorld);
        auto* Recast = NavigationSystem != nullptr
            ? Cast<ARecastNavMesh>(NavigationSystem->GetDefaultNavDataInstance(FNavigationSystem::DontCreate))
            : nullptr;
        Passed &= InTest.TestNotNull(TEXT("the benchmark map has Recast navigation data"), Recast);
        if (Recast != nullptr)
        {
            auto GenerationRadius = 0.0f;
            auto GenerationHeight = 0.0f;
            Passed &= InTest.TestTrue(TEXT("Recast exposes its generation radius"),
                GetRecastGenerationDimension(*Recast, TEXT("AgentRadius"), GenerationRadius));
            Passed &= InTest.TestTrue(TEXT("Recast exposes its generation height"),
                GetRecastGenerationDimension(*Recast, TEXT("AgentHeight"), GenerationHeight));
            Passed &= InTest.TestEqual(TEXT("Recast generation radius matches the benchmark agent"), GenerationRadius, kAgentRadiusUu);
            Passed &= InTest.TestEqual(TEXT("Recast generation height matches the benchmark agent"), GenerationHeight, kAgentHeightUu);
            Passed &= InTest.TestTrue(TEXT("all Recast generation resolutions use the fixture cell height"),
                HasRecastGenerationCellHeight(*Recast, kRecastCellHeightUu));
            Passed &= InTest.TestEqual(TEXT("Recast config radius matches the benchmark agent"), Recast->GetConfig().AgentRadius, kAgentRadiusUu);
            Passed &= InTest.TestEqual(TEXT("Recast config height matches the benchmark agent"), Recast->GetConfig().AgentHeight, kAgentHeightUu);
        }
        return Passed;
    }

    auto SpawnCube(UWorld& InWorld, UStaticMesh& InCube, const FName InTag, const FVector& InLocation, const FVector& InScale) -> AStaticMeshActor*
    {
        auto SpawnParams = FActorSpawnParameters{};
        SpawnParams.Name = MakeUniqueObjectName(&InWorld, AStaticMeshActor::StaticClass(), InTag);
        auto* Actor = InWorld.SpawnActor<AStaticMeshActor>(InLocation, FRotator::ZeroRotator, SpawnParams);
        if (Actor == nullptr)
        { return nullptr; }

        Actor->Tags.Add(InTag);
        Actor->SetActorLabel(InTag.ToString());
        Actor->SetActorScale3D(InScale);
        auto* Mesh = Actor->GetStaticMeshComponent();
        Mesh->SetStaticMesh(&InCube);
        Mesh->SetMobility(EComponentMobility::Static);
        Mesh->SetCollisionProfileName(TEXT("BlockAll"));
        Actor->MarkPackageDirty();
        return Actor;
    }

    auto CreateMap(FAutomationTestBase& InTest) -> bool
    {
        auto* World = UEditorLoadingAndSavingUtils::NewBlankMap(/*bSaveExistingMap=*/false);
        if (World == nullptr)
        { return InTest.AddError(TEXT("blank-map creation returned no editor world")), false; }

        auto* Cube = LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Cube.Cube"));
        if (Cube == nullptr)
        { return InTest.AddError(TEXT("could not load the engine cube used by the benchmark fixture")), false; }

        auto* WorldSettings = World->GetWorldSettings();
        if (WorldSettings == nullptr || !UCk_GroundNav_BenchmarkNavigationConfig::IsSupportedAgentsPropertyCompatible(*UNavigationSystemV1::StaticClass()))
        { return InTest.AddError(TEXT("the benchmark cannot install its fixture-local supported navigation agent")), false; }
        auto* FixtureNavigationConfig = NewObject<UCk_GroundNav_BenchmarkNavigationConfig>(WorldSettings, TEXT("GroundNavMatchedBenchmark_NavigationConfig"));
        auto* FixtureNavigationSystemClass = FixtureNavigationConfig != nullptr
            ? FixtureNavigationConfig->NavigationSystemClass.TryLoadClass<UNavigationSystemBase>()
            : nullptr;
        if (FixtureNavigationConfig == nullptr || FixtureNavigationSystemClass == nullptr ||
            !UCk_GroundNav_BenchmarkNavigationConfig::IsSupportedAgentsPropertyCompatible(*FixtureNavigationSystemClass) ||
            !SetWorldNavigationConfig(*WorldSettings, *FixtureNavigationConfig))
        { return InTest.AddError(TEXT("could not persist the benchmark WorldSettings navigation config")), false; }
        WorldSettings->MarkPackageDirty();
        FNavigationSystem::AddNavigationSystemToWorld(*World, FNavigationSystemRunMode::EditorMode, FixtureNavigationConfig,
            /*bInitializeForWorld=*/true, /*bOverridePreviousNavSys=*/true);
        if (FNavigationSystem::GetCurrent<UNavigationSystemV1>(World) == nullptr)
        { return InTest.AddError(TEXT("fixture-local navigation-system initialization failed without a fallback")), false; }
        if (!ValidateFixtureNavigationConfig(InTest, *World))
        { return false; }

        auto Created = SpawnCube(*World, *Cube, FName{kFloorTag}, FVector{0.0f, 0.0f, -50.0f}, FVector{36.0f, 24.0f, 1.0f}) != nullptr;
        for (auto Index = 0; Index < UE_ARRAY_COUNT(kPillarCentres); ++Index)
        { Created &= SpawnCube(*World, *Cube, FName{kPillarTags[Index]}, kPillarCentres[Index], FVector{1.5f, 1.5f, 3.0f}) != nullptr; }

        auto* NavBounds = World->SpawnActor<ANavMeshBoundsVolume>(FVector::ZeroVector, FRotator::ZeroRotator);
        if (NavBounds != nullptr)
        {
            NavBounds->SetActorLabel(TEXT("GroundNavMatchedBenchmark_NavBounds"));
            auto* Builder = NewObject<UCubeBuilder>();
            Builder->X = 8000.0f;
            Builder->Y = 5600.0f;
            Builder->Z = 1200.0f;
            // A raw volume has no UModel. Builder::Build alone returns true without creating it.
            UActorFactory::CreateBrushForVolumeActor(NavBounds, Builder);
            Created &= NavBounds->Brush != nullptr;
            NavBounds->MarkPackageDirty();
        }
        Created &= NavBounds != nullptr;

        auto* Harness = World->SpawnActor<ACk_GroundNav_MatchedBenchmarkActor>(FVector::ZeroVector, FRotator::ZeroRotator);
        if (Harness != nullptr)
        {
            Harness->Tags.Add(FName{kHarnessTag});
            Harness->SetActorLabel(TEXT("GroundNavMatchedBenchmark_Harness"));
            Harness->MarkPackageDirty();
        }
        Created &= Harness != nullptr;
        if (!Created)
        { return InTest.AddError(TEXT("could not author every matched benchmark fixture actor")), false; }

        auto* NavigationSystem = FNavigationSystem::GetCurrent<UNavigationSystemV1>(World);
        auto* Recast = NavigationSystem != nullptr
            ? Cast<ARecastNavMesh>(NavigationSystem->GetDefaultNavDataInstance(FNavigationSystem::Create))
            : nullptr;
        if (Recast == nullptr)
        { return InTest.AddError(TEXT("new map did not create its Recast navigation data")), false; }

        if (!SetRecastGenerationDimension(*Recast, TEXT("AgentRadius"), kAgentRadiusUu) ||
            !SetRecastGenerationDimension(*Recast, TEXT("AgentHeight"), kAgentHeightUu) ||
            !SetRecastGenerationCellHeight(*Recast, kRecastCellHeightUu))
        { return InTest.AddError(TEXT("Recast did not expose the fixture generation dimensions")), false; }
        auto Config = Recast->GetConfig();
        Config.AgentRadius = kAgentRadiusUu;
        Config.AgentHeight = kAgentHeightUu;
        Recast->SetConfig(Config);
        Recast->MarkPackageDirty();
        NavigationSystem->Build();
        Recast->EnsureBuildCompletion();
        const auto NavBoundsBox = NavBounds->GetComponentsBoundingBox(/*bNonColliding=*/true);
        UE_LOG(LogTemp, Display, TEXT("[NAV-BENCHMARK-FIXTURE] Authored bounds %s"), *NavBoundsBox.ToString());
        if (!NavBoundsBox.IsValid || !NavBoundsBox.IsInsideOrOn(FVector{-3600.0f, -2400.0f, -100.0f}) ||
            !NavBoundsBox.IsInsideOrOn(FVector{3600.0f, 2400.0f, 500.0f}))
        { return InTest.AddError(TEXT("authored NavMeshBounds brush does not cover the benchmark floor and agent height")), false; }
        if (!ValidateMap(InTest, *World, *Cube))
        { return false; }
        if (!UEditorLoadingAndSavingUtils::SaveMap(World, kMapPath))
        { return InTest.AddError(TEXT("could not save the benchmark map after its Recast build")), false; }
        return true;
    }

    auto EnsureMap(FAutomationTestBase& InTest) -> bool
    {
        if (auto* ExistingWorld = GEditor != nullptr ? GEditor->GetEditorWorldContext().World() : nullptr;
            ExistingWorld != nullptr && ExistingWorld->GetOutermost()->IsDirty())
        { return InTest.AddError(TEXT("refusing to replace a dirty editor map while checking the benchmark fixture")), false; }
        if (!FPackageName::DoesPackageExist(kMapPath))
        { return CreateMap(InTest); }

        if (!FEditorFileUtils::LoadMap(kMapPath, /*bLoadAsTemplate=*/false, /*bShowProgress=*/false))
        { return InTest.AddError(TEXT("could not load the existing matched benchmark map")), false; }
        auto* World = GEditor != nullptr ? GEditor->GetEditorWorldContext().World() : nullptr;
        auto* Cube = LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Cube.Cube"));
        return World != nullptr && Cube != nullptr && ValidateMap(InTest, *World, *Cube);
    }

    class FStartStandalonePIE final : public IAutomationLatentCommand
    {
    public:
        explicit FStartStandalonePIE(FAutomationTestBase* InTest) : _Test(InTest) {}

        virtual bool Update() override
        {
            if (GUnrealEd == nullptr)
            { _Test->AddError(TEXT("cannot start standalone PIE: GUnrealEd is null")); return true; }
            auto* Settings = GetMutableDefault<ULevelEditorPlaySettings>();
            if (Settings == nullptr)
            { _Test->AddError(TEXT("cannot start standalone PIE: play settings are unavailable")); return true; }
            auto Snapshot = FStandalonePlaySettings{};
            Settings->GetPlayNumberOfClients(Snapshot._NumClients);
            Settings->GetPlayNetMode(Snapshot._NetMode);
            Snapshot._LaunchSeparateServer = Settings->bLaunchSeparateServer;
            GStandalonePlaySettings = Snapshot;
            Settings->SetPlayNumberOfClients(1);
            Settings->SetPlayNetMode(EPlayNetMode::PIE_Standalone);
            Settings->bLaunchSeparateServer = false;
            auto Params = FRequestPlaySessionParams{};
            Params.WorldType = EPlaySessionWorldType::PlayInEditor;
            GUnrealEd->RequestPlaySession(Params);
            return true;
        }

    private:
        FAutomationTestBase* _Test = nullptr;
    };

    class FRunBenchmark final : public IAutomationLatentCommand
    {
    public:
        FRunBenchmark(FAutomationTestBase* InTest, const ECk_NavSurface_Provider InProvider, const ECk_GroundNav_BenchmarkMode InMode)
            : _Test(InTest), _Provider(InProvider), _Mode(InMode), _DeadlineSeconds(FPlatformTime::Seconds() + 100.0) {}

        virtual bool Update() override
        {
            if (FPlatformTime::Seconds() > _DeadlineSeconds)
            { _Test->AddError(TEXT("timed out after 100 seconds waiting for the matched benchmark harness terminal result")); return true; }
            if (_Test->HasAnyErrors())
            { return true; }
            auto* World = GetStandalonePIEWorld();
            if (World == nullptr)
            { return false; }
            if (!_Started)
            {
                auto* Harness = Cast<ACk_GroundNav_MatchedBenchmarkActor>(FindTaggedActor(*World, FName{kHarnessTag}));
                if (Harness == nullptr)
                { _Test->AddError(TEXT("PIE benchmark map has no unique tagged harness actor")); return true; }
                auto* Cube = LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Cube.Cube"));
                if (Cube == nullptr || !ValidateMap(*_Test, *World, *Cube))
                { return true; }
                if (Harness->Request_Run(static_cast<ECk_NavSurface_Provider>(255), _Mode))
                { _Test->AddError(TEXT("benchmark harness accepted an invalid navigation-provider enum")); return true; }
                if (Harness->Request_Run(_Provider, static_cast<ECk_GroundNav_BenchmarkMode>(255)))
                { _Test->AddError(TEXT("benchmark harness accepted an invalid benchmark-mode enum")); return true; }
                if (!Harness->Request_Run(_Provider, _Mode))
                { _Test->AddError(TEXT("benchmark harness refused its first request")); return true; }
                if (Harness->Request_Run(_Provider, _Mode))
                { _Test->AddError(TEXT("benchmark harness accepted a reentrant request while the original run was live")); return true; }
                _Harness = Harness;
                _Started = true;
                _DeadlineSeconds = FPlatformTime::Seconds() + 100.0;
            }
            if (!_Harness.IsValid())
            { _Test->AddError(TEXT("matched benchmark harness disappeared before its terminal result")); return true; }
            if (!_Harness->Get_IsFinished())
            { return false; }
            if (!_Harness->Get_DidPass())
            { _Test->AddError(FString::Printf(TEXT("benchmark harness failed: %s"), *_Harness->Get_Report())); }
            else if (_Harness->Get_Report().IsEmpty())
            { _Test->AddError(TEXT("benchmark harness passed without a JSON report")); }
            else
            {
                const FString& Report = _Harness->Get_Report();
                _Test->TestTrue(TEXT("benchmark report identifies the requested provider"),
                    Report.Contains(FString::Printf(TEXT("\"provider\":\"%s\""), ProviderName(_Provider))));
                _Test->TestTrue(TEXT("benchmark report identifies the requested mode"),
                    Report.Contains(FString::Printf(TEXT("\"mode\":\"%s\""), ModeName(_Mode))));
            }
            return true;
        }

    private:
        FAutomationTestBase* _Test = nullptr;
        ECk_NavSurface_Provider _Provider;
        ECk_GroundNav_BenchmarkMode _Mode;
        bool _Started = false;
        double _DeadlineSeconds = 0.0;
        TWeakObjectPtr<ACk_GroundNav_MatchedBenchmarkActor> _Harness;
    };

    class FEndStandalonePIE final : public IAutomationLatentCommand
    {
    public:
        explicit FEndStandalonePIE(FAutomationTestBase* InTest)
            : _Test(InTest), _DeadlineSeconds(FPlatformTime::Seconds() + 30.0) {}

        virtual bool Update() override
        {
            if (!_Requested && GUnrealEd != nullptr)
            {
                GUnrealEd->RequestEndPlayMap();
                _Requested = true;
                return false;
            }
            if (GetStandalonePIEWorld() != nullptr)
            {
                if (FPlatformTime::Seconds() <= _DeadlineSeconds)
                { return false; }
                _Test->AddError(TEXT("standalone PIE did not end within 30 seconds; restoring play settings"));
            }
            RestoreStandalonePlaySettings();
            return true;
        }

    private:
        FAutomationTestBase* _Test = nullptr;
        bool _Requested = false;
        double _DeadlineSeconds = 0.0;
    };

    auto EnqueueBenchmark(FAutomationTestBase& InTest, const ECk_NavSurface_Provider InProvider, const ECk_GroundNav_BenchmarkMode InMode) -> void
    {
        ADD_LATENT_AUTOMATION_COMMAND(FStartStandalonePIE(&InTest));
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(&InTest,
            FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
            {
                auto* World = GetStandalonePIEWorld();
                return World != nullptr && ck::IsValid(UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(World));
            }), 30.0, TEXT("the default map GameMode supports the Ck ECS transient entity")));
        ADD_LATENT_AUTOMATION_COMMAND(FRunBenchmark(&InTest, InProvider, InMode));
        ADD_LATENT_AUTOMATION_COMMAND(FEndStandalonePIE(&InTest));
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkGroundNavMatchedBenchmark_MapContract,
    "Ck.GroundNav.Benchmark.MapContract", EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkGroundNavMatchedBenchmark_MapContract::RunTest(const FString& Parameters)
{
    return ck_groundnav_matched_benchmark::EnsureMap(*this);
}

#define CK_GROUNDNAV_MATCHED_BENCHMARK_TEST(Name, TestName, Provider, Mode) \
IMPLEMENT_SIMPLE_AUTOMATION_TEST(Name, TestName, \
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter) \
bool Name::RunTest(const FString& Parameters) \
{ \
    if (!ck_groundnav_matched_benchmark::EnsureMap(*this)) { return false; } \
    ck_groundnav_matched_benchmark::EnqueueBenchmark(*this, ECk_NavSurface_Provider::Provider, ECk_GroundNav_BenchmarkMode::Mode); \
    return true; \
}

CK_GROUNDNAV_MATCHED_BENCHMARK_TEST(FCkGroundNavMatchedBenchmark_QueryBurst128_Recast,
    TEXT("Ck.GroundNav.Benchmark.QueryBurst128.Recast"), Recast, QueryBurst128)
CK_GROUNDNAV_MATCHED_BENCHMARK_TEST(FCkGroundNavMatchedBenchmark_QueryBurst128_GroundNav,
    TEXT("Ck.GroundNav.Benchmark.QueryBurst128.GroundNav"), GroundNav, QueryBurst128)
CK_GROUNDNAV_MATCHED_BENCHMARK_TEST(FCkGroundNavMatchedBenchmark_CrowdConvergence240_Recast,
    TEXT("Ck.GroundNav.Benchmark.CrowdConvergence240.Recast"), Recast, CrowdConvergence240)
CK_GROUNDNAV_MATCHED_BENCHMARK_TEST(FCkGroundNavMatchedBenchmark_CrowdConvergence240_GroundNav,
    TEXT("Ck.GroundNav.Benchmark.CrowdConvergence240.GroundNav"), GroundNav, CrowdConvergence240)

#undef CK_GROUNDNAV_MATCHED_BENCHMARK_TEST

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
