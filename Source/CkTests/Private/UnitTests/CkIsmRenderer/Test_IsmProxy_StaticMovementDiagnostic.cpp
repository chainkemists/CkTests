#include "Misc/AutomationTest.h"

#include "CkEcsExt/Transform/CkTransform_Fragment.h"
#include "CkIsmRenderer/Proxy/CkIsmProxy_Processor.h"

// --------------------------------------------------------------------------------------------------------------------

namespace
{
    constexpr auto kIsmProxyDiagnosticTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_IsmProxy_StaticMovementDiagnostic,
    "CkTests.UnitTests.CkIsmRenderer.IsmProxy.StaticMovementDiagnostic",
    kIsmProxyDiagnosticTestFlags)

bool FCkTest_IsmProxy_StaticMovementDiagnostic::RunTest(const FString& Parameters)
{
    const auto Params = ck::FFragment_IsmProxy_Params{};
    const auto InstanceTransform = FTransform::Identity;

    // Initial transform construction queues a force-refresh. It carries the shared
    // Transform_Updated tag, but the rendered instance is still at the authored pose.
    const auto Unchanged = ck::FFragment_Transform{FTransform::Identity};
    TestFalse(
        TEXT("Force-refresh-only update is not movement"),
        ck::FProcessor_IsmProxy_EnsureStaticNotMoved_DEBUG::DidTransformChange(
            Unchanged, Params, InstanceTransform));

    const auto LocationChanged = ck::FFragment_Transform{
        FTransform{FRotator::ZeroRotator, FVector{1.0f, 0.0f, 0.0f}, FVector::OneVector}};
    TestTrue(
        TEXT("Location change is movement"),
        ck::FProcessor_IsmProxy_EnsureStaticNotMoved_DEBUG::DidTransformChange(
            LocationChanged, Params, InstanceTransform));

    const auto RotationChanged = ck::FFragment_Transform{
        FTransform{FRotator{0.0f, 1.0f, 0.0f}, FVector::ZeroVector, FVector::OneVector}};
    TestTrue(
        TEXT("Rotation change is movement"),
        ck::FProcessor_IsmProxy_EnsureStaticNotMoved_DEBUG::DidTransformChange(
            RotationChanged, Params, InstanceTransform));

    const auto ScaleChanged = ck::FFragment_Transform{
        FTransform{FRotator::ZeroRotator, FVector::ZeroVector, FVector{2.0f, 1.0f, 1.0f}}};
    TestTrue(
        TEXT("Scale change is movement"),
        ck::FProcessor_IsmProxy_EnsureStaticNotMoved_DEBUG::DidTransformChange(
            ScaleChanged, Params, InstanceTransform));

    return true;
}
