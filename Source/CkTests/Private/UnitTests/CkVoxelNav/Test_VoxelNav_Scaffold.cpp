#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "CkVoxelNav/Volume/CkVoxelNavVolume_Fragment.h"
#include "CkVoxelNav/Volume/CkVoxelNavVolume_Utils.h"

#include "../CkUnitTest_Common.h"

#include <Misc/AutomationTest.h>

// --------------------------------------------------------------------------------------------------------------------
// Pins the CkVoxelNav volume scaffold: Add composes the feature onto a CHILD entity of the owner (the
// Add-creates-child ritual), stamps the NeedsBuild tag its Setup processor consumes, and round-trips the
// authored params. Hermetic (private ck::FEcsWorld, no PIE) — composition and the params fragment are
// synchronous, so nothing here needs a ticking world.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_voxelnav_scaffold
{
    const auto VolumeBounds = FBox{FVector{-400.0, -400.0, 0.0}, FVector{400.0, 400.0, 800.0}};

    constexpr auto FinestCellSizeUu = 50.0f;

    static auto Make_VolumeParams() -> FCk_Fragment_VoxelNavVolume_ParamsData
    {
        return FCk_Fragment_VoxelNavVolume_ParamsData{VolumeBounds, FinestCellSizeUu};
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Scaffold_AddComposesVolumeOnChildEntity,
    "Ck.VoxelNav.Volume.Scaffold.AddComposesVolumeOnChildEntity",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Scaffold_AddComposesVolumeOnChildEntity::RunTest(const FString& Parameters)
{
    using namespace ck_test_voxelnav_scaffold;

    auto EcsWorld = ck::FEcsWorld{};
    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry());

    const auto Volume = UCk_Utils_VoxelNavVolume_UE::Add(Owner, Make_VolumeParams());

    if (NOT TestTrue(TEXT("Add returns a valid VoxelNavVolume handle"), ck::IsValid(Volume)))
    { return false; }

    TestTrue(TEXT("the returned volume entity has the feature"), UCk_Utils_VoxelNavVolume_UE::Has(Volume));
    TestFalse(TEXT("the owner itself does NOT carry the feature (it lives on the child entity)"),
        UCk_Utils_VoxelNavVolume_UE::Has(Owner));

    TestTrue(TEXT("the volume is stamped NeedsBuild for the Setup processor"),
        Volume.Has<ck::FTag_VoxelNavVolume_NeedsBuild>());

    const auto& Params = Volume.Get<ck::FFragment_VoxelNavVolume_Params>();

    TestTrue(TEXT("authored volume bounds round-trip"), Params.Get_VolumeBounds() == VolumeBounds);
    TestEqual(TEXT("authored finest cell size round-trips"), Params.Get_FinestCellSizeUu(), FinestCellSizeUu);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Scaffold_AddOntoInvalidOwnerIsRejected,
    "Ck.VoxelNav.Volume.Scaffold.AddOntoInvalidOwnerIsRejected",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Scaffold_AddOntoInvalidOwnerIsRejected::RunTest(const FString& Parameters)
{
    using namespace ck_test_voxelnav_scaffold;

    auto InvalidOwner = FCk_Handle{};

    // One ensure fire emits a log entry + an Error line, both carrying the message — whitelist by substring
    // without enforcing a count.
    AddExpectedError(TEXT("supplied to UCk_Utils_VoxelNavVolume_UE::Add"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    const auto Volume = UCk_Utils_VoxelNavVolume_UE::Add(InvalidOwner, Make_VolumeParams());

    TestTrue(TEXT("Add onto an invalid owner returns an INVALID volume handle"), ck::Is_NOT_Valid(Volume));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
