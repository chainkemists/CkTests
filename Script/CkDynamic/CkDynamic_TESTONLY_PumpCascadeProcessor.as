// Language=angelscript

//============================================================================
// CK DYNAMIC — TEST-ONLY SCRIPT PROCESSOR: pump-cascade consumer
//============================================================================
//
// Fixture for CkAutoTest_ScriptProcessor_PumpDrainsSameFrame. Consumes
// FCk_Fragment_DynamicTest_PumpCascadeMarker: records the consumption frame
// into the entity's PumpCascadeResults, removes the marker, and — while the
// marker carried RemainingCascades > 0 — immediately re-adds a decremented
// marker. Each re-add happens AFTER this processor's dispatch for the pass, so
// a same-frame drain of the full chain is only possible via the scheduler's
// pump passes observing the dynamic-marker mutation (version bump).
//
// TESTONLY: registered globally like every script processor (the CkDynamic
// host scans all UCk_Processor_Script_Base_UE subclasses), but its query
// requires BOTH test-only fragments, so outside the AutoTest it visits
// nothing.
//
// DIRECT MODE (Configure + ForEachBatch, no ForEachEntity): the fixture is
// deliberately cross-entity — it collects handles from the batch, then runs
// all removes/re-adds after the collection loop, so it makes no assumptions
// about storage-iterator tolerance to mutation.
//============================================================================

class UCk_TESTONLY_ScriptProcessor_PumpCascade : UCk_Processor_Script_Base_UE
{
    default _Group = n"FGroup_Gameplay_Script";
    default _MarkedDirtyBy = FCk_Fragment_DynamicTest_PumpCascadeMarker;

    private TArray<FCk_Handle> _Collected;

    UFUNCTION(BlueprintOverride)
    void Configure(FCk_ScriptProcessorQuery& Query)
    {
        Query.Require(FCk_Fragment_DynamicTest_PumpCascadeMarker);
        Query.Require(FCk_Fragment_DynamicTest_PumpCascadeResults);
    }

    UFUNCTION(BlueprintOverride)
    void ForEachBatch(FCk_ScriptQueryBatch Batch, FCk_Time InDeltaT)
    {
        auto _CkPerfScope = ck::ScopedStat();

        _Collected.Empty();
        for (int32 i = 0; i < Batch.Num(); ++i)
        {
            _Collected.Add(Batch.GetHandle(i));
        }

        for (int32 Index = 0; Index < _Collected.Num(); ++Index)
        {
            auto Entity = _Collected[Index];

            // Read Remaining BEFORE the remove — the fragment ref dies with the marker.
            auto& Marker = Entity.Get_Fragment(FCk_Fragment_DynamicTest_PumpCascadeMarker);
            const int32 Remaining = Marker.RemainingCascades;

            auto& Results = Entity.Get_Fragment(FCk_Fragment_DynamicTest_PumpCascadeResults);
            Results.ConsumedFrames.Add(utils_stats::Get_FrameCount());

            Entity.Request_TryRemove(FCk_Fragment_DynamicTest_PumpCascadeMarker);

            if (Remaining > 0)
            {
                auto& NextMarker = Entity.AddOrGet_Fragment(FCk_Fragment_DynamicTest_PumpCascadeMarker);
                NextMarker.RemainingCascades = Remaining - 1;
            }
        }
    }
}
