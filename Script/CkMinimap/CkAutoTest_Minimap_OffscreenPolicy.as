// Language=angelscript

//============================================================================
// CK MINIMAP — AUTOMATION TEST: offscreen policy — Hide vs ClampToEdge
//============================================================================
//
// ViewExtent 1000 (Rectangle frame). Two POIs sit 3000uu out (outside the
// frame):
//   - Hide policy       -> absent from the entries entirely
//   - ClampToEdge (due North, dX=+3000) -> raw frame (0, -3), rect clamp
//     divides by max(|x|,|y|)=3 -> pinned at (0, -1) with ClampedToEdge
//
// Isolated Y band: 53300.
//============================================================================

class UCk_AutoTest_Minimap_OffscreenPolicy : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Minimap _Minimap;
    private FCk_Handle_Poi _HiddenPoi;
    private FCk_Handle_Poi _ClampedPoi;
    private FVector _Base = FVector(0.0, 53300.0, 0.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _SelfHandle = InHandle;

        auto Observer = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Observer.Request_OverrideToSelf();
        utils_transform::Add(Observer, FTransform(FRotator::ZeroRotator, _Base),
            ECk_Replication::DoesNotReplicate);

        _Minimap = utils_minimap::Add(Observer, FCk_Minimap_Spec(1000.0));

        // Due East, Hide policy — must not appear at all.
        _HiddenPoi = DoSpawnPoi(FVector(0.0, 3000.0, 0.0), n"Poi.Category.MinimapHide",
            ECk_Poi_OffscreenPolicy::Hide);
        // Due North, ClampToEdge — must pin to the frame rim at (0, -1).
        _ClampedPoi = DoSpawnPoi(FVector(3000.0, 0.0, 0.0), n"Poi.Category.MinimapClamp",
            ECk_Poi_OffscreenPolicy::ClampToEdge);

        WaitUntil(n"Check_MinimapProjected", n"OnSettled_Requests");
    }

    // Names THIS test's own POI rather than counting entries: autotests share one
    // PIE world, so a neighbouring band's POIs can occupy the projection while
    // this test's are still pending (see CkCompass wave 21).
    UFUNCTION()
    private void Check_MinimapProjected(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Entries = utils_minimap::Get_Entries(_Minimap);
        auto Found = false;

        for (auto Entry : Entries)
        {
            if (Entry.Get_Poi() == _ClampedPoi) { Found = true; }
        }

        auto Res = OutResult;
        Res.Set(Found);
    }

    private FCk_Handle_Poi DoSpawnPoi(FVector InOffset, FName InCategoryName, ECk_Poi_OffscreenPolicy InPolicy)
    {
        auto Owner = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Owner.Request_OverrideToSelf();
        utils_transform::Add(Owner, FTransform(FRotator::ZeroRotator, _Base + InOffset),
            ECk_Replication::DoesNotReplicate);

        auto Poi = utils_poi::Add(Owner, FCk_Poi_Spec(
            utils_gameplay_tag::ResolveGameplayTag(InCategoryName)));

        // Offscreen policy now lives in CkPoiDisplayDefinition, keyed by the minimap consumer.
        auto DisplayParams = FCk_PoiDisplayDefinition_Spec(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Consumer.Minimap"));
        DisplayParams.Set_OffscreenPolicy(InPolicy);
        utils_poi_display_definition::Add(Poi, DisplayParams);

        return Poi;
    }

    UFUNCTION()
    private void OnSettled_Requests(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        WaitOneFrame(n"OnSettled_Projection");
    }

    UFUNCTION()
    private void OnSettled_Projection(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Entries = utils_minimap::Get_Entries(_Minimap);
        Assert_Equals_Int(Entries.Num(), 1, "Hide policy should exclude; ClampToEdge should keep — 1 entry");

        if (Entries.Num() == 1)
        {
            auto Entry = Entries[0];
            Assert_True(Entry.Get_Poi() == _ClampedPoi, "The surviving entry should be the clamped POI");
            Assert_True(Entry.Get_EdgeState() == ECk_Minimap_EntryEdgeState::ClampedToEdge,
                "An out-of-frame ClampToEdge POI should report ClampedToEdge");

            auto Pos = Entry.Get_MapPosition();
            Assert_True(Math::Abs(Pos.X) < 0.01,
                f"North POI should clamp at frame X ~0 (got {Pos.X})");
            Assert_True(Math::Abs(Pos.Y + 1.0) < 0.01,
                f"North POI should clamp at frame Y ~-1 (got {Pos.Y})");
        }

        FinishSuccess();
    }
}
