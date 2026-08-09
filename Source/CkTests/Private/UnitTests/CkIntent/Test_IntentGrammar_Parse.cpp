#include "CkCore/Macros/CkMacros.h"

#include "CkIntent/CkIntentGrammar_Utils.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
// Pins the compact notation grammar (CkIntentGrammar_Utils.h) — the ONE parser every authoring path enters.
//
//   1. The canonical example parses to the documented shape: a digit run is a SEQUENCE and a `+` binds to its
//      LAST digit, so "236+LP" is three steps ending in a chord rather than one four-atom step.
//   2. The numpad-to-octant table, all nine digits, asserted through Parse itself so the mapping cannot drift
//      away from the entry point that uses it. Zero is not a direction and rejects.
//   3. Canonical motions round-trip: the shoryuken run, a whitespace-separated sequence, a hold-modified chord.
//   4. Modifiers are order-free and TRAILING — a step after a modifier is a rejection, not a re-ordering.
//   5. Whitespace is noise: leading, trailing, doubled and tabbed all parse to the same definition.
//   6. Every malformed-input class rejects with its OWN reason, carries no partial definition, and names the
//      offending token.
//
// Hermetic: the grammar is pure data and free functions — no world, no registry, no entity, so these run as
// plain value assertions with no fixture at all.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_intent_grammar
{
    constexpr auto kGrammarTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;

    // ----------------------------------------------------------------------------------------------------------------

    auto
    DoParse(
        const TCHAR* InNotation) -> FCk_Intent_ParseResult
    {
        return UCk_Utils_IntentGrammar_UE::Parse(InNotation, FName{TEXT("Test_Intent")}, 0, FGameplayTag{});
    }

    auto
    DoAssert_DirectionStep(
        FAutomationTestBase& InTest,
        const FCk_Intent_Step& InStep,
        ECk_Intent_Octant InExpected,
        const FString& InWhat) -> void
    {
        InTest.TestEqual(InWhat + TEXT(" is a lone atom"), InStep.Get_Atoms().Num(), 1);

        if (InStep.Get_Atoms().Num() != 1)
        { return; }

        InTest.TestTrue(InWhat + TEXT(" is a direction"),
            InStep.Get_Atoms()[0].Get_Kind() == ECk_Intent_AtomKind::Direction);
        InTest.TestTrue(InWhat + TEXT(" names the expected octant"),
            InStep.Get_Atoms()[0].Get_Direction() == InExpected);
    }

    auto
    DoAssert_ButtonStep(
        FAutomationTestBase& InTest,
        const FCk_Intent_Step& InStep,
        FName InExpected,
        const FString& InWhat) -> void
    {
        InTest.TestEqual(InWhat + TEXT(" is a lone atom"), InStep.Get_Atoms().Num(), 1);

        if (InStep.Get_Atoms().Num() != 1)
        { return; }

        InTest.TestTrue(InWhat + TEXT(" is a button"),
            InStep.Get_Atoms()[0].Get_Kind() == ECk_Intent_AtomKind::Button);
        InTest.TestTrue(InWhat + TEXT(" names the expected button"),
            InStep.Get_Atoms()[0].Get_ButtonName() == InExpected);
    }

    // A chord's atoms keep the order they were WRITTEN in, which is why this asserts positionally rather than
    // searching: a parser free to reorder would make two notations that read differently compare identical.
    auto
    DoAssert_DirectionButtonChord(
        FAutomationTestBase& InTest,
        const FCk_Intent_Step& InStep,
        ECk_Intent_Octant InExpectedDirection,
        FName InExpectedButton,
        const FString& InWhat) -> void
    {
        InTest.TestTrue(InWhat + TEXT(" reads as a chord"), InStep.Get_IsChord());
        InTest.TestEqual(InWhat + TEXT(" holds two atoms"), InStep.Get_Atoms().Num(), 2);

        if (InStep.Get_Atoms().Num() != 2)
        { return; }

        InTest.TestTrue(InWhat + TEXT(" leads with the direction"),
            InStep.Get_Atoms()[0].Get_Kind() == ECk_Intent_AtomKind::Direction);
        InTest.TestTrue(InWhat + TEXT(" names the expected octant"),
            InStep.Get_Atoms()[0].Get_Direction() == InExpectedDirection);
        InTest.TestTrue(InWhat + TEXT(" carries the button second"),
            InStep.Get_Atoms()[1].Get_Kind() == ECk_Intent_AtomKind::Button);
        InTest.TestTrue(InWhat + TEXT(" names the expected button"),
            InStep.Get_Atoms()[1].Get_ButtonName() == InExpectedButton);
    }

    auto
    DoAssert_Rejects(
        FAutomationTestBase& InTest,
        const TCHAR* InNotation,
        ECk_Intent_ParseError InExpected) -> void
    {
        const auto Result = DoParse(InNotation);
        const auto What = FString::Printf(TEXT("[%s]"), InNotation);

        InTest.TestTrue(What + TEXT(" is rejected"),
            Result.Get_Outcome() == ECk_SucceededFailed::Failed);
        InTest.TestTrue(What + TEXT(" rejects for its own reason"),
            Result.Get_Error() == InExpected);

        // Atomic, like every other declaration in this codebase: a rejected notation leaves nothing usable behind,
        // so no caller can act on the half of a move that happened to parse.
        InTest.TestTrue(What + TEXT(" carries no partial definition"),
            Result.Get_Definition().Get_IsEmpty());
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_IntentGrammar_CanonicalNotationParsesToDocumentedShape,
    "Ck.Intent.Grammar.CanonicalNotationParsesToDocumentedShape",
    ck_test_intent_grammar::kGrammarTestFlags)

bool FCkTest_IntentGrammar_CanonicalNotationParsesToDocumentedShape::RunTest(const FString& Parameters)
{
    using namespace ck_test_intent_grammar;

    const auto Result = UCk_Utils_IntentGrammar_UE::Parse(
        TEXT("236+LP w=200 lenient"), FName{TEXT("Hadouken")}, 10, FGameplayTag{});

    if (NOT TestTrue(TEXT("the canonical notation parses"), Result.Get_IsSucceeded()))
    { return false; }

    const auto& Definition = Result.Get_Definition();

    // THE binding rule: the run is a sequence and the `+` reaches only its last digit. Four atoms in one step
    // would mean the player had to hit down, down-forward, forward and LP simultaneously.
    TestEqual(TEXT("the digit run expanded to three steps, not one"), Definition.Get_Steps().Num(), 3);

    if (Definition.Get_Steps().Num() != 3)
    { return false; }

    DoAssert_DirectionStep(*this, Definition.Get_Steps()[0], ECk_Intent_Octant::S,  TEXT("step 0"));
    DoAssert_DirectionStep(*this, Definition.Get_Steps()[1], ECk_Intent_Octant::SE, TEXT("step 1"));

    const auto Terminal = UCk_Utils_IntentGrammar_UE::Get_TerminalStep(Definition);
    DoAssert_DirectionButtonChord(*this, Terminal, ECk_Intent_Octant::E, FName{TEXT("LP")}, TEXT("the terminal"));

    TestTrue(TEXT("the terminal IS the last step"),
        Terminal.Get_Atoms() == Definition.Get_Steps().Last().Get_Atoms());

    TestEqual(TEXT("the window parsed in logic frames"), Definition.Get_WindowFrames(), 200);
    TestTrue(TEXT("the lenience flag parsed"), Definition.Get_Lenience() == ECk_Intent_Lenience::Lenient);
    TestEqual(TEXT("an undeclared hold reads as zero"), Definition.Get_HoldFrames(), 0);

    // The identity is carried, not derived from the notation: two projects can share a motion and disagree about
    // what it is called and what it outranks.
    TestTrue(TEXT("the name is carried through"), Definition.Get_Name() == FName{TEXT("Hadouken")});
    TestEqual(TEXT("the priority is carried through"), Definition.Get_Priority(), 10);

    TestTrue(TEXT("an accepted parse records no rejection"),
        Result.Get_Error() == ECk_Intent_ParseError::None);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_IntentGrammar_NumpadDigitsMapToOctants,
    "Ck.Intent.Grammar.NumpadDigitsMapToOctants",
    ck_test_intent_grammar::kGrammarTestFlags)

bool FCkTest_IntentGrammar_NumpadDigitsMapToOctants::RunTest(const FString& Parameters)
{
    using namespace ck_test_intent_grammar;

    struct FDigitCase
    {
        const TCHAR* _Notation;
        ECk_Intent_Octant _Expected;
    };

    // The keypad's own face, exhaustively. Asserted through Parse so the table cannot drift away from its user.
    const auto Cases = TArray<FDigitCase>
    {
        FDigitCase{TEXT("1"), ECk_Intent_Octant::SW},
        FDigitCase{TEXT("2"), ECk_Intent_Octant::S},
        FDigitCase{TEXT("3"), ECk_Intent_Octant::SE},
        FDigitCase{TEXT("4"), ECk_Intent_Octant::W},
        FDigitCase{TEXT("5"), ECk_Intent_Octant::Neutral},
        FDigitCase{TEXT("6"), ECk_Intent_Octant::E},
        FDigitCase{TEXT("7"), ECk_Intent_Octant::NW},
        FDigitCase{TEXT("8"), ECk_Intent_Octant::N},
        FDigitCase{TEXT("9"), ECk_Intent_Octant::NE}
    };

    for (const auto& Case : Cases)
    {
        const auto Result = DoParse(Case._Notation);
        const auto What = FString::Printf(TEXT("digit [%s]"), Case._Notation);

        if (NOT TestTrue(What + TEXT(" parses"), Result.Get_IsSucceeded()))
        { continue; }

        TestEqual(What + TEXT(" is one step"), Result.Get_Definition().Get_Steps().Num(), 1);

        if (Result.Get_Definition().Get_Steps().Num() != 1)
        { continue; }

        DoAssert_DirectionStep(*this, Result.Get_Definition().Get_Steps()[0], Case._Expected, What);
    }

    // Zero has no place on the ring — it is neither a direction nor the start of a button name.
    DoAssert_Rejects(*this, TEXT("0"), ECk_Intent_ParseError::InvalidDirectionDigit);
    DoAssert_Rejects(*this, TEXT("206"), ECk_Intent_ParseError::InvalidDirectionDigit);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_IntentGrammar_CanonicalMotionsRoundTrip,
    "Ck.Intent.Grammar.CanonicalMotionsRoundTrip",
    ck_test_intent_grammar::kGrammarTestFlags)

bool FCkTest_IntentGrammar_CanonicalMotionsRoundTrip::RunTest(const FString& Parameters)
{
    using namespace ck_test_intent_grammar;

    {
        const auto Result = DoParse(TEXT("623+HP"));
        const auto& Steps = Result.Get_Definition().Get_Steps();

        TestTrue(TEXT("[623+HP] parses"), Result.Get_IsSucceeded());
        TestEqual(TEXT("[623+HP] is three steps"), Steps.Num(), 3);

        if (Steps.Num() == 3)
        {
            DoAssert_DirectionStep(*this, Steps[0], ECk_Intent_Octant::E, TEXT("[623+HP] step 0"));
            DoAssert_DirectionStep(*this, Steps[1], ECk_Intent_Octant::S, TEXT("[623+HP] step 1"));
            DoAssert_DirectionButtonChord(*this, Steps[2],
                ECk_Intent_Octant::SE, FName{TEXT("HP")}, TEXT("[623+HP] terminal"));
        }
    }

    {
        const auto Result = DoParse(TEXT("2 8 LP"));
        const auto& Steps = Result.Get_Definition().Get_Steps();

        TestTrue(TEXT("[2 8 LP] parses"), Result.Get_IsSucceeded());
        TestEqual(TEXT("[2 8 LP] is three steps"), Steps.Num(), 3);

        if (Steps.Num() == 3)
        {
            DoAssert_DirectionStep(*this, Steps[0], ECk_Intent_Octant::S, TEXT("[2 8 LP] step 0"));
            DoAssert_DirectionStep(*this, Steps[1], ECk_Intent_Octant::N, TEXT("[2 8 LP] step 1"));
            DoAssert_ButtonStep(*this, Steps[2], FName{TEXT("LP")}, TEXT("[2 8 LP] terminal"));

            TestTrue(TEXT("[2 8 LP] terminal is not a chord"), NOT Steps[2].Get_IsChord());
        }
    }

    {
        const auto Result = DoParse(TEXT("46+MP hold=30"));
        const auto& Steps = Result.Get_Definition().Get_Steps();

        TestTrue(TEXT("[46+MP hold=30] parses"), Result.Get_IsSucceeded());
        TestEqual(TEXT("[46+MP hold=30] is two steps"), Steps.Num(), 2);

        if (Steps.Num() == 2)
        {
            DoAssert_DirectionStep(*this, Steps[0], ECk_Intent_Octant::W, TEXT("[46+MP] step 0"));
            DoAssert_DirectionButtonChord(*this, Steps[1],
                ECk_Intent_Octant::E, FName{TEXT("MP")}, TEXT("[46+MP] terminal"));
        }

        TestEqual(TEXT("the hold parsed in logic frames"), Result.Get_Definition().Get_HoldFrames(), 30);
        TestEqual(TEXT("an undeclared window reads as zero"), Result.Get_Definition().Get_WindowFrames(), 0);
        TestTrue(TEXT("an undeclared lenience reads as strict"),
            Result.Get_Definition().Get_Lenience() == ECk_Intent_Lenience::Strict);
    }

    {
        // Two buttons, no direction: a chord is a SET of atoms, not a direction plus something.
        const auto Result = DoParse(TEXT("LP+MP"));
        const auto& Steps = Result.Get_Definition().Get_Steps();

        TestTrue(TEXT("[LP+MP] parses"), Result.Get_IsSucceeded());
        TestEqual(TEXT("[LP+MP] is one step"), Steps.Num(), 1);

        if (Steps.Num() == 1 && Steps[0].Get_Atoms().Num() == 2)
        {
            TestTrue(TEXT("[LP+MP] reads as a chord"), Steps[0].Get_IsChord());
            TestTrue(TEXT("[LP+MP] first atom is the button written first"),
                Steps[0].Get_Atoms()[0].Get_ButtonName() == FName{TEXT("LP")});
            TestTrue(TEXT("[LP+MP] second atom is the button written second"),
                Steps[0].Get_Atoms()[1].Get_ButtonName() == FName{TEXT("MP")});
        }
        else
        {
            AddError(TEXT("[LP+MP] did not parse to one two-atom chord"));
        }
    }

    {
        // Neutral is a legitimate STEP even though it cannot be a chord member — returning the stick to centre is
        // a thing a motion asks for.
        const auto Result = DoParse(TEXT("2 5 6"));
        const auto& Steps = Result.Get_Definition().Get_Steps();

        TestTrue(TEXT("[2 5 6] parses"), Result.Get_IsSucceeded());
        TestEqual(TEXT("[2 5 6] is three steps"), Steps.Num(), 3);

        if (Steps.Num() == 3)
        {
            DoAssert_DirectionStep(*this, Steps[1], ECk_Intent_Octant::Neutral, TEXT("[2 5 6] step 1"));
        }
    }

    {
        // Button case is PRESERVED, never normalised: the bake matches these names against declared ButtonIds and
        // an author reading the notation back must see what they wrote.
        const auto Result = DoParse(TEXT("Attack_Heavy"));
        const auto& Steps = Result.Get_Definition().Get_Steps();

        TestTrue(TEXT("[Attack_Heavy] parses"), Result.Get_IsSucceeded());

        if (Steps.Num() == 1 && Steps[0].Get_Atoms().Num() == 1)
        {
            TestEqual(TEXT("the button name kept its case verbatim"),
                Steps[0].Get_Atoms()[0].Get_ButtonName().ToString(), FString{TEXT("Attack_Heavy")});
        }
        else
        {
            AddError(TEXT("[Attack_Heavy] did not parse to one single-atom step"));
        }
    }

    {
        // Modifier keywords are matched case-insensitively, which is what stops `Lenient` from being read as a
        // button named after a modifier and the declaration from vanishing silently.
        const auto Result = DoParse(TEXT("236+LP W=200 LENIENT"));

        TestTrue(TEXT("[W=200 LENIENT] parses — modifier keywords are case-insensitive"), Result.Get_IsSucceeded());
        TestEqual(TEXT("the upper-case window still parsed"), Result.Get_Definition().Get_WindowFrames(), 200);
        TestTrue(TEXT("the upper-case lenience still parsed"),
            Result.Get_Definition().Get_Lenience() == ECk_Intent_Lenience::Lenient);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_IntentGrammar_ModifiersAreOrderFreeAndTrailingOnly,
    "Ck.Intent.Grammar.ModifiersAreOrderFreeAndTrailingOnly",
    ck_test_intent_grammar::kGrammarTestFlags)

bool FCkTest_IntentGrammar_ModifiersAreOrderFreeAndTrailingOnly::RunTest(const FString& Parameters)
{
    using namespace ck_test_intent_grammar;

    const auto Orderings = TArray<const TCHAR*>
    {
        TEXT("236+LP w=200 hold=5 lenient"),
        TEXT("236+LP lenient w=200 hold=5"),
        TEXT("236+LP hold=5 lenient w=200"),
        TEXT("236+LP lenient hold=5 w=200")
    };

    for (const auto& Notation : Orderings)
    {
        const auto Result = DoParse(Notation);
        const auto What = FString::Printf(TEXT("[%s]"), Notation);

        if (NOT TestTrue(What + TEXT(" parses"), Result.Get_IsSucceeded()))
        { continue; }

        TestEqual(What + TEXT(" has the same step count"), Result.Get_Definition().Get_Steps().Num(), 3);
        TestEqual(What + TEXT(" has the same window"), Result.Get_Definition().Get_WindowFrames(), 200);
        TestEqual(What + TEXT(" has the same hold"), Result.Get_Definition().Get_HoldFrames(), 5);
        TestTrue(What + TEXT(" has the same lenience"),
            Result.Get_Definition().Get_Lenience() == ECk_Intent_Lenience::Lenient);
    }

    // Trailing is not a stylistic preference: a token after a modifier is either a step the author meant to write
    // earlier or a misspelled modifier, and guessing which would silently reorder the move.
    DoAssert_Rejects(*this, TEXT("2 w=200 6"),      ECk_Intent_ParseError::ModifierNotTrailing);
    DoAssert_Rejects(*this, TEXT("2 lenient 6"),    ECk_Intent_ParseError::ModifierNotTrailing);
    DoAssert_Rejects(*this, TEXT("w=200 236+LP"),   ECk_Intent_ParseError::ModifierNotTrailing);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_IntentGrammar_WhitespaceDoesNotChangeTheParse,
    "Ck.Intent.Grammar.WhitespaceDoesNotChangeTheParse",
    ck_test_intent_grammar::kGrammarTestFlags)

bool FCkTest_IntentGrammar_WhitespaceDoesNotChangeTheParse::RunTest(const FString& Parameters)
{
    using namespace ck_test_intent_grammar;

    const auto Spellings = TArray<const TCHAR*>
    {
        TEXT("236+LP w=200 lenient"),
        TEXT("   236+LP w=200 lenient"),
        TEXT("236+LP w=200 lenient   "),
        TEXT("236+LP    w=200     lenient"),
        TEXT("236+LP\tw=200\tlenient")
    };

    for (const auto& Notation : Spellings)
    {
        const auto Result = DoParse(Notation);
        const auto What = FString::Printf(TEXT("[%s]"), Notation);

        if (NOT TestTrue(What + TEXT(" parses"), Result.Get_IsSucceeded()))
        { continue; }

        TestEqual(What + TEXT(" is three steps"), Result.Get_Definition().Get_Steps().Num(), 3);
        TestEqual(What + TEXT(" carries the window"), Result.Get_Definition().Get_WindowFrames(), 200);
        TestTrue(What + TEXT(" carries the lenience"),
            Result.Get_Definition().Get_Lenience() == ECk_Intent_Lenience::Lenient);

        const auto Terminal = UCk_Utils_IntentGrammar_UE::Get_TerminalStep(Result.Get_Definition());
        DoAssert_DirectionButtonChord(*this, Terminal, ECk_Intent_Octant::E, FName{TEXT("LP")},
            What + TEXT(" terminal"));
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_IntentGrammar_EveryMalformedInputRejectsWithItsOwnReason,
    "Ck.Intent.Grammar.EveryMalformedInputRejectsWithItsOwnReason",
    ck_test_intent_grammar::kGrammarTestFlags)

bool FCkTest_IntentGrammar_EveryMalformedInputRejectsWithItsOwnReason::RunTest(const FString& Parameters)
{
    using namespace ck_test_intent_grammar;

    DoAssert_Rejects(*this, TEXT(""),             ECk_Intent_ParseError::EmptyNotation);
    DoAssert_Rejects(*this, TEXT("     "),        ECk_Intent_ParseError::EmptyNotation);
    DoAssert_Rejects(*this, TEXT("w=200 lenient"), ECk_Intent_ParseError::NoSteps);

    DoAssert_Rejects(*this, TEXT("236 x=5"),      ECk_Intent_ParseError::UnknownModifier);
    DoAssert_Rejects(*this, TEXT("236 window=200"), ECk_Intent_ParseError::UnknownModifier);
    DoAssert_Rejects(*this, TEXT("236 w=200 w=300"), ECk_Intent_ParseError::DuplicateModifier);
    DoAssert_Rejects(*this, TEXT("236 lenient lenient"), ECk_Intent_ParseError::DuplicateModifier);

    DoAssert_Rejects(*this, TEXT("236 w=0"),      ECk_Intent_ParseError::MalformedWindow);
    DoAssert_Rejects(*this, TEXT("236 w=-5"),     ECk_Intent_ParseError::MalformedWindow);
    DoAssert_Rejects(*this, TEXT("236 w=abc"),    ECk_Intent_ParseError::MalformedWindow);
    DoAssert_Rejects(*this, TEXT("236 w="),       ECk_Intent_ParseError::MalformedWindow);
    DoAssert_Rejects(*this, TEXT("236 hold=0"),   ECk_Intent_ParseError::MalformedHold);
    DoAssert_Rejects(*this, TEXT("236 hold=x"),   ECk_Intent_ParseError::MalformedHold);

    DoAssert_Rejects(*this, TEXT("2a"),           ECk_Intent_ParseError::InvalidDirectionDigit);
    DoAssert_Rejects(*this, TEXT("L-P"),          ECk_Intent_ParseError::InvalidButtonName);
    DoAssert_Rejects(*this, TEXT("LP!"),          ECk_Intent_ParseError::InvalidButtonName);

    DoAssert_Rejects(*this, TEXT("6+"),           ECk_Intent_ParseError::EmptyChordAtom);
    DoAssert_Rejects(*this, TEXT("+LP"),          ECk_Intent_ParseError::EmptyChordAtom);
    DoAssert_Rejects(*this, TEXT("6++LP"),        ECk_Intent_ParseError::EmptyChordAtom);

    DoAssert_Rejects(*this, TEXT("LP+LP"),        ECk_Intent_ParseError::ChordDuplicateAtom);
    DoAssert_Rejects(*this, TEXT("LP+lp"),        ECk_Intent_ParseError::ChordDuplicateAtom);
    DoAssert_Rejects(*this, TEXT("6+6"),          ECk_Intent_ParseError::ChordDuplicateAtom);

    DoAssert_Rejects(*this, TEXT("6+4"),          ECk_Intent_ParseError::ChordTwoDirections);
    DoAssert_Rejects(*this, TEXT("236+4+LP"),     ECk_Intent_ParseError::ChordTwoDirections);

    DoAssert_Rejects(*this, TEXT("5+LP"),         ECk_Intent_ParseError::ChordNeutralDirection);
    DoAssert_Rejects(*this, TEXT("25+LP"),        ECk_Intent_ParseError::ChordNeutralDirection);

    // The token is carried verbatim so an authoring tool can point at the text instead of making the designer
    // re-derive which of six tokens the reason was about.
    const auto TokenCarried = DoParse(TEXT("236+LP w=200 nonsense=1"));
    TestTrue(TEXT("a rejection names the offending token"),
        TokenCarried.Get_ErrorToken() == FString{TEXT("nonsense=1")});

    // Whole-notation rejections have no single token to blame and say so rather than inventing one.
    const auto NoToken = DoParse(TEXT("w=200"));
    TestTrue(TEXT("a whole-notation rejection carries no token"), NoToken.Get_ErrorToken().IsEmpty());

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
