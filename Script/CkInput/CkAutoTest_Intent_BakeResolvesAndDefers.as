// Language=angelscript

//============================================================================
// CK INTENT - AUTOMATION TEST: THE BAKE IS REACHABLE FROM ANGELSCRIPT
//============================================================================
//
// Notation is authored in script, so the step that turns authored notation
// into something a character can actually use has to be reachable from there
// too. A bake that only C++ could call would make script a place moves are
// written and never a place they are validated.
//
// Entity-free, like its notation sibling - and that is the property under
// test as much as anything else. The button vocabulary arrives as ROWS the
// script makes up on the spot, not as a live ButtonMap, so there is no world,
// no input source and nothing to spin up before a set can be compiled. A cook
// step and a validation tool get to call it exactly this way.
//
// Two legs:
//
//   accept   two moves sharing terminal LP, one of them a hold -> the set
//            compiles, the resolution row is ordered by dominance, and LP
//            carries the hold deferral the ambiguity earns
//   reject   a move naming a button no row maps -> the whole set refuses,
//            and the reason names BOTH the move and the button
//
// The rejection leg is the one that matters for script specifically: an
// authoring path that cannot read back WHICH move and WHICH token was wrong
// is an authoring path that ships typos.
//============================================================================

class UCk_AutoTest_Intent_BakeResolvesAndDefers : UCk_AutoTest_Base
{
    // Not 3, so reading it back proves the set carried the argument rather
    // than the default the signature declares.
    private int32 _ChordWindowFrames = 4;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        DoAssert_SetCompilesAndDefers();
        DoAssert_UnknownButtonRejectsWithBothNames();

        FinishSuccess();
    }

    //------------------------------------------------------------------------

    private void DoAssert_SetCompilesAndDefers()
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("236+LP", n"AS_Special", 100));
        Definitions.Add(DoParse("LP hold=30", n"AS_HoldPunch", 50));

        auto Result = utils_intent_grammar::Bake(Definitions, DoMake_ButtonRows(), _ChordWindowFrames);

        Assert_True(Result.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "a set of well-formed moves over declared buttons must compile from AngelScript");

        FCk_Intent_CompiledSet Set = Result.Get_CompiledSet();

        Assert_Equals_Int(Set.Get_Intents().Num(), 2,
            "both moves must survive into the compiled set");
        Assert_Equals_Int(Set.Get_ChordWindowFrames(), _ChordWindowFrames,
            "the set must carry the chord window it was baked with, not the signature's default");

        auto Row = utils_intent_grammar::TryGet_ResolutionRow(Set, DoMake_Button(n"LP"));
        TArray<int32> Candidates = Row.Get_IntentIndices();

        Assert_Equals_Int(Candidates.Num(), 2,
            "a press of LP can complete either move, so both belong in its resolution row");

        if (Candidates.Num() != 2)
        { return; }

        TArray<FCk_Intent_CompiledIntent> Intents = Set.Get_Intents();

        Assert_True(Intents[Candidates[0]].Get_Name() == n"AS_Special",
            "the resolution row is ordered by descending priority, so the dominant move comes first");
        Assert_True(Intents[Candidates[1]].Get_Name() == n"AS_HoldPunch",
            "the less dominant move comes second");

        auto Verdict = utils_intent_grammar::Get_DeferralVerdict(Set, DoMake_Button(n"LP"));

        Assert_Equals_Int(Verdict.Get_HoldSiblingFrames(), 30,
            "a tap and a hold on one button cannot be told apart until the hold threshold has passed");
        Assert_Equals_Int(Verdict.Get_ChordMemberFrames(), 0,
            "neither move needs a second button press, so nothing waits on the chord window");

        auto Unheard = utils_intent_grammar::Get_DeferralVerdict(Set, DoMake_Button(n"Unheard"));

        Assert_Equals_Int(Unheard.Get_HoldSiblingFrames(), 0,
            "a button the set never heard of gets the same answer as one whose ambiguities were checked and absent");
    }

    //------------------------------------------------------------------------

    private void DoAssert_UnknownButtonRejectsWithBothNames()
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("236+LP", n"AS_Special", 100));
        Definitions.Add(DoParse("623+HP", n"AS_Undeclared", 50));

        auto Result = utils_intent_grammar::Bake(Definitions, DoMake_ButtonRows(), _ChordWindowFrames);

        Assert_True(Result.Get_Outcome() == ECk_SucceededFailed::Failed,
            "a move naming a button no row maps must be caught at bake, never left as a runtime surprise");
        Assert_True(Result.Get_Error() == ECk_Intent_BakeError::UnknownButtonName,
            "the reason must be readable from AngelScript");
        Assert_True(Result.Get_OffendingIntent() == n"AS_Undeclared",
            "the rejection must name the move that used the button");
        Assert_True(Result.Get_OffendingButtonName() == n"HP",
            "the rejection must name the button that did not resolve");

        FCk_Intent_CompiledSet Set = Result.Get_CompiledSet();

        Assert_Equals_Int(Set.Get_Intents().Num(), 0,
            "the well-formed move alongside it must NOT compile either - a set is valid whole or not at all");
    }

    //------------------------------------------------------------------------

    private FCk_Intent_Definition DoParse(const FString& InNotation, FName InName, int32 InPriority)
    {
        auto Result = utils_intent_grammar::Parse(InNotation, InName, InPriority, FGameplayTag());

        Assert_True(Result.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture notation must parse before the bake can mean anything");

        return Result.Get_Definition();
    }

    private FCk_Input_ButtonId DoMake_Button(FName InName)
    {
        return FCk_Input_ButtonId(ECk_Input_ButtonTier::Mapped, InName);
    }

    private TArray<FCk_Intent_ButtonNameRow> DoMake_ButtonRows()
    {
        TArray<FCk_Intent_ButtonNameRow> Rows;
        Rows.Add(FCk_Intent_ButtonNameRow(n"LP", DoMake_Button(n"LP")));
        Rows.Add(FCk_Intent_ButtonNameRow(n"MP", DoMake_Button(n"MP")));
        return Rows;
    }
}
