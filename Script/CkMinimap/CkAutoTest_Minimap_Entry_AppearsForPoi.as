// Language=angelscript

//============================================================================
// CK MINIMAP — AUTOMATION TEST: in-range POI projects into an entry
//============================================================================
//
// A POI 1000uu due East of the observer with ViewExtent 5000 must appear as
// exactly one entry with the frame position derived from the projection math:
//   world delta = (dX=0, dY=+1000), NorthLocked
//   Frame.X = dY / Extent = 1000/5000 = 0.2   (East = screen right)
//   Frame.Y = -dX / Extent = 0.0
// plus Distance ~1000 and EdgeState InsideFrame; OnEntryAppeared fires once.
//
// Isolated Y band: 53100.
//============================================================================

class UCk_AutoTest_Minimap_Entry_AppearsForPoi : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Minimap _Minimap;
    private FCk_Handle_Poi _Poi;
    private FVector _Base = FVector(0.0, 53100.0, 0.0);
    private int32 _AppearedCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _SelfHandle = InHandle;

        auto Observer = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Observer.Request_OverrideToSelf();
        utils_transform::Add(Observer, FTransform(FRotator::ZeroRotator, _Base),
            ECk_Replication::DoesNotReplicate);

        _Minimap = utils_minimap::Add(Observer, FCk_Fragment_Minimap_ParamsData(5000.0));
        _Minimap.BindTo_OnEntryAppeared(
            FCk_Delegate_Minimap_EntryAppeared(this, n"OnEntryAppeared"));

        auto PoiOwner = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        PoiOwner.Request_OverrideToSelf();
        utils_transform::Add(PoiOwner,
            FTransform(FRotator::ZeroRotator, _Base + FVector(0.0, 1000.0, 0.0)),
            ECk_Replication::DoesNotReplicate);
        _Poi = utils_poi::Add(PoiOwner, FCk_Fragment_Poi_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.MinimapAppear")));

        WaitUntil(n"Check_EntryAppeared", n"OnSettled_Requests");
    }

    UFUNCTION()
    private void Check_EntryAppeared(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_AppearedCount >= 1);
    }

    UFUNCTION()
    private void OnEntryAppeared(FCk_Handle_Minimap InMinimap, FCk_Minimap_Entry InEntry)
    {
        _AppearedCount++;
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
        Assert_Equals_Int(Entries.Num(), 1, "The in-range POI should project into exactly one entry");
        Assert_Equals_Int(_AppearedCount, 1, "OnEntryAppeared should fire exactly once");

        if (Entries.Num() == 1)
        {
            auto Entry = Entries[0];
            Assert_True(Entry.Get_Poi() == _Poi, "The entry should reference the created POI");
            Assert_True(Entry.Get_EdgeState() == ECk_Minimap_EntryEdgeState::InsideFrame,
                "A POI well inside the view extent should be InsideFrame");

            auto Pos = Entry.Get_MapPosition();
            Assert_True(Math::Abs(Pos.X - 0.2) < 0.01,
                f"East POI at 1000/5000 should sit at frame X ~0.2 (got {Pos.X})");
            Assert_True(Math::Abs(Pos.Y) < 0.01,
                f"East POI should sit at frame Y ~0 (got {Pos.Y})");
            Assert_True(Math::Abs(Entry.Get_Distance() - 1000.0) < 1.0,
                f"Distance should be ~1000 (got {Entry.Get_Distance()})");
        }

        FinishSuccess();
    }
}
