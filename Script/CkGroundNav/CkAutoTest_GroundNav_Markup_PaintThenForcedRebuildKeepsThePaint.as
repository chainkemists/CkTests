// Language=angelscript
//============================================================================
// CK GROUNDNAV - AUTOMATION TEST: A PAINT RACING A FORCED REBUILD IS NOT LOST
//
// The obstacle fixtures paint an impassable box and, in the SAME call, kick
// Request_SurfaceRebuild_ForTesting. On CkGroundNav the paint reaches the
// volume's record one drain later than the build request does, so the build
// snapshots its records without the paint and the paint's own repair is raised
// while that build is already in flight. What must hold: once the surface
// settles, the field carries the hole and the markup reads live. A build that
// publishes over a pending repair it never baked has lost a paint the caller
// was told succeeded.
//
// Same fixture, same probe and same spot as the Settle pin, so a failure here
// and a pass there isolate the one thing this file adds: the kick in the same
// step as the paint.
//============================================================================

class UCk_AutoTest_GroundNav_Markup_PaintThenForcedRebuildKeepsThePaint : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 120.0f;

    private const float SpotOffsetX = 300.0;
    private const float SpotOffsetY = 300.0;

    private const float BlockHalfXY = 150.0;
    private const float BlockHalfZ = 200.0;

    private const FVector ProbeHalfExtents = FVector(60.0, 60.0, 80.0);

    private const int32 BuildFrameBudget = 7200;
    private const int32 SurfaceFrameBudget = 1800;
    private const int32 SettleFrameBudget = 3600;

    private FCkAutoTest_GroundNavFixture _Field;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_NavSurfaceMarkup _Markup;

    private ECk_NavSurface_Provider _ProviderBefore = ECk_NavSurface_Provider::Recast;
    private bool _ProviderSwapped = false;

    private bool _Sampled = false;
    private bool _LiveAtSettled = false;
    private bool _HoleAtSettled = false;
    private int32 _SettledFrames = -1;
    private int64 _RevisionBeforeKick = -1;
    private int64 _RevisionAtSettled = -1;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;
        _ProviderBefore = utils_nav_surface::Get_Provider();

        Add_Step(          "stage a GroundNav field over the origin floor",          n"Step_StageField");
        Add_Step_WaitUntil("the origin field reports itself built",                  n"Check_OriginFieldBuilt",   BuildFrameBudget);
        Add_Step(          "switch the world onto GroundNav",                        n"Step_SwitchProvider");
        Add_Step_WaitUntil("the surface settles after the provider switch",          n"Check_SurfaceSettled",     SurfaceFrameBudget);
        Add_Step(          "the spot projects on bare floor",                        n"Step_AssertSpotProjects");
        Add_Step(          "paint the spot and kick a rebuild in the same step",     n"Step_PaintAndKickRebuild");
        Add_Step_WaitUntil("the surface settles after the paint and the rebuild",    n"Check_SettledAfterKick",   SettleFrameBudget);
        Add_Step(          "the hole is cut and the paint reads live",               n"Step_AssertPaintSurvived");
        Add_Step(          "hand the world back",                                    n"Step_Cleanup");

        Run_Steps(InHandle);
    }

    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        Teardown();
    }

    UFUNCTION()
    private void Step_StageField(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        if (_Field.Request_StageOriginField(_SelfHandle) == false)
        { FinishFailure(_Field.Get_StagingError()); }
    }

    UFUNCTION()
    private void Check_OriginFieldBuilt(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Field.Check_OriginFieldBuilt(InHandle, OutResult, InPayload);
    }

    UFUNCTION()
    private void Step_SwitchProvider(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Field.Request_KickSettleCount();

        utils_nav_surface::Request_SetProvider(ECk_NavSurface_Provider::GroundNav);
        _ProviderSwapped = true;

        const auto ProviderNow = utils_nav_surface::Get_Provider();

        Assert_True(ProviderNow == ECk_NavSurface_Provider::GroundNav,
            f"the world must report the provider it was told to answer on (got {ProviderNow})");
    }

    UFUNCTION()
    private void Check_SurfaceSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Field.Check_SurfaceSettled(InHandle, OutResult, InPayload);
    }

    UFUNCTION()
    private void Step_AssertSpotProjects(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto ProbeReachUu = ProbeHalfExtents.X;

        Assert_True(Get_SpotProjects(),
            f"the origin floor is baked and the world answers on GroundNav, so a projection at the spot with {ProbeReachUu}uu search half-extents must find ground before anything is painted");
    }

    // The paint and the kick land in ONE step, in this order, which is exactly what the obstacle
    // fixtures do. The build request is drained from the volume's own queue on the next tick; the
    // paint travels through the world's markup entity first and reaches the volume a tick after that.
    UFUNCTION()
    private void Step_PaintAndKickRebuild(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Request = FCk_Request_NavSurface_AreaMarkup(
            utils_shapes::Make_Box(
                FCk_ShapeBox_Dimensions(FVector(BlockHalfXY, BlockHalfXY, BlockHalfZ))),
            FGameplayTag());
        Request.Set_WorldTransform(
            FTransform(FRotator::ZeroRotator, Get_SpotCentre(), FVector::OneVector));

        _Markup = utils_nav_surface::Request_ImpassableBox(Request);

        Assert_True(ck::IsValid(_Markup),
            "Request_ImpassableBox hands back the handle the caller needs to observe and release the paint - an invalid one leaves the carve unreachable");

        Track_ForCleanup(FCk_Handle(_Markup));

        _RevisionBeforeKick = utils_nav_surface::Get_SurfaceRevision();

        utils_nav_surface::Request_SurfaceRebuild_ForTesting();

        _Field.Request_KickSettleCount();
    }

    UFUNCTION()
    private void Check_SettledAfterKick(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Field.Check_SurfaceSettled(InHandle, OutResult, InPayload);

        if (utils_shared_bool::Get(OutResult) == false)
        { return; }

        if (_Sampled)
        { return; }

        _Sampled = true;
        _LiveAtSettled = utils_nav_surface::Get_IsMarkupLive(_Markup);
        _HoleAtSettled = !Get_SpotProjects();
        _SettledFrames = _Field.Get_SettledFrames();
        _RevisionAtSettled = utils_nav_surface::Get_SurfaceRevision();
    }

    UFUNCTION()
    private void Step_AssertPaintSurvived(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Frames = _SettledFrames;
        const auto Live = _LiveAtSettled;
        const auto Hole = _HoleAtSettled;
        const auto Before = _RevisionBeforeKick;
        const auto After = _RevisionAtSettled;
        const auto ProbeReachUu = ProbeHalfExtents.X;

        ck::nav::Display(f"[GROUNDNAV-PAINT-RACE] settledFrames={Frames} holeAtSettled={Hole} liveAtSettled={Live} revisionBefore={Before} revisionAfter={After}");

        Assert_True(After > Before,
            f"the kicked rebuild republishes the surface, so the revision has to advance across it (was {Before}, now {After})");

        // Reads the BAKED FIELD: the one assertion a forced-live gate cannot satisfy.
        Assert_True(Hole,
            f"the surface reported itself SETTLED after a paint and a rebuild kicked in the same step, yet a projection at the painted spot with {ProbeReachUu}uu search half-extents still found ground. The build that the kick armed snapshotted its records before the paint reached the volume, and its publish then answered the paint's pending repair without ever baking it - the paint is lost");

        Assert_True(Live,
            "with the surface settled, Get_IsMarkupLive must answer true for the paint - and if the hole assertion above failed too, live here is the facade reporting a paint the field does not carry");
    }

    UFUNCTION()
    private void Step_Cleanup(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Teardown();
    }

    private void Teardown()
    {
        if (_ProviderSwapped)
        {
            _ProviderSwapped = false;
            utils_nav_surface::Request_SetProvider(_ProviderBefore);
        }

        if (ck::IsValid(_Markup))
        {
            utils_entity_lifetime::Request_DestroyEntity(FCk_Handle(_Markup));
            _Markup = FCk_Handle_NavSurfaceMarkup();
        }

        _Field.Request_ReleaseOriginField();
    }

    private FVector Get_SpotCentre()
    {
        const auto Centre = _Field.Get_FloorCentre();

        return FVector(Centre.X + SpotOffsetX, Centre.Y + SpotOffsetY, _Field.Get_FloorTopZ());
    }

    private bool Get_SpotProjects()
    {
        auto Query = FCk_NavSurface_ProjectionQuery(Get_SpotCentre());
        Query.Set_Mode(ECk_NavSurface_ProjectionMode::Closest);
        Query.Set_SearchHalfExtents(ProbeHalfExtents);

        return utils_nav_surface::Try_ProjectPoint(Query).Get_Status() == ECk_NavSurface_QueryStatus::Success;
    }
}

class ACk_AutoTest_GroundNav_Markup_PaintThenForcedRebuildKeepsThePaint_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_GroundNav_Markup_PaintThenForcedRebuildKeepsThePaint;
    default _TimeoutSeconds = 120.0f;
}
