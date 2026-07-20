// Language=angelscript

//============================================================================
// CK COMPASS GYM
//
// Interactive compass playground. The gym pawn carries a Compass (Auto
// heading source -> falls back to the pawn entity's actor-synced transform
// yaw, so mouse-turning the pawn sweeps the heading). A ring of category-
// varied POIs surrounds the main station; a live readout traces the heading
// and the nearest entries twice a second.
//
// Stations (content built toward -X from each anchor — house rule):
//   - Main:   POI ring (Quest/Shop/Danger/Info, varied priorities, one
//             ClampToEdge waypoint that pins to the arc edge when behind you)
//   - Stress: 500 standalone POIs on demand (Ck_GymCompass_Stress500)
//
// Exec commands:
//   Ck_GymCompass_Ping            — TTL ping POI 1500uu ahead of the pawn
//   Ck_GymCompass_ToggleQuestFilter — Quest-only category filter on/off
//   Ck_GymCompass_Stress500       — spawn the stress field
//   Ck_GymCompass_ClearStress     — destroy the stress field
//   Ck_GymCompass_Readout         — dump all entries to the log
//============================================================================

class ACk_CompassGym_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_CompassGym_PlayerController;
    default DefaultPawnClass = ACk_CompassGym_Pawn;
}

class ACk_CompassGym_Pawn : ACk_Gym_Base_Pawn
{
    // ADefaultPawn leaves the ACTOR un-yawed under mouse-look (only the control rotation moves).
    // The compass' Auto heading falls back to the pawn ENTITY's actor-synced transform yaw — the
    // actor must follow the controller yaw or the heading never sweeps.
    default bUseControllerRotationYaw = true;

    private FCk_Handle _PawnEntity;
    private FCk_Handle_Compass _Compass;

    void OnEntityConstructed(FCk_Handle_EntityScript InEntityScriptHandle) override
    {
        _PawnEntity = FCk_Handle(InEntityScriptHandle);

        auto Params = FCk_Fragment_Compass_ParamsData(180.0);
        Params.Set_HeadingSource(ECk_Compass_HeadingSource::Auto);
        Params.Set_MaxEntries(16);
        _Compass = utils_compass::Add(_PawnEntity, Params);

        ck::Trace("CompassGym: compass composed on pawn entity");
    }

    FCk_Handle_Compass Get_Compass()
    {
        return _Compass;
    }
}

class ACk_CompassGym_PlayerController : ACk_Gym_Base_PlayerController
{
    private FVector _MainOrigin = FVector::ZeroVector;
    private FVector _StressOrigin = FVector::ZeroVector;
    private TArray<FCk_Handle> _StressPois;
    private bool _QuestFilterActive = false;
    private float _ReadoutAccum = 0.0;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        auto Main = FCkGym_Station_SpawnParams_Payload();
        Main.Tags.Add(n"Gym.Compass.Main");
        Main.Title = FText::FromString("COMPASS");
        auto MainDescription = TArray<FText>();
        MainDescription.Add(FText::FromString("POI ring around the station.\nTurn the mouse to sweep the compass heading."));
        MainDescription.Add(FText::FromString("Ck_GymCompass_Ping\nCk_GymCompass_ToggleQuestFilter\nCk_GymCompass_Readout"));
        Main.Description = MainDescription;
        Main.AutoSize = true;
        Stations.Add(Main);

        auto Stress = FCkGym_Station_SpawnParams_Payload();
        Stress.Tags.Add(n"Gym.Compass.Stress");
        Stress.Title = FText::FromString("COMPASS STRESS");
        auto StressDescription = TArray<FText>();
        StressDescription.Add(FText::FromString("500 POIs on demand — watch the projector's cost."));
        StressDescription.Add(FText::FromString("Ck_GymCompass_Stress500\nCk_GymCompass_ClearStress"));
        Stress.Description = StressDescription;
        Stress.AutoSize = true;
        Stations.Add(Stress);

        return Stations;
    }

    void Request_StartGym() override
    {
        _MainOrigin = Get_StationAnchorLocation("Gym.Compass.Main", ECk_GymStation_Anchor::FootprintCenter);
        _StressOrigin = Get_StationAnchorLocation("Gym.Compass.Stress", ECk_GymStation_Anchor::FootprintCenter);

        // Ring of POIs centered 800uu into -X from the main anchor (content faces -X).
        auto RingCenter = _MainOrigin + FVector(-800.0, 0.0, 100.0);

        // 8 ring positions at 45-degree steps, radius 600 (precomputed — no trig dependency).
        DoAddRingPoi(RingCenter + FVector(600.0, 0.0, 0.0),      n"Poi.Category.Quest",  5);
        DoAddRingPoi(RingCenter + FVector(424.3, 424.3, 0.0),    n"Poi.Category.Shop",   3);
        DoAddRingPoi(RingCenter + FVector(0.0, 600.0, 0.0),      n"Poi.Category.Danger", 4);
        DoAddRingPoi(RingCenter + FVector(-424.3, 424.3, 0.0),   n"Poi.Category.Info",   1);
        DoAddRingPoi(RingCenter + FVector(-600.0, 0.0, 0.0),     n"Poi.Category.Quest",  2);
        DoAddRingPoi(RingCenter + FVector(-424.3, -424.3, 0.0),  n"Poi.Category.Shop",   1);
        DoAddRingPoi(RingCenter + FVector(0.0, -600.0, 0.0),     n"Poi.Category.Danger", 3);
        DoAddRingPoi(RingCenter + FVector(424.3, -424.3, 0.0),   n"Poi.Category.Info",   2);

        // One ClampToEdge waypoint far out — pins to the arc edge when behind the pawn.
        auto WaypointParams = FCk_Fragment_Poi_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Waypoint"));
        WaypointParams.Set_OffscreenPolicy(ECk_Poi_OffscreenPolicy::ClampToEdge);
        WaypointParams.Set_Priority(10);
        utils_poi::Create(ck::TransientEntity(), FTransform(FRotator::ZeroRotator, RingCenter + FVector(-2500.0, 0.0, 0.0)),
            WaypointParams, FCk_Time());

        utils_pmg_basic_shapes::DrawFilledSphere(RingCenter + FVector(-2500.0, 0.0, 60.0), 55.0, 12, 12,
            FLinearColor(0.7, 0.35, 0.95), true, 2.0, ECk_Plane_Axis::XY, -1.0);

        SetActorTickEnabled(true);
        ck::Trace("CompassGym: started — 8-POI ring + clamped waypoint built");
    }

    private void DoAddRingPoi(FVector InLocation, FName InCategoryName, int32 InPriority)
    {
        auto Params = FCk_Fragment_Poi_ParamsData(utils_gameplay_tag::ResolveGameplayTag(InCategoryName));
        Params.Set_Priority(InPriority);
        utils_poi::Create(ck::TransientEntity(), FTransform(FRotator::ZeroRotator, InLocation), Params, FCk_Time());

        // Persistent in-world marker so the POI is visible where it stands (color = category)
        utils_pmg_basic_shapes::DrawFilledSphere(InLocation + FVector(0.0, 0.0, 60.0), 40.0, 12, 12,
            DoGet_CategoryColor(InCategoryName), true, 2.0, ECk_Plane_Axis::XY, -1.0);
    }

    private FLinearColor DoGet_CategoryColor(FName InCategoryName)
    {
        if (InCategoryName == n"Poi.Category.Quest")  { return FLinearColor(1.0, 0.78, 0.25); }
        if (InCategoryName == n"Poi.Category.Shop")   { return FLinearColor(0.95, 0.5, 0.2); }
        if (InCategoryName == n"Poi.Category.Danger") { return FLinearColor(0.9, 0.25, 0.25); }
        if (InCategoryName == n"Poi.Category.Info")   { return FLinearColor(0.35, 0.6, 0.95); }
        return FLinearColor(0.8, 0.8, 0.85);
    }

    private FCk_Handle_Compass DoGet_Compass()
    {
        auto GymPawn = Cast<ACk_CompassGym_Pawn>(ControlledPawn);
        if (GymPawn == nullptr)
        { return FCk_Handle_Compass(); }
        return GymPawn.Get_Compass();
    }

    UFUNCTION(BlueprintOverride)
    void Tick(float InDeltaSeconds)
    {
        auto Compass = DoGet_Compass();
        if (ck::Is_NOT_Valid(Compass))
        { return; }

        DoDrawCompassOverlay(Compass);

        _ReadoutAccum += InDeltaSeconds;
        if (_ReadoutAccum < 0.5)
        { return; }
        _ReadoutAccum = 0.0;

        auto Heading = utils_compass::Get_Heading(Compass);
        auto Entries = utils_compass::Get_Entries(Compass);

        // Diagnostic split: if the heading sticks, this names the broken link — control yaw moves
        // with the mouse; entity yaw only moves if the actor yaws AND the transform actor-syncs.
        auto ControlYaw = GetControlRotation().Yaw;
        FCk_Handle Generic = Compass;
        auto TransformHandle = utils_transform::DoCastChecked(Generic);
        auto EntityYaw = ck::IsValid(TransformHandle)
            ? utils_transform::Get_EntityCurrentRotation(TransformHandle).Yaw
            : 0.0;
        ck::Trace(f"Compass: heading {Heading} | ctrlYaw {ControlYaw} | entYaw {EntityYaw} | {Entries.Num()} entries");
    }

    // The compass itself, in world: a heading needle from the pawn plus North (white) and East
    // (gray) reference ticks — redrawn every frame.
    private void DoDrawCompassOverlay(FCk_Handle_Compass InCompass)
    {
        if (ControlledPawn == nullptr)
        { return; }

        auto Base = ControlledPawn.GetActorLocation() + FVector(0.0, 0.0, 30.0);
        auto Heading = utils_compass::Get_Heading(InCompass);
        auto Rad = Heading * Math::PI / 180.0;
        auto Dir = FVector(Math::Cos(Rad), Math::Sin(Rad), 0.0);

        UCk_Utils_DebugDraw_UE::DrawDebugLine(Base, Base + Dir * 500.0,
            FLinearColor(0.2, 1.0, 0.4), 0.05, 6.0);
        UCk_Utils_DebugDraw_UE::DrawDebugLine(Base, Base + FVector(300.0, 0.0, 0.0),
            FLinearColor(1.0, 1.0, 1.0, 0.6), 0.05, 2.0);
        UCk_Utils_DebugDraw_UE::DrawDebugLine(Base, Base + FVector(0.0, 300.0, 0.0),
            FLinearColor(0.6, 0.6, 0.6, 0.5), 0.05, 2.0);
    }

    UFUNCTION(Exec, DisplayName="Compass Gym - Ping Ahead")
    void Ck_GymCompass_Ping()
    {
        if (ControlledPawn == nullptr)
        { return; }

        auto Ahead = ControlledPawn.GetActorLocation() +
            ControlledPawn.GetActorForwardVector() * 1500.0;

        auto Params = FCk_Fragment_Poi_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Ping"));
        Params.Set_OffscreenPolicy(ECk_Poi_OffscreenPolicy::ClampToEdge);
        Params.Set_Priority(20);
        utils_poi::Create(ck::TransientEntity(), FTransform(FRotator::ZeroRotator, Ahead), Params, FCk_Time(5.0));

        // Marker matches the ping's 5s TTL
        utils_pmg_basic_shapes::DrawFilledSphere(Ahead + FVector(0.0, 0.0, 60.0), 45.0, 12, 12,
            FLinearColor(0.3, 0.9, 0.95), true, 2.0, ECk_Plane_Axis::XY, 5.0);

        ck::Trace("CompassGym: ping placed 1500uu ahead (TTL 5s)");
    }

    UFUNCTION(Exec, DisplayName="Compass Gym - Toggle Quest Filter")
    void Ck_GymCompass_ToggleQuestFilter()
    {
        auto Compass = DoGet_Compass();
        if (ck::Is_NOT_Valid(Compass))
        { return; }

        if (_QuestFilterActive)
        {
            Compass.Request_SetCategoryFilter(FCk_Request_Compass_SetCategoryFilter(FGameplayTagQuery()));
            _QuestFilterActive = false;
            ck::Trace("CompassGym: category filter CLEARED (all POIs)");
            return;
        }

        auto QuestOnly = FGameplayTagContainer();
        QuestOnly.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Quest"));
        Compass.Request_SetCategoryFilter(FCk_Request_Compass_SetCategoryFilter(
            FGameplayTagQuery::MakeQuery_MatchAnyTags(QuestOnly)));
        _QuestFilterActive = true;
        ck::Trace("CompassGym: category filter = Quest only");
    }

    UFUNCTION(Exec, DisplayName="Compass Gym - Stress 500")
    void Ck_GymCompass_Stress500()
    {
        if (_StressPois.Num() > 0)
        {
            ck::Trace("CompassGym: stress field already spawned — clear it first");
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
                auto Poi = utils_poi::Create(ck::TransientEntity(),
                    FTransform(FRotator::ZeroRotator, FieldCenter + Offset),
                    FCk_Fragment_Poi_ParamsData(Category), FCk_Time());
                _StressPois.Add(FCk_Handle(Poi));
            }
        }

        ck::Trace("CompassGym: 500 stress POIs spawned");
    }

    UFUNCTION(Exec, DisplayName="Compass Gym - Clear Stress")
    void Ck_GymCompass_ClearStress()
    {
        for (auto Poi : _StressPois)
        {
            if (ck::IsValid(Poi))
            { utils_entity_lifetime::Request_DestroyEntity(Poi); }
        }
        _StressPois.Empty();
        ck::Trace("CompassGym: stress field cleared");
    }

    UFUNCTION(Exec, DisplayName="Compass Gym - Readout")
    void Ck_GymCompass_Readout()
    {
        auto Compass = DoGet_Compass();
        if (ck::Is_NOT_Valid(Compass))
        { return; }

        auto Heading = utils_compass::Get_Heading(Compass);
        ck::Trace(f"Compass readout: heading {Heading}");

        auto Entries = utils_compass::Get_Entries(Compass);
        for (auto Entry : Entries)
        {
            ck::Trace(f"  bearing {Entry.Get_BearingDegrees()} | offset {Entry.Get_NormalizedOffset()} | dist {Entry.Get_Distance()} | prio {Entry.Get_Priority()}");
        }
    }
}
