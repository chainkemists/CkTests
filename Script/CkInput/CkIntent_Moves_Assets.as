// Language=angelscript

//============================================================================
// CK INTENT — A CHARACTER'S WHOLE MOVE VOCABULARY, AS NOTATION
//============================================================================
//
// Forty moves, declared the way a designer declares them: a name, the notation
// string, and the priority that decides who wins a terminal they share. There
// is nothing else here on purpose — no steps, no atoms, no definitions. The
// grammar is the only thing that turns a string into a move, so a table that
// carried a pre-built shape beside the string would be a second dialect, and
// the first time the two disagreed nothing could say which one the character
// was actually playing.
//
// The bake is a whole-set operation, so this file exists as ONE asset rather
// than forty scattered literals: the priority tie check, the resolution
// ordering and every deferral verdict are derived from all forty at once, and
// a vocabulary a test can only see a slice of cannot prove anything about
// them.
//
// TERMINAL ZONES — read before adding a move.
//
// `CkAutoTest_Intent_FortyMoveBake` reads three verdicts off the baked set,
// and each one is a property of every move sharing that terminal button:
//
//   LP  must stay CLEAN — several moves end on it, none declares `hold=`,
//       and none of its terminals carries a second BUTTON. That is what makes
//       its zero verdict a statement about sharing a terminal rather than an
//       accident of a thin row.
//   HP  must keep exactly one hold sibling at `k_ChargeHoldFrames` frames and
//       no two-button chord terminal.
//   HK  must keep its two-button chord (`LK+HK`) and its bare rival, and no
//       `hold=` at all.
//
// Every other terminal is free. Adding a `hold=` or a second-button chord to
// one of the three above is a real behaviour change — it costs every move on
// that button the wait — and the test will say so by name.
//
// Priorities are DISTINCT across the whole table. A tie is only a defect where
// two moves share a terminal, but a globally unique number costs nothing and
// makes "did I just tie something" a question nobody has to answer by hand.
//============================================================================

// One authored move. The notation is the move; the name and the priority are
// its identity, carried through the parser untouched.
USTRUCT()
struct FCkTests_Intent_MoveRow
{
    UPROPERTY() FName _Name;
    UPROPERTY() FString _Notation;
    UPROPERTY() int32 _Priority = 0;

    FCkTests_Intent_MoveRow(FName InName = n"", FString InNotation = "", int32 InPriority = 0)
    {
        _Name = InName;
        _Notation = InNotation;
        _Priority = InPriority;
    }
}

// ====================================================================================================================

class UCkTests_Intent_MoveTable : UCk_DataAsset_PDA
{
    UPROPERTY()
    TArray<FCkTests_Intent_MoveRow> Rows;

    // The button vocabulary the bake resolves names against. It lives beside
    // the moves because a name only means something against a row that maps
    // it: split across two files they would drift, and the bake would reject
    // the whole set for a button somebody forgot to declare here.
    UPROPERTY()
    TArray<FName> ButtonNames;

    // Asset init bodies re-run on every AS recompile (the autotest wrapper
    // generator triggers one) and both declarations APPEND — without this the
    // table doubles on every reload and the count assertions go red for a
    // reason that has nothing to do with the moves.
    void Reset_Declarations()
    {
        Rows.Empty();
        ButtonNames.Empty();
    }

    void Declare_Button(FName InButtonName)
    {
        ButtonNames.Add(InButtonName);
    }

    void Declare_Move(FName InName, const FString& InNotation, int32 InPriority)
    {
        Rows.Add(FCkTests_Intent_MoveRow(InName, InNotation, InPriority));
    }
}

// ====================================================================================================================

namespace intent_moves
{
    // The test asserts the table's length against this, so a move added or
    // deleted without touching the count cannot pass unnoticed.
    const int32 k_MoveCount = 40;

    // `Charge_HP`'s declared hold, in logic frames. It appears in the notation
    // string below as text — the string is the authoring surface and stays
    // literal — and the test asserts the BAKED verdict against this constant,
    // which is what pins the two together.
    const int32 k_ChargeHoldFrames = 45;

    asset MoveTable_FortyMove of UCkTests_Intent_MoveTable
    {
        Reset_Declarations();

        //--------------------------------------------------------------------
        // The button vocabulary
        //--------------------------------------------------------------------

        Declare_Button(n"LP");
        Declare_Button(n"MP");
        Declare_Button(n"HP");
        Declare_Button(n"LK");
        Declare_Button(n"MK");
        Declare_Button(n"HK");
        Declare_Button(n"Guard");
        Declare_Button(n"Taunt");

        //--------------------------------------------------------------------
        // Quarter-circle forward — the canonical motion, once per button
        //--------------------------------------------------------------------

        Declare_Move(n"Qcf_LP", "236+LP", 900);
        Declare_Move(n"Qcf_MP", "236+MP", 890);
        Declare_Move(n"Qcf_HP", "236+HP", 880);
        Declare_Move(n"Qcf_LK", "236+LK", 870);
        Declare_Move(n"Qcf_MK", "236+MK", 860);

        //--------------------------------------------------------------------
        // Quarter-circle back
        //--------------------------------------------------------------------

        Declare_Move(n"Qcb_LP", "214+LP", 850);
        Declare_Move(n"Qcb_MP", "214+MP", 840);
        Declare_Move(n"Qcb_MK", "214+MK", 830);

        //--------------------------------------------------------------------
        // Dragon punch — a motion that doubles back on itself
        //--------------------------------------------------------------------

        Declare_Move(n"Dp_LP", "623+LP", 820);
        Declare_Move(n"Dp_MP", "623+MP", 810);
        Declare_Move(n"Dp_MK", "623+MK", 800);

        //--------------------------------------------------------------------
        // Half circles — five-digit runs, both directions
        //--------------------------------------------------------------------

        Declare_Move(n"Hcf_MP", "41236+MP", 790);
        Declare_Move(n"Hcb_MP", "63214+MP", 780);
        Declare_Move(n"Hcf_MK", "41236+MK", 770);
        Declare_Move(n"Hcb_MK", "63214+MK", 760);

        //--------------------------------------------------------------------
        // Supers — doubled motions, each with the window it is playable in
        //--------------------------------------------------------------------

        Declare_Move(n"Super_Qcf_LP", "236236+LP w=30", 750);
        Declare_Move(n"Super_Qcb_MP", "214214+MP w=30", 740);
        Declare_Move(n"Super_Hcf_MK", "4123641236+MK w=45", 730);
        Declare_Move(n"Super_Dp_MP", "623623+MP w=36", 720);

        //--------------------------------------------------------------------
        // Charges — the terminal must be HELD. `Charge_HP` is the one the test
        // reads back, so its threshold is k_ChargeHoldFrames.
        //--------------------------------------------------------------------

        Declare_Move(n"Charge_HP", "HP hold=45", 710);
        Declare_Move(n"Guard_Hold", "Guard hold=30", 700);
        Declare_Move(n"Charge_Fwd_MK", "4 6+MK hold=20", 690);
        Declare_Move(n"Taunt_Long", "Taunt hold=60", 680);

        //--------------------------------------------------------------------
        // Chords — two buttons at once, and the direction+button kind that
        // looks like one and deliberately is not (a direction is state the row
        // already reports, so nothing is ever in flight for it).
        //--------------------------------------------------------------------

        Declare_Move(n"Chord_Kicks", "LK+HK", 670);
        Declare_Move(n"Chord_Throw", "MP+MK", 660);
        Declare_Move(n"Dir_Chord_MP", "6+MP", 650);
        Declare_Move(n"Chord_Salute", "Guard+Taunt", 640);

        //--------------------------------------------------------------------
        // Normals — a lone button is a whole move, and the rival every
        // motion above shares its terminal with
        //--------------------------------------------------------------------

        Declare_Move(n"Jab_LP", "LP", 630);
        Declare_Move(n"Strong_HP", "HP", 620);
        Declare_Move(n"Short_LK", "LK", 610);
        Declare_Move(n"Roundhouse_HK", "HK", 600);
        Declare_Move(n"Forward_MK", "MK", 590);
        Declare_Move(n"Guard_Tap", "Guard", 580);

        //--------------------------------------------------------------------
        // Lenient — moves that tolerate a stick passing through directions
        // they never named
        //--------------------------------------------------------------------

        Declare_Move(n"Lenient_Zigzag_LK", "2 4 6+LK lenient", 570);
        Declare_Move(n"Lenient_Hcf_HP", "41236+HP lenient", 560);
        Declare_Move(n"Lenient_Super_MK", "236236+MK lenient w=40", 550);
        Declare_Move(n"Lenient_Dash_MP", "6 6+MP lenient", 540);

        //--------------------------------------------------------------------
        // Windows — whitespace-separated steps under an explicit frame budget,
        // including the neutral `5` step a return-to-centre motion asks for
        //--------------------------------------------------------------------

        Declare_Move(n"Window_Tight_LP", "2 3 6+LP w=12", 530);
        Declare_Move(n"Window_Loose_LK", "236+LK w=60", 520);
        Declare_Move(n"Neutral_Return_MP", "2 5 8+MP w=24", 510);
    }
}
