// Language=angelscript

//============================================================================
// CK MINIMAP GYM
//
// Interactive minimap + fog-of-war playground. The gym pawn carries an
// observer-centric minimap surfaced through the zero-asset reference widget
// (UCk_MinimapFrame_Widget) in the top-right of the viewport; walking and
// mouse-turning the pawn drives the projection live.
//
// Stations (content built toward -X from each anchor - house rule):
//   - PoiField:  a POI cluster (Quest/Shop/Danger/Info, varied priorities,
//                one far ClampToEdge waypoint pinned to the frame rim)
//   - WorldMap:  a FixedBounds projection over the station area; readout on
//                the control panel's [P] row
//   - FogWalk:   a fog grid over the station; the pawn is a revealer - walk
//                to paint exploration; link/unlink it to the HUD minimap
//   - Stress:    500 standalone POIs on demand (panel [M])
//
// Control panel rows:
//   [J] / [K]  - halve / double the view extent
//   [T]        - NorthLocked <-> RotateWithObserver
//   [G]        - link/unlink the FogWalk grid to the HUD minimap
//   [B]        - reveal the whole FogWalk grid
//   [N]        - reset the FogWalk grid to fully fogged
//   [M] / [U]  - spawn / destroy the stress field
//   [P]        - dump entries + fog fraction to the log
//============================================================================

class ACk_MinimapGym_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_MinimapGym_PlayerController;
    default DefaultPawnClass = ACk_MinimapGym_Pawn;
}

class ACk_MinimapGym_Pawn : ACk_Gym_Base_Pawn
{
    // ADefaultPawn leaves the ACTOR un-yawed under mouse-look - the minimap's view yaw reads the pawn
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

        DoComposePlayerAsPoi();

        ck::Trace("MinimapGym: observer-centric minimap composed on pawn entity");
    }

    // CkPoi v2 DIRECT-ATTACH acceptance demo (PROMPT criterion 5): the PLAYER itself IS a Poi,
    // composed onto the pawn's OWN entity (_PawnEntity - the very entity that hosts the minimap
    // observer), NOT a freshly spawned standalone child. Because the observer and the Poi are the
    // same entity, the player blip renders at the frame center (distance 0, observer-centric);
    // MaxRange 0 on VisibleRange = unlimited ("always shown to self", the design doc's example).
    private void DoComposePlayerAsPoi()
    {
        // OnEntityConstructed fires once per pawn entity, but guard anyway - utils_poi::Add ensures
        // on a double-add, so gate the whole compose on the identity tag if the path ever re-enters.
        if (utils_poi::Has(_PawnEntity))
        { return; }

        auto PawnPoi = utils_poi::Add(_PawnEntity,
            FCk_Fragment_Poi_ParamsData(utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Player")));

        // Direct-attach display definition (Add, not Create - single consumer: the minimap).
        auto DisplayParams = FCk_Fragment_PoiDisplayDefinition_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Consumer.Minimap"));
        DisplayParams.Set_Priority(100);
        utils_poi_display_definition::Add(PawnPoi, DisplayParams);

        utils_visible_range::Add(_PawnEntity, FCk_Fragment_VisibleRange_ParamsData(0.0));
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

    // The minimap carries the fog handle but exposes no getter for it, so the panel mirrors the link
    // here. This controller is the only writer. (The rotation mode, by contrast, reads back live.)
    private bool _FogLinked = false;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        auto PoiField = FCkGym_Station_SpawnParams_Payload();
        PoiField.Tags.Add(n"Gym.Minimap.PoiField");
        PoiField.Title = FText::FromString("MINIMAP");
        auto PoiFieldDescription = TArray<FText>();
        PoiFieldDescription.Add(FText::FromString("POI cluster around the station.\nWalk + mouse-turn to drive the HUD minimap."));
        PoiFieldDescription.Add(FText::FromString("Panel: [J]/[K] zoom\n[T] rotation mode"));
        PoiField.Description = PoiFieldDescription;
        PoiField.AutoSize = true;
        Stations.Add(PoiField);

        auto WorldMap = FCkGym_Station_SpawnParams_Payload();
        WorldMap.Tags.Add(n"Gym.Minimap.WorldMap");
        WorldMap.Title = FText::FromString("WORLD MAP");
        auto WorldMapDescription = TArray<FText>();
        WorldMapDescription.Add(FText::FromString("FixedBounds projection over the station area."));
        WorldMapDescription.Add(FText::FromString("Panel: [P] readout to the log"));
        WorldMap.Description = WorldMapDescription;
        WorldMap.AutoSize = true;
        Stations.Add(WorldMap);

        auto FogWalk = FCkGym_Station_SpawnParams_Payload();
        FogWalk.Tags.Add(n"Gym.Minimap.FogWalk");
        FogWalk.Title = FText::FromString("FOG WALK");
        auto FogWalkDescription = TArray<FText>();
        FogWalkDescription.Add(FText::FromString("The pawn reveals fog as it walks this station."));
        FogWalkDescription.Add(FText::FromString("Panel: [G] link fog\n[B] reveal all\n[N] reset"));
        FogWalk.Description = FogWalkDescription;
        FogWalk.AutoSize = true;
        Stations.Add(FogWalk);

        auto Stress = FCkGym_Station_SpawnParams_Payload();
        Stress.Tags.Add(n"Gym.Minimap.Stress");
        Stress.Title = FText::FromString("MINIMAP STRESS");
        auto StressDescription = TArray<FText>();
        StressDescription.Add(FText::FromString("500 POIs on demand — watch the projector's cost."));
        StressDescription.Add(FText::FromString("Panel: [M] spawn 500\n[U] clear"));
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
        ck::Trace("MinimapGym: started - POI field + world map + fog grid built");
    }

    private void DoBuildPoiField()
    {
        auto Center = _PoiFieldOrigin + FVector(-800.0, 0.0, 100.0);

        // 8 cluster positions at 45-degree steps, radius 600 (precomputed - no trig dependency).
        DoAddPoi(Center + FVector(600.0, 0.0, 0.0),      n"Poi.Category.Quest",  5);
        DoAddPoi(Center + FVector(424.3, 424.3, 0.0),    n"Poi.Category.Shop",   3);
        DoAddPoi(Center + FVector(0.0, 600.0, 0.0),      n"Poi.Category.Danger", 4);
        DoAddPoi(Center + FVector(-424.3, 424.3, 0.0),   n"Poi.Category.Info",   1);
        DoAddPoi(Center + FVector(-600.0, 0.0, 0.0),     n"Poi.Category.Quest",  2);
        DoAddPoi(Center + FVector(-424.3, -424.3, 0.0),  n"Poi.Category.Shop",   1);
        DoAddPoi(Center + FVector(0.0, -600.0, 0.0),     n"Poi.Category.Danger", 3);
        DoAddPoi(Center + FVector(424.3, -424.3, 0.0),   n"Poi.Category.Info",   2);

        // One far ClampToEdge waypoint - pins to the frame rim from anywhere in the gym.
        auto Waypoint = DoCreateStandalonePoi(
            FTransform(FRotator::ZeroRotator, Center + FVector(-6000.0, 0.0, 0.0)),
            FCk_Fragment_Poi_ParamsData(utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Waypoint")));
        DoAddMinimapDisplay(Waypoint, 10, ECk_Poi_OffscreenPolicy::ClampToEdge);

        utils_pmg_basic_shapes::DrawFilledSphere(Center + FVector(-6000.0, 0.0, 60.0), 55.0, 12, 12,
            FLinearColor(0.7, 0.35, 0.95), true, 2.0, ECk_Plane_Axis::XY, -1.0);
    }

    private void DoBuildWorldMap()
    {
        auto GymPawn = Cast<ACk_MinimapGym_Pawn>(ControlledPawn);
        if (GymPawn == nullptr)
        { return; }

        // A FixedBounds projection over the world-map station area, hosted on its own entity
        // (parented off the pawn entity - the gym PlayerController is not ECS-backed).
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
        // The pawn composes its minimap in OnEntityConstructed (deferred entity construction) - at gym
        // start it usually is not there YET. Retry on a short timer instead of silently giving up.
        auto Minimap = DoGet_Minimap();
        if (ck::Is_NOT_Valid(Minimap))
        {
            _HudWidgetRetries++;
            if (_HudWidgetRetries <= 40)
            { System::SetTimer(this, n"DoCreateHudWidget", 0.25, false); }
            else
            { ck::Trace("MinimapGym: pawn minimap never appeared - no HUD widget (use the panel's [P] readout row)"); }
            return;
        }

        _HudWidget = Cast<UCk_MinimapFrame_Widget>(
            WidgetBlueprint::CreateWidget(UCk_MinimapFrame_Widget, this));
        if (_HudWidget == nullptr)
        {
            ck::Trace("MinimapGym: HUD widget creation failed - use the panel's [P] readout row instead");
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
        auto Poi = DoCreateStandalonePoi(FTransform(FRotator::ZeroRotator, InLocation),
            FCk_Fragment_Poi_ParamsData(utils_gameplay_tag::ResolveGameplayTag(InCategoryName)));
        DoAddMinimapDisplay(Poi, InPriority, ECk_Poi_OffscreenPolicy::Hide);

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

    // Presentation (priority/offscreen) now lives in CkPoiDisplayDefinition, keyed by the minimap
    // consumer (CkPoi v2). Compose one direct-attach definition on the POI's own entity.
    private void DoAddMinimapDisplay(FCk_Handle_Poi InPoi, int32 InPriority, ECk_Poi_OffscreenPolicy InOffscreenPolicy)
    {
        auto DisplayParams = FCk_Fragment_PoiDisplayDefinition_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Consumer.Minimap"));
        DisplayParams.Set_Priority(InPriority);
        DisplayParams.Set_OffscreenPolicy(InOffscreenPolicy);
        utils_poi_display_definition::Add(InPoi, DisplayParams);
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

    // Facing needle from the pawn, redrawn every frame - mirrors what the HUD's arrow should do
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

    private void DoZoomIn()
    {
        auto Minimap = DoGet_Minimap();
        if (ck::Is_NOT_Valid(Minimap))
        { return; }

        auto NewExtent = Math::Max(utils_minimap::Get_ViewExtent(Minimap) * 0.5, 500.0);
        Minimap.Request_SetViewExtent(FCk_Request_Minimap_SetViewExtent(NewExtent));
        ck::Trace(f"MinimapGym: view extent -> {NewExtent}");
    }

    private void DoZoomOut()
    {
        auto Minimap = DoGet_Minimap();
        if (ck::Is_NOT_Valid(Minimap))
        { return; }

        auto NewExtent = Math::Min(utils_minimap::Get_ViewExtent(Minimap) * 2.0, 24000.0);
        Minimap.Request_SetViewExtent(FCk_Request_Minimap_SetViewExtent(NewExtent));
        ck::Trace(f"MinimapGym: view extent -> {NewExtent}");
    }

    private void DoToggleRotation()
    {
        auto Minimap = DoGet_Minimap();
        if (ck::Is_NOT_Valid(Minimap))
        { return; }

        if (DoGet_RotatesWithObserver())
        {
            Minimap.Request_SetRotationMode(
                FCk_Request_Minimap_SetRotationMode(ECk_Minimap_RotationMode::NorthLocked));
            ck::Trace("MinimapGym: rotation mode = NorthLocked");
            return;
        }

        Minimap.Request_SetRotationMode(
            FCk_Request_Minimap_SetRotationMode(ECk_Minimap_RotationMode::RotateWithObserver));
        ck::Trace("MinimapGym: rotation mode = RotateWithObserver");
    }

    private bool DoGet_RotatesWithObserver()
    {
        auto Minimap = DoGet_Minimap();
        if (ck::Is_NOT_Valid(Minimap))
        { return false; }

        return utils_minimap::Get_RotationMode(Minimap) == ECk_Minimap_RotationMode::RotateWithObserver;
    }

    private void DoToggleFog()
    {
        auto Minimap = DoGet_Minimap();
        if (ck::Is_NOT_Valid(Minimap))
        { return; }

        _FogLinked = !_FogLinked;
        if (_FogLinked)
        {
            Minimap.Request_SetFogOfWar(FCk_Request_Minimap_SetFogOfWar(_Fog));
            ck::Trace("MinimapGym: HUD minimap now culls unexplored POIs (fog linked)");
            return;
        }

        Minimap.Request_SetFogOfWar(FCk_Request_Minimap_SetFogOfWar(FCk_Handle_FogOfWar()));
        ck::Trace("MinimapGym: fog link cleared (all POIs project)");
    }

    private void DoRevealAllFog()
    {
        if (ck::Is_NOT_Valid(_Fog))
        { return; }

        _Fog.Request_RevealAll();
        ck::Trace("MinimapGym: fog fully revealed");
    }

    private void DoResetFog()
    {
        if (ck::Is_NOT_Valid(_Fog))
        { return; }

        _Fog.Request_Reset();
        ck::Trace("MinimapGym: fog reset to fully fogged");
    }

    private void DoSpawnStressField()
    {
        if (_StressPois.Num() > 0)
        {
            ck::Trace("MinimapGym: stress field already spawned - clear it first");
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

    private void DoClearStressField()
    {
        for (auto Poi : _StressPois)
        {
            if (ck::IsValid(Poi))
            { utils_entity_lifetime::Request_DestroyEntity(Poi); }
        }
        _StressPois.Empty();
        ck::Trace("MinimapGym: stress field cleared");
    }

    private void DoReadout()
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

    //--------------------------------------------------------------------------------------------------------------------------
    // CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
    //
    // The minimap is watched WHILE walking, so the extent and the rotation mode belong on screen next
    // to the frame rather than behind a console command typed before you start moving.
    //--------------------------------------------------------------------------------------------------------------------------

    FString Get_ControlPanelTitle() override
    {
        return "MINIMAP";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();

        auto Minimap = DoGet_Minimap();
        auto Extent = ck::IsValid(Minimap) ? utils_minimap::Get_ViewExtent(Minimap) : 0.0f;
        auto Entries = ck::IsValid(Minimap) ? utils_minimap::Get_Entries(Minimap).Num() : 0;

        Rows.Add(CkGym_Control::Header("PROJECTION"));
        Rows.Add(CkGym_Control::Status("View extent", f"{Extent} - {Entries} entries"));
        Rows.Add(CkGym_Control::Action(EKeys::J, "J", "Zoom in (halve the extent)"));
        Rows.Add(CkGym_Control::Action(EKeys::K, "K", "Zoom out (double the extent)"));
        Rows.Add(CkGym_Control::ToggleNamed(EKeys::T, "T", "Rotation", DoGet_RotatesWithObserver(),
            "RotateWithObserver", "NorthLocked"));

        auto ExploredPercent = ck::IsValid(_Fog) ? int32(utils_fog_of_war::Get_ExploredFraction(_Fog) * 100.0f) : 0;

        Rows.Add(CkGym_Control::Header("FOG WALK"));
        Rows.Add(CkGym_Control::Status("Explored", f"{ExploredPercent}%"));
        Rows.Add(CkGym_Control::Toggle(EKeys::G, "G", "Fog linked to the HUD minimap", _FogLinked));
        Rows.Add(CkGym_Control::Action(EKeys::B, "B", "Reveal the whole grid"));
        Rows.Add(CkGym_Control::Action(EKeys::N, "N", "Reset to fully fogged"));

        Rows.Add(CkGym_Control::Header("STRESS"));
        Rows.Add(CkGym_Control::Status("Stress POIs", f"{_StressPois.Num()}"));
        Rows.Add(CkGym_Control::Action(EKeys::M, "M", "Spawn 500 POIs", _StressPois.Num() == 0));
        Rows.Add(CkGym_Control::Action(EKeys::U, "U", "Clear the stress field", _StressPois.Num() > 0));

        Rows.Add(CkGym_Control::Action(EKeys::P, "P", "Readout to the log"));

        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        // Rows 0, 1, 5, 6, 10 and 11 are headers or status readouts - they hold no key and never
        // arrive here, but they DO occupy an index.
        if (InRowIndex == 2) { DoZoomIn(); }
        else if (InRowIndex == 3) { DoZoomOut(); }
        else if (InRowIndex == 4) { DoToggleRotation(); }
        else if (InRowIndex == 7) { DoToggleFog(); }
        else if (InRowIndex == 8) { DoRevealAllFog(); }
        else if (InRowIndex == 9) { DoResetFog(); }
        else if (InRowIndex == 12) { DoSpawnStressField(); }
        else if (InRowIndex == 13) { DoClearStressField(); }
        else if (InRowIndex == 14) { DoReadout(); }
    }
}
