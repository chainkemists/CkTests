// Language=angelscript

//============================================================================
// CK COMPASS — AUTOMATION TEST: bearing wrap-around at the 0/360 seam
//============================================================================
//
// Manual heading 350; POI at world yaw 10 (offset ~(984.8, 173.6)). Raw
// delta 10 - 350 = -340 must normalize to +20 (shortest signed path), never
// -340 or 340.
//
// Isolated Y band: 56800.
//============================================================================

class UCk_AutoTest_Compass_WrapAround : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Compass _Compass;
    private FCk_Handle_Poi _Poi;
    private FVector _Base = FVector(0.0, 56800.0, 0.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _SelfHandle = InHandle;

        auto Observer = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Observer.Request_OverrideToSelf();
        utils_transform::Add(Observer, FTransform(FRotator::ZeroRotator, _Base),
            ECk_Replication::DoesNotReplicate);

        auto Params = FCk_Compass_Spec(360.0);
        Params.Set_HeadingSource(ECk_Compass_HeadingSource::Manual);
        _Compass = utils_compass::Add(Observer, Params);
        _Compass.Request_SetManualHeading(350.0);

        // World yaw 10 degrees: (cos10, sin10) * 1000 = (984.8, 173.6).
        auto Owner = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Owner.Request_OverrideToSelf();
        utils_transform::Add(Owner,
            FTransform(FRotator::ZeroRotator, _Base + FVector(984.8, 173.6, 0.0)),
            ECk_Replication::DoesNotReplicate);
        _Poi = utils_poi::Add(Owner, FCk_Poi_Spec(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.TestWrap")));

        WaitUntil(n"Check_Projected", n"OnSettled_Projection");
    }

    // Waits on THIS test's own POIs reaching the compass, never on a bare entry
    // count: autotests share one PIE world and a neighbouring band's POIs can
    // occupy the projection while this test's are still pending.
    UFUNCTION()
    private void Check_Projected(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Entries = utils_compass::Get_Entries(_Compass);
        auto Found0 = false;

        for (auto Entry : Entries)
        {
            if (Entry.Get_Poi() == _Poi) { Found0 = true; }
        }

        auto Res = OutResult;
        Res.Set(Found0);
    }

    UFUNCTION()
    private void OnSettled_Projection(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto Entries = utils_compass::Get_Entries(_Compass);
        auto Found = false;
        for (auto Entry : Entries)
        {
            if (Entry.Get_Poi() == _Poi)
            {
                Found = true;
                Assert_True(Math::Abs(Entry.Get_BearingDegrees() - 20.0) < 0.5,
                    f"Heading 350 vs POI at yaw 10 must normalize to +20 (got {Entry.Get_BearingDegrees()})");
            }
        }
        Assert_True(Found, "Wrap-around POI should be on the compass");

        FinishSuccess();
    }
}
