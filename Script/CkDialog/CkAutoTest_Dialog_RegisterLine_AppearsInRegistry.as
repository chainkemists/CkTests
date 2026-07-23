// Language=angelscript

//============================================================================
// CK DIALOG — AUTOMATION TEST: REGISTER LINE APPEARS IN REGISTRY
//============================================================================
// Register one line at runtime, let deferred creation + EntityTag adds settle,
// then assert it is findable by ID / enter tag and its data round-trips.
//============================================================================

class UCk_AutoTest_Dialog_RegisterLine_AppearsInRegistry : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private FCk_Handle_DialogLine _Line;
    private FGameplayTag _EventTag;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        _EventTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Dialog.Register.Enter");
        auto LinkedEventTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Dialog.Register.Exit");

        auto Registry = UCk_DialogRegistry_Subsystem_UE::Get_DialogRegistry();
        Assert_True(ck::IsValid(Registry), "Dialog registry subsystem must exist in a game/PIE world");

        auto LineData = FCk_DialogBank_LineData(n"AutoTest.Register.Line1", _EventTag);
        LineData.Set_Text(FText::FromString("Hello there"));
        LineData.Set_LinkedEventTag(LinkedEventTag);

        _Line = Registry.Request_RegisterLine(LineData, FGameplayTagContainer());
        Track_ForCleanup(FCk_Handle(_Line));

        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(ck::IsValid(_Line), "Registered line handle should be valid after settle");
        Assert_True(_Line.Get_LineID() == n"AutoTest.Register.Line1", "LineID round-trips");
        Assert_True(_Line.Get_EventTag() == _EventTag, "Enter tag round-trips");
        Assert_True(_Line.Get_HasLinkedEventTag(), "Exit tag is present");
        Assert_True(_Line.Get_NumConditions() == 0, "No conditions on this line");

        auto Registry = UCk_DialogRegistry_Subsystem_UE::Get_DialogRegistry();
        auto Lines = Registry.Get_Lines_ByEventTag(_EventTag);
        Assert_True(Lines.Num() == 1, "Exactly one line registered under the enter tag");

        FinishSuccess();
    }
}
