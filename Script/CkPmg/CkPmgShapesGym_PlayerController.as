// Language=angelscript

//============================================================================
// PMG SHAPES GYM - PLAYER CONTROLLER
//============================================================================
// Displays PMG debug shapes in grid layouts for visual testing.
// Test stations:
// - Flat Shapes (8): Circle, Triangle, Plane, Ring, Cross, Star, Checkmark, Diamond (with XY/XZ/YZ orientations)
// - Basic 3D Shapes (8): Sphere, Box, Cone, Cylinder, Capsule, Pyramid, Hemisphere, Torus
// - Angular Shapes (3): Wedge, Arc, WedgeCone (with XY/XZ/YZ orientations)
// - Directional Shapes (3): Arrow, Pivot, DashedLine (with XY/XZ/YZ orientations)
// - Icon Shapes (4): Warning, Prohibition, NoEntry, InfoCircle (with XY/XZ/YZ orientations)
// - Symbol Shapes (5): MagnifyingGlass, QuestionMark, ExclamationMark, Flag, Pin (with XY/XZ/YZ orientations)
// - Text Shapes (12): AllOrientations (Latin), MultiLine, CJK placeholder, + 9 symbol/emoji rows (font fallback)
//============================================================================

class ACk_PmgShapesGym_PlayerController : ACk_Gym_Base_PlayerController
{
    // Grid layout configuration
    float32 GridSpacing = 250.0f;
    int GridColumns = 6;
    float32 ShapeSize = 50.0f;

    // Track spawned shape handles for cleanup
    TArray<FCk_Handle_Pmg_DebugShape> SpawnedShapes;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Pmg.FlatShapes");
            Station.Title = FText::FromString("PMG FLAT SHAPES");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Displays all 8 flat PMG debug shapes in multiple orientations."));
            Description.Add(FText::FromString("Shapes shown in XY (Red), XZ (Green), and YZ (Blue) planes."));
            Description.Add(FText::FromString("Console: Ck_GymPmg_RegenerateAll / ClearAll / SetGridSpacing / SetShapeSize"));
            Station.Description = Description;
            Station.AutoSize = true;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Pmg.BasicShapes");
            Station.Title = FText::FromString("PMG BASIC 3D SHAPES");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Displays all basic 3D PMG debug shapes."));
            Description.Add(FText::FromString("8 shapes shown in 3 orientations each (Red/Green/Blue)."));
            Description.Add(FText::FromString("Console: Ck_GymPmg_RegenerateAll / ClearAll / SetGridSpacing / SetShapeSize"));
            Station.Description = Description;
            Station.AutoSize = true;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Pmg.AngularShapes");
            Station.Title = FText::FromString("PMG ANGULAR SHAPES");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Displays angular PMG debug shapes (wedges, arcs)."));
            Description.Add(FText::FromString("3 shapes shown in 3 orientations each (Red/Green/Blue)."));
            Description.Add(FText::FromString("Console: Ck_GymPmg_RegenerateAll / ClearAll / SetGridSpacing / SetShapeSize"));
            Station.Description = Description;
            Station.AutoSize = true;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Pmg.DirectionalShapes");
            Station.Title = FText::FromString("PMG DIRECTIONAL SHAPES");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Displays directional PMG debug shapes (arrows, pivots, dashed lines)."));
            Description.Add(FText::FromString("3 shapes shown in 3 orientations each (Red/Green/Blue)."));
            Description.Add(FText::FromString("Console: Ck_GymPmg_RegenerateAll / ClearAll / SetGridSpacing / SetShapeSize"));
            Station.Description = Description;
            Station.AutoSize = true;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Pmg.IconShapes");
            Station.Title = FText::FromString("PMG ICON SHAPES");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Displays icon PMG debug shapes (warning, prohibition, no entry, info)."));
            Description.Add(FText::FromString("4 shapes shown in 3 orientations each (Red/Green/Blue)."));
            Description.Add(FText::FromString("Console: Ck_GymPmg_RegenerateAll / ClearAll / SetGridSpacing / SetShapeSize"));
            Station.Description = Description;
            Station.AutoSize = true;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Pmg.SymbolShapes");
            Station.Title = FText::FromString("PMG SYMBOL SHAPES");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Displays symbol PMG debug shapes (search, question, exclamation, flag, pin)."));
            Description.Add(FText::FromString("5 shapes shown in 3 orientations each (Red/Green/Blue)."));
            Description.Add(FText::FromString("Console: Ck_GymPmg_RegenerateAll / ClearAll / SetGridSpacing / SetShapeSize"));
            Station.Description = Description;
            Station.AutoSize = true;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Pmg.TextShapes");
            Station.Title = FText::FromString("PMG TEXT SHAPES (UTF-8)");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Displays UTF-8 text as debug geometry: Latin orientations, multi-line, CJK placeholder, and symbol/emoji rows."));
            Description.Add(FText::FromString("Wireframe glyph contours + filled procmesh (FreeType + Delaunay tessellation). Default axis XZ (upright)."));
            Description.Add(FText::FromString("Symbol/emoji rows (rows 4-12) use font fallback: primary text font -> Noto Emoji -> Noto Sans Symbols 2."));
            Description.Add(FText::FromString("CJK row renders .notdef boxes until the bundled Noto CJK font asset is imported."));
            Station.Description = Description;
            Station.AutoSize = true;
            Stations.Add(Station);
        }

        return Stations;
    }

    void Request_StartGym() override
    {
        Request_SpawnAllShapes();
        ck::Trace("✅ PMG Shapes Gym - All shapes spawned");
    }

    //------------------------------------------------------------------------
    // MAIN SHAPE SPAWNING
    //------------------------------------------------------------------------

    void Request_SpawnAllShapes()
    {
        // Clear any existing shapes
        Request_ClearAllShapes();

        // Spawn flat shapes station
        auto FlatStationTransform = Get_StationAnchorTransform("Gym.Pmg.FlatShapes", ECk_GymStation_Anchor::PanelCenter);
        auto FlatBaseLocation = FlatStationTransform.GetLocation();

        int FlatRow = 0;
        SpawnShape_Circle_AllOrientations(FlatBaseLocation, FlatRow); ++FlatRow;
        SpawnShape_Triangle_AllOrientations(FlatBaseLocation, FlatRow); ++FlatRow;
        SpawnShape_Plane_AllOrientations(FlatBaseLocation, FlatRow); ++FlatRow;
        SpawnShape_Ring_AllOrientations(FlatBaseLocation, FlatRow); ++FlatRow;
        SpawnShape_Cross_AllOrientations(FlatBaseLocation, FlatRow); ++FlatRow;
        SpawnShape_Star_AllOrientations(FlatBaseLocation, FlatRow); ++FlatRow;
        SpawnShape_Checkmark_AllOrientations(FlatBaseLocation, FlatRow); ++FlatRow;
        SpawnShape_Diamond_AllOrientations(FlatBaseLocation, FlatRow); ++FlatRow;

        ck::Trace("📐 Spawned " + FlatRow + " rows of flat shapes (3 orientations each)");

        // Spawn basic 3D shapes station
        auto BasicStationTransform = Get_StationAnchorTransform("Gym.Pmg.BasicShapes", ECk_GymStation_Anchor::PanelCenter);
        auto BasicBaseLocation = BasicStationTransform.GetLocation();

        int BasicRow = 0;
        SpawnShape_Sphere(BasicBaseLocation, BasicRow); ++BasicRow;
        SpawnShape_Box(BasicBaseLocation, BasicRow); ++BasicRow;
        SpawnShape_Cone(BasicBaseLocation, BasicRow); ++BasicRow;
        SpawnShape_Cylinder(BasicBaseLocation, BasicRow); ++BasicRow;
        SpawnShape_Capsule(BasicBaseLocation, BasicRow); ++BasicRow;
        SpawnShape_Pyramid(BasicBaseLocation, BasicRow); ++BasicRow;
        SpawnShape_Hemisphere(BasicBaseLocation, BasicRow); ++BasicRow;
        SpawnShape_Torus(BasicBaseLocation, BasicRow); ++BasicRow;

        ck::Trace("🔷 Spawned " + BasicRow + " basic 3D shapes");

        // Spawn angular shapes station
        auto AngularStationTransform = Get_StationAnchorTransform("Gym.Pmg.AngularShapes", ECk_GymStation_Anchor::PanelCenter);
        auto AngularBaseLocation = AngularStationTransform.GetLocation();

        int AngularRow = 0;
        SpawnShape_Wedge_AllOrientations(AngularBaseLocation, AngularRow); ++AngularRow;
        SpawnShape_Arc_AllOrientations(AngularBaseLocation, AngularRow); ++AngularRow;
        SpawnShape_WedgeCone_AllOrientations(AngularBaseLocation, AngularRow); ++AngularRow;

        ck::Trace("📐 Spawned " + AngularRow + " angular shapes");

        // Spawn directional shapes station
        auto DirectionalStationTransform = Get_StationAnchorTransform("Gym.Pmg.DirectionalShapes", ECk_GymStation_Anchor::PanelCenter);
        auto DirectionalBaseLocation = DirectionalStationTransform.GetLocation();

        int DirectionalRow = 0;
        SpawnShape_Arrow_AllOrientations(DirectionalBaseLocation, DirectionalRow); ++DirectionalRow;
        SpawnShape_Pivot_AllOrientations(DirectionalBaseLocation, DirectionalRow); ++DirectionalRow;
        SpawnShape_DashedLine_AllOrientations(DirectionalBaseLocation, DirectionalRow); ++DirectionalRow;

        ck::Trace("➡️ Spawned " + DirectionalRow + " directional shapes");

        // Spawn icon shapes station
        auto IconStationTransform = Get_StationAnchorTransform("Gym.Pmg.IconShapes", ECk_GymStation_Anchor::PanelCenter);
        auto IconBaseLocation = IconStationTransform.GetLocation();

        int IconRow = 0;
        SpawnShape_Warning_AllOrientations(IconBaseLocation, IconRow); ++IconRow;
        SpawnShape_Prohibition_AllOrientations(IconBaseLocation, IconRow); ++IconRow;
        SpawnShape_NoEntry_AllOrientations(IconBaseLocation, IconRow); ++IconRow;
        SpawnShape_InfoCircle_AllOrientations(IconBaseLocation, IconRow); ++IconRow;

        ck::Trace("⚠️ Spawned " + IconRow + " icon shapes");

        // Spawn symbol shapes station
        auto SymbolStationTransform = Get_StationAnchorTransform("Gym.Pmg.SymbolShapes", ECk_GymStation_Anchor::PanelCenter);
        auto SymbolBaseLocation = SymbolStationTransform.GetLocation();

        int SymbolRow = 0;
        SpawnShape_MagnifyingGlass_AllOrientations(SymbolBaseLocation, SymbolRow); ++SymbolRow;
        SpawnShape_QuestionMark_AllOrientations(SymbolBaseLocation, SymbolRow); ++SymbolRow;
        SpawnShape_ExclamationMark_AllOrientations(SymbolBaseLocation, SymbolRow); ++SymbolRow;
        SpawnShape_Flag_AllOrientations(SymbolBaseLocation, SymbolRow); ++SymbolRow;
        SpawnShape_Pin_AllOrientations(SymbolBaseLocation, SymbolRow); ++SymbolRow;

        ck::Trace("🔍 Spawned " + SymbolRow + " symbol shapes");

        // Spawn text shapes station
        auto TextStationTransform = Get_StationAnchorTransform("Gym.Pmg.TextShapes", ECk_GymStation_Anchor::PanelCenter);
        auto TextBaseLocation = TextStationTransform.GetLocation();

        int TextRow = 0;
        SpawnText_AllOrientations(TextBaseLocation, TextRow); ++TextRow;
        SpawnText_MultiLine(TextBaseLocation, TextRow); ++TextRow;
        SpawnText_CJK(TextBaseLocation, TextRow); ++TextRow;
        SpawnTextSymbols_MixedHP(TextBaseLocation, TextRow); ++TextRow;
        SpawnTextSymbols_MixedStatus(TextBaseLocation, TextRow); ++TextRow;
        SpawnTextSymbols_Arrows(TextBaseLocation, TextRow); ++TextRow;
        SpawnTextSymbols_CardsChess(TextBaseLocation, TextRow); ++TextRow;
        SpawnTextSymbols_MusicStars(TextBaseLocation, TextRow); ++TextRow;
        SpawnTextSymbols_WarningDanger(TextBaseLocation, TextRow); ++TextRow;
        SpawnTextSymbols_Dingbats(TextBaseLocation, TextRow); ++TextRow;
        SpawnTextSymbols_GeometricMisc(TextBaseLocation, TextRow); ++TextRow;
        SpawnTextSymbols_Emoji(TextBaseLocation, TextRow); ++TextRow;

        ck::Trace("🔣 Spawned 9 symbol/emoji rows (text+symbol font fallback)");
        ck::Trace("🔤 Spawned " + TextRow + " text-shape rows");
    }

    //------------------------------------------------------------------------
    // GRID POSITION HELPER
    //------------------------------------------------------------------------

    FVector GetGridPosition(FVector InBaseLocation, int InRow, int InCol)
    {
        // Grid spreads along Y (horizontal) and Z (vertical)
        return FVector(
            InBaseLocation.X,
            InBaseLocation.Y + (InCol * GridSpacing),
            InBaseLocation.Z + 100.0f + (InRow * GridSpacing)
        );
    }

    FLinearColor GetOrientationColor(int InCol)
    {
        if (InCol == 0) return FLinearColor(1.0f, 0.0f, 0.0f, 0.3f); // Red - XY
        if (InCol == 1) return FLinearColor(0.0f, 1.0f, 0.0f, 0.3f); // Green - XZ
        return FLinearColor(0.0f, 0.0f, 1.0f, 0.3f); // Blue - YZ
    }

    ECk_Plane_Axis GetOrientationAxis(int InCol)
    {
        if (InCol == 0) return ECk_Plane_Axis::XY;
        if (InCol == 1) return ECk_Plane_Axis::XZ;
        return ECk_Plane_Axis::YZ;
    }

    //------------------------------------------------------------------------
    // FLAT SHAPES - ALL ORIENTATIONS
    //------------------------------------------------------------------------

    void SpawnShape_Circle_AllOrientations(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Handle = utils_pmg_flat_shapes::DrawFilledCircle(Pos, ShapeSize, 32,
                GetOrientationColor(Col), true, 2.0f, true, GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    void SpawnShape_Triangle_AllOrientations(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Handle = utils_pmg_flat_shapes::DrawFilledTriangle(Pos, ShapeSize,
                GetOrientationColor(Col), true, 2.0f, GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    void SpawnShape_Plane_AllOrientations(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Handle = utils_pmg_flat_shapes::DrawFilledPlane(Pos, ShapeSize * 2, ShapeSize * 2,
                FRotator(), GetOrientationColor(Col), true, 2.0f, GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    void SpawnShape_Ring_AllOrientations(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Handle = utils_pmg_flat_shapes::DrawFilledRing(Pos, ShapeSize, ShapeSize * 0.5f, 32,
                GetOrientationColor(Col), true, 2.0f, GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    void SpawnShape_Cross_AllOrientations(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Handle = utils_pmg_flat_shapes::DrawFilledCross(Pos, ShapeSize, ShapeSize * 0.2f,
                GetOrientationColor(Col), true, 2.0f, GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    void SpawnShape_Star_AllOrientations(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Handle = utils_pmg_flat_shapes::DrawFilledStar(Pos, ShapeSize, 5, 0.5f,
                GetOrientationColor(Col), true, 2.0f, GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    void SpawnShape_Checkmark_AllOrientations(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Handle = utils_pmg_flat_shapes::DrawFilledCheckmark(Pos, ShapeSize, 8.0f,
                GetOrientationColor(Col), true, 2.0f, GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    void SpawnShape_Diamond_AllOrientations(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Handle = utils_pmg_flat_shapes::DrawFilledDiamond(Pos, ShapeSize, ShapeSize * 1.5f,
                GetOrientationColor(Col), true, 2.0f, GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    //------------------------------------------------------------------------
    // BASIC 3D SHAPES - ALL ORIENTATIONS
    //------------------------------------------------------------------------

    void SpawnShape_Sphere(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Handle = utils_pmg_basic_shapes::DrawFilledSphere(Pos, ShapeSize, 16, 16,
                GetOrientationColor(Col), true, 2.0f, GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    void SpawnShape_Box(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Extent = FVector(ShapeSize * 0.8f, ShapeSize * 0.8f, ShapeSize * 0.8f);
            auto Handle = utils_pmg_basic_shapes::DrawFilledBox(Pos, Extent,
                GetOrientationColor(Col), true, 2.0f, GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    void SpawnShape_Cone(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Handle = utils_pmg_basic_shapes::DrawFilledCone(Pos, ShapeSize * 0.7f, ShapeSize * 1.5f, 16,
                GetOrientationColor(Col), true, 2.0f, GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    void SpawnShape_Cylinder(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Handle = utils_pmg_basic_shapes::DrawFilledCylinder(Pos, ShapeSize * 0.6f, ShapeSize * 1.4f, 16,
                GetOrientationColor(Col), true, 2.0f, GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    void SpawnShape_Capsule(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Handle = utils_pmg_basic_shapes::DrawFilledCapsule(Pos, ShapeSize * 0.4f, ShapeSize * 0.8f,
                16, 8, GetOrientationColor(Col), true, 2.0f, GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    void SpawnShape_Pyramid(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Handle = utils_pmg_basic_shapes::DrawFilledPyramid(Pos, ShapeSize * 1.2f, ShapeSize,
                GetOrientationColor(Col), true, 2.0f, GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    void SpawnShape_Hemisphere(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Handle = utils_pmg_basic_shapes::DrawFilledHemisphere(Pos, ShapeSize, 16, 8,
                GetOrientationColor(Col), true, 2.0f, GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    void SpawnShape_Torus(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Handle = utils_pmg_basic_shapes::DrawFilledTorus(Pos, ShapeSize * 0.8f, ShapeSize * 0.2f, 32, 16,
                GetOrientationColor(Col), true, 2.0f, GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    //------------------------------------------------------------------------
    // ANGULAR SHAPES - ALL ORIENTATIONS
    //------------------------------------------------------------------------

    void SpawnShape_Wedge_AllOrientations(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Handle = utils_pmg_angular_shapes::DrawFilledWedge(Pos, ShapeSize, 0.0f, 90.0f, 32,
                GetOrientationColor(Col), true, 2.0f, GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    void SpawnShape_Arc_AllOrientations(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Handle = utils_pmg_angular_shapes::DrawFilledArc(Pos, ShapeSize, 0.0f, 90.0f, ShapeSize * 0.2f, 32,
                GetOrientationColor(Col), true, 2.0f, GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    void SpawnShape_WedgeCone_AllOrientations(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Handle = utils_pmg_angular_shapes::DrawFilledWedgeCone(Pos, FRotator(), ShapeSize * 0.7f, ShapeSize * 1.5f, 0.0f, 90.0f, 16,
                GetOrientationColor(Col), true, 2.0f, GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    //------------------------------------------------------------------------
    // DIRECTIONAL SHAPES - ALL ORIENTATIONS
    //------------------------------------------------------------------------

    void SpawnShape_Arrow_AllOrientations(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Handle = utils_pmg_directional_shapes::DrawFilledArrow(Pos, FRotator(), ShapeSize * 2.0f,
                ShapeSize * 0.3f, 0.3f, 2.0f, GetOrientationColor(Col), true, 2.0f,
                GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    void SpawnShape_Pivot_AllOrientations(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Handle = utils_pmg_directional_shapes::DrawPivot(Pos, FRotator(),
                ShapeSize * 1.2f, ShapeSize * 0.3f, GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    void SpawnShape_DashedLine_AllOrientations(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto LineStart = Pos - FVector(ShapeSize, 0.0f, 0.0f);
            auto LineEnd = Pos + FVector(ShapeSize, 0.0f, 0.0f);
            auto Handle = utils_pmg_directional_shapes::DrawDashedLine(LineStart, LineEnd,
                ShapeSize * 0.3f, ShapeSize * 0.15f, 3.0f, GetOrientationColor(Col),
                GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    //------------------------------------------------------------------------
    // ICON SHAPES - ALL ORIENTATIONS
    //------------------------------------------------------------------------

    void SpawnShape_Warning_AllOrientations(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Handle = utils_pmg_icon_shapes::DrawFilledWarning(Pos, ShapeSize,
                GetOrientationColor(Col), true, 2.0f, GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    void SpawnShape_Prohibition_AllOrientations(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Handle = utils_pmg_icon_shapes::DrawFilledProhibition(Pos, ShapeSize, 32,
                GetOrientationColor(Col), true, 2.0f, GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    void SpawnShape_NoEntry_AllOrientations(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Handle = utils_pmg_icon_shapes::DrawFilledNoEntry(Pos, ShapeSize, 32,
                GetOrientationColor(Col), true, 2.0f, GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    void SpawnShape_InfoCircle_AllOrientations(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Handle = utils_pmg_icon_shapes::DrawFilledInfoCircle(Pos, ShapeSize, 32,
                GetOrientationColor(Col), true, 2.0f, GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    //------------------------------------------------------------------------
    // SYMBOL SHAPES - ALL ORIENTATIONS
    //------------------------------------------------------------------------

    void SpawnShape_MagnifyingGlass_AllOrientations(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Handle = utils_pmg_symbol_shapes::DrawFilledMagnifyingGlass(Pos, ShapeSize * 0.6f,
                GetOrientationColor(Col), true, 2.0f, GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    void SpawnShape_QuestionMark_AllOrientations(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Handle = utils_pmg_symbol_shapes::DrawFilledQuestionMark(Pos, ShapeSize,
                GetOrientationColor(Col), true, 2.0f, GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    void SpawnShape_ExclamationMark_AllOrientations(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Handle = utils_pmg_symbol_shapes::DrawFilledExclamationMark(Pos, ShapeSize,
                GetOrientationColor(Col), true, 2.0f, GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    void SpawnShape_Flag_AllOrientations(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Handle = utils_pmg_symbol_shapes::DrawFilledFlag(Pos, ShapeSize,
                GetOrientationColor(Col), true, 2.0f, GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    void SpawnShape_Pin_AllOrientations(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Handle = utils_pmg_symbol_shapes::DrawFilledPin(Pos, ShapeSize,
                GetOrientationColor(Col), true, 2.0f, GetOrientationAxis(Col), 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    //------------------------------------------------------------------------
    // TEXT SHAPES
    //------------------------------------------------------------------------

    void SpawnText_AllOrientations(FVector InBase, int InRow)
    {
        for (int Col = 0; Col < 3; ++Col)
        {
            auto Pos = GetGridPosition(InBase, InRow, Col - 1);
            auto Handle = utils_pmg_text_shapes::DrawText(Pos, "Hello 123", ShapeSize,
                GetOrientationColor(Col), true, true, 2.0f,
                ECk_Pmg_TextAlign::Left, GetOrientationAxis(Col), nullptr, 500.0f);
            SpawnedShapes.Add(Handle);
        }
    }

    void SpawnText_MultiLine(FVector InBase, int InRow)
    {
        auto Pos = GetGridPosition(InBase, InRow, 0);
        auto Handle = utils_pmg_text_shapes::DrawText(Pos, "line one\nline two", ShapeSize,
            FLinearColor(1.0f, 1.0f, 1.0f, 0.5f), true, true, 2.0f,
            ECk_Pmg_TextAlign::Center, ECk_Plane_Axis::XZ, nullptr, 500.0f);
        SpawnedShapes.Add(Handle);
    }

    void SpawnText_CJK(FVector InBase, int InRow)
    {
        auto Pos = GetGridPosition(InBase, InRow, 0);
        // CJK renders as .notdef boxes until the bundled Noto CJK font is imported — intentional.
        auto Handle = utils_pmg_text_shapes::DrawText(Pos, "CJK-needs-Noto", ShapeSize,
            FLinearColor(1.0f, 0.8f, 0.0f, 0.6f), true, true, 2.0f,
            ECk_Pmg_TextAlign::Left, ECk_Plane_Axis::XZ, nullptr, 500.0f);
        SpawnedShapes.Add(Handle);
    }

    //------------------------------------------------------------------------
    // TEXT SHAPES — SYMBOL/EMOJI ROWS (font fallback: text font -> Noto Emoji -> Noto Sans Symbols 2)
    // All strings built ASCII-only via MakeText_FromHexCodepoints; no non-ASCII literals in source.
    //------------------------------------------------------------------------

    // Mixed text + symbol on one line (fallback: letters from text font, heart from Symbols 2).
    void SpawnTextSymbols_MixedHP(FVector InBase, int InRow)
    {
        auto Pos = GetGridPosition(InBase, InRow, 0);
        auto S = "HP 100 " + utils_pmg_text_shapes::MakeText_FromHexCodepoints("2665");
        auto Handle = utils_pmg_text_shapes::DrawText(Pos, S, ShapeSize,
            FLinearColor(1.0f, 0.3f, 0.3f, 0.85f), true, true, 2.0f,
            ECk_Pmg_TextAlign::Left, ECk_Plane_Axis::XZ, nullptr, 500.0f);
        SpawnedShapes.Add(Handle);
    }

    void SpawnTextSymbols_MixedStatus(FVector InBase, int InRow)
    {
        auto Pos = GetGridPosition(InBase, InRow, 0);
        auto S = "Wave 3 " + utils_pmg_text_shapes::MakeText_FromHexCodepoints("26A0")
               + "  Lv 5 " + utils_pmg_text_shapes::MakeText_FromHexCodepoints("2B50")
               + "  Boss " + utils_pmg_text_shapes::MakeText_FromHexCodepoints("2620");
        auto Handle = utils_pmg_text_shapes::DrawText(Pos, S, ShapeSize,
            FLinearColor(1.0f, 0.9f, 0.4f, 0.85f), true, true, 2.0f,
            ECk_Pmg_TextAlign::Left, ECk_Plane_Axis::XZ, nullptr, 500.0f);
        SpawnedShapes.Add(Handle);
    }

    void SpawnTextSymbols_Arrows(FVector InBase, int InRow)
    {
        auto Pos = GetGridPosition(InBase, InRow, 0);
        auto S = utils_pmg_text_shapes::MakeText_FromHexCodepoints("2190 2191 2192 2193 2194 2195 2196 2197 2198 2199");
        auto Handle = utils_pmg_text_shapes::DrawText(Pos, S, ShapeSize,
            FLinearColor(0.6f, 0.9f, 1.0f, 0.85f), true, true, 2.0f,
            ECk_Pmg_TextAlign::Left, ECk_Plane_Axis::XZ, nullptr, 500.0f);
        SpawnedShapes.Add(Handle);
    }

    void SpawnTextSymbols_CardsChess(FVector InBase, int InRow)
    {
        auto Pos = GetGridPosition(InBase, InRow, 0);
        auto S = utils_pmg_text_shapes::MakeText_FromHexCodepoints("2660 2665 2666 2663 2654 2655 2656 2657 2658 2659");
        auto Handle = utils_pmg_text_shapes::DrawText(Pos, S, ShapeSize,
            FLinearColor(0.9f, 0.9f, 0.9f, 0.85f), true, true, 2.0f,
            ECk_Pmg_TextAlign::Left, ECk_Plane_Axis::XZ, nullptr, 500.0f);
        SpawnedShapes.Add(Handle);
    }

    void SpawnTextSymbols_MusicStars(FVector InBase, int InRow)
    {
        auto Pos = GetGridPosition(InBase, InRow, 0);
        auto S = utils_pmg_text_shapes::MakeText_FromHexCodepoints("2669 266A 266B 266C 266D 266E 266F 2605 2606 2736");
        auto Handle = utils_pmg_text_shapes::DrawText(Pos, S, ShapeSize,
            FLinearColor(0.8f, 0.7f, 1.0f, 0.85f), true, true, 2.0f,
            ECk_Pmg_TextAlign::Left, ECk_Plane_Axis::XZ, nullptr, 500.0f);
        SpawnedShapes.Add(Handle);
    }

    void SpawnTextSymbols_WarningDanger(FVector InBase, int InRow)
    {
        auto Pos = GetGridPosition(InBase, InRow, 0);
        auto S = utils_pmg_text_shapes::MakeText_FromHexCodepoints("26A0 2622 2623 2620 26D4 2607 2621 2691 2692 2694");
        auto Handle = utils_pmg_text_shapes::DrawText(Pos, S, ShapeSize,
            FLinearColor(1.0f, 0.5f, 0.2f, 0.85f), true, true, 2.0f,
            ECk_Pmg_TextAlign::Left, ECk_Plane_Axis::XZ, nullptr, 500.0f);
        SpawnedShapes.Add(Handle);
    }

    void SpawnTextSymbols_Dingbats(FVector InBase, int InRow)
    {
        auto Pos = GetGridPosition(InBase, InRow, 0);
        auto S = utils_pmg_text_shapes::MakeText_FromHexCodepoints("2702 2708 2709 270F 2712 2713 2714 2716 2717 2764");
        auto Handle = utils_pmg_text_shapes::DrawText(Pos, S, ShapeSize,
            FLinearColor(0.5f, 1.0f, 0.6f, 0.85f), true, true, 2.0f,
            ECk_Pmg_TextAlign::Left, ECk_Plane_Axis::XZ, nullptr, 500.0f);
        SpawnedShapes.Add(Handle);
    }

    void SpawnTextSymbols_GeometricMisc(FVector InBase, int InRow)
    {
        auto Pos = GetGridPosition(InBase, InRow, 0);
        auto S = utils_pmg_text_shapes::MakeText_FromHexCodepoints("25A0 25A1 25B2 25BC 25C6 25CF 25D0 25B6 25C0 2699");
        auto Handle = utils_pmg_text_shapes::DrawText(Pos, S, ShapeSize,
            FLinearColor(0.7f, 0.85f, 0.95f, 0.85f), true, true, 2.0f,
            ECk_Pmg_TextAlign::Left, ECk_Plane_Axis::XZ, nullptr, 500.0f);
        SpawnedShapes.Add(Handle);
    }

    // Emoji come from the bundled Noto Emoji font (monochrome silhouettes, U+1F300+).
    void SpawnTextSymbols_Emoji(FVector InBase, int InRow)
    {
        auto Pos = GetGridPosition(InBase, InRow, 0);
        auto S = utils_pmg_text_shapes::MakeText_FromHexCodepoints("1F600 1F603 1F60E 1F525 1F480 1F3C6 1F44D 1F3AF 1F680 1F3AE");
        auto Handle = utils_pmg_text_shapes::DrawText(Pos, S, ShapeSize,
            FLinearColor(1.0f, 0.85f, 0.5f, 0.9f), true, true, 2.0f,
            ECk_Pmg_TextAlign::Left, ECk_Plane_Axis::XZ, nullptr, 500.0f);
        SpawnedShapes.Add(Handle);
    }

    //------------------------------------------------------------------------
    // CLEANUP
    //------------------------------------------------------------------------

    void Request_ClearAllShapes()
    {
        for (auto Handle : SpawnedShapes)
        {
            if (ck::IsValid(Handle))
            {
                utils_entity_lifetime::Request_DestroyEntity(Handle);
            }
        }
        SpawnedShapes.Empty();
    }

    //------------------------------------------------------------------------
    // CONSOLE COMMANDS
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="PMG Gym - Regenerate All Shapes")
    void Ck_GymPmg_RegenerateAll()
    {
        Request_SpawnAllShapes();
        ck::Trace("✅ All PMG shapes regenerated");
    }

    UFUNCTION(Exec, DisplayName="PMG Gym - Clear All Shapes")
    void Ck_GymPmg_ClearAll()
    {
        Request_ClearAllShapes();
        ck::Trace("🗑️ All PMG shapes cleared");
    }

    UFUNCTION(Exec, DisplayName="PMG Gym - Set Grid Spacing")
    void Ck_GymPmg_SetGridSpacing(float32 InSpacing)
    {
        GridSpacing = InSpacing;
        Request_SpawnAllShapes();
        ck::Trace("📏 Grid spacing set to " + InSpacing + " and shapes regenerated");
    }

    UFUNCTION(Exec, DisplayName="PMG Gym - Set Shape Size")
    void Ck_GymPmg_SetShapeSize(float32 InSize)
    {
        ShapeSize = InSize;
        Request_SpawnAllShapes();
        ck::Trace("📐 Shape size set to " + InSize + " and shapes regenerated");
    }
}
