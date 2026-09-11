#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/Validation/CkIsValid.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Net/CkNet_Utils.h"

#include "CkEcsExt/Transform/CkTransform_Utils.h"

#include "CkEqs/Query/CkEqs_Fragment_Data.h"
#include "CkEqs/Query/CkEqs_Utils.h"

#include "CkNavigation/NavSurface/CkNavSurface_Utils.h"

#include "CkTests/Net/CkNetAutomation_Common.h"

#include "../CkTest_CompletionListener.h"

#include "NavigationSystem.h"
#include "UObject/Package.h"
#include "UObject/StrongObjectPtr.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_eqs_navprojection
{
    constexpr auto TestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;
    constexpr auto EntryMapPath = TEXT("/Engine/Maps/Entry");
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto RawCircleCandidateCount = 4;

    auto
        MakeAuthorityNetSettings() -> FCk_Net_ConnectionSettings
    {
        return FCk_Net_ConnectionSettings{
            ECk_Replication::DoesNotReplicate,
            ECk_Net_NetModeType::ClientAndHost,
            ECk_Net_EntityNetRole::Authority};
    }

    auto
        MakeCircleGenerator(
            bool InProjectOntoNav) -> FCk_Eqs_GeneratorParams
    {
        auto Generator = FCk_Eqs_GeneratorParams{};
        Generator.Set_GeneratorType(ECk_Eqs_GeneratorType::OnCircle);
        Generator.Set_CircleRadius(200.0f);
        Generator.Set_NumPointsOnCircle(RawCircleCandidateCount);
        Generator.Set_ProjectOntoNav(InProjectOntoNav);
        Generator.Set_NavProjectionSearchHalfExtentUu(100.0f);
        return Generator;
    }

    auto
        MakeCompletionDelegate(
            UCk_Test_CompletionListener_UE* InListener) -> FCk_Delegate_Request_OnCompleted
    {
        auto Delegate = FCk_Delegate_Request_OnCompleted{};
        Delegate.BindDynamic(InListener, &UCk_Test_CompletionListener_UE::OnRequestCompleted);
        return Delegate;
    }
}

// --------------------------------------------------------------------------------------------------------------------
//
// Projection is an admission requirement. This uses an actual PIE UWorld and its actual Recast navigation
// system, deliberately without NavMeshBounds, rather than a hand-authored provider table. The non-projected
// companion query proves the fixture generated raw candidates and that failure is specific to requested projection.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Eqs_NavProjection_NoDataFailsClosed,
    "CkTests.UnitTests.CkEqs.NavProjection.NoDataFailsClosed",
    ck_test_eqs_navprojection::TestFlags)

bool FCkTest_Eqs_NavProjection_NoDataFailsClosed::RunTest(const FString& Parameters)
{
    using namespace ck_test_eqs_navprojection;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, EntryMapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, ReadyTimeoutSeconds));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InWorld) -> void
        {
            if (NOT TestNotNull(TEXT("the PIE server world exists"), InWorld))
            { return; }

            if (NOT TestNotNull(TEXT("the real Recast navigation system exists"),
                FNavigationSystem::GetCurrent<UNavigationSystemV1>(InWorld)))
            { return; }

            UCk_Utils_NavSurface_UE::Request_SetProvider(InWorld, ECk_NavSurface_Provider::Recast);
            if (NOT TestEqual(TEXT("the real facade selected Recast for this PIE world"),
                UCk_Utils_NavSurface_UE::Get_Provider(InWorld), ECk_NavSurface_Provider::Recast))
            { return; }

            if (NOT TestEqual(TEXT("Recast has no generated navigation data in the Entry-map fixture"),
                UCk_Utils_NavSurface_UE::Get_ProviderHealth(InWorld), ECk_NavSurface_ProviderHealth::NoData))
            { return; }

            auto Querier = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld);
            if (NOT TestTrue(TEXT("the real query owner was created"), ck::IsValid(Querier)))
            { return; }

            UCk_Utils_Net_UE::Add(Querier, MakeAuthorityNetSettings());
            auto QuerierTransform = UCk_Utils_Transform_UE::Add(
                Querier, FTransform::Identity, ECk_Replication::DoesNotReplicate);
            if (NOT TestTrue(TEXT("the query owner has a production transform"),
                ck::IsValid(QuerierTransform)))
            { return; }

            auto ProjectedListener = TStrongObjectPtr<UCk_Test_CompletionListener_UE>{
                NewObject<UCk_Test_CompletionListener_UE>(GetTransientPackage())};
            auto ProjectedParams = FCk_Eqs_QueryParams{
                Querier, MakeCircleGenerator(true), TArray<FCk_Eqs_TestParams>{}};
            ProjectedParams.Set_RunMode(ECk_Eqs_RunMode::AllMatching);
            const auto ProjectedQuery = UCk_Utils_Eqs_UE::Request_RunQuery_Immediate(
                Querier, ProjectedParams, MakeCompletionDelegate(ProjectedListener.Get()));

            if (NOT TestTrue(TEXT("the projected immediate query still returns a completed query handle"),
                ck::IsValid(ProjectedQuery)))
            { return; }
            TestTrue(TEXT("the projected query completes synchronously"),
                UCk_Utils_Eqs_UE::Get_IsComplete(ProjectedQuery));
            TestTrue(TEXT("the unavailable projection rejects the query"),
                UCk_Utils_Eqs_UE::Get_IsFailed(ProjectedQuery));
            TestEqual(TEXT("the projected failure reports exactly one callback"),
                ProjectedListener->_TimesRequestCompleted, 1);
            TestEqual(TEXT("the projected failure callback reports Failed"),
                ProjectedListener->_LastRequestResult, ECk_Request_OperationResult::Failed);
            TestEqual(TEXT("the rejected projection publishes no raw candidates"),
                UCk_Utils_Eqs_UE::Get_AllCandidates(ProjectedQuery).Num(), 0);

            auto RawListener = TStrongObjectPtr<UCk_Test_CompletionListener_UE>{
                NewObject<UCk_Test_CompletionListener_UE>(GetTransientPackage())};
            auto RawParams = FCk_Eqs_QueryParams{
                Querier, MakeCircleGenerator(false), TArray<FCk_Eqs_TestParams>{}};
            RawParams.Set_RunMode(ECk_Eqs_RunMode::AllMatching);
            const auto RawQuery = UCk_Utils_Eqs_UE::Request_RunQuery_Immediate(
                Querier, RawParams, MakeCompletionDelegate(RawListener.Get()));

            if (NOT TestTrue(TEXT("the unprojected immediate query returns a completed query handle"),
                ck::IsValid(RawQuery)))
            { return; }
            TestTrue(TEXT("the unprojected immediate query completes"),
                UCk_Utils_Eqs_UE::Get_IsComplete(RawQuery));
            TestFalse(TEXT("the unprojected control does not fail"),
                UCk_Utils_Eqs_UE::Get_IsFailed(RawQuery));
            TestEqual(TEXT("the unprojected control reports exactly one callback"),
                RawListener->_TimesRequestCompleted, 1);
            TestEqual(TEXT("the unprojected control callback reports success"),
                RawListener->_LastRequestResult, ECk_Request_OperationResult::Succeeded);
            TestEqual(TEXT("the unprojected control retains the deterministic raw circle candidates"),
                UCk_Utils_Eqs_UE::Get_AllCandidates(RawQuery).Num(), RawCircleCandidateCount);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif
