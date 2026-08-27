// Language=angelscript

//============================================================================
// CK COMPASS - AUTOMATION TEST: bearings at the four cardinal offsets
//============================================================================
//
// Observer at band origin, Manual heading 0. Four POIs placed 1000uu along
// +X / +Y / -X / -Y must project at bearings 0 / +90 / +/-180 / -90 (UE yaw
// convention: +X = yaw 0, +Y = yaw 90).
//
// Isolated Y band: 56400.
//============================================================================

class UCk_AutoTest_Compass_BearingAtCardinalOffsets : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Compass _Compass;
    private FVector _Base = FVector(0.0, 56400.0, 0.0);

    private FGameplayTag _North;
    private FGameplayTag _East;
    private FGameplayTag _South;
    private FGameplayTag _West;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _SelfHandle = InHandle;

        auto Observer = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Observer.Request_OverrideToSelf();
        utils_transform::Add(Observer, FTransform(FRotator::ZeroRotator, _Base),
            ECk_Replication::DoesNotReplicate);

        auto Params = FCk_Fragment_Compass_ParamsData(360.0);
        Params.Set_HeadingSource(ECk_Compass_HeadingSource::Manual);
        _Compass = utils_compass::Add(Observer, Params);
        _Compass.Request_SetManualHeading(0.0);

        _North = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.TestNorth");
        _East  = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.TestEast");
        _South = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.TestSouth");
        _West  = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.TestWest");

        DoSpawnPoi(FVector(1000.0, 0.0, 0.0), _North);
        DoSpawnPoi(FVector(0.0, 1000.0, 0.0), _East);
        DoSpawnPoi(FVector(-1000.0, 0.0, 0.0), _South);
        DoSpawnPoi(FVector(0.0, -1000.0, 0.0), _West);

        WaitUntil(n"Check_Projected", n"OnSettled_Projection");
    }

    private void DoSpawnPoi(FVector InOffset, FGameplayTag InCategory)
    {
        auto Owner = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Owner.Request_OverrideToSelf();
        utils_transform::Add(Owner, FTransform(FRotator::ZeroRotator, _Base + InOffset),
            ECk_Replication::DoesNotReplicate);
        utils_poi::Add(Owner, FCk_Fragment_Poi_ParamsData(InCategory));
    }

    private float DoFindBearing(const TArray<FCk_Compass_Entry>& InEntries, FGameplayTag InCategory, bool& OutFound)
    {
        for (auto Entry : InEntries)
        {
            if (Entry.Get_Category() == InCategory)
            {
                OutFound = true;
                return Entry.Get_BearingDegrees();
            }
        }
        OutFound = false;
        return 0.0;
    }

    // Waits on THIS test's own POIs reaching the compass, never on a bare entry
    // count: autotests share one PIE world and a neighbouring band's POIs can
    // occupy the projection while this test's are still pending.
    UFUNCTION()
    private void Check_Projected(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Entries = utils_compass::Get_Entries(_Compass);
        auto Found0 = false;
        auto Found1 = false;
        auto Found2 = false;
        auto Found3 = false;

        for (auto Entry : Entries)
        {
            if (Entry.Get_Category() == _North) { Found0 = true; }
            if (Entry.Get_Category() == _East) { Found1 = true; }
            if (Entry.Get_Category() == _South) { Found2 = true; }
            if (Entry.Get_Category() == _West) { Found3 = true; }
        }

        auto Res = OutResult;
        Res.Set(Found0
             && Found1
             && Found2
             && Found3);
    }

    UFUNCTION()
    private void OnSettled_Projection(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto Entries = utils_compass::Get_Entries(_Compass);
        Assert_Equals_Int(Entries.Num(), 4, "All four cardinal POIs should be on the compass");

        auto Found = false;

        auto NorthBearing = DoFindBearing(Entries, _North, Found);
        Assert_True(Found, "North (+X) POI should be present");
        Assert_True(Math::Abs(NorthBearing) < 0.5,
            f"+X POI should project at bearing ~0 (got {NorthBearing})");

        auto EastBearing = DoFindBearing(Entries, _East, Found);
        Assert_True(Found, "East (+Y) POI should be present");
        Assert_True(Math::Abs(EastBearing - 90.0) < 0.5,
            f"+Y POI should project at bearing ~+90 (got {EastBearing})");

        auto SouthBearing = DoFindBearing(Entries, _South, Found);
        Assert_True(Found, "South (-X) POI should be present");
        Assert_True(Math::Abs(Math::Abs(SouthBearing) - 180.0) < 0.5,
            f"-X POI should project at bearing ~+/-180 (got {SouthBearing})");

        auto WestBearing = DoFindBearing(Entries, _West, Found);
        Assert_True(Found, "West (-Y) POI should be present");
        Assert_True(Math::Abs(WestBearing + 90.0) < 0.5,
            f"-Y POI should project at bearing ~-90 (got {WestBearing})");

        FinishSuccess();
    }
}
