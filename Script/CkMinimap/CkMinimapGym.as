// Language=angelscript

//============================================================================
// CK MINIMAP GYM
//
// Interactive minimap + fog-of-war playground. The gym pawn carries an
// observer-centric minimap surfaced through the zero-asset reference widget
// (UCk_MinimapFrame_Widget) in the top-right of the viewport; walking and
// mouse-turning the pawn drives the projection live.
//
// Stations (content built toward -X from each anchor — house rule):
//   - PoiField:  a POI cluster (Quest/Shop/Danger/Info, varied priorities,
//                one far ClampToEdge waypoint pinned to the frame rim)
//   - WorldMap:  a FixedBounds projection over the station area; readout via
//                Ck_GymMinimap_Readout
//   - FogWalk:   a fog grid over the station; the pawn is a revealer — walk
//                to paint exploration; link/unlink it to the HUD minimap
//   - Stress:    500 standalone POIs on demand (Ck_GymMinimap_Stress500)
//
// Exec commands:
//   Ck_GymMinimap_ZoomIn / ZoomOut  — halve / double the view extent
//   Ck_GymMinimap_ToggleRotation    — NorthLocked <-> RotateWithObserver
//   Ck_GymMinimap_ToggleFog         — link/unlink the FogWalk grid to the HUD minimap
//   Ck_GymMinimap_RevealAll         — reveal the whole FogWalk grid
//   Ck_GymMinimap_ResetFog          — reset the FogWalk grid to fully fogged
//   Ck_GymMinimap_Stress500         — spawn the stress field
//   Ck_GymMinimap_ClearStress       — destroy the stress field
//   Ck_GymMinimap_Readout           — dump entries + fog fraction to the log
//============================================================================

class ACk_MinimapGym_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_MinimapGym_PlayerController;
    default DefaultPawnClass = ACk_MinimapGym_Pawn;
}

class ACk_MinimapGym_Pawn : ACk_Gym_Base_Pawn
{
    // ADefaultPawn leaves the ACTOR un-yawed under mouse-look — the minimap's view yaw reads the pawn
    // ENTITY's actor-synced transform yaw, so the actor must follow the controller for
    // RotateWithObserver (and the HUD's facing) to track the mouse.
    default bUseControllerRotationYaw = true;

    private FCk_Handle _PawnEntity;
    private FCk_Handle_Minimap _Minimap;

    void OnEntityConstructed(FCk_Handle_EntityScript InEntityScriptHandle) override
    {
        _PawnEntity = FCk_Handle(InEntityScriptHandle);

        auto Params = FCk_Fragment_Minimap_ParamsData(3000.0);
        Params.Set_MaxEntries(32);
        _Minimap = utils_minimap::Add(_PawnEntity, Params);

        ck::Trace("MinimapGym: observer-centric minimap composed on pawn entity");
    }

    FCk_Handle Get_PawnEntity()
    {
        return _PawnEntity;
    }

    FCk_Handle_Minimap Get_Minimap()
    {
        return _Minimap;
    }
}

class ACk_MinimapGym_PlayerController : ACk_Gym_Base_PlayerController
{
    private FVector _PoiFieldOrigin = FVector::ZeroVector;
    private FVector _WorldMapOrigin = FVector::ZeroVector;
    private FVector _FogWalkOrigin = FVector::ZeroVector;
    private FVector _StressOrigin = FVector::ZeroVector;

    private FCk_Handle_Minimap _WorldMap;
    private FCk_Handle_FogOfWar _Fog;
    private TArray<FCk_Handle> _StressPois;
    private UCk_MinimapFrame_Widget _HudWidget;
    private int32 _HudWidgetRetries = 0;
    private bool _RotateWithObserver = false;
    private bool _FogLinked = false;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        auto PoiField = FCkGym_Station_SpawnParams_Payload();
        PoiField.Tags.Add(n"Gym.Minimap.PoiField");
        PoiField.Title = FText::FromString("MINIMAP");
        auto PoiFieldDescription = TArray<FText>();
        PoiFieldDescription.Add(FText::FromString("POI cluster around the station.\nWalk + mouse-turn to drive the HUD minimap."));
        PoiFieldDescription.Add(FText::FromString("Ck_GymMinimap_ZoomIn / ZoomOut\nCk_GymMinimap_ToggleRotation"));
        PoiField.Description = PoiFieldDescription;
        PoiField.AutoSize = true;
        Stations.Add(PoiField);

        auto WorldMap = FCkGym_Station_SpawnParams_Payload();
        WorldMap.Tags.Add(n"Gym.Minimap.WorldMap");
        WorldMap.Title = FText::FromString("WORLD MAP");
        auto WorldMapDescription = TArray<FText>();
        WorldMapDescription.Add(FText::FromString("FixedBounds projection over the station area."));
        WorldMapDescription.Add(FText::FromString("Ck_GymMinimap_Readout"));
        WorldMap.Description = WorldMapDescription;
        WorldMap.AutoSize = true;
        Stations.Add(WorldMap);

        auto FogWalk = FCkGym_Station_SpawnParams_Payload();
        FogWalk.Tags.Add(n"Gym.Minimap.FogWalk");
        FogWalk.Title = FText::FromString("FOG WALK");
        auto FogWalkDescription = TArray<FText>();
        FogWalkDescription.Add(FText::FromString("The pawn reveals fog as it walks this station."));
        FogWalkDescription.Add(FText::FromString("Ck_GymMinimap_ToggleFog\nCk_GymMinimap_RevealAll\nCk_GymMinimap_ResetFog"));
        FogWalk.Description = FogWalkDescription;
        FogWalk.AutoSize = true;
        Stations.Add(FogWalk);

        auto Stress = FCkGym_Station_SpawnParams_Payload();
        Stress.Tags.Add(n"Gym.Minimap.Stress");
        Stress.Title = FText::FromString("MINIMAP STRESS");
        auto StressDescription = TArray<FText>();
        StressDescription.Add(FText::FromString("500 POIs on demand — watch the projector's cost."));
        StressDescription.Add(FText::FromString("Ck_GymMinimap_Stress500\nCk_GymMinimap_ClearStress"));
        Stress.Description = StressDescription;
        Stress.AutoSize = true;
        Stations.Add(Stress);

        return Stations;
    }

    void Request_StartGym() override
    {
        _PoiFieldOrigin = Get_StationAnchorLocation("Gym.Minimap.PoiField", ECk_GymStation_Anchor::FootprintCenter);
        _WorldMapOrigin = Get_StationAnchorLocation("Gym.Minimap.WorldMap", ECk_GymStation_Anchor::FootprintCenter);
        _FogWalkOrigin = Get_StationAnchorLocation("Gym.Minimap.FogWalk", ECk_GymStation_Anchor::FootprintCenter);
        _StressOrigin = Get_StationAnchorLocation("Gym.Minimap.Stress", ECk_GymStation_Anchor::FootprintCenter);

        DoBuildPoiField();
        DoBuildWorldMap();
        DoBuildFogWalk();
        DoCreateHudWidget();

        SetActorTickEnabled(true);
        ck::Trace("MinimapGym: started — POI field + world map + fog grid built");
    }

    private void DoBuildPoiField()
    {
        auto Center = _PoiFieldOrigin + FVector(-800.0, 0.0, 100.0);

        // 8 cluster positions at 45-degree steps, radius 600 (precomputed — no trig dependency).
        DoAddPoi(Center + FVector(600.0, 0.0, 0.0),      n"Poi.Category.Quest",  5);
        DoAddPoi(Center + FVector(424.3, 424.3, 0.0),    n"Poi.Category.Shop",   3);
        DoAddPoi(Center + FVector(0.0, 600.0, 0.0),      n"Poi.Category.Danger", 4);
        DoAddPoi(Center + FVector(-424.3, 424.3, 0.0),   n"Poi.Category.Info",   1);
        DoAddPoi(Center + FVector(-600.0, 0.0, 0.0),     n"Poi.Category.Quest",  2);
        DoAddPoi(Center + FVector(-424.3, -424.3, 0.0),  n"Poi.Category.Shop",   1);
        DoAddPoi(Center + FVector(0.0, -600.0, 0.0),     n"Poi.Category.Danger", 3);
        DoAddPoi(Center + FVector(424.3, -424.3, 0.0),   n"Poi.Category.Info",   2);

        // One far ClampToEdge waypoint — pins to the frame rim from anywhere in the gym.
        auto WaypointParams = FCk_Fragment_Poi_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Waypoint"));
        WaypointParams.Set_OffscreenPolicy(ECk_Poi_OffscreenPolicy::ClampToEdge);
        WaypointParams.Set_Priority(10);
        DoCreateStandalonePoi(FTransform(FRotator::ZeroRotator, Center + FVector(-6000.0, 0.0, 0.0)),
            WaypointParams);

        utils_pmg_basic_shapes::DrawFilledSphere(Center + FVector(-6000.0, 0.0, 60.0), 55.0, 12, 12,
            FLinearColor(0.7, 0.35, 0.95), true, 2.0, ECk_Plane_Axis::XY, -1.0);
    }

    private void DoBuildWorldMap()
    {
        auto GymPawn = Cast<ACk_MinimapGym_Pawn>(ControlledPawn);
        if (GymPawn == nullptr)
        { return; }

        // A FixedBounds projection over the world-map station area, hosted on its own entity
        // (parented off the pawn entity — the gym PlayerController is not ECS-backed).
        auto PawnEntity = GymPawn.Get_PawnEntity();
        auto Host = utils_entity_lifetime::Request_CreateEntity(PawnEntity);
        Host.Request_OverrideToSelf();
        utils_transform::Add(Host, FTransform(FRotator::ZeroRotator, _WorldMapOrigin),
            ECk_Replication::DoesNotReplicate);

        auto Params = FCk_Fragment_Minimap_ParamsData(3000.0);
        Params.Set_ProjectionMode(ECk_Minimap_ProjectionMode::FixedBounds);
        Params.Set_FixedBounds(FCk_Minimap_WorldBounds(
            FVector2D(_WorldMapOrigin.X - 800.0, _WorldMapOrigin.Y), FVector2D(3000.0, 3000.0)));
        _WorldMap = utils_minimap::Add(Host, Params);

        DoDrawBoundsOutline(FVector2D(_WorldMapOrigin.X - 800.0, _WorldMapOrigin.Y),
            FVector2D(3000.0, 3000.0), _WorldMapOrigin.Z + 30.0, FLinearColor(0.35, 0.56, 0.83));
    }

    private void DoBuildFogWalk()
    {
        auto GymPawn = Cast<ACk_MinimapGym_Pawn>(ControlledPawn);
        if (GymPawn == nullptr)
        { return; }

        auto PawnEntity = GymPawn.Get_PawnEntity();
        auto Host = utils_entity_lifetime::Request_CreateEntity(PawnEntity);
        Host.Request_OverrideToSelf();

        auto Params = FCk_Fragment_FogOfWar_ParamsData(FCk_Minimap_WorldBounds(
            FVector2D(_FogWalkOrigin.X - 800.0, _FogWalkOrigin.Y), FVector2D(2500.0, 2500.0)));
        Params.Set_CellSize(250.0);
        Params.Set_RevealRadius(600.0);
        _Fog = utils_fog_of_war::Add(Host, Params);

        _Fog.Request_AddRevealer(PawnEntity);

        DoDrawBoundsOutline(FVector2D(_FogWalkOrigin.X - 800.0, _FogWalkOrigin.Y),
            FVector2D(2500.0, 2500.0), _FogWalkOrigin.Z + 30.0, FLinearColor(0.61, 0.5, 0.83));
    }

    UFUNCTION()
    private void DoCreateHudWidget()
    {
        // The pawn composes its minimap in OnEntityConstructed (deferred entity construction) — at gym
        // start it usually is not there YET. Retry on a short timer instead of silently giving up.
        auto Minimap = DoGet_Minimap();
        if (ck::Is_NOT_Valid(Minimap))
        {
            _HudWidgetRetries++;
            if (_HudWidgetRetries <= 40)
            { System::SetTimer(this, n"DoCreateHudWidget", 0.25, false); }
            else
            { ck::Trace("MinimapGym: pawn minimap never appeared — no HUD widget (use Ck_GymMinimap_Readout)"); }
            return;
        }

        _HudWidget = Cast<UCk_MinimapFrame_Widget>(
            WidgetBlueprint::CreateWidget(UCk_MinimapFrame_Widget, this));
        if (_HudWidget == nullptr)
        {
            ck::Trace("MinimapGym: HUD widget creation failed — use Ck_GymMinimap_Readout instead");
            return;
        }

        _HudWidget.AddToViewport();
        _HudWidget.SetAnchorsInViewport(FAnchors(1.0, 0.0, 1.0, 0.0));
        _HudWidget.SetAlignmentInViewport(FVector2D(1.0, 0.0));
        _HudWidget.SetPositionInViewport(FVector2D(-24.0, 24.0), false);
        _HudWidget.SetDesiredSizeInViewport(FVector2D(280.0, 280.0));
        _HudWidget.Set_Minimap(Minimap);
    }

    private FCk_Handle_Minimap DoGet_Minimap()
    {
        auto GymPawn = Cast<ACk_MinimapGym_Pawn>(ControlledPawn);
        if (GymPawn == nullptr)
        { return FCk_Handle_Minimap(); }
        return GymPawn.Get_Minimap();
    }

    private void DoAddPoi(FVector InLocation, FName InCategoryName, int32 InPriority)
    {
        auto Params = FCk_Fragment_Poi_ParamsData(utils_gameplay_tag::ResolveGameplayTag(InCategoryName));
        Params.Set_Priority(InPriority);
        DoCreateStandalonePoi(FTransform(FRotator::ZeroRotator, InLocation), Params);

        // Persistent in-world marker so the POI is visible where it stands (color = category)
        utils_pmg_basic_shapes::DrawFilledSphere(InLocation + FVector(0.0, 0.0, 60.0), 40.0, 12, 12,
            DoGet_CategoryColor(InCategoryName), true, 2.0, ECk_Plane_Axis::XY, -1.0);
    }

    // The standalone-POI pattern (utils_poi::Create was removed): own entity under the world's
    // TransientEntity + Transform at the target location + Poi composed directly on it. Destroying
    // the returned handle's entity removes the whole POI.
    private FCk_Handle_Poi DoCreateStandalonePoi(FTransform InTransform, FCk_Fragment_Poi_ParamsData InParams)
    {
        FCk_Handle TransientOwner = ck::TransientEntity();
        auto Host = utils_entity_lifetime::Request_CreateEntity(TransientOwner);
        utils_transform::Add(Host, InTransform, ECk_Replication::DoesNotReplicate);
        return utils_poi::Add(Host, InParams);
    }

    private FLinearColor DoGet_CategoryColor(FName InCategoryName)
    {
        if (InCategoryName == n"Poi.Category.Quest")  { return FLinearColor(1.0, 0.78, 0.25); }
        if (InCategoryName == n"Poi.Category.Shop")   { return FLinearColor(0.95, 0.5, 0.2); }
        if (InCategoryName == n"Poi.Category.Danger") { return FLinearColor(0.9, 0.25, 0.25); }
        if (InCategoryName == n"Poi.Category.Info")   { return FLinearColor(0.35, 0.6, 0.95); }
        return FLinearColor(0.8, 0.8, 0.85);
    }

    // Long-lived outlines for the fixed rectangles (world-map bounds in blue, fog bounds in violet)
    private void DoDrawBoundsOutline(FVector2D InCenter, FVector2D InHalfExtents, float InZ, FLinearColor InColor)
    {
        auto A = FVector(InCenter.X - InHalfExtents.X, InCenter.Y - InHalfExtents.Y, InZ);
        auto B = FVector(InCenter.X - InHalfExtents.X, InCenter.Y + InHalfExtents.Y, InZ);
        auto C = FVector(InCenter.X + InHalfExtents.X, InCenter.Y + InHalfExtents.Y, InZ);
        auto D = FVector(InCenter.X + InHalfExtents.X, InCenter.Y - InHalfExtents.Y, InZ);

        UCk_Utils_DebugDraw_UE::DrawDebugLine(A, B, InColor, 3600.0, 4.0);
        UCk_Utils_DebugDraw_UE::DrawDebugLine(B, C, InColor, 3600.0, 4.0);
        UCk_Utils_DebugDraw_UE::DrawDebugLine(C, D, InColor, 3600.0, 4.0);
        UCk_Utils_DebugDraw_UE::DrawDebugLine(D, A, InColor, 3600.0, 4.0);
    }

    // Facing needle from the pawn, redrawn every frame — mirrors what the HUD's arrow should do
    private void DoDrawFacingNeedle(FCk_Handle_Minimap InMinimap)
    {
        if (ControlledPawn == nullptr)
        { return; }

        auto Base = ControlledPawn.GetActorLocation() + FVector(0.0, 0.0, 30.0);
        auto ViewYaw = utils_minimap::Get_ViewYawDegrees(InMinimap);
        auto Rad = ViewYaw * Math::PI / 180.0;
        auto Dir = FVector(Math::Cos(Rad), Math::Sin(Rad), 0.0);

        UCk_Utils_DebugDraw_UE::DrawDebugLine(Base, Base + Dir * 400.0,
            FLinearColor(0.35, 0.56, 0.83), 0.05, 6.0);
    }

    UFUNCTION(BlueprintOverride)
    void Tick(float InDeltaSeconds)
    {
        auto Minimap = DoGet_Minimap();
        if (ck::Is_NOT_Valid(Minimap))
        { return; }

        DoDrawFacingNeedle(Minimap);
    }

    UFUNCTION(Exec, DisplayName="Minimap Gym - Zoom In")
    void Ck_GymMinimap_ZoomIn()
    {
        auto Minimap = DoGet_Minimap();
        if (ck::Is_NOT_Valid(Minimap))
        { return; }

        auto NewExtent = Math::Max(utils_minimap::Get_ViewExtent(Minimap) * 0.5, 500.0);
        Minimap.Request_SetViewExtent(NewExtent);
        ck::Trace(f"MinimapGym: view extent -> {NewExtent}");
    }

    UFUNCTION(Exec, DisplayName="Minimap Gym - Zoom Out")
    void Ck_GymMinimap_ZoomOut()
    {
        auto Minimap = DoGet_Minimap();
        if (ck::Is_NOT_Valid(Minimap))
        { return; }

        auto NewExtent = Math::Min(utils_minimap::Get_ViewExtent(Minimap) * 2.0, 24000.0);
        Minimap.Request_SetViewExtent(NewExtent);
        ck::Trace(f"MinimapGym: view extent -> {NewExtent}");
    }

    UFUNCTION(Exec, DisplayName="Minimap Gym - Toggle Rotation")
    void Ck_GymMinimap_ToggleRotation()
    {
        auto Minimap = DoGet_Minimap();
        if (ck::Is_NOT_Valid(Minimap))
        { return; }

        _RotateWithObserver = !_RotateWithObserver;
        if (_RotateWithObserver)
        {
            Minimap.Request_SetRotationMode(ECk_Minimap_RotationMode::RotateWithObserver);
            ck::Trace("MinimapGym: rotation mode = RotateWithObserver");
            return;
        }

        Minimap.Request_SetRotationMode(ECk_Minimap_RotationMode::NorthLocked);
        ck::Trace("MinimapGym: rotation mode = NorthLocked");
    }

    UFUNCTION(Exec, DisplayName="Minimap Gym - Toggle Fog Link")
    void Ck_GymMinimap_ToggleFog()
    {
        auto Minimap = DoGet_Minimap();
        if (ck::Is_NOT_Valid(Minimap))
        { return; }

        _FogLinked = !_FogLinked;
        if (_FogLinked)
        {
            Minimap.Request_SetFogOfWar(_Fog);
            ck::Trace("MinimapGym: HUD minimap now culls unexplored POIs (fog linked)");
            return;
        }

        Minimap.Request_SetFogOfWar(FCk_Handle_FogOfWar());
        ck::Trace("MinimapGym: fog link cleared (all POIs project)");
    }

    UFUNCTION(Exec, DisplayName="Minimap Gym - Reveal All Fog")
    void Ck_GymMinimap_RevealAll()
    {
        if (ck::Is_NOT_Valid(_Fog))
        { return; }

        _Fog.Request_RevealAll();
        ck::Trace("MinimapGym: fog fully revealed");
    }

    UFUNCTION(Exec, DisplayName="Minimap Gym - Reset Fog")
    void Ck_GymMinimap_ResetFog()
    {
        if (ck::Is_NOT_Valid(_Fog))
        { return; }

        _Fog.Request_Reset();
        ck::Trace("MinimapGym: fog reset to fully fogged");
    }

    UFUNCTION(Exec, DisplayName="Minimap Gym - Stress 500")
    void Ck_GymMinimap_Stress500()
    {
        if (_StressPois.Num() > 0)
        {
            ck::Trace("MinimapGym: stress field already spawned — clear it first");
            return;
        }

        auto Category = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Stress");
        auto FieldCenter = _StressOrigin + FVector(-800.0, 0.0, 100.0);

        // 500 POIs on a 25 x 20 grid, 200uu spacing.
        for (int32 Row = 0; Row < 25; Row++)
        {
            for (int32 Col = 0; Col < 20; Col++)
            {
                auto Offset = FVector(
                    float(Row - 12) * 200.0,
                    float(Col - 10) * 200.0,
                    0.0);
                auto Poi = DoCreateStandalonePoi(
                    FTransform(FRotator::ZeroRotator, FieldCenter + Offset),
                    FCk_Fragment_Poi_ParamsData(Category));
                _StressPois.Add(FCk_Handle(Poi));
            }
        }

        ck::Trace("MinimapGym: 500 stress POIs spawned");
    }

    UFUNCTION(Exec, DisplayName="Minimap Gym - Clear Stress")
    void Ck_GymMinimap_ClearStress()
    {
        for (auto Poi : _StressPois)
        {
            if (ck::IsValid(Poi))
            { utils_entity_lifetime::Request_DestroyEntity(Poi); }
        }
        _StressPois.Empty();
        ck::Trace("MinimapGym: stress field cleared");
    }

    UFUNCTION(Exec, DisplayName="Minimap Gym - Readout")
    void Ck_GymMinimap_Readout()
    {
        auto Minimap = DoGet_Minimap();
        if (ck::IsValid(Minimap))
        {
            auto ViewYaw = utils_minimap::Get_ViewYawDegrees(Minimap);
            auto Extent = utils_minimap::Get_ViewExtent(Minimap);
            auto Entries = utils_minimap::Get_Entries(Minimap);
            ck::Trace(f"Minimap: yaw {ViewYaw} | extent {Extent} | {Entries.Num()} entries");

            for (auto Entry : Entries)
            {
                auto Pos = Entry.Get_MapPosition();
                ck::Trace(f"  pos ({Pos.X}, {Pos.Y}) | dist {Entry.Get_Distance()} | prio {Entry.Get_Priority()}");
            }
        }

        if (ck::IsValid(_WorldMap))
        {
            ck::Trace(f"WorldMap: {utils_minimap::Get_Entries(_WorldMap).Num()} entries");
        }

        if (ck::IsValid(_Fog))
        {
            auto Fraction = utils_fog_of_war::Get_ExploredFraction(_Fog);
            ck::Trace(f"Fog: explored fraction {Fraction}");
        }
    }
}
