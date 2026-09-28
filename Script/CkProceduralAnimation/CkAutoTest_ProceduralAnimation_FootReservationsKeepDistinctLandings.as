// Language=angelscript

// Actual Jolt contact admission, not a rig separation proxy. Existing trusted anchors may never be slid apart.
class UCk_AutoTest_ProceduralAnimation_FootReservationsKeepDistinctLandings : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 45.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Ledge;
    private FCkProceduralAnimationGym_Fixture _Contention;
    private FCk_Handle_ProceduralGait _ContentionGait;
    private FCk_Handle_Transform _ContentionBody;
    private TArray<FCk_Handle_ProceduralLeg> _ContentionLegs;
    private TArray<FVector> _PreviousPositions;
    private TArray<bool> _PreviousTrustedPlants;
    private TArray<bool> _Captured;
    private float _StartedAt = -1.0;
    private float _Radius = 0.0;
    private int32 _Samples = 0;
    private int32 _LedgeTouchdowns = 0;
    private int32 _NewTrustedPlants = 0;
    private int32 _ReservedViolations = 0;
    private int32 _InvalidFootSamples = 0;
    private float _MinimumNewPlantDistance = 1000000.0;
    private float _MaximumAnchorMovement = 0.0;
    private float _MaximumLedgeX = -1200.0;
    private float _MaximumLedgeZ = 0.0;
    private int32 _DistinctContentionSamples = 0;
    private FString _FirstViolation;
    private FVector _ContentionOrigin = FVector(120000.0, 535000.0, 600.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Roster = TArray<ECkProceduralAnimationGym_Species>();
        Roster.Add(ECkProceduralAnimationGym_Species::Spider);
        if (_Ledge.Create_WithRoster(InHandle, FVector(120000.0, 530000.0, 600.0),
            ECkProceduralAnimationGym_Course::Ledge, Roster, false,
            ECk_ProceduralBodyPose_ConformMode::PlantedFeet, ECkProceduralAnimationGym_HeightSource::Species,
            0.0, FCkProceduralAnimationGym_WallOverride(), true, true) == false ||
            _Contention.Create(InHandle, _ContentionOrigin, ECkProceduralAnimationGym_Course::Flat, false, 1) == false)
        {
            FinishFailure("The landing reservation fixtures could not be created");
            return;
        }
        _Radius = ck_procedural_gym::Get_FootHalfExtents(1.0).Size();
        for (auto Index = 0; Index < 10; Index++)
        {
            _PreviousPositions.Add(FVector::ZeroVector);
            _PreviousTrustedPlants.Add(false);
            _Captured.Add(false);
        }
        Add_Step_WaitUntil("both existing course surfaces are queryable", n"Check_SurfacesReady");
        Add_Step("compose two feet whose original ideal targets contend on the same floor", n"Step_ComposeContention");
        Add_Step_WaitUntil("observe new trusted contacts through the intact ledge approach", n"Check_Observed", 0, 25.0f);
        Add_Step("verify reserved landings and unchanged planted anchors", n"Step_Check");
        Add_Step("retire both fixture subtrees", n"Step_Destroy");
        Add_Step_WaitUntil("all fixture entities and collision are gone", n"Check_Destroyed", 0, 10.0f);
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_SurfacesReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Ledge.Get_AreSurfacesReady() && _Contention.Get_AreSurfacesReady());
    }

    UFUNCTION()
    private void Step_ComposeContention(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // Both hips share an outboard direction and neutral landing. The flat floor has room for the existing search
        // to find distinct contacts; no new obstacle or unreachable layout is needed to manufacture a collision.
        auto Rig = Cast<UCk_ProceduralRig_Data>(NewObject(ck::ProceduralGym_RigSpider, UCk_ProceduralRig_Data));
        if (IsValid(Rig) == false)
        {
            FinishFailure("The per-instance contention rig could not be created");
            return;
        }
        auto Specs = TArray<FCk_ProceduralLeg_Spec>();
        for (auto Index = 0; Index < 2; Index++)
        {
            auto Leg = ck_procedural_gym_assets::MakeLeg(FName(f"Reserved{Index}"),
                FVector(Index == 0 ? -10.0 : 10.0, 30.0, 0.0), FVector(0.0, 100.0, -65.0),
                FVector(0.0, 100.0, 65.0), 0.0f, 2);
            Leg.Set_FootContactRadius(float32(_Radius));
            Specs.Add(Leg);
        }
        Rig.Set_Legs(Specs);
        auto Owner = _Contention.SceneRoot;
        auto Entity = utils_entity_lifetime::Request_CreateEntity(Owner);
        Entity.Request_OverrideToSelf();
        _Contention.Entities.Add(Entity);
        auto Body = utils_transform::Add(Entity, FTransform(_ContentionOrigin + FVector(0.0, 0.0, 65.0)),
            ECk_Replication::DoesNotReplicate);
        _ContentionBody = Body;
        auto Walker = utils_procedural_animation::Add_Walker(Body, Rig, ck::ProceduralGym_Gait,
            TArray<FCk_ProceduralWalker_LegChain>());
        _ContentionGait = Walker.Get_Gait();
        _ContentionLegs = Walker.Get_Legs();
        Assert_True(ck::IsValid(_ContentionGait) && _ContentionLegs.Num() == 2,
            "Two physically reachable same-ideal legs are admitted on the unmodified flat floor");
        Assert_Equals_Float((Specs[0].Get_Placement().Get_RestFootLocal() -
            Specs[1].Get_Placement().Get_RestFootLocal()).Size(), 0.0, 0.001,
            "Precondition: both authored feet contend for exactly the same neutral target");
        for (auto Spec : ck::ProceduralGym_RigSpider.Get_Legs())
        {
            Assert_Equals_Float(Spec.Get_FootContactRadius(), 0.0, 0.0,
                "Per-instance reservation authoring leaves the shared Spider rig asset unchanged");
        }
    }

    private void DoObserve_Feet(TArray<FCk_Handle_ProceduralLeg> InLegs, int32 InOffset, FString InCourse)
    {
        for (auto Index = 0; Index < InLegs.Num(); Index++)
        {
            auto Foot = utils_procedural_leg::Get_Foot(InLegs[Index]);
            if (Foot.Get_Position().ContainsNaN())
            {
                _InvalidFootSamples++;
            }
            auto TrustedPlant = Foot.Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted &&
                Foot.Get_Contact() == ECk_ProceduralLeg_FootContact::Trusted;
            auto Slot = InOffset + Index;
            if (_Captured[Slot] && _PreviousTrustedPlants[Slot] && TrustedPlant)
            {
                _MaximumAnchorMovement = Math::Max(_MaximumAnchorMovement,
                    (Foot.Get_Position() - _PreviousPositions[Slot]).Size());
            }
            auto NewTrustedPlant = TrustedPlant && (_Captured[Slot] == false || _PreviousTrustedPlants[Slot] == false);
            if (NewTrustedPlant)
            {
                _NewTrustedPlants++;
                if (InOffset == 0 && _Captured[Slot])
                {
                    _LedgeTouchdowns++;
                }
                for (auto Peer = 0; Peer < InLegs.Num(); Peer++)
                {
                    if (Peer == Index)
                    {
                        continue;
                    }
                    auto PeerFoot = utils_procedural_leg::Get_Foot(InLegs[Peer]);
                    if (PeerFoot.Get_Phase() != ECk_ProceduralLeg_FootPhase::Planted ||
                        PeerFoot.Get_Contact() != ECk_ProceduralLeg_FootContact::Trusted)
                    {
                        continue;
                    }
                    auto Distance = (Foot.Get_Position() - PeerFoot.Get_Position()).Size();
                    _MinimumNewPlantDistance = Math::Min(_MinimumNewPlantDistance, Distance);
                    if (Distance + 0.05 < 2.0 * _Radius)
                    {
                        _ReservedViolations++;
                        if (_FirstViolation.IsEmpty())
                        {
                            auto Snapshot = UCk_Utils_AutoTest_UE::Get_ProceduralAnimationLegSnapshot(
                                InOffset == 0 ? _Ledge.Crawlers[0].Handles.Root : _ContentionBody,
                                utils_procedural_leg::Get_Id(InLegs[Index]),
                                InOffset == 0 ? _Ledge.Spawn.Origin : _ContentionOrigin);
                            _FirstViolation = f"{InCourse} legs {Index}/{Peer}, distance {Distance :.4} cm, radii {2.0 * _Radius :.4}: {Snapshot}";
                        }
                    }
                }
            }
            _PreviousPositions[Slot] = Foot.Get_Position();
            _PreviousTrustedPlants[Slot] = TrustedPlant;
            _Captured[Slot] = true;
        }
    }

    UFUNCTION()
    private void Check_Observed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Ledge.Update();
        if (_Ledge.CompositionError.IsEmpty() == false)
        {
            FinishFailure(_Ledge.CompositionError);
            return;
        }
        if (ck::Is_NOT_Valid(_ContentionGait) ||
            utils_procedural_gait::Get_Status(_ContentionGait) == ECk_ProceduralAnimation_Status::Failed)
        {
            FinishFailure("The contention gait is invalid or failed");
            return;
        }
        if (_Ledge.Get_AllReady() == false ||
            utils_procedural_gait::Get_Status(_ContentionGait) != ECk_ProceduralAnimation_Status::Ready)
        {
            return;
        }
        auto Now = float(System::GetGameTimeInSeconds());
        if (_StartedAt < 0.0)
        {
            _StartedAt = Now;
        }
        _Samples++;
        DoObserve_Feet(_Ledge.Crawlers[0].Handles.Legs, 0, "Ledge");
        DoObserve_Feet(_ContentionLegs, 8, "same-ideal control");
        auto Body = utils_transform::Get_EntityCurrentTransform(_Ledge.Crawlers[0].Handles.Root).GetLocation() - _Ledge.Spawn.Origin;
        _MaximumLedgeX = Math::Max(_MaximumLedgeX, Body.X);
        _MaximumLedgeZ = Math::Max(_MaximumLedgeZ, Body.Z);
        auto First = utils_procedural_leg::Get_Foot(_ContentionLegs[0]);
        auto Second = utils_procedural_leg::Get_Foot(_ContentionLegs[1]);
        if (First.Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted && Second.Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted &&
            First.Get_Contact() == ECk_ProceduralLeg_FootContact::Trusted && Second.Get_Contact() == ECk_ProceduralLeg_FootContact::Trusted &&
            (First.Get_Position() - Second.Get_Position()).Size() + 0.05 >= 2.0 * _Radius)
        {
            _DistinctContentionSamples++;
        }
        auto Result = OutResult;
        Result.Set(Now - _StartedAt >= 18.0);
    }

    UFUNCTION()
    private void Step_Check(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_Samples > 100 && _NewTrustedPlants >= 10, "Both scenes supplied actual trusted contact samples");
        Assert_True(_LedgeTouchdowns >= 8, f"The intact Ledge supplied at least a leg-count of new trusted touchdown events ({_LedgeTouchdowns})");
        Assert_Equals_Int(_InvalidFootSamples, 0, "Every observed published foot position remains finite");
        Assert_True(utils_procedural_gait::Get_Status(_Ledge.Crawlers[0].Handles.Gait) == ECk_ProceduralAnimation_Status::Ready &&
            utils_procedural_gait::Get_Status(_ContentionGait) == ECk_ProceduralAnimation_Status::Ready,
            "Both actual gaits remain ready throughout the observed contact scenarios");
        Assert_Equals_Int(_ReservedViolations, 0, f"No new trusted plant overlaps another trusted foot's authored contact sphere ({_FirstViolation})");
        Assert_True(_MaximumAnchorMovement <= 0.05, f"Existing trusted planted anchors never slide to solve a reservation ({_MaximumAnchorMovement :.4} cm)");
        Assert_True(_DistinctContentionSamples > 100, f"Same-ideal feet found distinct trusted floor contacts ({_DistinctContentionSamples})");
        Assert_True(_MaximumLedgeX > 600.0 && _MaximumLedgeZ > 180.0,
            f"Reservation admission keeps actual Ledge traversal progress (X {_MaximumLedgeX :.1}, Z {_MaximumLedgeZ :.1})");
        ck::Trace(f"[FootReservations] samples {_Samples}, new trusted plants {_NewTrustedPlants}, Ledge touchdowns {_LedgeTouchdowns}, minimum new plant separation {_MinimumNewPlantDistance :.4} cm, required {2.0 * _Radius :.4}, anchor movement {_MaximumAnchorMovement :.4} cm, contention distinct {_DistinctContentionSamples}");
    }

    UFUNCTION()
    private void Step_Destroy(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Ledge.Request_Destroy();
        _Contention.Request_Destroy();
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Ledge.Get_IsDestroyed() && _Contention.Get_IsDestroyed());
    }
}
