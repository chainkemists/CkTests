// Language=angelscript

//============================================================================
// CK INPUT - AUTOMATION TEST: THE SUBSYSTEM'S SOURCE IS CREATED ONCE
//============================================================================
//
// `UCk_InputSource_Subsystem` is the only thing that maps a `ULocalPlayer`
// onto an entity, and the Slate writer resolves every real device event
// through it. It deliberately does NOT create the source at `Initialize` - the
// subsystem collection comes up before the engine has handed the local player
// a controller or a world - so creation is re-attempted from
// `PlayerControllerChanged` and LAZILY from `Get_InputSource()` itself.
//
// A lazy creator that is not idempotent is the worst shape this could take: the
// second caller would get a second, empty source, the Slate writer would keep
// feeding the first, and the symptom is "input works for whoever asked first".
// Nothing about the second handle looks wrong - it is valid, it composes, it
// accepts injected events - which is exactly why the equality below is the
// assertion that matters rather than the validity check above it.
//
// This test only READS. Every other test in this battery composes its own
// synthetic source on its own entity precisely so the shared world's real one
// stays untouched; composing onto it here, or injecting into it, would leak
// state into every later test in the session.
//============================================================================

class UCk_AutoTest_Input_SubsystemSourceLazyCreateIdempotent : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private UCk_InputSource_Subsystem _Subsystem;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto PlayerController = Gameplay::GetPlayerController(0);
        if (ck::Is_NOT_Valid(PlayerController))
        {
            FinishFailure("no local PlayerController - the input source belongs to the local player behind one");
            return;
        }

        _Subsystem = UCk_InputSource_Subsystem::Get(PlayerController);
        if (ck::Is_NOT_Valid(_Subsystem))
        {
            FinishFailure("no UCk_InputSource_Subsystem on the local player - it is the only thing that maps one onto an entity");
            return;
        }

        Add_Step_WaitUntil("the subsystem hands out a source", n"Check_SourceExists");
        Add_Step(          "ask a second time and compare",    n"Step_AssertIdempotent");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertIdempotent(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto First = _Subsystem.Get_InputSource();

        Assert_True(ck::IsValid(First),
            "with a local player, a world and a controller all present, the lazy creation has run and answers a real source");

        auto Second = _Subsystem.Get_InputSource();

        Assert_True(ck::IsValid(Second),
            "the second ask answers a real source too");

        Assert_True(Second == First,
            "and it is the SAME source - a lazy creator that minted a second one would leave the Slate writer feeding the first while a later caller held an entity no real event ever reaches");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_SourceExists(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(ck::IsValid(_Subsystem.Get_InputSource()));
    }
}
