//============================================================================
// PROBE GYM - TRACE STATION (WORLD-HIT POLICY)
//
// The human-verifiable face of the ProbeTrace world-hit policy. Layout along
// the station's local +X:
//
//   start ---- [ baked BlockAll cube ] ---- [ target probe ]
//
// A shape trace re-runs every frame across both. Cycle the policy with
//   Ck_GymProbeTrace_Ignore / _Blocking / _Reported
// and watch the marker move:
//
//   Ignore   - the cube is invisible; the trace reports only the probe BEHIND
//              it (today's wallhack default, shown deliberately).
//   Blocking - the cube truncates; the probe disappears from the results.
//   Reported - both are reported, in near-to-far order.
//
// Markers are drawn locally (green = probe hit, red = world hit) so the station
// reads without touching any setting. The framework's own trace overlay is
// separate: enable Ck user setting DebugPreviewAllLineTraces to see it too.
//============================================================================

class UCk_EntityScript_ProbeGym_TraceStation : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    private FCk_Handle SelfHandle;
    private FCk_Handle ProbeEntity;
    private AStaticMeshActor WallActor;

    private FVector StationWorldLocation;
    private ECk_ProbeTrace_WorldHitPolicy CurrentPolicy = ECk_ProbeTrace_WorldHitPolicy::Ignore;

    // Station-local offsets along +X, all at the station's own Z.
    private float32 TraceStartOffset = -600.0f;
    private float32 WallOffset = 0.0f;
    private float32 ProbeOffset = 350.0f;
    private float32 TraceEndOffset = 700.0f;
    private float32 ProbeHalfExtent = 60.0f;
    private float32 CastRadius = 25.0f;

    private int32 BakedBodies = 0;
    private FString LastSummary = "(no cast yet)";
    private int32 LastHitCount = 0;

    private TArray<FCk_Handle_Pmg_DebugShape> HitMarkers;
    private FLinearColor ProbeHitColor = FLinearColor(0.2f, 1.0f, 0.3f, 1.0f);
    private FLinearColor WorldHitColor = FLinearColor(1.0f, 0.25f, 0.2f, 1.0f);

    private FCk_Handle_Timer AutoTimer;
    private bool AutoRunning = true;
    private FCkGym_AutoConfig AutoConfig;

    //------------------------------------------------------------------------
    // Construction
    //------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        InHandle.Set_DebugName(n"TraceStation");
        SelfHandle = InHandle;

        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, n"TAG_ProbeGym_TraceStation");
        StationWorldLocation = InitialTransform.Translation;

        // Target probe - the thing a probe-only trace is meant to find.
        ProbeEntity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        ProbeEntity.Set_DebugName(n"TraceTarget");
        ProbeEntity.Request_OverrideToSelf();

        auto ProbeTransform = utils_transform::Add(ProbeEntity,
            FTransform(FRotator::ZeroRotator, Get_LocalPoint(ProbeOffset)), ECk_Replication::DoesNotReplicate);

        auto ProbeParams = FCk_Fragment_Probe_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.Probe.Gym.TraceTarget"));
        ProbeParams.Set_MotionType(ECk_MotionType::Static);
        ProbeParams.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Silent);
        utils_probe::Add_Box(ProbeTransform,
            FVector(ProbeHalfExtent, ProbeHalfExtent, ProbeHalfExtent), ProbeParams, FCk_Probe_DebugInfo());

        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"FrameTick"));

        AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(1.0f));

        AutoConfig.TotalSteps = 1;
        AutoConfig.Description =
            "A shape trace runs left-to-right across\n" +
            "a baked cube and a target probe.\n" +
            "Cycle the world-hit policy and watch\n" +
            "which markers survive:\n" +
            "  Ignore   = cube invisible (wallhack)\n" +
            "  Blocking = cube truncates the probe\n" +
            "  Reported = both, near-to-far";
        AutoConfig.GlobalAutoCommand = "Ck_GymProbe_Auto [0/1]";
        AutoConfig.PerStationAutoCommand = "Ck_GymProbe_AutoTrace";
        AutoConfig.Steps.Add(FCkGym_AutoStep("Auto=ON re-casts every frame", 0, 0));
        AutoConfig.ManualCommands.Add("Ck_GymProbeTrace_Ignore");
        AutoConfig.ManualCommands.Add("Ck_GymProbeTrace_Blocking");
        AutoConfig.ManualCommands.Add("Ck_GymProbeTrace_Reported");

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Cube = Cast<UStaticMesh>(LoadObject(UStaticMesh, "/Engine/BasicShapes/Cube.Cube"));
        if (!IsValid(Cube))
        { return; }

        WallActor = Cast<AStaticMeshActor>(SpawnActor(AStaticMeshActor, Get_LocalPoint(WallOffset)));
        WallActor.StaticMeshComponent.SetMobility(EComponentMobility::Movable);
        WallActor.StaticMeshComponent.SetStaticMesh(Cube);
        WallActor.StaticMeshComponent.SetCollisionProfileName(n"BlockAll");

        // The bake is what puts the cube into the Jolt static world; without it the
        // trace has nothing non-probe to find, whatever the policy says.
        BakedBodies = utils_jolt_static_world::Request_BakeActor(WallActor);

        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_ProbeGymTrace_SetWorldHitPolicy,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnSetWorldHitPolicy"));
    }

    //------------------------------------------------------------------------
    // Casting
    //------------------------------------------------------------------------

    // World +X, matching how the physical station lays its balls out - the station panel's own
    // rotation is not worth a dependency here, and the trace reads fine from any viewing angle.
    private FVector Get_LocalPoint(float32 InForwardOffset) const
    {
        return StationWorldLocation + FVector(InForwardOffset, 0.0, 0.0);
    }

    private FCk_ShapeCast_Settings Make_Settings() const
    {
        auto Filter = FGameplayTagContainer();
        Filter.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"CkTests.Probe.Gym.TraceTarget"));

        auto Settings = FCk_ShapeCast_Settings(
            Get_LocalPoint(TraceStartOffset),
            Get_LocalPoint(TraceEndOffset),
            utils_shapes::Make_Sphere(FCk_ShapeSphere_Dimensions(CastRadius)),
            Filter);

        Settings.Set_WorldHitPolicy(CurrentPolicy);
        // The station is a viewer, not a participant: pinging the target probe every
        // frame would make the demo lie about what a trace costs.
        Settings.Set_OverlapNotifyPolicy(ECk_ProbeResponse_Policy::Silent);
        return Settings;
    }

    UFUNCTION()
    private void FrameTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (AutoRunning)
        { Do_Cast(); }

        DisplayCurrentValues();
    }

    private void Do_Cast()
    {
        auto Hits = utils_probe_trace::Request_MultiShapeTrace(SelfHandle, Make_Settings());

        Do_RefreshMarkers(Hits);

        LastHitCount = Hits.Num();
        LastSummary = Hits.Num() == 0 ? FString("(no hits)") : FString("");

        for (int32 i = 0; i < Hits.Num(); ++i)
        {
            auto Kind = Hits[i].Get_HitKind() == ECk_ProbeTrace_HitKind::World
                ? FString("World")
                : FString("Probe");
            auto Fraction = Hits[i].Get_Fraction();
            auto Separator = i == 0 ? FString("") : FString(", ");
            LastSummary = f"{LastSummary}{Separator}{Kind}@{Fraction :.2}";
        }
    }

    // Markers are destroyed and respawned wholesale: hit COUNT changes with the policy,
    // so there is no stable per-marker identity to update in place.
    private void Do_RefreshMarkers(const TArray<FCk_ShapeCast_Result>& InHits)
    {
        for (int32 i = 0; i < HitMarkers.Num(); ++i)
        {
            if (ck::IsValid(HitMarkers[i]))
            { utils_entity_lifetime::Request_DestroyEntity(HitMarkers[i]); }
        }
        HitMarkers.Empty();

        for (int32 i = 0; i < InHits.Num(); ++i)
        {
            auto Color = InHits[i].Get_HitKind() == ECk_ProbeTrace_HitKind::World
                ? WorldHitColor
                : ProbeHitColor;

            HitMarkers.Add(utils_pmg_basic_shapes::DrawFilledSphere(
                InHits[i].Get_HitLocation(), CastRadius * 1.5f, 12, 12, Color,
                true, 2.0f, ECk_Plane_Axis::XY, -1.0f));
        }
    }

    //------------------------------------------------------------------------
    // Console -> station
    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnSetWorldHitPolicy(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto Typed = InPayload.Get(FCk_Message_ProbeGymTrace_SetWorldHitPolicy);
        CurrentPolicy = Typed.Policy;
    }

    UFUNCTION()
    private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning);
    }

    UFUNCTION()
    private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
    }

    //------------------------------------------------------------------------
    // Display
    //------------------------------------------------------------------------

    private void DisplayCurrentValues()
    {
        auto SelfEntity = ck::ToEntity(this);
        auto NetworkRole = CkGym_Common::Get_NetworkRoleTitle(SelfEntity);
        auto TitleText = f"PROBE TRACE WORLD HITS ({NetworkRole})";

        auto DisplayText = gym_auto::FormatHeader(AutoConfig, AutoRunning);

        DisplayText = DisplayText + "===== Trace State =====\n";
        DisplayText = f"{DisplayText}Policy: {CurrentPolicy}\n";
        DisplayText = f"{DisplayText}Baked wall bodies: {BakedBodies}\n";
        DisplayText = f"{DisplayText}Hits: {LastHitCount}\n";
        DisplayText = f"{DisplayText}{LastSummary}\n";

        DisplayText = DisplayText + "\n";
        DisplayText = DisplayText + "green marker = Probe hit\n";
        DisplayText = DisplayText + "red marker   = World hit\n";

        DisplayText = DisplayText + gym_auto::FormatAutoAndCommands(AutoConfig, 0, AutoRunning);

        auto Owner = utils_entity_lifetime::Get_LifetimeOwner(SelfEntity);
        auto& Fragment = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        Fragment.Title = FText::FromString(TitleText);
        Fragment.Description = FText::FromString(DisplayText);
    }
}
