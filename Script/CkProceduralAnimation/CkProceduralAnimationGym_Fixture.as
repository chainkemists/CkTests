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

    FCk_SurfaceMotion_Spec MakeMotionParams()
    {
        auto Contact = FCk_SurfaceMotion_Contact();
        Contact.Set_Clearance(65.0f);
        Contact.Set_ProbeReach(180.0f);

        auto Movement = FCk_SurfaceMotion_Movement();
        Movement.Set_MaxSpeed(180.0f);
        Movement.Set_SurfaceTurnRate(240.0f);

        auto Params = FCk_SurfaceMotion_Spec();
        Params.Set_Contact(Contact);
        Params.Set_Movement(Movement);
        return Params;
    }
}

struct FCkProceduralAnimationGym_CrawlerHandles
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
    TArray<FCk_Handle_Transform> VisibleFeet;
}

struct FCkProceduralAnimationGym_CrawlerLayout
{
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
}

struct FCkProceduralAnimationGym_CrawlerProgress
{
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
    bool WasReady = false;
}

struct FCkProceduralAnimationGym_CrawlerEvidence
{
    UPROPERTY()
    bool SawWall = false;
    UPROPERTY()
    bool SawCeiling = false;
    UPROPERTY()
    int32 WallSupportSamples = 0;
    UPROPERTY()
    bool WallSupportLost = false;
    UPROPERTY()
    bool InvalidOutput = false;
    UPROPERTY()
    TArray<bool> SawSwing;
    UPROPERTY()
    TArray<bool> Replanted;
}

// Scene authoring is shared by the gym and runtime tests. Only production surface-motion
// requests move a creature; the fixture never writes its root transform after creation.
struct FCkProceduralAnimationGym_Crawler
{
    UPROPERTY()
    FCkProceduralAnimationGym_CrawlerHandles Handles;
    UPROPERTY()
    FCkProceduralAnimationGym_CrawlerLayout Layout;
    UPROPERTY()
    FCkProceduralAnimationGym_CrawlerProgress Progress;
    UPROPERTY()
    FCkProceduralAnimationGym_CrawlerEvidence Evidence;
    UPROPERTY()
    bool SignalsBound = false;
    UPROPERTY()
    bool FirstLegDisabled = false;

    bool Get_AllReady() const
    {
        if (ck::Is_NOT_Valid(Handles.Root) || ck::Is_NOT_Valid(Handles.Gait) || ck::Is_NOT_Valid(Handles.Motion) || Handles.Legs.Num() != Layout.LegCount)
        {
            return false;
        }
        if (utils_procedural_gait::Get_Status(Handles.Gait) != ECk_ProceduralAnimation_Status::Ready ||
            utils_surface_motion::Get_Status(Handles.Motion) != ECk_ProceduralAnimation_Status::Ready)
        {
            return false;
        }
        for (auto Leg : Handles.Legs)
        {
            if (ck::Is_NOT_Valid(Leg))
            {
                continue;
            }
            auto Rig = utils_procedural_rig::DoCast(Leg);
            if (Rig.IsSet() == false || utils_procedural_rig::Get_Status(Rig.GetValue()) != ECk_ProceduralAnimation_Status::Ready)
            {
                return false;
            }
        }
        return true;
    }

    bool Get_HasRigFailure() const
    {
        for (auto Leg : Handles.Legs)
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
        for (auto Value : Evidence.Replanted)
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
        if (Get_AllReady() == false || Evidence.InvalidOutput || Progress.Traversals == 0 || Get_ReplantedCount() != Layout.LegCount)
        {
            return false;
        }
        if (Layout.Course == ECkProceduralAnimationGym_Course::RampWall)
        {
            return Evidence.SawWall && Evidence.WallSupportSamples > 0 && Evidence.WallSupportLost == false;
        }
        if (Layout.Course == ECkProceduralAnimationGym_Course::Ring)
        {
            return Evidence.SawWall && Evidence.SawCeiling;
        }
        return true;
    }

    void Update(bool InRun, bool InDraw, bool InLabels)
    {
        if (ck::IsValid(Handles.Gait) && utils_procedural_gait::Get_Status(Handles.Gait) == ECk_ProceduralAnimation_Status::Failed)
        {
            Evidence.InvalidOutput = true;
        }
        if (Get_HasRigFailure())
        {
            Evidence.InvalidOutput = true;
        }
        if (Get_AllReady() == false)
        {
            // Startup is pending; losing an initialized production feature is a failure.
            // Otherwise a destroyed limb or rejected runtime input could erase an observed fault
            // behind an indefinitely pending label.
            Evidence.InvalidOutput = Evidence.InvalidOutput || Progress.WasReady;
            return;
        }
        Progress.WasReady = true;

        auto Transform = utils_transform::Get_EntityCurrentTransform(Handles.Root);
        auto Position = Transform.GetLocation();
        auto Local = Position - Layout.Origin;
        Progress.FurthestDistance = Math::Max(Progress.FurthestDistance, (Position - Layout.Start).Size());
        Evidence.InvalidOutput = Evidence.InvalidOutput || Position.ContainsNaN();
        // A band sample catches contact-frame flip-flop that a single 'saw a wall' sample would miss.
        if (Layout.Course == ECkProceduralAnimationGym_Course::RampWall && Local.Z > ck_procedural_gym::WallBandMinZ &&
            Local.Z < ck_procedural_gym::WallBandMaxZ)
        {
            Evidence.WallSupportSamples++;
            Evidence.WallSupportLost = Evidence.WallSupportLost || utils_surface_motion::Get_ContactQuery(Handles.Motion) != ECk_SurfaceMotion_ContactQuery::Trusted ||
                utils_surface_motion::Get_SupportNormal(Handles.Motion).X > -0.9;
        }

        Progress.PlantedCount = 0;
        Progress.TrustedCount = 0;
        for (auto Index = 0; Index < Handles.Legs.Num(); Index++)
        {
            if (ck::Is_NOT_Valid(Handles.Legs[Index]))
            {
                continue;
            }
            auto Foot = utils_procedural_leg::Get_Foot(Handles.Legs[Index]);
            Evidence.InvalidOutput = Evidence.InvalidOutput || Foot.Get_Position().ContainsNaN() || Foot.Get_Normal().ContainsNaN();
            if (Foot.Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted)
            {
                Progress.PlantedCount++;
                if (Evidence.SawSwing[Index] && Foot.Get_Contact() == ECk_ProceduralLeg_FootContact::Trusted)
                {
                    Evidence.Replanted[Index] = true;
                }
            }
            else
            {
                Evidence.SawSwing[Index] = true;
            }
            if (Foot.Get_Contact() == ECk_ProceduralLeg_FootContact::Trusted)
            {
                Progress.TrustedCount++;
                auto Normal = Foot.Get_Normal();
                if (Math::Abs(Normal.Z) < 0.3)
                {
                    Evidence.SawWall = true;
                }
                if (Normal.Z < -0.7)
                {
                    Evidence.SawCeiling = true;
                }
            }
            if (InDraw)
            {
                auto FootColor = Foot.Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted ? FLinearColor::Green : FLinearColor(1.0, 0.5, 0.0, 1.0);
                utils_debug_draw::DrawDebugSphere(Foot.Get_Position(), 7.0, 8, FootColor, 0.0, 1.5);
                utils_debug_draw::DrawDebugLine(Foot.Get_Position(), Foot.Get_Position() + Foot.Get_Normal() * 35.0,
                    FLinearColor(0.0, 1.0, 1.0, 1.0), 0.0, 1.5);
            }
        }

        auto Direction = FVector::ForwardVector;
        if (Layout.Course == ECkProceduralAnimationGym_Course::Ring)
        {
            auto Hub = Layout.Origin + ck_procedural_gym::RingHub;
            auto Radial = Position - Hub;
            Radial.Y = 0.0;
            Direction = FVector(-Radial.Z, 0.0, Radial.X).GetSafeNormal();
            Direction.Y = Math::Clamp((Layout.LaneY - Local.Y) / 150.0, -0.6, 0.6);
            if (Progress.RouteStage == 0 && Local.X > 550.0)
            {
                Progress.RouteStage = 1;
            }
            else if (Progress.RouteStage == 1 && Local.Z > 1500.0)
            {
                Progress.RouteStage = 2;
            }
            else if (Progress.RouteStage == 2 && Local.X < -550.0)
            {
                Progress.RouteStage = 3;
            }
            else if (Progress.RouteStage == 3 && Local.Z < 300.0)
            {
                Progress.Traversals++;
                Progress.RouteStage = 0;
            }
        }
        else if (Layout.Course == ECkProceduralAnimationGym_Course::RampWall)
        {
            if (Progress.RouteStage == 0 && Local.Z > ck_procedural_gym::WallSummitZ && Evidence.SawWall)
            {
                Progress.RouteStage = 1;
            }
            else if (Progress.RouteStage == 1 && Local.X < -ck_procedural_gym::TurnaroundX && Local.Z < ck_procedural_gym::ReturnMaxZ)
            {
                Progress.Traversals++;
                Progress.RouteStage = 0;
            }
            auto Target = Progress.RouteStage == 0 ?
                FVector(ck_procedural_gym::WallGoalX, Layout.LaneY, ck_procedural_gym::WallGoalZ) :
                FVector(-ck_procedural_gym::GoalX, Layout.LaneY, ck_procedural_gym::BodyClearance);
            Direction = Target - Local;
        }
        else
        {
            if (Progress.RouteStage == 0 && Local.X > ck_procedural_gym::TurnaroundX)
            {
                Progress.RouteStage = 1;
            }
            else if (Progress.RouteStage == 1 && Local.X < -ck_procedural_gym::TurnaroundX)
            {
                Progress.Traversals++;
                Progress.RouteStage = 0;
            }
            auto TargetX = Progress.RouteStage == 0 ? ck_procedural_gym::GoalX : -ck_procedural_gym::GoalX;
            Direction = FVector(TargetX, Layout.LaneY, Local.Z) - Local;
        }

        // A zero steering direction is only a valid request at zero speed.
        auto SteerDirection = Direction.GetSafeNormal();
        auto Moving = InRun && Evidence.InvalidOutput == false && SteerDirection.IsNearlyZero() == false;
        auto MotionLocal = Handles.Motion;
        utils_surface_motion::Request_Steering(MotionLocal,
            FCk_Request_SurfaceMotion_Steering(SteerDirection, Moving ? ck_procedural_gym::TravelSpeed : 0.0));
        if (InDraw)
        {
            utils_debug_draw::DrawDebugLine(Position, Position + Transform.GetRotation().GetUpVector() * 110.0,
                Layout.Color, 0.0, 3.0);
        }
        if (InLabels)
        {
            utils_debug_draw::DrawDebugString(Position + FVector(0.0, 0.0, 145.0),
                f"{Layout.LegCount} legs | {Progress.PlantedCount}/{Layout.LegCount} planted | laps {Progress.Traversals}", Layout.Color, 0.0f);
        }
    }
}

struct FCkProceduralAnimationGym_Rendering
{
    UPROPERTY()
    bool Render = true;
    // Keep the palette across resets: the factory keys by material identity. Recreating MIDs
    // per reset would accumulate distinct world-lifetime renderer cache entries.
    UPROPERTY()
    TArray<FLinearColor> RendererColors;
    UPROPERTY()
    TArray<UCk_IsmRenderer_Data> Renderers;
    UPROPERTY()
    bool RenderFailed = false;
}

// A body's impulse is dropped until Jolt has added it, so released debris waits here for its push.
struct FCkProceduralAnimationGym_Debris
{
    UPROPERTY()
    TArray<FCk_Handle_JoltBody> Bodies;
    UPROPERTY()
    TArray<FVector> Impulses;
}

struct FCkProceduralAnimationGym_RetirementProbes
{
    UPROPERTY()
    TArray<FVector> Starts;
    UPROPERTY()
    TArray<FVector> Ends;
}

struct FCkProceduralAnimationGym_SpawnRequest
{
    UPROPERTY()
    FVector Origin;
    UPROPERTY()
    ECkProceduralAnimationGym_Course Course;
    UPROPERTY()
    bool Pending = false;
    UPROPERTY()
    int32 Count = 3;
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
    FCkProceduralAnimationGym_RetirementProbes RetirementProbes;
    UPROPERTY()
    TArray<FCkProceduralAnimationGym_Crawler> Crawlers;
    UPROPERTY()
    FCkProceduralAnimationGym_SpawnRequest Spawn;
    UPROPERTY()
    FCkProceduralAnimationGym_Rendering Rendering;
    UPROPERTY()
    FString CompositionError;
    UPROPERTY()
    FCkProceduralAnimationGym_Debris Debris;

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
        RetirementProbes.Starts.Empty();
        RetirementProbes.Ends.Empty();
        Crawlers.Empty();
        Debris.Bodies.Empty();
        Debris.Impulses.Empty();
        CompositionError = "";
        auto Owner = InOwner;
        SceneRoot = utils_entity_lifetime::Request_CreateEntity(Owner);
        SceneRoot.Request_OverrideToSelf();
        SceneRoot.Set_DebugName(n"ProceduralAnimation.Fixture");
        Entities.Add(SceneRoot);
        Spawn.Origin = InOrigin;
        Rendering.Render = InRender;
        Rendering.RenderFailed = false;
        Spawn.Course = InCourse;
        Spawn.Count = InCount;
        Spawn.Pending = true;

        auto GroundColor = FLinearColor(0.12, 0.18, 0.24, 1.0);
        auto HalfWidth = ck_procedural_gym::CourseHalfWidth;
        if (Spawn.Course == ECkProceduralAnimationGym_Course::Ring)
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
        else if (Spawn.Course == ECkProceduralAnimationGym_Course::RampWall)
        {
            AddSurface(FVector(-100.0, 0.0, -25.0), FRotator::ZeroRotator,
                FVector(1400.0, HalfWidth, 25.0), GroundColor);
            AddSlab(FVector(400.0, 0.0, 0.0), FVector(1280.0, 0.0, ck_procedural_gym::RampLandingZ), GroundColor);
            AddSurface(FVector(ck_procedural_gym::WallX, 0.0, ck_procedural_gym::WallHalfHeight), FRotator::ZeroRotator,
                FVector(20.0, HalfWidth, ck_procedural_gym::WallHalfHeight), FLinearColor(0.18, 0.25, 0.31, 1.0));
        }
        else if (Spawn.Course == ECkProceduralAnimationGym_Course::Uneven)
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
        for (auto Index = 0; Index < Rendering.RendererColors.Num(); Index++)
        {
            if (Rendering.RendererColors[Index].Equals(InColor) && ck::IsValid(Rendering.Renderers[Index]))
            {
                return Rendering.Renderers[Index];
            }
        }

        auto World = utils_entity_lifetime::Get_WorldForEntity(SceneRoot);
        auto Mesh = Cast<UStaticMesh>(utils_i_o::LoadAssetByName("/Engine/BasicShapes/Cube.Cube",
            ECk_AssetSearchScope::Engine)._Asset);
        if (ck::Is_NOT_Valid(World) || ck::Is_NOT_Valid(Mesh))
        {
            Rendering.RenderFailed = true;
            return nullptr;
        }
        // PMG debug fills deliberately force 10% opacity. Real mesh proxies use the existing
        // opaque, ISM-compatible CkUsf master instead; its actual parameters are ColorA/ColorB.
        auto Material = utils_usf::Create_MID_ForLook(CkUsf::LitMetal, World);
        if (ck::Is_NOT_Valid(Material))
        {
            Rendering.RenderFailed = true;
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
            Rendering.RenderFailed = true;
            return nullptr;
        }
        Rendering.RendererColors.Add(InColor);
        Rendering.Renderers.Add(Renderer);
        return Renderer;
    }

    FCk_Handle_Transform AddVisual(FCk_Handle InOwner, FTransform InTransform, FVector InExtents,
        FLinearColor InColor)
    {
        auto Owner = InOwner;
        auto Entity = utils_entity_lifetime::Request_CreateEntity(Owner);
        auto Transform = utils_transform::Add(Entity, InTransform, ECk_Replication::DoesNotReplicate);
        if (Rendering.Render)
        {
            auto Renderer = GetOrCreate_Renderer(InColor);
            if (ck::IsValid(Renderer))
            {
                auto Params = FCk_IsmProxy_Spec(Renderer);
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
        FCk_Handle Entity = AddVisual(SceneRoot, FTransform(InRotation, Spawn.Origin + InLocation), InHalfExtents, InColor);
        auto Shape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        Shape.Set_HalfExtents(InHalfExtents);
        auto Params = FCk_JoltBody_Spec(ECk_JoltBody_ShapeSource::ExplicitShape);
        Params.Set_ShapeDimensions(Shape);
        Params.Set_MotionType(ECk_MotionType::Static);
        Params.Set_CollisionProfileName(n"BlockAll");
        Bodies.Add(utils_jolt_body::Add(Entity, Params));
        // Sample through the center of each owned solid. Entity retirement and physics removal
        // can be separate passes; a reset must observe BOTH before publishing replacement geometry.
        auto ProbeAxis = InRotation.RotateVector(FVector::UpVector);
        auto ProbeHalfLength = InHalfExtents.Z + 2.0;
        RetirementProbes.Starts.Add(Spawn.Origin + InLocation + ProbeAxis * ProbeHalfLength);
        RetirementProbes.Ends.Add(Spawn.Origin + InLocation - ProbeAxis * ProbeHalfLength);
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

    bool Get_AllReady() const
    {
        if (Spawn.Pending || Crawlers.Num() != Spawn.Count)
        {
            return false;
        }
        for (auto Index = 0; Index < Crawlers.Num(); Index++)
        {
            if (Crawlers[Index].Get_AllReady() == false)
            {
                return false;
            }
        }
        return Get_AreSurfacesReady();
    }

    FCk_ProceduralWalker_LegChain MakeLegChain(FCkProceduralAnimationGym_Crawler& InOutCrawler,
        FCk_ProceduralLeg_Spec InLeg)
    {
        auto Lengths = InLeg.Get_Chain().Get_SegmentLengths();
        auto Segments = TArray<FCk_Handle_Transform>();
        for (auto SegmentIndex = 0; SegmentIndex < Lengths.Num(); SegmentIndex++)
        {
            auto Tint = Lengths.Num() > 1 ? float(SegmentIndex) / float(Lengths.Num() - 1) : 0.0;
            auto Shade = InOutCrawler.Layout.Color * (1.0 - 0.25 * Tint);
            Shade.A = 1.0;
            Segments.Add(AddVisual(InOutCrawler.Handles.Root, FTransform(InOutCrawler.Layout.Start),
                ck_procedural_gym::Get_SegmentHalfExtents(Lengths, SegmentIndex), Shade));
        }
        auto Foot = AddVisual(InOutCrawler.Handles.Root, FTransform(InOutCrawler.Layout.Start), ck_procedural_gym::FootHalfExtents,
            FLinearColor(0.8, 0.9, 0.95, 1.0));
        InOutCrawler.Handles.VisibleFeet.Add(Foot);

        auto RigParams = FCk_ProceduralRig_Spec();
        RigParams.Set_Segments(Segments);
        RigParams.Set_Foot(Foot);
        return FCk_ProceduralWalker_LegChain(InLeg.Get_Id(), RigParams);
    }

    void SpawnCrawler(int32 InIndex)
    {
        auto Crawler = FCkProceduralAnimationGym_Crawler();
        Crawler.Layout.LegCount = 4 + InIndex * 2;
        Crawler.Layout.LaneY = Spawn.Count == 1 ? 0.0 : (InIndex - 1) * ck_procedural_gym::LaneSpacing;
        Crawler.Layout.Origin = Spawn.Origin;
        Crawler.Layout.Course = Spawn.Course;
        Crawler.Layout.Color = InIndex == 0 ? FLinearColor(0.1, 0.8, 0.85, 1.0) :
            (InIndex == 1 ? FLinearColor(1.0, 0.58, 0.12, 1.0) : FLinearColor(0.65, 0.35, 1.0, 1.0));
        Crawler.Layout.Start = Spawn.Origin + (Spawn.Course == ECkProceduralAnimationGym_Course::Ring ?
            FVector(0.0, Crawler.Layout.LaneY, ck_procedural_gym::RingStartZ) :
            FVector(ck_procedural_gym::StartX, Crawler.Layout.LaneY, ck_procedural_gym::BodyClearance));

        // AddVisual composes the root transform before the runtime features.
        auto RootEntity = FCk_Handle(AddVisual(SceneRoot, FTransform(Crawler.Layout.Start), ck_procedural_gym::BodyHalfExtents,
            Crawler.Layout.Color));
        RootEntity.Request_OverrideToSelf();
        auto CourseName = Spawn.Course == ECkProceduralAnimationGym_Course::Flat ? "Flat" :
            Spawn.Course == ECkProceduralAnimationGym_Course::Uneven ? "Uneven" :
            Spawn.Course == ECkProceduralAnimationGym_Course::RampWall ? "RampWall" : "Ring";
        RootEntity.Set_DebugName(FName(f"ProceduralAnimation.{CourseName}.Crawler{Crawler.Layout.LegCount}"));
        Crawler.Handles.Root = utils_transform::DoCastChecked(RootEntity);

        Crawler.Handles.Motion = utils_surface_motion::Add(Crawler.Handles.Root, ck_procedural_gym::MakeMotionParams());

        auto RigPreset = ck_procedural_gym::Get_RigPreset(Crawler.Layout.LegCount);
        Crawler.Layout.GaitPreset = ck_procedural_gym::Get_GaitPreset(Crawler.Layout.LegCount);
        auto Chains = TArray<FCk_ProceduralWalker_LegChain>();
        for (auto LegParams : RigPreset.Get_Legs())
        {
            Chains.Add(MakeLegChain(Crawler, LegParams));
            Crawler.Evidence.SawSwing.Add(false);
            Crawler.Evidence.Replanted.Add(false);
        }

        auto Walker = utils_procedural_animation::Add_Walker(Crawler.Handles.Root, RigPreset, Crawler.Layout.GaitPreset, Chains);
        Crawler.Handles.Gait = Walker.Get_Gait();
        Crawler.Handles.Legs = Walker.Get_Legs();
        if (ck::Is_NOT_Valid(Crawler.Handles.Motion) || ck::Is_NOT_Valid(Crawler.Handles.Gait) || Crawler.Handles.Legs.Num() != Crawler.Layout.LegCount)
        {
            CompositionError = f"{CourseName} crawler with {Crawler.Layout.LegCount} legs: surface motion or walker composition was rejected";
        }
        Crawlers.Add(Crawler);
    }

    void Update(bool InRun = true, bool InDraw = false)
    {
        if (ck::Is_NOT_Valid(SceneRoot))
        {
            return;
        }
        if (Spawn.Pending)
        {
            if (Get_AreSurfacesReady() == false)
            {
                return;
            }
            for (auto Index = 0; Index < Spawn.Count; Index++)
            {
                SpawnCrawler(Index);
            }
            Spawn.Pending = false;
        }
        for (auto Index = 0; Index < Crawlers.Num(); Index++)
        {
            Crawlers[Index].Update(InRun, InDraw, Rendering.Render);
        }
        ApplyPendingDebrisImpulses();
    }

    bool Get_OwnsLeg(FCk_Handle_ProceduralLeg InLeg) const
    {
        auto Leg = FCk_Handle(InLeg);
        for (auto Crawler : Crawlers)
        {
            for (auto Candidate : Crawler.Handles.Legs)
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
            auto Params = FCk_JoltBody_Spec(ECk_JoltBody_ShapeSource::ExplicitShape);
            Params.Set_ShapeDimensions(Shape);
            Params.Set_MotionType(ECk_MotionType::Dynamic);
            Params.Set_MassSource(ECk_JoltBody_MassSource::Explicit);
            Params.Set_MassKg(ck_procedural_gym::DebrisMassKg);
            Params.Set_CollisionProfileName(ck_procedural_gym::DebrisCollisionProfile);
            auto PartEntity = FCk_Handle(Part);
            auto DebrisBody = utils_jolt_body::Add(PartEntity, Params);

            auto Outward = utils_transform::Get_EntityCurrentLocation(Part) - BodyLocation;
            Outward.Z = 0.0;
            auto Velocity = Outward.GetSafeNormal() * ck_procedural_gym::DebrisOutwardSpeed +
                FVector::UpVector * ck_procedural_gym::DebrisUpSpeed;
            Debris.Bodies.Add(DebrisBody);
            Debris.Impulses.Add(Velocity * ck_procedural_gym::DebrisMassKg);
        }
    }

    void ApplyPendingDebrisImpulses()
    {
        for (auto Index = Debris.Bodies.Num() - 1; Index >= 0; Index--)
        {
            auto DebrisBody = Debris.Bodies[Index];
            if (ck::IsValid(DebrisBody) && utils_jolt_body::Get_IsBodyAdded(DebrisBody) == false)
            {
                continue;
            }
            if (ck::IsValid(DebrisBody))
            {
                utils_jolt_body::Request_AddImpulse(DebrisBody, FCk_Request_JoltBody_AddImpulse(Debris.Impulses[Index]));
            }
            Debris.Bodies.RemoveAt(Index);
            Debris.Impulses.RemoveAt(Index);
        }
    }

    void Request_ToggleFirstLeg()
    {
        for (auto Index = 0; Index < Crawlers.Num(); Index++)
        {
            if (Crawlers[Index].Handles.Legs.Num() == 0 || ck::Is_NOT_Valid(Crawlers[Index].Handles.Legs[0]))
            {
                continue;
            }
            auto Disable = Crawlers[Index].FirstLegDisabled == false;
            Crawlers[Index].FirstLegDisabled = Disable;
            auto Leg = Crawlers[Index].Handles.Legs[0];
            utils_procedural_leg::Request_EnableDisable(Leg,
                FCk_Request_ProceduralLeg_EnableDisable(Disable ? ECk_EnableDisable::Disable : ECk_EnableDisable::Enable));
        }
    }

    bool Request_DetachLeg(int32 InCrawlerIndex, int32 InLegIndex)
    {
        if (Crawlers.IsValidIndex(InCrawlerIndex) == false || Crawlers[InCrawlerIndex].Handles.Legs.IsValidIndex(InLegIndex) == false)
        {
            return false;
        }
        auto Leg = Crawlers[InCrawlerIndex].Handles.Legs[InLegIndex];
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
        Spawn.Pending = false;
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
        for (auto Index = 0; Index < RetirementProbes.Starts.Num(); Index++)
        {
            auto Hit = utils_jolt_query::Get_RayCast(RetirementProbes.Starts[Index], RetirementProbes.Ends[Index], FCk_Jolt_QueryFilter());
            if (Hit.Get_HasHit())
            {
                return false;
            }
        }
        return true;
    }

    bool Get_HasObservedWalking() const
    {
        if (Get_AllReady() == false)
        {
            return false;
        }
        for (auto Index = 0; Index < Crawlers.Num(); Index++)
        {
            auto Crawler = Crawlers[Index];
            if (Crawler.Evidence.InvalidOutput || Crawler.Progress.FurthestDistance < 150.0 ||
                Crawler.Get_ReplantedCount() != Crawler.Layout.LegCount ||
                utils_surface_motion::Get_Support(Crawler.Handles.Motion) != ECk_SurfaceMotion_Support::Grounded)
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
        if (Rendering.RenderFailed)
        {
            return "FAILED: solid renderer or master material unavailable";
        }
        for (auto Crawler : Crawlers)
        {
            if (Crawler.Evidence.InvalidOutput)
            {
                return "FAILED: procedural output or readiness lost";
            }
        }
        if (Get_AllReady() == false)
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
