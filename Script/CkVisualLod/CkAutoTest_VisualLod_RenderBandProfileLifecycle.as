// Language=angelscript

//============================================================================
// CK VISUAL LOD - AUTOTEST: render-profile bucket lifecycle
//============================================================================
//
// Exercises the public batched profile surface used by CkVisualLod render bands.
// The member index remains the durable identity while its profile bucket changes;
// transform/custom data and visibility must survive outward/inward migration without
// adding another rendered instance. The gym covers camera-distance presentation.
//============================================================================

class UCk_AutoTest_VisualLod_RenderBandProfileLifecycle : UCk_AutoTest_Base
{
    private UCk_IskmAnimCollection_Data _Collection;
    private FCk_Handle_VisualLodArbiter _RuntimeTunerArbiter;
    private int32 _AuthoredNearBudget = 0;
    private FCk_VisualLodArbiter_RuntimeTuners _AuthoredRuntimeTuners;
    private FCk_VisualLodArbiter_RuntimeTuners _AppliedRuntimeTuners;
    private int32 _SetRuntimeTunersCompletionCount = 0;
    private int32 _ResetRuntimeTunersCompletionCount = 0;
    private int32 _MalformedRuntimeTunersCompletionCount = 0;
    private ECk_Request_OperationResult _SetRuntimeTunersResult = ECk_Request_OperationResult::Failed;
    private ECk_Request_OperationResult _ResetRuntimeTunersResult = ECk_Request_OperationResult::Failed;
    private ECk_Request_OperationResult _MalformedRuntimeTunersResult = ECk_Request_OperationResult::Succeeded;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        _Collection = iskm_assets::AnimCollection_Demo();
        auto Full = visual_lod_gym_assets::FullRenderProfile();
        auto Reduced = visual_lod_gym_assets::ReducedRenderProfile();
        auto Culled = visual_lod_gym_assets::CulledRenderProfile();
        if (ck::Is_NOT_Valid(_Collection) || ck::Is_NOT_Valid(Full) ||
            ck::Is_NOT_Valid(Reduced) || ck::Is_NOT_Valid(Culled))
        {
            FinishFailure("required VisualLod render-band fixture asset is invalid");
            return;
        }

        Assert_Equals_Int(UCk_Utils_IskmAnimCollection_UE::Get_BakedSequenceCount(_Collection), 0,
            "the arbiter setup regression must start with an unbaked AnimCollection");

        auto ArbiterOwner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto Config = visual_lod_gym_assets::ArbiterConfig();
        _AuthoredNearBudget = Config.Get_NearBudget();
        _RuntimeTunerArbiter = utils_visual_lod_arbiter::Add(
            ArbiterOwner, FCk_Fragment_VisualLodArbiter_ParamsData(Config));

        Add_Step_WaitUntil("the arbiter seeds its authored runtime tuner snapshot while the collection is unbaked",
            n"Check_RuntimeTunersSeeded");
        Add_Step("create the crowd after cold arbiter setup and exercise profile-bucket migration",
            n"Step_ExerciseCrowdProfileLifecycle");
        Add_Step("request a full nested runtime tuner update through the public deferred API", n"Step_SetRuntimeTuners");
        Add_Step_WaitUntil("the deferred full runtime tuner update completes and reads back", n"Check_RuntimeTunersApplied");
        Add_Step("reset the runtime tuners to authored values", n"Step_ResetRuntimeTuners");
        Add_Step_WaitUntil("the authored nested runtime tuner snapshot is restored", n"Check_RuntimeTunersReset");
        Add_Step("submit one malformed nested runtime tuner candidate", n"Step_SetMalformedRuntimeTuners");
        Add_Step_WaitUntil("the malformed deferred candidate fails without changing the full snapshot", n"Check_MalformedRuntimeTunersRejectedAtomically");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_ExerciseCrowdProfileLifecycle(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // WorldContext is auto-injected by the AngelScript binding. Creating the crowd is the production
        // transition that bakes the collection, so it deliberately follows the cold arbiter setup check.
        auto Crowd = UCk_Utils_IskmBatched_UE::Create_Crowd(_Collection, 1000.0f);
        if (ck::Is_NOT_Valid(Crowd))
        {
            FinishFailure("Create_Crowd failed for the required render-band fixture");
            return;
        }
        Assert_True(UCk_Utils_IskmAnimCollection_UE::Get_BakedSequenceCount(_Collection) > 0,
            "Create_Crowd must bake the AnimCollection after cold arbiter setup");

        auto Full = visual_lod_gym_assets::FullRenderProfile();
        auto Reduced = visual_lod_gym_assets::ReducedRenderProfile();
        auto Culled = visual_lod_gym_assets::CulledRenderProfile();
        TArray<UCk_IskmRenderer_Data> Profiles;
        Profiles.Add(Full);
        Profiles.Add(Reduced);
        Profiles.Add(Culled);
        if (UCk_Utils_IskmBatched_UE::Set_CrowdRenderProfiles(Crowd, Profiles) == false)
        {
            FinishFailure("valid VisualLod render profiles were rejected");
            return;
        }

        // Render profiles are a pre-add contract. Build the tiny crowd only after the complete
        // profile set is accepted, then finalize once so member index is call-order stable.
        for (int32 i = 0; i < 3; ++i)
        {
            auto MemberTransform = FTransform(FRotator::ZeroRotator, FVector(float(i) * 150.0f, 0.0f, 0.0f), FVector::OneVector);
            const int32 AddedIndex = UCk_Utils_IskmBatched_UE::Add_CrowdMember(Crowd, MemberTransform, 0, 1.0f, float(i) * 0.1f);
            if (AddedIndex != i)
            {
                FinishFailure(f"Add_CrowdMember expected index {i}, got {AddedIndex}");
                return;
            }
        }
        UCk_Utils_IskmBatched_UE::Finalize_Crowd(Crowd);

        const int32 MemberIndex = 1;
        const auto ExpectedTransform = UCk_Utils_IskmBatched_UE::Get_CrowdMemberTransform(Crowd, MemberIndex);
        const float ExpectedAnimationTime = UCk_Utils_IskmBatched_UE::Get_CrowdMemberAnimationTime(Crowd, MemberIndex);
        UCk_Utils_IskmBatched_UE::Set_CrowdMemberCustomData(Crowd, MemberIndex, 0.25f, 0.75f);
        const int32 InitialRendered = UCk_Utils_IskmBatched_UE::Get_CrowdRenderedInstanceCount(Crowd);
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdProfileBucketCount(Crowd), 1,
            "initial members should share one full-profile bucket");

        Assert_True(UCk_Utils_IskmBatched_UE::Set_CrowdMemberRenderProfile(Crowd, MemberIndex, 1),
            "outward reduced-band migration should succeed");
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdMemberRenderProfile(Crowd, MemberIndex), 1,
            "outward reduced-band migration should select profile 1");
        Assert_True(UCk_Utils_IskmBatched_UE::Get_CrowdMemberTransform(Crowd, MemberIndex).Equals(ExpectedTransform),
            "reduced-band migration should preserve the member world transform");
        Assert_True(Math::IsNearlyEqual(UCk_Utils_IskmBatched_UE::Get_CrowdMemberCustomDataFloat(Crowd, MemberIndex, 2), 0.25f),
            "reduced-band migration should preserve custom data float 2");
        Assert_True(Math::IsNearlyEqual(
            UCk_Utils_IskmBatched_UE::Get_CrowdMemberAnimationTime(Crowd, MemberIndex), ExpectedAnimationTime),
            "reduced-band migration should preserve animation phase");
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdRenderedInstanceCount(Crowd), InitialRendered,
            "profile migration should not duplicate or remove a visible member");
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdProfileBucketCount(Crowd), 2,
            "mixed full/reduced members should create two profile buckets in one tile");

        Assert_True(UCk_Utils_IskmBatched_UE::Set_CrowdMemberRenderProfile(Crowd, MemberIndex, 2),
            "terminal cull-band migration should succeed");
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdMemberRenderProfile(Crowd, MemberIndex), 2,
            "terminal cull-band migration should select profile 2");
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdRenderedInstanceCount(Crowd), InitialRendered,
            "terminal render profile should keep one logical visible instance, not create a duplicate");
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdProfileBucketCount(Crowd), 3,
            "terminal profile should create a third retained bucket without changing member identity");

        UCk_Utils_IskmBatched_UE::Set_CrowdMemberVisible(Crowd, MemberIndex, false);
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdRenderedInstanceCount(Crowd), InitialRendered - 1,
            "hidden/promoted stand-in lifecycle should remove the far member exactly once");
        Assert_True(UCk_Utils_IskmBatched_UE::Set_CrowdMemberRenderProfile(Crowd, MemberIndex, 1),
            "hidden member profile migration should succeed");
        UCk_Utils_IskmBatched_UE::Set_CrowdMemberVisible(Crowd, MemberIndex, true);
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdMemberRenderProfile(Crowd, MemberIndex), 1,
            "inward return should retain the selected reduced profile while hidden");
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdRenderedInstanceCount(Crowd), InitialRendered,
            "showing the returned member should restore exactly one far instance");

        Assert_True(UCk_Utils_IskmBatched_UE::Set_CrowdMemberRenderProfile(Crowd, MemberIndex, 0),
            "inward full-band migration should succeed");
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdMemberRenderProfile(Crowd, MemberIndex), 0,
            "inward full-band migration should restore profile 0");
        Assert_True(UCk_Utils_IskmBatched_UE::Get_CrowdMemberTransform(Crowd, MemberIndex).Equals(ExpectedTransform),
            "inward profile migration should preserve the original member transform");
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdRenderedInstanceCount(Crowd), InitialRendered,
            "outward/inward migrations should leave no duplicate rendered instances");
    }

    UFUNCTION()
    private void Step_SetRuntimeTuners(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Arbiter = _RuntimeTunerArbiter;
        auto Tuners = Arbiter.Get_RuntimeTuners();

        // This is intentionally a full nested copy, not a partial replacement: the production API is
        // transactional over all tuners, including crowd render-band/profile state.
        auto CrowdTuners = Tuners.Get_CrowdTuners();
        Assert_True(CrowdTuners.Num() > 0, "the runtime arbiter must expose its configured crowd tuner");
        if (CrowdTuners.Num() == 0) { return; }

        auto RenderBands = CrowdTuners[0].Get_RenderBands();
        Assert_True(RenderBands.Num() >= 2, "the configured crowd must expose full and reduced render bands");
        if (RenderBands.Num() < 2) { return; }

        auto ProfileTuners = RenderBands[1].Get_ProfileTuners();
        auto RenderingTuners = ProfileTuners.Get_RenderingInfo();
        RenderingTuners.Set_bCastDynamicShadow(true);
        ProfileTuners.Set_RenderingInfo(RenderingTuners);
        ProfileTuners.Set_FarAnimationUpdateInterval(FCk_Time(0.123));
        ProfileTuners.Set_FreezeFarAnimation(ECk_EnableDisable::Enable);
        RenderBands[1].Set_DistanceThreshold(1750.0f);
        RenderBands[1].Set_ReturnHysteresis(300.0f);
        RenderBands[1].Set_ProfileTuners(ProfileTuners);

        CrowdTuners[0].Set_MoveSpeedThreshold(CrowdTuners[0].Get_MoveSpeedThreshold() + 17.0f);
        CrowdTuners[0].Set_RenderBands(RenderBands);
        Tuners.Set_CrowdTuners(CrowdTuners);
        Tuners.Set_NearBudget(_AuthoredNearBudget - 1);
        Tuners.Set_FadeAnchorLeadFrames(Tuners.Get_FadeAnchorLeadFrames() + 0.25f);
        Tuners.Set_FadeAnchorBakeLagIntervals(Tuners.Get_FadeAnchorBakeLagIntervals() + 0.25f);

        Assert_True(Arbiter.Get_AreRuntimeTunersValid(Tuners),
            "the complete nested runtime tuner candidate must be publicly valid before it is enqueued");
        _AppliedRuntimeTuners = Tuners;
        Arbiter.Request_SetRuntimeTuners(
            FCk_Request_VisualLodArbiter_SetRuntimeTuners(Tuners),
            FCk_Delegate_Request_OnCompleted(this, n"OnSetRuntimeTunersCompleted"));
    }

    UFUNCTION()
    private void Step_ResetRuntimeTuners(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Arbiter = _RuntimeTunerArbiter;
        Arbiter.Request_ResetRuntimeTuners(
            FCk_Request_VisualLodArbiter_ResetRuntimeTuners(),
            FCk_Delegate_Request_OnCompleted(this, n"OnResetRuntimeTunersCompleted"));
    }

    UFUNCTION()
    private void Step_SetMalformedRuntimeTuners(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Arbiter = _RuntimeTunerArbiter;
        auto Malformed = _AuthoredRuntimeTuners;
        auto CrowdTuners = Malformed.Get_CrowdTuners();
        Assert_True(CrowdTuners.Num() > 0, "the malformed-candidate leg must retain the configured crowd tuner");
        if (CrowdTuners.Num() == 0) { return; }

        auto RenderBands = CrowdTuners[0].Get_RenderBands();
        Assert_True(RenderBands.Num() >= 2, "the malformed-candidate leg needs two ordered render bands");
        if (RenderBands.Num() < 2) { return; }

        // Make the second outward boundary equal to the first. This is malformed independently of
        // any ensure path, and the public validity query below is the test's decision boundary.
        RenderBands[1].Set_DistanceThreshold(RenderBands[0].Get_DistanceThreshold());
        CrowdTuners[0].Set_RenderBands(RenderBands);
        Malformed.Set_CrowdTuners(CrowdTuners);

        Assert_True(Arbiter.Get_AreRuntimeTunersValid(Malformed) == false,
            "the public full runtime-tuner validator must reject unordered nested render-band thresholds");
        Assert_True(Get_AreRuntimeTunerSnapshotsEquivalent(Arbiter.Get_RuntimeTuners(), _AuthoredRuntimeTuners),
            "the pre-enqueue malformed candidate must not mutate the authored runtime snapshot");
        Arbiter.Request_SetRuntimeTuners(
            FCk_Request_VisualLodArbiter_SetRuntimeTuners(Malformed),
            FCk_Delegate_Request_OnCompleted(this, n"OnMalformedRuntimeTunersCompleted"));
    }

    UFUNCTION()
    private void Check_RuntimeTunersSeeded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        if (ck::Is_NOT_Valid(_RuntimeTunerArbiter))
        {
            Result.Set(false);
            return;
        }

        auto Arbiter = _RuntimeTunerArbiter;
        _AuthoredRuntimeTuners = Arbiter.Get_RuntimeTuners();
        Result.Set(_AuthoredRuntimeTuners.Get_NearBudget() == _AuthoredNearBudget
            && Arbiter.Get_AreRuntimeTunersValid(_AuthoredRuntimeTuners)
            && UCk_Utils_IskmAnimCollection_UE::Get_BakedSequenceCount(_Collection) == 0);
    }

    UFUNCTION()
    private void Check_RuntimeTunersApplied(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        auto Arbiter = _RuntimeTunerArbiter;
        Result.Set(ck::IsValid(Arbiter)
            && _SetRuntimeTunersCompletionCount == 1
            && _SetRuntimeTunersResult == ECk_Request_OperationResult::Succeeded
            && Get_AreRuntimeTunerSnapshotsEquivalent(Arbiter.Get_RuntimeTuners(), _AppliedRuntimeTuners));
    }

    UFUNCTION()
    private void Check_RuntimeTunersReset(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        auto Arbiter = _RuntimeTunerArbiter;
        Result.Set(ck::IsValid(Arbiter)
            && _ResetRuntimeTunersCompletionCount == 1
            && _ResetRuntimeTunersResult == ECk_Request_OperationResult::Succeeded
            && Get_AreRuntimeTunerSnapshotsEquivalent(Arbiter.Get_RuntimeTuners(), _AuthoredRuntimeTuners));
    }

    UFUNCTION()
    private void Check_MalformedRuntimeTunersRejectedAtomically(
        FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        auto Arbiter = _RuntimeTunerArbiter;
        Result.Set(ck::IsValid(Arbiter)
            && _MalformedRuntimeTunersCompletionCount == 1
            && _MalformedRuntimeTunersResult == ECk_Request_OperationResult::Failed
            && Get_AreRuntimeTunerSnapshotsEquivalent(Arbiter.Get_RuntimeTuners(), _AuthoredRuntimeTuners));
    }

    UFUNCTION()
    private void OnSetRuntimeTunersCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _SetRuntimeTunersCompletionCount += 1;
        _SetRuntimeTunersResult = InResult;
        Assert_True(InRequestOwner == FCk_Handle(_RuntimeTunerArbiter),
            "the valid tuner request completion must identify the runtime arbiter owner");
    }

    UFUNCTION()
    private void OnResetRuntimeTunersCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _ResetRuntimeTunersCompletionCount += 1;
        _ResetRuntimeTunersResult = InResult;
        Assert_True(InRequestOwner == FCk_Handle(_RuntimeTunerArbiter),
            "the reset tuner request completion must identify the runtime arbiter owner");
    }

    UFUNCTION()
    private void OnMalformedRuntimeTunersCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _MalformedRuntimeTunersCompletionCount += 1;
        _MalformedRuntimeTunersResult = InResult;
        Assert_True(InRequestOwner == FCk_Handle(_RuntimeTunerArbiter),
            "the malformed tuner request completion must identify the runtime arbiter owner");
    }

    private bool Get_AreRuntimeTunerSnapshotsEquivalent(
        const FCk_VisualLodArbiter_RuntimeTuners &in A,
        const FCk_VisualLodArbiter_RuntimeTuners &in B)
    {
        if (A.Get_PromoteDistance() != B.Get_PromoteDistance()
            || A.Get_DemoteDistance() != B.Get_DemoteDistance()
            || A.Get_NearBudget() != B.Get_NearBudget()
            || A.Get_LockBudget() != B.Get_LockBudget()
            || A.Get_LockPromoteMaxDistance() != B.Get_LockPromoteMaxDistance()
            || A.Get_ExhaustionPolicy() != B.Get_ExhaustionPolicy()
            || A.Get_ViewConeMarginDeg() != B.Get_ViewConeMarginDeg()
            || A.Get_AlwaysInViewDistance() != B.Get_AlwaysInViewDistance()
            || A.Get_PreemptDistanceMargin() != B.Get_PreemptDistanceMargin()
            || A.Get_MaxPreemptsPerTick() != B.Get_MaxPreemptsPerTick()
            || A.Get_FadeDuration().Get_Seconds() != B.Get_FadeDuration().Get_Seconds()
            || A.Get_FadeAnchorLeadFrames() != B.Get_FadeAnchorLeadFrames()
            || A.Get_FadeAnchorBakeLagIntervals() != B.Get_FadeAnchorBakeLagIntervals())
        { return false; }

        const auto CrowdA = A.Get_CrowdTuners();
        const auto CrowdB = B.Get_CrowdTuners();
        if (CrowdA.Num() != CrowdB.Num()) { return false; }
        for (int32 CrowdIndex = 0; CrowdIndex < CrowdA.Num(); ++CrowdIndex)
        {
            if (CrowdA[CrowdIndex].Get_IdleSequenceIndex() != CrowdB[CrowdIndex].Get_IdleSequenceIndex()
                || CrowdA[CrowdIndex].Get_MoveSequenceIndex() != CrowdB[CrowdIndex].Get_MoveSequenceIndex()
                || CrowdA[CrowdIndex].Get_MoveSpeedThreshold() != CrowdB[CrowdIndex].Get_MoveSpeedThreshold()
                || CrowdA[CrowdIndex].Get_MoveAuthoredSpeed() != CrowdB[CrowdIndex].Get_MoveAuthoredSpeed()
                || CrowdA[CrowdIndex].Get_MoveRateClamp().Get_Min()
                    != CrowdB[CrowdIndex].Get_MoveRateClamp().Get_Min()
                || CrowdA[CrowdIndex].Get_MoveRateClamp().Get_Max()
                    != CrowdB[CrowdIndex].Get_MoveRateClamp().Get_Max())
            { return false; }

            const auto BandsA = CrowdA[CrowdIndex].Get_RenderBands();
            const auto BandsB = CrowdB[CrowdIndex].Get_RenderBands();
            if (BandsA.Num() != BandsB.Num()) { return false; }
            for (int32 BandIndex = 0; BandIndex < BandsA.Num(); ++BandIndex)
            {
                const auto ProfileA = BandsA[BandIndex].Get_ProfileTuners();
                const auto ProfileB = BandsB[BandIndex].Get_ProfileTuners();
                const auto RenderingA = ProfileA.Get_RenderingInfo();
                const auto RenderingB = ProfileB.Get_RenderingInfo();
                if (BandsA[BandIndex].Get_DistanceThreshold() != BandsB[BandIndex].Get_DistanceThreshold()
                    || BandsA[BandIndex].Get_ReturnHysteresis() != BandsB[BandIndex].Get_ReturnHysteresis()
                    || RenderingA.Get_bCastDynamicShadow() != RenderingB.Get_bCastDynamicShadow()
                    || RenderingA.Get_bRenderInMainPass() != RenderingB.Get_bRenderInMainPass()
                    || RenderingA.Get_bRenderInDepthPass() != RenderingB.Get_bRenderInDepthPass()
                    || RenderingA.Get_bReceivesDecals() != RenderingB.Get_bReceivesDecals()
                    || RenderingA.Get_bUseAsOccluder() != RenderingB.Get_bUseAsOccluder()
                    || RenderingA.Get_bRenderCustomDepth() != RenderingB.Get_bRenderCustomDepth()
                    || RenderingA.Get_bCastContactShadow() != RenderingB.Get_bCastContactShadow()
                    || RenderingA.Get_bAffectDynamicIndirectLighting() != RenderingB.Get_bAffectDynamicIndirectLighting()
                    || RenderingA.Get_bAffectDistanceFieldLighting() != RenderingB.Get_bAffectDistanceFieldLighting()
                    || RenderingA.Get_bVisibleInRayTracing() != RenderingB.Get_bVisibleInRayTracing()
                    || RenderingA.Get_bOutputVelocity() != RenderingB.Get_bOutputVelocity()
                    || ProfileA.Get_MinDrawDistance() != ProfileB.Get_MinDrawDistance()
                    || ProfileA.Get_MaxDrawDistance() != ProfileB.Get_MaxDrawDistance()
                    || ProfileA.Get_MinLOD() != ProfileB.Get_MinLOD()
                    || ProfileA.Get_BoundsScale() != ProfileB.Get_BoundsScale()
                    || ProfileA.Get_LightingChannels().bChannel0 != ProfileB.Get_LightingChannels().bChannel0
                    || ProfileA.Get_LightingChannels().bChannel1 != ProfileB.Get_LightingChannels().bChannel1
                    || ProfileA.Get_LightingChannels().bChannel2 != ProfileB.Get_LightingChannels().bChannel2
                    || ProfileA.Get_FarAnimationUpdateInterval().Get_Seconds()
                        != ProfileB.Get_FarAnimationUpdateInterval().Get_Seconds()
                    || ProfileA.Get_FreezeFarAnimation() != ProfileB.Get_FreezeFarAnimation())
                { return false; }
            }
        }
        return true;
    }
}

class ACk_AutoTest_VisualLod_RenderBandProfileLifecycle_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_VisualLod_RenderBandProfileLifecycle;
    default _TimeoutSeconds = 8.0f;

    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("rejected invalid runtime tuners atomically");
        return Out;
    }
}
