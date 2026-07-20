// Language=angelscript

//============================================================================
// CK POI — AUTOMATION TEST: SetStateTags replaces the whole set
//============================================================================
//
// The composite Request_Poi_SetStateTags (the hydration vehicle) must
// REPLACE the entire state-tag set: previously added tags disappear, the
// new set is exactly what was passed.
//
// Isolated Y band: 53200.
//============================================================================

class UCk_AutoTest_Poi_SetStateTags_ReplacesAll : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle_Poi _Poi;
    private FGameplayTag _TagA;
    private FGameplayTag _TagB;
    private FGameplayTag _TagC;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Owner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        Owner.Request_OverrideToSelf();
        utils_transform::Add(Owner, FTransform(FRotator::ZeroRotator, FVector(0.0, 53200.0, 0.0)),
            ECk_Replication::DoesNotReplicate);

        auto Category = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Area");
        _TagA = utils_gameplay_tag::ResolveGameplayTag(n"Poi.State.Discovered");
        _TagB = utils_gameplay_tag::ResolveGameplayTag(n"Poi.State.Cleared");
        _TagC = utils_gameplay_tag::ResolveGameplayTag(n"Poi.State.Locked");

        _Poi = utils_poi::Add(Owner, FCk_Fragment_Poi_ParamsData(Category));
        _Poi.Request_AddStateTag(FCk_Request_Poi_AddStateTag(_TagA));
        _Poi.Request_AddStateTag(FCk_Request_Poi_AddStateTag(_TagB));

        WaitOneFrame(n"OnSettled_AfterSeeds");
    }

    UFUNCTION()
    private void OnSettled_AfterSeeds(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Tags = utils_poi::Get_StateTags(_Poi);
        Assert_True(Tags.HasTag(_TagA) && Tags.HasTag(_TagB),
            "Both seeded tags should be present before the composite replace");

        auto Replacement = FGameplayTagContainer();
        Replacement.AddTag(_TagC);
        _Poi.Request_SetStateTags(FCk_Request_Poi_SetStateTags(Replacement));

        WaitOneFrame(n"OnSettled_AfterReplace");
    }

    UFUNCTION()
    private void OnSettled_AfterReplace(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Tags = utils_poi::Get_StateTags(_Poi);
        Assert_True(Tags.HasTag(_TagC), "Replacement tag should be present after SetStateTags");
        Assert_True(!Tags.HasTag(_TagA), "SetStateTags must remove previously added tag A");
        Assert_True(!Tags.HasTag(_TagB), "SetStateTags must remove previously added tag B");
        Assert_Equals_Int(Tags.Num(), 1, "State set should contain exactly the replacement tag");

        FinishSuccess();
    }
}
