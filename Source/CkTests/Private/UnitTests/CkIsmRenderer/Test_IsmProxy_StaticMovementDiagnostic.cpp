#include "Misc/AutomationTest.h"

#include "HAL/PlatformTime.h"

#include "CkCore/Math/Vector/CkVector_Utils.h"
#include "CkEcsExt/Transform/CkTransform_Fragment.h"
#include "CkIsmRenderer/Proxy/CkIsmProxy_Processor.h"

// --------------------------------------------------------------------------------------------------------------------

namespace
{
    constexpr auto kIsmProxyDiagnosticTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;

    FORCENOINLINE auto
        Get_LegacyTransformWithLocalOffset(
            const ck::FFragment_IsmProxy_Params& InParams,
            const FTransform& InTransform) -> FTransform
    {
        const auto CombinedLocation = InTransform.GetLocation() + InParams.Get_LocalLocationOffset();
        const auto CombinedRotation = InTransform.GetRotation() * InParams.Get_LocalRotationOffset().Quaternion();

        if (UCk_Utils_Vector3_UE::Get_IsAnyAxisNearlyZero(InParams.Get_ScaleMultiplier()))
        { return FTransform{CombinedRotation.Rotator(), CombinedLocation, FVector::OneVector}; }

        const auto CombinedScale = InTransform.GetScale3D() * InParams.Get_ScaleMultiplier();
        return FTransform{CombinedRotation.Rotator(), CombinedLocation, CombinedScale};
    }

    auto
        Get_OrientationDot(
            const FQuat& InLeft,
            const FQuat& InRight) -> double
    {
        return static_cast<double>(InLeft.X) * InRight.X +
            static_cast<double>(InLeft.Y) * InRight.Y +
            static_cast<double>(InLeft.Z) * InRight.Z +
            static_cast<double>(InLeft.W) * InRight.W;
    }

    auto
        Get_TransformChecksum(
            const FTransform& InTransform) -> double
    {
        const auto& Rotation = InTransform.GetRotation();
        const auto& Location = InTransform.GetLocation();
        const auto& Scale = InTransform.GetScale3D();
        return Rotation.X + Rotation.Y + Rotation.Z + Rotation.W +
            Location.X + Location.Y + Location.Z +
            Scale.X + Scale.Y + Scale.Z;
    }

    struct FTransformBenchmarkResult
    {
        double _Milliseconds = 0.0;
        double _Checksum = 0.0;
    };

    auto
        Run_ProductionTransformBenchmark(
            const ck::FFragment_IsmProxy_Params& InParams,
            const TArray<FTransform>& InTransforms,
            int32 InIterations) -> FTransformBenchmarkResult
    {
        auto Result = FTransformBenchmarkResult{};
        const auto StartSeconds = FPlatformTime::Seconds();
        for (auto Iteration = 0; Iteration < InIterations; ++Iteration)
        {
            for (const auto& Transform : InTransforms)
            {
                Result._Checksum += Get_TransformChecksum(
                    ck_ism_proxy::Get_TransformWithLocalOffset(InParams, Transform));
            }
        }
        Result._Milliseconds = (FPlatformTime::Seconds() - StartSeconds) * 1000.0;
        return Result;
    }

    auto
        Run_LegacyTransformBenchmark(
            const ck::FFragment_IsmProxy_Params& InParams,
            const TArray<FTransform>& InTransforms,
            int32 InIterations) -> FTransformBenchmarkResult
    {
        auto Result = FTransformBenchmarkResult{};
        const auto StartSeconds = FPlatformTime::Seconds();
        for (auto Iteration = 0; Iteration < InIterations; ++Iteration)
        {
            for (const auto& Transform : InTransforms)
            {
                Result._Checksum += Get_TransformChecksum(
                    Get_LegacyTransformWithLocalOffset(InParams, Transform));
            }
        }
        Result._Milliseconds = (FPlatformTime::Seconds() - StartSeconds) * 1000.0;
        return Result;
    }

    auto
        Get_Mean(const TArray<double>& InValues) -> double
    {
        auto Total = 0.0;
        for (const auto Value : InValues)
        { Total += Value; }
        return Total / static_cast<double>(InValues.Num());
    }

    auto
        Get_Maximum(const TArray<double>& InValues) -> double
    {
        auto Result = 0.0;
        for (const auto Value : InValues)
        { Result = FMath::Max(Result, Value); }
        return Result;
    }

    auto
        Is_SameOrientation(
            const FQuat& InLeft,
            const FQuat& InRight) -> bool
    {
        return FMath::Abs(Get_OrientationDot(InLeft, InRight)) >= 1.0 - KINDA_SMALL_NUMBER;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_IsmProxy_StaticMovementDiagnostic,
    "CkTests.UnitTests.CkIsmRenderer.IsmProxy.StaticMovementDiagnostic",
    kIsmProxyDiagnosticTestFlags)

bool FCkTest_IsmProxy_StaticMovementDiagnostic::RunTest(const FString& Parameters)
{
    auto Params = ck::FFragment_IsmProxy_Params{};
    Params.Set_LocalLocationOffset(FVector{17.0, -23.0, 5.0});
    Params.Set_LocalRotationOffset(FRotator{31.0, -47.0, 83.0});
    Params.Set_ScaleMultiplier(FVector{-2.0, 0.5, 1.25});

    const auto Cases = TArray<FTransform>{
        FTransform{FRotator{89.999, 37.0, -61.0}, FVector{3.0, 5.0, 7.0}, FVector{1.0, 2.0, 3.0}},
        FTransform{FRotator{90.0, 37.0, -61.0}, FVector{-11.0, 13.0, -17.0}, FVector{0.5, 1.5, 2.5}},
        FTransform{FRotator{90.001, 37.0, -61.0}, FVector{19.0, -23.0, 29.0}, FVector{2.0, 0.25, 4.0}},
        FTransform{FRotator{-53.0, 127.0, 41.0}, FVector{-31.0, 37.0, -41.0}, FVector{1.75, 2.25, 0.75}}};

    for (const auto& Transform : Cases)
    {
        const auto Production = ck_ism_proxy::Get_TransformWithLocalOffset(Params, Transform);
        const auto Legacy = Get_LegacyTransformWithLocalOffset(Params, Transform);

        const auto ExpectedPostMultiplyRotation = Transform.GetRotation() * Params.Get_LocalRotationOffset().Quaternion();
        TestTrue(TEXT("Production helper keeps a normalized rotation"), Production.IsRotationNormalized());
        TestTrue(TEXT("Production helper preserves legacy composed orientation"),
            Is_SameOrientation(Production.GetRotation(), Legacy.GetRotation()));
        TestTrue(TEXT("Production helper post-multiplies the local rotation offset"),
            Is_SameOrientation(Production.GetRotation(), ExpectedPostMultiplyRotation));
        TestEqual(TEXT("Production helper preserves exact composed location"),
            Production.GetLocation(), Legacy.GetLocation());
        TestEqual(TEXT("Production helper preserves exact multiplied scale"),
            Production.GetScale3D(), Legacy.GetScale3D());
        TestFalse(TEXT("Diagnostic treats the rendered production transform as unchanged"),
            ck::FProcessor_IsmProxy_EnsureStaticNotMoved_DEBUG::DidTransformChange(
                ck::FFragment_Transform{Transform}, Params, Production));
    }

    const auto SignedQuaternion = Cases[0].GetRotation();
    const auto SignEquivalent = FTransform{
        FQuat{-SignedQuaternion.X, -SignedQuaternion.Y, -SignedQuaternion.Z, -SignedQuaternion.W},
        Cases[0].GetLocation(),
        Cases[0].GetScale3D()};
    const auto SignedProduction = ck_ism_proxy::Get_TransformWithLocalOffset(Params, Cases[0]);
    const auto SignEquivalentProduction = ck_ism_proxy::Get_TransformWithLocalOffset(Params, SignEquivalent);
    TestTrue(TEXT("Production helper preserves sign-equivalent source orientation"),
        Is_SameOrientation(SignedProduction.GetRotation(), SignEquivalentProduction.GetRotation()));

    const auto PreMultipliedRotation = Params.Get_LocalRotationOffset().Quaternion() * Cases[0].GetRotation();
    TestFalse(TEXT("Production helper does not pre-multiply the local rotation offset"),
        Is_SameOrientation(SignedProduction.GetRotation(), PreMultipliedRotation));

    auto ZeroOffsetParams = Params;
    ZeroOffsetParams.Set_LocalLocationOffset(FVector::ZeroVector);
    ZeroOffsetParams.Set_LocalRotationOffset(FRotator::ZeroRotator);
    const auto GimbalCases = TArray<FTransform>{
        FTransform{FRotator{89.999, 37.0, -61.0}, FVector::ZeroVector, FVector::OneVector},
        FTransform{FRotator{90.0, 37.0, -61.0}, FVector::ZeroVector, FVector::OneVector},
        FTransform{FRotator{90.001, 37.0, -61.0}, FVector::ZeroVector, FVector::OneVector},
        FTransform{FRotator{-89.999, 37.0, -61.0}, FVector::ZeroVector, FVector::OneVector},
        FTransform{FRotator{-90.0, 37.0, -61.0}, FVector::ZeroVector, FVector::OneVector},
        FTransform{FRotator{-90.001, 37.0, -61.0}, FVector::ZeroVector, FVector::OneVector}};
    for (const auto& Transform : GimbalCases)
    {
        const auto Production = ck_ism_proxy::Get_TransformWithLocalOffset(ZeroOffsetParams, Transform);
        TestTrue(TEXT("Zero-offset gimbal orientation remains unchanged"),
            Is_SameOrientation(Production.GetRotation(), Transform.GetRotation()));
        TestFalse(TEXT("Zero-offset gimbal transform remains unchanged to the static diagnostic"),
            ck::FProcessor_IsmProxy_EnsureStaticNotMoved_DEBUG::DidTransformChange(
                ck::FFragment_Transform{Transform}, ZeroOffsetParams, Production));
    }

    const auto DefaultParams = ck::FFragment_IsmProxy_Params{};
    const auto InstanceTransform = FTransform::Identity;

    // Initial transform construction queues a force-refresh. It carries the shared
    // Transform_Updated tag, but the rendered instance is still at the authored pose.
    const auto Unchanged = ck::FFragment_Transform{FTransform::Identity};
    TestFalse(
        TEXT("Force-refresh-only update is not movement"),
        ck::FProcessor_IsmProxy_EnsureStaticNotMoved_DEBUG::DidTransformChange(
            Unchanged, DefaultParams, InstanceTransform));

    const auto LocationChanged = ck::FFragment_Transform{
        FTransform{FRotator::ZeroRotator, FVector{1.0f, 0.0f, 0.0f}, FVector::OneVector}};
    TestTrue(
        TEXT("Location change is movement"),
        ck::FProcessor_IsmProxy_EnsureStaticNotMoved_DEBUG::DidTransformChange(
            LocationChanged, DefaultParams, InstanceTransform));

    const auto RotationChanged = ck::FFragment_Transform{
        FTransform{FRotator{0.0f, 1.0f, 0.0f}, FVector::ZeroVector, FVector::OneVector}};
    TestTrue(
        TEXT("Rotation change is movement"),
        ck::FProcessor_IsmProxy_EnsureStaticNotMoved_DEBUG::DidTransformChange(
            RotationChanged, DefaultParams, InstanceTransform));

    const auto ScaleChanged = ck::FFragment_Transform{
        FTransform{FRotator::ZeroRotator, FVector::ZeroVector, FVector{2.0f, 1.0f, 1.0f}}};
    TestTrue(
        TEXT("Scale change is movement"),
        ck::FProcessor_IsmProxy_EnsureStaticNotMoved_DEBUG::DidTransformChange(
            ScaleChanged, DefaultParams, InstanceTransform));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_IsmProxy_TransformConstructionBenchmark,
    "CkTests.UnitTests.CkIsmRenderer.IsmProxy.TransformConstructionBenchmark",
    kIsmProxyDiagnosticTestFlags)

bool FCkTest_IsmProxy_TransformConstructionBenchmark::RunTest(const FString& Parameters)
{
    auto Params = ck::FFragment_IsmProxy_Params{};
    Params.Set_LocalLocationOffset(FVector{17.0, -23.0, 5.0});
    Params.Set_LocalRotationOffset(FRotator{31.0, -47.0, 83.0});
    Params.Set_ScaleMultiplier(FVector{-2.0, 0.5, 1.25});

    const auto Corpus = TArray<FTransform>{
        FTransform{FRotator{89.999, 37.0, -61.0}, FVector{3.0, 5.0, 7.0}, FVector{1.0, 2.0, 3.0}},
        FTransform{FRotator{90.0, 37.0, -61.0}, FVector{-11.0, 13.0, -17.0}, FVector{0.5, 1.5, 2.5}},
        FTransform{FRotator{90.001, 37.0, -61.0}, FVector{19.0, -23.0, 29.0}, FVector{2.0, 0.25, 4.0}},
        FTransform{FRotator{-53.0, 127.0, 41.0}, FVector{-31.0, 37.0, -41.0}, FVector{1.75, 2.25, 0.75}}};
    constexpr auto Repetitions = 3;
    constexpr auto Iterations = 100000;
    auto ProductionRuns = TArray<double>{};
    auto LegacyRuns = TArray<double>{};

    for (auto RunIndex = 0; RunIndex < Repetitions; ++RunIndex)
    {
        auto Production = FTransformBenchmarkResult{};
        auto Legacy = FTransformBenchmarkResult{};
        if (RunIndex % 2 == 0)
        {
            Production = Run_ProductionTransformBenchmark(Params, Corpus, Iterations);
            Legacy = Run_LegacyTransformBenchmark(Params, Corpus, Iterations);
        }
        else
        {
            Legacy = Run_LegacyTransformBenchmark(Params, Corpus, Iterations);
            Production = Run_ProductionTransformBenchmark(Params, Corpus, Iterations);
        }

        TestTrue(TEXT("Production transform benchmark has an observable checksum"),
            FMath::IsFinite(Production._Checksum));
        TestTrue(TEXT("Legacy transform benchmark has an observable checksum"),
            FMath::IsFinite(Legacy._Checksum));
        AddInfo(FString::Printf(
            TEXT("[CkIsmRenderer PERF][TransformConstruction] repeat=%d production=%.3fms legacy=%.3fms"),
            RunIndex + 1,
            Production._Milliseconds,
            Legacy._Milliseconds));
        ProductionRuns.Add(Production._Milliseconds);
        LegacyRuns.Add(Legacy._Milliseconds);
    }

    const auto TransformsPerRun = static_cast<double>(Corpus.Num()) * Iterations;
    AddInfo(FString::Printf(
        TEXT("[CkIsmRenderer PERF][TransformConstruction] transforms=%.0f repeats=%d production mean=%.3fms max=%.3fms ns/transform=%.3f legacy mean=%.3fms max=%.3fms ns/transform=%.3f"),
        TransformsPerRun,
        Repetitions,
        Get_Mean(ProductionRuns),
        Get_Maximum(ProductionRuns),
        Get_Mean(ProductionRuns) * 1000000.0 / TransformsPerRun,
        Get_Mean(LegacyRuns),
        Get_Maximum(LegacyRuns),
        Get_Mean(LegacyRuns) * 1000000.0 / TransformsPerRun));

    return true;
}
