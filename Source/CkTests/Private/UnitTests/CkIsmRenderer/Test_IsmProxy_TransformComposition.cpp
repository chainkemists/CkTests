#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/Enums/CkEnums.h"
#include "CkCore/Validation/CkIsValid.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Net/CkNet_Utils.h"
#include "CkEcsExt/Transform/CkTransform_Utils.h"

#include "CkIsmRenderer/CkIsmSubsystem.h"
#include "CkIsmRenderer/Proxy/CkIsmProxy_Fragment.h"
#include "CkIsmRenderer/Proxy/CkIsmProxy_Utils.h"
#include "CkIsmRenderer/Renderer/CkIsmRenderer_TransientFactory.h"

#include "CkTests/Net/CkNetAutomation_Common.h"

#include "Components/InstancedStaticMeshComponent.h"
#include "Engine/StaticMesh.h"
#include "Engine/World.h"
#include "Materials/Material.h"
#include "Materials/MaterialInterface.h"
#include "UObject/UObjectGlobals.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_tests_ismproxy_transform_composition
{
    constexpr auto kTestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;
    constexpr auto kEntryMapPath = TEXT("/Engine/Maps/Entry");
    constexpr auto kReadyTimeoutSeconds = 30.0;
    constexpr auto kTransformTolerance = 1.0e-3;

    struct FScenario
    {
        FCk_Handle _Owner;
        FCk_Handle_Transform _Transform;
        FCk_Handle_IsmProxy _Proxy;
        TWeakObjectPtr<UCk_IsmRenderer_Subsystem_UE> _RendererSubsystem;
        FTransform _InitialExpected = FTransform::Identity;
        FTransform _MovedExpected = FTransform::Identity;
    };

    auto MakeAuthorityNetSettings() -> FCk_Net_ConnectionSettings
    {
        return FCk_Net_ConnectionSettings{
            ECk_Replication::DoesNotReplicate,
            ECk_Net_NetModeType::ClientAndHost,
            ECk_Net_EntityNetRole::Authority};
    }

    auto ComposeExpectedTransform(
        const FTransform& InSourceTransform,
        const FVector& InLocalLocationOffset,
        const FRotator& InLocalRotationOffset,
        const FVector& InScaleMultiplier) -> FTransform
    {
        return FTransform{
            InSourceTransform.GetRotation() * InLocalRotationOffset.Quaternion(),
            InSourceTransform.GetLocation() + InLocalLocationOffset,
            InSourceTransform.GetScale3D() * InScaleMultiplier};
    }

    auto TryReadLiveInstanceTransform(
        const FScenario& InScenario,
        FTransform& OutTransform) -> bool
    {
        auto* RendererSubsystem = InScenario._RendererSubsystem.Get();
        if (NOT ck::IsValid(RendererSubsystem) ||
            NOT ck::IsValid(InScenario._Proxy) ||
            NOT InScenario._Proxy.Has<ck::FFragment_IsmProxy_Current>() ||
            NOT InScenario._Proxy.Has<ck::FFragment_IsmProxy_Params>())
        { return false; }

        const auto& RendererData = InScenario._Proxy.Get<ck::FFragment_IsmProxy_Params>().Get_IsmRenderer().Get();
        if (NOT ck::IsValid(RendererData))
        { return false; }

        auto* IsmComponent = RendererSubsystem->FindOrCache_IsmComponent(RendererData).Get();
        if (NOT ck::IsValid(IsmComponent))
        { return false; }

        const auto InstanceId =
            InScenario._Proxy.Get<ck::FFragment_IsmProxy_Current>().Get_IsmInstanceIndex();
        if (NOT IsmComponent->IsValidId(InstanceId))
        { return false; }

        const auto InstanceIndex = IsmComponent->GetInstanceIndexForId(InstanceId);
        if (InstanceIndex == INDEX_NONE)
        { return false; }

        constexpr auto TransformAsWorldSpace = true;
        return IsmComponent->GetInstanceTransform(InstanceIndex, OutTransform, TransformAsWorldSpace);
    }

    auto DoesLiveInstanceMatch(
        const FScenario& InScenario,
        const FTransform& InExpectedTransform) -> bool
    {
        auto ActualTransform = FTransform{};
        return TryReadLiveInstanceTransform(InScenario, ActualTransform) &&
            ActualTransform.Equals(InExpectedTransform, kTransformTolerance);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_IsmProxy_TransformComposition,
    "CkTests.UnitTests.CkIsmRenderer.IsmProxy.TransformComposition",
    ck_tests_ismproxy_transform_composition::kTestFlags)

bool FCkTest_IsmProxy_TransformComposition::RunTest(const FString&)
{
    using namespace ck_tests_ismproxy_transform_composition;

    const auto Scenario = MakeShared<FScenario>();
    const auto InitialTransform = FTransform{
        FRotator{17.0, -43.0, 29.0},
        FVector{137.0, -251.0, 389.0},
        FVector{1.25, 0.75, 2.5}};
    const auto MovedTransform = FTransform{
        FRotator{-31.0, 68.0, -47.0},
        FVector{-467.0, 593.0, -719.0},
        FVector{2.0, 1.5, 0.625}};
    const auto LocalLocationOffset = FVector{11.0, -19.0, 23.0};
    const auto LocalRotationOffset = FRotator{37.0, 53.0, -71.0};
    const auto ScaleMultiplier = FVector{0.5, 1.75, 1.25};

    Scenario->_InitialExpected = ComposeExpectedTransform(
        InitialTransform, LocalLocationOffset, LocalRotationOffset, ScaleMultiplier);
    Scenario->_MovedExpected = ComposeExpectedTransform(
        MovedTransform, LocalLocationOffset, LocalRotationOffset, ScaleMultiplier);

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, kEntryMapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, kReadyTimeoutSeconds));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda(
            [this, Scenario, InitialTransform, LocalLocationOffset, LocalRotationOffset, ScaleMultiplier](UWorld* InWorld) -> void
            {
                auto* Mesh = LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Cube.Cube"));
                if (Mesh == nullptr)
                {
                    AddError(TEXT("failed to load the transient ISM test mesh"));
                    return;
                }

                auto* Material = LoadObject<UMaterialInterface>(nullptr,
                    TEXT("/CkFoundation/CkUsf/GeneratedLooks/M_CkUsf_Look_PerInstanceHue.M_CkUsf_Look_PerInstanceHue"));
                if (NOT TestTrue(TEXT("authored ISM visualizer material is available"), ck::IsValid(Material)))
                { return; }
                auto* RootMaterial = Material->GetMaterial();
                if (NOT TestTrue(TEXT("ISM visualizer material has a valid root"), ck::IsValid(RootMaterial)))
                { return; }
                if (NOT TestTrue(TEXT("authored material supports ISM usage"), RootMaterial->bUsedWithInstancedStaticMeshes != 0))
                { return; }

                const auto Overrides = TArray<FCk_MeshMaterialOverride>{FCk_MeshMaterialOverride{0, Material}};
                auto* RendererData = UCk_Utils_IsmRenderer_TransientFactory_UE::GetOrCreate_ForMeshWithMaterialsAndCustomData(
                    InWorld, Mesh, Overrides, 1, ECk_Mobility::Movable);
                if (RendererData == nullptr)
                {
                    AddError(TEXT("failed to create the movable transient ISM renderer"));
                    return;
                }

                auto* RendererSubsystem = InWorld->GetSubsystem<UCk_IsmRenderer_Subsystem_UE>();
                if (RendererSubsystem == nullptr)
                {
                    AddError(TEXT("failed to resolve the ISM renderer subsystem"));
                    return;
                }

                Scenario->_Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld);
                if (NOT TestTrue(TEXT("transient test owner was created"), ck::IsValid(Scenario->_Owner)))
                { return; }

                UCk_Utils_Net_UE::Add(Scenario->_Owner, MakeAuthorityNetSettings());
                if (NOT TestTrue(TEXT("transient test owner has authority network info"),
                    UCk_Utils_Net_UE::Has(Scenario->_Owner)))
                { return; }

                Scenario->_Transform = UCk_Utils_Transform_UE::Add(
                    Scenario->_Owner, InitialTransform, ECk_Replication::DoesNotReplicate);
                if (NOT TestTrue(TEXT("transform source was created"), ck::IsValid(Scenario->_Transform)))
                { return; }

                auto ProxyParams = FCk_Fragment_IsmProxy_ParamsData{RendererData};
                ProxyParams.Set_LocalLocationOffset(LocalLocationOffset);
                ProxyParams.Set_LocalRotationOffset(LocalRotationOffset);
                ProxyParams.Set_ScaleMultiplier(ScaleMultiplier);
                ProxyParams.Get_CustomInstanceDataDefaults().Add(FCk_CustomPrimitiveData{
                    0, FCk_CustomPrimitiveData_Value{0.5f}});
                Scenario->_Proxy = UCk_Utils_IsmProxy_UE::Add(Scenario->_Transform, ProxyParams);
                if (NOT TestTrue(TEXT("movable ISM proxy was added"), ck::IsValid(Scenario->_Proxy)))
                { return; }

                Scenario->_RendererSubsystem = RendererSubsystem;
            })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(
        this,
        FCk_NetAutoTest_Condition::CreateLambda(
            [Scenario]() -> bool
            { return DoesLiveInstanceMatch(*Scenario, Scenario->_InitialExpected); }),
        kReadyTimeoutSeconds,
        TEXT("production ISM proxy setup adds the composed initial instance")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda(
            [this, Scenario]() -> bool
            {
                auto ActualTransform = FTransform{};
                const auto HasLiveInstance = TryReadLiveInstanceTransform(*Scenario, ActualTransform);
                TestTrue(TEXT("production setup creates a live movable ISM instance"), HasLiveInstance);
                if (NOT HasLiveInstance)
                { return true; }

                TestTrue(TEXT("initial instance location includes the local offset"),
                    ActualTransform.GetLocation().Equals(Scenario->_InitialExpected.GetLocation(), kTransformTolerance));
                TestTrue(TEXT("initial instance rotation post-multiplies the local offset"),
                    ActualTransform.GetRotation().Equals(Scenario->_InitialExpected.GetRotation(), kTransformTolerance));
                TestTrue(TEXT("initial instance scale includes the nonuniform multiplier"),
                    ActualTransform.GetScale3D().Equals(Scenario->_InitialExpected.GetScale3D(), kTransformTolerance));
                return true;
            }),
        TEXT("initial movable ISM instance pose is composed by production setup")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda(
            [this, Scenario, MovedTransform](UWorld*) -> void
            {
                if (NOT ck::IsValid(Scenario->_Transform))
                {
                    AddError(TEXT("transform source became invalid before the move request"));
                    return;
                }

                UCk_Utils_Transform_UE::Request_SetTransform(
                    Scenario->_Transform,
                    FCk_Request_Transform_SetTransform{MovedTransform},
                    {});
            })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(
        this,
        FCk_NetAutoTest_Condition::CreateLambda(
            [Scenario]() -> bool
            { return DoesLiveInstanceMatch(*Scenario, Scenario->_MovedExpected); }),
        kReadyTimeoutSeconds,
        TEXT("production transform update moves the live ISM instance")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda(
            [this, Scenario]() -> bool
            {
                auto ActualTransform = FTransform{};
                const auto HasLiveInstance = TryReadLiveInstanceTransform(*Scenario, ActualTransform);
                TestTrue(TEXT("moved ISM instance remains live"), HasLiveInstance);
                if (NOT HasLiveInstance)
                { return true; }

                TestTrue(TEXT("updated instance location includes the local offset"),
                    ActualTransform.GetLocation().Equals(Scenario->_MovedExpected.GetLocation(), kTransformTolerance));
                TestTrue(TEXT("updated instance rotation keeps the post-multiplied local offset"),
                    ActualTransform.GetRotation().Equals(Scenario->_MovedExpected.GetRotation(), kTransformTolerance));
                TestTrue(TEXT("updated instance scale keeps the nonuniform multiplier"),
                    ActualTransform.GetScale3D().Equals(Scenario->_MovedExpected.GetScale3D(), kTransformTolerance));
                TestFalse(TEXT("updated live instance no longer has the initial pose"),
                    ActualTransform.Equals(Scenario->_InitialExpected, kTransformTolerance));
                return true;
            }),
        TEXT("moved movable ISM instance pose is composed by production update")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif
