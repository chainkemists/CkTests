// Language=angelscript
//
//============================================================================
// CkAggro Gym — station EntityScripts
//
// Three self-driving demos of the threat/target-selection feature, visualized
// with utils_debug_draw. All authority-side; each station owns a "guard" Aggro
// entity plus dummy "attacker" entities it tracks.
//
//   1. Chase        — bursts of threat rotate the active target; the guard eases
//                     toward whoever it is aggro'd on. Dummies redden with threat.
//   2. Perception   — a vision cone gates decay: a dummy inside the cone is
//                     perceived (keeps its threat); outside, threat decays fast.
//   3. Stress       — many guards x many dummies; the pipeline holds, a sampled
//                     guard reports its selection.
//============================================================================

USTRUCT()
struct FCkAggroGym_Station_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY()
    FString StationTitle;

    UPROPERTY()
    FString StationDescription;
}

// ====================================================================================================================
// Station 1 — Aggro + Chase
// ====================================================================================================================

class UCk_EntityScript_AggroGym_Chase_Station : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn) FTransform InitialTransform = FTransform::Identity;
    UPROPERTY(ExposeOnSpawn) FString StationTitle;
    UPROPERTY(ExposeOnSpawn) FString StationDescription;

    private FCk_Handle_Aggro _Guard;
    private FCk_Handle_Transform _GuardTransform;
    private TArray<FCk_Handle_Transform> _Dummies;
    private float _FeedTimer = 0.0;
    private int32 _FeedIndex = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        auto Center = InitialTransform.Location + FVector(0.0, 0.0, 150.0);

        auto GuardEntity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        GuardEntity.Set_DebugName(n"AggroGym.Chase.Guard");
        _GuardTransform = utils_transform::Add(GuardEntity, FTransform(FRotator::ZeroRotator, Center), ECk_Replication::DoesNotReplicate);
        _Guard = utils_aggro::Add(GuardEntity, FCk_Fragment_Aggro_ParamsData());

        for (int32 i = 0; i < 3; i++)
        {
            auto Angle = float(i) * 2.0943951;   // 120 degrees
            auto Loc = Center + FVector(Math::Cos(Angle) * 450.0, Math::Sin(Angle) * 450.0, 0.0);

            auto Dummy = utils_entity_lifetime::Request_CreateEntity(InHandle);
            Dummy.Set_DebugName(n"AggroGym.Chase.Dummy");
            auto DummyTransform = utils_transform::Add(Dummy, FTransform(FRotator::ZeroRotator, Loc), ECk_Replication::DoesNotReplicate);
            _Dummies.Add(DummyTransform);
            _Guard.CreateTarget(FCk_Handle(DummyTransform));
        }

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));
        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto DtSec = float(InDeltaT.Get_Seconds());
        _FeedTimer += DtSec;

        // Every 2.5s, dump a burst of threat on the next dummy — the active target rotates around the ring.
        if (_FeedTimer >= 2.5)
        {
            _FeedTimer = 0.0;
            _FeedIndex = (_FeedIndex + 1) % _Dummies.Num();
            _Guard.Request_AddThreat(FCk_Request_Aggro_AddThreat(FCk_Handle(_Dummies[_FeedIndex]), 25.0));
        }

        auto GuardLoc      = utils_transform::Get_EntityCurrentLocation(_GuardTransform);
        auto ActiveTracked = _Guard.TryGet_ActiveTrackedEntity();

        // Highest threat across the tracked dummies, for relative colouring.
        float MaxThreat = 0.001f;
        for (auto DummyTransform : _Dummies)
        {
            auto Target = _Guard.TryGet_Target_ByTrackedEntity(FCk_Handle(DummyTransform));
            if (ck::IsValid(Target))
            { MaxThreat = Math::Max(MaxThreat, Target.Get_Threat()); }
        }

        // Chase: ease the guard toward the active target, and draw the aggro line.
        if (ck::IsValid(ActiveTracked))
        {
            for (auto DummyTransform : _Dummies)
            {
                if (FCk_Handle(DummyTransform) != ActiveTracked)
                { continue; }

                auto TargetLoc = utils_transform::Get_EntityCurrentLocation(DummyTransform);
                auto NewLoc    = GuardLoc + (TargetLoc - GuardLoc) * 0.03;
                utils_transform::Request_SetLocation(_GuardTransform, FCk_Request_Transform_SetLocation(NewLoc));
                utils_debug_draw::DrawDebugLine(GuardLoc, TargetLoc, FLinearColor(1.0, 0.9, 0.2), 0.0, 3.0);
                break;
            }
        }

        // Dummies — redder = more threat.
        for (auto DummyTransform : _Dummies)
        {
            auto  Loc    = utils_transform::Get_EntityCurrentLocation(DummyTransform);
            auto  Target = _Guard.TryGet_Target_ByTrackedEntity(FCk_Handle(DummyTransform));
            float Threat = ck::IsValid(Target) ? Target.Get_Threat() : 0.0f;
            float Frac   = Math::Clamp(Threat / MaxThreat, 0.0f, 1.0f);
            utils_debug_draw::DrawDebugSphere(Loc, 50.0, 12, FLinearColor(0.3 + 0.7 * Frac, 0.25, 0.25), 0.0, 2.0);
        }

        utils_debug_draw::DrawDebugSphere(GuardLoc, 40.0, 12, FLinearColor(0.2, 0.6, 1.0), 0.0, 2.0);

        auto ActiveStr = ck::IsValid(ActiveTracked) ? "yes" : "(none)";
        auto Body = f"Tracked          {_Guard.Get_NumTrackedTargets()}\n"
            + f"Active target    {ActiveStr}\n\n"
            + "Blue  = guard (chases its target)\n"
            + "Red   = attacker (brighter = more threat)\n"
            + "Yellow line = current aggro";
        CkGym_Common::Update_StationDisplay(ck::ToEntity(this), StationTitle, Body, StationDescription);
    }
}

// ====================================================================================================================
// Station 2 — Line-of-sight cone gates perception (and therefore decay)
// ====================================================================================================================

class UCk_EntityScript_AggroGym_Perception_Station : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn) FTransform InitialTransform = FTransform::Identity;
    UPROPERTY(ExposeOnSpawn) FString StationTitle;
    UPROPERTY(ExposeOnSpawn) FString StationDescription;

    private FCk_Handle_Aggro _Guard;
    private FVector _GuardLoc = FVector::ZeroVector;
    private FCk_Handle_Transform _OrbiterTransform;
    private FCk_Handle _Orbiter;
    private bool _WasInCone = false;
    private float _OrbitAngle = 0.0;

    // Guard faces +X; cone half-angle 35 degrees. cos(35deg) ~= 0.819.
    private float _ConeHalfCos = 0.819;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        _GuardLoc = InitialTransform.Location + FVector(0.0, 0.0, 150.0);

        auto GuardEntity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        GuardEntity.Set_DebugName(n"AggroGym.Perception.Guard");
        utils_transform::Add(GuardEntity, FTransform(FRotator::ZeroRotator, _GuardLoc), ECk_Replication::DoesNotReplicate);

        // Fast decay + heavy unperceived penalty so "out of sight" visibly bleeds threat.
        auto OwnerParams = FCk_Fragment_Aggro_ParamsData();
        auto DefaultTargetParams = FCk_Fragment_AggroTarget_ParamsData();
        auto ThreatParams = FCk_AggroTarget_ThreatParams();
        ThreatParams.Set_InitialThreat(50.0);
        ThreatParams.Set_ThreatDecayRate(3.0);
        ThreatParams.Set_UnperceivedThreatDecayMultiplier(5.0);
        DefaultTargetParams.Set_ThreatParams(ThreatParams);
        auto ForgetParams = FCk_AggroTarget_ForgetParams();
        ForgetParams.Set_LostSightGraceDuration(FCk_Time(0.4));
        ForgetParams.Set_ForgetDuration(FCk_Time(120.0));   // never forget during the demo
        DefaultTargetParams.Set_ForgetParams(ForgetParams);
        OwnerParams.Set_DefaultTargetParams(DefaultTargetParams);
        _Guard = utils_aggro::Add(GuardEntity, OwnerParams);

        _Orbiter = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Orbiter.Set_DebugName(n"AggroGym.Perception.Orbiter");
        _OrbiterTransform = utils_transform::Add(_Orbiter, FTransform(FRotator::ZeroRotator, Get_OrbitLocation()), ECk_Replication::DoesNotReplicate);
        _Guard.CreateTarget(_Orbiter);

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));
        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    private FVector Get_OrbitLocation()
    {
        return _GuardLoc + FVector(Math::Cos(_OrbitAngle) * 500.0, Math::Sin(_OrbitAngle) * 500.0, 0.0);
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        _OrbitAngle += 0.9 * float(InDeltaT.Get_Seconds());
        utils_transform::Request_SetLocation(_OrbiterTransform, FCk_Request_Transform_SetLocation(Get_OrbitLocation()));

        auto OrbiterLoc = utils_transform::Get_EntityCurrentLocation(_OrbiterTransform);
        // Guard faces +X, so dot((1,0,0), dir) == dir.X.
        auto ToOrbiter = (OrbiterLoc - _GuardLoc).GetSafeNormal();
        auto InCone    = ToOrbiter.X >= _ConeHalfCos;

        // Mark perception ONLY on cone-entry/exit — FTag_AggroTarget_Perceived is counted.
        if (InCone && !_WasInCone)
        { _Guard.Request_MarkPerceived_ByTrackedEntity(_Orbiter, FCk_Request_AggroTarget_MarkPerceived()); }
        else if (!InCone && _WasInCone)
        {
            auto Target = _Guard.TryGet_Target_ByTrackedEntity(_Orbiter);
            if (ck::IsValid(Target))
            { Target.Request_MarkUnperceived(); }
        }
        _WasInCone = InCone;

        // Cone edges (35 degrees each side of +X).
        auto Left  = _GuardLoc + FVector(Math::Cos(0.6109) * 900.0,  Math::Sin(0.6109) * 900.0,  0.0);
        auto Right = _GuardLoc + FVector(Math::Cos(-0.6109) * 900.0, Math::Sin(-0.6109) * 900.0, 0.0);
        utils_debug_draw::DrawDebugLine(_GuardLoc, Left,  FLinearColor(0.5, 0.5, 0.5), 0.0, 1.0);
        utils_debug_draw::DrawDebugLine(_GuardLoc, Right, FLinearColor(0.5, 0.5, 0.5), 0.0, 1.0);

        utils_debug_draw::DrawDebugSphere(_GuardLoc, 40.0, 12, FLinearColor(0.2, 0.6, 1.0), 0.0, 2.0);

        auto  Target = _Guard.TryGet_Target_ByTrackedEntity(_Orbiter);
        float Threat = ck::IsValid(Target) ? Target.Get_Threat() : 0.0f;
        auto  OrbiterColor = InCone ? FLinearColor(0.2, 1.0, 0.3) : FLinearColor(0.5, 0.35, 0.35);
        utils_debug_draw::DrawDebugSphere(OrbiterLoc, 55.0, 12, OrbiterColor, 0.0, 2.0);

        auto InSightStr = InCone ? "PERCEIVED" : "lost";
        auto Body = f"In sight         {InSightStr}\n"
            + f"Threat           {int32(Threat)}\n\n"
            + "Green orbiter = perceived (holds threat)\n"
            + "Dim orbiter   = unperceived (decays ~5x)";
        CkGym_Common::Update_StationDisplay(ck::ToEntity(this), StationTitle, Body, StationDescription);
    }
}

// ====================================================================================================================
// Station 3 — Stress: many guards x many dummies
// ====================================================================================================================

class UCk_EntityScript_AggroGym_Stress_Station : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn) FTransform InitialTransform = FTransform::Identity;
    UPROPERTY(ExposeOnSpawn) FString StationTitle;
    UPROPERTY(ExposeOnSpawn) FString StationDescription;

    private int32 _GuardCount = 24;
    private int32 _DummiesPerGuard = 5;

    private TArray<FCk_Handle_Aggro> _Guards;
    private TArray<FVector> _GuardLocs;
    private float _FeedTimer = 0.0;
    private int32 _Seed = 1337;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        auto Origin = InitialTransform.Location + FVector(0.0, 0.0, 100.0);

        for (int32 g = 0; g < _GuardCount; g++)
        {
            int32 Col = g % 6;
            int32 Row = Math::IntegerDivisionTrunc(g, 6);
            auto GuardLoc = Origin + FVector(float(Col) * 220.0, float(Row) * 220.0, 0.0);
            auto GuardEntity = utils_entity_lifetime::Request_CreateEntity(InHandle);
            GuardEntity.Set_DebugName(n"AggroGym.Stress.Guard");
            utils_transform::Add(GuardEntity, FTransform(FRotator::ZeroRotator, GuardLoc), ECk_Replication::DoesNotReplicate);
            auto Guard = utils_aggro::Add(GuardEntity, FCk_Fragment_Aggro_ParamsData());

            for (int32 d = 0; d < _DummiesPerGuard; d++)
            {
                auto Dummy = utils_entity_lifetime::Request_CreateEntity(InHandle);
                Dummy.Set_DebugName(n"AggroGym.Stress.Dummy");
                utils_transform::Add(Dummy, FTransform(FRotator::ZeroRotator, GuardLoc + FVector(float(d) * 40.0, 90.0, 0.0)), ECk_Replication::DoesNotReplicate);
                Guard.CreateTarget(Dummy);
                Guard.Request_AddThreat(FCk_Request_Aggro_AddThreat(Dummy, float(d + 1) * 3.0));
            }

            _Guards.Add(Guard);
            _GuardLocs.Add(GuardLoc);
        }

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));
        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        _FeedTimer += float(InDeltaT.Get_Seconds());

        // Keep churning: every 0.5s nudge a pseudo-random guard's random dummy so selections keep moving.
        if (_FeedTimer >= 0.5)
        {
            _FeedTimer = 0.0;
            _Seed = (_Seed * 1103515245 + 12345) & 0x7fffffff;
            auto Gi = _Seed % _Guards.Num();
            if (ck::IsValid(_Guards[Gi]))
            {
                auto Active = _Guards[Gi].Get_ActiveTarget();
                if (ck::IsValid(Active))
                { Active.Request_AddThreat(8.0); }
            }
        }

        // Draw each guard, greener when it currently holds an active target.
        auto WithActive = 0;
        for (int32 g = 0; g < _Guards.Num(); g++)
        {
            if (ck::Is_NOT_Valid(_Guards[g]))
            { continue; }
            auto HasActive = ck::IsValid(_Guards[g].Get_ActiveTarget());
            if (HasActive) { WithActive++; }
            auto Color = HasActive ? FLinearColor(0.2, 0.9, 0.3) : FLinearColor(0.5, 0.5, 0.5);
            utils_debug_draw::DrawDebugSphere(_GuardLocs[g], 30.0, 8, Color, 0.0, 1.5);
        }

        auto Body = f"Guards           {_Guards.Num()}\n"
            + f"Targets / guard  {_DummiesPerGuard}\n"
            + f"Guards w/ active {WithActive}\n\n"
            + "Green = guard with an active target\n"
            + "Grey  = idle this frame";
        CkGym_Common::Update_StationDisplay(ck::ToEntity(this), StationTitle, Body, StationDescription);
    }
}
