// Language=angelscript

//============================================================================
// CK COMPASS — AUTOMATION TEST: MaxEntries truncates by priority
//============================================================================
//
// MaxEntries 3 with five in-arc POIs of priorities 1..5: exactly the three
// highest-priority POIs (5, 4, 3) survive truncation.
//
// Isolated Y band: 58800.
//============================================================================

class UCk_AutoTest_Compass_MaxEntries_PriorityTruncation : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Compass _Compass;
    private FVector _Base = FVector(0.0, 58800.0, 0.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _SelfHandle = InHandle;

        auto Observer = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Observer.Request_OverrideToSelf();
        utils_transform::Add(Observer, FTransform(FRotator::ZeroRotator, _Base),
            ECk_Replication::DoesNotReplicate);

        auto Params = FCk_Fragment_Compass_ParamsData();
        Params.Set_HeadingSource(ECk_Compass_HeadingSource::Manual);
        Params.Set_MaxEntries(3);
        _Compass = utils_compass::Add(Observer, Params);
        _Compass.Request_SetManualHeading(0.0);

        // Five POIs fanned across the forward arc, priorities 1..5.
        for (int32 i = 1; i <= 5; i++)
        {
            auto Owner = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
            Owner.Request_OverrideToSelf();
            utils_transform::Add(Owner,
                FTransform(FRotator::ZeroRotator, _Base + FVector(1000.0, float(i - 3) * 100.0, 0.0)),
                ECk_Replication::DoesNotReplicate);

            utils_poi::Add(Owner, FCk_Fragment_Poi_ParamsData(
                utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.TestPriority")));

            // Priority now lives in CkPoiDisplayDefinition, keyed by the compass consumer.
            auto DisplayParams = FCk_Fragment_PoiDisplayDefinition_ParamsData(
                utils_gameplay_tag::ResolveGameplayTag(n"Poi.Consumer.Compass"));
            DisplayParams.Set_Priority(i);
            utils_poi_display_definition::Add(Owner, DisplayParams);
        }

        WaitOneFrame(n"OnSettled_Requests");
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

        auto Entries = utils_compass::Get_Entries(_Compass);
        Assert_Equals_Int(Entries.Num(), 3, "MaxEntries 3 should truncate five POIs to three");

        auto MinPriority = 999;
        for (auto Entry : Entries)
        {
            if (Entry.Get_Priority() < MinPriority)
            { MinPriority = Entry.Get_Priority(); }
        }
        Assert_Equals_Int(MinPriority, 3,
            "Truncation must keep the highest priorities (5,4,3) — lowest surviving priority should be 3");

        FinishSuccess();
    }
}
