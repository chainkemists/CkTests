// Language=angelscript

//============================================================================
// CK RESOLVER - AUTOMATION TEST: OPERATIONS LAND ONE PHASE LATER
//============================================================================
//
// CHARACTERIZATION TEST. It pins the resolver's ACTUAL submit-to-visible
// contract, which is not the intuitive one:
//
//   An operation submitted during phase N is NOT reflected in phase N's
//   resolved value. It first appears in phase N+1.
//
// Measured on a 3-phase bundle, seeding BaseValue=100 with the resolution
// request and submitting from the phase-start hook:
//
//   submitted                                  | phase One | Two | Three
//   -------------------------------------------|-----------|-----|------
//   seed 100 -> BaseValue (with the request)    |     0     | 100 | 100
//   +25 -> BonusValue    (at phase Two start)   |           |   0 |  25
//   x1.5 -> TotalMultiplier (at phase Three start) - never observed: it would
//   surface in phase Four, which does not exist.
//
//   observed resolved values: [0] [100] [125]   final: 125
//
// WHY THIS TEST EXISTS RATHER THAN A BUG REPORT
//
// The lag is pre-existing, not a consequence of making the cascade drain in one
// tick. Established by measurement, not inspection: BusterBlock's BasicDamage
// and DamageOverkill assert EXACT damage values end-to-end through the resolver,
// and both were green before the pump fix and after it. The fix changed how long
// the cascade takes, not what it computes.
//
// It is also why a multi-wave applicator is the working production shape:
// BusterBlock's UBb_DamageApplicator runs three resolution WAVES and carries
// Get_FinalValue() forward from each wave's AllPhasesComplete into the next
// wave's seed. Each wave boundary is a hard barrier, so the lag is absorbed
// there and the damage value that reaches the receiver is correct. A consumer
// that collapsed that to a single wave and read its seed back in the first phase
// would silently get 0 - which is exactly the trap this test documents.
//
// WHAT IS NOT ESTABLISHED
//
// The mechanism. The suspicion is that the modifier is applied via a revocable
// float-attribute modifier in ResolveOperations while Calculate reads the
// attribute's final value in the same pass, one recompute behind - but the
// float-attribute processors were not traced far enough to confirm ordering, so
// that is a lead, not a finding. If someone fixes the lag, this test SHOULD go
// red: it is a record of current behaviour, not an endorsement of it. Update the
// expectations and this header together.
//============================================================================

class UCk_AutoTest_Resolver_Cascade_OperationsLandOnePhaseLater : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle_ResolverSource _Source;
    private FCk_Handle_ResolverTarget _Target;
    private bool                      _BundleBound = false;

    private TArray<float32> _ValueAtEachPhaseComplete;
    private float32         _FinalValue = -1.0f;
    private int32           _AllPhasesCompleteCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        Add_Step(          "arrange source + target",            n"Step_Arrange");
        Add_Step(          "initiate a 3-phase resolution",      n"Step_Initiate");
        Add_Step_WaitUntil("the cascade reports all phases",     n"Check_Complete");
        Add_Step(          "assert the one-phase submit lag",    n"Step_AssertLag");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto SourceEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        _Source = utils_resolver_source::Add(
            SourceEntity,
            FCk_Fragment_ResolverSource_ParamsData(autotest_resolver_cascade::Make_ThreePhases()));

        auto TargetEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        _Target = utils_resolver_target::Add(TargetEntity, FCk_Fragment_ResolverTarget_ParamsData());
    }

    UFUNCTION()
    private void Step_Initiate(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Request = utils_resolver_source::Make_InitiateNewResolution(
            autotest_resolver_cascade::BundleName(),
            _Target,
            InHandle,
            FCk_ResolverDataBundle_MetadataOperation_Conditional(),
            autotest_resolver_cascade::Make_Modifier(
                autotest_resolver_cascade::k_SeedBaseValue,
                ECk_ResolverDataBundle_ModifierComponent::BaseValue,
                ECk_ArithmeticOperations_Basic::Add));

        utils_resolver_source::Request_InitiateNewResolution(
            _Source, Request,
            FCk_Delegate_ResolverSource_OnNewResolverDataBundle(this, n"OnNewDataBundle"));
    }

    UFUNCTION()
    private void Check_Complete(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Res = OutResult;
        Res.Set(_AllPhasesCompleteCount > 0);
    }

    UFUNCTION()
    private void Step_AssertLag(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto _CkPerfScope = ck::ScopedStat();

        Assert_Equals_Int(_ValueAtEachPhaseComplete.Num(), 3,
            f"Observed one resolved value per phase - got {_ValueAtEachPhaseComplete.Num()}");

        if (_ValueAtEachPhaseComplete.Num() != 3)
        { return; }

        const auto Seed = autotest_resolver_cascade::k_SeedBaseValue;
        const auto SeedPlusBonus = Seed + autotest_resolver_cascade::k_PhaseTwoBonus;

        // Every message carries the whole observed sequence: the failure that
        // matters is an operation moving between phases, which a single
        // mismatched number cannot distinguish from a wrong total.
        const auto Seq = Get_ObservedSequence();

        Assert_Equals_Float(_ValueAtEachPhaseComplete[0], 0.0f, 0.01f,
            f"Phase One resolves to 0: the request's own seed is submitted DURING phase One and is"
            + f" therefore not visible until phase Two. Observed {Seq}");

        Assert_Equals_Float(_ValueAtEachPhaseComplete[1], Seed, 0.01f,
            f"Phase Two shows the seed submitted one phase earlier, but NOT the bonus submitted at"
            + f" its own phase start. Observed {Seq}");

        Assert_Equals_Float(_ValueAtEachPhaseComplete[2], SeedPlusBonus, 0.01f,
            f"Phase Three shows the bonus submitted at phase Two. Its own multiplier, submitted at"
            + f" phase Three start, would need a phase Four to surface. Observed {Seq}");

        Assert_Equals_Float(_FinalValue, SeedPlusBonus, 0.01f,
            f"AllPhasesComplete carries the last phase's value - the trailing operation submitted in"
            + f" the final phase is silently dropped. Observed {Seq} final {_FinalValue}");
    }

    private FString Get_ObservedSequence() const
    {
        auto Out = FString("");
        for (auto Value : _ValueAtEachPhaseComplete)
        { Out = f"{Out}[{Value}]"; }
        return Out;
    }

    UFUNCTION()
    private void OnNewDataBundle(
        FCk_Handle_ResolverSource InSource,
        FCk_Handle InCauser,
        FCk_Handle_ResolverDataBundle InDataBundle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (_BundleBound)
        { return; }
        _BundleBound = true;

        utils_resolver_data_bundle::BindTo_OnPhaseStart(
            InDataBundle, FCk_Delegate_ResolverDataBundle_OnPhaseStart(this, n"OnPhaseStart"));
        utils_resolver_data_bundle::BindTo_OnPhaseComplete(
            InDataBundle, FCk_Delegate_ResolverDataBundle_OnPhaseComplete(this, n"OnPhaseComplete"));
        utils_resolver_data_bundle::BindTo_OnAllPhasesComplete(
            InDataBundle, FCk_Delegate_ResolverDataBundle_OnAllPhasesComplete(this, n"OnAllPhasesComplete"));
    }

    // Submitting from the phase-start hook is the production shape - it is how
    // BusterBlock's damage receiver injects into the HitPoints phase.
    UFUNCTION()
    private void OnPhaseStart(FCk_Handle_ResolverDataBundle InDataBundle, FGameplayTag InPhase)
    {
        auto _CkPerfScope = ck::ScopedStat();

        if (InPhase == autotest_resolver_cascade::Phase_Two())
        {
            utils_resolver_data_bundle::Request_AddOperation_Modifier(
                InDataBundle,
                ECk_ResolverDataBundle_PhaseSelection::ThisPhase,
                FCk_Request_ResolverDataBundle_ModifierOperation(
                    autotest_resolver_cascade::Make_Modifier(
                        autotest_resolver_cascade::k_PhaseTwoBonus,
                        ECk_ResolverDataBundle_ModifierComponent::BonusValue,
                        ECk_ArithmeticOperations_Basic::Add)));
        }

        if (InPhase == autotest_resolver_cascade::Phase_Three())
        {
            utils_resolver_data_bundle::Request_AddOperation_Modifier(
                InDataBundle,
                ECk_ResolverDataBundle_PhaseSelection::ThisPhase,
                FCk_Request_ResolverDataBundle_ModifierOperation(
                    autotest_resolver_cascade::Make_Modifier(
                        autotest_resolver_cascade::k_PhaseThreeMultiplier,
                        ECk_ResolverDataBundle_ModifierComponent::TotalMultiplier,
                        ECk_ArithmeticOperations_Basic::Multiply)));
        }
    }

    UFUNCTION()
    private void OnPhaseComplete(
        FCk_Handle_ResolverDataBundle InDataBundle,
        FGameplayTag InPhase,
        FCk_Payload_ResolverDataBundle_Resolved InPayload)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _ValueAtEachPhaseComplete.Add(InPayload.Get_FinalValue());
    }

    UFUNCTION()
    private void OnAllPhasesComplete(
        FCk_Handle_ResolverDataBundle InDataBundle,
        FCk_Payload_ResolverDataBundle_Resolved InPayload)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _AllPhasesCompleteCount += 1;
        _FinalValue = InPayload.Get_FinalValue();
    }
}
