// Language=angelscript

//============================================================================
// CK INTENT — AUTOMATION TEST: A WHOLE CHARACTER'S MOVE LIST, BAKED AT ONCE
//============================================================================
//
// The grammar's other tests prove one notation, one bake, two moves. This one
// proves the thing a shipping character actually asks for: forty moves — every
// shape the notation can express — parsed one at a time and compiled into ONE
// set, with nothing hand-assembled anywhere. The vocabulary lives in
// `CkIntent_Moves_Assets.as` as notation STRINGS and nothing else, so the only
// thing this test can be reading is what the parser and the bake made of them.
//
// Entity-free, like its two grammar siblings, and for the same reason: parse
// and bake are pure functions over values, so a test that spun up a world here
// would be asserting that entity creation works on the way to asserting
// something that never touches an entity.
//
// Four things are asserted, and the last one is what makes the scale mean
// something:
//
//   parse   every authored row parses, and a rejection names the MOVE, its
//           notation and the reason — a red here points at one string
//   bake    forty definitions over a declared button vocabulary compile as one
//           set, and a rejection names the offending move and button
//   count   the compiled set carries every authored move; a bake is atomic, so
//           a short count is a silently dropped special
//   verdict three deferral verdicts read straight off the artifact, one per
//           law: a shared terminal costs nothing, a hold sibling costs its
//           threshold, a chord partner costs the set's window
//
// The verdicts are the point. Every table in a set is derived from every
// intent in it, so the tie check, the ordering and the deferrals are all
// functions of the WHOLE forty — and a two-move fixture cannot tell a rule
// that holds from one that merely has not been contradicted yet.
//============================================================================

class UCk_AutoTest_Intent_FortyMoveBake : UCk_AutoTest_Base
{
    // Not the signature's default 3, so reading it back off the set — and off
    // the chord verdict — proves both carried the argument the bake was given.
    private int32 _ChordWindowFrames = 4;

    private TArray<FCk_Intent_Definition> _Definitions;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        DoAssert_EveryAuthoredRowParses();
        DoAssert_WholeVocabularyBakes();

        FinishSuccess();
    }

    //------------------------------------------------------------------------

    private void DoAssert_EveryAuthoredRowParses()
    {
        TArray<FCkTests_Intent_MoveRow> Rows = intent_moves::MoveTable_FortyMove.Rows;

        Assert_Equals_Int(Rows.Num(), intent_moves::k_MoveCount,
            "the move table must declare the whole vocabulary — a table that lost rows would make every count below vacuous");

        for (auto Index = 0; Index < Rows.Num(); Index++)
        {
            _Definitions.Add(DoParse_Row(Rows[Index]));
        }

        Assert_Equals_Int(_Definitions.Num(), Rows.Num(),
            "one definition per authored row, so a rejection cannot quietly shorten what the bake is handed");
    }

    //------------------------------------------------------------------------

    private void DoAssert_WholeVocabularyBakes()
    {
        auto Result = utils_intent_grammar::Bake(_Definitions, DoMake_ButtonRows(), _ChordWindowFrames);

        auto Error = Result.Get_Error();
        auto OffendingMove = Result.Get_OffendingIntent();
        auto ConflictingMove = Result.Get_ConflictingIntent();
        auto OffendingButton = Result.Get_OffendingButtonName();

        Assert_True(Result.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            f"forty well-formed moves over a declared vocabulary must compile as ONE set — rejected as {Error :n}, naming move '{OffendingMove}', rival '{ConflictingMove}', button '{OffendingButton}'");

        FCk_Intent_CompiledSet Set = Result.Get_CompiledSet();

        Assert_Equals_Int(Set.Get_Intents().Num(), _Definitions.Num(),
            "every authored move must survive into the set — the bake is atomic, so a short count is a special that would go missing in a fight");
        Assert_Equals_Int(Set.Get_ChordWindowFrames(), _ChordWindowFrames,
            "the set must carry the chord window it was baked with, not the signature's default");

        DoAssert_SharedTerminalNeverDefers(Set);
        DoAssert_HoldSiblingDefers(Set);
        DoAssert_ChordMemberDefers(Set);
    }

    //------------------------------------------------------------------------
    // The three laws, read off the artifact
    //------------------------------------------------------------------------

    // LP is the suffix zone: six moves end on it and not one of them can be
    // waited out. This is the property the whole deferral model exists to
    // protect, and at forty moves it is worth rather more than at two — the
    // prefix either already happened or it did not, however many rivals share
    // the button.
    private void DoAssert_SharedTerminalNeverDefers(const FCk_Intent_CompiledSet& InSet)
    {
        auto Row = utils_intent_grammar::TryGet_ResolutionRow(InSet, DoMake_Button(n"LP"));
        TArray<int32> Candidates = Row.Get_IntentIndices();

        Assert_True(Candidates.Num() >= 2,
            "several moves must resolve off LP, or its zero verdict says nothing about SHARING a terminal");

        auto Verdict = utils_intent_grammar::Get_DeferralVerdict(InSet, DoMake_Button(n"LP"));

        Assert_Equals_Int(Verdict.Get_HoldSiblingFrames(), 0,
            "no move ending on LP declares a hold, so a press of it waits on no threshold");
        Assert_Equals_Int(Verdict.Get_ChordMemberFrames(), 0,
            "sharing a terminal is answered by what is already BEHIND the press, so a crowded button still resolves on its press frame");

        DoAssert_RowOrderedByDominance(InSet, Candidates, "LP");
    }

    // HP is the charge zone: a tap and a hold on one button are the first of
    // the two ambiguities that genuinely reach forward.
    private void DoAssert_HoldSiblingDefers(const FCk_Intent_CompiledSet& InSet)
    {
        auto Row = utils_intent_grammar::TryGet_ResolutionRow(InSet, DoMake_Button(n"HP"));
        TArray<int32> Candidates = Row.Get_IntentIndices();

        Assert_True(Candidates.Num() >= 2,
            "a hold defers only against a RIVAL, so HP must carry more than one candidate for the verdict to be earned");

        auto Verdict = utils_intent_grammar::Get_DeferralVerdict(InSet, DoMake_Button(n"HP"));

        Assert_Equals_Int(Verdict.Get_HoldSiblingFrames(), intent_moves::k_ChargeHoldFrames,
            "a tap and a charge share HP, so a press cannot be told apart until the longest declared hold has passed");
        Assert_Equals_Int(Verdict.Get_ChordMemberFrames(), 0,
            "no move ending on HP needs a second BUTTON, so there is never a partner press in flight");

        DoAssert_RowOrderedByDominance(InSet, Candidates, "HP");
    }

    // HK is the chord zone: the second forward ambiguity, and the one that
    // reads the set's own window back rather than a per-move number.
    private void DoAssert_ChordMemberDefers(const FCk_Intent_CompiledSet& InSet)
    {
        auto Row = utils_intent_grammar::TryGet_ResolutionRow(InSet, DoMake_Button(n"HK"));
        TArray<int32> Candidates = Row.Get_IntentIndices();

        Assert_True(Candidates.Num() >= 2,
            "a chord member defers only against a RIVAL, so HK must carry the bare move alongside the chord");

        auto Verdict = utils_intent_grammar::Get_DeferralVerdict(InSet, DoMake_Button(n"HK"));

        Assert_Equals_Int(Verdict.Get_ChordMemberFrames(), _ChordWindowFrames,
            "HK ends a two-button chord and a bare move, so a lone press waits out the set's chord window for its partner");
        Assert_Equals_Int(Verdict.Get_HoldSiblingFrames(), 0,
            "neither move ending on HK declares a hold, so nothing waits on a threshold");

        DoAssert_RowOrderedByDominance(InSet, Candidates, "HK");
    }

    //------------------------------------------------------------------------

    // The tie check runs before the sort, so at forty moves a row that is not
    // strictly descending is either a tie that slipped through or an ordering
    // that depends on iteration accident.
    private void DoAssert_RowOrderedByDominance(
        const FCk_Intent_CompiledSet& InSet,
        const TArray<int32>& InCandidates,
        const FString& InTerminalLabel)
    {
        TArray<FCk_Intent_CompiledIntent> Intents = InSet.Get_Intents();

        for (auto Index = 1; Index < InCandidates.Num(); Index++)
        {
            auto Dominant = Intents[InCandidates[Index - 1]].Get_Priority();
            auto Lesser = Intents[InCandidates[Index]].Get_Priority();

            Assert_True(Dominant > Lesser,
                f"terminal '{InTerminalLabel}' resolves most-dominant first, so priorities down the row must strictly descend (at index {Index}: {Dominant} then {Lesser})");
        }
    }

    //------------------------------------------------------------------------

    private FCk_Intent_Definition DoParse_Row(const FCkTests_Intent_MoveRow& InRow)
    {
        auto Result = utils_intent_grammar::Parse(InRow._Notation, InRow._Name, InRow._Priority, FGameplayTag());

        auto MoveName = InRow._Name;
        auto Notation = InRow._Notation;
        auto Error = Result.Get_Error();
        auto Token = Result.Get_ErrorToken();

        Assert_True(Result.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            f"move '{MoveName}' ({Notation}) must parse — rejected as {Error :n} on token '{Token}'");

        return Result.Get_Definition();
    }

    private FCk_Input_ButtonId DoMake_Button(FName InName)
    {
        return FCk_Input_ButtonId(ECk_Input_ButtonTier::Mapped, InName);
    }

    // Rows the test makes up on the spot, straight from the table's own button
    // vocabulary. The bake takes values and no live ButtonMap, which is what
    // lets a cook step and a validation tool call it exactly this way.
    private TArray<FCk_Intent_ButtonNameRow> DoMake_ButtonRows()
    {
        TArray<FName> Names = intent_moves::MoveTable_FortyMove.ButtonNames;
        TArray<FCk_Intent_ButtonNameRow> Rows;

        Assert_True(Names.Num() >= 1,
            "the table must declare the button vocabulary, or every move naming one is a bake rejection");

        for (auto Index = 0; Index < Names.Num(); Index++)
        {
            Rows.Add(FCk_Intent_ButtonNameRow(Names[Index], DoMake_Button(Names[Index])));
        }

        return Rows;
    }
}
