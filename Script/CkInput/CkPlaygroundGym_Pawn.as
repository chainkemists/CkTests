// Language=angelscript

//============================================================================
// CK INPUT PLAYGROUND GYM — PAWN
//============================================================================
//
// The drivable body of the playground, controlled Diablo-style: a fixed top-down
// camera that only follows the pawn, WASD movement in screen space, and the mouse
// cursor as the aim pointer — the character always faces it. The camera never
// takes mouse or stick input.
//
// On ready it adds the camera director on the pawn entity (whose actor-synced
// transform is the camera anchor, so the framing follows the pawn; the view sink
// is this pawn's UCk_CameraComponent — the framework does not create one), pushes
// the top-down layer as the one and only view, spawns the floor, spawns the
// dummy, raises the combat kit's readouts, and emits the binding self-check
// below.
//
// ADefaultPawn has no in-game mesh, so the body is assembled here: a cylinder trunk between two sphere caps
// (a ~90cm capsule silhouette) plus a forward nose cube for facing. Visual only — no collision.
//
// BINDING SELF-CHECK. Two shapes are emitted on spawn and are expected to behave on a fixed schedule: an
// immediate-mode DebugDraw sphere that expires on its own after 5s, and a persistent PMG child entity that
// recolors at 1s, hides at 2s, and is destroyed at 3s. They exist so a broken binding shows up as visibly
// wrong geometry the moment the gym opens, rather than as a silent no-op inside a later exercise.
//
//----------------------------------------------------------------------------
// THE COMBAT KIT
//----------------------------------------------------------------------------
//
// Everything below the aim update is a CONSUMER of CkIntent, not an extension of
// it. The matcher grades exactly eight things — a light tap, a light charge, the
// same pair on the heavy button, and four combos — and every chain, buffer,
// charge and special a viewer watches happen is game state owned by this file,
// driven by polling those completions. That is the shape a real consumer has and
// the shape the module's doc prescribes: poll the completion FRAME, act once,
// never branch on a latched phase (CkIntent/CLAUDE.md anti-pattern 15).
//
// ONE MACHINE, FIFTEEN STATES. Idle, three light steps, three heavy steps, two
// charges, two specials and four combos all live in one `_State`. A second flag
// mirroring "am I attacking" would be a second answer to a question that has one.
//
// THE ATTACK LENGTHS ARE THIS FILE'S OWN NUMBERS. No notation quotes them, the
// matcher never sees them, and nothing is graded against them — they are how long
// this kit's swings last. They are UNEQUAL on purpose: a chain whose third hit
// visibly outlives its first reads as three moves rather than one repeated.
//
// EVERY CHAIN STEP IS PHASED: a wind-up nothing comes out of (20%), then the
// strike. The swing is a PMG entity spawned where the wind-up ENDS, with the
// active-plus-wind-down remainder as its duration: it counts itself down and
// destroys itself on the same tick the state expires, so the two cannot drift,
// and the swings are never tracked. The CHAIN WINDOW is everything after the
// wind-up, the buffer answers the PRESS row rather than the completion, and a
// step that expires unbuffered leaves a short grace window where a late tap
// still chains (the wind-up/attack/wind-down model). Four persistent shapes have no such clock — the charge
// accumulator, the buffered marker, the block plate, and the two readout lines —
// and those are the ones this file owns and destroys.
//
// COMBOS ARE PHASE-EXEMPT, LIKE THE SPECIALS, AND FOR THE SAME REASON: the
// sequence the player already produced WAS the wind-up, so the strike comes out
// on the frame the completion is read. A combo also SUPERSEDES whatever the
// machine was doing — it clears the chain step, its buffer and its grace window
// — because a combo is what the player meant by the presses a chain would
// otherwise have read one at a time.
//
// THE CHARGE ACCUMULATOR IS DISPLAY, AND THE CODE SAYS SO WHERE IT READS IT. It
// is driven by the RECORD's held rows — the physical fact, which keeps counting
// through anything — and it never grades an outcome. The matcher's accumulator is
// the policy-applied count, it is not readable, and a consumer that graded from
// its own timer would agree with the module right up until the frame it mattered
// (anti-pattern 23). The RELEASE that fires a special is read the same way: the
// button is no longer in the record's held set, which is a fact about this frame.
//
// PMG HAS NO SIZE MUTATION, so a shape that grows or follows the pawn is a
// persistent entity re-transformed every tick through its own Transform fragment
// (CkPmg/Claude.md, "Pattern: live-tracking overlay").
//
// THE MOUSE BUTTONS ARE UNPROVEN THROUGH THIS STACK. Nothing upstream has ever
// carried a real LeftMouseButton event to a matcher, so the readouts render with
// ZERO input and quote the last press frame and held run of both buttons: a dead
// button has to look different from a dead kit.
//
//----------------------------------------------------------------------------
// THE DUMMY, AND THE BLOCK
//----------------------------------------------------------------------------
//
// SOMETHING TO HIT. A swing thrown at empty floor looks the same whether it
// connects or not, so the pawn spawns one dummy 800cm along world +X from its own
// spawn point (UCk_EntityScript_PlaygroundGym_Enemy) and tests every swing
// against it. THE DRAWN SHAPE IS THE HITBOX: the swing arms a hit window at the
// shape's own world position for the shape's own lifetime, tested every tick as
// a planar distance from that centre — its extent plus a hand's-width of padding
// — and it lands at most once. A shape the player can watch standing over the
// dummy MUST connect, however late in the step the two came together; the old
// at-spawn-only test missed exactly that, and an arc test is not needed at all
// once the test is centred on the shape rather than on the pawn.
//
// BLOCK IS A HELD SET, NOT A MOVE, AND THAT IS THE WHOLE POINT. Q is minted into
// the button map so the record carries a row for it, and no move table names it —
// so the block is read off the newest row's held set rather than graded by the
// matcher. Eight moves that are notation compiled into a set, beside one state
// that is a fact about a row: the contrast is the exercise, and the deleted sekiro
// station demonstrated the same pair.
//
// BLOCKING IS INDEPENDENT OF THE ATTACK MACHINE. `_State` is not consulted to
// raise the plate and is not changed by raising it, so a block can go up mid-chain
// and a chain can start with the plate up. That is a DECISION, not an oversight:
// the two systems answer different questions (what did the matcher grade, and
// what is the record reporting held right now), and coupling them would make the
// held read look like a move with priority rules.
//
// THE PAWN HAS NO HEALTH. A projectile that reaches the pawn is answered with
// STRUCK, BLOCKED or PARRIED and nothing else — no damage, no state change, no
// stagger. The dummy renders nothing at the point of resolution; the verdict is
// a fact about this pawn's input, it is drawn on this pawn, and the dummy only
// ACTS on the answer handed back (a parried shot flies home).
//============================================================================

namespace playground_gym_kit
{
    //------------------------------------------------------------------------
    // The machine
    //------------------------------------------------------------------------

    const int32 k_State_Idle           = 0;
    const int32 k_State_Light1         = 1;
    const int32 k_State_Light2         = 2;
    const int32 k_State_Light3         = 3;
    const int32 k_State_Heavy1         = 4;
    const int32 k_State_Heavy2         = 5;
    const int32 k_State_Heavy3         = 6;
    const int32 k_State_Charging_Light = 7;
    const int32 k_State_Charging_Heavy = 8;
    const int32 k_State_Special_Light  = 9;
    const int32 k_State_Special_Heavy  = 10;

    // One state per combo rather than one Combo state carrying which-one beside
    // it: the two specials are already two states for the same reason, and the
    // floor label reads the name straight off `_State` instead of off a second
    // value that could disagree with it.
    const int32 k_State_Combo_LH = 11;
    const int32 k_State_Combo_HL = 12;
    const int32 k_State_Combo_WL = 13;
    const int32 k_State_Combo_WH = 14;

    // The two families, as one value. A tap, a charge, a chain step and a special
    // all have to say which side of the kit they belong to, and three bools would
    // be three places one answer could disagree with itself.
    const int32 k_Family_None  = 0;
    const int32 k_Family_Light = 1;
    const int32 k_Family_Heavy = 2;

    //------------------------------------------------------------------------
    // Locomotion
    //------------------------------------------------------------------------
    //
    // Two speeds, polled every tick off Shift: the sprint is a real locomotion
    // state, not a flag the combos invent — the sprint attacks exist only while
    // both W and Shift are down, and a sprint that did not MOVE faster would
    // make that condition invisible. Walk is half of ADefaultPawn's stock 1200,
    // which read as a sprint at this framing.

    const float32 k_MoveSpeed_Walk   = 600.0f;
    const float32 k_MoveSpeed_Sprint = 1000.0f;

    //------------------------------------------------------------------------
    // How long a swing lasts
    //------------------------------------------------------------------------
    //
    // Seconds, because a PMG duration is seconds and the identity between the two
    // is the design. One length per family, maintainer-tuned LONG: the step is
    // the window the next press buffers into, so its length is the time the
    // player is given to queue the follow-up, and the families' 2x split is the
    // whole difference between them to play.

    const float32 k_Duration_Light1 = 2.00f;
    const float32 k_Duration_Light2 = 2.00f;
    const float32 k_Duration_Light3 = 2.00f;

    const float32 k_Duration_Heavy1 = 4.00f;
    const float32 k_Duration_Heavy2 = 4.00f;
    const float32 k_Duration_Heavy3 = 4.00f;

    const float32 k_Duration_Special_Light = 0.80f;
    const float32 k_Duration_Special_Heavy = 1.20f;

    // One length for all four combos: what tells them apart is which inputs
    // produced them and what colour comes out, not how long they stand.
    const float32 k_Duration_Combo = 0.70f;

    //------------------------------------------------------------------------
    // The phases (maintainer's model: wind-up, attack, wind-down)
    //------------------------------------------------------------------------
    //
    // Every chain step opens with a wind-up nothing comes out of: the swing shape
    // spawns where the wind-up ENDS, so cancelling into a charge during it costs
    // no strike, and the hit lands when the strike is visible rather than on the
    // press. The wind-up is ANIMATION, not an input gate: the chain window is the
    // whole step from its entry row, because a double-click's second press lands
    // ~50-100ms after the first click's release — inside any wind-up measured
    // from the entry the release caused — and the maintainer's ruling is that it
    // chains. A press completing just after the step expired still chains through
    // the grace window instead of resetting to step 1: "almost chained" has to
    // read as a chain, not as a fresh opener.
    //
    // Specials have no wind-up — the charge the player just sat through WAS the
    // wind-up. Neither do combos: the sequence was.

    const float32 k_Phase_WindUpFraction = 0.20f;

    const int32 k_ChainGraceFrames = 10;

    //------------------------------------------------------------------------
    // Where a swing lands
    //------------------------------------------------------------------------
    //
    // Ahead of the pawn along its ACTOR FORWARD, which is the cursor aim: the
    // facing a player is steering with is the facing the attack comes out on, and
    // reading the two as one thing is the point of aiming with the mouse.

    const float32 k_Attack_ForwardOffset = 160.0f;
    const float32 k_Attack_SpecialForwardOffset = 215.0f;
    const float32 k_Attack_Height = 60.0f;

    const float32 k_Extent_Light1 = 45.0f;
    const float32 k_Extent_Light2 = 60.0f;
    const float32 k_Extent_Light3 = 80.0f;

    const float32 k_Extent_Heavy1 = 60.0f;
    const float32 k_Extent_Heavy2 = 80.0f;
    const float32 k_Extent_Heavy3 = 100.0f;

    const float32 k_Extent_Special_Light = 120.0f;
    const float32 k_Extent_Special_Heavy = 150.0f;

    // Bigger than anything either family throws, including the heavy special: a
    // combo is the most the kit can be asked for, and it has to look like it.
    const float32 k_Extent_Combo = 170.0f;

    // The sprint attacks are AREA moves: a flat ring around the pawn rather than
    // a box along the aim, because an attack thrown at a run has no aim to speak
    // of — the commitment is the sprint, and the payoff is everything nearby.
    const float32 k_Extent_SprintAoE = 300.0f;

    //------------------------------------------------------------------------
    // Landing it on something
    //------------------------------------------------------------------------
    //
    // The hit window IS the drawn shape: same centre, its extent plus the
    // padding, alive exactly as long as the shape is. Tested every tick and
    // landing at most once, so walking the dummy into a standing swing connects
    // and one swing never counts twice. The padding is the one number that is
    // not derived from the shape: a target whose own body is 60cm wide has to be
    // hittable when the box stops just short of its centre.

    const float32 k_HitTest_Padding = 70.0f;

    // Far enough that the arena reads as having somewhere to walk to, close enough
    // that the dummy is in the first screenful. World +X, on the floor: the floor
    // slab's walkable surface sits at the pawn's own spawn height.
    const float32 k_Enemy_SpawnForwardOffset = 800.0f;

    //------------------------------------------------------------------------
    // The charge accumulator
    //------------------------------------------------------------------------
    //
    // A persistent sphere on the pawn, re-transformed every tick. The scale runs
    // from a visible floor at zero frames to full size at the threshold, which is
    // what makes "full" and "it fired" the same instant to look at. The ceiling is
    // defensive: the run keeps climbing after the charge completes and the player
    // is still holding, and an unclamped ratio would grow without bound.

    const float32 k_ChargeScale_Min = 0.25f;
    const float32 k_ChargeScale_Max = 2.50f;

    const float32 k_ChargeRadius   = 50.0f;
    const int32   k_ChargeSegments = 16;
    const int32   k_ChargeRings    = 16;
    const float32 k_ChargeHeight   = 50.0f;

    // How long a charge takes to LOOK full — display only, and deliberately a
    // different number from the move table's hold=10 verdict point: the verdict
    // says "this press is a hold", this says "the hold has ripened". The counter
    // quotes it and the sphere saturates at it; nothing grades against it.
    const int32 k_ChargeFullFrames = 45;

    //------------------------------------------------------------------------
    // The block plate
    //------------------------------------------------------------------------
    //
    // A translucent plate held out along the ACTOR FORWARD — the cursor aim, so
    // the block covers the direction the player is looking at, exactly like the
    // swings do. A YZ plane's normal runs along the shape's own forward, so the
    // actor rotation is what turns the plate to face outward.
    //
    // It is a persistent shape re-transformed every tick and destroyed the frame
    // the button leaves the record's held set: PMG has no parenting, so a shape
    // that follows the pawn is a transform driven per tick, and a plate that
    // outlived the hold would be a block the record no longer reports.

    const float32 k_Block_ForwardOffset = 70.0f;
    const float32 k_Block_Height        = 70.0f;
    const float32 k_Block_Width         = 130.0f;
    const float32 k_Block_PlateHeight   = 110.0f;

    //------------------------------------------------------------------------
    // The single-frame beat
    //------------------------------------------------------------------------
    //
    // A completion arriving is a "right now", so it is a DebugDraw call at
    // duration zero rather than a PMG entity. One tick at 60 Hz is 16ms, which is
    // a flash nobody can confirm they saw, so the same one-frame call is re-issued
    // for a fifth of a second.

    const int32   k_BeatTicks     = 12;
    const float32 k_BeatRadius    = 34.0f;
    const int32   k_BeatSegments  = 12;
    const float32 k_BeatThickness = 3.0f;
    const float32 k_BeatHeight    = 30.0f;

    // A projectile resolving is the same kind of "right now", drawn with the same
    // primitive on the same schedule — at the PLATE when it was blocked or
    // parried, on the pawn's own body when it was not.
    const int32   k_ProjectileBeatTicks  = 12;
    const float32 k_ProjectileBeatRadius = 42.0f;

    // A PARRY is a block that BARELY started: at impact, the record answers how
    // long Q has been down, and a run inside this window is a read of the
    // incoming shot rather than a wall the player was already hiding behind. Q
    // stays verdict-free in the grammar (no move terminates on it), so the press
    // registers the row it lands — the window is judged at IMPACT, adding zero
    // latency to the block itself. ~133ms; the number to steer for parry feel.
    const int32 k_ParryWindowFrames = 8;

    const float32 k_ParryBeatRadius = 64.0f;

    const int32 k_ProjectileVerdict_Struck  = 0;
    const int32 k_ProjectileVerdict_Blocked = 1;
    const int32 k_ProjectileVerdict_Parried = 2;

    //------------------------------------------------------------------------
    // The buffered marker
    //------------------------------------------------------------------------
    //
    // The queued input, made visible while it waits — the sekiro station's
    // precedent, shrunk to a hint over the pawn's head. Small and dim on purpose:
    // it is a promise about the next attack, not an attack.

    const float32 k_Buffer_Radius   = 16.0f;
    const int32   k_Buffer_Segments = 10;
    const int32   k_Buffer_Rings    = 10;
    const float32 k_Buffer_Height   = 145.0f;

    //------------------------------------------------------------------------
    // The palette
    //------------------------------------------------------------------------
    //
    // Cyan is light, orange is heavy, all the way through: a viewer never has to
    // work out which button a shape belongs to. Within a family the alpha climbs
    // with the chain step, and the special is the brightest thing the kit draws.
    //
    // The block is steel blue and belongs to neither family, because it is not a
    // move: a plate in either family's colour would read as a third attack.
    //
    // The four combos are OFF both family ramps for the same reason — a combo is
    // not a louder light or a louder heavy, it is the third thing the kit can be
    // asked for — and they are three different hues rather than three alphas of
    // one, because which combo landed is the whole question a viewer has about
    // them.

    const FLinearColor k_Colour_Light1  = FLinearColor(0.35f, 0.85f, 1.00f, 0.55f);
    const FLinearColor k_Colour_Light2  = FLinearColor(0.30f, 0.90f, 1.00f, 0.65f);
    const FLinearColor k_Colour_Light3  = FLinearColor(0.25f, 0.95f, 1.00f, 0.75f);
    const FLinearColor k_Colour_Heavy1  = FLinearColor(1.00f, 0.55f, 0.15f, 0.55f);
    const FLinearColor k_Colour_Heavy2  = FLinearColor(1.00f, 0.50f, 0.10f, 0.65f);
    const FLinearColor k_Colour_Heavy3  = FLinearColor(1.00f, 0.45f, 0.05f, 0.75f);

    const FLinearColor k_Colour_Special_Light = FLinearColor(0.60f, 1.00f, 1.00f, 0.90f);
    const FLinearColor k_Colour_Special_Heavy = FLinearColor(1.00f, 0.80f, 0.35f, 0.90f);

    const FLinearColor k_Colour_Combo_LH = FLinearColor(0.70f, 0.35f, 1.00f, 0.85f);
    const FLinearColor k_Colour_Combo_HL = FLinearColor(1.00f, 0.30f, 0.75f, 0.85f);
    const FLinearColor k_Colour_Combo_WL = FLinearColor(0.35f, 1.00f, 0.55f, 0.85f);
    const FLinearColor k_Colour_Combo_WH = FLinearColor(0.20f, 0.85f, 0.45f, 0.85f);

    const FLinearColor k_Colour_ChargeGrow_Light = FLinearColor(0.30f, 0.90f, 1.00f, 0.45f);
    const FLinearColor k_Colour_ChargeGrow_Heavy = FLinearColor(1.00f, 0.55f, 0.15f, 0.45f);

    const FLinearColor k_Colour_Buffer      = FLinearColor(1.00f, 0.70f, 0.15f, 0.35f);
    const FLinearColor k_Colour_Beat_Acted  = FLinearColor(0.90f, 1.00f, 0.70f, 1.00f);
    const FLinearColor k_Colour_Beat_Ignored = FLinearColor(0.45f, 0.45f, 0.50f, 1.00f);

    const FLinearColor k_Colour_Block   = FLinearColor(0.35f, 0.60f, 0.90f, 0.35f);
    const FLinearColor k_Colour_Blocked = FLinearColor(0.40f, 1.00f, 1.00f, 1.00f);
    const FLinearColor k_Colour_Parried = FLinearColor(1.00f, 0.85f, 0.20f, 1.00f);
    const FLinearColor k_Colour_Struck  = FLinearColor(1.00f, 0.25f, 0.25f, 1.00f);

    //------------------------------------------------------------------------
    // The readouts
    //------------------------------------------------------------------------
    //
    // Two lines lying FLAT ON THE FLOOR behind the character (the camera side),
    // re-anchored every tick — PMG has no parenting, so a shape that follows
    // something is a persistent entity whose transform is driven (CkPmg/Claude.md,
    // "Pattern: live-tracking overlay").
    //
    // Floor text is the right surface for this camera: at -65 a ground plate is
    // viewed nearly face-on, where an upright plate pays the whole view angle and
    // flat XY-authored text reads from BELOW only (wireframe glyphs are visible
    // from both sides but readable from exactly one — the other side is the mirror
    // the first two attempts hit). The transform is therefore derived, not
    // authored: take the YZ plate orientation that reads correctly facing the
    // camera, then tip its top edge away from the viewer until it lies flat — the
    // readable side stays the visible side through the whole tilt, so no flip can
    // occur. That composes to FRotator(-90, CameraYaw, 0) on a YZ plate. Derived
    // off the CAMERA, never the pawn: the pawn spins with the cursor, and a label
    // that spun with it would be unreadable exactly while aiming.
    //
    // The upper line is the STATE. The lower one is the INPUT, and it exists
    // because the two mouse buttons are unproven through this stack: it quotes
    // both buttons' last press frame and held run whether or not anything has ever
    // landed, so "the kit is broken" and "the button never arrived" are two
    // different pictures. Q's held run is on the same line for the same reason —
    // a block that never rises has to be diagnosable as a dead key rather than as
    // a dead plate.

    const float32 k_Label_StateBehindOffset = 150.0f;
    const float32 k_Label_StateSize         = 52.0f;

    const float32 k_Label_InputBehindOffset = 215.0f;
    const float32 k_Label_InputSize         = 28.0f;

    // Just proud of the slab so the glyph lines never z-fight with it.
    const float32 k_Label_FloorLift = 3.0f;

    const float32 k_Label_LineThickness = 2.0f;

    const FLinearColor k_Colour_Label_Idle    = FLinearColor(0.55f, 0.58f, 0.62f, 0.90f);
    const FLinearColor k_Colour_Label_Light   = FLinearColor(0.35f, 0.90f, 1.00f, 1.00f);
    const FLinearColor k_Colour_Label_Heavy   = FLinearColor(1.00f, 0.60f, 0.20f, 1.00f);
    const FLinearColor k_Colour_Label_Buffer  = FLinearColor(1.00f, 0.80f, 0.25f, 1.00f);
    const FLinearColor k_Colour_Label_Broken  = FLinearColor(1.00f, 0.30f, 0.30f, 1.00f);
    const FLinearColor k_Colour_Label_Input   = FLinearColor(0.70f, 0.75f, 0.80f, 0.95f);

    // One colour for all four combos, because the LINE already names which one
    // landed — the colour only has to say "this was a combo, not a chain step".
    const FLinearColor k_Colour_Label_Combo   = FLinearColor(0.85f, 0.55f, 1.00f, 1.00f);

    const FString k_LabelText_Idle = "IDLE";

    const FString k_LabelText_Combo_LH = "COMBO L-H";
    const FString k_LabelText_Combo_HL = "COMBO H-L";
    const FString k_LabelText_Combo_WL = "SPRINT ATTACK L";
    const FString k_LabelText_Combo_WH = "SPRINT ATTACK H";

    const float32 k_ShapeLineThickness = 2.0f;
}

// --------------------------------------------------------------------------------------------------------------------

class ACk_PlaygroundGym_Pawn : ACk_Gym_Base_Pawn
{
    // ADefaultPawn's built-in WASD + mouse-look move along / pitch the hidden control rotation, which a fixed
    // camera never reads. Movement is polled in Tick instead; the mouse aims the character, never the camera.
    default bAddDefaultMovementBindings = false;

    UPROPERTY(DefaultComponent)
    UStaticMeshComponent BodyMesh;

    UPROPERTY(DefaultComponent)
    UStaticMeshComponent CapTopMesh;

    UPROPERTY(DefaultComponent)
    UStaticMeshComponent CapBottomMesh;

    UPROPERTY(DefaultComponent)
    UStaticMeshComponent NoseMesh;

    // The camera director's required output sink: the default PlayerCameraManager resolves the view target's
    // active camera component and pulls the composed view through its GetCameraView override.
    UPROPERTY(DefaultComponent)
    UCk_CameraComponent CameraComponent;

    private FCk_Handle        _PawnEntity;
    private FCk_Handle_Camera _Camera;

    private FCk_Handle_Pmg_DebugShape _SelfCheckShape;
    private float32                   _SelfCheckElapsed = 0.0f;
    private int32                     _SelfCheckStage   = 0;

    // The kit's own input layer and the matcher composed on it. The layer is what
    // decides which events the set is even allowed to see, so it is created here
    // rather than inherited from anything (CkIntent/CLAUDE.md anti-pattern 16).
    private FCk_Handle_InputLayer     _Layer;
    private FCk_Handle_IntentMatcher  _Matcher;
    private bool                      _SwapRequested = false;
    private bool                      _SetRejected   = false;

    // One record per move, not one shared: the freshness test is a completion
    // frame comparison and a sibling's older latch is a different frame, so a
    // shared record would read it as a landing every time a newer move replaced it.
    private FCkPlaygroundGym_Attempt _Attempt_LightTap;
    private FCkPlaygroundGym_Attempt _Attempt_HeavyTap;
    private FCkPlaygroundGym_Attempt _Attempt_LightCharge;
    private FCkPlaygroundGym_Attempt _Attempt_HeavyCharge;
    private FCkPlaygroundGym_Attempt _Attempt_ComboLH;
    private FCkPlaygroundGym_Attempt _Attempt_ComboHL;
    private FCkPlaygroundGym_Attempt _Attempt_ComboWL;
    private FCkPlaygroundGym_Attempt _Attempt_ComboWH;

    private int32   _State = playground_gym_kit::k_State_Idle;
    private float32 _StateSecondsRemaining = 0.0f;

    // A single slot. A second press during a step queues the next one; a third has
    // nothing left to say, so it is dropped rather than deepening a queue the
    // chain could never spend.
    private bool _BufferedNext = false;

    // The current chain step's phase bookkeeping: total length (elapsed is derived
    // from it and the remaining), the record frame the step was entered on (the
    // frame a chain press has to beat — only the step's OWN initiating press
    // predates it), and the swing stashed until the wind-up has been served. A
    // charge landing mid-wind-up leaves _SwingSpawned false and the strike never
    // comes out — a cancelled attack costs no shape.
    private float32 _StateTotalSeconds = 0.0f;
    private int32   _StepEntryFrame    = -1;
    private bool    _SwingSpawned      = true;

    private int32        _PendingSwing_Family = 0;
    private float32      _PendingSwing_Extent = 0.0f;
    private FLinearColor _PendingSwing_Colour;

    // The live hit window — the drawn shape's centre and reach, counting down the
    // shape's own lifetime. One at a time: a new swing replaces whatever window
    // was still open, exactly as its state replaced the old state.
    private float32 _Hitbox_SecondsRemaining = 0.0f;
    private FVector _Hitbox_Centre           = FVector::ZeroVector;
    private float32 _Hitbox_Reach            = 0.0f;
    private bool    _Hitbox_Landed           = true;

    // The grace window: for a few frames after a step expires unbuffered, a
    // same-family tap continues the chain instead of opening a new one.
    private int32 _GraceUntilFrame = -1;
    private int32 _GraceFamily     = 0;
    private int32 _GraceNextStep   = 0;

    // The dummy registers itself once it has found this pawn (it is spawned from
    // Request_OnPawnReady but constructs on its own schedule). Nothing here waits
    // for it: an unregistered dummy is a swing that lands on nothing, which is
    // exactly what the playground did before there was one.
    private UCk_EntityScript_PlaygroundGym_Enemy _Enemy;

    private FCk_Handle_Pmg_DebugShape _ChargeShape;
    private FCk_Handle_Pmg_DebugShape _BufferMarker;
    private FCk_Handle_Pmg_DebugShape _BlockPlate;
    private FCk_Handle_Pmg_DebugShape _StateLabel;
    private FCk_Handle_Pmg_DebugShape _InputLabel;

    private int32 _BeatTicksRemaining = 0;
    private bool  _BeatWasActedOn = false;

    private int32 _ProjectileBeatTicksRemaining = 0;
    private int32 _ProjectileBeatVerdict = 0;

    UFUNCTION(BlueprintOverride)
    void ConstructionScript()
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Cylinder = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Cylinder.Cylinder"));
        auto Sphere   = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Sphere.Sphere"));
        auto Cube     = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Cube.Cube"));
        auto Mat      = Cast<UMaterialInterface>(LoadObject(this, "/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));

        // 40cm-wide trunk 50cm tall between two 40cm caps at +/-25 → a 90cm capsule centered on the pawn origin.
        if (Cylinder != nullptr) { BodyMesh.SetStaticMesh(Cylinder); }
        if (Mat      != nullptr) { BodyMesh.SetMaterial(0, Mat); }
        BodyMesh.SetRelativeScale3D(FVector(0.4f, 0.4f, 0.5f));
        BodyMesh.SetCollisionEnabled(ECollisionEnabled::NoCollision);

        if (Sphere != nullptr) { CapTopMesh.SetStaticMesh(Sphere); }
        if (Mat    != nullptr) { CapTopMesh.SetMaterial(0, Mat); }
        CapTopMesh.SetRelativeLocation(FVector(0.0f, 0.0f, 25.0f));
        CapTopMesh.SetRelativeScale3D(FVector(0.4f, 0.4f, 0.4f));
        CapTopMesh.SetCollisionEnabled(ECollisionEnabled::NoCollision);

        if (Sphere != nullptr) { CapBottomMesh.SetStaticMesh(Sphere); }
        if (Mat    != nullptr) { CapBottomMesh.SetMaterial(0, Mat); }
        CapBottomMesh.SetRelativeLocation(FVector(0.0f, 0.0f, -25.0f));
        CapBottomMesh.SetRelativeScale3D(FVector(0.4f, 0.4f, 0.4f));
        CapBottomMesh.SetCollisionEnabled(ECollisionEnabled::NoCollision);

        if (Cube != nullptr) { NoseMesh.SetStaticMesh(Cube); }
        if (Mat  != nullptr) { NoseMesh.SetMaterial(0, Mat); }
        NoseMesh.SetRelativeLocation(FVector(28.0f, 0.0f, 0.0f)); // pokes out past the 20cm trunk radius on +X (pawn forward)
        NoseMesh.SetRelativeScale3D(FVector(0.18f, 0.18f, 0.18f));
        NoseMesh.SetCollisionEnabled(ECollisionEnabled::NoCollision);
    }

    void OnEntityConstructed(FCk_Handle_EntityScript InEntityScriptHandle) override
    {
        _PawnEntity = FCk_Handle(InEntityScriptHandle);
        Request_OnPawnReady();
    }

    void Request_OnPawnReady() override
    {
        if (ck::Is_NOT_Valid(_PawnEntity))
        { return; }

        // The pawn entity (a WithActor entity script) already carries an actor-synced transform — that IS the camera
        // anchor, and the POV reads it each frame, so the framing follows the pawn with no extra transform to add.
        _Camera = utils_camera::Add(_PawnEntity, FCk_Fragment_Camera_ParamsData(CameraComponent));

        Request_SpawnFloor();
        Request_SpawnEnemy();
        Request_EmitBindingSelfCheck();

        // Raised here rather than lazily from the tick so they are up before the
        // first frame the player could press anything: a kit that only draws once
        // something lands cannot say that nothing landed.
        Request_CreateReadouts();

        // Poll WASD movement, the cursor aim and the combat kit each frame (see Tick).
        SetActorTickEnabled(true);

        Request_ApplyView();
    }

    // 6000cm x 6000cm slab, sized for the arena. ACk_Gym_Floor puts its walkable surface ON its origin, so
    // spawning at the pawn's spawn point lands the top face at that height. Z scale must stay >= 0.5 or the
    // navmesh bakes zero tiles.
    private void Request_SpawnFloor()
    {
        auto Floor = SpawnActor(ACk_Gym_Floor, GetActorLocation(), FRotator::ZeroRotator, NAME_None, true);
        if (Floor != nullptr)
        {
            Floor.SetActorScale3D(FVector(60.0f, 60.0f, 0.5f));
            FinishSpawningActor(Floor);
        }
    }

    // The dummy is an ENTITY SCRIPT, not an actor: it has no movement, no
    // collision and no mesh, and everything it renders is PMG geometry it owns.
    // Its lifetime hangs off the pawn entity, so a gym cycle takes it with the
    // pawn rather than leaving a target standing on an empty map.
    //
    // The floor slab's walkable surface is at the pawn's own spawn height (see
    // Request_SpawnFloor), so the spawn point's Z is the ground the dummy stands
    // on and no offset is applied to it.
    private void Request_SpawnEnemy()
    {
        const auto EnemyLocation = GetActorLocation()
            + FVector(playground_gym_kit::k_Enemy_SpawnForwardOffset, 0.0, 0.0);

        auto SpawnParams = FCk_Gym_TransformSpawnParams(FTransform(EnemyLocation));

        utils_entity_script::Request_SpawnEntity(
            _PawnEntity,
            UCk_EntityScript_PlaygroundGym_Enemy,
            FInstancedStruct::Make(SpawnParams));
    }

    private void Request_EmitBindingSelfCheck()
    {
        const auto Center = GetActorLocation();

        utils_debug_draw::DrawDebugSphere(
            Center + FVector(300.0f, -120.0f, 5.0f), 60.0f, 16, FLinearColor::Yellow, 5.0f, 3.0f);

        // Negative duration = persist until explicitly destroyed, which is what the staged mutations below need.
        _SelfCheckShape = utils_pmg_basic_shapes::Create_Sphere(
            _PawnEntity,
            FTransform(Center + FVector(300.0f, 120.0f, 60.0f)),
            60.0f, 16, 16,
            ECk_Plane_Axis::XY,
            FLinearColor(0.0f, 1.0f, 1.0f, 0.5f),
            true, 2.0f, -1.0f);
    }

    // The playground has exactly one view: the fixed top-down framing, pushed once and never toggled.
    private void Request_ApplyView()
    {
        if (ck::Is_NOT_Valid(_Camera))
        { return; }

        auto Request = FCk_Request_Camera_AddLayer(UCk_CameraLayer_TopDown);
        Request.Set_StackingBehavior(ECk_Camera_StackingBehavior::OneOnly);
        Request.Set_BlendInTime(FCk_Time(0.0));
        _Camera.Request_AddLayer(Request);
    }

    // Movement is polled each frame and applied relative to the camera's view yaw so W always means "up the
    // screen". Yaw-only basis vectors are already planar, so nothing can push the pawn vertically. Facing is
    // decoupled from movement entirely: the character points at the cursor, walking backwards if need be.
    //
    // W is polled here AND graded by the matcher as the forward combo's chord partner. The two cannot starve
    // each other: a capture ends a routing walk, and this read is engine-level key state that no capture
    // touches (key ledger, Shared.as).
    UFUNCTION(BlueprintOverride)
    void Tick(float32 InDeltaSeconds)
    {
        auto _CkPerfScope = ck::ScopedStat();

        DoAdvance_BindingSelfCheck(InDeltaSeconds);

        if (ck::Is_NOT_Valid(_Camera))
        { return; }

        auto PC = Cast<APlayerController>(GetController());
        if (PC == nullptr)
        { return; }

        const auto YawRot  = FRotator(0.0f, utils_camera::Get_ViewRotation(_Camera).Yaw, 0.0f);
        const auto Forward = YawRot.GetForwardVector();
        const auto Right   = YawRot.GetRightVector();

        // Sprint is a held Shift, applied before the movement input so this
        // frame's steps are already at this frame's speed. The same two keys the
        // speed reads are the sprint combos' chord partners (key ledger, Shared.as).
        auto Movement = Cast<UFloatingPawnMovement>(GetMovementComponent());
        if (Movement != nullptr)
        {
            Movement.MaxSpeed = PC.IsInputKeyDown(playground_gym::k_Key_Sprint)
                ? playground_gym_kit::k_MoveSpeed_Sprint
                : playground_gym_kit::k_MoveSpeed_Walk;
        }

        if (PC.IsInputKeyDown(EKeys::W)) { AddMovementInput(Forward,  1.0f); }
        if (PC.IsInputKeyDown(EKeys::S)) { AddMovementInput(Forward, -1.0f); }
        if (PC.IsInputKeyDown(EKeys::D)) { AddMovementInput(Right,    1.0f); }
        if (PC.IsInputKeyDown(EKeys::A)) { AddMovementInput(Right,   -1.0f); }

        DoAdvance_CursorAim(PC);

        // AFTER the aim: an attack reads the actor rotation the cursor just set, so
        // the swing comes out along the facing the player is looking at rather than
        // along last frame's.
        DoAdvance_CombatKit(InDeltaSeconds);
    }

    // Diablo-style facing: project the cursor ray onto the pawn's ground plane and yaw the whole actor at the
    // hit point. The actor rotation is the aim — attacks and blocks will read the same facing the player sees.
    private void DoAdvance_CursorAim(APlayerController InPlayerController)
    {
        FVector CursorOrigin;
        FVector CursorDirection;
        if (InPlayerController.DeprojectMousePositionToWorld(CursorOrigin, CursorDirection) == false)
        { return; }

        // A ray that never crosses the pawn's height (parallel, or pointing away) has no aim point this frame;
        // keeping the previous facing beats snapping to a garbage one.
        if (Math::Abs(CursorDirection.Z) < 0.001f)
        { return; }

        const auto RayDistance = (GetActorLocation().Z - CursorOrigin.Z) / CursorDirection.Z;
        if (RayDistance <= 0.0)
        { return; }

        const auto AimPoint = CursorOrigin + CursorDirection * RayDistance;
        auto ToAim = AimPoint - GetActorLocation();
        ToAim.Z = 0.0;

        if (ToAim.IsNearlyZero())
        { return; }

        SetActorRotation(FRotator(0.0, ToAim.Rotation().Yaw, 0.0));
    }

    private void DoAdvance_BindingSelfCheck(float32 InDeltaSeconds)
    {
        if (_SelfCheckStage > 2)
        { return; }

        if (ck::Is_NOT_Valid(_SelfCheckShape))
        { return; }

        _SelfCheckElapsed += InDeltaSeconds;

        if (_SelfCheckStage == 0 && _SelfCheckElapsed >= 1.0f)
        {
            utils_pmg_debug_shape::Request_SetColor(_SelfCheckShape,
                FCk_Request_Pmg_DebugShape_SetColor(FLinearColor(1.0f, 0.0f, 1.0f, 0.5f)));
            _SelfCheckStage = 1;
            return;
        }

        if (_SelfCheckStage == 1 && _SelfCheckElapsed >= 2.0f)
        {
            utils_pmg_debug_shape::Request_SetVisible(_SelfCheckShape, false);
            _SelfCheckStage = 2;
            return;
        }

        if (_SelfCheckStage == 2 && _SelfCheckElapsed >= 3.0f)
        {
            utils_entity_lifetime::Request_DestroyEntity(FCk_Handle(_SelfCheckShape));
            _SelfCheckStage = 3;
        }
    }

    //------------------------------------------------------------------------
    // What the dummy calls
    //------------------------------------------------------------------------

    // Stored, not validated against anything: the dummy registers once it has
    // found this pawn, and a pawn that is handed a second one simply points at the
    // newer target rather than keeping a list nothing would iterate.
    void Request_RegisterEnemy(UCk_EntityScript_PlaygroundGym_Enemy InEnemy)
    {
        _Enemy = InEnemy;
    }

    // No health, no state change, no interruption of the attack machine — the
    // whole outcome is a beat, a line, and the VERDICT handed back. Blocked-
    // versus-parried-versus-hit is a fact about this pawn's input — specifically
    // how LONG the block key has been down when the shot lands — which is why the
    // dummy renders nothing at resolution and asks here instead. The dummy acts
    // on the answer (a parried shot flies home), but it never re-derives it.
    int32 Request_ResolveProjectileImpact()
    {
        const auto BlockRun = playground_gym::Get_HeldRunFrames(
            playground_gym::TryGet_Sampler(),
            playground_gym::k_Key_Block.GetKeyName());

        _ProjectileBeatTicksRemaining = playground_gym_kit::k_ProjectileBeatTicks;

        if (BlockRun <= 0)
        {
            _ProjectileBeatVerdict = playground_gym_kit::k_ProjectileVerdict_Struck;
            Print("[Playground] HIT", 1.5f);
        }
        else if (BlockRun <= playground_gym_kit::k_ParryWindowFrames)
        {
            _ProjectileBeatVerdict = playground_gym_kit::k_ProjectileVerdict_Parried;
            Print("[Playground] PARRY", 1.5f);
        }
        else
        {
            _ProjectileBeatVerdict = playground_gym_kit::k_ProjectileVerdict_Blocked;
            Print("[Playground] BLOCKED", 1.5f);
        }

        return _ProjectileBeatVerdict;
    }

    // The camera director lives on this pawn's entity, so the dummy's floor label
    // asks for the yaw rather than composing a second read of the same camera.
    float64 Get_CameraYaw() const
    {
        if (ck::Is_NOT_Valid(_Camera))
        { return 0.0; }

        return utils_camera::Get_ViewRotation(_Camera).Yaw;
    }

    //------------------------------------------------------------------------
    // The kit's tick
    //------------------------------------------------------------------------
    //
    // The held runs are read ONCE and handed down, because they are walks over the
    // record's rows and three readers asking separately could disagree about the
    // same frame if a row landed between two of them.
    //
    // The step order below is the design:
    //   1. the chain-press read, FIRST — the buffer answers the button-down the
    //      moment its row lands, and a charge landing later this same tick gets
    //      the last word by clearing it;
    //   2. combos and charges, so a completed sequence or hold interrupts whatever
    //      chain was live before that chain's own timer can end it on the same
    //      tick;
    //   3. taps, the back-stop for the press read and the grace-window consumer;
    //   4. the release check, which turns a charge into its special on the frame
    //      the button actually left the record's held set;
    //   5. the countdown — it serves the wind-up (spawning the stashed swing
    //      where the wind-up ends and the press's verdict is in), expires the
    //      state, and arms the grace window when nothing was buffered;
    //   6. the hit window, LAST — it tests the live swing's own region against
    //      the dummy, after the countdown so the swing a spawn just armed is
    //      tested on the tick it appeared.
    //
    // The block is refreshed alongside the other persistent shapes and is not part
    // of that order at all: it reads its own key off the record and never consults
    // `_State`, which is the independence the header describes.

    private void DoAdvance_CombatKit(float32 InDeltaSeconds)
    {
        DoTryCompose();

        auto Sampler = playground_gym::TryGet_Sampler();

        const auto LightRun = playground_gym::Get_HeldRunFrames(Sampler, playground_gym::k_Key_Light.GetKeyName());
        const auto HeavyRun = playground_gym::Get_HeldRunFrames(Sampler, playground_gym::k_Key_Heavy.GetKeyName());
        const auto BlockRun = playground_gym::Get_HeldRunFrames(Sampler, playground_gym::k_Key_Block.GetKeyName());

        // BEFORE the completions: a charge landing this tick must have the last
        // word on the buffer, and this reads the same press the charge grew from.
        DoAdvance_ChainPressIntent(Sampler);

        DoTryRecordAttempts(Sampler);

        DoAdvance_ChargeRelease(LightRun, HeavyRun);
        DoAdvance_Countdown(InDeltaSeconds, LightRun, HeavyRun);
        DoAdvance_Hitbox(InDeltaSeconds);

        DoRefresh_ChargeShape(LightRun, HeavyRun);
        DoRefresh_BufferMarker();
        DoRefresh_BlockPlate(BlockRun);
        DoRefresh_Readouts(Sampler, LightRun, HeavyRun, BlockRun);
        DoAdvance_Beat();
        DoAdvance_ProjectileBeat();
    }

    //------------------------------------------------------------------------
    // Composition
    //------------------------------------------------------------------------
    //
    // Everything here is idempotent and retried from the tick: the source does not
    // exist until the local player has a controller, the button map is EMPTY on
    // the calling stack of its own Add, and a swap is deferred two groups ahead of
    // the scan (CkIntent/CLAUDE.md anti-patterns 18 and 21).

    private void DoTryCompose()
    {
        if (_SetRejected)
        { return; }

        // Called from here as well as from the PlayerController's timer tick, so
        // the two never have to be ordered against each other.
        if (playground_gym::Request_EnsureSourceComposed() == false)
        { return; }

        auto Source = playground_gym::TryGet_PlayerSource();

        if (ck::Is_NOT_Valid(_Layer))
        {
            // A priority that is still held makes Create ensure and hand back an
            // invalid handle, so asking first turns that into a one-frame wait.
            if (ck::IsValid(utils_input_layer::TryGet_LayerWithPriority(Source, playground_gym::k_LayerPriority_CombatKit)))
            { return; }

            _Layer = utils_input_layer::Create(_PawnEntity,
                FCk_Fragment_InputLayer_ParamsData(Source, playground_gym::k_LayerPriority_CombatKit));
        }

        if (ck::Is_NOT_Valid(_Layer))
        { return; }

        if (ck::Is_NOT_Valid(_Matcher))
        {
            auto MatcherParams = FCk_Fragment_IntentMatcher_ParamsData();
            MatcherParams.Set_LatchDecayFrames(playground_gym::k_LatchDecayFrames);

            FCk_Handle LayerEntity = _Layer;
            _Matcher = utils_intent_matcher::Add(LayerEntity, MatcherParams);
        }

        if (ck::Is_NOT_Valid(_Matcher) || _SwapRequested)
        { return; }

        // A swap is atomic — one unresolved terminal rejects the whole set — so it
        // waits for ALL FOUR terminal keys to be minted rather than being rejected
        // for keys that only look unresolvable. Forward and sprint are two of
        // them: a chord terminal contributes EVERY button in it, so W and Shift
        // are terminals exactly as much as L is. The block key is NOT waited on:
        // no move terminates on it, so it cannot resolve or fail to resolve a
        // terminal.
        auto ButtonMap = playground_gym::TryGet_ButtonMap();

        if (playground_gym::Get_IsKeyMinted(ButtonMap, playground_gym::k_Key_Light) == false)
        { return; }

        if (playground_gym::Get_IsKeyMinted(ButtonMap, playground_gym::k_Key_Heavy) == false)
        { return; }

        if (playground_gym::Get_IsKeyMinted(ButtonMap, playground_gym::k_Key_Forward) == false)
        { return; }

        if (playground_gym::Get_IsKeyMinted(ButtonMap, playground_gym::k_Key_Sprint) == false)
        { return; }

        DoRequestSwap();
    }

    private void DoRequestSwap()
    {
        TArray<FCkTests_Intent_MoveRow> Rows = playground_gym_kit_moves::MoveTable_PlaygroundKit.Rows;

        TArray<FCk_Intent_Definition> Definitions;

        for (auto Index = 0; Index < Rows.Num(); Index++)
        {
            auto Row = Rows[Index];
            auto Parsed = utils_intent_grammar::Parse(Row._Notation, Row._Name, Row._Priority, FGameplayTag());

            if (Parsed.Get_Outcome() != ECk_SucceededFailed::Succeeded)
            {
                auto MoveName = Row._Name;
                auto Notation = Row._Notation;
                auto ParseError = Parsed.Get_Error();

                DoReportAuthoringFailure(f"move '{MoveName}' ({Notation}) rejected as {ParseError :n}");
                return;
            }

            Definitions.Add(Parsed.Get_Definition());
        }

        TArray<FCk_Intent_ButtonNameRow> ButtonRows;
        ButtonRows.Add(FCk_Intent_ButtonNameRow(n"L", playground_gym::Make_PhysicalButton(playground_gym::k_Key_Light)));
        ButtonRows.Add(FCk_Intent_ButtonNameRow(n"H", playground_gym::Make_PhysicalButton(playground_gym::k_Key_Heavy)));
        ButtonRows.Add(FCk_Intent_ButtonNameRow(n"W", playground_gym::Make_PhysicalButton(playground_gym::k_Key_Forward)));
        ButtonRows.Add(FCk_Intent_ButtonNameRow(n"R", playground_gym::Make_PhysicalButton(playground_gym::k_Key_Sprint)));

        // The sprint combos ARE chord terminals, so the bake's chord window is
        // live now and governs how long a mouse press waits for a W or Shift
        // that might still be arriving. The default (3 frames) stands: it is
        // already shorter than the hold wait the same press carries, so nothing
        // about either button's latency changes, and a number named here would
        // be a second opinion about a window nobody asked to move.
        auto Baked = utils_intent_grammar::Bake(Definitions, ButtonRows);

        if (Baked.Get_Outcome() != ECk_SucceededFailed::Succeeded)
        {
            auto BakeError = Baked.Get_Error();
            auto Offending = Baked.Get_OffendingIntent();

            DoReportAuthoringFailure(f"the set did not compile: {BakeError :n} on move '{Offending}'");
            return;
        }

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(Baked.Get_CompiledSet()),
            FCk_Delegate_Request_OnCompleted(this, n"OnSwapCompleted"));

        _SwapRequested = true;
    }

    UFUNCTION()
    private void OnSwapCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (InResult == ECk_Request_OperationResult::Succeeded)
        { return; }

        DoReportAuthoringFailure("the swap was rejected - a terminal resolved to no key");
    }

    // The state label carries the bad news because it is the one thing a player is
    // already looking at, and the log carries the detail. Latched so the tick stops
    // retrying a set that is not going to compile.
    private void DoReportAuthoringFailure(FString InReason)
    {
        _SwapRequested = true;
        _SetRejected = true;

        DoSetLabel(_StateLabel, "SET REJECTED", playground_gym_kit::k_Colour_Label_Broken);

        Print(f"[Playground/Kit] {InReason}", 12.0f);
    }

    //------------------------------------------------------------------------
    // Reading the result
    //------------------------------------------------------------------------
    //
    // ALL SEVEN rows are asked every tick, unconditionally. A skipped call would
    // leave that move's record behind the matcher's, and the next landing it did
    // see would be graded against a frame two completions old. That is also why
    // nothing below short-circuits when the kit has decided to ignore the press:
    // the module delivered it, the record carries it, and this file declines to
    // act on it — three different statements, and only the last one is the kit's.
    //
    // The combos are handled FIRST because they supersede: only one intent can
    // complete per button per row, so two of these can only ever land together on
    // two different buttons — and a combo is the more specific reading of the
    // presses that produced it.

    private void DoTryRecordAttempts(FCk_Handle_IntentSampler InSampler)
    {
        if (ck::Is_NOT_Valid(InSampler) || ck::Is_NOT_Valid(_Matcher))
        { return; }

        const auto LightName = playground_gym::k_Key_Light.GetKeyName();
        const auto HeavyName = playground_gym::k_Key_Heavy.GetKeyName();

        // Each combo's terminal names the button whose PRESS completed it: L-then-H
        // ends on the heavy button, H-then-L on the light one, and each sprint
        // chord completes on the mouse press its held partners were waiting for.
        const auto ComboLHLanded = playground_gym::Request_RecordAttempt(
            _Attempt_ComboLH, _Matcher, InSampler, playground_gym_kit_moves::k_Move_Combo_LH, HeavyName);

        const auto ComboHLLanded = playground_gym::Request_RecordAttempt(
            _Attempt_ComboHL, _Matcher, InSampler, playground_gym_kit_moves::k_Move_Combo_HL, LightName);

        const auto ComboWLLanded = playground_gym::Request_RecordAttempt(
            _Attempt_ComboWL, _Matcher, InSampler, playground_gym_kit_moves::k_Move_Combo_WL, LightName);

        const auto ComboWHLanded = playground_gym::Request_RecordAttempt(
            _Attempt_ComboWH, _Matcher, InSampler, playground_gym_kit_moves::k_Move_Combo_WH, HeavyName);

        const auto LightChargeLanded = playground_gym::Request_RecordAttempt(
            _Attempt_LightCharge, _Matcher, InSampler, playground_gym_kit_moves::k_Move_Light_Charge, LightName);

        const auto HeavyChargeLanded = playground_gym::Request_RecordAttempt(
            _Attempt_HeavyCharge, _Matcher, InSampler, playground_gym_kit_moves::k_Move_Heavy_Charge, HeavyName);

        const auto LightTapLanded = playground_gym::Request_RecordAttempt(
            _Attempt_LightTap, _Matcher, InSampler, playground_gym_kit_moves::k_Move_Light_Tap, LightName);

        const auto HeavyTapLanded = playground_gym::Request_RecordAttempt(
            _Attempt_HeavyTap, _Matcher, InSampler, playground_gym_kit_moves::k_Move_Heavy_Tap, HeavyName);

        if (ComboLHLanded)
        { DoOnComboLanded(playground_gym_kit::k_State_Combo_LH); }

        if (ComboHLLanded)
        { DoOnComboLanded(playground_gym_kit::k_State_Combo_HL); }

        if (ComboWLLanded)
        { DoOnComboLanded(playground_gym_kit::k_State_Combo_WL); }

        if (ComboWHLanded)
        { DoOnComboLanded(playground_gym_kit::k_State_Combo_WH); }

        if (LightChargeLanded)
        { DoOnChargeLanded(playground_gym_kit::k_Family_Light); }

        if (HeavyChargeLanded)
        { DoOnChargeLanded(playground_gym_kit::k_Family_Heavy); }

        if (LightTapLanded)
        { DoOnTapLanded(playground_gym_kit::k_Family_Light); }

        if (HeavyTapLanded)
        { DoOnTapLanded(playground_gym_kit::k_Family_Heavy); }
    }

    //------------------------------------------------------------------------
    // The machine
    //------------------------------------------------------------------------

    // The chain intent is the PRESS, read off the record the moment its row lands
    // — the candidate-lifecycle read played game-side: act on button-down, let the verdict re-resolve
    // it. ANY press after the step's entry row buffers the next step immediately —
    // the wind-up is animation, not an input gate ([P10-D6]'s wind-up rejection
    // swallowed the second click of a natural double-click, which lands inside
    // the wind-up the first click's release started). If the matcher later grades
    // the press a CHARGE, the charge's interrupt clears the buffer it briefly held.
    private void DoAdvance_ChainPressIntent(FCk_Handle_IntentSampler InSampler)
    {
        const auto Step = Get_ChainStep();

        if (Step < 1 || Step > 2)
        { return; }

        const auto Key = Get_StateFamily() == playground_gym_kit::k_Family_Light
            ? playground_gym::k_Key_Light
            : playground_gym::k_Key_Heavy;

        const auto PressFrame = playground_gym::Get_LatestPressFrame(InSampler, Key.GetKeyName());

        // Strictly after: the press that STARTED this step landed on or before
        // the entry row, and it can never buffer the step after itself.
        if (PressFrame <= _StepEntryFrame)
        { return; }

        _BufferedNext = true;
    }

    // A combo supersedes whatever was running, exactly as a charge does, and for a
    // stronger reason: the presses a chain was reading one at a time are the same
    // presses the matcher just read as one move, so continuing the chain would be
    // answering the same input twice. The chain bookkeeping goes with it — step,
    // buffer and grace window all belong to a chain that is no longer running.
    //
    // Phase-exempt: the sequence WAS the wind-up, so the strike is spawned on this
    // frame rather than stashed, and `_SwingSpawned` is set so the countdown's
    // wind-up server has nothing left to do.
    private void DoOnComboLanded(int32 InComboState)
    {
        _BufferedNext = false;
        _GraceUntilFrame = -1;
        _SwingSpawned = true;

        _State                 = InComboState;
        _StateTotalSeconds     = playground_gym_kit::k_Duration_Combo;
        _StateSecondsRemaining = playground_gym_kit::k_Duration_Combo;

        // The ordered combos are aimed moves and come out as a box along the aim
        // like everything else; the sprint attacks are AREA moves — a ring around
        // the pawn, hit-tested from the pawn — because an attack thrown at a run
        // has no aim to speak of.
        if (InComboState == playground_gym_kit::k_State_Combo_WL ||
            InComboState == playground_gym_kit::k_State_Combo_WH)
        {
            DoSpawnSprintAoE(Get_ComboColour(InComboState));
        }
        else
        {
            DoSpawnSwing(
                playground_gym_kit::k_Extent_Combo,
                Get_ComboColour(InComboState),
                playground_gym_kit::k_Attack_SpecialForwardOffset,
                playground_gym_kit::k_Duration_Combo);
        }

        DoFlashBeat(true);
    }

    // A charge interrupts everything. The buffer goes with it: a queued next step
    // belongs to a chain that is no longer running, and firing it after the special
    // would be answering an input the player made about a different move. A
    // mid-wind-up charge also cancels the strike itself: the pending swing never
    // spawns, so a cancelled attack costs no shape.
    private void DoOnChargeLanded(int32 InFamily)
    {
        _BufferedNext = false;
        _GraceUntilFrame = -1;
        _StateSecondsRemaining = 0.0f;

        _State = InFamily == playground_gym_kit::k_Family_Light
            ? playground_gym_kit::k_State_Charging_Light
            : playground_gym_kit::k_State_Charging_Heavy;

        DoFlashBeat(true);
    }

    // Idle starts a chain — or CONTINUES one, when the tap lands inside the grace
    // window a just-expired step left behind. A completion during a step is the
    // back-stop for the press-intent read (its press has to clear the same
    // entry-row gate). Anything else — the other family mid-chain, a press during
    // a charge, a press during a special, a press during a combo — is delivered,
    // recorded and deliberately not acted on.
    private void DoOnTapLanded(int32 InFamily)
    {
        if (_State == playground_gym_kit::k_State_Idle)
        {
            const auto LiveFrame = playground_gym::Get_LiveFrameIndex(playground_gym::TryGet_Sampler());

            if (_GraceUntilFrame >= 0 && LiveFrame <= _GraceUntilFrame && InFamily == _GraceFamily)
            {
                DoEnterChainStep(InFamily, _GraceNextStep);
                DoFlashBeat(true);
                return;
            }

            DoEnterChainStep(InFamily, 1);
            DoFlashBeat(true);
            return;
        }

        if (Get_StateFamily() == InFamily && Get_ChainStep() >= 1 && Get_ChainStep() <= 2)
        {
            const auto PressFrame = InFamily == playground_gym_kit::k_Family_Light
                ? _Attempt_LightTap.PressFrame
                : _Attempt_HeavyTap.PressFrame;

            if (PressFrame > _StepEntryFrame)
            {
                _BufferedNext = true;
                DoFlashBeat(true);
                return;
            }
        }

        DoFlashBeat(false);
    }

    // The release frame — the beat the charge exists to reach. The record no longer
    // reports the button held, which is a fact about THIS frame rather than a timer
    // this file kept (CkIntent/CLAUDE.md anti-pattern 23).
    private void DoAdvance_ChargeRelease(int32 InLightRun, int32 InHeavyRun)
    {
        if (_State == playground_gym_kit::k_State_Charging_Light && InLightRun <= 0)
        {
            DoEnterSpecial(playground_gym_kit::k_Family_Light);
            return;
        }

        if (_State == playground_gym_kit::k_State_Charging_Heavy && InHeavyRun <= 0)
        { DoEnterSpecial(playground_gym_kit::k_Family_Heavy); }
    }

    // A charge has no countdown of its own — it lasts as long as the player holds —
    // so a zero remaining while charging is the normal state and not an expiry.
    private void DoAdvance_Countdown(float32 InDeltaSeconds, int32 InLightRun, int32 InHeavyRun)
    {
        if (_StateSecondsRemaining <= 0.0f)
        { return; }

        _StateSecondsRemaining -= InDeltaSeconds;

        DoTrySpawnPendingSwing(InLightRun, InHeavyRun);

        if (_StateSecondsRemaining > 0.0f)
        { return; }

        _StateSecondsRemaining = 0.0f;

        const auto Step = Get_ChainStep();

        if (_BufferedNext && Step >= 1 && Step <= 2)
        {
            _BufferedNext = false;
            DoEnterChainStep(Get_StateFamily(), Step + 1);
            return;
        }

        // Expiring unbuffered arms the grace window: a same-family tap landing in
        // Idle within it CONTINUES the chain rather than opening a new one. Step 3
        // arms nothing — there is no fourth hit to be late for, and neither a
        // special nor a combo arms one, because neither is a chain step.
        if (Step >= 1 && Step <= 2)
        {
            _GraceUntilFrame = playground_gym::Get_LiveFrameIndex(playground_gym::TryGet_Sampler())
                + playground_gym_kit::k_ChainGraceFrames;
            _GraceFamily   = Get_StateFamily();
            _GraceNextStep = Step + 1;
        }

        _BufferedNext = false;
        _State = playground_gym_kit::k_State_Idle;
    }

    // The strike comes out where the wind-up ends: the swing is given the state's
    // remaining seconds, so the two still expire on the same tick however late the
    // spawn ran, and the hit-test runs at the strike rather than at the press.
    //
    // AND ONLY ONCE THE STEP'S PRESS HAS A VERDICT. A press still down under the
    // verdict point may yet be graded a hold, and a hold's cancel must stay free —
    // so the strike waits out the run rather than spawning under a press that
    // might retract it. A tap resolves at its release and the swing comes out a
    // beat late; a hold's charge supersedes the state in the completions read,
    // which runs earlier in the tick than this does, so the threshold branch
    // below is a backstop rather than a path.
    private void DoTrySpawnPendingSwing(int32 InLightRun, int32 InHeavyRun)
    {
        if (_SwingSpawned || Get_ChainStep() == 0)
        { return; }

        const auto Elapsed = _StateTotalSeconds - _StateSecondsRemaining;

        if (Elapsed < _StateTotalSeconds * playground_gym_kit::k_Phase_WindUpFraction)
        { return; }

        const auto Run = _PendingSwing_Family == playground_gym_kit::k_Family_Light
            ? InLightRun
            : InHeavyRun;

        if (Run > 0 && Run < playground_gym_kit_moves::k_ChargeHoldFrames)
        { return; }

        _SwingSpawned = true;

        DoSpawnSwing(
            _PendingSwing_Extent,
            _PendingSwing_Colour,
            playground_gym_kit::k_Attack_ForwardOffset,
            _StateSecondsRemaining);
    }

    // Entering a step does NOT spawn its swing — the strike is stashed and comes
    // out when the wind-up has been served (DoTrySpawnPendingSwing), which is also
    // what lets a mid-wind-up charge cancel it for free.
    private void DoEnterChainStep(int32 InFamily, int32 InStep)
    {
        _GraceUntilFrame = -1;

        _State                 = Get_ChainState(InFamily, InStep);
        _StateTotalSeconds     = Get_ChainDuration(InFamily, InStep);
        _StateSecondsRemaining = _StateTotalSeconds;

        _SwingSpawned        = false;
        _PendingSwing_Family = InFamily;
        _PendingSwing_Extent = Get_ChainExtent(InFamily, InStep);
        _PendingSwing_Colour = Get_ChainColour(InFamily, InStep);

        _StepEntryFrame = playground_gym::Get_LiveFrameIndex(playground_gym::TryGet_Sampler());
    }

    private int32 Get_ChainState(int32 InFamily, int32 InStep) const
    {
        if (InFamily == playground_gym_kit::k_Family_Light)
        {
            if (InStep == 1) { return playground_gym_kit::k_State_Light1; }
            if (InStep == 2) { return playground_gym_kit::k_State_Light2; }
            return playground_gym_kit::k_State_Light3;
        }

        if (InStep == 1) { return playground_gym_kit::k_State_Heavy1; }
        if (InStep == 2) { return playground_gym_kit::k_State_Heavy2; }
        return playground_gym_kit::k_State_Heavy3;
    }

    private float32 Get_ChainDuration(int32 InFamily, int32 InStep) const
    {
        if (InFamily == playground_gym_kit::k_Family_Light)
        {
            if (InStep == 1) { return playground_gym_kit::k_Duration_Light1; }
            if (InStep == 2) { return playground_gym_kit::k_Duration_Light2; }
            return playground_gym_kit::k_Duration_Light3;
        }

        if (InStep == 1) { return playground_gym_kit::k_Duration_Heavy1; }
        if (InStep == 2) { return playground_gym_kit::k_Duration_Heavy2; }
        return playground_gym_kit::k_Duration_Heavy3;
    }

    private float32 Get_ChainExtent(int32 InFamily, int32 InStep) const
    {
        if (InFamily == playground_gym_kit::k_Family_Light)
        {
            if (InStep == 1) { return playground_gym_kit::k_Extent_Light1; }
            if (InStep == 2) { return playground_gym_kit::k_Extent_Light2; }
            return playground_gym_kit::k_Extent_Light3;
        }

        if (InStep == 1) { return playground_gym_kit::k_Extent_Heavy1; }
        if (InStep == 2) { return playground_gym_kit::k_Extent_Heavy2; }
        return playground_gym_kit::k_Extent_Heavy3;
    }

    private FLinearColor Get_ChainColour(int32 InFamily, int32 InStep) const
    {
        if (InFamily == playground_gym_kit::k_Family_Light)
        {
            if (InStep == 1) { return playground_gym_kit::k_Colour_Light1; }
            if (InStep == 2) { return playground_gym_kit::k_Colour_Light2; }
            return playground_gym_kit::k_Colour_Light3;
        }

        if (InStep == 1) { return playground_gym_kit::k_Colour_Heavy1; }
        if (InStep == 2) { return playground_gym_kit::k_Colour_Heavy2; }
        return playground_gym_kit::k_Colour_Heavy3;
    }

    private FLinearColor Get_ComboColour(int32 InComboState) const
    {
        if (InComboState == playground_gym_kit::k_State_Combo_LH)
        { return playground_gym_kit::k_Colour_Combo_LH; }

        if (InComboState == playground_gym_kit::k_State_Combo_HL)
        { return playground_gym_kit::k_Colour_Combo_HL; }

        if (InComboState == playground_gym_kit::k_State_Combo_WH)
        { return playground_gym_kit::k_Colour_Combo_WH; }

        return playground_gym_kit::k_Colour_Combo_WL;
    }

    private FString Get_ComboLabelText(int32 InComboState) const
    {
        if (InComboState == playground_gym_kit::k_State_Combo_LH)
        { return playground_gym_kit::k_LabelText_Combo_LH; }

        if (InComboState == playground_gym_kit::k_State_Combo_HL)
        { return playground_gym_kit::k_LabelText_Combo_HL; }

        if (InComboState == playground_gym_kit::k_State_Combo_WH)
        { return playground_gym_kit::k_LabelText_Combo_WH; }

        return playground_gym_kit::k_LabelText_Combo_WL;
    }

    // Specials spawn their swing IMMEDIATELY — the charge the player sat through
    // was the wind-up.
    private void DoEnterSpecial(int32 InFamily)
    {
        _BufferedNext = false;
        _GraceUntilFrame = -1;
        _SwingSpawned = true;

        if (InFamily == playground_gym_kit::k_Family_Light)
        {
            _State = playground_gym_kit::k_State_Special_Light;
            _StateTotalSeconds = playground_gym_kit::k_Duration_Special_Light;
            _StateSecondsRemaining = playground_gym_kit::k_Duration_Special_Light;

            DoSpawnSwing(
                playground_gym_kit::k_Extent_Special_Light, playground_gym_kit::k_Colour_Special_Light,
                playground_gym_kit::k_Attack_SpecialForwardOffset, playground_gym_kit::k_Duration_Special_Light);
            return;
        }

        _State = playground_gym_kit::k_State_Special_Heavy;
        _StateTotalSeconds = playground_gym_kit::k_Duration_Special_Heavy;
        _StateSecondsRemaining = playground_gym_kit::k_Duration_Special_Heavy;

        DoSpawnSwing(
            playground_gym_kit::k_Extent_Special_Heavy, playground_gym_kit::k_Colour_Special_Heavy,
            playground_gym_kit::k_Attack_SpecialForwardOffset, playground_gym_kit::k_Duration_Special_Heavy);
    }

    //------------------------------------------------------------------------
    // Reading the machine
    //------------------------------------------------------------------------

    private int32 Get_StateFamily() const
    {
        if (_State == playground_gym_kit::k_State_Light1 ||
            _State == playground_gym_kit::k_State_Light2 ||
            _State == playground_gym_kit::k_State_Light3 ||
            _State == playground_gym_kit::k_State_Charging_Light ||
            _State == playground_gym_kit::k_State_Special_Light)
        { return playground_gym_kit::k_Family_Light; }

        if (_State == playground_gym_kit::k_State_Heavy1 ||
            _State == playground_gym_kit::k_State_Heavy2 ||
            _State == playground_gym_kit::k_State_Heavy3 ||
            _State == playground_gym_kit::k_State_Charging_Heavy ||
            _State == playground_gym_kit::k_State_Special_Heavy)
        { return playground_gym_kit::k_Family_Heavy; }

        return playground_gym_kit::k_Family_None;
    }

    // Zero for anything that is not a chain step, which is what makes "may I
    // buffer" a range test rather than a list of states to keep in step.
    private int32 Get_ChainStep() const
    {
        if (_State == playground_gym_kit::k_State_Light1 || _State == playground_gym_kit::k_State_Heavy1)
        { return 1; }

        if (_State == playground_gym_kit::k_State_Light2 || _State == playground_gym_kit::k_State_Heavy2)
        { return 2; }

        if (_State == playground_gym_kit::k_State_Light3 || _State == playground_gym_kit::k_State_Heavy3)
        { return 3; }

        return 0;
    }

    private bool Get_IsCharging() const
    {
        return _State == playground_gym_kit::k_State_Charging_Light
            || _State == playground_gym_kit::k_State_Charging_Heavy;
    }

    private bool Get_IsCombo() const
    {
        return _State == playground_gym_kit::k_State_Combo_LH
            || _State == playground_gym_kit::k_State_Combo_HL
            || _State == playground_gym_kit::k_State_Combo_WL
            || _State == playground_gym_kit::k_State_Combo_WH;
    }

    //------------------------------------------------------------------------
    // The shapes
    //------------------------------------------------------------------------

    // Created with a positive duration and then forgotten: the entity counts itself
    // down and destroys itself, and that countdown IS the attack's length made
    // visible. Nothing here is tracked, because there is no path on which one of
    // these outlives its own clock.
    //
    // The hit window is armed on the same call, from the same numbers the shape
    // was drawn with: the shape and the hitbox are one event, and a second place
    // deciding reach could disagree with the picture.
    private void DoSpawnSwing(
        float32 InExtent,
        FLinearColor InColour,
        float32 InForwardOffset,
        float32 InDurationSeconds)
    {
        const auto Centre = Get_AttackLocation(InForwardOffset);

        utils_pmg_basic_shapes::Create_Box(
            _PawnEntity,
            FTransform(GetActorRotation(), Centre, FVector(1.0, 1.0, 1.0)),
            FVector(InExtent, InExtent, InExtent),
            ECk_Plane_Axis::XY,
            InColour,
            true,
            playground_gym_kit::k_ShapeLineThickness,
            InDurationSeconds);

        DoArmHitbox(Centre, InExtent, InDurationSeconds);
    }

    // The sprint attacks' shape: a flat ring on the floor around the pawn, the
    // area the hit window covers made visible. Same one-call identity as the box.
    private void DoSpawnSprintAoE(FLinearColor InColour)
    {
        const auto Centre = GetActorLocation();

        utils_pmg_flat_shapes::Create_Circle(
            _PawnEntity,
            FTransform(Centre + FVector(0.0, 0.0, playground_gym_kit::k_Label_FloorLift)),
            playground_gym_kit::k_Extent_SprintAoE,
            32,
            InColour,
            true,
            playground_gym_kit::k_ShapeLineThickness,
            false,
            ECk_Plane_Axis::XY,
            playground_gym_kit::k_Duration_Combo);

        DoArmHitbox(Centre, playground_gym_kit::k_Extent_SprintAoE, playground_gym_kit::k_Duration_Combo);
    }

    private void DoArmHitbox(FVector InCentre, float32 InExtent, float32 InSeconds)
    {
        _Hitbox_SecondsRemaining = InSeconds;
        _Hitbox_Centre           = InCentre;
        _Hitbox_Reach            = InExtent + playground_gym_kit::k_HitTest_Padding;
        _Hitbox_Landed           = false;
    }

    // PLANAR distance from the drawn shape's own centre, every tick the shape is
    // up, landing at most once: the dummy stands on the same floor the pawn does,
    // so a height difference between two things on one slab is not a reason to
    // miss — and a dummy walked into a standing swing is a hit, however late the
    // two came together.
    private void DoAdvance_Hitbox(float32 InDeltaSeconds)
    {
        if (_Hitbox_SecondsRemaining <= 0.0f)
        { return; }

        _Hitbox_SecondsRemaining -= InDeltaSeconds;

        if (_Hitbox_Landed || ck::Is_NOT_Valid(_Enemy))
        { return; }

        auto ToEnemy = _Enemy.Get_Location() - _Hitbox_Centre;
        ToEnemy.Z = 0.0;

        if (ToEnemy.Size() > _Hitbox_Reach)
        { return; }

        _Hitbox_Landed = true;
        _Enemy.Request_TakeHit();
    }

    // The accumulator is DISPLAY ONLY: it counts the rows the RECORD reports the
    // button down for, which is the physical fact, and it never decides that
    // anything came out. It is up while the button is held from the frame the
    // charge state was entered, and it goes down the frame the button does — which
    // is the same frame the special replaces it.
    private void DoRefresh_ChargeShape(int32 InLightRun, int32 InHeavyRun)
    {
        if (Get_IsCharging() == false)
        {
            DoDestroyShape(_ChargeShape);
            return;
        }

        const auto Run = _State == playground_gym_kit::k_State_Charging_Light ? InLightRun : InHeavyRun;

        const auto Colour = _State == playground_gym_kit::k_State_Charging_Light
            ? playground_gym_kit::k_Colour_ChargeGrow_Light
            : playground_gym_kit::k_Colour_ChargeGrow_Heavy;

        if (ck::Is_NOT_Valid(_ChargeShape))
        {
            // The creation transform already carries the frame's own scale, so the
            // growth continues on the next tick rather than with a second request
            // against the same frame's value.
            _ChargeShape = utils_pmg_basic_shapes::Create_Sphere(
                _PawnEntity,
                Get_ChargeTransform(Get_ChargeScale(Run)),
                playground_gym_kit::k_ChargeRadius,
                playground_gym_kit::k_ChargeSegments,
                playground_gym_kit::k_ChargeRings,
                ECk_Plane_Axis::XY,
                Colour,
                true,
                playground_gym_kit::k_ShapeLineThickness,
                playground_gym::k_ShapeDuration_Persistent);

            return;
        }

        DoSetShapeTransform(_ChargeShape, Get_ChargeTransform(Get_ChargeScale(Run)));
    }

    // A floor so a shape that has just appeared is visible, full size exactly at
    // the threshold, and a ceiling for the run that keeps climbing after the charge
    // has already been answered.
    private float32 Get_ChargeScale(int32 InRun) const
    {
        const auto Progress = float32(InRun) / float32(playground_gym_kit::k_ChargeFullFrames);

        const auto Scaled = playground_gym_kit::k_ChargeScale_Min
            + (Progress * (1.0f - playground_gym_kit::k_ChargeScale_Min));

        return Scaled > playground_gym_kit::k_ChargeScale_Max
            ? playground_gym_kit::k_ChargeScale_Max
            : Scaled;
    }

    private void DoRefresh_BufferMarker()
    {
        if (_BufferedNext == false)
        {
            DoDestroyShape(_BufferMarker);
            return;
        }

        if (ck::Is_NOT_Valid(_BufferMarker))
        {
            _BufferMarker = utils_pmg_basic_shapes::Create_Sphere(
                _PawnEntity,
                Get_MarkerTransform(playground_gym_kit::k_Buffer_Height),
                playground_gym_kit::k_Buffer_Radius,
                playground_gym_kit::k_Buffer_Segments,
                playground_gym_kit::k_Buffer_Rings,
                ECk_Plane_Axis::XY,
                playground_gym_kit::k_Colour_Buffer,
                true,
                playground_gym_kit::k_ShapeLineThickness,
                playground_gym::k_ShapeDuration_Persistent);

            return;
        }

        DoSetShapeTransform(_BufferMarker, Get_MarkerTransform(playground_gym_kit::k_Buffer_Height));
    }

    // The plate is up for exactly as long as the record reports Q held, and it is
    // re-transformed every tick because it rides the cursor aim. `_State` is not
    // consulted: a block during a chain is a block, which is the independence the
    // header describes.
    private void DoRefresh_BlockPlate(int32 InBlockRun)
    {
        if (InBlockRun <= 0)
        {
            DoDestroyShape(_BlockPlate);
            return;
        }

        if (ck::Is_NOT_Valid(_BlockPlate))
        {
            _BlockPlate = utils_pmg_flat_shapes::Create_Plane(
                _PawnEntity,
                Get_BlockTransform(),
                playground_gym_kit::k_Block_Width,
                playground_gym_kit::k_Block_PlateHeight,
                playground_gym_kit::k_Colour_Block,
                true,
                playground_gym_kit::k_ShapeLineThickness,
                ECk_Plane_Axis::YZ,
                playground_gym::k_ShapeDuration_Persistent);

            return;
        }

        DoSetShapeTransform(_BlockPlate, Get_BlockTransform());
    }

    // A completion arriving is a "right now", so it is the single-frame primitive
    // re-issued for a fifth of a second rather than an entity with a lifetime. The
    // dim variant is a completion the kit deliberately did not act on — the module
    // delivered it and the debugger's timeline will show it, and this says so.
    private void DoFlashBeat(bool InWasActedOn)
    {
        _BeatTicksRemaining = playground_gym_kit::k_BeatTicks;
        _BeatWasActedOn = InWasActedOn;
    }

    private void DoAdvance_Beat()
    {
        if (_BeatTicksRemaining <= 0)
        { return; }

        _BeatTicksRemaining--;

        const auto Colour = _BeatWasActedOn
            ? playground_gym_kit::k_Colour_Beat_Acted
            : playground_gym_kit::k_Colour_Beat_Ignored;

        utils_debug_draw::DrawDebugSphere(
            GetActorLocation() + FVector(0.0, 0.0, playground_gym_kit::k_BeatHeight),
            playground_gym_kit::k_BeatRadius,
            playground_gym_kit::k_BeatSegments,
            Colour,
            playground_gym::k_ShapeDuration_SingleFrame,
            playground_gym_kit::k_BeatThickness);
    }

    // Where the burst lands is the answer: on the PLATE if the record had Q held
    // when the projectile arrived, on the pawn's own body if it did not. The plate
    // transform is a pure computation, so a burst can still be drawn where the
    // block was on the frames after the player let go.
    private void DoAdvance_ProjectileBeat()
    {
        if (_ProjectileBeatTicksRemaining <= 0)
        { return; }

        _ProjectileBeatTicksRemaining--;

        if (_ProjectileBeatVerdict == playground_gym_kit::k_ProjectileVerdict_Struck)
        {
            utils_debug_draw::DrawDebugSphere(
                GetActorLocation() + FVector(0.0, 0.0, playground_gym_kit::k_Attack_Height),
                playground_gym_kit::k_ProjectileBeatRadius,
                playground_gym_kit::k_BeatSegments,
                playground_gym_kit::k_Colour_Struck,
                playground_gym::k_ShapeDuration_SingleFrame,
                playground_gym_kit::k_BeatThickness);

            return;
        }

        const auto Parried = _ProjectileBeatVerdict == playground_gym_kit::k_ProjectileVerdict_Parried;

        utils_debug_draw::DrawDebugSphere(
            Get_BlockTransform().GetLocation(),
            Parried ? playground_gym_kit::k_ParryBeatRadius : playground_gym_kit::k_ProjectileBeatRadius,
            playground_gym_kit::k_BeatSegments,
            Parried ? playground_gym_kit::k_Colour_Parried : playground_gym_kit::k_Colour_Blocked,
            playground_gym::k_ShapeDuration_SingleFrame,
            playground_gym_kit::k_BeatThickness);
    }

    //------------------------------------------------------------------------
    // Shape plumbing
    //------------------------------------------------------------------------
    //
    // PMG has no size mutation and no parenting, so a shape that grows or follows
    // the pawn is the entity's own Transform fragment driven through the ordinary
    // deferred request (CkPmg/Claude.md, "Pattern: live-tracking overlay").

    private void DoSetShapeTransform(FCk_Handle_Pmg_DebugShape InShape, FTransform InTransform)
    {
        if (ck::Is_NOT_Valid(InShape))
        { return; }

        auto CastResult = utils_transform::DoCast(FCk_Handle(InShape));
        if (CastResult.IsSet() == false)
        { return; }

        utils_transform::Request_SetTransform(CastResult.GetValue(),
            FCk_Request_Transform_SetTransform(InTransform));
    }

    // Takes the member by reference and clears it, because a persistent shape and
    // the handle naming it have to stop existing together — a stale handle would
    // read as "the accumulator is already up" and the next charge would grow a
    // shape that is not there.
    private void DoDestroyShape(FCk_Handle_Pmg_DebugShape& InOutShape)
    {
        if (ck::Is_NOT_Valid(InOutShape))
        { return; }

        utils_entity_lifetime::Request_DestroyEntity(FCk_Handle(InOutShape));

        InOutShape = utils_pmg_debug_shape::Get_InvalidHandle();
    }

    //------------------------------------------------------------------------
    // Geometry
    //------------------------------------------------------------------------

    // Along the ACTOR's forward, which the cursor aim set earlier this same tick.
    private FVector Get_AttackLocation(float32 InForwardOffset) const
    {
        return GetActorLocation()
            + (GetActorRotation().GetForwardVector() * InForwardOffset)
            + FVector(0.0, 0.0, playground_gym_kit::k_Attack_Height);
    }

    // The accumulator sits ON the pawn and turns with it; the scale is what the
    // growth is expressed as, because PMG cannot resize a shape.
    private FTransform Get_ChargeTransform(float32 InScale) const
    {
        return FTransform(
            GetActorRotation(),
            GetActorLocation() + FVector(0.0, 0.0, playground_gym_kit::k_ChargeHeight),
            FVector(InScale, InScale, InScale));
    }

    // The plate turns WITH the pawn, unlike the readouts: it is held out along the
    // aim, so a plate that ignored the actor rotation would be a block facing
    // somewhere the player is not looking. A YZ plane's normal is the shape's own
    // forward, so the actor rotation is what makes it face outward.
    private FTransform Get_BlockTransform() const
    {
        return FTransform(
            GetActorRotation(),
            GetActorLocation()
                + (GetActorRotation().GetForwardVector() * playground_gym_kit::k_Block_ForwardOffset)
                + FVector(0.0, 0.0, playground_gym_kit::k_Block_Height),
            FVector(1.0, 1.0, 1.0));
    }

    // Identity rotation on purpose: the pawn spins with the cursor, and a readout
    // or a marker that spun with it would be unreadable exactly while the player is
    // aiming.
    private FTransform Get_MarkerTransform(float32 InHeight) const
    {
        return FTransform(
            FRotator::ZeroRotator,
            GetActorLocation() + FVector(0.0, 0.0, InHeight),
            FVector(1.0, 1.0, 1.0));
    }

    // Flat on the floor, on the camera's side of the character, run axis along the
    // screen's horizontal (rotation rationale: the readouts comment block above).
    // Read live rather than baked at creation: the framing is fixed today, but a
    // label that derives its facing can never be stranded by a camera that moves.
    private FTransform Get_ReadoutTransform(float32 InBehindOffset) const
    {
        const auto CameraYaw = utils_camera::Get_ViewRotation(_Camera).Yaw;
        const auto TowardCamera = FRotator(0.0, CameraYaw, 0.0).GetForwardVector() * -1.0;

        return FTransform(
            FRotator(-90.0, CameraYaw, 0.0),
            GetActorLocation()
                + (TowardCamera * InBehindOffset)
                + FVector(0.0, 0.0, playground_gym_kit::k_Label_FloorLift),
            FVector(1.0, 1.0, 1.0));
    }

    //------------------------------------------------------------------------
    // The readouts
    //------------------------------------------------------------------------

    private void Request_CreateReadouts()
    {
        _StateLabel = DoCreateReadoutLine(
            playground_gym_kit::k_LabelText_Idle,
            playground_gym_kit::k_Label_StateBehindOffset,
            playground_gym_kit::k_Label_StateSize,
            playground_gym_kit::k_Colour_Label_Idle);

        _InputLabel = DoCreateReadoutLine(
            "L - / - H - / - B -",
            playground_gym_kit::k_Label_InputBehindOffset,
            playground_gym_kit::k_Label_InputSize,
            playground_gym_kit::k_Colour_Label_Input);
    }

    private FCk_Handle_Pmg_DebugShape DoCreateReadoutLine(
        FString InText,
        float32 InBehindOffset,
        float32 InSize,
        FLinearColor InColour)
    {
        return utils_pmg_text_shapes::Create_Text(
            _PawnEntity,
            Get_ReadoutTransform(InBehindOffset),
            InText,
            InSize,
            InColour,
            true,
            true,
            playground_gym_kit::k_Label_LineThickness,
            ECk_Pmg_TextAlign::Center,
            ECk_Plane_Axis::YZ,
            nullptr,
            playground_gym::k_ShapeDuration_Persistent);
    }

    private void DoRefresh_Readouts(FCk_Handle_IntentSampler InSampler, int32 InLightRun, int32 InHeavyRun, int32 InBlockRun)
    {
        DoSetShapeTransform(_StateLabel, Get_ReadoutTransform(playground_gym_kit::k_Label_StateBehindOffset));
        DoSetShapeTransform(_InputLabel, Get_ReadoutTransform(playground_gym_kit::k_Label_InputBehindOffset));

        DoRefresh_StateLabel(InLightRun, InHeavyRun);
        DoRefresh_InputLabel(InSampler, InLightRun, InHeavyRun, InBlockRun);
    }

    private void DoRefresh_StateLabel(int32 InLightRun, int32 InHeavyRun)
    {
        if (_SetRejected)
        { return; }

        // Ahead of the family branch, because a combo has no family: the line names
        // which combo landed and the colour says only that it was one.
        if (Get_IsCombo())
        {
            DoSetLabel(_StateLabel, Get_ComboLabelText(_State), playground_gym_kit::k_Colour_Label_Combo);
            return;
        }

        const auto Family = Get_StateFamily();

        const auto Colour = Family == playground_gym_kit::k_Family_Light
            ? playground_gym_kit::k_Colour_Label_Light
            : playground_gym_kit::k_Colour_Label_Heavy;

        if (Get_IsCharging())
        {
            const auto Run = _State == playground_gym_kit::k_State_Charging_Light ? InLightRun : InHeavyRun;
            const auto Threshold = playground_gym_kit::k_ChargeFullFrames;

            DoSetLabel(_StateLabel, f"CHARGE {Run}f / {Threshold}f", Colour);
            return;
        }

        if (_State == playground_gym_kit::k_State_Special_Light)
        {
            DoSetLabel(_StateLabel, "SPECIAL LIGHT", playground_gym_kit::k_Colour_Label_Light);
            return;
        }

        if (_State == playground_gym_kit::k_State_Special_Heavy)
        {
            DoSetLabel(_StateLabel, "SPECIAL HEAVY", playground_gym_kit::k_Colour_Label_Heavy);
            return;
        }

        const auto Step = Get_ChainStep();

        if (Step > 0)
        {
            const auto FamilyText = Family == playground_gym_kit::k_Family_Light ? "LIGHT" : "HEAVY";

            // The buffer ANNOTATES the step rather than replacing it: which attack
            // is running is the one thing the player mid-chain needs the line for,
            // and the amber says a follow-up is queued behind it.
            if (_BufferedNext)
            {
                DoSetLabel(_StateLabel, f"{FamilyText} {Step} + BUFFERED", playground_gym_kit::k_Colour_Label_Buffer);
                return;
            }

            DoSetLabel(_StateLabel, f"{FamilyText} {Step}", Colour);
            return;
        }

        DoSetLabel(_StateLabel, playground_gym_kit::k_LabelText_Idle, playground_gym_kit::k_Colour_Label_Idle);
    }

    // The line that has to render with ZERO input. Both mouse buttons' last press
    // frame and current held run come straight off the record, so a mouse button
    // that never reaches the Slate writer reads as a press frame stuck at -1 while
    // the record's own frame counter keeps climbing — which is a different picture
    // from a kit that is not armed. Q carries only its held run, because a held run
    // IS the whole of what the block reads: a block that never rises has to be
    // separable into "the key never arrived" and "the plate never drew".
    private void DoRefresh_InputLabel(FCk_Handle_IntentSampler InSampler, int32 InLightRun, int32 InHeavyRun, int32 InBlockRun)
    {
        const auto LightPress = playground_gym::Get_LatestPressFrame(InSampler, playground_gym::k_Key_Light.GetKeyName());
        const auto HeavyPress = playground_gym::Get_LatestPressFrame(InSampler, playground_gym::k_Key_Heavy.GetKeyName());
        const auto LiveFrame  = playground_gym::Get_LiveFrameIndex(InSampler);

        const auto Armed = playground_gym::Format_Bool(
            playground_gym::Get_IsArmed(_Matcher, playground_gym::k_Key_Light) &&
            playground_gym::Get_IsArmed(_Matcher, playground_gym::k_Key_Heavy));

        DoSetLabel(_InputLabel,
            f"L p{LightPress} h{InLightRun}f | H p{HeavyPress} h{InHeavyRun}f | B h{InBlockRun}f | row {LiveFrame} | armed {Armed}",
            playground_gym_kit::k_Colour_Label_Input);
    }

    private void DoSetLabel(FCk_Handle_Pmg_DebugShape InShape, FString InText, FLinearColor InColour)
    {
        if (ck::Is_NOT_Valid(InShape))
        { return; }

        utils_pmg_debug_shape::Request_SetText(InShape, InText);
        utils_pmg_debug_shape::Request_SetColor(InShape, FCk_Request_Pmg_DebugShape_SetColor(InColour));
    }
}
