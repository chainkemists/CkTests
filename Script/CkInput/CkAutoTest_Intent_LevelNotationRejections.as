// Language=angelscript

//============================================================================
// CK INTENT - AUTOMATION TEST: WHAT `level` MAY AND MAY NOT BE WRITTEN ON
//============================================================================
//
// `level` is a bare trailing modifier like `lenient`, but unlike `lenient` it
// changes what the definition IS rather than how forgivingly it matches. A
// level intent has no completion - it has a state that opens and closes - so
// the notations that would ask for a state AND an edge at once are not
// merely odd, they are unanswerable, and the parser is the only place that
// can say so before a set is baked and shipped.
//
// Three families are rejected, and each names the fact that makes it
// impossible rather than a generic "bad token":
//
//   level + hold      a hold is a threshold measured from an edge; a state
//                     that is simply on has no edge to measure from
//   level + sequence  a sequence is answered by its LAST step, so the state
//                     would have no defined moment to open on
//   level + a terminal that is not one button
//                     the state is "this button is down"; a direction, a
//                     chord or neutral has no such reading
//
// Deliberately ENTITY-FREE, for the reason the sibling parse test gives: this
// is pure data in, pure verdict out. The two ordinary modifier errors are
// asserted too - `level` must be an ordinary member of the trailing-modifier
// grammar, not a special token the tokenizer handles before the rules apply,
// because a special case is exactly where a duplicate or a mis-ordered token
// stops being caught.
//
// The offending TOKEN is asserted alongside every reason, and the three level
// families assert it EMPTY. That is a contract, not an omission: the token
// exists so an authoring tool can underline the text a designer has to fix, and
// these three rules are about the notation as a whole - once `level` and the
// steps contradict each other, blaming one word would point the designer at the
// wrong one. The two ordinary modifier errors name their token, which is what
// makes the empty ones legible as a decision.
//
// The acceptance legs pin the other half: `level` sets the definition's KIND
// and nothing else. A parser that quietly dropped an inert `w=`/`lenient` on
// a level intent, or that forgot to leave `Edge` alone as the default, would
// go red here rather than in whichever matcher test happened to notice.
//============================================================================

class UCk_AutoTest_Intent_LevelNotationRejections : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        DoAssert_LevelAndHoldAreExclusive();
        DoAssert_LevelAndSequenceAreExclusive();
        DoAssert_LevelTerminalMustBeOneButton();
        DoAssert_LevelObeysTheModifierGrammar();
        DoAssert_LevelParsesAndSetsTheKind();

        FinishSuccess();
    }

    //------------------------------------------------------------------------

    private void DoAssert_LevelAndHoldAreExclusive()
    {
        DoAssert_Rejects("IP level hold=60", ECk_Intent_ParseError::LevelWithHold, "",
            "a hold measures frames from a press edge, and a level intent has a state rather than an edge to measure from");

        // Both orderings, because the two tokens are trailing modifiers and the parser sees them in
        // whichever order they were authored - a check written into only one branch passes one of these.
        DoAssert_Rejects("IP hold=60 level", ECk_Intent_ParseError::LevelWithHold, "",
            "the same pair the other way round is the same impossibility, so the rejection cannot depend on which arrived first");
    }

    //------------------------------------------------------------------------

    private void DoAssert_LevelAndSequenceAreExclusive()
    {
        DoAssert_Rejects("236 IP level", ECk_Intent_ParseError::LevelWithSequence, "",
            "a sequence is answered by its last step, so a state written on one has no defined moment to open");

        DoAssert_Rejects("IP IP2 level", ECk_Intent_ParseError::LevelWithSequence, "",
            "a two-button sequence is still a sequence - the rejection is about step COUNT, not about directions");
    }

    //------------------------------------------------------------------------

    private void DoAssert_LevelTerminalMustBeOneButton()
    {
        DoAssert_Rejects("6 level", ECk_Intent_ParseError::LevelTerminalNotSingleButton, "",
            "a direction is a reading of the stick, not a button with a held-union to answer 'still down?' with");

        DoAssert_Rejects("5 level", ECk_Intent_ParseError::LevelTerminalNotSingleButton, "",
            "neutral is the ABSENCE of a direction, so a state that is on while neutral holds is on while nothing is happening");

        DoAssert_Rejects("6+IP level", ECk_Intent_ParseError::LevelTerminalNotSingleButton, "",
            "a chord's direction half can change under a button that never came up, so the pair has no single state to be in");

        DoAssert_Rejects("IP+IS level", ECk_Intent_ParseError::LevelTerminalNotSingleButton, "",
            "two buttons is two states - which one closes it is a question the notation does not answer");
    }

    //------------------------------------------------------------------------

    private void DoAssert_LevelObeysTheModifierGrammar()
    {
        DoAssert_Rejects("IP level level", ECk_Intent_ParseError::DuplicateModifier, "level",
            "`level` is an ordinary trailing modifier, so declaring it twice is caught by the ordinary rule rather than silently absorbed");

        DoAssert_Rejects("IP level 6", ECk_Intent_ParseError::ModifierNotTrailing, "6",
            "modifiers are TRAILING - a step token after `level` is the same error it would be after any other modifier");
    }

    //------------------------------------------------------------------------

    private void DoAssert_LevelParsesAndSetsTheKind()
    {
        auto LevelResult = utils_intent_grammar::Parse("IP level", n"AS_LevelParse_Drag", 0, FGameplayTag());

        Assert_True(LevelResult.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "one button plus the bare modifier is the whole legal shape, so it must parse");

        FCk_Intent_Definition LevelDefinition = LevelResult.Get_Definition();

        Assert_True(LevelDefinition.Get_Kind() == ECk_Intent_Kind::Level,
            "the modifier's ONLY job is to set the kind - a consumer reads this to know a completion will never come");

        Assert_Equals_Int(LevelDefinition.Get_Steps().Num(), 1,
            "a level intent is exactly one step, which is what makes the sequence rejection structural rather than a policy");

        auto EdgeResult = utils_intent_grammar::Parse("IP", n"AS_LevelParse_Tap", 0, FGameplayTag());

        Assert_True(EdgeResult.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the same terminal without the modifier is the ordinary case and must be untouched by any of this");

        Assert_True(EdgeResult.Get_Definition().Get_Kind() == ECk_Intent_Kind::Edge,
            "Edge is the default, so every move authored before `level` existed keeps the kind it always had");

        auto InertResult = utils_intent_grammar::Parse("IP level w=200 lenient", n"AS_LevelParse_Inert", 0, FGameplayTag());

        Assert_True(InertResult.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the modifiers a level intent cannot use are INERT rather than rejected - only the ones that contradict a state are errors");

        Assert_True(InertResult.Get_Definition().Get_Kind() == ECk_Intent_Kind::Level,
            "carrying an inert window does not demote the definition back to an edge");
    }

    //------------------------------------------------------------------------

    // InExpectedToken is the offending token VERBATIM, and "" is a real expectation rather than a
    // "don't care": the token exists so an authoring tool can point at the text to fix, and the
    // three level rules are about the notation as a WHOLE - once `level` and the steps contradict
    // each other there is no honest single token to blame, so blaming one would send a designer to
    // edit the wrong word. The two ordinary modifier errors DO name their token, which is what shows
    // the empty ones are a decision rather than a field nobody filled in.
    private void DoAssert_Rejects(
        const FString& InNotation,
        ECk_Intent_ParseError InExpectedError,
        const FString& InExpectedToken,
        const FString& InWhy)
    {
        auto Result = utils_intent_grammar::Parse(InNotation, n"AS_LevelParse_Rejected", 0, FGameplayTag());

        Assert_True(Result.Get_Outcome() == ECk_SucceededFailed::Failed,
            f"'{InNotation}' must be rejected: {InWhy}");

        Assert_True(Result.Get_Error() == InExpectedError,
            f"'{InNotation}' must be rejected for its OWN reason - a script author who cannot tell which rule fired cannot tell what to fix");

        Assert_Equals_String(Result.Get_ErrorToken(), InExpectedToken,
            f"'{InNotation}' must carry the token an authoring tool would underline");

        Assert_Equals_Int(Result.Get_Definition().Get_Steps().Num(), 0,
            f"'{InNotation}' was rejected, so it must leave nothing partially usable behind");
    }
}
