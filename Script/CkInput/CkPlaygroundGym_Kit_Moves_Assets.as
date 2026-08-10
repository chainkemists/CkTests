// Language=angelscript

//============================================================================
// CK INPUT PLAYGROUND GYM — THE COMBAT KIT'S MOVE VOCABULARY
//============================================================================
//
// Four moves on two buttons, authored the way every other table in this project
// authors moves: a name, the notation STRING, and the priority that decides who
// wins a terminal they share. The grammar is the only thing that turns a string
// into a move, and a table carrying a pre-built shape beside the string would be
// a second dialect nothing could tell apart from an authored one.
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
// NO MOVE HERE DECLARES A TWO-BUTTON CHORD, so the chord cause reads zero on
// both terminals and the hold cause is the only thing making these buttons wait.
//
// THE THRESHOLD IS WRITTEN TWICE ON PURPOSE — literally in the notation, which is
// the authoring surface and stays literal, and as the constant below, which is
// what the pawn's charge counter quotes. A reader compares the two; neither one
// alone could pin the number.
//
// PRIORITIES ARE DISTINCT ACROSS THE WHOLE TABLE, and each hold OUTWEIGHS the tap
// it shares a terminal with — the same 900/890 over 600/590 shape the archived
// souls table used. A tie is only a defect where two moves share a terminal, but
// a table-unique number costs nothing and makes "did I just tie something" a
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

    // Three quarters of a second at the sampler's 60 Hz cadence. Long enough that
    // a player feels themselves holding rather than mistiming a click, short
    // enough that failing it costs nothing and the next attempt starts
    // immediately. Both buttons carry the SAME threshold here — this kit's two
    // families differ in what comes out, not in how long the wind-up is.
    const int32 k_ChargeHoldFrames = 45;

    // The table asserts nothing about its own length, but a kit that armed a set
    // with a move missing would be silently teaching the wrong law.
    const int32 k_MoveCount = 4;

    asset MoveTable_PlaygroundKit of UCkTests_Intent_MoveTable
    {
        Reset_Declarations();

        Declare_Button(n"L");
        Declare_Button(n"H");

        Declare_Move(k_Move_Light_Charge, "L hold=45", 900);
        Declare_Move(k_Move_Heavy_Charge, "H hold=45", 890);

        Declare_Move(k_Move_Light_Tap, "L", 600);
        Declare_Move(k_Move_Heavy_Tap, "H", 590);
    }
}
