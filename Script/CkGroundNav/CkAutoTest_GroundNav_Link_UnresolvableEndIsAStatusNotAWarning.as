// Language=angelscript

//============================================================================
// CK GROUND NAV - AUTOMATION TEST: AN UNRESOLVED LINK IS A STATUS, NOT A WARNING
//============================================================================
//
// A link whose end finds no ground is an ordinary authoring state, not a defect:
// levels are authored before they are baked, and a link over a piece of the
// world nobody has built yet has to survive until something does. The contract
// is that such a link is REPORTED rather than complained about - a count on the
// volume, a per-end status in the resolved entry, and Get_IsLinkLive answering
// false - and that its record is never lost.
//
//----------------------------------------------------------------------------
// THE HARNESS IS THE ASSERTION
//----------------------------------------------------------------------------
//
// The AutoTest harness escalates a Warning into a test failure. So the claim
// "a dropped link never warns" needs no assertion of its own: if the composer
// ever raised one, this file would go red naming it. Everything asserted below
// exists to prove the run actually REACHED that state - a test that authored no
// link, or whose link quietly resolved after all, would also finish green and
// would prove nothing.
//
//----------------------------------------------------------------------------
// WHY THE END HANGS IN THE AIR RATHER THAN OFF THE SIDE
//----------------------------------------------------------------------------
//
// Admission refuses an endpoint outside the volume's bounds, so an unresolvable
// end has to be inside the volume and still over nothing. On this fixture the
// volume's horizontal extent and the ground under it coincide - the level's
// origin floor reaches further than the volume does on every horizontal side -
// so there is no XY inside the volume that is off the field. The VERTICAL span
// is where the two differ: the volume reaches 400uu above the floor's top face,
// and a projection reaches only as far as the record's own vertical extent. An
// end 300uu up with a 100uu reach is inside the volume, over built ground, and
// out of reach of it, which resolves NoSurface rather than Unbuilt.
//
// Both projection extents are written on the record rather than left to their
// defaults: the geometry argument above is about specific numbers, and a default
// that moved later would turn this pin into one that passes for a reason nobody
// wrote down.
//============================================================================

class UCk_AutoTest_GroundNav_Link_UnresolvableEndIsAStatusNotAWarning : UCk_AutoTest_Base
{
    // A 16-tile bake of the origin floor plus two kicked settles, each on its own budgeted condition.
    default _TimeoutSeconds = 240.0f;

    //------------------------------------------------------------------------
    // Geometry, as offsets from the floor's own centre and top face
    //------------------------------------------------------------------------

    private const float StartOffsetX = -300.0;
    private const float StartOffsetY = -300.0;

    private const float EndOffsetX = 300.0;
    private const float EndOffsetY = -300.0;

    // Inside the volume, which reaches 400uu above the floor's top face, and further above the ground
    // than the vertical reach below can see.
    private const float EndRiseUu = 300.0;

    private const float ProjectionHorizontalExtentUu = 50.0;
    private const float ProjectionVerticalExtentUu = 100.0;

    //------------------------------------------------------------------------
    // Budgets - every one is a ceiling on a NAMED condition, never a settle.
    //------------------------------------------------------------------------

    private const int32 BuildFrameBudget = 7200;
    private const int32 SurfaceFrameBudget = 1800;
    private const int32 SettleFrameBudget = 3600;

    //------------------------------------------------------------------------
    // Fixture
    //------------------------------------------------------------------------

    private FCkAutoTest_GroundNavFixture _Field;

    private FCk_Handle _SelfHandle;
    private FCk_Handle _LinkEntity;

    //------------------------------------------------------------------------
    // World state this test changes and must hand back
    //------------------------------------------------------------------------

    private ECk_NavSurface_Provider _ProviderBefore = ECk_NavSurface_Provider::Recast;
    private bool _ProviderSwapped = false;

    //------------------------------------------------------------------------
    // Bookkeeping and the samples taken at the FIRST poll that answers settled
    //------------------------------------------------------------------------

    private int32 _LinkCompletions = 0;
    private ECk_Request_OperationResult _LastLinkResult = ECk_Request_OperationResult::Failed;

    private bool _Sampled = false;
    private bool _LiveAtSettled = true;
    private int32 _UnresolvedAtSettled = -1;
    private int32 _RecordsAtSettled = -1;
    private int32 _SettledFrames = -1;

    //------------------------------------------------------------------------
    // Reporting state
    //------------------------------------------------------------------------

    private FString _Verdict = "incomplete";
    private bool _Reported = false;

    //------------------------------------------------------------------------
    // Lifecycle
    //------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // Captured BEFORE anything can fail, so DoEndPlay always has something to put back.
        _ProviderBefore = utils_nav_surface::Get_Provider();

        Add_Step(          "stage a GroundNav field over the origin floor",     n"Step_StageField");
        Add_Step_WaitUntil("the origin field reports itself built",             n"Check_OriginFieldBuilt", BuildFrameBudget);
        Add_Step(          "switch the world onto GroundNav",                   n"Step_SwitchProvider");
        Add_Step_WaitUntil("the surface settles after the provider switch",     n"Check_SurfaceSettled",   SurfaceFrameBudget);
        Add_Step(          "author a link whose end hangs over nothing",        n"Step_AuthorHangingLink");
        Add_Step_WaitUntil("the surface settles after the link",                n"Check_SettledAfterLink", SettleFrameBudget);
        Add_Step(          "the hanging end is reported, not complained about", n"Step_AssertHeldAsStatus");
        Add_Step(          "hand the world back",                               n"Step_Cleanup");

        Run_Steps(InHandle);
    }

    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        Teardown();
    }

    //------------------------------------------------------------------------
    // Staging - the fixture owns the field, this test owns the provider
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_StageField(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        if (_Field.Request_StageOriginField(_SelfHandle) == false)
        { FinishFailure(_Field.Get_StagingError()); }
    }

    // The fixture exposes predicate BODIES, not UFUNCTIONs: Do_EvaluatePredicate binds the named
    // predicate against THIS object, so every wait below needs its own one-line forwarder here.
    UFUNCTION()
    private void Check_OriginFieldBuilt(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Field.Check_OriginFieldBuilt(InHandle, OutResult, InPayload);
    }

    UFUNCTION()
    private void Step_SwitchProvider(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // Kicked before the mutation, so the number reported afterwards measures THIS switch rather
        // than every poll since staging.
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

    //------------------------------------------------------------------------
    // The link with nowhere to land
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AuthorHangingLink(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Volume = _Field.Get_OriginVolume();

        Assert_True(ck::IsValid(Volume),
            "the fixture must hand back a valid volume before a link can be authored against it");

        _LinkEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _LinkEntity.Request_OverrideToSelf();
        _LinkEntity.Set_DebugName(n"AutoTest_GroundNav_HangingLink");

        // The id is -1 because the VOLUME assigns it: the record's identity carries no setter.
        auto Record = FCk_GroundNav_LinkRecord(-1, Get_StartPoint(), Get_EndPoint());

        Record.Set_Direction(ECk_GroundNav_LinkDirection::Bidirectional)
              .Set_ProjectionMode(ECk_NavSurface_ProjectionMode::Closest)
              .Set_ProjectionHorizontalExtentUu(float32(ProjectionHorizontalExtentUu))
              .Set_ProjectionVerticalExtentUu(float32(ProjectionVerticalExtentUu));

        utils_ground_nav_volume::Request_Link(Volume,
            FCk_Request_GroundNavVolume_Link(_LinkEntity, Record),
            FCk_Delegate_Request_OnCompleted(this, n"OnLinkCompleted"));

        _Field.Request_KickSettleCount();
    }

    UFUNCTION()
    private void OnLinkCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _LinkCompletions += 1;
        _LastLinkResult = InResult;
    }

    UFUNCTION()
    private void Check_SettledAfterLink(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Field.Check_SurfaceSettled(InHandle, OutResult, InPayload);

        if (utils_shared_bool::Get(OutResult) == false)
        { return; }

        if (_Sampled)
        { return; }

        auto Volume = _Field.Get_OriginVolume();

        _Sampled = true;
        _LiveAtSettled = utils_ground_nav_volume::Get_IsLinkLive(_LinkEntity);
        _UnresolvedAtSettled = utils_ground_nav_volume::Get_UnresolvedLinkCount(Volume);
        _RecordsAtSettled = utils_ground_nav_volume::Get_LinkRecords(Volume).Num();
        _SettledFrames = _Field.Get_SettledFrames();
    }

    UFUNCTION()
    private void Step_AssertHeldAsStatus(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Frames = _SettledFrames;
        const auto Live = _LiveAtSettled;
        const auto Unresolved = _UnresolvedAtSettled;
        const auto Records = _RecordsAtSettled;

        ck::nav::Display(f"[GROUNDNAV-LINK] hanging end: settledFrames={Frames} liveAtSettled={Live} unresolvedLinks={Unresolved} records={Records}");

        // The POSITIVE the rest of the file rests on: a link that was never admitted would satisfy
        // every assertion below by never existing.
        Assert_Equals_Int(_LinkCompletions, 1,
            "the link request's completion delegate must fire exactly once");

        Assert_True(_LastLinkResult == ECk_Request_OperationResult::Succeeded,
            f"a link whose ends reach no baked ground is still ADMITTED - the volume owns what was authored, and where its two points stand is the composition's separate answer, so admission must complete Succeeded (got {_LastLinkResult})");

        Assert_Equals_Int(Unresolved, 1,
            "one authored link has an end that found no ground, and the count of links with an end that did not resolve is exactly how a dropped link is reported. It reads otherwise, so either the end resolved after all - and this pin is measuring nothing - or the count does not answer for it.");

        Assert_False(Live,
            "a link that did not resolve is not there at all, which is the one way liveness is narrower for a link than for a markup: a markup that reaches nothing is admitted and simply decides nothing. Get_IsLinkLive answering true over an unresolved end would route an agent onto ground that does not carry it.");

        Assert_Equals_Int(Records, 1,
            "authored data is never lost to a resolution that failed: the record stays on the volume so the next publish over that ground can resolve it, and only the field's graph drops it");
    }

    //------------------------------------------------------------------------
    // Geometry
    //------------------------------------------------------------------------

    private FVector Get_StartPoint()
    {
        const auto Centre = _Field.Get_FloorCentre();
        return FVector(Centre.X + StartOffsetX, Centre.Y + StartOffsetY, _Field.Get_FloorTopZ());
    }

    private FVector Get_EndPoint()
    {
        const auto Centre = _Field.Get_FloorCentre();
        return FVector(Centre.X + EndOffsetX, Centre.Y + EndOffsetY, _Field.Get_FloorTopZ() + EndRiseUu);
    }

    //------------------------------------------------------------------------
    // Teardown
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_Cleanup(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Verdict = "green";

        Teardown();
    }

    // Idempotent, and called from BOTH the conclusion and DoEndPlay. The provider is a WORLD selection
    // every later fixture in this map reads, and the fixture's field - plus any floor body it pushed
    // into the Jolt static world - would otherwise stay staged for the rest of the lane.
    private void Teardown()
    {
        if (_Reported == false)
        {
            _Reported = true;
            _Field.Do_ReportCrossover("Link_UnresolvableEndIsAStatusNotAWarning", _Verdict);
        }

        if (_ProviderSwapped)
        {
            _ProviderSwapped = false;
            utils_nav_surface::Request_SetProvider(_ProviderBefore);
        }

        if (ck::IsValid(_LinkEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_LinkEntity);
            _LinkEntity = FCk_Handle();
        }

        _Field.Request_ReleaseOriginField();
    }
}
