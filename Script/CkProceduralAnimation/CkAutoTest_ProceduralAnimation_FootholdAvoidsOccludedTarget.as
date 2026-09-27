// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_FootholdAvoidsOccludedTarget : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private FCk_Handle_ProceduralGait _Gait;
    private TArray<FCk_Handle_ProceduralLeg> _Legs;
    private FVector _Origin = FVector(120000.0, 290000.0, 600.0);
    // The box's faces span Y 40..80 and it stands 200 cm tall, so the +Y hip at Y 30 sees its ideal target on the floor
    // at Y 100 through it.
    private FVector _BoxCentre = FVector(0.0, 60.0, 100.0);
    private FVector _BoxHalfExtents = FVector(20.0, 20.0, 100.0);
    private float _NearFaceY = 40.0;
    private float _BoxTopZ = 200.0;
    // The side rig's rest feet hang this far below its hips, so the -Y ideal target lies on the floor.
    private float _BodyHeight = 65.0;
    private float _OcclusionTolerance = 3.0;
    private float _StartInsideFraction = 0.0001;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        if (_Fixture.Create(InHandle, _Origin, ECkProceduralAnimationGym_Course::Flat, false, 1) == false)
        {
            FinishFailure("The isolated occluder fixture could not be created");
            return;
        }
        // Do not call fixture.Update: only its Jolt floor and the box are needed, and no crawler may spawn.
        _Fixture.AddSurface(_BoxCentre, FRotator::ZeroRotator, _BoxHalfExtents, FLinearColor(0.18, 0.25, 0.31, 1.0));
        Add_Step_WaitUntil("the floor and the box are queryable", n"Check_SurfacesReady");
        Add_Step("compose a gait-only side walker beside the box", n"Step_ComposeGait");
        Add_Step_WaitUntil("the gait publishes its initial planted feet", n"Check_GaitReady");
        Add_Step("verify the +Y foot stands where its hip can see it", n"Step_CheckFeet");
        Add_Step("retire the fixture and the gait", n"Step_Destroy");
        Add_Step_WaitUntil("entities and collision are gone", n"Check_Destroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_SurfacesReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Fixture.Get_AreSurfacesReady());
    }

    UFUNCTION()
    private void Step_ComposeGait(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Owner = _Fixture.SceneRoot;
        auto Root = utils_entity_lifetime::Request_CreateEntity(Owner);
        Root.Request_OverrideToSelf();
        _Fixture.Entities.Add(Root);
        auto Body = utils_transform::Add(Root, FTransform(_Origin + FVector(0.0, 0.0, _BodyHeight)), ECk_Replication::DoesNotReplicate);

        auto Walker = utils_procedural_animation::Add_Walker(Body, ck::ProceduralTest_SideRig, ck::ProceduralGym_Gait,
            TArray<FCk_ProceduralWalker_LegChain>());
        _Gait = Walker.Get_Gait();
        _Legs = Walker.Get_Legs();
        Assert_True(ck::IsValid(_Gait) && _Legs.Num() == 2, "A gait-only side walker is admitted");

        auto HipToIdeal = utils_jolt_query::Get_RayCast(_Origin + FVector(0.0, 30.0, _BodyHeight), _Origin + FVector(0.0, 100.0, 0.0),
            FCk_Jolt_QueryFilter());
        Assert_True(HipToIdeal.Get_HasHit() && HipToIdeal.Get_Fraction() > _StartInsideFraction && HipToIdeal.Get_Fraction() < 0.9,
            "Precondition: the box stands between the +Y hip and its ideal target");
    }

    UFUNCTION()
    private void Check_GaitReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::IsValid(_Gait) && utils_procedural_gait::Get_Status(_Gait) == ECk_ProceduralAnimation_Status::Ready);
    }

    // A held foothold only ever comes from the search, and while the ideal target stays occluded the hold serves from the
    // update after the pick on.
    bool Get_IsSearchSource(ECk_ProceduralLeg_Foothold InSource) const
    {
        return InSource == ECk_ProceduralLeg_Foothold::Front || InSource == ECk_ProceduralLeg_Foothold::Ring
            || InSource == ECk_ProceduralLeg_Foothold::Inward || InSource == ECk_ProceduralLeg_Foothold::Outward
            || InSource == ECk_ProceduralLeg_Foothold::Held;
    }

    UFUNCTION()
    private void Step_CheckFeet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Body = _Origin + FVector(0.0, 0.0, _BodyHeight);
        for (auto Leg : _Legs)
        {
            auto Hip = Body + utils_procedural_leg::Get_Placement(Leg).Get_HipLocal();
            auto Foot = utils_procedural_leg::Get_Foot(Leg);
            auto Local = Foot.Get_Position() - _Origin;
            auto Source = Foot.Get_Foothold();
            auto SourceValue = int32(Source);
            if (Hip.Y < Body.Y)
            {
                Assert_True(Foot.Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted, "The -Y foot is planted");
                Assert_Equals_Float(Local.Z, 0.0, 1.0, "The -Y foot stands on the floor");
                Assert_True(Source == ECk_ProceduralLeg_Foothold::Ideal, f"The -Y foot's target is its ideal (got {SourceValue})");
                continue;
            }

            Assert_True(Foot.Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted && Foot.Get_Contact() == ECk_ProceduralLeg_FootContact::Trusted,
                "The +Y foot is planted on trusted ground");
            auto Sight = utils_jolt_query::Get_RayCast(Hip, Foot.Get_Position(), FCk_Jolt_QueryFilter());
            auto Occluded = Sight.Get_HasHit() && Sight.Get_Fraction() > _StartInsideFraction
                && (Sight.Get_Position() - Foot.Get_Position()).Size() > _OcclusionTolerance;
            Assert_False(Occluded, f"Nothing solid lies between the +Y hip and its foot at {Local.X :.1}, {Local.Y :.1}, {Local.Z :.1}");
            auto InFront = Local.Y < _NearFaceY;
            auto OnTop = Math::Abs(Local.Z - _BoxTopZ) <= 1.0;
            auto OnNearFace = Math::Abs(Local.Y - _NearFaceY) <= 1.0;
            Assert_True(InFront || OnTop || OnNearFace,
                f"The +Y foot stands in front of the box, on its top or on its near face (at {Local.X :.1}, {Local.Y :.1}, {Local.Z :.1})");
            Assert_True(Get_IsSearchSource(Source), f"The +Y foot's target came from the foothold search (got {SourceValue})");
        }
    }

    UFUNCTION()
    private void Step_Destroy(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Fixture.Request_Destroy();
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Fixture.Get_IsDestroyed());
    }
}
