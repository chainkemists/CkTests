// Language=angelscript
//============================================================================
// CK NAV SURFACE - AUTOMATION TEST: PROJECTION SUCCEEDS ON FLOOR, NOT OVER VOID
//============================================================================
//
// Try_ProjectPoint is the facade's most-used entry, and the whole point of the
// neutral status vocabulary is that "there is nothing walkable here" is a
// DIFFERENT answer from "it worked". Both halves are pinned in one test so a
// regression that made every projection Succeed (or every projection fail)
// cannot hide behind the other half.
//
// The floor half also checks the answer is PLAUSIBLE rather than merely
// Success-flagged: the returned point must lie inside the search volume the
// query itself declared, which is the only bound the contract actually gives.
//
// The void half queries a point 60,000uu out on every axis - four orders of
// magnitude past the level's nav volume and far outside the project-wide
// projection extent - so NoSurface is the only answer Recast can give. It is
// asserted exactly (not "anything but Success") because the provider is gated
// at Ready first, which rules out Unbuilt, and no query filter is supplied,
// which rules out Blocked and NoProvider.
//
// Everything here goes through UCk_Utils_NavSurface_UE.
//============================================================================

class UCk_AutoTest_NavSurface_ProjectPointOnFloorAndOverVoid : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;

    // The project-wide projection extent (UCk_Nav_ProjectSettings_UE::_NavQuerySearchHalfExtent,
    // 500uu by default) is what an unset _SearchHalfExtents opts into, so it is also the widest
    // the answer is allowed to be from the query point.
    private const float DefaultExtentUu = 500.0;

    // 60,000uu out on every axis: past the level's nav volume by two orders of magnitude.
    private const FVector VoidPoint = FVector(60000.0, 60000.0, 60000.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step_WaitUntil("the nav surface provider settles at Ready", n"Check_ProviderIsReady", 900);
        Add_Step(          "a point above walkable floor projects onto it",  n"Step_ProjectOntoFloor");
        Add_Step(          "a point over void does not project at all",      n"Step_ProjectOverVoid");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_ProviderIsReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_nav_surface::Get_ProviderHealth() == ECk_NavSurface_ProviderHealth::Ready);
    }

    UFUNCTION()
    private void Step_ProjectOntoFloor(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto QueryPoint = FVector::ZeroVector;

        auto Query = FCk_NavSurface_ProjectionQuery(QueryPoint);
        Query.Set_Mode(ECk_NavSurface_ProjectionMode::Closest);

        const auto Result = utils_nav_surface::Try_ProjectPoint(Query);

        Assert_True(Result.Get_Status() == ECk_NavSurface_QueryStatus::Success,
            f"the level's floor covers the origin, so a Closest projection there must succeed - got {Result.Get_Status()}");

        const auto Offset = Result.Get_Location() - QueryPoint;
        Assert_True(Math::Abs(Offset.X) <= DefaultExtentUu
                 && Math::Abs(Offset.Y) <= DefaultExtentUu
                 && Math::Abs(Offset.Z) <= DefaultExtentUu,
            f"a projection may only answer with a point inside the search box it was given - query {QueryPoint} answered {Result.Get_Location()}, which is outside +/-{DefaultExtentUu}uu");
    }

    UFUNCTION()
    private void Step_ProjectOverVoid(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Query = FCk_NavSurface_ProjectionQuery(VoidPoint);
        Query.Set_Mode(ECk_NavSurface_ProjectionMode::Closest);

        const auto Result = utils_nav_surface::Try_ProjectPoint(Query);

        Assert_True(Result.Get_Status() != ECk_NavSurface_QueryStatus::Success,
            f"there is no walkable surface anywhere near {VoidPoint} - a Success there means the projection is not honouring its search volume");

        Assert_True(Result.Get_Status() == ECk_NavSurface_QueryStatus::NoSurface,
            f"nothing walkable qualified, and the provider is Ready with no filter supplied, so NoSurface is the only correct status - got {Result.Get_Status()}");

        Assert_True(Result.Get_Location() == FVector::ZeroVector,
            f"a failed projection must not hand back a location - got {Result.Get_Location()}");
    }
}
