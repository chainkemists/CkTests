// Language=angelscript

//============================================================================
// CK INPUT PLAYGROUND GYM - THE COMBAT KIT'S MOVE VOCABULARY
//============================================================================
//
// Eight moves on four buttons, authored the way every other table in this
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
// never consulted - so the bare tap is not decoration, it is the second
// candidate the deferral law requires. It is also what comes out when the player
// lets go early, which is what makes a light attack and an abandoned charge the
// same event to the kit: a tap.
//
// THE COST OF THAT IS PAID BY THE TAP, ON PURPOSE. Declaring a hold sibling
// costs EVERY move on that button the wait (the CkIntent docs anti-pattern 22),
// so the light attack answers on release rather than on the press frame. That is
// the trade this kit is here to make visible: a chain whose first hit waits for
// the player's thumb, beside a charge that is only reachable because it does.
//
// ONE MOVE PER BUTTON PER KIND, NOT ONE PER DEVICE. The archived station tables
// declared each move twice because they were playable on a pad and a keyboard,
// and a button NAME resolves to exactly one identity - two rows answering one
// name with different keys is a bake rejection (`ConflictingButtonRow`). This kit
// is mouse-driven and has exactly one device, so each move is declared once.
//
// PRESS ORDER IS A SEQUENCE, NOT A CHORD. A chord absorbs a DELTA between its
// presses - the bake's chord window is exactly that tolerance - but its atoms
// are a SET, so `L+H` and `H+L` are the same step semantically and WHICH CAME
// FIRST is gone. Ordering is the thing these two moves exist to exercise, so
// they are two-step SEQUENCES with different terminals - `"L H"` ends on H,
// `"H L"` ends on L - which is also what keeps them cheap: sharing a terminal
// never defers, so neither combo costs the bare tap on its terminal a single
// frame of latency. `w=30` is the whole window, half a second at the sampler's
// cadence, and it is the number to steer if the combos feel tight.
//
// THE SPRINT COMBOS ARE REAL CHORDS, AND THEY COMPLETE ON THE PRESS ROW.
// `"W+R+L"` is one step of three buttons, and a chord terminal accepts partners
// that are merely still DOWN - so a W and a Shift already held for sprinting
// satisfy the chord on the mouse button's own press row, and within a row the
// chord is asked before the hold. That is what "attacks only while running"
// compiles to: both locomotion keys are chord members, so the move is
// unreachable standing still. The chord cause the sprints introduce on L and H
// (the bake's default window, 3 frames) is dominated by the hold cause both
// buttons already carried (10), so neither bare tap pays a single extra frame.
//
// W AND SHIFT ARE GRADED TERMINALS AND LOCOMOTION KEYS AT THE SAME TIME. That
// is a deliberate dual read, not a collision: the matcher's capture lives on
// the routed pipeline, and the pawn's movement poll reads the
// PlayerController's own key state, which no capture can starve. See the key
// ledger in Shared.as.
//
// THE THRESHOLD IS WRITTEN TWICE ON PURPOSE - literally in the notation, which is
// the authoring surface and stays literal, and as the constant below. A reader
// compares the two; neither one alone could pin the number. (The pawn's charge
// counter quotes a THIRD number, k_ChargeFullFrames - that one is display, not a
// verdict, and deliberately does not live here.)
//
// PRIORITIES ARE DISTINCT ACROSS THE WHOLE TABLE, and the order on each terminal
// is the order a press should be READ in: the most specific thing the player
// could have meant first. On each mouse button that is the sprint chord, then
// the two-step combo, then the charge, then the bare tap. A tie is only a
// defect where two moves share a terminal, but a
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
    const FName k_Move_Combo_WH = n"Kit_Combo_WH";

    // ~166ms at the sampler's 60 Hz cadence - the tap-versus-hold VERDICT point,
    // not the charge-up time. The first cut sat at 5 frames (~83ms) and PIE
    // disproved it: an ordinary mouse click lasts ~90-150ms, so the matcher
    // graded most single clicks as holds and a lone press came out as a special.
    // Ten frames clears the click-duration distribution, and a deliberate hold
    // still commits long before it LOOKS ripe. How long a charge takes to look
    // full is that different number, and it lives with the display that draws it
    // (the pawn's k_ChargeFullFrames).
    const int32 k_ChargeHoldFrames = 10;

    // Half a second at the same cadence: the whole-sequence window the two
    // ordered combos are given to arrive in. Wide enough that a deliberate
    // one-two is comfortably inside it, narrow enough that two unrelated attacks
    // a beat apart are not silently read as a combo.
    const int32 k_ComboWindowFrames = 30;

    // The table asserts nothing about its own length, but a kit that armed a set
    // with a move missing would be silently teaching the wrong law.
    const int32 k_MoveCount = 8;

    asset MoveTable_PlaygroundKit of UCkTests_Intent_MoveTable
    {
        Reset_Declarations();

        Declare_Button(n"L");
        Declare_Button(n"H");
        Declare_Button(n"W");
        Declare_Button(n"R");

        Declare_Move(k_Move_Combo_WL, "W+R+L", 960);
        Declare_Move(k_Move_Combo_WH, "W+R+H", 955);
        Declare_Move(k_Move_Combo_HL, "H L w=30", 950);
        Declare_Move(k_Move_Combo_LH, "L H w=30", 940);

        Declare_Move(k_Move_Light_Charge, "L hold=10", 900);
        Declare_Move(k_Move_Heavy_Charge, "H hold=10", 890);

        Declare_Move(k_Move_Light_Tap, "L", 600);
        Declare_Move(k_Move_Heavy_Tap, "H", 590);
    }
}
