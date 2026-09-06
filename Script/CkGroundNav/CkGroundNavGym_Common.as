// Language=angelscript

//============================================================================
// GROUNDNAV GYMS - THE SHARED HALF
//============================================================================
//
// Four gyms stand on the same three facts: GroundNav bakes from the JOLT STATIC WORLD and from
// nothing else, a link / a repair / a paint / a walked route is asked OF A VOLUME, and a volume's
// answers are only worth reading once the surface it published has gone quiet. Everything below is
// what those three facts cost, written once.
//
// Three shapes, and the split between them is not stylistic:
//
//   namespace CkGroundNavGym  - the stateless half. Scene boxes, the fly-back, the status strings.
//   struct FCkGroundNavGym_Field - the stateful half. One minted volume, its build result, the
//                              settle poll every gym waits on before it reads anything, and the
//                              bake tunables it was minted with, which the debug picture needs.
//   struct FCkGroundNavGym_OverlayRefresh - the deferred redraw. A request that changes the field is
//                              answered a publish later, so the picture is re-run then and not at
//                              the keypress.
//
// The struct is a VALUE TYPE held as a member, in the same "compose, don't inherit" spirit as
// CkAutoTest_GroundNavFixture.as and CkAutoTest_ActorEntity_Helper.as. It is NOT a base class, and
// it hosts no UFUNCTION - AngelScript does not allow one on a struct method (Script/ARCHITECTURE.md
// 1). Both the build completion and the settle timer therefore have to be bound against the GYM,
// which is why the two delegates are passed IN rather than built here:
//
//   private FCkGroundNavGym_Field _Field;
//
//   _Field.Request_Mint(_PcEntity, n"MyGym_Field", Bounds, Config, Profile, NAME_None, 600,
//       FCk_Delegate_Request_OnCompleted(this, n"OnFieldBuildCompleted"),
//       FCk_Delegate_Timer(this, n"OnFieldSettlePoll"));
//
//   UFUNCTION() private void OnFieldSettlePoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
//   {
//       const auto Step = _Field.Do_PollSettle();
//       if (Step == ECkGroundNavGym_Settle::Settled) { ...the gym's own follow-up... }
//   }
//
//   UFUNCTION() private void OnFieldBuildCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
//   { _Field.Notify_BuildCompleted(InResult); }
//
// No access specifiers and no const on any struct method here: Script/ARCHITECTURE.md 9's struct
// example declares plain methods only, so nothing beyond that shape is assumed of the AS struct
// compiler. The Do_ prefix carries the "internal" meaning instead.
//
//----------------------------------------------------------------------------
// WHAT HAS NO READBACK, SO NOBODY GOES LOOKING FOR ONE
//----------------------------------------------------------------------------
//
// PLATES. A plate total is not among the volume's reflected counts - the only place one is printed
// is ck.GroundNav.Print, over the DEBUG field, which is a different field from any volume's.
// Walkable cells and seam portals are what a volume will answer, so they are what these strings say.
//
// THE DEBUG BAKE. ck.GroundNav.BakeAt / BakeFieldAt draw a picture owned by the draw layer. Nothing
// about it is reflected: FCk_GroundNav_DebugSnapshot is a plain C++ struct in a namespace, no Utils
// class exposes it, and nothing under CkFoundation/Script/Generated mentions it. A gym that wants a
// verdict has to mint a volume - the debug bake cannot be asked anything at all.
//
// CONSOLE VARIABLES. AngelScript is bound no cvar READER: the CVar utility exposes Make_CVarRef and
// IsRegistered and no getter of any type. A gym that pushes ck.GroundNav.Debug.* values owns them.
//============================================================================

// Where one Do_PollSettle call left the wait. Waiting is the only one that keeps the timer running.
enum ECkGroundNavGym_Settle
{
    Waiting,
    Settled,
    GaveUp
}

// --------------------------------------------------------------------------------------------------------------------

namespace CkGroundNavGym
{
    //------------------------------------------------------------------------
    // Scene geometry
    //
    // Everything spawned here goes into the Jolt static world through
    // utils_jolt_static_world::Request_BakeActor. An actor that is visible but
    // not baked is free space as far as every GroundNav bake is concerned, so a
    // spawn that baked zero bodies is reported as a failure rather than left to
    // read as missing ground later.
    //------------------------------------------------------------------------

    // Hands the actor back rather than a verdict, for the boxes a gym has to keep hold of - the one
    // it moves, the one it toggles. Callers that only want to know whether the scene is still whole
    // use Spawn_Box / Spawn_BoxRotated.
    //
    // InOuter is the LoadObject outer: the engine cube and the plain grey BasicShapeMaterial are
    // loaded against the caller so a gym travelling away takes its own loads with it.
    AStaticMeshActor Spawn_BoxActor(UObject InOuter, FVector InCentre, FRotator InRotation, FVector InScale)
    {
        FVector Centre = InCentre;
        FRotator Rotation = InRotation;

        auto BoxActor = Cast<AStaticMeshActor>(SpawnActor(AStaticMeshActor, Centre, Rotation));
        if (ck::Is_NOT_Valid(BoxActor))
        {
            ck::groundnav::Warning("GroundNav gym: failed to spawn a scene box");
            return nullptr;
        }

        // A runtime-spawned AStaticMeshActor must be Movable BEFORE it will accept a mesh.
        BoxActor.StaticMeshComponent.SetMobility(EComponentMobility::Movable);

        // Every failure past this point DESTROYS the half-built actor before it returns. A spawned
        // AStaticMeshActor left standing is a body in the level with no mesh and no Jolt shape - the
        // caller is told the scene failed and has no handle to clean up with, so this is the only
        // place that can.
        auto CubeMesh = Cast<UStaticMesh>(LoadObject(InOuter, "/Engine/BasicShapes/Cube.Cube"));
        if (CubeMesh == nullptr)
        {
            ck::groundnav::Warning("GroundNav gym: failed to load /Engine/BasicShapes/Cube.Cube");
            BoxActor.DestroyActor();
            return nullptr;
        }
        BoxActor.StaticMeshComponent.SetStaticMesh(CubeMesh);

        auto BoxMaterial = Cast<UMaterialInterface>(LoadObject(InOuter, "/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));
        if (BoxMaterial != nullptr)
        { BoxActor.StaticMeshComponent.SetMaterial(0, BoxMaterial); }

        FVector Scale = InScale;
        BoxActor.SetActorScale3D(Scale);
        BoxActor.StaticMeshComponent.SetCollisionProfileName(n"BlockAll");

        const auto NumBaked = utils_jolt_static_world::Request_BakeActor(BoxActor);
        if (NumBaked == 0)
        {
            ck::groundnav::Warning("GroundNav gym: a scene box baked 0 Jolt bodies - the bake would read it as free space");
            BoxActor.DestroyActor();
            return nullptr;
        }

        return BoxActor;
    }

    bool Spawn_Box(UObject InOuter, FVector InCentre, FVector InScale)
    {
        return Spawn_BoxRotated(InOuter, InCentre, FRotator::ZeroRotator, InScale);
    }

    bool Spawn_BoxRotated(UObject InOuter, FVector InCentre, FRotator InRotation, FVector InScale)
    {
        return Spawn_BoxActor(InOuter, InCentre, InRotation, InScale) != nullptr;
    }

    // The walkable surface of ACk_Gym_Floor is at the ACTOR'S ORIGIN, so InLocation is the Z agents
    // stand on with no half-thickness compensation. Z scale must stay >= 0.5 - thinner slabs bake to
    // zero walkable tiles.
    //
    // Baked like everything else: the GroundNav backend reads the Jolt static world, not the level
    // collision, so a floor Recast can see is still nothing to this bake until it has Jolt bodies.
    ACk_Gym_Floor Spawn_Floor(FVector InLocation, FVector InScale)
    {
        FVector Location = InLocation;

        auto Floor = Cast<ACk_Gym_Floor>(SpawnActor(ACk_Gym_Floor, Location, FRotator::ZeroRotator, NAME_None, true));
        if (Floor == nullptr)
        {
            ck::groundnav::Warning("GroundNav gym: failed to spawn the floor actor");
            return nullptr;
        }

        FVector Scale = InScale;
        Floor.SetActorScale3D(Scale);
        FinishSpawningActor(Floor);

        // Destroyed rather than left standing, for the same reason Spawn_BoxActor destroys its own: the
        // caller gets nullptr and no handle, so nothing else can clean this up afterwards.
        const auto NumBaked = utils_jolt_static_world::Request_BakeActor(Floor);
        if (NumBaked == 0)
        {
            ck::groundnav::Warning("GroundNav gym: the floor baked 0 Jolt bodies");
            Floor.DestroyActor();
            return nullptr;
        }

        return Floor;
    }

    //------------------------------------------------------------------------
    // Viewpoint
    //------------------------------------------------------------------------

    // Flies the pawn to a place expressed RELATIVE TO A STATION rather than to a world constant.
    // A gym whose station is placed by Request_ApplyDefaultGridLayout does not know where it stands
    // until the station exists, so a hardcoded view location is wrong the moment the grid changes -
    // and every gym here builds its scene off the same anchor, so the offset that frames the scene
    // is the one thing worth writing down.
    //
    // Safe to call before the pawn is possessed: it says so and returns, which is why every gym
    // calls it once at startup and again a frame later.
    void Request_FlyToStation(
        ACk_Gym_Base_PlayerController InController,
        FString InStationTag,
        FVector InOffsetFromFootprint,
        FRotator InViewRotation)
    {
        if (ck::Is_NOT_Valid(InController))
        { return; }

        auto ViewPawn = InController.GetControlledPawn();
        if (ck::Is_NOT_Valid(ViewPawn))
        { return; }

        FString StationTag = InStationTag;

        const auto Anchor = InController.Get_StationAnchorLocation(StationTag, ECk_GymStation_Anchor::FootprintCenter);

        FVector Offset = InOffsetFromFootprint;
        FRotator ViewRotation = InViewRotation;

        ViewPawn.SetActorLocation(Anchor + Offset);
        InController.SetControlRotation(ViewRotation);
    }

    //------------------------------------------------------------------------
    // Status readbacks - asked for as the row is built, never mirrored
    //------------------------------------------------------------------------

    // The volume's own counts. InStageWhenUnbuilt is the one thing a volume cannot answer - WHAT it
    // is waiting on - so the caller supplies it and everything else is read here.
    FString Get_FieldStatusText(FCk_Handle_GroundNavVolume InVolume, FString InStageWhenUnbuilt)
    {
        if (utils_ground_nav_volume::Get_IsBuilt(InVolume) == false)
        { return InStageWhenUnbuilt; }

        const auto Epoch = utils_ground_nav_volume::Get_BuildEpoch(InVolume);
        const auto TilesBuilt = utils_ground_nav_volume::Get_BuiltTileCount(InVolume);
        const auto TilesTotal = utils_ground_nav_volume::Get_TileCount(InVolume);
        const auto Cells = utils_ground_nav_volume::Get_WalkableCellCount(InVolume);
        const auto Seams = utils_ground_nav_volume::Get_SeamPortalCount(InVolume);

        return f"epoch {Epoch} - {TilesBuilt} of {TilesTotal} tiles built - {Cells} walkable cells - {Seams} seam portals";
    }

    // The world's provider, not any one volume's: which backend is answering, whether it is healthy,
    // and whether what it publishes has gone quiet. A gym's verdict is only worth reading when it has.
    FString Get_SurfaceStatusText()
    {
        const auto Provider = utils_nav_surface::Get_Provider();
        const auto Health = utils_nav_surface::Get_ProviderHealth();
        const auto Revision = utils_nav_surface::Get_SurfaceRevision();
        const auto Settled = utils_nav_surface::Get_IsSurfaceSettled();

        return f"{Provider} - health {Health} - revision {Revision} - settled: {Settled}";
    }

    // The static-body count is read off the world as the row is built rather than remembered: a gym
    // that toggles or moves a body changes it, and a number captured at startup would go on reporting
    // the scene as it was first spawned.
    FString Get_GeometryStatusText(bool InSceneIsBuilt, FString InSceneSummary)
    {
        const auto Bodies = utils_jolt_static_world::Get_NumStaticBodies();

        if (InSceneIsBuilt == false)
        { return f"NOT BAKED INTO JOLT ({Bodies} static bodies) - every bake will find nothing"; }

        return f"{Bodies} static bodies - " + InSceneSummary;
    }

    //------------------------------------------------------------------------
    // The provider row - shared by every gym that mints a volume
    //
    // The provider is a per-WORLD choice, so the label and the swap are the same
    // two lines in every gym that offers them. What differs is only the sentence
    // each gym logs afterwards, which is why the swap hands the new provider back
    // instead of logging one of its own.
    //------------------------------------------------------------------------

    FString Get_ProviderLabel()
    {
        const auto Provider = utils_nav_surface::Get_Provider();

        if (Provider == ECk_NavSurface_Provider::GroundNav)
        { return "GroundNav (this gym's volume answers)"; }

        return "Recast (the volume stays baked, but nothing routes through it)";
    }

    ECk_NavSurface_Provider Request_CycleProvider()
    {
        ECk_NavSurface_Provider Next = ECk_NavSurface_Provider::GroundNav;

        if (utils_nav_surface::Get_Provider() == ECk_NavSurface_Provider::GroundNav)
        { Next = ECk_NavSurface_Provider::Recast; }

        utils_nav_surface::Request_SetProvider(Next);

        return Next;
    }

    //------------------------------------------------------------------------
    // The debug-draw cvars
    //
    // A gym owns whatever it pushes here and never reads it back, because there is
    // nothing to read it back with: AngelScript is bound no console-variable READER
    // at all - the CVar utility exposes Make_CVarRef and IsRegistered and no getter
    // of any type.
    //------------------------------------------------------------------------

    void Set_DebugTunable(FString InName, float InValue)
    {
        System::ExecuteConsoleCommand(f"ck.GroundNav.Debug.{InName} {InValue}");
    }

    //------------------------------------------------------------------------
    // The debug-draw COMMANDS
    //
    // ck.GroundNav.Debug.Mode selects what a bake draws and nothing redraws on
    // its own, so a gym that wants a picture on screen has to run the commands
    // that make one. There are two retained groups and each command owns
    // exactly one: a field bake replaces the FIELD group (the plates), and
    // LinksAt / PathAt each replace the QUERY group with their own answer.
    //
    // Do_PublishRetainedDebugDraw destroys the group it is about to publish
    // into BEFORE it appends, so a re-bake replaces its own picture and needs
    // no Clear in front of it. The same fact the other way round: a bake leaves
    // whatever stands in the QUERY group exactly where it was. A gym that wants
    // the query half gone has to say so, which is the only thing
    // Request_ClearDebugDraw is for.
    //------------------------------------------------------------------------

    // Drops both retained groups, drops the debug field every probe command queries, and - because
    // ck.GroundNav.Clear ends in FlushPersistentDebugLines - flushes EVERY persistent debug line in
    // the world, including ones no GroundNav command drew. Blunt on purpose and blunt everywhere, so
    // a gym that only wants its own plates replaced re-bakes instead of calling this.
    void Request_ClearDebugDraw()
    {
        System::ExecuteConsoleCommand("ck.GroundNav.Clear");
    }

    // The DEBUG field bake, which is a PICTURE and not a volume: nothing can be asked of it, and it is
    // the only field ck.GroundNav.PathAt and ck.GroundNav.ProbeAt can read.
    //
    // EVERY cvar Make_BakeParams reads is pushed here, from the field the caller minted. That is the
    // whole point of taking the field rather than a handful of floats: the debug bake's tunables are
    // WORLD state, one console set apart from each other, so a gym that pushed only the two it cared
    // about would draw a picture carrying whatever the last gym to visit this world left behind - a
    // Tuning gym's slope limit, its cell size, its agent radius - while the rows beside it read the
    // volume's own field. The two disagreeing is the bug this closes.
    //
    // AgentHeightUu inverts Make_BakeParams' own arithmetic: it rebuilds the capsule as
    // ((height * 0.5) - radius, radius), so the height that reproduces the profile's capsule is
    // 2 * (half-height + radius).
    void Request_BakeDebugFieldAt(
        const FCkGroundNavGym_Field&in InField,
        FVector InCentre,
        float   InExtentUu,
        float   InHeightUu,
        int32   InMaxCells,
        int32   InDrawMode)
    {
        // A declared local of the concrete type: an AS struct parameter is implicitly const, `auto`
        // preserves const (Script/ARCHITECTURE.md 9.2), and the field's readers are plain non-const
        // struct methods. This is the copy that launders it.
        FCkGroundNavGym_Field Field = InField;
        FCk_GroundNav_MergeTunables Merge = Field.Get_MergeTunables();

        Set_DebugTunable("CellSizeUu", Field.Get_CellSizeUu());
        Set_DebugTunable("CellHeightUu", Field.Get_CellHeightUu());
        Set_DebugTunable("TileSizeUu", Field.Get_TileSizeUu());

        Set_DebugTunable("AgentHeightUu", Field.Get_AgentHeightUu());
        Set_DebugTunable("AgentRadiusUu", Field.Get_AgentRadiusUu());
        Set_DebugTunable("MaxSlopeDegrees", Field.Get_MaxSlopeDegrees());
        Set_DebugTunable("MaxSlopeChangeDegrees", Field.Get_MaxSlopeChangeDegrees());
        Set_DebugTunable("StepHeightUu", Field.Get_StepHeightUu());
        Set_DebugTunable("LedgeSensitivity", Field.Get_LedgeSensitivity());
        Set_DebugTunable("RoughPerchToleranceUu", Field.Get_RoughPerchToleranceUu());

        Set_DebugTunable("PlaneFitToleranceUu", Merge.Get_PlaneFitToleranceUu());
        Set_DebugTunable("NormalConeDegrees", Merge.Get_NormalConeDegrees());

        Set_DebugTunable("ExtentUu", InExtentUu);
        Set_DebugTunable("HeightUu", InHeightUu);
        Set_DebugTunable("MaxCells", float(InMaxCells));
        Set_DebugTunable("Mode", float(InDrawMode));

        FVector Centre = InCentre;

        System::ExecuteConsoleCommand(f"ck.GroundNav.BakeFieldAt {Centre.X} {Centre.Y} {Centre.Z}");
    }

    // Draws and reports every link this world's volumes hold, off their PUBLISHED fields, so it needs
    // no bake of its own: green traversable, grey disabled, orange an end over ground nobody has baked,
    // red an end with no ground under it. Re-run it after anything that changes a record - the colours
    // come off the field the derive publishes, not off the record store.
    void Request_ReportLinksAt(FVector InWhere)
    {
        FVector Where = InWhere;

        System::ExecuteConsoleCommand(f"ck.GroundNav.LinksAt {Where.X} {Where.Y} {Where.Z}");
    }

    // Reads the DEBUG field, so Request_BakeDebugFieldAt has to have run over the ground this route
    // crosses: a region bake, or no bake at all, leaves it with nothing to path through.
    void Request_DrawPathAt(FVector InStart, FVector InGoal)
    {
        FVector Start = InStart;
        FVector Goal = InGoal;

        System::ExecuteConsoleCommand(
            f"ck.GroundNav.PathAt {Start.X} {Start.Y} {Start.Z} {Goal.X} {Goal.Y} {Goal.Z}");
    }

    // The console lines a reader can type for themselves, aimed at a point the gym computed. A
    // hardcoded "0 0 0" would name the world origin, and every gym scene stands wherever
    // Request_ApplyDefaultGridLayout put its station - so the coordinates are only known at runtime.
    // Rounded because the line is read by a person rather than parsed back.
    FString Get_BakeFieldAtCommandText(FVector InWhere)
    {
        return "ck.GroundNav.BakeFieldAt " + Get_PointCommandText(InWhere);
    }

    FString Get_LinksAtCommandText(FVector InWhere)
    {
        return "ck.GroundNav.LinksAt " + Get_PointCommandText(InWhere);
    }

    FString Get_PointCommandText(FVector InWhere)
    {
        FVector Where = InWhere;

        const auto X = Math::RoundToInt(float32(Where.X));
        const auto Y = Math::RoundToInt(float32(Where.Y));
        const auto Z = Math::RoundToInt(float32(Where.Z));

        return f"{X} {Y} {Z}";
    }

    // Asks the PROVIDER-NEUTRAL facade what is under a point. The search half-extents are the whole
    // discipline of it: a generous Z reaches PAST the surface being asked about and answers with the
    // floor below, which reads as a success and says nothing. Keep the Z tight enough that only the
    // surface in question is inside it.
    ECk_NavSurface_QueryStatus Get_ProjectedStatus(FVector InLocation, FVector InSearchHalfExtents)
    {
        FVector Location = InLocation;
        FVector SearchHalfExtents = InSearchHalfExtents;

        auto Query = FCk_NavSurface_ProjectionQuery(Location);
        Query.Set_SearchHalfExtents(SearchHalfExtents);

        return utils_nav_surface::Try_ProjectPoint(Query).Get_Status();
    }

    // Joins a list of reasons into one FAIL string. AngelScript has no Join and no brace-initialised
    // TArray, so this is the imperative shape every verdict row would otherwise repeat.
    FString Get_VerdictText(FString InOkText, const TArray<FString>&in InFailures)
    {
        if (InFailures.Num() == 0)
        { return InOkText; }

        FString Text = "FAIL: ";

        for (int32 Index = 0; Index < InFailures.Num(); Index++)
        {
            if (Index > 0)
            { Text += "; "; }

            Text += InFailures[Index];
        }

        return Text;
    }

    //------------------------------------------------------------------------
    // The debug picture's draw modes - ck.GroundNav.Debug.Mode 0-7, in the
    // order Make_DrawSelection maps them. The demo frame's T row reads these.
    //------------------------------------------------------------------------

    int32 Get_DrawModeCount()
    { return 8; }

    // ck.GroundNav.Debug.Mode 0-7, in the order Make_DrawSelection maps them.
    TArray<FString> Get_DrawModeLabels()
    {
        auto Labels = TArray<FString>();
        Labels.Add("0 Plates");
        Labels.Add("1 Clearance");
        Labels.Add("2 Layers");
        Labels.Add("3 Rejected (what the filters threw away)");
        Labels.Add("4 Portals (the crossings between plates)");
        Labels.Add("5 Tiles");
        Labels.Add("6 Boundary (the walkable edge)");
        Labels.Add("7 Links");
        return Labels;
    }

    TArray<FString> Get_DrawModeLegends()
    {
        auto Legends = TArray<FString>();
        Legends.Add("one wireframe box per plate - green = layer 0, blue = layer 1");
        Legends.Add("one point per cell - BLUE = least room, RED = most (scaled to this bake)");
        Legends.Add("one point per cell - green = layer 0 (ground), blue = layer 1 (a deck above it)");
        Legends.Add("RED = cut by the filters, dim grey = what survived");
        Legends.Add("one line per crossing - BLUE = tightest, RED = widest; a mast marks one that changes floor");
        Legends.Add("BLUE box per tile, RED = a tile that did not build; thick lines = the seams between tiles");
        Legends.Add("one run per walkable edge, drawn where the ground stops");
        Legends.Add("plates plus every link - green traversable, grey disabled, orange an end over unbaked ground, red an end with no ground");
        return Legends;
    }
}

// --------------------------------------------------------------------------------------------------------------------

// ONE minted GroundNav volume, its build result, and the settle every gym waits on.
//
// Guarded so Ck_Gym_Restart re-running a gym does not stack a second volume over the same ground.
struct FCkGroundNavGym_Field
{
    //------------------------------------------------------------------------
    // All UPROPERTY because AS structs reflect their fields.
    //------------------------------------------------------------------------

    // The entity the volume entity is minted UNDER, kept because utils_timer::Add takes its handle BY
    // VALUE and an AS struct parameter is implicitly const, so the owner has to be copied into storage
    // before it can be passed on. (utils_entity_lifetime::Request_CreateEntity takes a const &in and
    // would have been happy with the parameter itself.)
    UPROPERTY() FCk_Handle _Owner;

    UPROPERTY() FCk_Handle _VolumeEntity;
    UPROPERTY() FCk_Handle_GroundNavVolume _Volume;

    // ONE repeating timer, not a chain of one-shots: utils_timer::Add mints a child entity per timer,
    // so re-arming a one-shot every poll would leave one behind for every frame it waited.
    UPROPERTY() FCk_Handle_Timer _SettleTimer;

    UPROPERTY() int32 _SettlePolls = 0;
    UPROPERTY() int32 _SettlePollCeiling = 600;
    UPROPERTY() bool _Armed = false;

    // The one thing about a field with no readback: WHAT it is waiting on. Everything else - built,
    // epoch, tiles, walkable cells, seams - is asked for as the row is built.
    UPROPERTY() FString _Stage = "not started";

    UPROPERTY() int32 _BuildCompletions = 0;
    UPROPERTY() bool _HasBuildResult = false;
    UPROPERTY() ECk_Request_OperationResult _LastBuildResult = ECk_Request_OperationResult::Failed;

    // The plate-merge tunables the next mint applies. They are not a Request_Mint parameter because
    // most gyms have no opinion about them, and the default here is the same pair
    // FCk_GroundNav_MergeTunables itself authors (10uu plane fit, 10 degree normal cone) - so a gym
    // that never touches this mints exactly the volume it minted before this member existed.
    //
    // Set it BEFORE Request_Mint / Request_Remint; params are read once, at Add.
    UPROPERTY() FCk_GroundNav_MergeTunables _MergeTunables;

    //------------------------------------------------------------------------
    // What the last mint was made WITH
    //
    // Read off the config and the profile inside Request_Mint and kept, because the debug bake needs
    // every one of them and a volume hands none of them back: FCk_Fragment_GroundNavVolume_ParamsData
    // is not reflected, and the volume exposes counts and epochs rather than the params it was minted
    // under. Without these a gym would have to state its own tunables twice - once to the volume and
    // once to the picture - and the two would drift the first time one was edited.
    //------------------------------------------------------------------------

    UPROPERTY() float _CellSizeUu = 25.0f;
    UPROPERTY() float _CellHeightUu = 10.0f;
    UPROPERTY() float _TileSizeUu = 1600.0f;

    UPROPERTY() float _AgentHalfHeightUu = 90.0f;
    UPROPERTY() float _AgentRadiusUu = 34.0f;
    UPROPERTY() float _MaxSlopeDegrees = 45.0f;
    UPROPERTY() float _MaxSlopeChangeDegrees = 30.0f;
    UPROPERTY() float _StepHeightUu = 40.0f;
    UPROPERTY() float _LedgeSensitivity = 1.0f;
    UPROPERTY() float _RoughPerchToleranceUu = 0.0f;

    //------------------------------------------------------------------------
    // Minting
    //------------------------------------------------------------------------

    // Mints a volume over InBounds, sets the world onto GroundNav, asks for the build and starts
    // polling for the settle. Returns false with the reason in Get_Stage() when the mint itself could
    // not be made - the caller decides how to report it, because this struct owns no panel row.
    //
    // The provider is set HERE rather than per gym: it is a per-WORLD selection, and a volume nobody
    // routes through answers nothing. It is not handed back either - the cycler TRAVELS to reach
    // another gym, so the world this was set on ends with the gym.
    bool Request_Mint(
        FCk_Handle InOwner,
        FName InDebugName,
        const FBox&in InBounds,
        const FCk_GroundNav_BakeConfig&in InConfig,
        const FCk_GroundNav_AgentProfile&in InProfile,
        FName InCookKey,
        int32 InSettlePollCeiling,
        const FCk_Delegate_Request_OnCompleted&in InBuildCompleted,
        const FCk_Delegate_Timer&in InSettlePoll)
    {
        if (_Armed)
        { return ck::IsValid(_Volume); }

        _Owner = InOwner;

        if (ck::Is_NOT_Valid(_Owner))
        {
            _Stage = "the owning entity is invalid - no volume was minted";
            return false;
        }

        _Armed = true;
        _SettlePollCeiling = InSettlePollCeiling;

        utils_nav_surface::Request_SetProvider(ECk_NavSurface_Provider::GroundNav);

        _VolumeEntity = utils_entity_lifetime::Request_CreateEntity(_Owner);
        _VolumeEntity.Request_OverrideToSelf();
        _VolumeEntity.Set_DebugName(InDebugName);

        // Explicitly typed locals rather than auto: an AS struct parameter is const, `auto` PRESERVES
        // const (Script/ARCHITECTURE.md 9.2), and a const value cannot be handed to a by-value
        // parameter. A declared local of the concrete type is the copy that launders it.
        FBox Bounds = InBounds;
        FCk_GroundNav_BakeConfig Config = InConfig;
        FCk_GroundNav_AgentProfile Profile = InProfile;

        Do_RememberBakeTunables(Config, Profile);

        auto VolumeParams = FCk_Fragment_GroundNavVolume_ParamsData(Bounds, Config, Profile);

        // The bake waited on must be the one asked for, not one that happened to run at setup.
        VolumeParams.Set_AutoBuildOnSetup(ECk_EnableDisable::Disable);
        VolumeParams.Set_CookKey(InCookKey);
        VolumeParams.Set_MergeTunables(_MergeTunables);

        _Volume = utils_ground_nav_volume::Add(_VolumeEntity, VolumeParams);

        if (ck::Is_NOT_Valid(_Volume))
        {
            _Stage = "Add() returned an invalid volume handle";
            return false;
        }

        Do_StartBuildAndSettle(InBuildCompleted, InSettlePoll);
        return true;
    }

    // Copies out of the two params structs the values the debug bake has to be told about. Done at
    // the mint and nowhere else: these describe the field that IS standing, so a gym that re-mints
    // with a different profile gets the new numbers and one that never re-mints keeps the old.
    //
    // The capsule is read back through the shape it was authored as. FCk_AnyShape carries a type tag
    // and one struct per type, so the half-height and the radius survive the round trip - which is
    // what lets AgentHeightUu be reconstructed rather than passed in beside the profile.
    void Do_RememberBakeTunables(
        const FCk_GroundNav_BakeConfig&in InConfig,
        const FCk_GroundNav_AgentProfile&in InProfile)
    {
        FCk_GroundNav_BakeConfig Config = InConfig;
        FCk_GroundNav_AgentProfile Profile = InProfile;

        _CellSizeUu = Config.Get_CellSizeUu();
        _CellHeightUu = Config.Get_CellHeightUu();
        _TileSizeUu = Config.Get_TileSizeUu();

        FCk_AnyShape Standing = Profile.Get_StandingExtents();
        FCk_ShapeCapsule_Dimensions Capsule = Standing.Get_Capsule();

        _AgentHalfHeightUu = Capsule.Get_HalfHeight();
        _AgentRadiusUu = Capsule.Get_Radius();

        _MaxSlopeDegrees = Profile.Get_MaxSlopeDegrees();
        _MaxSlopeChangeDegrees = Profile.Get_MaxSlopeChangeDegrees();
        _StepHeightUu = Profile.Get_StepHeightUu();
        _LedgeSensitivity = Profile.Get_LedgeSensitivity();
        _RoughPerchToleranceUu = Profile.Get_RoughPerchToleranceUu();
    }

    // Re-asks for the build the volume was minted with and restarts the settle. The profile and the
    // bounds are unchanged - this is "read the world again", which is what a gym owes its verdict
    // after anything moved in the Jolt static world.
    bool Request_Rebuild(
        const FCk_Delegate_Request_OnCompleted&in InBuildCompleted,
        const FCk_Delegate_Timer&in InSettlePoll)
    {
        if (ck::Is_NOT_Valid(_Volume))
        { return false; }

        Do_StartBuildAndSettle(InBuildCompleted, InSettlePoll);
        return true;
    }

    // Mints the volume AGAIN, from values that may have moved since the last mint.
    //
    // A volume's params are read ONCE, at Add, and no request re-authors them - so a gym whose panel
    // moves a bake tunable cannot push that tunable into a standing volume. Re-minting is the only
    // way a volume can track what the panel says, and a verdict read off a volume that did NOT track
    // it is a row whose value does not move when the reader turns the dial.
    //
    // Destroy first, then mint, in that order: the old field is retired before the new one publishes,
    // so the settle being waited on afterwards is the NEW bake's and not the tail of the old one's.
    // Safe before the first mint - Request_Destroy is a no-op on an unarmed field.
    bool Request_Remint(
        FCk_Handle InOwner,
        FName InDebugName,
        const FBox&in InBounds,
        const FCk_GroundNav_BakeConfig&in InConfig,
        const FCk_GroundNav_AgentProfile&in InProfile,
        FName InCookKey,
        int32 InSettlePollCeiling,
        const FCk_Delegate_Request_OnCompleted&in InBuildCompleted,
        const FCk_Delegate_Timer&in InSettlePoll)
    {
        Request_Destroy();

        // Explicitly typed locals for the by-value parameters, for the same reason Request_Mint
        // declares its own: an AS struct parameter is implicitly const and a const value cannot be
        // handed to a by-value parameter (Script/ARCHITECTURE.md 9.2).
        FCk_Handle Owner = InOwner;
        FName DebugName = InDebugName;
        FName CookKey = InCookKey;

        return Request_Mint(Owner, DebugName, InBounds, InConfig, InProfile, CookKey,
            InSettlePollCeiling, InBuildCompleted, InSettlePoll);
    }

    // Tears the minted volume down and disarms, so the next Request_Mint builds a fresh one rather
    // than being turned away by the _Armed guard. Idempotent.
    //
    // THE SETTLE POLL IS STOPPED FIRST, and it has to be stopped explicitly: utils_timer::Add mints
    // the poll timer under _OWNER - the gym's own entity - not under the volume entity, so destroying
    // the volume cascades nothing to it. Stopping it before the handles are cleared is what makes it
    // impossible for a poll to run against the dead volume. Even one that somehow did would read
    // nothing dangerous - Do_PollSettle asks the WORLD whether the surface is settled and touches
    // _Volume nowhere - but that is the belt, not the argument.
    //
    // The build result is cleared with the volume it described: a Succeeded left standing from the
    // previous volume would be read by the next verdict as this volume's answer.
    void Request_Destroy()
    {
        Do_StopSettlePoll();

        if (ck::IsValid(_VolumeEntity))
        { utils_entity_lifetime::Request_DestroyEntity(_VolumeEntity); }

        _VolumeEntity = FCk_Handle();
        _Volume = FCk_Handle_GroundNavVolume();

        _Armed = false;
        _SettlePolls = 0;

        _HasBuildResult = false;
        _LastBuildResult = ECk_Request_OperationResult::Failed;

        // _BuildCompletions is NOT reset - it counts what this gym has asked of GroundNav across the
        // whole session, which is the only thing that number was ever useful for.

        _Stage = "the volume was destroyed - nothing is baked";
    }

    void Do_StartBuildAndSettle(
        const FCk_Delegate_Request_OnCompleted&in InBuildCompleted,
        const FCk_Delegate_Timer&in InSettlePoll)
    {
        Do_StopSettlePoll();

        utils_ground_nav_volume::Request_Build(_Volume, FCk_Request_GroundNavVolume_Build(), InBuildCompleted);

        _Stage = "baking, then waiting for the surface to settle";
        _SettlePolls = 0;

        auto PollParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.05));
        PollParams.Set_StartingState(ECk_Timer_State::Running)
                  .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);

        auto PollTimer = utils_timer::Add(_Owner, PollParams);
        PollTimer.BindTo_OnDone(InSettlePoll);

        _SettleTimer = PollTimer;
    }

    //------------------------------------------------------------------------
    // The settle
    //------------------------------------------------------------------------

    // The one named condition worth waiting on after a bake: nothing in flight and nothing pending,
    // so the field the volume publishes is the one every query answers from. A fixed number of hops
    // would bake a guess about the probe budget into the gym.
    //
    // At 0.05s a poll the ceiling is a wall-clock budget: 600 is thirty seconds, 1200 a minute. When
    // it runs out the stage says so in the gym's own status row rather than the gym hanging silently.
    ECkGroundNavGym_Settle Do_PollSettle()
    {
        _SettlePolls += 1;

        if (utils_nav_surface::Get_IsSurfaceSettled())
        {
            Do_StopSettlePoll();
            _Stage = f"settled after {_SettlePolls} polls";
            return ECkGroundNavGym_Settle::Settled;
        }

        if (_SettlePolls >= _SettlePollCeiling)
        {
            Do_StopSettlePoll();
            _Stage = f"the surface never settled after {_SettlePolls} polls";
            return ECkGroundNavGym_Settle::GaveUp;
        }

        return ECkGroundNavGym_Settle::Waiting;
    }

    // Stopped AND destroyed, in that order. utils_timer::Add mints a CHILD ENTITY per timer under
    // _Owner, and Request_Stop only halts it - the entity outlives the stop, so a gym that re-bakes on
    // every keypress would leave one behind per press for the life of the session. Destroying it is
    // also what makes a late poll impossible rather than merely harmless: a stopped timer's OnDone can
    // no longer be delivered by an entity that is gone.
    //
    // Idempotent: an invalid handle is the state after the first call, and the second one does nothing.
    void Do_StopSettlePoll()
    {
        if (ck::Is_NOT_Valid(_SettleTimer))
        { return; }

        utils_timer::Request_Stop(_SettleTimer);
        utils_entity_lifetime::Request_DestroyEntity(FCk_Handle(_SettleTimer));

        _SettleTimer = FCk_Handle_Timer();
    }

    // Fired by the gym's build-completion UFUNCTION. The result is the volume's own answer to the
    // request this struct made, which is the only thing a verdict can call a bake succeeding.
    void Notify_BuildCompleted(ECk_Request_OperationResult InResult)
    {
        _BuildCompletions += 1;
        _HasBuildResult = true;
        _LastBuildResult = InResult;
    }

    //------------------------------------------------------------------------
    // Readers
    //------------------------------------------------------------------------

    FCk_Handle_GroundNavVolume Get_Volume() { return _Volume; }
    FCk_Handle Get_VolumeEntity() { return _VolumeEntity; }

    bool Get_IsBuilt() { return ck::IsValid(_Volume) && utils_ground_nav_volume::Get_IsBuilt(_Volume); }

    // Asked of the WORLD, not remembered from the settle poll: a bake started after the poll stopped
    // puts the surface back in flight, and a mirrored bool would go on saying it was quiet. A volume
    // that is built but whose surface has not settled is publishing, and its answers are the previous
    // field's - which is why a verdict has to gate on both.
    bool Get_IsSettled() { return utils_nav_surface::Get_IsSurfaceSettled(); }

    int32 Get_WalkableCellCount() { return utils_ground_nav_volume::Get_WalkableCellCount(_Volume); }
    int32 Get_SeamPortalCount() { return utils_ground_nav_volume::Get_SeamPortalCount(_Volume); }

    bool Get_HasBuildResult() { return _HasBuildResult; }
    ECk_Request_OperationResult Get_LastBuildResult() { return _LastBuildResult; }
    int32 Get_BuildCompletions() { return _BuildCompletions; }
    int32 Get_SettlePolls() { return _SettlePolls; }

    FString Get_Stage() { return _Stage; }
    void Set_Stage(FString InStage) { _Stage = InStage; }

    FCk_GroundNav_MergeTunables Get_MergeTunables() { return _MergeTunables; }
    void Set_MergeTunables(FCk_GroundNav_MergeTunables InMergeTunables) { _MergeTunables = InMergeTunables; }

    // What the last mint was made with, for the debug bake that has to reproduce it.
    float Get_CellSizeUu() { return _CellSizeUu; }
    float Get_CellHeightUu() { return _CellHeightUu; }
    float Get_TileSizeUu() { return _TileSizeUu; }

    float Get_AgentRadiusUu() { return _AgentRadiusUu; }

    // The FULL standing height, which is what ck.GroundNav.Debug.AgentHeightUu takes: Make_BakeParams
    // turns it back into a capsule as ((height * 0.5) - radius, radius), so this is the one value
    // that reproduces the profile's own capsule on the other side.
    float Get_AgentHeightUu() { return 2.0f * (_AgentHalfHeightUu + _AgentRadiusUu); }

    float Get_MaxSlopeDegrees() { return _MaxSlopeDegrees; }
    float Get_MaxSlopeChangeDegrees() { return _MaxSlopeChangeDegrees; }
    float Get_StepHeightUu() { return _StepHeightUu; }
    float Get_LedgeSensitivity() { return _LedgeSensitivity; }
    float Get_RoughPerchToleranceUu() { return _RoughPerchToleranceUu; }

    FString Get_FieldStatusText() { return CkGroundNavGym::Get_FieldStatusText(_Volume, _Stage); }
}

// --------------------------------------------------------------------------------------------------------------------

// THE DEFERRED REDRAW every gym here owes its own picture.
//
// A request that changes what the field says - a link toggle, a paint, a nudge, a repair - is
// DEFERRED, and the retained draw is command-driven, so the picture a gym runs at the keypress is
// the picture of the field the keypress is about to change. Redrawing needs a NAMED condition:
// the volume's build epoch has moved past the one read when the request went in, AND the surface
// has gone quiet again. How many passes a derive needs is a property of processor ordering, not of
// frame rate, so a hop count would bake a guess in.
//
// The ceiling is a wall-clock budget at 0.05s a poll (200 is ten seconds), after which the refresh
// runs ANYWAY: a request the derive never answered still leaves the reader looking at what the
// field actually holds rather than at nothing.
//
// A value type held as a member, for the same reason FCkGroundNavGym_Field is one, and with the
// same consequence: an AS struct hosts no UFUNCTION, so the timer's delegate is passed IN and the
// gym owns the poll body. The shape at the call site is:
//
//   _Overlay.Request_Arm(_PcEntity, _Field, 200, FCk_Delegate_Timer(this, n"OnOverlayRefreshPoll"));
//
//   UFUNCTION() private void OnOverlayRefreshPoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
//   {
//       if (_Overlay.Do_Poll(_Field)) { ...the gym's own redraw... }
//   }
struct FCkGroundNavGym_OverlayRefresh
{
    // Kept because utils_timer::Add takes its handle BY VALUE and an AS struct parameter is
    // implicitly const, so the owner has to be copied into storage before it can be passed on.
    UPROPERTY() FCk_Handle _Owner;

    UPROPERTY() FCk_Handle_Timer _Timer;
    UPROPERTY() int32 _Polls = 0;
    UPROPERTY() int32 _PollCeiling = 200;

    // The epoch the request was made AGAINST. The wait is for the field to move past it.
    UPROPERTY() int64 _EpochAtArm = 0;

    // Re-arming replaces the wait rather than stacking a second one: two toggles in quick succession
    // are one question - "what does the field say once it is quiet" - and the later arm is the one
    // whose epoch is right.
    void Request_Arm(
        FCk_Handle InOwner,
        const FCkGroundNavGym_Field&in InField,
        int32 InPollCeiling,
        const FCk_Delegate_Timer&in InPoll)
    {
        Request_Stop();

        _Owner = InOwner;

        if (ck::Is_NOT_Valid(_Owner))
        { return; }

        FCkGroundNavGym_Field Field = InField;

        _EpochAtArm = utils_ground_nav_volume::Get_BuildEpoch(Field.Get_Volume());
        _PollCeiling = InPollCeiling;
        _Polls = 0;

        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(0.05));
        Params.Set_StartingState(ECk_Timer_State::Running)
              .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);

        auto Timer = utils_timer::Add(_Owner, Params);
        Timer.BindTo_OnDone(InPoll);

        _Timer = Timer;
    }

    // Stopped AND destroyed, in that order. utils_timer::Add mints a CHILD ENTITY per timer under
    // the owner, and a stop alone would leave one behind per arm for the life of the session.
    // Idempotent - an invalid handle is the state after the first call.
    void Request_Stop()
    {
        if (ck::Is_NOT_Valid(_Timer))
        { return; }

        utils_timer::Request_Stop(_Timer);
        utils_entity_lifetime::Request_DestroyEntity(FCk_Handle(_Timer));

        _Timer = FCk_Handle_Timer();
    }

    // True when the caller should redraw NOW - the field republished, or the ceiling ran out. The
    // timer is stopped before either answer, so a caller that redraws on true is redrawing once.
    bool Do_Poll(const FCkGroundNavGym_Field&in InField)
    {
        FCkGroundNavGym_Field Field = InField;

        _Polls += 1;

        const auto Republished = utils_ground_nav_volume::Get_BuildEpoch(Field.Get_Volume()) > _EpochAtArm
            && utils_nav_surface::Get_IsSurfaceSettled();

        if (Republished == false && _Polls < _PollCeiling)
        { return false; }

        Request_Stop();

        return true;
    }

    // Whether a redraw is still owed. A gym's verdict reads this to say "pending" rather than "FAIL"
    // while the field it is judging has not finished moving.
    bool Get_IsWaiting() { return ck::IsValid(_Timer); }

    int32 Get_Polls() { return _Polls; }
}
