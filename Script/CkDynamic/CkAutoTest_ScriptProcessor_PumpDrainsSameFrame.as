// Language=angelscript

//============================================================================
// CK DYNAMIC — AUTOMATION TEST: script-processor pump drains same frame
//============================================================================
//
// Pins the contract that a script processor's MarkedDirtyBy work drains via
// the scheduler's PUMP passes within a single frame — the same-frame cascade
// guarantee C++ processors get — rather than slipping one frame per
// generation to successive main passes.
//
// Mechanism under test: dynamic-fragment mutations bump the dirty-marker
// version in the FName-hash domain the script-processor host registers
// (UCk_Utils_DynamicFragment_UE::Get_DirtyMarkerHash), so the scheduler's
// persistent version short-circuit re-evaluates and re-pumps the script node
// within the frame. Before that fix the registered hash was never bumped and
// script processors were pump-deaf: this test's cascade generations would
// record three DIFFERENT frame numbers.
//
// Shape: seed the marker with RemainingCascades = 2 (three generations
// total). The TESTONLY processor consumes a generation per pass and re-adds
// the next one after its tick, so generations 2 and 3 can only drain in the
// seed frame if pump passes fire. Assert all three recorded frames are equal.
//============================================================================

class UCk_AutoTest_ScriptProcessor_PumpDrainsSameFrame : UCk_AutoTest_Base
{
    private FCk_Handle _TestEntity;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _TestEntity = InHandle;

        auto Entity = InHandle;
        Entity.Add_Fragment(FCk_Fragment_DynamicTest_PumpCascadeResults());

        auto& Marker = Entity.AddOrGet_Fragment(FCk_Fragment_DynamicTest_PumpCascadeMarker);
        Marker.RemainingCascades = 2;

        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Entity = _TestEntity;
        auto& Results = Entity.Get_Fragment(FCk_Fragment_DynamicTest_PumpCascadeResults);

        Assert_Equals_Int(Results.ConsumedFrames.Num(), 3,
            "all three cascade generations must have been consumed by settle time");

        if (Results.ConsumedFrames.Num() == 3)
        {
            Assert_True(
                Results.ConsumedFrames[0] == Results.ConsumedFrames[1] &&
                Results.ConsumedFrames[1] == Results.ConsumedFrames[2],
                f"cascade generations must all drain in the SAME frame (via pump passes) — got frames [{Results.ConsumedFrames[0]}, {Results.ConsumedFrames[1]}, {Results.ConsumedFrames[2]}]; differing frames mean the script processor is pump-deaf (dynamic-marker version bumps broken)");
        }

        FinishSuccess();
    }
}
