// Language=angelscript

//============================================================================
// CK INTENT DEBUGGER GYM — THE FOUR STATIONS' MOVE VOCABULARIES
//============================================================================
//
// One table per station, authored exactly the way `CkIntent_Moves_Assets.as`
// authors the forty-move vocabulary and the two gyms next door author theirs: a
// name, the notation STRING, and the priority that decides who wins a terminal
// they share. Nothing here builds a move any other way — the grammar is the only
// thing that turns a string into a move, and a table carrying a pre-built shape
// beside the string would be a second dialect nothing could tell apart from an
// authored one.
//
// THIS GYM'S TABLES ARE SIZED FOR A VIEW, NOT FOR A LAW. The other two gyms pick
// the smallest set that can express the property they assert. These four are
// picked for what they put ON SCREEN in the debugger: one lane per intent on the
// timeline, one row per candidate in the resolution table, one entry per
// scanned candidate in the near-miss ring. A set twice this size would still be
// correct and would make every one of those views something a viewer has to
// read past rather than read.
//
// TWO DEVICES MEANS TWO MOVES, NOT ONE MOVE ON TWO KEYS — where a second device
// is declared at all. A button name resolves to exactly one ButtonId, and two
// rows answering one name with different identities is a bake rejection
// (`ConflictingButtonRow`). The two MOTION stations declare both legs because
// their exercise needs a stick and their keyboard leg is the deskless viewer's
// only way in; the two button-only stations declare one, for the key-budget
// reason recorded beside the key constants in `CkIntentGym_Shared.as`.
//
// PRIORITIES ARE DISTINCT ACROSS EACH TABLE. A tie is only a defect where two
// moves share a terminal, but a table-unique number costs nothing and makes "did
// I just tie something" a question nobody has to answer by hand.
//============================================================================

namespace intent_gym_debugger_moves
{
    //========================================================================
    // STATION 1 — timeline and episodes
    //========================================================================
    //
    // Both of the exactly two ambiguities that reach FORWARD, in one set, so a
    // viewer can open a deferral episode on demand from either cause and watch
    // the timeline's BLOCKED lane answer for it:
    //
    //   TA  ends a move on its own AND completes a two-button chord with TB, so
    //       a lone press might still be half of something that has not arrived.
    //       Chord cause, `k_ChordWindowFrames` frames.
    //   TH  carries a hold AND a bare tap, so the press cannot be answered when
    //       it lands. Hold cause, `k_Debugger_HoldFrames` frames.
    //
    // THE BARE RIVALS ARE LOAD-BEARING ON BOTH. A `hold=` on a terminal only one
    // intent ends on defers for nothing, and neither does a chord whose members
    // end nothing else — the verdict fires when two or more intents share the
    // terminal. Delete either rival and the station stops opening episodes at
    // all, silently.
    //
    // Four moves means four intent lanes on the timeline, which is the largest
    // number a viewer can hold beside two layer lanes and a BLOCKED lane.

    const int32 k_Timeline_MoveCount = 4;

    asset MoveTable_Debugger_Timeline of UCkTests_Intent_MoveTable
    {
        Reset_Declarations();

        Declare_Button(n"TA");
        Declare_Button(n"TB");
        Declare_Button(n"TH");

        Declare_Move(n"Gym_Dbg_Chord_Pair", "TA+TB",      900);
        Declare_Move(n"Gym_Dbg_Chord_Bare", "TA",         600);

        Declare_Move(n"Gym_Dbg_Hold_Full",  "TH hold=60", 890);
        Declare_Move(n"Gym_Dbg_Hold_Tap",   "TH",         590);
    }

    //========================================================================
    // STATION 2 — the layer stack and what masking does to it
    //========================================================================
    //
    // The set exists to be MASKED, so what matters about it is that it is
    // unremarkable: nothing here declares a hold and nothing carries a
    // second-button chord, so every press is answered on its own frame and any
    // silence a viewer sees is the mask rather than a wait.
    //
    // `Gym_Dbg_Mask_Motion` is never expected to be performed. It is here so the
    // terminal is SHARED, which is what gives the debugger's resolution table
    // two candidates to order and its layer-stack row a set worth summarising —
    // and sharing a terminal reaches backward only, so it costs the station's
    // press nothing.

    const int32 k_LayerStack_MoveCount = 2;

    asset MoveTable_Debugger_LayerStack of UCkTests_Intent_MoveTable
    {
        Reset_Declarations();

        Declare_Button(n"LM");

        Declare_Move(n"Gym_Dbg_Mask_Motion", "236+LM", 900);
        Declare_Move(n"Gym_Dbg_Mask_Move",   "LM",     600);
    }

    //========================================================================
    // STATION 3 — the octant sweep
    //========================================================================
    //
    // A direction-plus-button move and its bare rival, per device. The pairing is
    // what makes the sweep CHECKABLE: press the terminal while the stick reads
    // East and the East move is what comes out, press it anywhere else and the
    // bare one does — so the octant the panel and the rosette are both showing
    // is confirmed by which move the matcher actually built, not by a viewer
    // squinting at two pictures.
    //
    // A direction in a chord does NOT defer — only a second BUTTON does — so
    // both of these answer on the press frame, and the station asserts that zero
    // beside everything else it renders.

    const int32 k_Octant_MoveCount = 4;

    asset MoveTable_Debugger_Octant of UCkTests_Intent_MoveTable
    {
        Reset_Declarations();

        Declare_Button(n"OS");
        Declare_Button(n"OSP");

        Declare_Move(n"Gym_Dbg_Octant_East_Kb", "6+OS",  900);
        Declare_Move(n"Gym_Dbg_Octant_Bare_Kb", "OS",    600);

        Declare_Move(n"Gym_Dbg_Octant_East_Pad", "6+OSP", 890);
        Declare_Move(n"Gym_Dbg_Octant_Bare_Pad", "OSP",   590);
    }

    //========================================================================
    // STATION 4 — the near-miss corpus
    //========================================================================
    //
    // The same quarter-circle three times over one terminal, differing ONLY in
    // how many frames it is allowed. That is what fills the debugger's near-miss
    // list with rows a viewer can tell apart: one unhurried motion is scanned
    // against all three in priority order and produces three entries whose
    // `FramesExamined` differ by construction — the tight one gave up first, the
    // medium one read more rows before giving up, and the open one, bounded only
    // by what the ring still holds, is the one that matches and comes out.
    //
    // `lenient` is on all three, and it is load-bearing: without it the walk
    // would die on the first neutral row as a CONTIGUITY break, which is a
    // different diagnosis with a different fix and would make all three rows say
    // the same thing.
    //
    // The keyboard leg can never match — a keyboard moves no octant — and it is
    // declared anyway: pressing it produces exactly the same three-row corpus
    // with every row exhausted, on a device with no stick attached.

    const int32 k_NearMiss_MoveCount = 6;

    asset MoveTable_Debugger_NearMiss of UCkTests_Intent_MoveTable
    {
        Reset_Declarations();

        Declare_Button(n"NC");
        Declare_Button(n"NCP");

        Declare_Move(n"Gym_Dbg_Corpus_Tight_Kb",  "2 3 6+NC w=8 lenient",   900);
        Declare_Move(n"Gym_Dbg_Corpus_Medium_Kb", "2 3 6+NC w=20 lenient",  890);
        Declare_Move(n"Gym_Dbg_Corpus_Open_Kb",   "2 3 6+NC lenient",       880);

        Declare_Move(n"Gym_Dbg_Corpus_Tight_Pad",  "2 3 6+NCP w=8 lenient",  870);
        Declare_Move(n"Gym_Dbg_Corpus_Medium_Pad", "2 3 6+NCP w=20 lenient", 860);
        Declare_Move(n"Gym_Dbg_Corpus_Open_Pad",   "2 3 6+NCP lenient",      850);
    }
}
