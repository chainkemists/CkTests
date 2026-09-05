// The crowd's stationary-agent disc and the avoidance volume's painted box are provider-neutral
// markup, not a Recast painter the crowd owns. Two facts are pinned here, and both are cheap to
// state in a headless world because neither needs a built navmesh.
//
// The first is structural: the fragments hold FCk_Handle_NavSurfaceMarkup - an ENTITY the world
// owns, released by destroying it - rather than a weak pointer to UCk_NavAreaMarkup_UE. A revert to
// the engine-typed member fails to compile here rather than quietly re-binding the crowd to Recast.
//
// The second is the lifetime the crowd now has to honour: the paint is a REQUEST. The handle is
// valid on the frame it is raised and the area is not live until the drain reaches it, which is why
// the crowd's eligibility gate is _ConfirmedOnMesh and not the handle. The drain and the release
// are driven by hand, because a headless registry has no scheduler to walk either forward.
//
// What is NOT covered here: an agent that actually paints one - that needs a world with a settled
// surface, a moving crowd and the project settings that gate the painter, and is a PIE pin.

#include "CkCrowd/Agent/CkCrowdAgent_Fragment.h"
#include "CkCrowd/AvoidanceVolume/CkCrowdAvoidanceVolume_Fragment.h"
#include "CkCrowd/CkCrowd_NavGameplayTags.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkNavigation/NavSurface/CkNavSurface_AreaPolicy.h"
#include "CkNavigation/NavSurface/CkNavSurface_Fragment.h"
#include "CkNavigation/NavSurface/CkNavSurface_Fragment_Data.h"
#include "CkNavigation/NavSurface/CkNavSurface_Utils.h"

#include "CkShapes/CkShapes_Common.h"

#include "../CkUnitTest_Common.h"

#include <Engine/World.h>

#include <type_traits>
#include <utility>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_tests_crowd_neutral_markup
{
    constexpr auto InformEngineOfWorld = false;

    // A representative disc extent. Nothing here depends on the value - what is pinned is the shape
    // of the request, not its size.
    const auto AgentDiscHalfExtents = FVector{84.0, 84.0, 192.0};

    using AgentMarkupType = std::decay_t<
        decltype(std::declval<const ck::FFragment_CrowdAgent_NavMarkup&>().Get_Markup())>;

    using VolumeMarkupType = std::decay_t<
        decltype(std::declval<const ck::FFragment_CrowdAvoidanceVolume_ProbeRef&>().Get_Markup())>;

    static_assert(std::is_same_v<AgentMarkupType, FCk_Handle_NavSurfaceMarkup>,
        "The stationary-agent disc is a neutral markup handle, not an engine nav-area object");

    static_assert(std::is_same_v<VolumeMarkupType, FCk_Handle_NavSurfaceMarkup>,
        "The avoidance volume's painted box is a neutral markup handle, not an engine nav-area object");
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_CrowdNeutralMarkup_UnpaintedAgentHoldsNoMarkup,
    "CkTests.UnitTests.CkCrowd.NeutralMarkup.UnpaintedAgentHoldsNoMarkup",
    kCkUnitTestFlags)

bool FCkTest_CrowdNeutralMarkup_UnpaintedAgentHoldsNoMarkup::RunTest(const FString& Parameters)
{
    using namespace ck_tests_crowd_neutral_markup;

    const auto Agent = ck::FFragment_CrowdAgent_NavMarkup{};
    const auto Volume = ck::FFragment_CrowdAvoidanceVolume_ProbeRef{};

    // An unpainted fragment reads as holding nothing through the handle's own validity, which is
    // what every reader of these members now asks. A weak pointer would answer this question with
    // a different call and the readers would not compile.
    TestFalse(TEXT("an agent that has never painted holds no markup"),
        ck::IsValid(Agent.Get_Markup()));

    TestFalse(TEXT("nor does a volume that has not been set up"),
        ck::IsValid(Volume.Get_Markup()));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_CrowdNeutralMarkup_TheDiscIsRaisedThroughTheFacade,
    "CkTests.UnitTests.CkCrowd.NeutralMarkup.TheDiscIsRaisedThroughTheFacade",
    kCkUnitTestFlags)

bool FCkTest_CrowdNeutralMarkup_TheDiscIsRaisedThroughTheFacade::RunTest(const FString& Parameters)
{
    using namespace ck_tests_crowd_neutral_markup;

    auto* World = UWorld::CreateWorld(EWorldType::Game, InformEngineOfWorld, TEXT("CkCrowdNeutralMarkup"));

    if (NOT TestTrue(TEXT("the probe world was created"), World != nullptr))
    { return false; }

    // The paint raises an ENTITY, and an entity needs the world's registry. Resolved and checked
    // before the request rather than discovered missing inside it, so a world that came up without
    // one fails as a fixture rather than as the feature.
    auto WorldEntity = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(World);

    if (NOT TestTrue(TEXT("the probe world carries an ECS registry to raise the markup in"),
        ck::IsValid(WorldEntity)))
    {
        World->DestroyWorld(InformEngineOfWorld);
        return false;
    }

    // The exact request the stationary painter builds: the crowd's own area TAG and a box, with no
    // UNavArea class anywhere in the call.
    auto Request = FCk_Request_NavSurface_AreaMarkup{
        FCk_AnyShape{FCk_ShapeBox_Dimensions{AgentDiscHalfExtents}},
        TAG_Nav_Area_Crowd_Agent.GetTag()};
    Request.Set_WorldTransform(FTransform{FQuat::Identity, FVector{100.0, 200.0, 0.0}});

    auto Markup = UCk_Utils_NavSurface_UE::Request_AreaMarkup(World, Request, {});

    if (NOT TestTrue(TEXT("the paint hands back a markup entity"), ck::IsValid(Markup)))
    {
        World->DestroyWorld(InformEngineOfWorld);
        return false;
    }

    // The lifetime the crowd honours: raised now, live later. The request is still queued, so
    // nothing has reached a provider and the area cannot be reported live.
    TestTrue(TEXT("the paint is still queued on the markup entity"),
        Markup.Has<ck::FFragment_NavSurfaceMarkup_Requests>());

    TestFalse(TEXT("so the disc is not live on the frame it was raised"),
        UCk_Utils_NavSurface_UE::Get_IsMarkupLive(Markup));

    // Releasing it is destroying the entity - the same call Remove_Markup and Release_Runtime make.
    // Teardown stops at its first stamp here; the unpaint happens later, in FGroup_EndPlay.
    UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(Markup);

    TestTrue(TEXT("releasing the markup tears its entity down"),
        Markup.Has<ck::FTag_DestroyEntity_Initiate>());

    TestTrue(TEXT("and the release the provider is owed is still in flight"),
        ck::nav_surface::Get_HasPendingMarkupWork(World));

    World->DestroyWorld(InformEngineOfWorld);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
