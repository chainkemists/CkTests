// Language=angelscript

//============================================================================
// CK INTENT - AUTOMATION TEST: THE NOTATION PARSES FROM ANGELSCRIPT
//============================================================================
//
// The notation string IS the authoring surface, and the place moves will be
// authored is script. So the parser is not "a C++ function that AngelScript
// happens to reach" - the AS path is one of the three environments the API
// has to work in, and this test is what says so.
//
// Deliberately ENTITY-FREE. Parsing is pure data: no world, no source, no
// sampler, nothing to settle and nothing to wait for. A test that spun up an
// entity here would be asserting that entity creation works, on the way to
// asserting something that does not involve entities at all.
//
// Three legs, and the third is the one that earns the test:
//
//   "236+LP w=200 lenient"  the canonical motion, whole shape
//   "2 8 LP"                a plain sequence, one atom per step
//   "6+4"                   a REJECTION, with its reason readable from AS
//
// The rejection leg matters because a parser is only usable from a language
// if that language can tell WHY it said no. A surface that returns a valid
// definition or an empty one, with the reason stranded in C++, would let a
// script author ship a typo'd move and never learn which token was wrong.
//============================================================================

class UCk_AutoTest_Intent_NotationParsesInAngelScript : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        DoAssert_CanonicalMotionParses();
        DoAssert_PlainSequenceParses();
        DoAssert_RejectionCarriesItsReason();

        FinishSuccess();
    }

    //------------------------------------------------------------------------

    private void DoAssert_CanonicalMotionParses()
    {
        auto Result = utils_intent_grammar::Parse("236+LP w=200 lenient", n"AS_Hadouken", 10, FGameplayTag());

        Assert_True(Result.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the canonical notation must parse from AngelScript exactly as it does from C++");

        FCk_Intent_Definition Definition = Result.Get_Definition();
        TArray<FCk_Intent_Step> Steps = Definition.Get_Steps();

        Assert_Equals_Int(Steps.Num(), 3,
            "the digit run is a SEQUENCE and the + binds only its last digit, so 236+LP is three steps");

        if (Steps.Num() != 3)
        { return; }

        TArray<FCk_Intent_Atom> FirstAtoms = Steps[0].Get_Atoms();
        TArray<FCk_Intent_Atom> SecondAtoms = Steps[1].Get_Atoms();

        Assert_True(FirstAtoms.Num() == 1 && FirstAtoms[0].Get_Direction() == ECk_Intent_Octant::S,
            "the run's first digit is its own step, reading as the numpad's down");
        Assert_True(SecondAtoms.Num() == 1 && SecondAtoms[0].Get_Direction() == ECk_Intent_Octant::SE,
            "the run's second digit is its own step, reading as the numpad's down-forward");

        auto Terminal = utils_intent_grammar::Get_TerminalStep(Definition);
        TArray<FCk_Intent_Atom> TerminalAtoms = Terminal.Get_Atoms();

        Assert_Equals_Int(TerminalAtoms.Num(), 2,
            "the terminal is the chord the + built: the run's last digit and the button, together");

        if (TerminalAtoms.Num() != 2)
        { return; }

        Assert_True(TerminalAtoms[0].Get_Kind() == ECk_Intent_AtomKind::Direction &&
                    TerminalAtoms[0].Get_Direction() == ECk_Intent_Octant::E,
            "the chord's direction atom is the run's LAST digit, not its first");
        Assert_True(TerminalAtoms[1].Get_Kind() == ECk_Intent_AtomKind::Button &&
                    TerminalAtoms[1].Get_ButtonName() == n"LP",
            "the button atom stays an unresolved NAME - resolving it to a ButtonId is the bake's job");

        Assert_Equals_Int(Definition.Get_WindowFrames(), 200,
            "the window modifier parses to logic frames");
        Assert_True(Definition.Get_Lenience() == ECk_Intent_Lenience::Lenient,
            "the lenient modifier parses to the definition's lenience");
        Assert_True(Definition.Get_Name() == n"AS_Hadouken",
            "the identity is carried through untouched, because it is not part of the notation");
    }

    //------------------------------------------------------------------------

    private void DoAssert_PlainSequenceParses()
    {
        auto Result = utils_intent_grammar::Parse("2 8 LP", n"AS_UpDownPunch", 0, FGameplayTag());

        Assert_True(Result.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "a whitespace-separated sequence must parse");

        FCk_Intent_Definition Definition = Result.Get_Definition();
        TArray<FCk_Intent_Step> Steps = Definition.Get_Steps();

        Assert_Equals_Int(Steps.Num(), 3,
            "whitespace separates steps, so three tokens are three steps");

        if (Steps.Num() != 3)
        { return; }

        TArray<FCk_Intent_Atom> TerminalAtoms = Steps[2].Get_Atoms();

        Assert_True(TerminalAtoms.Num() == 1 && TerminalAtoms[0].Get_ButtonName() == n"LP",
            "a lone button token is a one-atom step, not a chord");
        Assert_Equals_Int(Definition.Get_WindowFrames(), 0,
            "an undeclared window reads as zero, which is unambiguous because a declared zero is rejected");
    }

    //------------------------------------------------------------------------

    private void DoAssert_RejectionCarriesItsReason()
    {
        auto Result = utils_intent_grammar::Parse("6+4", n"AS_ImpossibleChord", 0, FGameplayTag());

        Assert_True(Result.Get_Outcome() == ECk_SucceededFailed::Failed,
            "one stick cannot be in two octants at once, so a two-direction chord must be rejected");
        Assert_True(Result.Get_Error() == ECk_Intent_ParseError::ChordTwoDirections,
            "the reason must be readable from AngelScript, or a script author cannot tell what to fix");

        FCk_Intent_Definition Definition = Result.Get_Definition();
        TArray<FCk_Intent_Step> Steps = Definition.Get_Steps();

        Assert_Equals_Int(Steps.Num(), 0,
            "a rejected notation leaves nothing partially usable behind");
        Assert_Equals_String(Result.Get_ErrorToken(), "6+4",
            "the offending token is carried verbatim so an authoring tool can point at the text");
    }
}
