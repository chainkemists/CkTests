#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "HAL/PlatformTime.h"

#include "Engine/World.h"

#include "CkCore/Enums/CkEnums.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Net/CkNet_Utils.h"

#include "CkGrid/2dGridSystem/Grid/Ck2dGridSystem_Utils.h"
#include "CkGrid/2dGridSystem/Occupancy/Ck2dGridOccupancy_Utils.h"
#include "CkGrid/2dGridSystem/Placement/Ck2dGridPlacement_Fragment.h"

#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------
//
// Exercises the public 2d-grid occupancy lifecycle through a real PIE scheduler. The assertions observe cell
// occupancy and placement identity only; they deliberately do not inspect the processor's private stamped/scratch
// maps. The benchmark below is a separate same-input map microbenchmark, not a frame-time claim.
//
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_grid_occupancy_scratch
{
    constexpr auto TestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;
    constexpr auto EntryMapPath = TEXT("/Engine/Maps/Entry");
    constexpr auto ReadyTimeoutSeconds = 30.0;
    constexpr auto DesiredCellsScratchMaxBytes = 256 * 1024;

    struct FPlacementInput
    {
        FCk_Handle_2dGridPlacement _Placement;
        const TArray<FIntPoint>* _Cells = nullptr;
    };

    struct FMapBenchmarkResult
    {
        double _Milliseconds = 0.0;
        int32 _FinalCellCount = 0;
    };

    struct FScenario
    {
        FCk_Handle _Owner;
        FCk_Handle_2dGridSystem _GridA;
        FCk_Handle_2dGridSystem _GridB;
        FCk_Handle _InitialOccupant;
        FCk_Handle _AlternateGridOccupant;
        FCk_Handle _ReplacementOccupant;
        FCk_Handle _LargeOccupant;
        FCk_Handle _SmallOccupant;
        FCk_Handle_2dGridPlacement _InitialPlacement;
        FCk_Handle_2dGridPlacement _AlternateGridPlacement;
        FCk_Handle_2dGridPlacement _ReplacementPlacement;
        FCk_Handle_2dGridPlacement _LargePlacement;
        FCk_Handle_2dGridPlacement _SmallPlacement;
        TArray<FIntPoint> _LargeCells;
    };

    auto
        MakeGridParams(
            const FIntPoint& InDimensions) -> FCk_Fragment_2dGridSystem_ParamsData
    {
        return FCk_Fragment_2dGridSystem_ParamsData{InDimensions, FVector2D{100.0f, 100.0f}};
    }

    auto
        MakeAuthorityNetSettings() -> FCk_Net_ConnectionSettings
    {
        return FCk_Net_ConnectionSettings{
            ECk_Replication::DoesNotReplicate,
            ECk_Net_NetModeType::ClientAndHost,
            ECk_Net_EntityNetRole::Authority};
    }

    auto
        Get_AllGridCoordinates(
            const FIntPoint& InDimensions) -> TArray<FIntPoint>
    {
        auto Coordinates = TArray<FIntPoint>{};
        Coordinates.Reserve(InDimensions.X * InDimensions.Y);

        for (auto Y = 0; Y < InDimensions.Y; ++Y)
        {
            for (auto X = 0; X < InDimensions.X; ++X)
            { Coordinates.Add(FIntPoint{X, Y}); }
        }

        return Coordinates;
    }

    auto
        Run_FreshMapMoveBenchmark(
            const TArray<FPlacementInput>& InInputs,
            int32 InIterations) -> FMapBenchmarkResult
    {
        auto Result = FMapBenchmarkResult{};
        auto Stamped = TMap<FIntPoint, FCk_Handle_2dGridPlacement>{};
        auto Sink = int32{0};

        {
            auto Desired = TMap<FIntPoint, FCk_Handle_2dGridPlacement>{};
            for (const auto& Input : InInputs)
            {
                for (const auto& Coordinate : *Input._Cells)
                { Desired.Add(Coordinate, Input._Placement); }
            }
            Stamped = MoveTemp(Desired);
        }

        const auto StartSeconds = FPlatformTime::Seconds();
        for (auto Iteration = 0; Iteration < InIterations; ++Iteration)
        {
            auto Desired = TMap<FIntPoint, FCk_Handle_2dGridPlacement>{};
            for (const auto& Input : InInputs)
            {
                for (const auto& Coordinate : *Input._Cells)
                { Desired.Add(Coordinate, Input._Placement); }
            }

            Stamped = MoveTemp(Desired);
            Sink += Stamped.Num();
            Sink += Stamped.Contains(FIntPoint{0, 0}) ? 1 : 0;
            Result._FinalCellCount = Stamped.Num();
        }
        Result._Milliseconds = (FPlatformTime::Seconds() - StartSeconds) * 1000.0;

        volatile auto ObservableSink = Sink;
        (void)ObservableSink;
        return Result;
    }

    auto
        Run_RetainedSwapResetBenchmark(
            const TArray<FPlacementInput>& InInputs,
            int32 InIterations) -> FMapBenchmarkResult
    {
        auto Result = FMapBenchmarkResult{};
        auto Stamped = TMap<FIntPoint, FCk_Handle_2dGridPlacement>{};
        auto Scratch = TMap<FIntPoint, FCk_Handle_2dGridPlacement>{};
        auto Sink = int32{0};

        {
            auto Desired = MoveTemp(Scratch);
            for (const auto& Input : InInputs)
            {
                for (const auto& Coordinate : *Input._Cells)
                { Desired.Add(Coordinate, Input._Placement); }
            }
            Swap(Stamped, Desired);

            if (Desired.GetAllocatedSize() > DesiredCellsScratchMaxBytes)
            { Desired.Empty(); }
            else
            { Desired.Reset(); }

            Scratch = MoveTemp(Desired);
        }

        const auto StartSeconds = FPlatformTime::Seconds();
        for (auto Iteration = 0; Iteration < InIterations; ++Iteration)
        {
            auto Desired = MoveTemp(Scratch);
            Desired.Reset();
            for (const auto& Input : InInputs)
            {
                for (const auto& Coordinate : *Input._Cells)
                { Desired.Add(Coordinate, Input._Placement); }
            }

            Swap(Stamped, Desired);
            Sink += Stamped.Num();
            Sink += Stamped.Contains(FIntPoint{0, 0}) ? 1 : 0;
            Result._FinalCellCount = Stamped.Num();

            if (Desired.GetAllocatedSize() > DesiredCellsScratchMaxBytes)
            { Desired.Empty(); }
            else
            { Desired.Reset(); }

            Scratch = MoveTemp(Desired);
        }
        Result._Milliseconds = (FPlatformTime::Seconds() - StartSeconds) * 1000.0;

        volatile auto ObservableSink = Sink;
        (void)ObservableSink;
        return Result;
    }

    auto
        Log_MapMicrobenchmark(
            FAutomationTestBase& InTest,
            const TArray<FPlacementInput>& InInputs,
            int32 InIterations) -> void
    {
        auto FreshRuns = TArray<double>{};
        auto RetainedRuns = TArray<double>{};
        constexpr auto Repetitions = 3;

        for (auto RunIndex = 0; RunIndex < Repetitions; ++RunIndex)
        {
            auto Fresh = FMapBenchmarkResult{};
            auto Retained = FMapBenchmarkResult{};

            if (RunIndex % 2 == 0)
            {
                Fresh = Run_FreshMapMoveBenchmark(InInputs, InIterations);
                Retained = Run_RetainedSwapResetBenchmark(InInputs, InIterations);
            }
            else
            {
                Retained = Run_RetainedSwapResetBenchmark(InInputs, InIterations);
                Fresh = Run_FreshMapMoveBenchmark(InInputs, InIterations);
            }

            InTest.TestEqual(TEXT("baseline map workload produces the expected desired-cell count"),
                Fresh._FinalCellCount, 64);
            InTest.TestEqual(TEXT("retained map workload produces the expected desired-cell count"),
                Retained._FinalCellCount, 64);

            FreshRuns.Add(Fresh._Milliseconds);
            RetainedRuns.Add(Retained._Milliseconds);
        }

        const auto GetMean = [](const TArray<double>& InRuns) -> double
        {
            auto Total = 0.0;
            for (const auto Run : InRuns)
            { Total += Run; }
            return Total / static_cast<double>(InRuns.Num());
        };

        const auto GetMax = [](const TArray<double>& InRuns) -> double
        {
            auto Maximum = 0.0;
            for (const auto Run : InRuns)
            { Maximum = FMath::Max(Maximum, Run); }
            return Maximum;
        };

        InTest.AddInfo(FString::Printf(
            TEXT("[CkGridOccupancyScratchBench] map microbenchmark only; iterations=%d cells=64 repeats=%d fresh-map mean=%.3fms max=%.3fms retained-swap-reset mean=%.3fms max=%.3fms"),
            InIterations,
            Repetitions,
            GetMean(FreshRuns),
            GetMax(FreshRuns),
            GetMean(RetainedRuns),
            GetMax(RetainedRuns)));
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkGrid_OccupancyScratch_LifecycleAndMapWorkload,
    "Ck.Grid.OccupancyScratch.LifecycleAndMapWorkload",
    ck_test_grid_occupancy_scratch::TestFlags)

bool FCkGrid_OccupancyScratch_LifecycleAndMapWorkload::RunTest(const FString& Parameters)
{
    using namespace ck_test_grid_occupancy_scratch;

    auto Scenario = MakeShared<FScenario>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, EntryMapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, ReadyTimeoutSeconds));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, Scenario](UWorld* InWorld) -> void
        {
            Scenario->_Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld);
            if (NOT TestTrue(TEXT("transient test owner was created"), ck::IsValid(Scenario->_Owner)))
            { return; }

            UCk_Utils_Net_UE::Add(Scenario->_Owner, MakeAuthorityNetSettings());

            Scenario->_GridA = UCk_Utils_2dGridSystem_UE::Create(
                Scenario->_Owner, FTransform::Identity, MakeGridParams(FIntPoint{8, 8}));
            Scenario->_GridB = UCk_Utils_2dGridSystem_UE::Create(
                Scenario->_Owner, FTransform{FVector{2000.0, 0.0, 0.0}}, MakeGridParams(FIntPoint{2, 2}));

            Scenario->_InitialOccupant = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Scenario->_Owner);
            Scenario->_AlternateGridOccupant = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Scenario->_Owner);
            Scenario->_ReplacementOccupant = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Scenario->_Owner);
            Scenario->_LargeOccupant = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Scenario->_Owner);
            Scenario->_SmallOccupant = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Scenario->_Owner);

            if (NOT TestTrue(TEXT("both real grids were composed"),
                ck::IsValid(Scenario->_GridA) && ck::IsValid(Scenario->_GridB)))
            { return; }

            // Grid creation uses Request_CreateEntity, which copies Net Info from this non-transient lifetime owner.
            // Occupancy's production replication path requires that composition even for a non-replicating fixture.
            if (NOT TestTrue(TEXT("owner and both grids have the required Net Info"),
                UCk_Utils_Net_UE::Has(Scenario->_Owner)
                    && UCk_Utils_Net_UE::Has(Scenario->_GridA)
                    && UCk_Utils_Net_UE::Has(Scenario->_GridB)))
            { return; }

            if (NOT TestTrue(TEXT("all placement occupants were created"),
                ck::IsValid(Scenario->_InitialOccupant)
                    && ck::IsValid(Scenario->_AlternateGridOccupant)
                    && ck::IsValid(Scenario->_ReplacementOccupant)
                    && ck::IsValid(Scenario->_LargeOccupant)
                    && ck::IsValid(Scenario->_SmallOccupant)))
            { return; }

            Scenario->_InitialPlacement = UCk_Utils_2dGridOccupancy_UE::Request_AddPlacement(
                Scenario->_GridA,
                Scenario->_InitialOccupant,
                FIntPoint{1, 1},
                ECk_CardinalRotation::None,
                TArray<FIntPoint>{FIntPoint{1, 1}, FIntPoint{1, 2}, FIntPoint{2, 2}},
                {});
            Scenario->_AlternateGridPlacement = UCk_Utils_2dGridOccupancy_UE::Request_AddPlacement(
                Scenario->_GridB,
                Scenario->_AlternateGridOccupant,
                FIntPoint{1, 1},
                ECk_CardinalRotation::None,
                TArray<FIntPoint>{FIntPoint{1, 1}},
                {});

            TestTrue(TEXT("initial placement was created"), ck::IsValid(Scenario->_InitialPlacement));
            TestTrue(TEXT("alternate-grid placement was created"), ck::IsValid(Scenario->_AlternateGridPlacement));
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([Scenario]() -> bool
        {
            return UCk_Utils_2dGridOccupancy_UE::Get_IsOccupied(Scenario->_GridA, FIntPoint{1, 1})
                && UCk_Utils_2dGridOccupancy_UE::Get_IsOccupied(Scenario->_GridA, FIntPoint{1, 2})
                && UCk_Utils_2dGridOccupancy_UE::Get_IsOccupied(Scenario->_GridA, FIntPoint{2, 2})
                && UCk_Utils_2dGridOccupancy_UE::Get_IsOccupied(Scenario->_GridB, FIntPoint{1, 1});
        }),
        ReadyTimeoutSeconds,
        TEXT("initial placements are stamped by the production occupancy processor")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(2));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, Scenario]() -> bool
        {
            const auto InitialStillOwnsCell = UCk_Utils_2dGridOccupancy_UE::Get_PlacementAt(
                Scenario->_GridA, FIntPoint{1, 1}) == Scenario->_InitialPlacement;
            const auto AlternateGridStillOwnsCell = UCk_Utils_2dGridOccupancy_UE::Get_PlacementAt(
                Scenario->_GridB, FIntPoint{1, 1}) == Scenario->_AlternateGridPlacement;

            return TestTrue(TEXT("unchanged repeated stamps preserve Grid A placement identity"), InitialStillOwnsCell)
                && TestTrue(TEXT("same coordinate on another grid retains its independent placement"), AlternateGridStillOwnsCell);
        }),
        TEXT("unchanged stamping and alternate-grid isolation")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, Scenario](UWorld*) -> void
        {
            if (ck::Is_NOT_Valid(Scenario->_GridA) || ck::Is_NOT_Valid(Scenario->_InitialPlacement)
                || ck::Is_NOT_Valid(Scenario->_ReplacementOccupant))
            { AddError(TEXT("replacement stage requires a valid Grid A, initial placement, and replacement occupant")); return; }

            UCk_Utils_2dGridOccupancy_UE::Request_RemovePlacement(Scenario->_InitialPlacement, {});
            Scenario->_ReplacementPlacement = UCk_Utils_2dGridOccupancy_UE::Request_AddPlacement(
                Scenario->_GridA,
                Scenario->_ReplacementOccupant,
                FIntPoint{5, 5},
                ECk_CardinalRotation::None,
                TArray<FIntPoint>{FIntPoint{5, 5}},
                {});
            TestTrue(TEXT("replacement placement was created"), ck::IsValid(Scenario->_ReplacementPlacement));
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([Scenario]() -> bool
        {
            return NOT UCk_Utils_2dGridOccupancy_UE::Get_IsOccupied(Scenario->_GridA, FIntPoint{1, 1})
                && NOT UCk_Utils_2dGridOccupancy_UE::Get_IsOccupied(Scenario->_GridA, FIntPoint{1, 2})
                && NOT UCk_Utils_2dGridOccupancy_UE::Get_IsOccupied(Scenario->_GridA, FIntPoint{2, 2})
                && UCk_Utils_2dGridOccupancy_UE::Get_PlacementAt(Scenario->_GridA, FIntPoint{5, 5})
                    == Scenario->_ReplacementPlacement;
        }),
        ReadyTimeoutSeconds,
        TEXT("removed footprint is unstamped and replacement footprint is stamped")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, Scenario](UWorld*) -> void
        {
            if (ck::Is_NOT_Valid(Scenario->_AlternateGridOccupant))
            { AddError(TEXT("destruction cleanup stage requires a valid alternate-grid occupant")); return; }

            auto OccupantToDestroy = Scenario->_AlternateGridOccupant;
            UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(OccupantToDestroy);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([Scenario]() -> bool
        {
            return NOT UCk_Utils_2dGridOccupancy_UE::Get_IsOccupied(Scenario->_GridB, FIntPoint{1, 1});
        }),
        ReadyTimeoutSeconds,
        TEXT("destroyed alternate-grid occupant auto-prunes its placement and clears its cell")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, Scenario]() -> bool
        {
            const auto ReplacementSurvived = UCk_Utils_2dGridOccupancy_UE::Get_PlacementAt(
                Scenario->_GridA, FIntPoint{5, 5}) == Scenario->_ReplacementPlacement;
            return TestTrue(TEXT("destroying Grid B's occupant does not contaminate Grid A"), ReplacementSurvived);
        }),
        TEXT("occupant destruction cleanup is scoped to its placement grid")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, Scenario](UWorld*) -> void
        {
            if (ck::Is_NOT_Valid(Scenario->_GridA) || ck::Is_NOT_Valid(Scenario->_ReplacementPlacement)
                || ck::Is_NOT_Valid(Scenario->_LargeOccupant))
            { AddError(TEXT("large-footprint stage requires Grid A, replacement placement, and large occupant")); return; }

            UCk_Utils_2dGridOccupancy_UE::Request_RemovePlacement(Scenario->_ReplacementPlacement, {});
            Scenario->_LargeCells = Get_AllGridCoordinates(FIntPoint{8, 8});
            Scenario->_LargePlacement = UCk_Utils_2dGridOccupancy_UE::Request_AddPlacement(
                Scenario->_GridA,
                Scenario->_LargeOccupant,
                FIntPoint::ZeroValue,
                ECk_CardinalRotation::None,
                Scenario->_LargeCells,
                {});

            TestTrue(TEXT("large footprint placement was created"), ck::IsValid(Scenario->_LargePlacement));
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([Scenario]() -> bool
        {
            return UCk_Utils_2dGridOccupancy_UE::Get_PlacementAt(Scenario->_GridA, FIntPoint{0, 0})
                    == Scenario->_LargePlacement
                && UCk_Utils_2dGridOccupancy_UE::Get_PlacementAt(Scenario->_GridA, FIntPoint{7, 7})
                    == Scenario->_LargePlacement;
        }),
        ReadyTimeoutSeconds,
        TEXT("large footprint is stamped before the bounded map-workload benchmark")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, Scenario](UWorld*) -> void
        {
            if (ck::Is_NOT_Valid(Scenario->_GridA) || ck::Is_NOT_Valid(Scenario->_LargePlacement)
                || ck::Is_NOT_Valid(Scenario->_SmallOccupant))
            { AddError(TEXT("benchmark and small-replacement stage requires Grid A, large placement, and small occupant")); return; }

            const auto& LargePlacementCells = Scenario->_LargePlacement
                .Get<ck::FFragment_2dGridPlacement_Params>()
                .Get_Cells();
            const auto Inputs = TArray<FPlacementInput>{
                FPlacementInput{Scenario->_LargePlacement, &LargePlacementCells}};
            Log_MapMicrobenchmark(*this, Inputs, 4096);

            UCk_Utils_2dGridOccupancy_UE::Request_RemovePlacement(Scenario->_LargePlacement, {});
            Scenario->_SmallPlacement = UCk_Utils_2dGridOccupancy_UE::Request_AddPlacement(
                Scenario->_GridA,
                Scenario->_SmallOccupant,
                FIntPoint{0, 0},
                ECk_CardinalRotation::None,
                TArray<FIntPoint>{FIntPoint{0, 0}},
                {});
            TestTrue(TEXT("small replacement footprint was created"), ck::IsValid(Scenario->_SmallPlacement));
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([Scenario]() -> bool
        {
            if (UCk_Utils_2dGridOccupancy_UE::Get_PlacementAt(Scenario->_GridA, FIntPoint{0, 0})
                != Scenario->_SmallPlacement)
            { return false; }

            for (const auto& Coordinate : Scenario->_LargeCells)
            {
                if (Coordinate != FIntPoint{0, 0}
                    && UCk_Utils_2dGridOccupancy_UE::Get_IsOccupied(Scenario->_GridA, Coordinate))
                { return false; }
            }
            return true;
        }),
        ReadyTimeoutSeconds,
        TEXT("large footprint stale cells are cleared after a small replacement")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([Scenario](UWorld*) -> void
        {
            auto OwnerToDestroy = Scenario->_Owner;
            UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(OwnerToDestroy);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
