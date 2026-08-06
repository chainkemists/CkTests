// Language=angelscript

//============================================================================
// RENDER TARGET GYM — WHITEBOARD (manual multiplayer validation)
//============================================================================
//
// Manual multiplayer validation for CkRenderTarget: a replicated
// whiteboard entity carrying a Hybrid / client-authoring RenderTarget. Run
// under PIE with 2+ players; HOLD LMB while looking at the board surface to
// draw freehand (predicted locally, relayed + republished), and watch every
// world's station display converge (applied batch seq, pixel payloads,
// pixel-state hash).
//
//   LMB (hold, aim at board)              — freehand draw where you look
//   Ck_GymRenderTarget_DrawRandomStroke   — draw a random line
//   Ck_GymRenderTarget_Clear              — clear the board
//   Ck_GymRenderTarget_SyncPixels         — server capture -> FullSync/Delta
//                                           reconcile (Hybrid mode's pixel leg)
//
// PASS = seq / payload counters and the pixel hash match across all worlds
// after each operation settles, and strokes drawn on one world appear on all.
//============================================================================

namespace Ck
{
    asset Asset_RenderTargetGym_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"RenderTarget.Gym.Whiteboard");
    }
}

// ----------------------------------------------------------------------------------------------------------------
// MESSAGES (console -> whiteboard entity)
// ----------------------------------------------------------------------------------------------------------------

USTRUCT()
struct FCk_Message_RenderTargetGym_DrawRandomStroke
{
}

USTRUCT()
struct FCk_Message_RenderTargetGym_Clear
{
}

USTRUCT()
struct FCk_Message_RenderTargetGym_SyncPixels
{
}

// ----------------------------------------------------------------------------------------------------------------
// REPLICATED WHITEBOARD ACTOR — spawned at the station by the (server) PC.
// BeginPlay spawns the WithActor entity script so both worlds compose the
// RenderTarget symmetrically (the rep handler's Apply/NotReady contract).
// ----------------------------------------------------------------------------------------------------------------

class ACk_RenderTargetGym_WhiteboardActor : AActor
{
    default bReplicateMovement = false;
    default bReplicates = true;
    default bReplicateUsingRegisteredSubObjectList = true;

    UPROPERTY(DefaultComponent, RootComponent)
    USceneComponent SceneRoot;

    // Board surface: engine plane stood upright like a banner — the actor spawns
    // above the station's back wall (the header), the mesh floats above it with
    // its normal facing local +X (the alcove opening, i.e. toward the player).
    // Pitch -90 maps the plane's +Z normal onto +X. One-sided: invisible from behind.
    UPROPERTY(DefaultComponent, Attach = SceneRoot)
    UStaticMeshComponent BoardMesh;
    default BoardMesh.RelativeLocation = FVector(0.0, 0.0, 220.0);
    default BoardMesh.RelativeRotation = FRotator(-90.0, 0.0, 0.0);
    default BoardMesh.RelativeScale3D = FVector(4.0, 4.0, 1.0);

    private bool _SurfaceBindFailed = false;

    UFUNCTION(BlueprintOverride)
    void ConstructionScript()
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto PlaneMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Plane.Plane"));
        if (PlaneMesh != nullptr)
        { BoardMesh.SetStaticMesh(PlaneMesh); }
    }

    // Blits the board's render target onto the plane via the USF Blit look.
    // Returning true means "stop retrying" — including the no-generated-look
    // failure case, which warns once and leaves the board untextured.
    bool Request_BindBoardSurface(UTextureRenderTarget2D InTarget)
    {
        if (_SurfaceBindFailed)
        { return true; }

        auto MID = UCk_Utils_Usf_UE::Create_MID_ForLook(CkUsf::Blit, this);
        if (MID == nullptr)
        {
            ck::Warning("RenderTarget gym: no generated Blit look material — board stays untextured. Run 'Generate Look Materials'.");
            _SurfaceBindFailed = true;
            return true;
        }

        MID.SetTextureParameterValue(n"iChannel0", InTarget);
        BoardMesh.SetMaterial(0, MID);
        return true;
    }

    // Maps the view ray to render-target pixel coords via analytic ray/plane
    // intersection — no collision needed on the board mesh. Assumes the engine
    // plane's UVs run U along local +X, V along local +Y from the (-50,-50)
    // corner; if strokes appear mirrored relative to the aim point, flip here.
    bool Get_BoardPixelUnderRay(FVector InViewLoc, FVector InViewDir, FVector2D& OutPixel)
    {
        auto BoardT = BoardMesh.GetWorldTransform();
        auto PlaneNormal = BoardT.TransformVectorNoScale(FVector(0.0, 0.0, 1.0));

        auto Denom = InViewDir.DotProduct(PlaneNormal);
        if (Math::Abs(Denom) < 0.0001)
        { return false; }

        auto Dist = (BoardT.GetLocation() - InViewLoc).DotProduct(PlaneNormal) / Denom;
        if (Dist < 0.0 || Dist > 10000.0)
        { return false; }

        auto Local = BoardT.InverseTransformPosition(InViewLoc + InViewDir * Dist);
        if (Math::Abs(Local.X) > 50.0 || Math::Abs(Local.Y) > 50.0)
        { return false; }

        OutPixel = FVector2D(
            (Local.X + 50.0) / 100.0 * 255.0,
            (Local.Y + 50.0) / 100.0 * 255.0);
        return true;
    }

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto _CkPerfScope = ck::ScopedStat();
        // Authority only: this actor replicates, so BeginPlay also runs on clients —
        // spawning there would create a SECOND, orphan composition next to the one the
        // entity-script replication path re-creates (split-brain boards: the display
        // and the local draws can land on different render targets).
        if (!HasAuthority())
        { return; }

        auto SpawnParams = FCk_EntityScript_WithActor_SpawnParams();
        SpawnParams._OwningActor = this;
        utils_entity_script::Request_SpawnEntity(
            ck::TransientEntity(),
            UCk_RenderTargetGym_Whiteboard_EntityScript,
            SpawnParams);
    }
}

// ----------------------------------------------------------------------------------------------------------------
// WHITEBOARD ENTITY SCRIPT
// ----------------------------------------------------------------------------------------------------------------

class UCk_RenderTargetGym_Whiteboard_EntityScript : UCk_EntityScript_WithActor_UE
{
    default _Replication = ECk_Replication::Replicates;

    private FCk_Handle_RenderTarget _Board;
    private int32 _LocalBatchCount = 0;
    private int32 _LocalPayloadCount = 0;
    private bool _SurfaceBound = false;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        utils_entity_tag::Add(InHandle, n"TAG_RenderTargetGym_Whiteboard");

        auto Params = FCk_Fragment_RenderTarget_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"RenderTarget.Gym.Whiteboard"));
        Params.Set_Size(FIntPoint(256, 256));
        Params.Set_SyncMode(ECk_RenderTarget_SyncMode::Hybrid);
        Params.Set_ClientAuthoring(ECk_RenderTarget_ClientAuthoring::Allowed);
        Params.Set_Replication(ECk_Replication::Replicates);
        // Hybrid NEEDS the periodic pixel-reconcile leg: freehand drawing outruns the
        // 64-batch instruction ring, and ring-wrap gap recovery can only reconcile
        // against a captured snapshot. Without captures the worlds diverge permanently.
        Params.Set_PixelSyncPolicy(ECk_RenderTarget_PixelSyncPolicy::Interval);
        Params.Set_SyncInterval(FCk_Time(2.0));
        _Board = utils_render_target::Add(InHandle, Params);

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Board.BindTo_OnInstructionsApplied(
            FCk_Delegate_RenderTarget_OnInstructionsApplied(this, n"OnInstructionsApplied"));
        _Board.BindTo_OnPixelPayloadApplied(
            FCk_Delegate_RenderTarget_OnPixelPayloadApplied(this, n"OnPixelPayloadApplied"));

        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_RenderTargetGym_DrawRandomStroke,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnDrawRandomStroke"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_RenderTargetGym_Clear,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnClear"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_RenderTargetGym_SyncPixels,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnSyncPixels"));

        auto DisplayTimerParams = FCk_Timer_Spec(FCk_Time(0.25f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"DisplayTick"));

        // The managed target starts black — the host resets it to the whiteboard
        // base look. Replicated instructions; late joiners get them via the ring.
        if (utils_net::Get_IsEntityNetMode_Host(InHandle))
        { RequestBoardReset(); }
    }

    // Soft grey-white base (pure white blooms hard under the unlit blit look and
    // drowns the strokes) + a dark frame so the board edges are obvious in-world.
    private void RequestBoardReset()
    {
        auto ClearRequest = FCk_Request_RenderTarget_Clear();
        ClearRequest.Set_ClearColor(FLinearColor(0.45, 0.45, 0.5, 1.0));
        _Board.Request_Clear(ClearRequest);

        auto Frame = FCk_Request_RenderTarget_DrawBox(FVector2D(4.0, 4.0), FVector2D(248.0, 248.0));
        Frame.Set_Thickness(6.0);
        Frame.Set_Color(FLinearColor::Black);
        _Board.Request_DrawBox(Frame);
    }

    UFUNCTION()
    private void OnInstructionsApplied(FCk_Handle_RenderTarget InHandle, int32 InBatchSeq, int32 InNumCmds)
    {
        _LocalBatchCount++;
    }

    UFUNCTION()
    private void OnPixelPayloadApplied(FCk_Handle_RenderTarget InHandle, ECk_RenderTarget_PixelPayloadKind InKind, int32 InPayloadSeq)
    {
        _LocalPayloadCount++;
    }

    UFUNCTION()
    private void OnDrawRandomStroke(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto Start = FVector2D(Math::RandRange(0.0, 255.0), Math::RandRange(0.0, 255.0));
        auto End = FVector2D(Math::RandRange(0.0, 255.0), Math::RandRange(0.0, 255.0));
        auto Color = FLinearColor(Math::RandRange(0.0, 1.0), Math::RandRange(0.0, 1.0), Math::RandRange(0.0, 1.0), 1.0);

        auto Request = FCk_Request_RenderTarget_DrawLine(Start, End);
        Request.Set_Thickness(3.0);
        Request.Set_Color(Color);
        _Board.Request_DrawLine(Request);
    }

    UFUNCTION()
    private void OnClear(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        RequestBoardReset();
    }

    UFUNCTION()
    private void OnSyncPixels(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        _Board.Request_SyncPixels(FCk_Request_RenderTarget_SyncPixels());
    }

    // The drawable target exists one tick after Add (Setup processor) and only
    // on worlds that can render — retried from the display timer until bound.
    private void TryBindBoardSurface(FCk_Handle InSelfEntity)
    {
        if (_SurfaceBound)
        { return; }

        auto Target = _Board.Get_Target();
        if (!ck::IsValid(Target))
        { return; }

        auto BoardActor = Cast<ACk_RenderTargetGym_WhiteboardActor>(
            utils_owning_actor::Get_EntityOwningActor(InSelfEntity));
        if (!ck::IsValid(BoardActor))
        { return; }

        _SurfaceBound = BoardActor.Request_BindBoardSurface(Target);

        if (_SurfaceBound)
        { ck::Trace("[Whiteboard] render target bound to board mesh", n"Whiteboard", 5.0f, FLinearColor::Green); }
    }

    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        // The board entity dies before this timer during gym restart teardown.
        if (ck::Is_NOT_Valid(_Board))
        { return; }

        auto SelfEntity = ck::ToEntity(this);
        auto NetworkRole = CkGym_Common::Get_NetworkRoleTitle(SelfEntity);

        TryBindBoardSurface(SelfEntity);

        auto Title = f"RENDER TARGET — WHITEBOARD ({NetworkRole})";

        auto AppliedSeq = _Board.Get_LatestAppliedBatchSeq();
        auto PixelHash = _Board.Get_PixelStateHash();
        auto LastPayloadSeq = _Board.Get_LatestAppliedPixelPayloadSeq();

        FString Body;
        Body = f"Hybrid sync, client authoring ALLOWED\n";
        Body = f"{Body}  Applied batch seq:    {AppliedSeq}\n";
        Body = f"{Body}  Batches seen here:    {_LocalBatchCount}\n";
        Body = f"{Body}  Pixel payloads here:  {_LocalPayloadCount} (last seq {LastPayloadSeq})\n";
        Body = f"{Body}  Pixel state hash:     {PixelHash}\n\n";
        Body = f"{Body}PASS = seq + hash converge on every world after each op.\n\n";
        Body = f"{Body}HOLD LMB while looking at the board to draw.\n\n";
        Body = f"{Body}Manual:\n";
        Body = f"{Body}  Ck_GymRenderTarget_DrawRandomStroke\n";
        Body = f"{Body}  Ck_GymRenderTarget_Clear\n";
        Body = f"{Body}  Ck_GymRenderTarget_SyncPixels\n";

        auto StationActor = utils_actor::Get_FirstActorWithNameContaining(
            "Gym.RenderTarget.Whiteboard", ECk_ActorSearchMethod::SearchByTag);
        if (!ck::IsValid(StationActor))
        { return; }

        auto StationHandle = utils_owning_actor::TryGet_ActorEntityHandle(StationActor);
        if (!ck::IsValid(StationHandle))
        { return; }

        auto& Fragment = StationHandle.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        Fragment.Title = FText::FromString(Title);
        Fragment.Description = FText::FromString(Body);
    }
}

// ----------------------------------------------------------------------------------------------------------------
// PLAYER CONTROLLER + GAME MODE
// ----------------------------------------------------------------------------------------------------------------

class ACk_RenderTargetGym_PlayerController : ACk_Gym_Base_PlayerController
{
    private ACk_RenderTargetGym_WhiteboardActor _SpawnedWhiteboard;

    private ACk_RenderTargetGym_WhiteboardActor _BoardActor;
    private FCk_Handle_RenderTarget _BoardRT;
    private FVector2D _LastPixel;
    private bool _HasLastPixel = false;
    private bool _LmbWasDown = false;
    private int32 _StrokeSegments = 0;
    private float32 _SegmentCooldown = 0.0;
    private FLinearColor _DrawColor = FLinearColor(0.0, 0.0, 0.0, 0.0);

    // Freehand drawing: while LMB is held, intersect the camera ray with the
    // board plane each frame and draw a line segment from the previous hit.
    // Runs on the local PC of every world — clients author predictively
    // (the board's _ClientAuthoring is Allowed).
    UFUNCTION(BlueprintOverride)
    void Tick(float32 InDeltaSeconds)
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (!IsLocalController())
        { return; }

        if (!IsInputKeyDown(EKeys::LeftMouseButton))
        {
            if (_LmbWasDown)
            {
                ck::Trace(f"[Whiteboard] stroke ended — {_StrokeSegments} segment(s) drawn", n"Whiteboard", 3.0f,
                    _StrokeSegments > 0 ? FLinearColor::Green : FLinearColor::Yellow);
                _StrokeSegments = 0;
            }
            _LmbWasDown = false;
            _HasLastPixel = false;
            return;
        }

        auto LmbJustPressed = !_LmbWasDown;
        _LmbWasDown = true;

        if (!TryResolveBoard())
        {
            if (LmbJustPressed)
            { ck::Trace("[Whiteboard] LMB held but no whiteboard entity/render-target resolved in this world", n"Whiteboard", 3.0f, FLinearColor::Red); }
            return;
        }

        FVector ViewLoc;
        FRotator ViewRot;
        GetPlayerViewPoint(ViewLoc, ViewRot);

        FVector2D Pixel;
        if (!_BoardActor.Get_BoardPixelUnderRay(ViewLoc, ViewRot.Vector(), Pixel))
        {
            if (LmbJustPressed)
            { ck::Trace("[Whiteboard] LMB held but the view ray misses the board surface", n"Whiteboard", 3.0f, FLinearColor::Yellow); }
            _HasLastPixel = false;
            return;
        }

        if (!_HasLastPixel)
        {
            ck::Trace(f"[Whiteboard] stroke start at pixel ({Pixel.X}, {Pixel.Y})", n"Whiteboard", 3.0f, FLinearColor::Green);
            _LastPixel = Pixel;
            _HasLastPixel = true;
            return;
        }

        // Throttle to ~20 segments/sec — every segment is one replicated instruction
        // batch, and the ring only holds 64. Unthrottled 60Hz strokes force constant
        // ring-wrap gap recovery on every other world.
        _SegmentCooldown -= InDeltaSeconds;
        if (_SegmentCooldown > 0.0)
        { return; }

        if ((Pixel - _LastPixel).Size() < 2.0)
        { return; }

        // Near-black colors only — strokes must survive the unlit look's bloom.
        if (_DrawColor.A <= 0.0)
        {
            _DrawColor = FLinearColor(
                Math::RandRange(0.0, 0.3), Math::RandRange(0.0, 0.3), Math::RandRange(0.0, 0.3), 1.0);
        }

        auto Request = FCk_Request_RenderTarget_DrawLine(_LastPixel, Pixel);
        Request.Set_Thickness(5.0);
        Request.Set_Color(_DrawColor);
        _BoardRT.Request_DrawLine(Request);
        _LastPixel = Pixel;
        _StrokeSegments++;
        _SegmentCooldown = 0.05;
    }

    private bool TryResolveBoard()
    {
        if (ck::IsValid(_BoardActor) && ck::IsValid(_BoardRT))
        { return true; }

        // Anchor the tag query to THIS controller's entity — ck::TransientEntity()
        // resolves through an ambient world lookup that can return another PIE
        // world's registry in multi-window sessions.
        auto ContextEntity = ck::ToEntity(this);
        if (!ck::IsValid(ContextEntity))
        { return false; }

        for (auto E : utils_entity_tag::ForEach_Entity(ContextEntity, n"TAG_RenderTargetGym_Whiteboard"))
        {
            auto Actor = Cast<ACk_RenderTargetGym_WhiteboardActor>(utils_owning_actor::Get_EntityOwningActor(E));
            if (!ck::IsValid(Actor))
            { continue; }

            auto RT = utils_render_target::TryGet_RenderTarget(E,
                utils_gameplay_tag::ResolveGameplayTag(n"RenderTarget.Gym.Whiteboard"));
            if (!ck::IsValid(RT))
            { continue; }

            _BoardActor = Actor;
            _BoardRT = RT;
            ck::Trace(f"[Whiteboard] resolved board {Actor.GetPathName()}", n"Whiteboard", 5.0f, FLinearColor::Green);
            return true;
        }

        return false;
    }

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.RenderTarget.Whiteboard");
            Station.Title = FText::FromString("RENDER TARGET — WHITEBOARD");
            Station.AutoSize = true;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Replicated whiteboard: draw instructions + pixel reconcile (Hybrid)."));
            Description.Add(FText::FromString("HOLD LMB while looking at the board to draw — from ANY world."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        return Stations;
    }

    void Request_StartGym() override
    {
        Request_StartWhiteboard();
    }

    void Request_StartWhiteboard()
    {
        // The whiteboard replicates — only the server spawns it; clients receive it.
        // And only ONE per world: Request_StartGym runs on EVERY server-side
        // PlayerController (one per connected player), so without the local gate each
        // joining player stacks another whiteboard actor on the station — two meshes,
        // two render targets, and draws landing on a board nobody is looking at.
        // (Listen-server tool: the host's PC is the local one.)
        if (!HasAuthority() || !IsLocalController())
        { return; }

        if (ck::IsValid(_SpawnedWhiteboard))
        {
            _SpawnedWhiteboard.DestroyActor();
            _SpawnedWhiteboard = nullptr;
        }

        // The header text sits on the BACK wall top — no anchor exists for it, but it's
        // PanelTopFront (top FRONT edge) reflected through PanelCenter horizontally.
        auto StationRotation = Get_StationTransform("Gym.RenderTarget.Whiteboard").Rotator();
        auto FrontTop = Get_StationAnchorLocation("Gym.RenderTarget.Whiteboard", ECk_GymStation_Anchor::PanelTopFront);
        auto MidPanel = Get_StationAnchorLocation("Gym.RenderTarget.Whiteboard", ECk_GymStation_Anchor::PanelCenter);
        auto ToBack = MidPanel - FrontTop;
        ToBack.Z = 0.0;
        auto BackWallTop = FrontTop + ToBack * 2.0;

        _SpawnedWhiteboard = Cast<ACk_RenderTargetGym_WhiteboardActor>(SpawnActor(
            ACk_RenderTargetGym_WhiteboardActor,
            BackWallTop, StationRotation));

        ck::Trace("✅ RenderTarget whiteboard spawned at station");
    }

    UFUNCTION(Exec, DisplayName="RenderTarget Gym - Draw Random Stroke")
    void Ck_GymRenderTarget_DrawRandomStroke()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_RenderTargetGym_Whiteboard"))
        { utils_messaging::Broadcast(E, FCk_Message_RenderTargetGym_DrawRandomStroke()); }
    }

    UFUNCTION(Exec, DisplayName="RenderTarget Gym - Clear")
    void Ck_GymRenderTarget_Clear()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_RenderTargetGym_Whiteboard"))
        { utils_messaging::Broadcast(E, FCk_Message_RenderTargetGym_Clear()); }
    }

    UFUNCTION(Exec, DisplayName="RenderTarget Gym - Sync Pixels")
    void Ck_GymRenderTarget_SyncPixels()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_RenderTargetGym_Whiteboard"))
        { utils_messaging::Broadcast(E, FCk_Message_RenderTargetGym_SyncPixels()); }
    }
}

class ACk_RenderTargetGym_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_RenderTargetGym_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
