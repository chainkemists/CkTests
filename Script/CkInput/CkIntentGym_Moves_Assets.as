// Language=angelscript

//============================================================================
// CK INTENT FIGHTING GYM — THE THREE STATIONS' MOVE VOCABULARIES
//============================================================================
//
// One table per station, authored exactly the way `CkIntent_Moves_Assets.as`
// authors the forty-move vocabulary: a name, the notation STRING, and the
// priority that decides who wins a terminal they share. Nothing here builds a
// move any other way — the grammar is the only thing that turns a string into a
// move, and a table carrying a pre-built shape beside the string would be a
// second dialect nothing could tell apart from an authored one.
//
// WHY THREE TABLES AND NOT ONE SLICE OF THE FORTY. Every verdict in a compiled
// set is derived from the WHOLE set: the deferral verdicts, the arbitration
// order and the priority tie check all read every intent at once. Each station
// asserts a different property of a different set, so each needs a set it wholly
// owns — a station asserting "this button defers for exactly the chord window"
// against a shared forty-move table would be asserting something about the other
// thirty-nine moves as well.
//
// TWO DEVICES MEANS TWO MOVES, NOT ONE MOVE ON TWO KEYS. A button name resolves
// to exactly one ButtonId, and two rows answering one name with different
// identities is a bake rejection (`ConflictingButtonRow`). So a move playable on
// pad and keyboard is declared twice under two names, and the panel reports
// whichever one the player's hands actually completed.
//
// PRIORITIES ARE DISTINCT ACROSS EACH TABLE. A tie is only a defect where two
// moves share a terminal, but a table-unique number costs nothing and makes "did
// I just tie something" a question nobody has to answer by hand.
//============================================================================

namespace intent_gym_moves
{
    //========================================================================
    // STATION 1 — the deferral-frame counter
    //========================================================================
    //
    // A quarter-circle-forward punch beside a BARE punch on the same button.
    // That pairing is the point: sharing a terminal is decided by what the
    // record already contains BEHIND the press, so neither move waits for
    // anything and the counter must read zero for both. A set carrying only the
    // motion would read zero too — and would prove nothing, because with one
    // candidate there is no ambiguity to have resolved.
    //
    // Neither move declares `hold=`, and neither terminal carries a second
    // BUTTON, so this table must stay free of both: adding either would cost
    // every move on that terminal the wait, and the counter would start reading
    // non-zero for a reason that has nothing to do with the law under test.

    const int32 k_DeferralCounter_MoveCount = 4;

    asset MoveTable_DeferralCounter of UCkTests_Intent_MoveTable
    {
        Reset_Declarations();

        Declare_Button(n"P");
        Declare_Button(n"PK");

        Declare_Move(n"Gym_Qcf_Punch_Pad",  "236+P",  900);
        Declare_Move(n"Gym_Punch_Bare_Pad", "P",      600);

        Declare_Move(n"Gym_Qcf_Punch_Key",  "236+PK", 890);
        Declare_Move(n"Gym_Punch_Bare_Key", "PK",     590);
    }

    //========================================================================
    // STATION 2 — deferred versus instant, side by side
    //========================================================================
    //
    // Two buttons whose presses are answered on completely different frames, in
    // one set, so the contrast cannot be an artifact of two different setups.
    //
    //   CA  terminates a move on its own AND completes a two-button chord, so a
    //       lone press might still be half of something and has to wait out the
    //       chord window. This is one of the exactly two ambiguities that reach
    //       FORWARD.
    //   SF  terminates a bare move and a MOTION that ends on the same button.
    //       Sharing a terminal reaches BACKWARD only, so the press is answered
    //       on its own frame.
    //
    // `Gym_Suffix_Motion` is never expected to be performed — it exists to make
    // SF a shared terminal. That is exactly the case the law is about, and it is
    // why the station is drivable with no stick at all.

    const int32 k_DeferredVsInstant_MoveCount = 4;

    asset MoveTable_DeferredVsInstant of UCkTests_Intent_MoveTable
    {
        Reset_Declarations();

        Declare_Button(n"CA");
        Declare_Button(n"CB");
        Declare_Button(n"SF");

        Declare_Move(n"Gym_Chord_Pair",     "CA+CB",  900);
        Declare_Move(n"Gym_Chord_Bare",     "CA",     600);

        Declare_Move(n"Gym_Suffix_Motion",  "236+SF", 890);
        Declare_Move(n"Gym_Suffix_Bare",    "SF",     590);
    }

    //========================================================================
    // STATION 3 — the near miss
    //========================================================================
    //
    // One quarter-circle under a deliberately TIGHT window, so a motion a player
    // performs at a comfortable pace runs out of frames before the walk finds
    // its first step. `lenient` is load-bearing: without it the walk would die
    // on the first neutral row as a contiguity break, and the station is about
    // the OTHER diagnosis — the input was there in spirit and the player was too
    // slow.
    //
    // The keyboard leg cannot ever match, because a keyboard moves no octant. It
    // is declared anyway: pressing it produces exactly the same WindowExhausted
    // near-miss the station is teaching, on a device with no stick attached.

    const int32 k_NearMiss_MoveCount = 2;

    asset MoveTable_NearMiss of UCkTests_Intent_MoveTable
    {
        Reset_Declarations();

        Declare_Button(n"NM");
        Declare_Button(n"NMK");

        Declare_Move(n"Gym_NearMiss_Qcf_Pad", "2 3 6+NM w=12 lenient",  900);
        Declare_Move(n"Gym_NearMiss_Qcf_Key", "2 3 6+NMK w=12 lenient", 890);
    }
}
