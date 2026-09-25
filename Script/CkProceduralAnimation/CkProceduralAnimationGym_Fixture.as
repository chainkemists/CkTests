// Language=angelscript

enum ECkProceduralAnimationGym_Course
{
    Flat,
    Uneven,
    RampWall,
    Ring
}

namespace ck_procedural_gym
{
    const float CourseHalfWidth = 540.0;
    const float SlabHalfThickness = 14.0;
    const float LaneSpacing = 280.0;
    const float BodyClearance = 65.0;
    const float StartX = -1200.0;
    const float TurnaroundX = 1150.0;
    const float GoalX = 1250.0;
    const FVector RingHub = FVector(0.0, 0.0, 911.0);
    const float RingRadius = 900.0;
    const float RingStartZ = 90.0;
    const float RampLandingZ = 738.4;
    const float WallX = 1300.0;
    const float WallHalfHeight = 850.0;
    const float WallSummitZ = 1400.0;
    const float WallGoalX = 1215.0;
    const float WallGoalZ = 1480.0;
    const float ReturnMaxZ = 100.0;
    // Above the ramp landing and below the turnaround the only supporting surface is the wall's west face.
    const float WallBandMinZ = 950.0;
    const float WallBandMaxZ = 1300.0;

    const float TravelSpeed = 180.0;
    const FVector BodyHalfExtents = FVector(42.0, 30.0, 18.0);
    const FVector FootHalfExtents = FVector(10.0, 9.0, 5.0);
    const float SegmentRootThickness = 8.0;
    const float SegmentTipThickness = 5.5;

    // Ragdoll gets PhysicsBody objects that ignore the Visibility channel the gait and surface-motion
    // probes trace, so released debris never reads as ground for the survivors.
    const FName DebrisCollisionProfile = n"Ragdoll";
    const float DebrisMassKg = 2.0;
    const float DebrisOutwardSpeed = 100.0;
    const float DebrisUpSpeed = 50.0;
    const int32 SlowGaitBelowEnabledLegs = 3;

    UCk_ProceduralRig_Data Get_RigPreset(int32 InLegCount)
    {
        if (InLegCount == 4)
        {
            return ck::ProceduralGym_Rig4;
        }
        if (InLegCount == 6)
        {
            return ck::ProceduralGym_Rig6;
        }
        return ck::ProceduralGym_Rig8;
    }

    UCk_ProceduralGait_Data Get_GaitPreset(int32 InLegCount)
    {
        return InLegCount == 4 ? ck::ProceduralGym_GaitRedistribute : ck::ProceduralGym_Gait;
    }

    FVector Get_SegmentHalfExtents(TArray<float32> InLengths, int32 InSegmentIndex)
    {
        auto Alpha = InLengths.Num() > 1 ? float(InSegmentIndex) / float(InLengths.Num() - 1) : 0.0;
        auto Thickness = Math::Lerp(SegmentRootThickness, SegmentTipThickness, Alpha);
        return FVector(InLengths[InSegmentIndex] * 0.5, Thickness, Thickness);
    }

    FCk_Fragment_SurfaceMotion_ParamsData MakeMotionParams()
    {
        auto Contact = FCk_SurfaceMotion_Contact();
        Contact.Set_Clearance(65.0f);
        Contact.Set_ProbeReach(180.0f);

        auto Movement = FCk_SurfaceMotion_Movement();
        Movement.Set_MaxSpeed(180.0f);
        Movement.Set_SurfaceTurnRate(240.0f);

        auto Params = FCk_Fragment_SurfaceMotion_ParamsData();
        Params.Set_Contact(Contact);
        Params.Set_Movement(Movement);
        return Params;
    }
}

// Scene authoring is shared by the gym and runtime tests. Only production surface-motion
// requests move a creature; the fixture never writes its root transform after creation.
struct FCkProceduralAnimationGym_Crawler
{
    UPROPERTY()
    FCk_Handle_Transform Root;
    UPROPERTY()
    FCk_Handle_ProceduralGait Gait;
    UPROPERTY()
    FCk_Handle_SurfaceMotion Motion;
    UPROPERTY()
    TArray<FCk_Handle_ProceduralLeg> Legs;
    UPROPERTY()
    UCk_ProceduralGait_Data GaitPreset;
    UPROPERTY()
    FVector Origin;
    UPROPERTY()
    FVector Start;
    UPROPERTY()
    FLinearColor Color;
    UPROPERTY()
    ECkProceduralAnimationGym_Course Course;
    UPROPERTY()
    int32 LegCount = 0;
    UPROPERTY()
    float LaneY = 0.0;
    UPROPERTY()
    int32 RouteStage = 0;
    UPROPERTY()
    int32 Traversals = 0;
    UPROPERTY()
    float FurthestDistance = 0.0;
    UPROPERTY()
    int32 PlantedCount = 0;
    UPROPERTY()
    int32 TrustedCount = 0;
    UPROPERTY()
    bool SawWall = false;
    UPROPERTY()
    bool SawCeiling = false;
    UPROPERTY()
    bool InvalidOutput = false;
    UPROPERTY()
    bool WasReady = false;
    UPROPERTY()
    int32 WallSupportSamples = 0;
    UPROPERTY()
    bool WallSupportLost = false;
    UPROPERTY()
    bool SignalsBound = false;
    UPROPERTY()
    bool FirstLegDisabled = false;
    UPROPERTY()
    TArray<FCk_Handle_Transform> VisibleFeet;
    UPROPERTY()
    TArray<bool> SawSwing;
    UPROPERTY()
    TArray<bool> Replanted;

    bool Get_IsReady() const
    {
        if (ck::Is_NOT_Valid(Root) || ck::Is_NOT_Valid(Gait) || ck::Is_NOT_Valid(Motion) || Legs.Num() != LegCount)
        {
            return false;
        }
        if (utils_procedural_gait::Get_IsReady(Gait) == false || utils_surface_motion::Get_IsReady(Motion) == false)
        {
            return false;
        }
        for (auto Leg : Legs)
        {
            if (ck::Is_NOT_Valid(Leg))
            {
                continue;
            }
            auto Rig = utils_procedural_rig::DoCast(Leg);
            if (Rig.IsSet() == false || utils_procedural_rig::Get_IsReady(Rig.GetValue()) == false)
            {
                return false;
            }
        }
        return true;
    }

    bool Get_HasRigFailure() const
    {
        for (auto Leg : Legs)
        {
            if (ck::Is_NOT_Valid(Leg))
            {
                continue;
            }
            auto Rig = utils_procedural_rig::DoCast(Leg);
            if (Rig.IsSet() && utils_procedural_rig::Get_Failure(Rig.GetValue()) != ECk_ProceduralRig_Failure::None)
            {
                return true;
            }
        }
        return false;
    }

    int32 Get_ReplantedCount() const
    {
        auto Count = 0;
        for (auto Value : Replanted)
        {
            if (Value)
            {
                Count++;
            }
        }
        return Count;
    }

    bool Get_HasCompletedCourse() const
    {
        if (Get_IsReady() == false || InvalidOutput || Traversals == 0 || Get_ReplantedCount() != LegCount)
        {
            return false;
        }
        if (Course == ECkProceduralAnimationGym_Course::RampWall)
        {
            return SawWall && WallSupportSamples > 0 && WallSupportLost == false;
        }
        if (Course == ECkProceduralAnimationGym_Course::Ring)
        {
            return SawWall && SawCeiling;
        }
        return true;
    }

    void Update(bool InRun, bool InDraw, bool InLabels)
    {
        if (ck::IsValid(Gait) && utils_procedural_gait::Get_HasFailed(Gait))
        {
            InvalidOutput = true;
        }
        if (Get_HasRigFailure())
        {
            InvalidOutput = true;
        }
        if (Get_IsReady() == false)
        {
            // Startup is pending; losing an initialized production feature is a failure.
            // Otherwise a destroyed limb or rejected runtime input could erase an observed fault
            // behind an indefinitely pending label.
            InvalidOutput = InvalidOutput || WasReady;
            return;
        }
        WasReady = true;

        auto Transform = utils_transform::Get_EntityCurrentTransform(Root);
        auto Position = Transform.GetLocation();
        auto Local = Position - Origin;
        FurthestDistance = Math::Max(FurthestDistance, (Position - Start).Size());
        InvalidOutput = InvalidOutput || Position.ContainsNaN();
        // A band sample catches contact-frame flip-flop that a single 'saw a wall' sample would miss.
        if (Course == ECkProceduralAnimationGym_Course::RampWall && Local.Z > ck_procedural_gym::WallBandMinZ &&
            Local.Z < ck_procedural_gym::WallBandMaxZ)
        {
            WallSupportSamples++;
            WallSupportLost = WallSupportLost || utils_surface_motion::Get_HasTrustedContact(Motion) == false ||
                utils_surface_motion::Get_SupportNormal(Motion).X > -0.9;
        }

        PlantedCount = 0;
        TrustedCount = 0;
        for (auto Index = 0; Index < Legs.Num(); Index++)
        {
            if (ck::Is_NOT_Valid(Legs[Index]))
            {
                continue;
            }
            auto Foot = utils_procedural_leg::Get_Foot(Legs[Index]);
            InvalidOutput = InvalidOutput || Foot.Get_Position().ContainsNaN() || Foot.Get_Normal().ContainsNaN();
            if (Foot.Get_Planted())
            {
                PlantedCount++;
                if (SawSwing[Index] && Foot.Get_ContactTrusted())
                {
                    Replanted[Index] = true;
                }
            }
            else
            {
                SawSwing[Index] = true;
            }
            if (Foot.Get_ContactTrusted())
            {
                TrustedCount++;
                auto Normal = Foot.Get_Normal();
                if (Math::Abs(Normal.Z) < 0.3)
                {
                    SawWall = true;
                }
                if (Normal.Z < -0.7)
                {
                    SawCeiling = true;
                }
            }
            if (InDraw)
            {
                auto FootColor = Foot.Get_Planted() ? FLinearColor::Green : FLinearColor(1.0, 0.5, 0.0, 1.0);
                utils_debug_draw::DrawDebugSphere(Foot.Get_Position(), 7.0, 8, FootColor, 0.0, 1.5);
                utils_debug_draw::DrawDebugLine(Foot.Get_Position(), Foot.Get_Position() + Foot.Get_Normal() * 35.0,
                    FLinearColor(0.0, 1.0, 1.0, 1.0), 0.0, 1.5);
            }
        }

        auto Direction = FVector::ForwardVector;
        if (Course == ECkProceduralAnimationGym_Course::Ring)
        {
            auto Hub = Origin + ck_procedural_gym::RingHub;
            auto Radial = Position - Hub;
            Radial.Y = 0.0;
            Direction = FVector(-Radial.Z, 0.0, Radial.X).GetSafeNormal();
            Direction.Y = Math::Clamp((LaneY - Local.Y) / 150.0, -0.6, 0.6);
            if (RouteStage == 0 && Local.X > 550.0)
            {
                RouteStage = 1;
            }
            else if (RouteStage == 1 && Local.Z > 1500.0)
            {
                RouteStage = 2;
            }
            else if (RouteStage == 2 && Local.X < -550.0)
            {
                RouteStage = 3;
            }
            else if (RouteStage == 3 && Local.Z < 300.0)
            {
                Traversals++;
                RouteStage = 0;
            }
        }
        else if (Course == ECkProceduralAnimationGym_Course::RampWall)
        {
            if (RouteStage == 0 && Local.Z > ck_procedural_gym::WallSummitZ && SawWall)
            {
                RouteStage = 1;
            }
            else if (RouteStage == 1 && Local.X < -ck_procedural_gym::TurnaroundX && Local.Z < ck_procedural_gym::ReturnMaxZ)
            {
                Traversals++;
                RouteStage = 0;
            }
            auto Target = RouteStage == 0 ?
                FVector(ck_procedural_gym::WallGoalX, LaneY, ck_procedural_gym::WallGoalZ) :
                FVector(-ck_procedural_gym::GoalX, LaneY, ck_procedural_gym::BodyClearance);
            Direction = Target - Local;
        }
        else
        {
            if (RouteStage == 0 && Local.X > ck_procedural_gym::TurnaroundX)
            {
                RouteStage = 1;
            }
            else if (RouteStage == 1 && Local.X < -ck_procedural_gym::TurnaroundX)
            {
                Traversals++;
                RouteStage = 0;
            }
            auto TargetX = RouteStage == 0 ? ck_procedural_gym::GoalX : -ck_procedural_gym::GoalX;
            Direction = FVector(TargetX, LaneY, Local.Z) - Local;
        }

        // A zero steering direction is only a valid request at zero speed.
        auto SteerDirection = Direction.GetSafeNormal();
        auto Moving = InRun && InvalidOutput == false && SteerDirection.IsNearlyZero() == false;
        auto MotionLocal = Motion;
        utils_surface_motion::Request_Steering(MotionLocal,
            FCk_Request_SurfaceMotion_Steering(SteerDirection, Moving ? ck_procedural_gym::TravelSpeed : 0.0));
        if (InDraw)
        {
            utils_debug_draw::DrawDebugLine(Position, Position + Transform.GetRotation().GetUpVector() * 110.0,
                Color, 0.0, 3.0);
        }
        if (InLabels)
        {
            utils_debug_draw::DrawDebugString(Position + FVector(0.0, 0.0, 145.0),
                f"{LegCount} legs | {PlantedCount}/{LegCount} planted | laps {Traversals}", Color, 0.0f);
        }
    }
}

struct FCkProceduralAnimationGym_Fixture
{
    UPROPERTY()
    FCk_Handle SceneRoot;
    UPROPERTY()
    TArray<FCk_Handle> Entities;
    UPROPERTY()
    TArray<FCk_Handle_JoltBody> Bodies;
    UPROPERTY()
    TArray<FVector> RetirementProbeStarts;
    UPROPERTY()
    TArray<FVector> RetirementProbeEnds;
    UPROPERTY()
    TArray<FCkProceduralAnimationGym_Crawler> Crawlers;
    UPROPERTY()
    FVector Origin;
    UPROPERTY()
    ECkProceduralAnimationGym_Course Course;
    UPROPERTY()
    bool Render = true;
    UPROPERTY()
    bool SpawnPending = false;
    UPROPERTY()
    int32 RequestedCount = 3;
    // Keep the palette across resets: the factory keys by material identity. Recreating MIDs
    // per reset would accumulate distinct world-lifetime renderer cache entries.
    UPROPERTY()
    TArray<FLinearColor> RendererColors;
    UPROPERTY()
    TArray<UCk_IsmRenderer_Data> Renderers;
    UPROPERTY()
    bool RenderFailed = false;
    UPROPERTY()
    FString CompositionError;
    // A body's impulse is dropped until Jolt has added it, so released debris waits here for its push.
    UPROPERTY()
    TArray<FCk_Handle_JoltBody> PendingDebris;
    UPROPERTY()
    TArray<FVector> PendingDebrisImpulses;

    // Caller first retires the previous fixture and waits for Get_IsDestroyed(). No overlapping
    // old/new collision bodies are hidden under a reset, even when destruction is deferred.
    bool Create(FCk_Handle InOwner, FVector InOrigin, ECkProceduralAnimationGym_Course InCourse,
        bool InRender = true, int32 InCount = 3)
    {
        if (Get_IsDestroyed() == false || ck::Is_NOT_Valid(InOwner) || InCount < 1 || InCount > 3)
        {
            return false;
        }
        Entities.Empty();
        Bodies.Empty();
        RetirementProbeStarts.Empty();
        RetirementProbeEnds.Empty();
        Crawlers.Empty();
        PendingDebris.Empty();
        PendingDebrisImpulses.Empty();
        CompositionError = "";
        auto Owner = InOwner;
        SceneRoot = utils_entity_lifetime::Request_CreateEntity(Owner);
        SceneRoot.Request_OverrideToSelf();
        SceneRoot.Set_DebugName(n"ProceduralAnimation.Fixture");
        Entities.Add(SceneRoot);
        Origin = InOrigin;
        Render = InRender;
        RenderFailed = false;
        Course = InCourse;
        RequestedCount = InCount;
        SpawnPending = true;

        auto GroundColor = FLinearColor(0.12, 0.18, 0.24, 1.0);
        auto HalfWidth = ck_procedural_gym::CourseHalfWidth;
        if (Course == ECkProceduralAnimationGym_Course::Ring)
        {
            for (auto Index = 0; Index < 24; Index++)
            {
                auto Degrees = -90.0 + 15.0 * Index;
                auto Theta = Math::DegreesToRadians(Degrees);
                auto Radial = FVector(Math::Cos(Theta), 0.0, Math::Sin(Theta));
                auto Shade = Index % 2 == 0 ? GroundColor : FLinearColor(0.18, 0.25, 0.31, 1.0);
                AddSurface(ck_procedural_gym::RingHub + Radial * ck_procedural_gym::RingRadius,
                    FRotator(Degrees + 90.0, 0.0, 0.0), FVector(120.0, HalfWidth, ck_procedural_gym::SlabHalfThickness), Shade);
            }
        }
        else if (Course == ECkProceduralAnimationGym_Course::RampWall)
        {
            AddSurface(FVector(-100.0, 0.0, -25.0), FRotator::ZeroRotator,
                FVector(1400.0, HalfWidth, 25.0), GroundColor);
            AddSlab(FVector(400.0, 0.0, 0.0), FVector(1280.0, 0.0, ck_procedural_gym::RampLandingZ), GroundColor);
            AddSurface(FVector(ck_procedural_gym::WallX, 0.0, ck_procedural_gym::WallHalfHeight), FRotator::ZeroRotator,
                FVector(20.0, HalfWidth, ck_procedural_gym::WallHalfHeight), FLinearColor(0.18, 0.25, 0.31, 1.0));
        }
        else if (Course == ECkProceduralAnimationGym_Course::Uneven)
        {
            auto Points = TArray<FVector>();
            Points.Add(FVector(-1500.0, 0.0, 0.0));
            Points.Add(FVector(-900.0, 0.0, 0.0));
            Points.Add(FVector(-300.0, 0.0, 65.0));
            Points.Add(FVector(300.0, 0.0, 0.0));
            Points.Add(FVector(900.0, 0.0, 65.0));
            Points.Add(FVector(1500.0, 0.0, 0.0));
            for (auto Index = 0; Index < Points.Num() - 1; Index++)
            {
                AddSlab(Points[Index], Points[Index + 1], GroundColor);
            }
        }
        else
        {
            AddSurface(FVector(0.0, 0.0, -25.0), FRotator::ZeroRotator,
                FVector(1550.0, HalfWidth, 25.0), GroundColor);
        }
        return true;
    }

    void AddSlab(FVector InStart, FVector InEnd, FLinearColor InColor)
    {
        auto Delta = InEnd - InStart;
        auto Pitch = Math::RadiansToDegrees(Math::Atan2(Delta.Z, Delta.X));
        auto Angle = Math::DegreesToRadians(Pitch);
        auto Normal = FVector(-Math::Sin(Angle), 0.0, Math::Cos(Angle));
        auto Thickness = ck_procedural_gym::SlabHalfThickness;
        AddSurface((InStart + InEnd) * 0.5 - Normal * Thickness, FRotator(Pitch, 0.0, 0.0),
            FVector(Delta.Size() * 0.5 + 4.0, ck_procedural_gym::CourseHalfWidth, Thickness), InColor);
    }

    UCk_IsmRenderer_Data GetOrCreate_Renderer(FLinearColor InColor)
    {
        for (auto Index = 0; Index < RendererColors.Num(); Index++)
        {
            if (RendererColors[Index].Equals(InColor) && ck::IsValid(Renderers[Index]))
            {
                return Renderers[Index];
            }
        }

        auto World = utils_entity_lifetime::Get_WorldForEntity(SceneRoot);
        auto Mesh = Cast<UStaticMesh>(utils_i_o::LoadAssetByName("/Engine/BasicShapes/Cube.Cube",
            ECk_AssetSearchScope::Engine)._Asset);
        if (ck::Is_NOT_Valid(World) || ck::Is_NOT_Valid(Mesh))
        {
            RenderFailed = true;
            return nullptr;
        }
        // PMG debug fills deliberately force 10% opacity. Real mesh proxies use the existing
        // opaque, ISM-compatible CkUsf master instead; its actual parameters are ColorA/ColorB.
        auto Material = utils_usf::Create_MID_ForLook(CkUsf::LitMetal, World);
        if (ck::Is_NOT_Valid(Material))
        {
            RenderFailed = true;
            return nullptr;
        }
        utils_usf::Set_Vector(Material, n"ColorA", InColor);
        utils_usf::Set_Vector(Material, n"ColorB", InColor);
        utils_usf::Set_Scalar(Material, n"Tiles", 0.0f);
        auto Overrides = TArray<FCk_MeshMaterialOverride>();
        Overrides.Add(FCk_MeshMaterialOverride(0, Material));
        auto Renderer = utils_ism_renderer_transient_factory::GetOrCreate_ForMeshWithMaterials(
            World, Mesh, Overrides, ECk_Mobility::Movable);
        if (ck::Is_NOT_Valid(Renderer))
        {
            RenderFailed = true;
            return nullptr;
        }
        RendererColors.Add(InColor);
        Renderers.Add(Renderer);
        return Renderer;
    }

    FCk_Handle_Transform AddVisual(FCk_Handle InOwner, FTransform InTransform, FVector InExtents,
        FLinearColor InColor)
    {
        auto Owner = InOwner;
        auto Entity = utils_entity_lifetime::Request_CreateEntity(Owner);
        auto Transform = utils_transform::Add(Entity, InTransform, ECk_Replication::DoesNotReplicate);
        if (Render)
        {
            auto Renderer = GetOrCreate_Renderer(InColor);
            if (ck::IsValid(Renderer))
            {
                auto Params = FCk_Fragment_IsmProxy_ParamsData(Renderer);
                // Engine cube: 100cm side / 50cm half-extent. Render scale belongs on the proxy,
                // never the ECS root: gait/IK and Jolt use the unscaled transform in both modes.
                Params.Set_ScaleMultiplier(InExtents / 50.0);
                utils_ism_proxy::Add(Transform, Params);
            }
        }
        Entities.Add(Entity);
        return Transform;
    }

    void AddSurface(FVector InLocation, FRotator InRotation, FVector InHalfExtents, FLinearColor InColor)
    {
        FCk_Handle Entity = AddVisual(SceneRoot, FTransform(InRotation, Origin + InLocation), InHalfExtents, InColor);
        auto Shape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        Shape.Set_HalfExtents(InHalfExtents);
        auto Params = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        Params.Set_ShapeDimensions(Shape);
        Params.Set_MotionType(ECk_MotionType::Static);
        Params.Set_CollisionProfileName(n"BlockAll");
        Bodies.Add(utils_jolt_body::Add(Entity, Params));
        // Sample through the center of each owned solid. Entity retirement and physics removal
        // can be separate passes; a reset must observe BOTH before publishing replacement geometry.
        auto ProbeAxis = InRotation.RotateVector(FVector::UpVector);
        auto ProbeHalfLength = InHalfExtents.Z + 2.0;
        RetirementProbeStarts.Add(Origin + InLocation + ProbeAxis * ProbeHalfLength);
        RetirementProbeEnds.Add(Origin + InLocation - ProbeAxis * ProbeHalfLength);
    }

    bool Get_AreSurfacesReady() const
    {
        if (Bodies.IsEmpty())
        {
            return false;
        }
        for (auto Body : Bodies)
        {
            if (ck::Is_NOT_Valid(Body) || utils_jolt_body::Get_IsBodyAdded(Body) == false)
            {
                return false;
            }
        }
        return true;
    }

    bool Get_IsReady() const
    {
        if (SpawnPending || Crawlers.Num() != RequestedCount)
        {
            return false;
        }
        for (auto Index = 0; Index < Crawlers.Num(); Index++)
        {
            if (Crawlers[Index].Get_IsReady() == false)
            {
                return false;
            }
        }
        return Get_AreSurfacesReady();
    }

    FCk_ProceduralWalker_LegChain MakeLegChain(FCkProceduralAnimationGym_Crawler& InOutCrawler,
        FCk_Fragment_ProceduralLeg_ParamsData InLeg)
    {
        auto Lengths = InLeg.Get_Chain().Get_SegmentLengths();
        auto Segments = TArray<FCk_Handle_Transform>();
        for (auto SegmentIndex = 0; SegmentIndex < Lengths.Num(); SegmentIndex++)
        {
            auto Tint = Lengths.Num() > 1 ? float(SegmentIndex) / float(Lengths.Num() - 1) : 0.0;
            auto Shade = InOutCrawler.Color * (1.0 - 0.25 * Tint);
            Shade.A = 1.0;
            Segments.Add(AddVisual(InOutCrawler.Root, FTransform(InOutCrawler.Start),
                ck_procedural_gym::Get_SegmentHalfExtents(Lengths, SegmentIndex), Shade));
        }
        auto Foot = AddVisual(InOutCrawler.Root, FTransform(InOutCrawler.Start), ck_procedural_gym::FootHalfExtents,
            FLinearColor(0.8, 0.9, 0.95, 1.0));
        InOutCrawler.VisibleFeet.Add(Foot);

        auto RigParams = FCk_Fragment_ProceduralRig_ParamsData();
        RigParams.Set_Segments(Segments);
        RigParams.Set_Foot(Foot);
        return FCk_ProceduralWalker_LegChain(InLeg.Get_Id(), RigParams);
    }

    void SpawnCrawler(int32 InIndex)
    {
        auto Crawler = FCkProceduralAnimationGym_Crawler();
        Crawler.LegCount = 4 + InIndex * 2;
        Crawler.LaneY = RequestedCount == 1 ? 0.0 : (InIndex - 1) * ck_procedural_gym::LaneSpacing;
        Crawler.Origin = Origin;
        Crawler.Course = Course;
        Crawler.Color = InIndex == 0 ? FLinearColor(0.1, 0.8, 0.85, 1.0) :
            (InIndex == 1 ? FLinearColor(1.0, 0.58, 0.12, 1.0) : FLinearColor(0.65, 0.35, 1.0, 1.0));
        Crawler.Start = Origin + (Course == ECkProceduralAnimationGym_Course::Ring ?
            FVector(0.0, Crawler.LaneY, ck_procedural_gym::RingStartZ) :
            FVector(ck_procedural_gym::StartX, Crawler.LaneY, ck_procedural_gym::BodyClearance));

        // AddVisual composes the root transform before the runtime features.
        auto RootEntity = FCk_Handle(AddVisual(SceneRoot, FTransform(Crawler.Start), ck_procedural_gym::BodyHalfExtents,
            Crawler.Color));
        RootEntity.Request_OverrideToSelf();
        auto CourseName = Course == ECkProceduralAnimationGym_Course::Flat ? "Flat" :
            Course == ECkProceduralAnimationGym_Course::Uneven ? "Uneven" :
            Course == ECkProceduralAnimationGym_Course::RampWall ? "RampWall" : "Ring";
        RootEntity.Set_DebugName(FName(f"ProceduralAnimation.{CourseName}.Crawler{Crawler.LegCount}"));
        Crawler.Root = utils_transform::DoCastChecked(RootEntity);

        Crawler.Motion = utils_surface_motion::Add(Crawler.Root, ck_procedural_gym::MakeMotionParams());

        auto RigPreset = ck_procedural_gym::Get_RigPreset(Crawler.LegCount);
        Crawler.GaitPreset = ck_procedural_gym::Get_GaitPreset(Crawler.LegCount);
        auto Chains = TArray<FCk_ProceduralWalker_LegChain>();
        for (auto LegParams : RigPreset.Get_Legs())
        {
            Chains.Add(MakeLegChain(Crawler, LegParams));
            Crawler.SawSwing.Add(false);
            Crawler.Replanted.Add(false);
        }

        auto Walker = utils_procedural_animation::Add_Walker(Crawler.Root, RigPreset, Crawler.GaitPreset, Chains);
        Crawler.Gait = Walker.Get_Gait();
        Crawler.Legs = Walker.Get_Legs();
        if (ck::Is_NOT_Valid(Crawler.Motion) || ck::Is_NOT_Valid(Crawler.Gait) || Crawler.Legs.Num() != Crawler.LegCount)
        {
            CompositionError = f"{CourseName} crawler with {Crawler.LegCount} legs: surface motion or walker composition was rejected";
        }
        Crawlers.Add(Crawler);
    }

    void Update(bool InRun = true, bool InDraw = false)
    {
        if (ck::Is_NOT_Valid(SceneRoot))
        {
            return;
        }
        if (SpawnPending)
        {
            if (Get_AreSurfacesReady() == false)
            {
                return;
            }
            for (auto Index = 0; Index < RequestedCount; Index++)
            {
                SpawnCrawler(Index);
            }
            SpawnPending = false;
        }
        for (auto Index = 0; Index < Crawlers.Num(); Index++)
        {
            Crawlers[Index].Update(InRun, InDraw, Render);
        }
        ApplyPendingDebrisImpulses();
    }

    bool Get_OwnsLeg(FCk_Handle_ProceduralLeg InLeg) const
    {
        auto Leg = FCk_Handle(InLeg);
        for (auto Crawler : Crawlers)
        {
            for (auto Candidate : Crawler.Legs)
            {
                if (FCk_Handle(Candidate) == Leg)
                {
                    return true;
                }
            }
        }
        return false;
    }

    // The game-side ragdoll recipe for a detached leg: every released part becomes a dynamic Jolt body
    // sized like its visual, then gets a small outward push once Jolt has added it.
    void Request_RagdollReleasedParts(FCk_Handle_ProceduralLeg InLeg, FCk_ProceduralLeg_ReleasedParts InReleasedParts)
    {
        auto Lengths = utils_procedural_leg::Get_ChainGeometry(InLeg).Get_SegmentLengths();
        auto Chain = utils_procedural_rig::Get_Chain(utils_procedural_rig::DoCastChecked(InLeg));
        auto Body = utils_entity_lifetime::Get_LifetimeOwner(InLeg);
        auto BodyLocation = utils_transform::Get_EntityCurrentLocation(utils_transform::DoCastChecked(Body));
        for (auto Part : InReleasedParts.Get_Parts())
        {
            auto HalfExtents = ck_procedural_gym::FootHalfExtents;
            for (auto SegmentIndex = 0; SegmentIndex < Chain.Get_Segments().Num(); SegmentIndex++)
            {
                if (FCk_Handle(Chain.Get_Segments()[SegmentIndex]) == FCk_Handle(Part))
                {
                    HalfExtents = ck_procedural_gym::Get_SegmentHalfExtents(Lengths, SegmentIndex);
                }
            }

            auto Shape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
            Shape.Set_HalfExtents(HalfExtents);
            auto Params = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
            Params.Set_ShapeDimensions(Shape);
            Params.Set_MotionType(ECk_MotionType::Dynamic);
            Params.Set_MassSource(ECk_JoltBody_MassSource::Explicit);
            Params.Set_MassKg(ck_procedural_gym::DebrisMassKg);
            Params.Set_CollisionProfileName(ck_procedural_gym::DebrisCollisionProfile);
            auto PartEntity = FCk_Handle(Part);
            auto Debris = utils_jolt_body::Add(PartEntity, Params);

            auto Outward = utils_transform::Get_EntityCurrentLocation(Part) - BodyLocation;
            Outward.Z = 0.0;
            auto Velocity = Outward.GetSafeNormal() * ck_procedural_gym::DebrisOutwardSpeed +
                FVector::UpVector * ck_procedural_gym::DebrisUpSpeed;
            PendingDebris.Add(Debris);
            PendingDebrisImpulses.Add(Velocity * ck_procedural_gym::DebrisMassKg);
        }
    }

    void ApplyPendingDebrisImpulses()
    {
        for (auto Index = PendingDebris.Num() - 1; Index >= 0; Index--)
        {
            auto Debris = PendingDebris[Index];
            if (ck::IsValid(Debris) && utils_jolt_body::Get_IsBodyAdded(Debris) == false)
            {
                continue;
            }
            if (ck::IsValid(Debris))
            {
                utils_jolt_body::Request_AddImpulse(Debris, FCk_Request_JoltBody_AddImpulse(PendingDebrisImpulses[Index]));
            }
            PendingDebris.RemoveAt(Index);
            PendingDebrisImpulses.RemoveAt(Index);
        }
    }

    void Request_ToggleFirstLeg()
    {
        for (auto Index = 0; Index < Crawlers.Num(); Index++)
        {
            if (Crawlers[Index].Legs.Num() == 0 || ck::Is_NOT_Valid(Crawlers[Index].Legs[0]))
            {
                continue;
            }
            auto Disable = Crawlers[Index].FirstLegDisabled == false;
            Crawlers[Index].FirstLegDisabled = Disable;
            auto Leg = Crawlers[Index].Legs[0];
            utils_procedural_leg::Request_EnableDisable(Leg,
                FCk_Request_ProceduralLeg_EnableDisable(Disable ? ECk_EnableDisable::Disable : ECk_EnableDisable::Enable));
        }
    }

    bool Request_DetachLeg(int32 InCrawlerIndex, int32 InLegIndex)
    {
        if (Crawlers.IsValidIndex(InCrawlerIndex) == false || Crawlers[InCrawlerIndex].Legs.IsValidIndex(InLegIndex) == false)
        {
            return false;
        }
        auto Leg = Crawlers[InCrawlerIndex].Legs[InLegIndex];
        if (ck::Is_NOT_Valid(Leg))
        {
            return false;
        }
        utils_procedural_leg::Request_Detach(Leg,
            FCk_Request_ProceduralLeg_Detach(ECk_ProceduralLeg_ReleasedPartsOwnership::KeepBodyOwned));
        return true;
    }

    void Request_Destroy()
    {
        SpawnPending = false;
        if (ck::IsValid(SceneRoot))
        {
            utils_entity_lifetime::Request_DestroyEntity(SceneRoot);
        }
    }

    bool Get_IsDestroyed() const
    {
        for (auto Entity : Entities)
        {
            if (ck::IsValid(Entity))
            {
                return false;
            }
        }
        for (auto Index = 0; Index < RetirementProbeStarts.Num(); Index++)
        {
            auto Hit = utils_jolt_query::Get_RayCast(RetirementProbeStarts[Index], RetirementProbeEnds[Index], FCk_Jolt_QueryFilter());
            if (Hit.Get_HasHit())
            {
                return false;
            }
        }
        return true;
    }

    bool Get_HasObservedWalking() const
    {
        if (Get_IsReady() == false)
        {
            return false;
        }
        for (auto Index = 0; Index < Crawlers.Num(); Index++)
        {
            auto Crawler = Crawlers[Index];
            if (Crawler.InvalidOutput || Crawler.FurthestDistance < 150.0 ||
                Crawler.Get_ReplantedCount() != Crawler.LegCount ||
                utils_surface_motion::Get_IsGrounded(Crawler.Motion) == false)
            {
                return false;
            }
        }
        return true;
    }

    FString Get_Verdict() const
    {
        if (CompositionError.IsEmpty() == false)
        {
            return f"FAILED: {CompositionError}";
        }
        if (RenderFailed)
        {
            return "FAILED: solid renderer or master material unavailable";
        }
        for (auto Crawler : Crawlers)
        {
            if (Crawler.InvalidOutput)
            {
                return "FAILED: procedural output or readiness lost";
            }
        }
        if (Get_IsReady() == false)
        {
            return "Pending: collision and rigs initializing";
        }
        auto Completed = 0;
        for (auto Index = 0; Index < Crawlers.Num(); Index++)
        {
            if (Crawlers[Index].Get_HasCompletedCourse())
            {
                Completed++;
            }
        }
        if (Completed == Crawlers.Num() && Get_HasObservedWalking())
        {
            return "Observed: every rig completed this course";
        }
        if (Get_HasObservedWalking())
        {
            return f"Walking observed; courses completed {Completed}/{Crawlers.Num()}";
        }
        return "Pending: waiting for displacement and completed foot steps";
    }
}
