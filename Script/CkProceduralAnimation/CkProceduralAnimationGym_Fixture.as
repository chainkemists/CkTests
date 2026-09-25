// Language=angelscript

enum ECkProceduralAnimationGym_Course
{
    Flat,
    Uneven,
    RampWall,
    Ring
}

// Scene authoring is shared by the gym and runtime tests. Only production surface-motion
// requests move a creature; the fixture never writes its root transform after creation.
struct FCkProceduralAnimationGym_Crawler
{
    UPROPERTY()
    FCk_Handle Root;
    UPROPERTY()
    FCk_Handle_ProceduralGait Gait;
    UPROPERTY()
    FCk_Handle_SurfaceMotion Motion;
    UPROPERTY()
    FCk_Handle_ProceduralRig Rig;
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
    TArray<FCk_Handle_Transform> VisibleFeet;
    UPROPERTY()
    TArray<bool> SawSwing;
    UPROPERTY()
    TArray<bool> Replanted;

    bool Get_IsReady() const
    {
        return ck::IsValid(Root) && ck::IsValid(Gait) && ck::IsValid(Motion) && ck::IsValid(Rig) &&
            utils_procedural_gait::Get_IsReady(Gait) && utils_surface_motion::Get_IsReady(Motion) &&
            utils_procedural_rig::Get_IsReady(Rig);
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
        if (ck::IsValid(Rig) && utils_procedural_rig::Get_Failure(Rig) != ECk_ProceduralRig_Failure::None)
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

        auto Transform = utils_transform::Get_EntityCurrentTransform(utils_transform::DoCastChecked(Root));
        auto Position = Transform.GetLocation();
        auto Local = Position - Origin;
        FurthestDistance = Math::Max(FurthestDistance, (Position - Start).Size());
        InvalidOutput = InvalidOutput || Position.ContainsNaN();
        // This band is above the ramp's 738 cm landing and below the turnaround. On both
        // ascent and descent, the only supporting surface here is the west face of the wall.
        // It catches contact-frame flip-flop that a single 'saw a wall' sample would miss.
        if (Course == ECkProceduralAnimationGym_Course::RampWall && Local.Z > 950.0 && Local.Z < 1300.0)
        {
            WallSupportSamples++;
            WallSupportLost = WallSupportLost || utils_surface_motion::Get_HasTrustedContact(Motion) == false ||
                utils_surface_motion::Get_SupportNormal(Motion).X > -0.9;
        }

        auto Feet = utils_procedural_gait::Get_Feet(Gait);
        PlantedCount = 0;
        TrustedCount = 0;
        if (Feet.Num() != LegCount)
        {
            InvalidOutput = true;
            return;
        }
        for (auto Index = 0; Index < Feet.Num(); Index++)
        {
            auto Foot = Feet[Index];
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
            auto Hub = Origin + FVector(0.0, 0.0, 911.0);
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
            if (RouteStage == 0 && Local.Z > 1400.0 && SawWall)
            {
                RouteStage = 1;
            }
            else if (RouteStage == 1 && Local.X < -1150.0 && Local.Z < 100.0)
            {
                Traversals++;
                RouteStage = 0;
            }
            auto Target = RouteStage == 0 ? FVector(1215.0, LaneY, 1480.0) : FVector(-1250.0, LaneY, 65.0);
            Direction = Target - Local;
        }
        else
        {
            if (RouteStage == 0 && Local.X > 1150.0)
            {
                RouteStage = 1;
            }
            else if (RouteStage == 1 && Local.X < -1150.0)
            {
                Traversals++;
                RouteStage = 0;
            }
            auto TargetX = RouteStage == 0 ? 1250.0 : -1250.0;
            Direction = FVector(TargetX, LaneY, Local.Z) - Local;
        }

        auto MotionLocal = Motion;
        utils_surface_motion::Request_Steering(MotionLocal,
            FCk_Request_SurfaceMotion_Steering(Direction.GetSafeNormal(), InRun && InvalidOutput == false ? 180.0 : 0.0));
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
        if (Course == ECkProceduralAnimationGym_Course::Ring)
        {
            auto Hub = FVector(0.0, 0.0, 911.0);
            for (auto Index = 0; Index < 24; Index++)
            {
                auto Degrees = -90.0 + 15.0 * Index;
                auto Theta = Math::DegreesToRadians(Degrees);
                auto Radial = FVector(Math::Cos(Theta), 0.0, Math::Sin(Theta));
                auto Shade = Index % 2 == 0 ? GroundColor : FLinearColor(0.18, 0.25, 0.31, 1.0);
                AddSurface(Hub + Radial * 900.0, FRotator(Degrees + 90.0, 0.0, 0.0),
                    FVector(120.0, 540.0, 14.0), Shade);
            }
        }
        else if (Course == ECkProceduralAnimationGym_Course::RampWall)
        {
            AddSurface(FVector(-100.0, 0.0, -25.0), FRotator::ZeroRotator,
                FVector(1400.0, 540.0, 25.0), GroundColor);
            AddSlab(FVector(400.0, 0.0, 0.0), FVector(1280.0, 0.0, 738.4), GroundColor);
            AddSurface(FVector(1300.0, 0.0, 850.0), FRotator::ZeroRotator,
                FVector(20.0, 540.0, 850.0), FLinearColor(0.18, 0.25, 0.31, 1.0));
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
                FVector(1550.0, 540.0, 25.0), GroundColor);
        }
        return true;
    }

    void AddSlab(FVector InStart, FVector InEnd, FLinearColor InColor)
    {
        auto Delta = InEnd - InStart;
        auto Pitch = Math::RadiansToDegrees(Math::Atan2(Delta.Z, Delta.X));
        auto Angle = Math::DegreesToRadians(Pitch);
        auto Normal = FVector(-Math::Sin(Angle), 0.0, Math::Cos(Angle));
        AddSurface((InStart + InEnd) * 0.5 - Normal * 14.0, FRotator(Pitch, 0.0, 0.0),
            FVector(Delta.Size() * 0.5 + 4.0, 540.0, 14.0), InColor);
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
        auto Mesh = Cast<UStaticMesh>(LoadObject(nullptr, "/Engine/BasicShapes/Cube.Cube"));
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

    void SpawnCrawler(int32 InIndex)
    {
        auto Crawler = FCkProceduralAnimationGym_Crawler();
        Crawler.LegCount = 4 + InIndex * 2;
        Crawler.LaneY = RequestedCount == 1 ? 0.0 : (InIndex - 1) * 280.0;
        Crawler.Origin = Origin;
        Crawler.Course = Course;
        Crawler.Color = InIndex == 0 ? FLinearColor(0.1, 0.8, 0.85, 1.0) :
            (InIndex == 1 ? FLinearColor(1.0, 0.58, 0.12, 1.0) : FLinearColor(0.65, 0.35, 1.0, 1.0));
        Crawler.Start = Origin + (Course == ECkProceduralAnimationGym_Course::Ring ?
            FVector(0.0, Crawler.LaneY, 90.0) : FVector(-1200.0, Crawler.LaneY, 65.0));

        // AddVisual composes the root transform before the three runtime features.
        Crawler.Root = AddVisual(SceneRoot, FTransform(Crawler.Start), FVector(42.0, 30.0, 18.0), Crawler.Color);
        Crawler.Root.Request_OverrideToSelf();
        auto CourseName = Course == ECkProceduralAnimationGym_Course::Flat ? "Flat" :
            Course == ECkProceduralAnimationGym_Course::Uneven ? "Uneven" :
            Course == ECkProceduralAnimationGym_Course::RampWall ? "RampWall" : "Ring";
        Crawler.Root.Set_DebugName(FName(f"ProceduralAnimation.{CourseName}.Crawler{Crawler.LegCount}"));

        auto MotionParams = FCk_Fragment_SurfaceMotion_ParamsData();
        MotionParams.Set_Clearance(65.0f);
        MotionParams.Set_ProbeReach(180.0f);
        MotionParams.Set_MaxSpeed(180.0f);
        MotionParams.Set_SurfaceTurnRate(240.0f);
        Crawler.Motion = utils_surface_motion::Add(Crawler.Root, MotionParams);

        auto GaitLegs = TArray<FCk_ProceduralGait_Leg>();
        auto RigLegs = TArray<FCk_ProceduralRig_Leg>();
        for (auto LegIndex = 0; LegIndex < Crawler.LegCount; LegIndex++)
        {
            auto Angle = Math::DegreesToRadians(360.0 * (LegIndex + 0.5) / Crawler.LegCount);
            auto Radial = FVector(Math::Cos(Angle), Math::Sin(Angle), 0.0);
            auto Id = FName(f"Leg{LegIndex}");
            auto GaitLeg = FCk_ProceduralGait_Leg();
            GaitLeg.Set_Id(Id);
            GaitLeg.Set_HipLocal(Radial * 30.0);
            GaitLeg.Set_RestFootLocal(Radial * 100.0 - FVector(0.0, 0.0, 65.0));
            GaitLeg.Set_PhaseOffset(LegIndex % 2 == 0 ? 0.0f : 0.5f);
            GaitLegs.Add(GaitLeg);

            auto Leg = FCk_ProceduralRig_Leg();
            Leg.Set_Id(Id);
            Leg.Set_Upper(AddVisual(Crawler.Root, FTransform(Crawler.Start), FVector(32.5, 8.0, 8.0), Crawler.Color));
            auto LowerColor = Crawler.Color * 0.75;
            LowerColor.A = 1.0;
            Leg.Set_Lower(AddVisual(Crawler.Root, FTransform(Crawler.Start), FVector(42.5, 5.5, 5.5), LowerColor));
            Leg.Set_Foot(AddVisual(Crawler.Root, FTransform(Crawler.Start), FVector(10.0, 9.0, 5.0), FLinearColor(0.8, 0.9, 0.95, 1.0)));
            Crawler.VisibleFeet.Add(Leg.Get_Foot());
            Leg.Set_UpperLength(65.0f);
            Leg.Set_LowerLength(85.0f);
            Leg.Set_PoleLocal(Radial * 100.0 + FVector(0.0, 0.0, 65.0));
            RigLegs.Add(Leg);
            Crawler.SawSwing.Add(false);
            Crawler.Replanted.Add(false);
        }

        auto GaitParams = FCk_Fragment_ProceduralGait_ParamsData();
        GaitParams.Set_Legs(GaitLegs);
        GaitParams.Set_CycleDuration(FCk_Time(0.65));
        GaitParams.Set_StepDuration(FCk_Time(0.22));
        GaitParams.Set_StepHeight(24.0f);
        GaitParams.Set_StepThreshold(30.0f);
        Crawler.Gait = utils_procedural_gait::Add(Crawler.Root, GaitParams);
        auto RigParams = FCk_Fragment_ProceduralRig_ParamsData();
        RigParams.Set_Legs(RigLegs);
        Crawler.Rig = utils_procedural_rig::Add(Crawler.Root, RigParams);
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
            if (Crawlers[Index].InvalidOutput)
            {
                return "FAILED: invalid procedural output";
            }
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
