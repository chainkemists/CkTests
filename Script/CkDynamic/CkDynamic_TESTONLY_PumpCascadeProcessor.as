// Language=angelscript

//============================================================================
// CK DYNAMIC — TEST-ONLY SCRIPT PROCESSOR: pump-cascade consumer
//============================================================================
//
// Fixture for CkAutoTest_ScriptProcessor_PumpDrainsSameFrame. Consumes
// FCk_Fragment_DynamicTest_PumpCascadeMarker: records the consumption frame
// into the entity's PumpCascadeResults, removes the marker, and — while the
// marker carried RemainingCascades > 0 — immediately re-adds a decremented
// marker. Each re-add happens AFTER this processor's tick for the pass, so a
// same-frame drain of the full chain is only possible via the scheduler's
// pump passes observing the dynamic-marker mutation (version bump).
//
// TESTONLY: registered globally like every script processor (the CkDynamic
// host scans all UCk_Processor_Script_Base_UE subclasses), but its query
// requires BOTH test-only fragments, so outside the AutoTest it visits
// nothing.
//
// Mutation-during-iteration note: the ForEach only COLLECTS handles; all
// removes/re-adds run after the iteration completes, so the fixture makes no
// assumptions about the dynamic-storage iterator's tolerance to mutation.
//============================================================================

class UCk_TESTONLY_ScriptProcessor_PumpCascade : UCk_Processor_Script_Base_UE
{
    default _Group = n"FGroup_Gameplay_Script";
    default _MarkedDirtyBy = FCk_Fragment_DynamicTest_PumpCascadeMarker;

    private TArray<FCk_Handle> _Collected;

    UFUNCTION(BlueprintOverride)
    void Tick(FCk_Time DeltaSeconds)
    {
        auto _CkPerfScope = ck::ScopedStat();

        _Collected.Empty();
        _Handle.ForEach_EntityWithTwoFragments(
            FCk_Fragment_DynamicTest_PumpCascadeMarker, FCk_Fragment_DynamicTest_PumpCascadeResults,
            FCk_DynamicFragment_ForEachEntity(this, n"ForEach_Collect"));

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

    UFUNCTION()
    private void ForEach_Collect(FCk_Handle& InHandle)
    {
        _Collected.Add(InHandle);
    }
}
