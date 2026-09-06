// Language=angelscript

//============================================================================
// CK GROUND NAV - AUTOMATION TEST: THE CONTAINMENT COUNTER IS PRODUCED
//============================================================================
//
// FCk_GroundNav_ShadowCounters::_ContainmentEscapes is produced nowhere in the
// query path: it is banked by the crowd's single Transform writer, once per
// agent per frame, whenever the position that pass resolved projects onto
// walkable ground for one of the two providers and onto none for the other.
// Nothing in the shadow REPORT can say whether that producer exists, because a
// zero and an absent producer read identically - which is the whole reason this
// test is here rather than an assertion on a report row.
//
// The split is forced HONESTLY, by geometry, with nothing disabled: the world
// plans on Recast and GroundNav shadows it, the origin field covers the middle
// of the level's floor, and one agent is parked on real Recast navmesh OUTSIDE
// that field. Recast answers Success there, GroundNav answers no surface, and
// the pair is a containment escape on every frame the body stands there.
//
// The second half is what makes the first mean something. The same agent is
// then put back INSIDE the field, where both providers answer Success, and the
// counter must stand perfectly still. A counter that always rises measures
// nothing, and only the pair of readings tells the two apart.
//
// A settle sits between the teleport and the quiet window on purpose: a
// transform move is a REQUEST, so the frame it is issued on is not the frame
// the constrain pass sees the new position, and reading the floor before it
// lands would fold one more escape into the quiet window.
//============================================================================

class UCk_AutoTest_GroundNav_Shadow_ContainmentEscapeIsCounted : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 180.0f;

    //------------------------------------------------------------------------
    // Fixture shape
    //------------------------------------------------------------------------

    // Half the fixture's default, so the level's own Recast ground reaches well
    // past the field's edge: the agent has to stand OUTSIDE the field and ON that
    // ground, and the fixture exposes no reader for the extent it staged.
    private const float FieldHalfXY = 500.0;

    // Past the field's edge and still inside the level's own navmesh bounds
    // volume, which reaches +/-1000 from the floor centre: Recast bakes nothing
    // outside it and erodes its rim, so the point sits 250uu short of the edge
    // and 250uu clear of the field.
    private const float OutsideMarginUu = 250.0;

    private const float AgentRadius = 42.0;
    private const float AgentHeight = 192.0;

    private const float ProjectionExtentUu = 300.0;
    private const float ProjectionVerticalExtentUu = 500.0;

    private const int32 BuildFrameBudget = 3600;
    private const int32 SettleFrameBudget = 900;

    // Long enough that a producer running once per agent per frame cannot be
    // mistaken for one that fired on a single transition edge.
    private const int32 EscapeFrames = 60;

    // The teleport is a request; this is the window it has to land in and the
    // constrain pass has to see the new position through.
    private const int32 TeleportSettleFrames = 30;

    private const FName FixtureName = n"Shadow_ContainmentEscape";

    //------------------------------------------------------------------------
    // Resolved fixture
    //------------------------------------------------------------------------

    private FCkAutoTest_GroundNavFixture _Field;

    private FCk_Handle _SelfHandle;

    private FVector _OutsideLocation = FVector::ZeroVector;
    private FVector _InsideLocation = FVector::ZeroVector;

    private FCk_Handle _AgentEntity;
    private FCk_Handle_Transform _AgentTransform;
    private FCk_Handle_CrowdAgent _Agent;

    private int64 _EscapesAfterOutside = 0;
    private int64 _EscapesAtQuietFloor = 0;

    //------------------------------------------------------------------------
    // World state this test changes and must hand back
    //------------------------------------------------------------------------

    private ECk_NavSurface_Provider _ProviderBefore = ECk_NavSurface_Provider::Recast;
    private ECk_NavSurface_ShadowMode _ShadowModeBefore = ECk_NavSurface_ShadowMode::Off;
    private bool _WorldStateSwapped = false;
    private bool _FixtureOpened = false;

    //------------------------------------------------------------------------
    // Lifecycle
    //------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        _ProviderBefore = utils_nav_surface::Get_Provider();
        _ShadowModeBefore = utils_nav_surface::Get_ShadowMode();

        Add_Step(           "stage a GroundNav field over the origin floor",        n"Step_StageField");
        Add_Step_WaitUntil( "the origin field reports itself built",                n"Check_OriginFieldBuilt", BuildFrameBudget);
        Add_Step(           "plan on Recast and let GroundNav shadow it",           n"Step_ArmShadowing");
        Add_Step_WaitUntil( "the surface settles",                                  n"Check_SurfaceSettled", SettleFrameBudget);
        Add_Step(           "ask the surface and the navmesh to build",              n"Step_KickRebuild");
        Add_Step_WaitUntil( "the level's Recast navmesh answers at the outside point",  n"Check_OutsidePointOnRecast", SettleFrameBudget);
        Add_Step(           "park one agent on navmesh OUTSIDE the field",          n"Step_SpawnAgentOutsideField");
        Add_Step_WaitFrames("let the counter run while the two providers disagree", EscapeFrames);
        Add_Step(           "assert the counter moved",                             n"Step_AssertCounterMoved");
        Add_Step(           "put the same agent back inside the field",             n"Step_MoveAgentInsideField");
        Add_Step_WaitFrames("let the teleport land and the constrain pass see it",  TeleportSettleFrames);
        Add_Step(           "read the quiet floor",                                 n"Step_RecordQuietFloor");
        Add_Step_WaitFrames("watch the counter while both providers agree",         EscapeFrames);
        Add_Step(           "assert the counter stood perfectly still",             n"Step_AssertCounterStood");
        Add_Step(           "hand the world back",                                  n"Step_Cleanup");

        Run_Steps(InHandle);
    }

    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        Teardown();
    }

    //------------------------------------------------------------------------
    // Staging
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_StageField(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        if (_Field.Request_StageOriginField(InHandle, FieldHalfXY) == false)
        {
            FinishFailure(_Field.Get_StagingError());
            return;
        }

        const auto Centre = _Field.Get_FloorCentre();
        const auto SurfaceZ = _Field.Get_FloorTopZ();

        _InsideLocation = FVector(Centre.X, Centre.Y, SurfaceZ);
        _OutsideLocation = FVector(Centre.X + FieldHalfXY + OutsideMarginUu, Centre.Y, SurfaceZ);
    }

    UFUNCTION()
    private void Check_OriginFieldBuilt(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Field.Check_OriginFieldBuilt(InHandle, OutResult, InPayload);
    }

    UFUNCTION()
    private void Check_SurfaceSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Field.Check_SurfaceSettled(InHandle, OutResult, InPayload);
    }

    UFUNCTION()
    private void Step_ArmShadowing(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // The pairing that can be counted at all: the shadowing provider answers alongside the
        // installing one, so a world already planning on GroundNav has no second answer.
        utils_nav_surface::Request_SetProvider(ECk_NavSurface_Provider::Recast);
        _WorldStateSwapped = true;

        utils_ground_nav_shadow::Request_ResetShadowDiagnostics();
        utils_ground_nav_shadow::Request_BeginShadowFixture(FixtureName);
        _FixtureOpened = true;

        utils_nav_surface::Request_SetShadowMode(ECk_NavSurface_ShadowMode::GroundNavShadowsRecast);

        const auto ProviderNow = utils_nav_surface::Get_Provider();
        const auto ShadowNow = utils_nav_surface::Get_ShadowMode();

        Assert_True(ProviderNow == ECk_NavSurface_Provider::Recast,
            f"the world must be planning on Recast for anything to shadow it (got {ProviderNow})");
        Assert_True(ShadowNow == ECk_NavSurface_ShadowMode::GroundNavShadowsRecast,
            f"the world must report the shadow mode it was told to run (got {ShadowNow})");

        const auto EscapesNow = utils_ground_nav_shadow::Get_ShadowContainmentEscapes();

        Assert_True(EscapesNow == 0,
            f"a reset run starts at zero escapes - a rise measured from an unknown floor measures nothing (got {EscapesNow})");

        _Field.Request_KickSettleCount();
    }

    //------------------------------------------------------------------------
    // The disagreeing half
    //------------------------------------------------------------------------

    // The build just asked for lands on its own schedule, so the placement is polled until Recast
    // answers at the point rather than asserted on the first frame.
    // The level's navmesh is dynamic and nothing before this pin is obliged to have built it;
    // the shadow siblings ask for the build the same way.
    UFUNCTION()
    private void Step_KickRebuild(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto LocalHandle = InHandle;

        utils_nav_surface::Request_SurfaceRebuild_ForTesting();
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);
    }

    UFUNCTION()
    private void Check_OutsidePointOnRecast(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Snapped = FVector::ZeroVector;
        auto Res = OutResult;
        Res.Set(utils_nav::Try_ProjectOntoNavmesh(InHandle, _OutsideLocation, float32(ProjectionExtentUu), Snapped, float32(ProjectionVerticalExtentUu)));
    }

    UFUNCTION()
    private void Step_SpawnAgentOutsideField(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // The placement is only honest if the ACTIVE provider genuinely has ground there: an agent
        // off both surfaces is agreement, not divergence, and would count nothing.
        auto Snapped = FVector::ZeroVector;

        if (utils_nav::Try_ProjectOntoNavmesh(InHandle, _OutsideLocation, float32(ProjectionExtentUu), Snapped, float32(ProjectionVerticalExtentUu)) == false)
        {
            FinishFailure(f"staging failed: {_OutsideLocation} is not on the level's Recast navmesh, so the fixture cannot produce a split verdict - the fixture, not the counter, is broken");
            return;
        }

        _OutsideLocation = Snapped;

        Spawn_Agent(_OutsideLocation);
    }

    UFUNCTION()
    private void Step_AssertCounterMoved(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _EscapesAfterOutside = utils_ground_nav_shadow::Get_ShadowContainmentEscapes();

        ck::nav::Display(f"[CROWD-SHADOW-ESCAPE] outside={_OutsideLocation} inside={_InsideLocation} frames={EscapeFrames} escapes={_EscapesAfterOutside}");

        // Half the window rather than all of it: the agent is composed on the frame the step runs and
        // the constrain pass only sees it once its own setup has landed, so the first frames belong
        // to the fixture rather than to the producer.
        const auto HalfWindow = Math::IntegerDivisionTrunc(EscapeFrames, 2);

        Assert_True(_EscapesAfterOutside >= int64(HalfWindow),
            f"an agent standing on Recast ground the GroundNav field does not cover is a split verdict every frame, so {EscapeFrames} frames must bank at least {HalfWindow} escapes (got {_EscapesAfterOutside})");
    }

    //------------------------------------------------------------------------
    // The agreeing half
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_MoveAgentInsideField(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_transform::Request_SetTransform(_AgentTransform,
            FTransform(FRotator::ZeroRotator, _InsideLocation, FVector::OneVector));
    }

    UFUNCTION()
    private void Step_RecordQuietFloor(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _EscapesAtQuietFloor = utils_ground_nav_shadow::Get_ShadowContainmentEscapes();
    }

    UFUNCTION()
    private void Step_AssertCounterStood(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto EscapesNow = utils_ground_nav_shadow::Get_ShadowContainmentEscapes();

        ck::nav::Display(f"[CROWD-SHADOW-ESCAPE] quietFloor={_EscapesAtQuietFloor} afterQuietWindow={EscapesNow} frames={EscapeFrames}");

        Assert_True(EscapesNow == _EscapesAtQuietFloor,
            f"the same agent standing on ground BOTH providers cover is agreement, so {EscapeFrames} frames must bank nothing further (banked {EscapesNow - _EscapesAtQuietFloor})");
    }

    //------------------------------------------------------------------------
    // The agent
    //------------------------------------------------------------------------

    private void Spawn_Agent(FVector InLocation)
    {
        _AgentEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _AgentEntity.Set_DebugName(n"Shadow_ContainmentEscape_Agent");

        _AgentTransform = utils_transform::Add(_AgentEntity,
            FTransform(FRotator::ZeroRotator, InLocation, FVector::OneVector), ECk_Replication::DoesNotReplicate);

        auto Params = FCk_Fragment_CrowdAgent_ParamsData(float32(AgentRadius), float32(AgentHeight));
        _Agent = utils_crowd_agent::Add(_AgentTransform, Params);

        // No MoveTo and no integrator drive: the counter is asked of a POSITION, and a walker would
        // carry itself across the field's edge and blur the two halves into each other.
        utils_velocity::Add(_AgentEntity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(_AgentEntity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);

        Assert_True(ck::IsValid(_Agent), "Add() must return a valid crowd agent handle");
    }

    //------------------------------------------------------------------------
    // Teardown
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_Cleanup(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Teardown();
    }

    private void Teardown()
    {
        if (_FixtureOpened)
        {
            _FixtureOpened = false;
            utils_ground_nav_shadow::Request_EndShadowFixture();
        }

        if (_WorldStateSwapped)
        {
            _WorldStateSwapped = false;
            utils_nav_surface::Request_SetShadowMode(_ShadowModeBefore);
            utils_nav_surface::Request_SetProvider(_ProviderBefore);
        }

        if (ck::IsValid(_AgentEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_AgentEntity);
            _AgentEntity = FCk_Handle();
            _Agent = FCk_Handle_CrowdAgent();
            _AgentTransform = FCk_Handle_Transform();
        }

        _Field.Request_ReleaseOriginField();
    }
}
