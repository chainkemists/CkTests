// Language=angelscript

enum ECkProceduralAnimationGym_Species
{
    Crawler4,
    Crawler6,
    Crawler8,
    Spider,
    Centipede,
    Tentacled,
    Beast,
    Biped
}

enum ECkProceduralAnimationGym_Course
{
    Flat,
    Uneven,
    RampWall,
    Ring,
    Stairs,
    Rubble,
    Hump,
    StepField,
    Ledge,
    Ridge,
    Log,
    Beam,
    Pillars,
    Spin,
    PillarCrossing,
    Posts,
    Cylinder
}

// SpinThenRoute turns the walker in place before it walks the course's route. Helix climbs the lane's cylinder, circles
// up and down it, climbs off and walks back.
enum ECkProceduralAnimationGym_Patrol
{
    Route,
    SpinThenRoute,
    Helix
}

// Which surface-motion height source a fixture composes its walkers with: each species' own, or one for every walker.
enum ECkProceduralAnimationGym_HeightSource
{
    Species,
    Rays,
    PlantedFeet
}

struct FCkProceduralAnimationGym_SpeciesProfile
{
    UPROPERTY()
    UCk_ProceduralRig_Data Rig;
    UPROPERTY()
    UCk_ProceduralGait_Data Gait;
    UPROPERTY()
    float Clearance = 65.0;
    UPROPERTY()
    float CollapseDrop = 45.0;
    UPROPERTY()
    FVector BodyHalfExtents;
    UPROPERTY()
    float SurfaceTurnRate = 240.0;
    // Two feet never fit a plane, so the biped keeps to its rays.
    UPROPERTY()
    ECk_SurfaceMotion_HeightSource HeightSource = ECk_SurfaceMotion_HeightSource::PlantedFeet;
}

namespace ck_procedural_gym
{
    const float NarrowCourseHalfWidth = 540.0;
    const float WideCourseHalfWidth = 660.0;
    const float SlabHalfThickness = 14.0;
    const float NarrowLaneSpacing = 280.0;
    const float WideLaneSpacing = 380.0;
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
    const float StairRun = 70.0;
    // Half a run plus 1 cm, so neighbouring treads overlap and no seam opens between the boxes.
    const float StairHalfTread = 36.0;
    const int32 StairsUpSteps = 6;
    const float StairsUpRise = 20.0;
    const int32 StairsDownSteps = 3;
    const float StairsDownRise = 30.0;
    const float StairsLandingHalfLength = 220.0;
    const float StairsLandingZ = 120.0;
    const int32 RubbleCount = 36;
    const float RubbleHalfSpanX = 1000.0;
    const float RubbleEdgeMargin = 80.0;
    const float RubbleMaxTilt = 8.0;
    // A raised-cosine profile leaves and rejoins the floor tangentially, so the only thing the walkers negotiate is
    // curvature: no corner at the foot of the hump and no slope step larger than the facet resolution.
    const float HumpTopZ = 300.0;
    const float HumpHalfWidth = 700.0;
    const float HumpFacetLength = 25.0;
    // Solid enough that no probe can start under a facet's top face and fall through to the floor below.
    const float HumpSlabHalfThickness = 60.0;

    const float StepFieldTread = 60.0;
    const float LedgeHalfLength = 150.0;
    const float LedgeHeight = 150.0;
    const float RidgeHalfBase = 150.0;
    const float RidgeHeight = 150.0;
    const float RidgeSlabHalfThickness = 60.0;
    const float LogRadius = 80.0;
    const int32 LogFacets = 32;
    // Each facet's slab reaches the axis, so no probe can start in a hollow core.
    const float LogSlabHalfThickness = 40.0;
    const float BeamHalfLength = 1000.0;
    const float BeamHalfWidth = 15.0;
    const float BeamHeight = 60.0;
    const float PillarHalfSize = 20.0;
    const float PillarHeight = 200.0;
    const float PillarSpacing = 150.0;
    const float PillarHalfSpanX = 900.0;
    // Three spacings, so with the rows half a spacing off the centre line every lane threads a corridor between two rows.
    const float PillarsLaneSpacing = 450.0;
    const float CrossingRampRun = 300.0;
    const float CrossingHeight = 150.0;
    const float CrossingPillarHalfSize = 25.0;
    const float CrossingPillarPitch = 100.0;
    const float CrossingFieldHalfSpanX = 450.0;
    const float CrossingLandingHalfLength = 50.0;
    // Solid enough that no probe can start under a ramp's top face and fall through to the floor below.
    const float CrossingRampSlabHalfThickness = 60.0;
    const int32 PostLowCount = 9;
    const float PostLowHalfHeight = 15.0;
    const float PostLowHalfSize = 30.0;
    const float PostTallHalfHeight = 45.0;
    const float PostTallHalfSize = 20.0;
    const float PostPitch = 150.0;
    const float PostFlankOffset = 100.0;
    const float CylinderRadiusWide = 90.0;
    const float CylinderRadiusNarrow = 45.0;
    const float CylinderHeight = 500.0;
    const int32 CylinderFacets = 24;
    const float CylinderFacetHalfThickness = 40.0;
    const float CylinderFacetSeamOverlap = 1.0;
    const float HelixPitchDegrees = 30.0;
    const float HelixTopZ = 400.0;
    const float HelixBottomZ = 120.0;
    // Above every species' clearance, so one frame of wall support at floor height does not start the climb.
    const float HelixClimbStartAboveClearance = 30.0;
    // A climbing or circling walker that has had no wall support for this long fell off and approaches again.
    const float HelixLostWallSeconds = 1.0;
    const float HelixLandedZ = 100.0;
    // The outer lanes keep 280 cm between the cylinder's axis and the course edge.
    const float CylinderLeaveMargin = 120.0;
    const float SpinSeconds = 6.0;
    const float SpinDegreesPerSecond = 120.0;
    // The traversal tests' support evidence: a turn of the accepted support normal counts as a flip above this angle, and
    // a root ray that hits within this fraction of its length began inside a solid.
    const float SupportFlipDegrees = 30.0;
    const float RootRayStartInsideFraction = 0.0001;

    const float TravelSpeed = 180.0;
    // A 2.6 m body cannot pivot at the other species' rate on four phase groups that step one after another.
    const float CentipedeSurfaceTurnRate = 90.0;
    const FVector BodyHalfExtents = FVector(42.0, 30.0, 18.0);
    // Crawler hips sit on a 30 cm radius; these boxes put every hip on a side face instead of inside the body.
    const FVector Crawler4BodyHalfExtents = FVector(21.2, 21.2, 14.0);
    const FVector Crawler6BodyHalfExtents = FVector(26.0, 30.0, 14.0);
    const FVector Crawler8BodyHalfExtents = FVector(27.7, 27.7, 14.0);
    // Below BodyClearance: a body that has lost a leg or two must not sink into the floor.
    const float BodyCollapseDrop = 45.0;
    // The same bound for the other species, scaled to their clearance.
    const float CollapseDropPerClearance = 0.7;
    const float BodyMaxTilt = 22.0;
    const float ProbeReachBeyondClearance = 115.0;
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

    // The step field's tread tops: up the authored risers, then down the same risers in reverse order.
    TArray<float> Get_StepFieldTreadHeights()
    {
        auto Risers = TArray<float>();
        Risers.Add(10.0);
        Risers.Add(25.0);
        Risers.Add(40.0);
        Risers.Add(15.0);
        Risers.Add(30.0);
        Risers.Add(20.0);
        Risers.Add(35.0);
        Risers.Add(12.0);
        auto Heights = TArray<float>();
        auto Height = 0.0;
        for (auto Rise : Risers)
        {
            Height += Rise;
            Heights.Add(Height);
        }
        for (auto Index = Risers.Num() - 2; Index >= 0; Index--)
        {
            auto Mirrored = Heights[Index];
            Heights.Add(Mirrored);
        }
        return Heights;
    }

    FCkProceduralAnimationGym_SpeciesProfile Get_SpeciesProfile(ECkProceduralAnimationGym_Species InSpecies)
    {
        auto Profile = FCkProceduralAnimationGym_SpeciesProfile();
        if (InSpecies == ECkProceduralAnimationGym_Species::Spider)
        {
            Profile.Rig = ck::ProceduralGym_RigSpider;
            Profile.Gait = ck::ProceduralGym_GaitSpider;
            Profile.Clearance = ck_procedural_gym_assets::SpiderRestDrop;
            Profile.BodyHalfExtents = ck_procedural_gym_assets::SpiderBodyHalfExtents;
        }
        else if (InSpecies == ECkProceduralAnimationGym_Species::Centipede)
        {
            Profile.Rig = ck::ProceduralGym_RigCentipede;
            Profile.Gait = ck::ProceduralGym_GaitCentipede;
            Profile.Clearance = ck_procedural_gym_assets::CentipedeRestDrop;
            Profile.BodyHalfExtents = ck_procedural_gym_assets::CentipedeBodyHalfExtents;
            Profile.SurfaceTurnRate = CentipedeSurfaceTurnRate;
        }
        else if (InSpecies == ECkProceduralAnimationGym_Species::Tentacled)
        {
            Profile.Rig = ck::ProceduralGym_RigTentacled;
            Profile.Gait = ck::ProceduralGym_GaitTentacled;
            Profile.Clearance = ck_procedural_gym_assets::TentacledRestDrop;
            Profile.BodyHalfExtents = ck_procedural_gym_assets::TentacledBodyHalfExtents;
        }
        else if (InSpecies == ECkProceduralAnimationGym_Species::Beast)
        {
            Profile.Rig = ck::ProceduralGym_RigBeast;
            Profile.Gait = ck::ProceduralGym_GaitBeast;
            Profile.Clearance = ck_procedural_gym_assets::BeastRestDrop;
            Profile.BodyHalfExtents = ck_procedural_gym_assets::BeastBodyHalfExtents;
        }
        else if (InSpecies == ECkProceduralAnimationGym_Species::Biped)
        {
            Profile.Rig = ck::ProceduralGym_RigBiped;
            Profile.Gait = ck::ProceduralGym_GaitBiped;
            Profile.Clearance = ck_procedural_gym_assets::BipedRestDrop;
            Profile.BodyHalfExtents = ck_procedural_gym_assets::BipedBodyHalfExtents;
            Profile.HeightSource = ECk_SurfaceMotion_HeightSource::Rays;
        }
        else
        {
            Profile.Rig = InSpecies == ECkProceduralAnimationGym_Species::Crawler4 ? ck::ProceduralGym_Rig4 :
                (InSpecies == ECkProceduralAnimationGym_Species::Crawler6 ? ck::ProceduralGym_Rig6 : ck::ProceduralGym_Rig8);
            Profile.Gait = InSpecies == ECkProceduralAnimationGym_Species::Crawler4 ? ck::ProceduralGym_GaitRedistribute : ck::ProceduralGym_Gait;
            Profile.Clearance = BodyClearance;
            Profile.CollapseDrop = BodyCollapseDrop;
            Profile.BodyHalfExtents = InSpecies == ECkProceduralAnimationGym_Species::Crawler4 ? Crawler4BodyHalfExtents :
                (InSpecies == ECkProceduralAnimationGym_Species::Crawler6 ? Crawler6BodyHalfExtents : Crawler8BodyHalfExtents);
            return Profile;
        }
        Profile.CollapseDrop = CollapseDropPerClearance * Profile.Clearance;
        return Profile;
    }

    FString Get_SpeciesName(ECkProceduralAnimationGym_Species InSpecies)
    {
        if (InSpecies == ECkProceduralAnimationGym_Species::Spider)
        {
            return "Spider";
        }
        if (InSpecies == ECkProceduralAnimationGym_Species::Centipede)
        {
            return "Centipede";
        }
        if (InSpecies == ECkProceduralAnimationGym_Species::Tentacled)
        {
            return "Tentacled";
        }
        if (InSpecies == ECkProceduralAnimationGym_Species::Beast)
        {
            return "Beast";
        }
        if (InSpecies == ECkProceduralAnimationGym_Species::Biped)
        {
            return "Biped";
        }
        return "Crawler";
    }

    FString Get_CourseTitle(ECkProceduralAnimationGym_Course InCourse)
    {
        if (InCourse == ECkProceduralAnimationGym_Course::Flat)
        {
            return "Flat";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Uneven)
        {
            return "Uneven";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::RampWall)
        {
            return "Ramp / wall";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Ring)
        {
            return "Closed loop";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Stairs)
        {
            return "Stairs";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Rubble)
        {
            return "Rubble";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::StepField)
        {
            return "Step field";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Ledge)
        {
            return "Ledge";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Ridge)
        {
            return "Sharp ridge";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Log)
        {
            return "Log";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Beam)
        {
            return "Narrow beams";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Pillars)
        {
            return "Pillar field";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Spin)
        {
            return "Spin in place";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::PillarCrossing)
        {
            return "Pillar crossing";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Posts)
        {
            return "Posts";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Cylinder)
        {
            return "Cylinder";
        }
        return "Convex hump";
    }

    // The course part of each walker's debug name; the debugger PIE test selects walkers by that name.
    FString Get_CourseIdentifier(ECkProceduralAnimationGym_Course InCourse)
    {
        if (InCourse == ECkProceduralAnimationGym_Course::Flat)
        {
            return "Flat";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Uneven)
        {
            return "Uneven";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::RampWall)
        {
            return "RampWall";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Ring)
        {
            return "Ring";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Stairs)
        {
            return "Stairs";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Rubble)
        {
            return "Rubble";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::StepField)
        {
            return "StepField";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Ledge)
        {
            return "Ledge";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Ridge)
        {
            return "Ridge";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Log)
        {
            return "Log";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Beam)
        {
            return "Beam";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Pillars)
        {
            return "Pillars";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Spin)
        {
            return "Spin";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::PillarCrossing)
        {
            return "PillarCrossing";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Posts)
        {
            return "Posts";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Cylinder)
        {
            return "Cylinder";
        }
        return "Hump";
    }

    bool Get_IsStressCourse(ECkProceduralAnimationGym_Course InCourse)
    {
        return InCourse == ECkProceduralAnimationGym_Course::StepField || InCourse == ECkProceduralAnimationGym_Course::Ledge ||
            InCourse == ECkProceduralAnimationGym_Course::Ridge || InCourse == ECkProceduralAnimationGym_Course::Log ||
            InCourse == ECkProceduralAnimationGym_Course::Beam || InCourse == ECkProceduralAnimationGym_Course::Pillars ||
            InCourse == ECkProceduralAnimationGym_Course::Spin || InCourse == ECkProceduralAnimationGym_Course::PillarCrossing ||
            InCourse == ECkProceduralAnimationGym_Course::Posts || InCourse == ECkProceduralAnimationGym_Course::Cylinder;
    }

    // The menagerie's legs span up to 2.6 m, so its courses and every stress course space their lanes wider.
    bool Get_IsWideCourse(ECkProceduralAnimationGym_Course InCourse)
    {
        return InCourse == ECkProceduralAnimationGym_Course::Stairs || InCourse == ECkProceduralAnimationGym_Course::Rubble ||
            InCourse == ECkProceduralAnimationGym_Course::Hump || Get_IsStressCourse(InCourse);
    }

    // Three walkers per stress course; every species but the biped, which only climbs the cylinder, crosses at least two of
    // them. The gym and the PaViz harness share it.
    TArray<ECkProceduralAnimationGym_Species> Get_StressRoster(ECkProceduralAnimationGym_Course InCourse)
    {
        auto Roster = TArray<ECkProceduralAnimationGym_Species>();
        if (InCourse == ECkProceduralAnimationGym_Course::StepField)
        {
            Roster.Add(ECkProceduralAnimationGym_Species::Beast);
            Roster.Add(ECkProceduralAnimationGym_Species::Spider);
            Roster.Add(ECkProceduralAnimationGym_Species::Crawler4);
        }
        else if (InCourse == ECkProceduralAnimationGym_Course::Ledge)
        {
            Roster.Add(ECkProceduralAnimationGym_Species::Crawler6);
            Roster.Add(ECkProceduralAnimationGym_Species::Tentacled);
            Roster.Add(ECkProceduralAnimationGym_Species::Beast);
        }
        else if (InCourse == ECkProceduralAnimationGym_Course::Ridge)
        {
            Roster.Add(ECkProceduralAnimationGym_Species::Spider);
            Roster.Add(ECkProceduralAnimationGym_Species::Centipede);
            Roster.Add(ECkProceduralAnimationGym_Species::Crawler8);
        }
        else if (InCourse == ECkProceduralAnimationGym_Course::Log)
        {
            Roster.Add(ECkProceduralAnimationGym_Species::Tentacled);
            Roster.Add(ECkProceduralAnimationGym_Species::Beast);
            Roster.Add(ECkProceduralAnimationGym_Species::Crawler4);
        }
        else if (InCourse == ECkProceduralAnimationGym_Course::Beam)
        {
            Roster.Add(ECkProceduralAnimationGym_Species::Centipede);
            Roster.Add(ECkProceduralAnimationGym_Species::Spider);
            Roster.Add(ECkProceduralAnimationGym_Species::Crawler6);
        }
        else if (InCourse == ECkProceduralAnimationGym_Course::Pillars)
        {
            Roster.Add(ECkProceduralAnimationGym_Species::Crawler6);
            Roster.Add(ECkProceduralAnimationGym_Species::Tentacled);
            Roster.Add(ECkProceduralAnimationGym_Species::Beast);
        }
        else if (InCourse == ECkProceduralAnimationGym_Course::Spin)
        {
            Roster.Add(ECkProceduralAnimationGym_Species::Beast);
            Roster.Add(ECkProceduralAnimationGym_Species::Centipede);
            Roster.Add(ECkProceduralAnimationGym_Species::Tentacled);
        }
        else if (InCourse == ECkProceduralAnimationGym_Course::PillarCrossing)
        {
            Roster.Add(ECkProceduralAnimationGym_Species::Crawler8);
            Roster.Add(ECkProceduralAnimationGym_Species::Tentacled);
            Roster.Add(ECkProceduralAnimationGym_Species::Spider);
        }
        else if (InCourse == ECkProceduralAnimationGym_Course::Posts)
        {
            Roster.Add(ECkProceduralAnimationGym_Species::Crawler4);
            Roster.Add(ECkProceduralAnimationGym_Species::Beast);
            Roster.Add(ECkProceduralAnimationGym_Species::Centipede);
        }
        else if (InCourse == ECkProceduralAnimationGym_Course::Cylinder)
        {
            Roster.Add(ECkProceduralAnimationGym_Species::Spider);
            Roster.Add(ECkProceduralAnimationGym_Species::Centipede);
            Roster.Add(ECkProceduralAnimationGym_Species::Biped);
        }
        return Roster;
    }

    float Get_LaneY(int32 InIndex, int32 InRosterCount, ECkProceduralAnimationGym_Course InCourse)
    {
        return InRosterCount == 1 ? 0.0 : (InIndex - (InRosterCount - 1) * 0.5) * Get_LaneSpacing(InCourse);
    }

    float Get_LaneSpacing(ECkProceduralAnimationGym_Course InCourse)
    {
        if (InCourse == ECkProceduralAnimationGym_Course::Pillars)
        {
            return PillarsLaneSpacing;
        }
        return Get_IsWideCourse(InCourse) ? WideLaneSpacing : NarrowLaneSpacing;
    }

    float Get_CylinderRadius(int32 InLaneIndex)
    {
        return InLaneIndex == 1 ? CylinderRadiusNarrow : CylinderRadiusWide;
    }

    float Get_CourseHalfWidth(ECkProceduralAnimationGym_Course InCourse)
    {
        return Get_IsWideCourse(InCourse) ? WideCourseHalfWidth : NarrowCourseHalfWidth;
    }

    float Get_FrameTargetZ(ECkProceduralAnimationGym_Course InCourse)
    {
        if (InCourse == ECkProceduralAnimationGym_Course::RampWall || InCourse == ECkProceduralAnimationGym_Course::Ring)
        {
            return 800.0;
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Stairs)
        {
            return 120.0;
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Hump)
        {
            return 250.0;
        }
        if (InCourse == ECkProceduralAnimationGym_Course::StepField || InCourse == ECkProceduralAnimationGym_Course::Ledge ||
            InCourse == ECkProceduralAnimationGym_Course::Ridge || InCourse == ECkProceduralAnimationGym_Course::Pillars ||
            InCourse == ECkProceduralAnimationGym_Course::PillarCrossing)
        {
            return 150.0;
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Log)
        {
            return 120.0;
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Posts)
        {
            return 100.0;
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Cylinder)
        {
            return 250.0;
        }
        return 80.0;
    }

    // Deterministic, stateless pseudo-random value in [0, 1): the rubble must be identical on every reset.
    float Hash01(int32 InN)
    {
        auto S = Math::Sin(float(InN) * 12.9898) * 43758.5453;
        return S - Math::FloorToFloat(S);
    }

    // The 6-leg crawler keeps FABRIK so the gym shows both chain solvers; the tentacled walker names the curve that Auto
    // would pick for its eight-link chains.
    ECk_ProceduralRig_ChainSolver Get_ChainSolver(ECkProceduralAnimationGym_Species InSpecies)
    {
        if (InSpecies == ECkProceduralAnimationGym_Species::Crawler6)
        {
            return ECk_ProceduralRig_ChainSolver::Fabrik;
        }
        if (InSpecies == ECkProceduralAnimationGym_Species::Tentacled)
        {
            return ECk_ProceduralRig_ChainSolver::Curve;
        }
        return ECk_ProceduralRig_ChainSolver::Auto;
    }

    // Every species swivels its knees clear of the pillars and edges its legs pass, the rigid centipede included.
    ECk_ProceduralRig_Clearance Get_Clearance()
    {
        return ECk_ProceduralRig_Clearance::Swivel;
    }

    FVector Get_SegmentHalfExtents(TArray<float32> InLengths, int32 InSegmentIndex)
    {
        auto Alpha = InLengths.Num() > 1 ? float(InSegmentIndex) / float(InLengths.Num() - 1) : 0.0;
        auto Thickness = Math::Lerp(SegmentRootThickness, SegmentTipThickness, Alpha);
        return FVector(InLengths[InSegmentIndex] * 0.5, Thickness, Thickness);
    }

    ECk_SurfaceMotion_HeightSource Get_HeightSource(ECkProceduralAnimationGym_HeightSource InOverride,
        ECk_SurfaceMotion_HeightSource InSpecies)
    {
        if (InOverride == ECkProceduralAnimationGym_HeightSource::Rays)
        {
            return ECk_SurfaceMotion_HeightSource::Rays;
        }
        if (InOverride == ECkProceduralAnimationGym_HeightSource::PlantedFeet)
        {
            return ECk_SurfaceMotion_HeightSource::PlantedFeet;
        }
        return InSpecies;
    }

    FCk_SurfaceMotion_Spec MakeMotionParams(float InClearance, float InSurfaceTurnRate, ECk_SurfaceMotion_HeightSource InHeightSource)
    {
        auto Contact = FCk_SurfaceMotion_Contact();
        Contact.Set_Clearance(InClearance);
        Contact.Set_ProbeReach(InClearance + ProbeReachBeyondClearance);
        Contact.Set_HeightSource(InHeightSource);

        auto Movement = FCk_SurfaceMotion_Movement();
        Movement.Set_MaxSpeed(180.0f);
        Movement.Set_SurfaceTurnRate(InSurfaceTurnRate);

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
    FCk_Handle_Transform Presentation;
    UPROPERTY()
    FCk_Handle_ProceduralGait Gait;
    UPROPERTY()
    FCk_Handle_SurfaceMotion Motion;
    UPROPERTY()
    FCk_Handle_ProceduralBodyPose BodyPose;
    UPROPERTY()
    TArray<FCk_Handle_ProceduralLeg> Legs;
    UPROPERTY()
    TArray<FCk_Handle_Transform> VisibleFeet;
}

struct FCkProceduralAnimationGym_CrawlerLayout
{
    UPROPERTY()
    ECkProceduralAnimationGym_Species Species;
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
    ECkProceduralAnimationGym_Patrol Patrol = ECkProceduralAnimationGym_Patrol::Route;
    // The lane cylinder's radius on the cylinder course, 0 elsewhere.
    UPROPERTY()
    float CylinderRadius = 0.0;
}

struct FCkProceduralAnimationGym_CrawlerProgress
{
    UPROPERTY()
    bool Spinning = false;
    UPROPERTY()
    float SpinStartTime = -1.0;
    UPROPERTY()
    int32 RouteStage = 0;
    UPROPERTY()
    int32 Traversals = 0;
    // Game time of the helix route's last update with wall support.
    UPROPERTY()
    float LastOnWallTime = -1.0;
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
    // How deep the root sat inside the surface under it, as a fraction of its clearance, at worst: a ray from the root down
    // the support normal for one clearance finds the surface closer than the clearance (1 when it starts inside a solid).
    UPROPERTY()
    float WorstRootDepthFraction = 0.0;
    // Updates on which the accepted support normal turned more than 30 degrees, counted until the first traversal.
    UPROPERTY()
    int32 SupportFlips = 0;
    UPROPERTY()
    FVector LastSupportNormal = FVector::ZeroVector;
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
            utils_surface_motion::Get_Status(Handles.Motion) != ECk_ProceduralAnimation_Status::Ready ||
            utils_procedural_body_pose::Get_Status(Handles.BodyPose) != ECk_ProceduralAnimation_Status::Ready)
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

    // The spin starts on the first update after the walker is ready.
    bool DoUpdateSpin()
    {
        if (Layout.Patrol != ECkProceduralAnimationGym_Patrol::SpinThenRoute)
        {
            return false;
        }
        auto Now = float(System::GetGameTimeInSeconds());
        if (Progress.SpinStartTime < 0.0)
        {
            Progress.SpinStartTime = Now;
        }
        return Now - Progress.SpinStartTime < ck_procedural_gym::SpinSeconds;
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
        if (Layout.Course == ECkProceduralAnimationGym_Course::Cylinder)
        {
            return Evidence.SawWall;
        }
        return true;
    }

    void DoUpdate_SupportEvidence(FVector InPosition)
    {
        auto SupportNormal = utils_surface_motion::Get_SupportNormal(Handles.Motion);
        auto Clearance = ck_procedural_gym::Get_SpeciesProfile(Layout.Species).Clearance;
        auto Hit = utils_jolt_query::Get_RayCast(InPosition, InPosition - SupportNormal * Clearance, FCk_Jolt_QueryFilter());
        if (Hit.Get_HasHit())
        {
            auto Depth = Hit.Get_Fraction() <= ck_procedural_gym::RootRayStartInsideFraction ? 1.0 : 1.0 - Hit.Get_Fraction();
            Evidence.WorstRootDepthFraction = Math::Max(Evidence.WorstRootDepthFraction, Depth);
        }
        if (Progress.Traversals == 0 && Evidence.LastSupportNormal.IsNearlyZero() == false &&
            SupportNormal.GetSafeNormal().DotProduct(Evidence.LastSupportNormal) < Math::Cos(Math::DegreesToRadians(ck_procedural_gym::SupportFlipDegrees)))
        {
            Evidence.SupportFlips++;
        }
        Evidence.LastSupportNormal = SupportNormal.GetSafeNormal();
    }

    // Advances the helix stage whose end condition holds, then steers for the current stage: approach the lane's cylinder,
    // circle up it, circle down it, climb down to the floor, walk away from it, return to the start. A walker that loses
    // the wall while on the cylinder steers back toward its axis, and approaches again after a second off it: the helix
    // steer carried on along the floor would take it off the course.
    FVector DoUpdate_HelixRoute(FVector InPosition, FVector InLocal)
    {
        auto Axis = Layout.Origin + FVector(0.0, Layout.LaneY, 0.0);
        auto Radial = InPosition - Axis;
        Radial.Z = 0.0;
        auto Tangent = FVector::UpVector.CrossProduct(Radial.GetSafeNormal());
        auto Pitch = Math::DegreesToRadians(ck_procedural_gym::HelixPitchDegrees);
        auto SupportNormal = utils_surface_motion::Get_SupportNormal(Handles.Motion);
        auto OnWall = Math::Abs(SupportNormal.Z) < 0.3;
        auto Now = float(System::GetGameTimeInSeconds());
        if (OnWall)
        {
            Progress.LastOnWallTime = Now;
        }
        auto ClimbStartZ = ck_procedural_gym::Get_SpeciesProfile(Layout.Species).Clearance + ck_procedural_gym::HelixClimbStartAboveClearance;
        auto OnCylinderRoute = Progress.RouteStage >= 1 && Progress.RouteStage <= 3;
        if (Progress.RouteStage == 0 && OnWall && InLocal.Z > ClimbStartZ)
        {
            Progress.RouteStage = 1;
        }
        else if (Progress.RouteStage == 3 && SupportNormal.Z > 0.7 && InLocal.Z < ck_procedural_gym::HelixLandedZ)
        {
            Progress.RouteStage = 4;
        }
        else if (OnCylinderRoute && Now - Progress.LastOnWallTime > ck_procedural_gym::HelixLostWallSeconds)
        {
            Progress.RouteStage = 0;
        }
        else if (Progress.RouteStage == 1 && InLocal.Z > ck_procedural_gym::HelixTopZ)
        {
            Progress.RouteStage = 2;
        }
        else if (Progress.RouteStage == 2 && InLocal.Z < ck_procedural_gym::HelixBottomZ)
        {
            Progress.RouteStage = 3;
        }
        else if (Progress.RouteStage == 4 && Radial.Size() > Layout.CylinderRadius + ck_procedural_gym::CylinderLeaveMargin)
        {
            Progress.RouteStage = 5;
        }
        else if (Progress.RouteStage == 5 && InLocal.X < -ck_procedural_gym::TurnaroundX)
        {
            Progress.Traversals++;
            Progress.RouteStage = 0;
        }

        if (Progress.RouteStage == 0 || (Progress.RouteStage >= 1 && Progress.RouteStage <= 3 && OnWall == false))
        {
            return FVector(-Radial.X, -Radial.Y, 0.0);
        }
        if (Progress.RouteStage == 1)
        {
            return Tangent * Math::Cos(Pitch) + FVector::UpVector * Math::Sin(Pitch);
        }
        if (Progress.RouteStage == 2)
        {
            return Tangent * Math::Cos(Pitch) - FVector::UpVector * Math::Sin(Pitch);
        }
        if (Progress.RouteStage == 3)
        {
            return FVector(0.0, 0.0, -1.0);
        }
        if (Progress.RouteStage == 4)
        {
            return Radial.GetSafeNormal();
        }
        return FVector(-ck_procedural_gym::GoalX, Layout.LaneY, InLocal.Z) - InLocal;
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
        DoUpdate_SupportEvidence(Position);
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
        else if (Layout.Patrol == ECkProceduralAnimationGym_Patrol::Helix)
        {
            Direction = DoUpdate_HelixRoute(Position, Local);
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

        Progress.Spinning = DoUpdateSpin();
        if (Progress.Spinning)
        {
            auto SpinYaw = ck_procedural_gym::SpinDegreesPerSecond * (float(System::GetGameTimeInSeconds()) - Progress.SpinStartTime);
            Direction = FRotator(0.0, SpinYaw, 0.0).Vector();
        }

        // A zero steering direction is only a valid request at zero speed. A spinning walker turns in place: surface
        // motion faces the steering direction at any speed.
        auto SteerDirection = Direction.GetSafeNormal();
        auto Moving = InRun && Progress.Spinning == false && Evidence.InvalidOutput == false && SteerDirection.IsNearlyZero() == false;
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
            auto SpeciesName = ck_procedural_gym::Get_SpeciesName(Layout.Species);
            utils_debug_draw::DrawDebugString(Position + FVector(0.0, 0.0, 145.0),
                f"{SpeciesName} | {Progress.PlantedCount}/{Layout.LegCount} planted | laps {Progress.Traversals}", Layout.Color, 0.0f);
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
    TArray<ECkProceduralAnimationGym_Species> Roster;
    UPROPERTY()
    ECk_ProceduralBodyPose_ConformMode ConformMode = ECk_ProceduralBodyPose_ConformMode::PlantedFeet;
    UPROPERTY()
    ECkProceduralAnimationGym_HeightSource HeightSource = ECkProceduralAnimationGym_HeightSource::Species;
    // How far above the fixture origin the walkers' start stands: a test that builds its own start above the floor.
    UPROPERTY()
    float StartHeight = 0.0;
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

    // The first InCount of the 4, 6 and 8-leg crawlers; see Create_WithRoster.
    bool Create(FCk_Handle InOwner, FVector InOrigin, ECkProceduralAnimationGym_Course InCourse,
        bool InRender = true, int32 InCount = 3)
    {
        auto Roster = TArray<ECkProceduralAnimationGym_Species>();
        for (auto Index = 0; Index < InCount; Index++)
        {
            Roster.Add(Index == 0 ? ECkProceduralAnimationGym_Species::Crawler4 :
                (Index == 1 ? ECkProceduralAnimationGym_Species::Crawler6 : ECkProceduralAnimationGym_Species::Crawler8));
        }
        return Create_WithRoster(InOwner, InOrigin, InCourse, Roster, InRender);
    }

    // Caller first retires the previous fixture and waits for Get_IsDestroyed(). No overlapping
    // old/new collision bodies are hidden under a reset, even when destruction is deferred.
    bool Create_WithRoster(FCk_Handle InOwner, FVector InOrigin, ECkProceduralAnimationGym_Course InCourse,
        TArray<ECkProceduralAnimationGym_Species> InRoster, bool InRender = true,
        ECk_ProceduralBodyPose_ConformMode InConformMode = ECk_ProceduralBodyPose_ConformMode::PlantedFeet,
        ECkProceduralAnimationGym_HeightSource InHeightSource = ECkProceduralAnimationGym_HeightSource::Species,
        float InStartHeight = 0.0)
    {
        if (Get_IsDestroyed() == false || ck::Is_NOT_Valid(InOwner) || InRoster.Num() < 1 || InRoster.Num() > 3)
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
        Spawn.Roster = InRoster;
        Spawn.ConformMode = InConformMode;
        Spawn.HeightSource = InHeightSource;
        Spawn.StartHeight = InStartHeight;
        Spawn.Pending = true;

        auto GroundColor = FLinearColor(0.12, 0.18, 0.24, 1.0);
        auto RaisedColor = FLinearColor(0.18, 0.25, 0.31, 1.0);
        auto HalfWidth = ck_procedural_gym::Get_CourseHalfWidth(Spawn.Course);
        if (Spawn.Course == ECkProceduralAnimationGym_Course::Ring)
        {
            for (auto Index = 0; Index < 24; Index++)
            {
                auto Degrees = -90.0 + 15.0 * Index;
                auto Theta = Math::DegreesToRadians(Degrees);
                auto Radial = FVector(Math::Cos(Theta), 0.0, Math::Sin(Theta));
                auto Shade = Index % 2 == 0 ? GroundColor : RaisedColor;
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
                FVector(20.0, HalfWidth, ck_procedural_gym::WallHalfHeight), RaisedColor);
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
            if (Spawn.Course == ECkProceduralAnimationGym_Course::Stairs)
            {
                AddStairs(HalfWidth, RaisedColor);
            }
            else if (Spawn.Course == ECkProceduralAnimationGym_Course::Rubble)
            {
                AddRubble(HalfWidth, RaisedColor);
            }
            else if (Spawn.Course == ECkProceduralAnimationGym_Course::Hump)
            {
                AddHump(GroundColor, RaisedColor);
            }
            else if (Spawn.Course == ECkProceduralAnimationGym_Course::StepField)
            {
                AddStepField(HalfWidth, RaisedColor);
            }
            else if (Spawn.Course == ECkProceduralAnimationGym_Course::Ledge)
            {
                AddSurface(FVector(0.0, 0.0, ck_procedural_gym::LedgeHeight * 0.5), FRotator::ZeroRotator,
                    FVector(ck_procedural_gym::LedgeHalfLength, HalfWidth, ck_procedural_gym::LedgeHeight * 0.5), RaisedColor);
            }
            else if (Spawn.Course == ECkProceduralAnimationGym_Course::Ridge)
            {
                AddSlabWithShape(FVector(-ck_procedural_gym::RidgeHalfBase, 0.0, 0.0), FVector(0.0, 0.0, ck_procedural_gym::RidgeHeight),
                    RaisedColor, ck_procedural_gym::RidgeSlabHalfThickness);
                AddSlabWithShape(FVector(0.0, 0.0, ck_procedural_gym::RidgeHeight), FVector(ck_procedural_gym::RidgeHalfBase, 0.0, 0.0),
                    GroundColor, ck_procedural_gym::RidgeSlabHalfThickness);
            }
            else if (Spawn.Course == ECkProceduralAnimationGym_Course::Log)
            {
                AddLog(GroundColor, RaisedColor);
            }
            else if (Spawn.Course == ECkProceduralAnimationGym_Course::Beam)
            {
                for (auto Index = 0; Index < Spawn.Roster.Num(); Index++)
                {
                    auto LaneY = ck_procedural_gym::Get_LaneY(Index, Spawn.Roster.Num(), Spawn.Course);
                    AddSurface(FVector(0.0, LaneY, ck_procedural_gym::BeamHeight * 0.5), FRotator::ZeroRotator,
                        FVector(ck_procedural_gym::BeamHalfLength, ck_procedural_gym::BeamHalfWidth, ck_procedural_gym::BeamHeight * 0.5),
                        RaisedColor);
                }
            }
            else if (Spawn.Course == ECkProceduralAnimationGym_Course::Pillars)
            {
                AddPillars(HalfWidth, RaisedColor);
            }
            else if (Spawn.Course == ECkProceduralAnimationGym_Course::PillarCrossing)
            {
                AddPillarCrossing(HalfWidth, GroundColor, RaisedColor);
            }
            else if (Spawn.Course == ECkProceduralAnimationGym_Course::Posts)
            {
                AddPosts(RaisedColor);
            }
            else if (Spawn.Course == ECkProceduralAnimationGym_Course::Cylinder)
            {
                AddCylinders(GroundColor, RaisedColor);
            }
        }
        return true;
    }

    // Each tread is a box from the floor to its top; neighbouring boxes share their riser plane.
    void AddStepField(float InHalfWidth, FLinearColor InColor)
    {
        auto Heights = ck_procedural_gym::Get_StepFieldTreadHeights();
        auto StartX = -0.5 * Heights.Num() * ck_procedural_gym::StepFieldTread;
        for (auto Index = 0; Index < Heights.Num(); Index++)
        {
            auto HalfTop = Heights[Index] * 0.5;
            AddSurface(FVector(StartX + ck_procedural_gym::StepFieldTread * (Index + 0.5), 0.0, HalfTop), FRotator::ZeroRotator,
                FVector(ck_procedural_gym::StepFieldTread * 0.5, InHalfWidth, HalfTop), InColor);
        }
    }

    // A horizontal cylinder resting on the floor, its axis along Y. The facets run clockwise seen from -Y, so every slab's
    // top face points out of the log.
    void AddLog(FLinearColor InColor, FLinearColor InAlternateColor)
    {
        auto Radius = ck_procedural_gym::LogRadius;
        for (auto Index = 0; Index < ck_procedural_gym::LogFacets; Index++)
        {
            auto FromAngle = Math::PI - 2.0 * Math::PI * Index / ck_procedural_gym::LogFacets;
            auto ToAngle = Math::PI - 2.0 * Math::PI * (Index + 1) / ck_procedural_gym::LogFacets;
            AddSlabWithShape(FVector(Radius * Math::Cos(FromAngle), 0.0, Radius + Radius * Math::Sin(FromAngle)),
                FVector(Radius * Math::Cos(ToAngle), 0.0, Radius + Radius * Math::Sin(ToAngle)),
                Math::IntegerDivisionTrunc(Index, 2) % 2 == 0 ? InColor : InAlternateColor, ck_procedural_gym::LogSlabHalfThickness);
        }
    }

    void AddPillars(float InHalfWidth, FLinearColor InColor)
    {
        auto Columns = Math::RoundToInt(2.0 * ck_procedural_gym::PillarHalfSpanX / ck_procedural_gym::PillarSpacing);
        auto Rows = Math::FloorToInt((InHalfWidth - ck_procedural_gym::PillarHalfSize) / ck_procedural_gym::PillarSpacing);
        auto HalfExtents = FVector(ck_procedural_gym::PillarHalfSize, ck_procedural_gym::PillarHalfSize, ck_procedural_gym::PillarHeight * 0.5);
        for (auto Column = 0; Column <= Columns; Column++)
        {
            for (auto Row = -Rows; Row < Rows; Row++)
            {
                AddSurface(FVector(-ck_procedural_gym::PillarHalfSpanX + ck_procedural_gym::PillarSpacing * Column,
                    ck_procedural_gym::PillarSpacing * (Row + 0.5), HalfExtents.Z), FRotator::ZeroRotator, HalfExtents, InColor);
            }
        }
    }

    // A ramp up onto a landing, a field of pillar tops at the landing's height, a landing and a ramp down. Everything spans
    // the course, so every lane crosses the same tops.
    void AddPillarCrossing(float InHalfWidth, FLinearColor InColor, FLinearColor InAlternateColor)
    {
        auto Height = ck_procedural_gym::CrossingHeight;
        auto LandingCenterX = ck_procedural_gym::CrossingFieldHalfSpanX + 2.0 * ck_procedural_gym::CrossingLandingHalfLength;
        auto RampTopX = LandingCenterX + ck_procedural_gym::CrossingLandingHalfLength;
        auto RampFootX = RampTopX + ck_procedural_gym::CrossingRampRun;
        auto LandingHalfExtents = FVector(ck_procedural_gym::CrossingLandingHalfLength, InHalfWidth, Height * 0.5);
        AddSlabWithShape(FVector(-RampFootX, 0.0, 0.0), FVector(-RampTopX, 0.0, Height), InAlternateColor,
            ck_procedural_gym::CrossingRampSlabHalfThickness);
        AddSurface(FVector(-LandingCenterX, 0.0, Height * 0.5), FRotator::ZeroRotator, LandingHalfExtents, InAlternateColor);

        auto Columns = Math::RoundToInt(2.0 * ck_procedural_gym::CrossingFieldHalfSpanX / ck_procedural_gym::CrossingPillarPitch);
        auto Rows = Math::FloorToInt((InHalfWidth - ck_procedural_gym::CrossingPillarHalfSize) / ck_procedural_gym::CrossingPillarPitch);
        auto PillarHalfExtents = FVector(ck_procedural_gym::CrossingPillarHalfSize, ck_procedural_gym::CrossingPillarHalfSize, Height * 0.5);
        for (auto Column = 0; Column <= Columns; Column++)
        {
            for (auto Row = -Rows; Row <= Rows; Row++)
            {
                AddSurface(FVector(-ck_procedural_gym::CrossingFieldHalfSpanX + ck_procedural_gym::CrossingPillarPitch * Column,
                    ck_procedural_gym::CrossingPillarPitch * Row, Height * 0.5), FRotator::ZeroRotator, PillarHalfExtents,
                    (Column + Row + Rows) % 2 == 0 ? InColor : InAlternateColor);
            }
        }

        AddSurface(FVector(LandingCenterX, 0.0, Height * 0.5), FRotator::ZeroRotator, LandingHalfExtents, InAlternateColor);
        AddSlabWithShape(FVector(RampTopX, 0.0, Height), FVector(RampFootX, 0.0, 0.0), InAlternateColor,
            ck_procedural_gym::CrossingRampSlabHalfThickness);
    }

    // Per lane, low posts on the lane's line and tall posts flanking it halfway between them.
    void AddPosts(FLinearColor InColor)
    {
        auto LowHalfExtents = FVector(ck_procedural_gym::PostLowHalfSize, ck_procedural_gym::PostLowHalfSize, ck_procedural_gym::PostLowHalfHeight);
        auto TallHalfExtents = FVector(ck_procedural_gym::PostTallHalfSize, ck_procedural_gym::PostTallHalfSize, ck_procedural_gym::PostTallHalfHeight);
        auto FirstX = -0.5 * (ck_procedural_gym::PostLowCount - 1) * ck_procedural_gym::PostPitch;
        for (auto Lane = 0; Lane < Spawn.Roster.Num(); Lane++)
        {
            auto LaneY = ck_procedural_gym::Get_LaneY(Lane, Spawn.Roster.Num(), Spawn.Course);
            for (auto Index = 0; Index < ck_procedural_gym::PostLowCount; Index++)
            {
                AddSurface(FVector(FirstX + ck_procedural_gym::PostPitch * Index, LaneY, ck_procedural_gym::PostLowHalfHeight),
                    FRotator::ZeroRotator, LowHalfExtents, InColor);
            }
            for (auto Index = 0; Index < ck_procedural_gym::PostLowCount - 1; Index++)
            {
                auto FlankX = FirstX + ck_procedural_gym::PostPitch * (Index + 0.5);
                AddSurface(FVector(FlankX, LaneY - ck_procedural_gym::PostFlankOffset, ck_procedural_gym::PostTallHalfHeight),
                    FRotator::ZeroRotator, TallHalfExtents, InColor);
                AddSurface(FVector(FlankX, LaneY + ck_procedural_gym::PostFlankOffset, ck_procedural_gym::PostTallHalfHeight),
                    FRotator::ZeroRotator, TallHalfExtents, InColor);
            }
        }
    }

    // A vertical cylinder at the centre of every lane. A facet's local X is the radial, so its outer face sits at the
    // radius; each facet is a little wider than the polygon's edge so no seam opens between neighbours.
    void AddCylinders(FLinearColor InColor, FLinearColor InAlternateColor)
    {
        auto HalfHeight = ck_procedural_gym::CylinderHeight * 0.5;
        for (auto Lane = 0; Lane < Spawn.Roster.Num(); Lane++)
        {
            auto LaneY = ck_procedural_gym::Get_LaneY(Lane, Spawn.Roster.Num(), Spawn.Course);
            auto Radius = ck_procedural_gym::Get_CylinderRadius(Lane);
            auto HalfExtents = FVector(ck_procedural_gym::CylinderFacetHalfThickness,
                Radius * Math::Tan(Math::PI / ck_procedural_gym::CylinderFacets) + ck_procedural_gym::CylinderFacetSeamOverlap, HalfHeight);
            for (auto Facet = 0; Facet < ck_procedural_gym::CylinderFacets; Facet++)
            {
                auto Theta = 2.0 * Math::PI * Facet / ck_procedural_gym::CylinderFacets;
                AddSurface(FVector(Math::Cos(Theta), Math::Sin(Theta), 0.0) * (Radius - ck_procedural_gym::CylinderFacetHalfThickness) +
                    FVector(0.0, LaneY, HalfHeight), FRotator(0.0, Math::RadiansToDegrees(Theta), 0.0), HalfExtents,
                    Facet % 2 == 0 ? InColor : InAlternateColor);
            }
        }
    }

    void AddStairs(float InHalfWidth, FLinearColor InColor)
    {
        auto UpStartX = -ck_procedural_gym::StairsLandingHalfLength - ck_procedural_gym::StairsUpSteps * ck_procedural_gym::StairRun;
        for (auto Step = 1; Step <= ck_procedural_gym::StairsUpSteps; Step++)
        {
            auto HalfTop = ck_procedural_gym::StairsUpRise * Step * 0.5;
            AddSurface(FVector(UpStartX + ck_procedural_gym::StairRun * (Step - 0.5), 0.0, HalfTop), FRotator::ZeroRotator,
                FVector(ck_procedural_gym::StairHalfTread, InHalfWidth, HalfTop), InColor);
        }
        auto LandingHalfHeight = ck_procedural_gym::StairsLandingZ * 0.5;
        AddSurface(FVector(0.0, 0.0, LandingHalfHeight), FRotator::ZeroRotator,
            FVector(ck_procedural_gym::StairsLandingHalfLength, InHalfWidth, LandingHalfHeight), InColor);
        for (auto Step = 1; Step <= ck_procedural_gym::StairsDownSteps; Step++)
        {
            auto HalfTop = (ck_procedural_gym::StairsLandingZ - ck_procedural_gym::StairsDownRise * Step) * 0.5;
            AddSurface(FVector(ck_procedural_gym::StairsLandingHalfLength + ck_procedural_gym::StairRun * (Step - 0.5), 0.0, HalfTop),
                FRotator::ZeroRotator, FVector(ck_procedural_gym::StairHalfTread, InHalfWidth, HalfTop), InColor);
        }
    }

    // Every rock is half buried: its centre sits half its half-height above the floor.
    void AddRubble(float InHalfWidth, FLinearColor InColor)
    {
        for (auto Index = 0; Index < ck_procedural_gym::RubbleCount; Index++)
        {
            auto Seed = 8 * Index;
            auto HalfExtents = FVector(15.0 + 30.0 * ck_procedural_gym::Hash01(Seed + 3), 15.0 + 30.0 * ck_procedural_gym::Hash01(Seed + 4),
                5.0 + 13.0 * ck_procedural_gym::Hash01(Seed + 5));
            auto Location = FVector(ck_procedural_gym::RubbleHalfSpanX * (2.0 * ck_procedural_gym::Hash01(Seed + 1) - 1.0),
                (2.0 * ck_procedural_gym::Hash01(Seed + 2) - 1.0) * (InHalfWidth - ck_procedural_gym::RubbleEdgeMargin), HalfExtents.Z * 0.5);
            auto Rotation = FRotator(ck_procedural_gym::RubbleMaxTilt * (2.0 * ck_procedural_gym::Hash01(Seed + 7) - 1.0),
                90.0 * ck_procedural_gym::Hash01(Seed + 6), ck_procedural_gym::RubbleMaxTilt * (2.0 * ck_procedural_gym::Hash01(Seed + 8) - 1.0));
            AddSurface(Location, Rotation, HalfExtents, InColor);
        }
    }

    float Get_HumpHeight(float InX) const
    {
        if (Math::Abs(InX) >= ck_procedural_gym::HumpHalfWidth)
        {
            return 0.0;
        }
        return ck_procedural_gym::HumpTopZ * 0.5 * (1.0 + Math::Cos(Math::PI * InX / ck_procedural_gym::HumpHalfWidth));
    }

    void AddHump(FLinearColor InColor, FLinearColor InAlternateColor)
    {
        auto FacetCount = Math::RoundToInt(2.0 * ck_procedural_gym::HumpHalfWidth / ck_procedural_gym::HumpFacetLength);
        for (auto Index = 0; Index < FacetCount; Index++)
        {
            auto FromX = -ck_procedural_gym::HumpHalfWidth + ck_procedural_gym::HumpFacetLength * Index;
            auto ToX = FromX + ck_procedural_gym::HumpFacetLength;
            AddSlabWithShape(FVector(FromX, 0.0, Get_HumpHeight(FromX)), FVector(ToX, 0.0, Get_HumpHeight(ToX)),
                (Index / 4) % 2 == 0 ? InColor : InAlternateColor, ck_procedural_gym::HumpSlabHalfThickness);
        }
    }

    void AddSlab(FVector InStart, FVector InEnd, FLinearColor InColor)
    {
        AddSlabWithShape(InStart, InEnd, InColor, ck_procedural_gym::SlabHalfThickness);
    }

    // Slab top faces run exactly from InStart to InEnd, so neighbouring slabs meet at shared points on the profile: an
    // overlap would leave a lip at every convex seam that a forward contact ray reads as a wall.
    void AddSlabWithShape(FVector InStart, FVector InEnd, FLinearColor InColor, float InHalfThickness)
    {
        auto Delta = InEnd - InStart;
        auto Pitch = Math::RadiansToDegrees(Math::Atan2(Delta.Z, Delta.X));
        auto Angle = Math::DegreesToRadians(Pitch);
        auto Normal = FVector(-Math::Sin(Angle), 0.0, Math::Cos(Angle));
        AddSurface((InStart + InEnd) * 0.5 - Normal * InHalfThickness, FRotator(Pitch, 0.0, 0.0),
            FVector(Delta.Size() * 0.5, ck_procedural_gym::Get_CourseHalfWidth(Spawn.Course), InHalfThickness), InColor);
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
        if (Spawn.Pending || Crawlers.Num() != Spawn.Roster.Num())
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
        RigParams.Set_Solver(ck_procedural_gym::Get_ChainSolver(InOutCrawler.Layout.Species));
        RigParams.Set_Clearance(ck_procedural_gym::Get_Clearance());
        return FCk_ProceduralWalker_LegChain(InLeg.Get_Id(), RigParams);
    }

    void SpawnCrawler(int32 InIndex)
    {
        auto Crawler = FCkProceduralAnimationGym_Crawler();
        Crawler.Layout.Species = Spawn.Roster[InIndex];
        auto Profile = ck_procedural_gym::Get_SpeciesProfile(Crawler.Layout.Species);
        Crawler.Layout.LegCount = Profile.Rig.Get_Legs().Num();
        Crawler.Layout.LaneY = ck_procedural_gym::Get_LaneY(InIndex, Spawn.Roster.Num(), Spawn.Course);
        Crawler.Layout.Origin = Spawn.Origin;
        Crawler.Layout.Course = Spawn.Course;
        Crawler.Layout.Patrol = Spawn.Course == ECkProceduralAnimationGym_Course::Spin ? ECkProceduralAnimationGym_Patrol::SpinThenRoute :
            (Spawn.Course == ECkProceduralAnimationGym_Course::Cylinder ? ECkProceduralAnimationGym_Patrol::Helix : ECkProceduralAnimationGym_Patrol::Route);
        if (Spawn.Course == ECkProceduralAnimationGym_Course::Cylinder)
        {
            Crawler.Layout.CylinderRadius = ck_procedural_gym::Get_CylinderRadius(InIndex);
        }
        Crawler.Layout.Color = InIndex == 0 ? FLinearColor(0.1, 0.8, 0.85, 1.0) :
            (InIndex == 1 ? FLinearColor(1.0, 0.58, 0.12, 1.0) : FLinearColor(0.65, 0.35, 1.0, 1.0));
        Crawler.Layout.Start = Spawn.Origin + (Spawn.Course == ECkProceduralAnimationGym_Course::Ring ?
            FVector(0.0, Crawler.Layout.LaneY, ck_procedural_gym::RingStartZ) :
            FVector(ck_procedural_gym::StartX, Crawler.Layout.LaneY, Spawn.StartHeight + Profile.Clearance));

        // The root is the simulation body; its visual lives on the presentation entity, which the body pose sags.
        auto Owner = SceneRoot;
        auto RootEntity = utils_entity_lifetime::Request_CreateEntity(Owner);
        Crawler.Handles.Root = utils_transform::Add(RootEntity, FTransform(Crawler.Layout.Start), ECk_Replication::DoesNotReplicate);
        Entities.Add(RootEntity);
        RootEntity.Request_OverrideToSelf();
        auto CourseIdentifier = ck_procedural_gym::Get_CourseIdentifier(Spawn.Course);
        auto SpeciesName = ck_procedural_gym::Get_SpeciesName(Crawler.Layout.Species);
        RootEntity.Set_DebugName(FName(f"ProceduralAnimation.{CourseIdentifier}.{SpeciesName}{Crawler.Layout.LegCount}"));
        Crawler.Handles.Presentation = AddVisual(RootEntity, FTransform(Crawler.Layout.Start), Profile.BodyHalfExtents,
            Crawler.Layout.Color);

        Crawler.Handles.Motion = utils_surface_motion::Add(Crawler.Handles.Root, ck_procedural_gym::MakeMotionParams(Profile.Clearance,
            Profile.SurfaceTurnRate, ck_procedural_gym::Get_HeightSource(Spawn.HeightSource, Profile.HeightSource)));

        Crawler.Layout.GaitPreset = Profile.Gait;
        auto Chains = TArray<FCk_ProceduralWalker_LegChain>();
        for (auto LegParams : Profile.Rig.Get_Legs())
        {
            Chains.Add(MakeLegChain(Crawler, LegParams));
            Crawler.Evidence.SawSwing.Add(false);
            Crawler.Evidence.Replanted.Add(false);
        }

        auto Walker = utils_procedural_animation::Add_Walker(Crawler.Handles.Root, Profile.Rig, Crawler.Layout.GaitPreset, Chains);
        Crawler.Handles.Gait = Walker.Get_Gait();
        Crawler.Handles.Legs = Walker.Get_Legs();
        if (ck::IsValid(Crawler.Handles.Gait))
        {
            auto Support = FCk_ProceduralBodyPose_Support();
            Support.Set_CollapseDrop(Profile.CollapseDrop);
            Support.Set_MaxTilt(ck_procedural_gym::BodyMaxTilt);
            auto Conform = FCk_ProceduralBodyPose_Conform();
            Conform.Set_Mode(Spawn.ConformMode);
            auto PoseSpec = FCk_ProceduralBodyPose_Spec(Crawler.Handles.Presentation);
            PoseSpec.Set_Support(Support);
            PoseSpec.Set_Conform(Conform);
            Crawler.Handles.BodyPose = utils_procedural_body_pose::Add(Crawler.Handles.Gait, PoseSpec);
        }
        if (ck::Is_NOT_Valid(Crawler.Handles.Motion) || ck::Is_NOT_Valid(Crawler.Handles.Gait) || Crawler.Handles.Legs.Num() != Crawler.Layout.LegCount ||
            ck::Is_NOT_Valid(Crawler.Handles.BodyPose))
        {
            CompositionError = f"{CourseIdentifier} {SpeciesName} with {Crawler.Layout.LegCount} legs: surface motion, walker or body pose composition was rejected";
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
            for (auto Index = 0; Index < Spawn.Roster.Num(); Index++)
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
