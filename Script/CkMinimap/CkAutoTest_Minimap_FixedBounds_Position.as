// Language=angelscript

//============================================================================
// CK MINIMAP — AUTOMATION TEST: FixedBounds projection position parity
//============================================================================
//
// World-map mode: bounds centered on the band with half-extents (2000, 2000).
// A POI at center + (dX=+1000 North, dY=+500 East) must land at
//   Frame.X = dY / HalfY = 500/2000  = +0.25
//   Frame.Y = -dX / HalfX = -1000/2000 = -0.5
// (per-axis normalize over the bounds, math parity with Get_BoundsToFrame).
//
// Isolated Y band: 53400.
//============================================================================

class UCk_AutoTest_Minimap_FixedBounds_Position : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Minimap _Minimap;
    private FCk_Handle_Poi _Poi;
    private FVector _Base = FVector(0.0, 53400.0, 0.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _SelfHandle = InHandle;

        auto Observer = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Observer.Request_OverrideToSelf();
        utils_transform::Add(Observer, FTransform(FRotator::ZeroRotator, _Base),
            ECk_Replication::DoesNotReplicate);

        auto Params = FCk_Fragment_Minimap_ParamsData(2000.0);
        Params.Set_ProjectionMode(ECk_Minimap_ProjectionMode::FixedBounds);
        Params.Set_FixedBounds(FCk_Minimap_WorldBounds(
            FVector2D(0.0, 53400.0), FVector2D(2000.0, 2000.0)));
        _Minimap = utils_minimap::Add(Observer, Params);

        auto PoiOwner = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        PoiOwner.Request_OverrideToSelf();
        utils_transform::Add(PoiOwner,
            FTransform(FRotator::ZeroRotator, _Base + FVector(1000.0, 500.0, 0.0)),
            ECk_Replication::DoesNotReplicate);
        _Poi = utils_poi::Add(PoiOwner, FCk_Fragment_Poi_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.MinimapFixedBounds")));

        WaitUntil(n"Check_MinimapProjected", n"OnSettled_Requests");
    }

    UFUNCTION()
    private void Check_MinimapProjected(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_minimap::Get_Entries(_Minimap).Num() >= 1);
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
        Assert_Equals_Int(Entries.Num(), 1, "The in-bounds POI should project into exactly one entry");

        if (Entries.Num() == 1)
        {
            auto Pos = Entries[0].Get_MapPosition();
            Assert_True(Math::Abs(Pos.X - 0.25) < 0.01,
                f"POI 500 East over half-extent 2000 should sit at frame X ~0.25 (got {Pos.X})");
            Assert_True(Math::Abs(Pos.Y + 0.5) < 0.01,
                f"POI 1000 North over half-extent 2000 should sit at frame Y ~-0.5 (got {Pos.Y})");
        }

        FinishSuccess();
    }
}
