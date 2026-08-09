#include "CkCore/Macros/CkMacros.h"

#include "CkInput/CkInputButtonMap_Fragment_Data.h"

#include "CkIntent/CkIntentGrammar_Utils.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
// Pins the bake (CkIntentGrammar_Utils.h) — definitions in, an activatable compiled set out.
//
//   1. THE deferral law, in four legs. Two intents sharing a terminal defer for NOTHING, even when one of them
//      terminates on a direction+button chord and the other is the tail of a longer sequence. Deferral appears
//      only when a hold sibling or a second-button chord makes a lone press genuinely ambiguous, and both causes
//      are carried when both apply. The no-deferral answer is structural: the set writes no row at all.
//   2. Resolution tables are ordered by descending priority, are keyed on TERMINAL buttons only (a mid-sequence
//      button gets no row), and answer empty for a button no intent terminates on.
//   3. Every rejection class has its own reason and names what the author has to fix; one bad definition among
//      good ones yields an EMPTY set, never the moves that happened to compile.
//   4. A compiled set is self-contained value data — a copy answers identically, which is what makes activating
//      one an assignment rather than a rebuild.
//
// The fixture builds definitions by PARSING notation, never by hand: the parser is the only producer, so a test
// that assembled definitions some other way would be testing a shape the bake can never actually receive.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_intent_bake
{
    constexpr auto kBakeTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;

    // Deliberately not 3, so an assertion that reads this back proves the set carried the ARGUMENT rather than
    // the default the signature happens to declare.
    constexpr auto kChordWindowFrames = 4;

    // ----------------------------------------------------------------------------------------------------------------

    auto
    DoMake_Button(
        const TCHAR* InName) -> FCk_Input_ButtonId
    {
        return FCk_Input_ButtonId{ECk_Input_ButtonTier::Mapped, FName{InName}};
    }

    auto
    DoMake_ButtonRows(
        std::initializer_list<const TCHAR*> InNames) -> TArray<FCk_Intent_ButtonNameRow>
    {
        auto Rows = TArray<FCk_Intent_ButtonNameRow>{};

        for (const auto& Name : InNames)
        { Rows.Add(FCk_Intent_ButtonNameRow{FName{Name}, DoMake_Button(Name)}); }

        return Rows;
    }

    auto
    DoParse(
        FAutomationTestBase& InTest,
        const TCHAR* InNotation,
        const TCHAR* InName,
        int32 InPriority) -> FCk_Intent_Definition
    {
        const auto Result = UCk_Utils_IntentGrammar_UE::Parse(
            InNotation, FName{InName}, InPriority, FGameplayTag{});

        if (NOT Result.Get_IsSucceeded())
        { InTest.AddError(FString::Printf(TEXT("fixture notation [%s] failed to parse"), InNotation)); }

        return Result.Get_Definition();
    }

    auto
    DoGet_OrderedNames(
        const FCk_Intent_CompiledSet& InSet,
        const FCk_Input_ButtonId& InButton) -> TArray<FName>
    {
        auto Names = TArray<FName>{};

        const auto Row = UCk_Utils_IntentGrammar_UE::TryGet_ResolutionRow(InSet, InButton);

        for (const auto& Index : Row.Get_IntentIndices())
        { Names.Add(InSet.Get_Intents()[Index].Get_Name()); }

        return Names;
    }

    auto
    DoAssert_Rejects(
        FAutomationTestBase& InTest,
        const TArray<FCk_Intent_Definition>& InDefinitions,
        const TArray<FCk_Intent_ButtonNameRow>& InRows,
        int32 InChordWindowFrames,
        ECk_Intent_BakeError InExpected,
        const FString& InWhat) -> FCk_Intent_BakeResult
    {
        const auto Result = UCk_Utils_IntentGrammar_UE::Bake(InDefinitions, InRows, InChordWindowFrames);

        InTest.TestTrue(InWhat + TEXT(" is rejected"), Result.Get_Outcome() == ECk_SucceededFailed::Failed);
        InTest.TestTrue(InWhat + TEXT(" rejects for its own reason"), Result.Get_Error() == InExpected);
        InTest.TestTrue(InWhat + TEXT(" yields an unusable-empty set"), Result.Get_CompiledSet().Get_IsEmpty());

        return Result;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_IntentBake_SharedTerminalNeverDefersButAmbiguityDoes,
    "Ck.Intent.Grammar.SharedTerminalNeverDefersButAmbiguityDoes",
    ck_test_intent_bake::kBakeTestFlags)

bool FCkTest_IntentBake_SharedTerminalNeverDefersButAmbiguityDoes::RunTest(const FString& Parameters)
{
    using namespace ck_test_intent_bake;

    const auto Rows = DoMake_ButtonRows({TEXT("LP"), TEXT("MP")});
    const auto LP = DoMake_Button(TEXT("LP"));
    const auto MP = DoMake_Button(TEXT("MP"));

    // LEG 1 — the law. LP terminates a chord in one intent and a longer sequence in another; both scans anchor on
    // the same press. Sharing a terminal is not ambiguity: whichever intent's prefix the record actually contains
    // is decidable from the record the press arrives on, so there is nothing to wait for.
    {
        const auto Definitions = TArray<FCk_Intent_Definition>
        {
            DoParse(*this, TEXT("236+LP"), TEXT("Special"), 100),
            DoParse(*this, TEXT("2 3 6 LP"), TEXT("Chain"), 50)
        };

        const auto Result = UCk_Utils_IntentGrammar_UE::Bake(Definitions, Rows, kChordWindowFrames);

        TestTrue(TEXT("a set sharing one terminal bakes"), Result.Get_IsSucceeded());

        const auto& Set = Result.Get_CompiledSet();

        // Structural, not computed-then-found-zero: nothing wrote a row, so there is nothing to get wrong.
        TestTrue(TEXT("no button in the set defers at all"), Set.Get_Deferrals().IsEmpty());

        const auto Verdict = UCk_Utils_IntentGrammar_UE::Get_DeferralVerdict(Set, LP);

        TestTrue(TEXT("a shared terminal defers for nothing"), NOT Verdict.Get_IsDeferred());
        TestEqual(TEXT("no hold cause"), Verdict.Get_HoldSiblingFrames(), 0);

        // This move's own terminal IS a chord — of a DIRECTION and a button. A direction is state the frame
        // record already reports on the press frame, so nothing is still in flight and nothing may be waited on.
        TestEqual(TEXT("a direction+button chord is not a second-press ambiguity"),
            Verdict.Get_ChordMemberFrames(), 0);
    }

    // LEG 2 — a hold sibling. Tap and hold on one button cannot be told apart until the threshold passes.
    {
        const auto Definitions = TArray<FCk_Intent_Definition>
        {
            DoParse(*this, TEXT("236+LP"), TEXT("Special"), 100),
            DoParse(*this, TEXT("2 3 6 LP"), TEXT("Chain"), 50),
            DoParse(*this, TEXT("LP hold=30"), TEXT("HoldPunch"), 25)
        };

        const auto Result = UCk_Utils_IntentGrammar_UE::Bake(Definitions, Rows, kChordWindowFrames);

        TestTrue(TEXT("a set with a hold sibling bakes"), Result.Get_IsSucceeded());

        const auto Verdict = UCk_Utils_IntentGrammar_UE::Get_DeferralVerdict(Result.Get_CompiledSet(), LP);

        TestTrue(TEXT("a hold sibling makes the button defer"), Verdict.Get_IsDeferred());
        TestEqual(TEXT("the deferral is the declared hold threshold"), Verdict.Get_HoldSiblingFrames(), 30);
        TestEqual(TEXT("a hold sibling alone raises no chord cause"), Verdict.Get_ChordMemberFrames(), 0);
    }

    // LEG 3 — a second-button chord. Pressing LP may be the whole of one intent or the first half of another's
    // chord, and the partner press may still be in flight.
    {
        const auto Definitions = TArray<FCk_Intent_Definition>
        {
            DoParse(*this, TEXT("LP"), TEXT("Jab"), 100),
            DoParse(*this, TEXT("LP+MP"), TEXT("Throw"), 50)
        };

        const auto Result = UCk_Utils_IntentGrammar_UE::Bake(Definitions, Rows, kChordWindowFrames);

        TestTrue(TEXT("a set with a two-button chord bakes"), Result.Get_IsSucceeded());

        const auto& Set = Result.Get_CompiledSet();
        const auto LpVerdict = UCk_Utils_IntentGrammar_UE::Get_DeferralVerdict(Set, LP);

        TestEqual(TEXT("the chord deferral is the set's chord window"),
            LpVerdict.Get_ChordMemberFrames(), kChordWindowFrames);
        TestEqual(TEXT("a chord sibling alone raises no hold cause"), LpVerdict.Get_HoldSiblingFrames(), 0);
        TestEqual(TEXT("the set carries the window it was baked with"),
            Set.Get_ChordWindowFrames(), kChordWindowFrames);

        // MP terminates only the chord. A press of it can be wrong about nothing, so it waits for nothing —
        // even though completing the chord still needs its partner.
        TestTrue(TEXT("the chord's other button has no rival and so no verdict"),
            NOT UCk_Utils_IntentGrammar_UE::Get_DeferralVerdict(Set, MP).Get_IsDeferred());
    }

    // LEG 4 — both causes at once. They are independent ambiguities and the set carries both; how to combine them
    // is the matcher's call, which is exactly why this does not collapse to one number.
    {
        const auto Definitions = TArray<FCk_Intent_Definition>
        {
            DoParse(*this, TEXT("LP"), TEXT("Jab"), 100),
            DoParse(*this, TEXT("LP hold=30"), TEXT("HoldPunch"), 50),
            DoParse(*this, TEXT("LP+MP"), TEXT("Throw"), 25)
        };

        const auto Result = UCk_Utils_IntentGrammar_UE::Bake(Definitions, Rows, kChordWindowFrames);

        TestTrue(TEXT("a set with both ambiguities bakes"), Result.Get_IsSucceeded());

        const auto Verdict = UCk_Utils_IntentGrammar_UE::Get_DeferralVerdict(Result.Get_CompiledSet(), LP);

        TestEqual(TEXT("the hold cause survives alongside the chord one"), Verdict.Get_HoldSiblingFrames(), 30);
        TestEqual(TEXT("the chord cause survives alongside the hold one"),
            Verdict.Get_ChordMemberFrames(), kChordWindowFrames);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_IntentBake_ResolutionTablesOrderByDescendingPriority,
    "Ck.Intent.Grammar.ResolutionTablesOrderByDescendingPriority",
    ck_test_intent_bake::kBakeTestFlags)

bool FCkTest_IntentBake_ResolutionTablesOrderByDescendingPriority::RunTest(const FString& Parameters)
{
    using namespace ck_test_intent_bake;

    const auto Rows = DoMake_ButtonRows({TEXT("LP"), TEXT("MP"), TEXT("HP")});

    // Authored out of priority order on purpose — the table's order must come from the priorities, not from the
    // order the definitions happened to arrive in.
    const auto Definitions = TArray<FCk_Intent_Definition>
    {
        DoParse(*this, TEXT("236+LP"), TEXT("Middling"), 50),
        DoParse(*this, TEXT("2 8 LP"), TEXT("Weakest"), 10),
        DoParse(*this, TEXT("623+LP"), TEXT("Strongest"), 90),
        DoParse(*this, TEXT("6 MP HP"), TEXT("OtherTerminal"), 70)
    };

    const auto Result = UCk_Utils_IntentGrammar_UE::Bake(Definitions, Rows, kChordWindowFrames);

    if (NOT TestTrue(TEXT("the set bakes"), Result.Get_IsSucceeded()))
    { return false; }

    const auto& Set = Result.Get_CompiledSet();

    const auto Ordered = DoGet_OrderedNames(Set, DoMake_Button(TEXT("LP")));

    TestEqual(TEXT("every intent terminating on LP is in its row"), Ordered.Num(), 3);

    if (Ordered.Num() == 3)
    {
        TestTrue(TEXT("the most dominant intent is first"),  Ordered[0] == FName{TEXT("Strongest")});
        TestTrue(TEXT("the middle intent is second"),        Ordered[1] == FName{TEXT("Middling")});
        TestTrue(TEXT("the least dominant intent is last"),  Ordered[2] == FName{TEXT("Weakest")});
    }

    const auto OtherRow = DoGet_OrderedNames(Set, DoMake_Button(TEXT("HP")));

    TestEqual(TEXT("a different terminal gets its own row"), OtherRow.Num(), 1);

    // MP is the SECOND-to-last step of OtherTerminal — a sequence member, never a terminal. It gets no row, which
    // is the resolution-table half of the same law the deferral verdicts obey: only terminals are ever visited.
    TestTrue(TEXT("a mid-sequence button terminates nothing and gets no row"),
        UCk_Utils_IntentGrammar_UE::TryGet_ResolutionRow(Set, DoMake_Button(TEXT("MP")))
            .Get_IntentIndices().IsEmpty());

    // A button the set has never heard of answers the same empty row — there is no found-flag to check.
    TestTrue(TEXT("an unreferenced button answers an empty row"),
        UCk_Utils_IntentGrammar_UE::TryGet_ResolutionRow(Set, DoMake_Button(TEXT("Unheard")))
            .Get_IntentIndices().IsEmpty());

    TestEqual(TEXT("the table holds exactly the terminal buttons"), Set.Get_ResolutionTable().Num(), 2);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_IntentBake_EveryRejectionHasItsOwnReasonAndIsAtomic,
    "Ck.Intent.Grammar.EveryBakeRejectionHasItsOwnReasonAndIsAtomic",
    ck_test_intent_bake::kBakeTestFlags)

bool FCkTest_IntentBake_EveryRejectionHasItsOwnReasonAndIsAtomic::RunTest(const FString& Parameters)
{
    using namespace ck_test_intent_bake;

    const auto Rows = DoMake_ButtonRows({TEXT("LP"), TEXT("MP")});
    const auto Valid = DoParse(*this, TEXT("236+LP"), TEXT("Special"), 100);

    DoAssert_Rejects(*this, {}, Rows, kChordWindowFrames,
        ECk_Intent_BakeError::NoDefinitions, TEXT("an empty definition array"));

    DoAssert_Rejects(*this, {Valid}, Rows, 0,
        ECk_Intent_BakeError::NonPositiveChordWindow, TEXT("a zero chord window"));

    DoAssert_Rejects(*this, {Valid}, Rows, -1,
        ECk_Intent_BakeError::NonPositiveChordWindow, TEXT("a negative chord window"));

    // The empty definition is the only one anybody outside the parser can make, and the bake is where that gets
    // caught: the parser deliberately does not police names, because one string cannot know what else is in the set.
    DoAssert_Rejects(*this, {Valid, FCk_Intent_Definition{}}, Rows, kChordWindowFrames,
        ECk_Intent_BakeError::UnnamedIntent, TEXT("a nameless definition"));

    {
        const auto Duplicated = TArray<FCk_Intent_Definition>
        {
            DoParse(*this, TEXT("236+LP"), TEXT("Twice"), 100),
            DoParse(*this, TEXT("623+MP"), TEXT("Twice"), 50)
        };

        const auto Result = DoAssert_Rejects(*this, Duplicated, Rows, kChordWindowFrames,
            ECk_Intent_BakeError::DuplicateIntentName, TEXT("two intents sharing a name"));

        TestTrue(TEXT("the duplicate rejection names the contested name"),
            Result.Get_OffendingIntent() == FName{TEXT("Twice")});
    }

    {
        const auto UnknownButton = TArray<FCk_Intent_Definition>
        {
            Valid,
            DoParse(*this, TEXT("623+HP"), TEXT("Undeclared"), 50)
        };

        const auto Result = DoAssert_Rejects(*this, UnknownButton, Rows, kChordWindowFrames,
            ECk_Intent_BakeError::UnknownButtonName, TEXT("a button no row maps"));

        // Both halves, because either alone leaves the author searching: which move, and which token in it.
        TestTrue(TEXT("the rejection names the intent that used it"),
            Result.Get_OffendingIntent() == FName{TEXT("Undeclared")});
        TestTrue(TEXT("the rejection names the button that did not resolve"),
            Result.Get_OffendingButtonName() == FName{TEXT("HP")});

        // Atomicity: the valid definition alongside it compiled to nothing.
        TestTrue(TEXT("one bad definition invalidates the whole set"),
            Result.Get_CompiledSet().Get_Intents().IsEmpty());
    }

    {
        const auto Tied = TArray<FCk_Intent_Definition>
        {
            DoParse(*this, TEXT("236+LP"), TEXT("Fireball"), 50),
            DoParse(*this, TEXT("623+LP"), TEXT("Uppercut"), 50)
        };

        const auto Result = DoAssert_Rejects(*this, Tied, Rows, kChordWindowFrames,
            ECk_Intent_BakeError::PriorityTieOnSharedTerminal, TEXT("two intents tied on one terminal"));

        TestTrue(TEXT("the tie names the first intent"),
            Result.Get_OffendingIntent() == FName{TEXT("Fireball")});
        TestTrue(TEXT("the tie names the second intent"),
            Result.Get_ConflictingIntent() == FName{TEXT("Uppercut")});
        TestTrue(TEXT("the tie names the terminal they contest"),
            Result.Get_OffendingButton() == DoMake_Button(TEXT("LP")));
    }

    {
        // A name declared twice against the SAME identity is a caller stitching rows from two overlapping
        // sources. There is one answer, so there is nothing to resolve and nothing to complain about.
        auto Idempotent = Rows;
        Idempotent.Add(FCk_Intent_ButtonNameRow{FName{TEXT("LP")}, DoMake_Button(TEXT("LP"))});

        const auto Result = UCk_Utils_IntentGrammar_UE::Bake({Valid}, Idempotent, kChordWindowFrames);

        TestTrue(TEXT("a duplicate row agreeing with itself bakes"), Result.Get_IsSucceeded());
        TestEqual(TEXT("the idempotent duplicate produced one intent, not two"),
            Result.Get_CompiledSet().Get_Intents().Num(), 1);

        const auto& Terminal = Result.Get_CompiledSet().Get_Intents()[0].Get_Steps().Last();

        if (Terminal.Get_Atoms().Num() == 2)
        {
            TestTrue(TEXT("the duplicated name still resolves to the one identity both rows named"),
                Terminal.Get_Atoms()[1].Get_Button() == DoMake_Button(TEXT("LP")));
        }
        else
        {
            AddError(TEXT("the terminal chord did not survive the idempotent duplicate"));
        }
    }

    {
        // Two identities for one name is two answers to one question. Taking either would silently discard a
        // declaration the caller wrote down, which is the failure mode this rejection exists to prevent.
        auto Conflicting = Rows;
        Conflicting.Add(FCk_Intent_ButtonNameRow
        {
            FName{TEXT("LP")},
            FCk_Input_ButtonId{ECk_Input_ButtonTier::Physical, FName{TEXT("LP")}}
        });

        const auto Result = DoAssert_Rejects(*this, {Valid}, Conflicting, kChordWindowFrames,
            ECk_Intent_BakeError::ConflictingButtonRow, TEXT("two rows answering one name differently"));

        TestTrue(TEXT("the conflict names the contested button name"),
            Result.Get_OffendingButtonName() == FName{TEXT("LP")});
        TestTrue(TEXT("the conflict names the identity the first row gave"),
            Result.Get_OffendingButton() == DoMake_Button(TEXT("LP")));
        TestTrue(TEXT("the conflict names the identity the second row gave"),
            Result.Get_ConflictingButton() ==
                FCk_Input_ButtonId{ECk_Input_ButtonTier::Physical, FName{TEXT("LP")}});
    }

    {
        // The same two priorities are fine when the intents cannot both answer one press — a tie is only a defect
        // where arbitration would actually have to choose.
        const auto Disjoint = TArray<FCk_Intent_Definition>
        {
            DoParse(*this, TEXT("236+LP"), TEXT("Fireball"), 50),
            DoParse(*this, TEXT("623+MP"), TEXT("Uppercut"), 50)
        };

        const auto Result = UCk_Utils_IntentGrammar_UE::Bake(Disjoint, Rows, kChordWindowFrames);

        TestTrue(TEXT("equal priorities on DIFFERENT terminals are not a tie"), Result.Get_IsSucceeded());
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_IntentBake_CompiledSetIsSelfContainedValueData,
    "Ck.Intent.Grammar.CompiledSetIsSelfContainedValueData",
    ck_test_intent_bake::kBakeTestFlags)

bool FCkTest_IntentBake_CompiledSetIsSelfContainedValueData::RunTest(const FString& Parameters)
{
    using namespace ck_test_intent_bake;

    const auto Rows = DoMake_ButtonRows({TEXT("LP"), TEXT("MP")});
    const auto LP = DoMake_Button(TEXT("LP"));

    const auto Definitions = TArray<FCk_Intent_Definition>
    {
        DoParse(*this, TEXT("236+LP"), TEXT("Special"), 100),
        DoParse(*this, TEXT("LP hold=30"), TEXT("HoldPunch"), 50),
        DoParse(*this, TEXT("LP+MP"), TEXT("Throw"), 25)
    };

    const auto Result = UCk_Utils_IntentGrammar_UE::Bake(Definitions, Rows, kChordWindowFrames);

    if (NOT TestTrue(TEXT("the set bakes"), Result.Get_IsSucceeded()))
    { return false; }

    // The whole point of an O(1) activation: a set is values all the way down, so handing one to a state machine
    // costs a copy and re-resolves, re-sorts and re-validates nothing.
    const auto Copy = FCk_Intent_CompiledSet{Result.Get_CompiledSet()};

    TestEqual(TEXT("the copy holds the same intents"),
        Copy.Get_Intents().Num(), Result.Get_CompiledSet().Get_Intents().Num());
    TestEqual(TEXT("the copy holds the same resolution table"),
        Copy.Get_ResolutionTable().Num(), Result.Get_CompiledSet().Get_ResolutionTable().Num());
    TestEqual(TEXT("the copy holds the same deferral rows"),
        Copy.Get_Deferrals().Num(), Result.Get_CompiledSet().Get_Deferrals().Num());
    TestEqual(TEXT("the copy carries the same chord window"),
        Copy.Get_ChordWindowFrames(), Result.Get_CompiledSet().Get_ChordWindowFrames());

    TestTrue(TEXT("the copy resolves the terminal identically"),
        DoGet_OrderedNames(Copy, LP) == DoGet_OrderedNames(Result.Get_CompiledSet(), LP));
    TestTrue(TEXT("the copy answers the same verdict"),
        UCk_Utils_IntentGrammar_UE::Get_DeferralVerdict(Copy, LP) ==
        UCk_Utils_IntentGrammar_UE::Get_DeferralVerdict(Result.Get_CompiledSet(), LP));

    // A compiled atom carries an identity, not a name: a rebind moves which KEY produces that button and this
    // stays true, which is the reason the bake resolves at all.
    const auto& Terminal = Copy.Get_Intents()[0].Get_Steps().Last();

    TestEqual(TEXT("the terminal chord kept both atoms"), Terminal.Get_Atoms().Num(), 2);

    if (Terminal.Get_Atoms().Num() == 2)
    {
        TestTrue(TEXT("the button atom resolved to a ButtonId"),
            Terminal.Get_Atoms()[1].Get_Button() == LP);
    }

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
