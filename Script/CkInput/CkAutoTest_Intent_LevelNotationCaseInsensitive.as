// Language=angelscript

//============================================================================
// CK INTENT — AUTOMATION TEST: `level` IS SPELLED HOWEVER THE DESIGNER TYPED IT
//============================================================================
//
// Every other token in the grammar compares case-insensitively — `w=`, `hold=`
// and `lenient` all do, and button names compare as FName does. `level` is not
// allowed to be the exception, and the reason is what happens when it is:
// nothing visible.
//
// A designer who writes `IP LEVEL` in a move table does not get a parse error.
// `LEVEL` is a legal BUTTON token ([A-Za-z0-9_]), so a case-sensitive parser
// reads the notation as a two-step SEQUENCE — press IP, then press the button
// called LEVEL — which bakes, activates, and simply never fires, because no
// button named LEVEL exists on the terminal. The move is silently absent from
// the game and every readiness gate reports healthy.
//
// So the assertion is not merely "it parses" but WHAT it parses to: one step,
// kind Level. A two-step Edge definition is precisely the wrong answer this
// exists to catch, and "Succeeded" alone cannot tell them apart.
//
// The constraint checks are asserted through the same spelling, because the
// case-fold has to happen where the token is CLASSIFIED, not at some later
// comparison — a parser that recognised `LEVEL` as a modifier but compared the
// stored kind case-sensitively afterwards would accept `IP LEVEL hold=60`, the
// one combination that has no meaning at all.
//
// Deliberately ENTITY-FREE, like its sibling rejection test: pure data in,
// pure verdict out.
//============================================================================

class UCk_AutoTest_Intent_LevelNotationCaseInsensitive : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        DoAssert_EverySpellingIsTheSameModifier();
        DoAssert_TheConstraintsFollowTheSpelling();

        FinishSuccess();
    }

    //------------------------------------------------------------------------

    private void DoAssert_EverySpellingIsTheSameModifier()
    {
        DoAssert_ParsesAsLevel("IP level",
            "the canonical spelling, and the baseline the other two are being held to");

        DoAssert_ParsesAsLevel("IP Level",
            "title case is what an authoring tool or a tidy-minded designer produces, and it must mean the same thing");

        DoAssert_ParsesAsLevel("IP LEVEL",
            "upper case is the dangerous one: LEVEL is a legal BUTTON token, so a case-sensitive parser reads a two-step SEQUENCE that bakes, activates and never fires");
    }

    //------------------------------------------------------------------------

    private void DoAssert_TheConstraintsFollowTheSpelling()
    {
        DoAssert_Rejects("IP LEVEL hold=60", ECk_Intent_ParseError::LevelWithHold,
            "the case-fold has to happen where the token is CLASSIFIED — a parser that recognised the modifier but compared the kind case-sensitively afterwards would accept the one pairing that cannot mean anything");

        DoAssert_Rejects("6 LEVEL", ECk_Intent_ParseError::LevelTerminalNotSingleButton,
            "and the terminal constraint applies through the same spelling, rather than the token quietly becoming a second step on a direction");

        DoAssert_Rejects("IP Level LEVEL", ECk_Intent_ParseError::DuplicateModifier,
            "two spellings of one modifier is still the modifier twice — a case-sensitive duplicate check would absorb the second one silently");
    }

    //------------------------------------------------------------------------

    private void DoAssert_ParsesAsLevel(const FString& InNotation, const FString& InWhy)
    {
        auto Result = utils_intent_grammar::Parse(InNotation, n"AS_LevelCase_Drag", 0, FGameplayTag());

        Assert_True(Result.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            f"'{InNotation}' must parse: {InWhy}");

        auto Definition = Result.Get_Definition();

        Assert_True(Definition.Get_Kind() == ECk_Intent_Kind::Level,
            f"'{InNotation}' must be a LEVEL definition — 'Succeeded' on its own is also what the wrong reading produces");

        Assert_Equals_Int(Definition.Get_Steps().Num(), 1,
            f"'{InNotation}' is ONE step, and the step count is the reading that separates a modifier from a second button token");
    }

    //------------------------------------------------------------------------

    private void DoAssert_Rejects(const FString& InNotation, ECk_Intent_ParseError InExpectedError, const FString& InWhy)
    {
        auto Result = utils_intent_grammar::Parse(InNotation, n"AS_LevelCase_Rejected", 0, FGameplayTag());

        Assert_True(Result.Get_Outcome() == ECk_SucceededFailed::Failed,
            f"'{InNotation}' must be rejected: {InWhy}");

        Assert_True(Result.Get_Error() == InExpectedError,
            f"'{InNotation}' must be rejected for its OWN reason — a rejection under the wrong rule is the case-fold landing in the wrong place");

        Assert_Equals_Int(Result.Get_Definition().Get_Steps().Num(), 0,
            f"'{InNotation}' was rejected, so it must leave nothing partially usable behind");
    }
}
