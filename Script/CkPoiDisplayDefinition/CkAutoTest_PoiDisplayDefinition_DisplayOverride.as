// Language=angelscript

//============================================================================
// CK POI DISPLAY DEFINITION — AUTOMATION TEST: per-instance display override
//============================================================================
//
// Tint / SizeHint are authored on Params as a SEED and copied into Current by Add;
// every later change goes through a deferred request. (Icon is immutable post-Add and
// stays Params-only, which is why nothing here overrides it.)
// VERIFIED here:
//   - Get_Tint / Get_SizeHint echo the Params seed immediately after Add.
//   - Request_SetTint mutates Current and broadcasts OnDisplayChanged.
//   - A SetTint + SetSizeHint issued in the SAME frame collapse into exactly ONE
//     broadcast (the drain broadcasts once, not once per request).
//   - Re-asserting the value already in Current broadcasts NOTHING.
//
// The owner is a POI: Add/Create/TryGet take FCk_Handle_Poi, so the owner needs
// the Transform + Poi composition even though nothing here projects.
//============================================================================

class UCk_AutoTest_PoiDisplayDefinition_DisplayOverride : UCk_AutoTest_Base
{
    private FCk_Handle _SelfHandle;
    private FCk_Handle_Poi _Owner;
    private FCk_Handle_PoiDisplayDefinition _Def;

    private int32 _ChangedCount = 0;

    private const FLinearColor _SeedTint = FLinearColor(1.0, 1.0, 1.0, 1.0);
    private const FLinearColor _OverrideTint = FLinearColor(1.0, 0.069870, 0.0, 1.0);
    private const FVector2D _SeedSize = FVector2D(32.0, 32.0);
    private const FVector2D _OverrideSize = FVector2D(64.0, 64.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _SelfHandle = InHandle;

        auto OwnerEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        OwnerEntity.Request_OverrideToSelf();
        utils_transform::Add(OwnerEntity, FTransform(), ECk_Replication::DoesNotReplicate);
        _Owner = utils_poi::Add(OwnerEntity, FCk_Fragment_Poi_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Landmark")));

        auto Params = FCk_Fragment_PoiDisplayDefinition_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Consumer.TestCompass"));
        Params.Set_Tint(_SeedTint);
        Params.Set_SizeHint(_SeedSize);
        _Def = utils_poi_display_definition::Add(_Owner, Params);

        Assert_True(ck::IsValid(_Def), "Add should return a valid PoiDisplayDefinition handle");

        // Add seeds Current synchronously — no settle needed for the seed assertions.
        Assert_True(utils_poi_display_definition::Get_Tint(_Def).Equals(_SeedTint),
            "Get_Tint should echo the Params seed immediately after Add");
        Assert_True(utils_poi_display_definition::Get_SizeHint(_Def).Equals(_SeedSize),
            "Get_SizeHint should echo the Params seed immediately after Add");

        utils_poi_display_definition::BindTo_OnDisplayChanged(_Def,
            FCk_Delegate_PoiDisplayDefinition_DisplayChanged(this, n"OnDisplayChanged"));

        // Two overrides in ONE frame must collapse into ONE broadcast.
        utils_poi_display_definition::Request_SetTint(_Def,
            FCk_Request_PoiDisplayDefinition_SetTint(_OverrideTint));
        utils_poi_display_definition::Request_SetSizeHint(_Def,
            FCk_Request_PoiDisplayDefinition_SetSizeHint(_OverrideSize));

        WaitUntil(n"Predicate_DisplayChanged", n"OnOverrideApplied");
    }

    UFUNCTION()
    private void Predicate_DisplayChanged(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        // Value params are read-only in AS — copy before mutating.
        auto Res = OutResult;
        Res.Set(_ChangedCount > 0);
    }

    UFUNCTION()
    private void OnDisplayChanged(FCk_Handle_PoiDisplayDefinition InDefinition)
    {
        ++_ChangedCount;
    }

    UFUNCTION()
    private void OnOverrideApplied(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto _CkPerfScope = ck::ScopedStat();

        Assert_True(utils_poi_display_definition::Get_Tint(_Def).Equals(_OverrideTint),
            "Request_SetTint should have mutated Current");
        Assert_True(utils_poi_display_definition::Get_SizeHint(_Def).Equals(_OverrideSize),
            "Request_SetSizeHint should have mutated Current");
        Assert_Equals_Int(_ChangedCount, 1,
            "Two overrides drained in one frame should broadcast OnDisplayChanged exactly ONCE");

        // A request that re-asserts the value already in Current must broadcast nothing.
        // Nothing is expected to change, so a frame budget is the only way to observe it.
        utils_poi_display_definition::Request_SetTint(_Def,
            FCk_Request_PoiDisplayDefinition_SetTint(_OverrideTint));
        WaitFrames(4, n"OnNoOpSettled");
    }

    UFUNCTION()
    private void OnNoOpSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto _CkPerfScope = ck::ScopedStat();

        Assert_Equals_Int(_ChangedCount, 1,
            "Re-asserting the tint already in Current should NOT broadcast OnDisplayChanged");

        FinishSuccess();
    }
}
