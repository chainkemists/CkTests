// Language=angelscript
//============================================================================
// CK NAV SURFACE - AUTOMATION TEST: THE PROVIDER REPORTS Ready ON A BAKED MAP
//============================================================================
//
// The facade's health readout is what every other NavSurface caller gates on,
// so it is worth pinning on its own: on the AutoTests level - which carries a
// NavMeshBoundsVolume over static floor geometry - the Recast adapter must
// report Ready, not NoData and not Error.
//
// Ready is defined by the adapter as "NavData resolved AND no build running",
// so the test also reads Get_IsBuildInProgress through the facade and requires
// the two answers to agree. A pair that disagreed would mean the health value
// was computed from something other than the live provider state.
//
// Everything here goes through UCk_Utils_NavSurface_UE - no engine navigation
// API is touched from this test.
//============================================================================

class UCk_AutoTest_NavSurface_ProviderHealthIsReady : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step_WaitUntil("the nav surface provider settles at Ready", n"Check_ProviderIsReady", 900);
        Add_Step(          "Ready agrees with the build and query surfaces",  n"Step_AssertReadyIsCoherent");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_ProviderIsReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_nav_surface::Get_ProviderHealth() == ECk_NavSurface_ProviderHealth::Ready);
    }

    UFUNCTION()
    private void Step_AssertReadyIsCoherent(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Health = utils_nav_surface::Get_ProviderHealth();
        Assert_True(Health == ECk_NavSurface_ProviderHealth::Ready,
            f"the AutoTests level bakes a navmesh, so the Recast adapter must report Ready - got {Health}");

        Assert_False(utils_nav_surface::Get_IsBuildInProgress(),
            "Ready is defined as 'data resolved AND no build running' - a build reported in progress contradicts the health value");

        // Ready must mean there is real surface to answer with, not merely that a NavData actor exists.
        auto Probe = FCk_NavSurface_ProjectionQuery(FVector::ZeroVector);
        Probe.Set_Mode(ECk_NavSurface_ProjectionMode::Closest);
        const auto Projection = utils_nav_surface::Try_ProjectPoint(Probe);
        Assert_True(Projection.Get_Status() == ECk_NavSurface_QueryStatus::Success,
            f"a Ready provider must be able to answer a projection over the level's own floor - got {Projection.Get_Status()}");
    }
}
