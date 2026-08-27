// Language=angelscript

//============================================================================
// CK INTENT - AUTOMATION TEST: A LEVEL INTENT IS STILL ON THE TERMINAL
//============================================================================
//
// Arbitration over one terminal has to be a strict total order or it is not
// arbitration, only iteration luck - so two intents sharing a terminal button
// at the SAME priority reject the whole bake. The question a level intent
// raises is whether it is IN that order at all.
//
// It is easy to believe it is not. A level row never enters an episode, never
// defers, and is scanned in a pass of its own AFTER the edge scan, which makes
// "level intents are outside arbitration" a natural thing to assume and a
// cheap thing to implement - group only the edge indices, and the tie check
// stops seeing level rows. The set then compiles, and which of the two moves a
// press produces becomes a function of iteration order, decided per build.
//
// So the terminal grouping is asserted to include level indices, from both
// sides:
//
//   a level and an edge, tied      -> rejected
//   two levels, tied               -> rejected  (grouping, not edge-vs-level)
//   a level and an edge, untied    -> COMPILES  (it was the tie, not the kind)
//
// The third leg is what keeps the first two honest: without it, an
// implementation that rejected every set containing both kinds would pass.
//
// Deliberately ENTITY-FREE, like the sibling notation test: this is pure data
// in, pure verdict out. The bake resolves names against the supplied rows and
// never consults a live button map, so no source, no layer and no PIE state is
// involved in the answer.
//============================================================================

class UCk_AutoTest_Intent_LevelEdgePriorityTieRejected : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FName _ButtonToken = n"TB";

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        DoAssert_LevelTiedWithEdgeRejects();
        DoAssert_TwoLevelsTiedReject();
        DoAssert_DifferentPrioritiesCompile();

        FinishSuccess();
    }

    //------------------------------------------------------------------------

    private void DoAssert_LevelTiedWithEdgeRejects()
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("TB level", n"AS_Tie_Level", 50));
        Definitions.Add(DoParse("TB",       n"AS_Tie_Edge",  50));

        auto Baked = utils_intent_grammar::Bake(Definitions, DoMake_Rows(), 3);

        DoAssert_RejectedAsTie(Baked, n"AS_Tie_Level", n"AS_Tie_Edge",
            "a level and an edge on one button at one priority leave the press ambiguous - the level pass runs separately, but the two intents still answer the same terminal");
    }

    //------------------------------------------------------------------------

    private void DoAssert_TwoLevelsTiedReject()
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("TB level", n"AS_Tie_LevelA", 20));
        Definitions.Add(DoParse("TB level", n"AS_Tie_LevelB", 20));

        auto Baked = utils_intent_grammar::Bake(Definitions, DoMake_Rows(), 3);

        DoAssert_RejectedAsTie(Baked, n"AS_Tie_LevelA", n"AS_Tie_LevelB",
            "two states on one button at one priority is the same undefined answer - which proves the grouping is over TERMINALS, not over the edge candidates that happen to defer");
    }

    //------------------------------------------------------------------------

    private void DoAssert_DifferentPrioritiesCompile()
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("TB level", n"AS_Untied_Level", 10));
        Definitions.Add(DoParse("TB",       n"AS_Untied_Edge",  90));

        auto Baked = utils_intent_grammar::Bake(Definitions, DoMake_Rows(), 3);

        Assert_True(Baked.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the SAME pair at distinct priorities compiles - it was the tie that was rejected, not the two kinds meeting on one button, which they are expected to do");

        Assert_True(Baked.Get_Error() == ECk_Intent_BakeError::None,
            "and an accepted bake carries no reason, because there is nothing to give one for");

        Assert_Equals_Int(Baked.Get_CompiledSet().Get_Intents().Num(), 2,
            "both intents survive into the compiled set - coexistence on one terminal is the ordinary case");
    }

    //------------------------------------------------------------------------

    private void DoAssert_RejectedAsTie(
        const FCk_Intent_BakeResult& InBaked,
        FName InFirstName,
        FName InSecondName,
        const FString& InWhy)
    {
        Assert_True(InBaked.Get_Outcome() == ECk_SucceededFailed::Failed,
            f"the bake must be rejected: {InWhy}");

        Assert_True(InBaked.Get_Error() == ECk_Intent_BakeError::PriorityTieOnSharedTerminal,
            "and rejected for its OWN reason - an author shown a generic failure cannot tell that the fix is a priority edit");

        // Asserted as an unordered PAIR: which of the two is named 'offending' is a function of the
        // order the definitions were handed in, and the contract is that BOTH are named, because the
        // fix is to separate those two and an author shown one cannot tell which pair to look at.
        auto Offending   = InBaked.Get_OffendingIntent();
        auto Conflicting = InBaked.Get_ConflictingIntent();

        Assert_True((Offending == InFirstName  && Conflicting == InSecondName) ||
                    (Offending == InSecondName && Conflicting == InFirstName),
            f"the rejection must name BOTH tied intents (got '{Offending}' and '{Conflicting}')");

        Assert_True(InBaked.Get_OffendingButton().Get_Tier() == ECk_Input_ButtonTier::Physical &&
                    InBaked.Get_OffendingButton().Get_Name() == DoMake_TerminalButton().Get_Name(),
            "and the button they are tied ON, which is the third thing an author needs to find the two rows");

        Assert_Equals_Int(InBaked.Get_CompiledSet().Get_Intents().Num(), 0,
            "a rejected bake leaves nothing partially usable behind - one bad definition invalidates the whole set");
    }

    //------------------------------------------------------------------------

    private FCk_Intent_Definition DoParse(const FString& InNotation, FName InName, int32 InPriority)
    {
        auto Result = utils_intent_grammar::Parse(InNotation, InName, InPriority, FGameplayTag());

        Assert_True(Result.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            f"'{InNotation}' must parse before the bake can mean anything - this test is about the BAKE");

        return Result.Get_Definition();
    }

    private FCk_Input_ButtonId DoMake_TerminalButton()
    {
        return FCk_Input_ButtonId(ECk_Input_ButtonTier::Physical, EKeys::F9.GetKeyName());
    }

    private TArray<FCk_Intent_ButtonNameRow> DoMake_Rows()
    {
        TArray<FCk_Intent_ButtonNameRow> Rows;
        Rows.Add(FCk_Intent_ButtonNameRow(_ButtonToken, DoMake_TerminalButton()));
        return Rows;
    }
}
