// Language=angelscript

//============================================================================
// CK INPUT PLAYGROUND GYM — THE COMBAT KIT'S MOVE VOCABULARY
//============================================================================
//
// Seven moves on three buttons, authored the way every other table in this
// project authors moves: a name, the notation STRING, and the priority that
// decides who wins a terminal they share. The grammar is the only thing that
// turns a string into a move, and a table carrying a pre-built shape beside the
// string would be a second dialect nothing could tell apart from an authored
// one.
//
// EVERY HOLD HAS A BARE RIVAL, AND THE RIVAL IS WHAT MAKES THE HOLD REAL. A
// `hold=` on a terminal only ONE intent ends on defers for nothing: the verdict
// fires when two or more intents share the terminal and at least one declares a
// hold. A lone charge would be answered on its press frame with its threshold
// never consulted — so the bare tap is not decoration, it is the second
// candidate the deferral law requires. It is also what comes out when the player
// lets go early, which is what makes a light attack and an abandoned charge the
// same event to the kit: a tap.
//
// THE COST OF THAT IS PAID BY THE TAP, ON PURPOSE. Declaring a hold sibling
// costs EVERY move on that button the wait (CkIntent/CLAUDE.md anti-pattern 22),
// so the light attack answers on release rather than on the press frame. That is
// the trade this kit is here to make visible: a chain whose first hit waits for
// the player's thumb, beside a charge that is only reachable because it does.
//
// ONE MOVE PER BUTTON PER KIND, NOT ONE PER DEVICE. The archived station tables
// declared each move twice because they were playable on a pad and a keyboard,
// and a button NAME resolves to exactly one identity — two rows answering one
// name with different keys is a bake rejection (`ConflictingButtonRow`). This kit
// is mouse-driven and has exactly one device, so each move is declared once.
//
// PRESS ORDER IS A SEQUENCE, NOT A CHORD. `L then H` and `H then L` are two
// different combos, and a chord cannot express either of them: a chord's atoms
// are a SET, so `L+H` and `H+L` are the same step semantically and the order the
// player produced is gone. The two are therefore two-step SEQUENCES with
// different terminals — `"L H"` ends on H, `"H L"` ends on L — which is also
// what keeps them cheap: sharing a terminal never defers, so neither combo costs
// the bare tap on its terminal a single frame of latency. `w=30` is the whole
// window, half a second at the sampler's cadence, and it is the number to steer
// if the combos feel tight.
//
// THE DIRECTION COMBO IS A REAL CHORD, AND IT COMPLETES ON THE PRESS ROW.
// `"W+L"` is one step of two buttons, and a chord terminal accepts a partner
// that is merely still DOWN — so a W already held for locomotion satisfies the
// chord on L's own press row, and within a row the chord is asked before the
// hold. The chord cause it introduces on L (the bake's default window, 3 frames)
// is dominated by the hold cause L already carried (5), so the direction combo
// costs the light tap nothing either.
//
// W IS A GRADED TERMINAL AND A LOCOMOTION KEY AT THE SAME TIME. That is a
// deliberate dual read, not a collision: the matcher's capture lives on the
// routed pipeline, and the pawn's WASD poll reads the PlayerController's own key
// state, which no capture can starve. See the key ledger in Shared.as.
//
// THE THRESHOLD IS WRITTEN TWICE ON PURPOSE — literally in the notation, which is
// the authoring surface and stays literal, and as the constant below. A reader
// compares the two; neither one alone could pin the number. (The pawn's charge
// counter quotes a THIRD number, k_ChargeFullFrames — that one is display, not a
// verdict, and deliberately does not live here.)
//
// PRIORITIES ARE DISTINCT ACROSS THE WHOLE TABLE, and the order on each terminal
// is the order a press should be READ in: the most specific thing the player
// could have meant first. On L that is the direction chord, then the two-step
// combo, then the charge, then the bare tap; on H the combo, then the charge,
// then the tap. A tie is only a defect where two moves share a terminal, but a
// table-unique number costs nothing and makes "did I just tie something" a
// question nobody has to answer by hand.
//============================================================================

namespace playground_gym_kit_moves
{
    // The names the PAWN reads its completions back by. They live here rather
    // than as literals at the read site because the table and its reader are two
    // files and a literal in each is two places one rename has to reach.

    const FName k_Move_Light_Charge = n"Kit_Light_Charge";
    const FName k_Move_Heavy_Charge = n"Kit_Heavy_Charge";
    const FName k_Move_Light_Tap    = n"Kit_Light_Tap";
    const FName k_Move_Heavy_Tap    = n"Kit_Heavy_Tap";

    const FName k_Move_Combo_LH = n"Kit_Combo_LH";
    const FName k_Move_Combo_HL = n"Kit_Combo_HL";
    const FName k_Move_Combo_WL = n"Kit_Combo_WL";

    // ~83ms at the sampler's 60 Hz cadence — the tap-versus-hold VERDICT point,
    // not the charge-up time (maintainer tuning: the usual verdict threshold is
    // 70-80ms so the non-hold attack never feels sluggish). A crisp click releases
    // under it and answers as a tap almost immediately; any press that outlives it
    // IS a hold, so the tap's worst-case wait is bounded at five frames. How long
    // a charge takes to LOOK full is a different number and it lives with the
    // display that draws it (the pawn's k_ChargeFullFrames).
    const int32 k_ChargeHoldFrames = 5;

    // Half a second at the same cadence: the whole-sequence window the two
    // ordered combos are given to arrive in. Wide enough that a deliberate
    // one-two is comfortably inside it, narrow enough that two unrelated attacks
    // a beat apart are not silently read as a combo.
    const int32 k_ComboWindowFrames = 30;

    // The table asserts nothing about its own length, but a kit that armed a set
    // with a move missing would be silently teaching the wrong law.
    const int32 k_MoveCount = 7;

    asset MoveTable_PlaygroundKit of UCkTests_Intent_MoveTable
    {
        Reset_Declarations();

        Declare_Button(n"L");
        Declare_Button(n"H");
        Declare_Button(n"W");

        Declare_Move(k_Move_Combo_WL, "W+L", 960);
        Declare_Move(k_Move_Combo_HL, "H L w=30", 950);
        Declare_Move(k_Move_Combo_LH, "L H w=30", 940);

        Declare_Move(k_Move_Light_Charge, "L hold=5", 900);
        Declare_Move(k_Move_Heavy_Charge, "H hold=5", 890);

        Declare_Move(k_Move_Light_Tap, "L", 600);
        Declare_Move(k_Move_Heavy_Tap, "H", 590);
    }
}
