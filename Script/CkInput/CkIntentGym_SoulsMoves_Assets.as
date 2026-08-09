// Language=angelscript

//============================================================================
// CK INTENT SOULS GYM — THE THREE STATIONS' MOVE VOCABULARIES
//============================================================================
//
// One table per station, authored exactly the way `CkIntent_Moves_Assets.as`
// authors the forty-move vocabulary and `CkIntentGym_Moves_Assets.as` authors
// the fighting gym's three: a name, the notation STRING, and the priority that
// decides who wins a terminal they share. Nothing here builds a move any other
// way — the grammar is the only thing that turns a string into a move.
//
// EVERY TABLE CARRIES A BARE RIVAL BESIDE ITS HOLD, AND THAT IS LOAD-BEARING.
// A `hold=` on a terminal only ONE intent ends on defers for nothing: the
// verdict fires when two or more intents share the terminal and at least one
// declares a hold, so a lone charge would be answered on its press frame with
// its threshold never consulted. The bare tap is what makes the hold real, and
// it is also the move the player gets for letting go early — the two facts are
// the same fact, which is what the tap-vs-hold station is about.
//
// TWO DEVICES MEANS TWO MOVES, NOT ONE MOVE ON TWO KEYS. A button name resolves
// to exactly one ButtonId, and two rows answering one name with different
// identities is a bake rejection (`ConflictingButtonRow`). So each station
// declares its pair twice, and the panel reports whichever leg the player's
// hands actually completed.
//
// THE THRESHOLD IS WRITTEN TWICE ON PURPOSE — literally in the notation, which
// is the authoring surface, and as `intent_gym::k_Souls_*Frames`, which is what
// the panel asserts the BAKED verdict against. That is what pins the string to
// the number a viewer reads; neither one alone could.
//
// PRIORITIES ARE DISTINCT ACROSS EACH TABLE. A tie is only a defect where two
// moves share a terminal, but a table-unique number costs nothing and makes "did
// I just tie something" a question nobody has to answer by hand.
//============================================================================

namespace intent_gym_souls_moves
{
    //========================================================================
    // STATION 1 — a tap and a hold on one button
    //========================================================================
    //
    // The whole of the forward ambiguity, on the smallest set that can express
    // it. Neither move can be told from the other at the moment of the press —
    // the difference is entirely in what happens NEXT — so the press is held
    // pending and the two boundaries of that wait are what the panel grades:
    // let go early and the tap answers before the threshold, hold on and the
    // charge answers EXACTLY on it.
    //
    // No move here declares a second-button chord, so the chord cause reads zero
    // and the hold cause is the only thing making this button wait. That is what
    // lets the panel say which cause it is measuring.

    const int32 k_TapVsHold_MoveCount = 4;

    asset MoveTable_Souls_TapVsHold of UCkTests_Intent_MoveTable
    {
        Reset_Declarations();

        Declare_Button(n"TH");
        Declare_Button(n"THP");

        Declare_Move(n"Gym_Souls_Hold_Key", "TH hold=45",  900);
        Declare_Move(n"Gym_Souls_Tap_Key",  "TH",          600);

        Declare_Move(n"Gym_Souls_Hold_Pad", "THP hold=45", 890);
        Declare_Move(n"Gym_Souls_Tap_Pad",  "THP",         590);
    }

    //========================================================================
    // STATION 2 — the charge accumulator
    //========================================================================
    //
    // The same shape at two seconds instead of three quarters of one, because
    // the thing this station shows is only visible over a LONG wait: the press
    // sits `Pending` the whole way down, the countdown is real frames rather
    // than a flicker, and letting go and pressing again visibly starts the count
    // over rather than resuming it.
    //
    // The tap rival is the same load-bearing rival as station 1's. Here it also
    // does a second job: it is what comes out when a player abandons a charge,
    // so abandoning is a legible outcome rather than silence.

    const int32 k_Charge_MoveCount = 4;

    asset MoveTable_Souls_Charge of UCkTests_Intent_MoveTable
    {
        Reset_Declarations();

        Declare_Button(n"CH");
        Declare_Button(n"CHP");

        Declare_Move(n"Gym_SoulsCharge_Full_Key",  "CH hold=120",  900);
        Declare_Move(n"Gym_SoulsCharge_Quick_Key", "CH",           600);

        Declare_Move(n"Gym_SoulsCharge_Full_Pad",  "CHP hold=120", 890);
        Declare_Move(n"Gym_SoulsCharge_Quick_Pad", "CHP",          590);
    }

    //========================================================================
    // STATION 3 — the charge a menu ate
    //========================================================================
    //
    // A second and a half, which is the shortest threshold that still leaves a
    // player time to reach the menu key with the charge button already down.
    // The set is otherwise station 2's: the point is not the moves, it is what
    // happens to a live episode when a higher layer starts consuming the key
    // underneath it.
    //
    // The MENU key is deliberately absent from this table. It carries no move,
    // terminates nothing and is never baked — the station reads its press edge
    // off the record, which holds every claimed event regardless of who received
    // it, so opening the modal costs the set nothing and cannot be confused with
    // a move the player performed.

    const int32 k_DeliveryLoss_MoveCount = 4;

    asset MoveTable_Souls_DeliveryLoss of UCkTests_Intent_MoveTable
    {
        Reset_Declarations();

        Declare_Button(n"LS");
        Declare_Button(n"LSP");

        Declare_Move(n"Gym_SoulsLoss_Full_Key",  "LS hold=90",  900);
        Declare_Move(n"Gym_SoulsLoss_Quick_Key", "LS",          600);

        Declare_Move(n"Gym_SoulsLoss_Full_Pad",  "LSP hold=90", 890);
        Declare_Move(n"Gym_SoulsLoss_Quick_Pad", "LSP",         590);
    }
}
