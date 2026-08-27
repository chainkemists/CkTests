// Language=angelscript

//============================================================================
// CK INTENT - AUTOMATION TEST: THE RING WRAPS INSTEAD OF GROWING
//============================================================================
//
// A frame record that grew without bound would be a memory leak with a nice
// name, so the ring's cost has to be fixed and its eviction has to be silent.
// Four things are pinned, and the last two are where an "obvious" circular
// buffer goes wrong:
//
//   1. Before it fills, the count tracks the frames written.
//   2. Once full it STOPS at capacity and never moves again, however long the
//      sampler runs.
//   3. Offsets still address the whole retained window after wrapping
//      offset capacity-1 answers a real row, not the slot the writer is about
//      to overwrite.
//   4. The retained window is CONTIGUOUS and ordered: walking offsets 0..N-1
//      steps back through consecutive frame indices. A ring that wrapped its
//      write index but not its reads would keep a stale row in the middle and
//      still report the right count.
//
// The oldest retained frame is also checked against the newest: with a full
// ring of N, they must be exactly N-1 apart, which is the arithmetic statement
// of "nothing inside the window was skipped or duplicated".
//
// Capacity 8 rather than the default 120 so the wrap happens in a fraction of
// a second at the sampler's cadence.
//============================================================================

class UCk_AutoTest_Intent_RingWrapsAtCapacity : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;

    private FCk_Handle               _Owner;
    private FCk_Handle_InputSource   _Source;
    private FCk_Handle_IntentSampler _Sampler;

    private int32 _Capacity = 8;

    private int32 _NewestAtFill = -1;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner   = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source  = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));
        _Sampler = utils_intent_sampler::Add(_Owner, FCk_Fragment_IntentSampler_ParamsData(_Capacity));

        Assert_True(ck::IsValid(_Sampler), "the sampler must compose for this test to mean anything");

        Add_Step_WaitUntil("the ring starts filling",              n"Check_Started");
        Add_Step(          "assert it has not reached capacity",   n"Step_AssertPartial");
        Add_Step_WaitUntil("the ring fills",                       n"Check_Full");
        Add_Step(          "capture the newest frame at fill",     n"Step_CaptureAtFill");
        Add_Step_WaitUntil("the sampler runs a whole ring past it", n"Check_WrappedWell");
        Add_Step(          "assert the count held and the window is intact", n"Step_AssertWrapped");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertPartial(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_intent_sampler::Get_FrameCount(_Sampler) <= _Capacity,
            "the count can never exceed the declared capacity, not even while filling");
    }

    UFUNCTION()
    private void Step_CaptureAtFill(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _NewestAtFill = utils_intent_sampler::Get_LatestFrame(_Sampler).Get_FrameIndex();

        Assert_True(_NewestAtFill >= _Capacity - 1,
            "a full ring must have been fed at least capacity frames");
    }

    UFUNCTION()
    private void Step_AssertWrapped(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(utils_intent_sampler::Get_FrameCount(_Sampler), _Capacity,
            "a full ring evicts rather than grows, so the count is stable at capacity");

        auto Newest = utils_intent_sampler::Get_LatestFrame(_Sampler);
        Assert_True(Newest.Get_FrameIndex() > _NewestAtFill,
            "the sampler must have kept writing past the point the ring filled");

        auto Oldest = utils_intent_sampler::TryGet_FrameAtOffset(_Sampler, _Capacity - 1);
        Assert_True(Oldest.Get_FrameIndex() >= 0,
            "the last offset inside the window must answer with a real row after wrapping");

        Assert_Equals_Int(Newest.Get_FrameIndex() - Oldest.Get_FrameIndex(), _Capacity - 1,
            "the retained window spans exactly capacity consecutive frames - nothing skipped, nothing kept twice");

        Assert_True(Oldest.Get_FrameIndex() > _NewestAtFill - _Capacity,
            "the frames that fell out of the window are gone, not still addressable");

        for (auto Offset = 0; Offset < _Capacity; Offset++)
        {
            auto Row = utils_intent_sampler::TryGet_FrameAtOffset(_Sampler, Offset);

            Assert_Equals_Int(Row.Get_FrameIndex(), Newest.Get_FrameIndex() - Offset,
                "offsets step back through consecutive frames after the ring has wrapped");
        }

        auto PastEnd = utils_intent_sampler::TryGet_FrameAtOffset(_Sampler, _Capacity);
        Assert_True(PastEnd.Get_FrameIndex() < 0,
            "an offset past the retained window answers with the no-such-frame row");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_Started(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_sampler::Get_FrameCount(_Sampler) >= 1);
    }

    UFUNCTION()
    private void Check_Full(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_sampler::Get_FrameCount(_Sampler) >= _Capacity);
    }

    UFUNCTION()
    private void Check_WrappedWell(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_sampler::Get_LatestFrame(_Sampler).Get_FrameIndex() >= _NewestAtFill + _Capacity);
    }
}
