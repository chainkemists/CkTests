// Language=angelscript

//============================================================================
// CK INPUT PLAYGROUND GYM — THE DUMMY
//============================================================================
//
// One thing to hit, and one thing that hits back. The playground's combat kit had
// nothing to land on: every swing was a shape thrown at empty floor, and a chain
// that connects looks exactly like a chain that misses. This entity is the other
// half of that sentence — it takes the swing, says which family landed it, and
// counts. It has no health, no state machine and no AI: a hit is a flash and a
// number, which is all the feedback a kit demo can honestly claim.
//
// AND IT SHOOTS, BECAUSE BLOCK NEEDS A REASON TO EXIST. Q is a held set read
// straight off the record — the deliberate contrast to the graded moves — and a
// held button with nothing to hold it against is not a demonstration. Every
// three seconds, if the player is close enough to be worth shooting, the dummy
// telegraphs and throws ONE slow projectile at where the player was standing at
// fire time. Walking out of the way beats it; holding Q beats it; PARRYING it
// sends it home; standing still with the hand off Q does not. That is the whole
// lesson.
//
// THE PLAYER OWNS THE VERDICT, NOT THE DUMMY. When a projectile reaches the pawn
// this file asks Request_ResolveProjectileImpact and renders NOTHING at the
// point of resolution — the pawn draws the outcome on its own body. The dummy
// only ACTS on the answer: a parried shot turns gold and flies back the way it
// came, and a returned shot that reaches the dummy counts exactly like a swing.
//
// THE BODY IS PMG, NOT MESHES, BECAUSE THE BODY IS THE FEEDBACK. A sphere torso
// over a flat base ring, and the torso's COLOUR is the hit feedback: it flashes
// RED for any landed hit — red is damage, full stop — via
// utils_pmg_debug_shape::Request_SetColor, which recolours a live shape in
// place; a StaticMeshComponent silhouette could not do that without a material
// instance the gym has no reason to own. The base ring is there so the torso
// reads as standing on the floor rather than floating over it.
//
// PMG HAS NO SIZE MUTATION AND NO PARENTING, so the projectile is a persistent
// sphere whose Transform fragment is driven every tick, and the floor label is
// re-anchored the same way (CkPmg/Claude.md, "Pattern: live-tracking overlay").
// The three persistent shapes plus the projectile are this file's to destroy, and
// DoEndPlay is the path that runs whether the session ended, the gym cycled, or
// the entity was torn down on its own.
//
// THE COUNTER LIES FLAT ON THE FLOOR, derived off the CAMERA the same way the
// pawn's readouts are: FRotator(-90, CameraYaw, 0) on a YZ text plate is the one
// orientation that reads face-on under this gym's fixed top-down framing. The yaw
// is asked of the PAWN rather than re-derived here — the pawn already owns the
// camera director and hands the number over — and falls back to zero for the
// frames before the pawn has registered, which is a label reading sideways for a
// tick rather than a second camera authority.
//============================================================================

namespace playground_gym_enemy
{
    //------------------------------------------------------------------------
    // The body
    //------------------------------------------------------------------------

    const float32 k_Torso_Radius   = 60.0f;
    const int32   k_Torso_Segments = 16;
    const int32   k_Torso_Rings    = 16;
    const float32 k_Torso_Height   = 60.0f;

    // Wider than the torso so the silhouette reads as a thing standing on a spot
    // rather than a ball resting on the floor.
    const float32 k_Base_Radius   = 95.0f;
    const int32   k_Base_Segments = 24;
    const float32 k_Base_Lift     = 2.0f;

    const float32 k_ShapeLineThickness = 2.0f;

    //------------------------------------------------------------------------
    // The hit feedback
    //------------------------------------------------------------------------
    //
    // RED, whatever landed it. Red is the one colour the kit never throws a
    // swing in, so on this body it can only mean "that hit" — the maintainer's
    // ruling over the earlier family-coloured tints, which read as nothing at a
    // glance. Long enough to register; there is no damage model here, only
    // "that landed" and the counter.

    const FLinearColor k_Colour_Torso_Idle = FLinearColor(0.55f, 0.57f, 0.60f, 0.65f);
    const FLinearColor k_Colour_Base       = FLinearColor(0.30f, 0.32f, 0.36f, 0.55f);

    const FLinearColor k_Colour_Hit       = FLinearColor(1.00f, 0.15f, 0.15f, 1.00f);
    const FLinearColor k_Colour_Telegraph = FLinearColor(1.00f, 0.75f, 0.10f, 0.95f);

    const float32 k_HitFlashSeconds = 0.40f;

    // The torso's colour is requested only when the tint CHANGES, so the codes
    // below are what "what colour am I already" is stored as. A colour compared
    // against a colour would be a float comparison asked once per tick forever.
    const int32 k_Tint_Idle      = 0;
    const int32 k_Tint_Hit       = 1;
    const int32 k_Tint_Telegraph = 2;

    //------------------------------------------------------------------------
    // The counter
    //------------------------------------------------------------------------

    const float32 k_Label_BehindOffset  = 210.0f;
    const float32 k_Label_Size          = 34.0f;
    const float32 k_Label_FloorLift     = 3.0f;
    const float32 k_Label_LineThickness = 2.0f;

    const FLinearColor k_Colour_Label = FLinearColor(0.80f, 0.82f, 0.86f, 0.95f);

    //------------------------------------------------------------------------
    // The shot
    //------------------------------------------------------------------------
    //
    // Slow and telegraphed on purpose. 700cm/s over a 1600cm engagement range is
    // more than two seconds of flight at the far edge, which is a projectile a
    // player can watch, decide about, and either sidestep or meet with Q. A fast
    // one would only ever be blocked by accident.

    const float32 k_Fire_IntervalSeconds = 3.0f;
    const float32 k_Fire_RangeCm         = 1600.0f;
    const float32 k_Telegraph_Seconds    = 0.4f;

    const float32 k_Projectile_Radius            = 25.0f;
    const int32   k_Projectile_Segments          = 10;
    const int32   k_Projectile_Rings             = 10;
    const float32 k_Projectile_Height            = 60.0f;
    const float32 k_Projectile_SpeedCmPerSecond  = 700.0f;
    const float32 k_Projectile_HitRadiusCm       = 80.0f;
    const float32 k_Projectile_MaxFlightSeconds  = 4.0f;

    const FLinearColor k_Colour_Projectile = FLinearColor(1.00f, 0.70f, 0.10f, 0.90f);
}

// --------------------------------------------------------------------------------------------------------------------

class UCk_EntityScript_PlaygroundGym_Enemy : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    // The only thing the spawner decides. FCk_Gym_TransformSpawnParams is the
    // shared transform-only params struct every gym entity script in this plugin
    // is spawned with (CkGym_Utils.as) — the spawn machinery matches on the
    // PROPERTY NAME, so an entity script that names its exposed transform
    // InitialTransform is spawnable without a params struct of its own.
    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    private FCk_Handle_Pmg_DebugShape _Torso;
    private FCk_Handle_Pmg_DebugShape _Base;
    private FCk_Handle_Pmg_DebugShape _Label;
    private FCk_Handle_Pmg_DebugShape _Projectile;

    // Found by asking the world for the local pawn and retried from the tick: the
    // dummy is spawned BY the pawn, but nothing guarantees a spawned entity
    // script constructs before the pawn is the possessed one, and a registration
    // that only happened once would be a dummy nothing could hit.
    private ACk_PlaygroundGym_Pawn _Pawn;

    private int32   _HitCount          = 0;
    private float32 _HitFlashRemaining = 0.0f;
    private int32   _TintApplied       = playground_gym_enemy::k_Tint_Idle;

    private int32 _LabelCountRendered = -1;

    private float32 _FireElapsed        = 0.0f;
    private float32 _TelegraphRemaining = 0.0f;

    private FVector _ProjectileLocation  = FVector::ZeroVector;
    private FVector _ProjectileDirection = FVector::ZeroVector;
    private float32 _ProjectileAge       = 0.0f;
    private bool    _ProjectileReflected = false;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        DoCreateBody(InHandle);
        DoCreateLabel(InHandle);

        // The pawn may already be possessed by now; if it is not, the tick asks
        // again until it is.
        DoTryRegisterWithPawn();

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnEnemyTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    // The one path that runs whether the viewer stopped the session, cycled to the
    // next gym, or the dummy was destroyed on its own. Four persistent shapes and
    // no clock of their own, so nothing else can take them down.
    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        DoDestroyShape(_Projectile);
        DoDestroyShape(_Label);
        DoDestroyShape(_Torso);
        DoDestroyShape(_Base);
    }

    //------------------------------------------------------------------------
    // What the pawn calls
    //------------------------------------------------------------------------

    // A jab, a special, a combo and a returned projectile are all the same one
    // hit: a red flash and a number. What landed it is the pawn's story, told in
    // the swing's own colour on the way in.
    void Request_TakeHit()
    {
        _HitCount++;
        _HitFlashRemaining = playground_gym_enemy::k_HitFlashSeconds;
    }

    FVector Get_Location() const
    {
        return InitialTransform.GetLocation();
    }

    //------------------------------------------------------------------------
    // The tick
    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnEnemyTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto _CkPerfScope = ck::ScopedStat();

        const auto DeltaSeconds = float32(InDeltaT.Get_Seconds());

        DoTryRegisterWithPawn();

        DoAdvance_HitFlash(DeltaSeconds);
        DoAdvance_Fire(DeltaSeconds);
        DoAdvance_Projectile(DeltaSeconds);

        DoRefresh_TorsoColour();
        DoRefresh_Label();
    }

    //------------------------------------------------------------------------
    // Registration
    //------------------------------------------------------------------------

    private void DoTryRegisterWithPawn()
    {
        if (ck::IsValid(_Pawn))
        { return; }

        auto CastResult = Cast<ACk_PlaygroundGym_Pawn>(Gameplay::GetPlayerPawn(0));
        if (CastResult == nullptr)
        { return; }

        _Pawn = CastResult;
        _Pawn.Request_RegisterEnemy(this);
    }

    //------------------------------------------------------------------------
    // Taking a hit
    //------------------------------------------------------------------------

    private void DoAdvance_HitFlash(float32 InDeltaSeconds)
    {
        if (_HitFlashRemaining <= 0.0f)
        { return; }

        _HitFlashRemaining -= InDeltaSeconds;

        if (_HitFlashRemaining > 0.0f)
        { return; }

        _HitFlashRemaining = 0.0f;
    }

    // The telegraph outranks the hit flash: a dummy that swallowed its own wind-up
    // because the player was mid-chain would be hiding the one warning the shot
    // has.
    private void DoRefresh_TorsoColour()
    {
        auto Wanted = playground_gym_enemy::k_Tint_Idle;

        if (_HitFlashRemaining > 0.0f)
        { Wanted = playground_gym_enemy::k_Tint_Hit; }

        if (_TelegraphRemaining > 0.0f)
        { Wanted = playground_gym_enemy::k_Tint_Telegraph; }

        if (Wanted == _TintApplied)
        { return; }

        _TintApplied = Wanted;

        if (ck::Is_NOT_Valid(_Torso))
        { return; }

        utils_pmg_debug_shape::Request_SetColor(_Torso,
            FCk_Request_Pmg_DebugShape_SetColor(Get_ColourForTint(Wanted)));
    }

    private FLinearColor Get_ColourForTint(int32 InTint) const
    {
        if (InTint == playground_gym_enemy::k_Tint_Telegraph)
        { return playground_gym_enemy::k_Colour_Telegraph; }

        if (InTint == playground_gym_enemy::k_Tint_Hit)
        { return playground_gym_enemy::k_Colour_Hit; }

        return playground_gym_enemy::k_Colour_Torso_Idle;
    }

    //------------------------------------------------------------------------
    // Shooting
    //------------------------------------------------------------------------
    //
    // ONE PROJECTILE IN FLIGHT. The cadence clock does not advance into a second
    // shot while the first is still travelling, so a player who backs off to the
    // edge of the range never accumulates a volley they cannot read.
    //
    // The clock is HELD at the interval while the player is out of range rather
    // than reset, so walking into range is answered on the next tick — the dummy
    // is a sparring partner, not an ambush.

    private void DoAdvance_Fire(float32 InDeltaSeconds)
    {
        if (_TelegraphRemaining > 0.0f)
        {
            _TelegraphRemaining -= InDeltaSeconds;

            if (_TelegraphRemaining > 0.0f)
            { return; }

            _TelegraphRemaining = 0.0f;
            DoFireProjectile();
            return;
        }

        if (ck::IsValid(_Projectile))
        { return; }

        if (ck::Is_NOT_Valid(_Pawn))
        { return; }

        _FireElapsed += InDeltaSeconds;

        if (_FireElapsed < playground_gym_enemy::k_Fire_IntervalSeconds)
        { return; }

        if (Get_PlanarDistanceToPawn() > playground_gym_enemy::k_Fire_RangeCm)
        {
            _FireElapsed = playground_gym_enemy::k_Fire_IntervalSeconds;
            return;
        }

        _FireElapsed = 0.0f;
        _TelegraphRemaining = playground_gym_enemy::k_Telegraph_Seconds;
    }

    // Aimed at where the pawn IS at fire time and never corrected after — that is
    // what makes walking out of the way a real answer rather than a delay.
    private void DoFireProjectile()
    {
        if (ck::Is_NOT_Valid(_Pawn))
        { return; }

        const auto Origin = Get_ProjectileOrigin();

        auto ToPawn = _Pawn.GetActorLocation() - Origin;
        ToPawn.Z = 0.0;

        if (ToPawn.IsNearlyZero())
        { return; }

        _ProjectileDirection = ToPawn.GetSafeNormal();
        _ProjectileLocation  = Origin;
        _ProjectileAge       = 0.0f;
        _ProjectileReflected = false;

        _Projectile = utils_pmg_basic_shapes::Create_Sphere(
            ck::ToEntity(this),
            FTransform(_ProjectileLocation),
            playground_gym_enemy::k_Projectile_Radius,
            playground_gym_enemy::k_Projectile_Segments,
            playground_gym_enemy::k_Projectile_Rings,
            ECk_Plane_Axis::XY,
            playground_gym_enemy::k_Colour_Projectile,
            true,
            playground_gym_enemy::k_ShapeLineThickness,
            playground_gym::k_ShapeDuration_Persistent);
    }

    // The dummy renders NOTHING at resolution: it asks the pawn for the verdict
    // and acts on the answer. A struck or blocked shot ends at the pawn; a
    // PARRIED one turns gold, flies back the way it came, and counts a hit when
    // it arrives — the one-in-flight rule holds through the return leg, so a
    // dummy waiting on its own returned shot cannot fire through it. The age
    // resets on the turn because the return is a second flight, not the tail
    // of the first.
    private void DoAdvance_Projectile(float32 InDeltaSeconds)
    {
        if (ck::Is_NOT_Valid(_Projectile))
        { return; }

        _ProjectileAge += InDeltaSeconds;
        _ProjectileLocation += _ProjectileDirection
            * (playground_gym_enemy::k_Projectile_SpeedCmPerSecond * InDeltaSeconds);

        DoSetShapeTransform(_Projectile, FTransform(_ProjectileLocation));

        if (_ProjectileReflected)
        {
            auto ToHome = Get_ProjectileOrigin() - _ProjectileLocation;
            ToHome.Z = 0.0;

            if (ToHome.Size() <= playground_gym_enemy::k_Projectile_HitRadiusCm)
            {
                Request_TakeHit();
                DoDestroyShape(_Projectile);
                return;
            }
        }
        else if (ck::IsValid(_Pawn))
        {
            auto ToPawn = _Pawn.GetActorLocation() - _ProjectileLocation;
            ToPawn.Z = 0.0;

            if (ToPawn.Size() <= playground_gym_enemy::k_Projectile_HitRadiusCm)
            {
                const auto Verdict = _Pawn.Request_ResolveProjectileImpact();

                if (Verdict != playground_gym_kit::k_ProjectileVerdict_Parried)
                {
                    DoDestroyShape(_Projectile);
                    return;
                }

                auto ToHome = Get_ProjectileOrigin() - _ProjectileLocation;
                ToHome.Z = 0.0;

                if (ToHome.IsNearlyZero())
                {
                    DoDestroyShape(_Projectile);
                    return;
                }

                _ProjectileReflected = true;
                _ProjectileDirection = ToHome.GetSafeNormal();
                _ProjectileAge       = 0.0f;

                utils_pmg_debug_shape::Request_SetColor(_Projectile,
                    FCk_Request_Pmg_DebugShape_SetColor(playground_gym_kit::k_Colour_Parried));

                return;
            }
        }

        if (_ProjectileAge >= playground_gym_enemy::k_Projectile_MaxFlightSeconds)
        { DoDestroyShape(_Projectile); }
    }

    private float32 Get_PlanarDistanceToPawn() const
    {
        if (ck::Is_NOT_Valid(_Pawn))
        { return playground_gym_enemy::k_Fire_RangeCm + 1.0f; }

        auto ToPawn = _Pawn.GetActorLocation() - InitialTransform.GetLocation();
        ToPawn.Z = 0.0;

        return float32(ToPawn.Size());
    }

    private FVector Get_ProjectileOrigin() const
    {
        return InitialTransform.GetLocation()
            + FVector(0.0, 0.0, playground_gym_enemy::k_Projectile_Height);
    }

    //------------------------------------------------------------------------
    // The shapes
    //------------------------------------------------------------------------

    private void DoCreateBody(FCk_Handle& InHandle)
    {
        const auto Ground = InitialTransform.GetLocation();

        _Base = utils_pmg_flat_shapes::Create_Circle(
            InHandle,
            FTransform(Ground + FVector(0.0, 0.0, playground_gym_enemy::k_Base_Lift)),
            playground_gym_enemy::k_Base_Radius,
            playground_gym_enemy::k_Base_Segments,
            playground_gym_enemy::k_Colour_Base,
            true,
            playground_gym_enemy::k_ShapeLineThickness,
            false,
            ECk_Plane_Axis::XY,
            playground_gym::k_ShapeDuration_Persistent);

        _Torso = utils_pmg_basic_shapes::Create_Sphere(
            InHandle,
            FTransform(Ground + FVector(0.0, 0.0, playground_gym_enemy::k_Torso_Height)),
            playground_gym_enemy::k_Torso_Radius,
            playground_gym_enemy::k_Torso_Segments,
            playground_gym_enemy::k_Torso_Rings,
            ECk_Plane_Axis::XY,
            playground_gym_enemy::k_Colour_Torso_Idle,
            true,
            playground_gym_enemy::k_ShapeLineThickness,
            playground_gym::k_ShapeDuration_Persistent);
    }

    private void DoCreateLabel(FCk_Handle& InHandle)
    {
        _Label = utils_pmg_text_shapes::Create_Text(
            InHandle,
            Get_LabelTransform(),
            Get_LabelText(),
            playground_gym_enemy::k_Label_Size,
            playground_gym_enemy::k_Colour_Label,
            true,
            true,
            playground_gym_enemy::k_Label_LineThickness,
            ECk_Pmg_TextAlign::Center,
            ECk_Plane_Axis::YZ,
            nullptr,
            playground_gym::k_ShapeDuration_Persistent);

        _LabelCountRendered = _HitCount;
    }

    // The transform is re-driven every tick and the TEXT only when the number
    // changes: a Request_SetText per frame would be a deferred request per frame
    // saying the same thing.
    private void DoRefresh_Label()
    {
        DoSetShapeTransform(_Label, Get_LabelTransform());

        if (_LabelCountRendered == _HitCount)
        { return; }

        _LabelCountRendered = _HitCount;

        if (ck::Is_NOT_Valid(_Label))
        { return; }

        utils_pmg_debug_shape::Request_SetText(_Label, Get_LabelText());
    }

    private FString Get_LabelText() const
    {
        const auto Count = _HitCount;
        return f"HITS {Count}";
    }

    // The pawn's floor-text recipe: a YZ text plate tipped flat by -90 pitch and
    // turned to the camera's yaw reads face-on under this gym's fixed framing.
    // Zero yaw until the pawn has registered — a label reading sideways for the
    // first frames beats a second opinion about where the camera is.
    private FTransform Get_LabelTransform() const
    {
        const auto CameraYaw = Get_CameraYaw();
        const auto TowardCamera = FRotator(0.0, CameraYaw, 0.0).GetForwardVector() * -1.0;

        return FTransform(
            FRotator(-90.0, CameraYaw, 0.0),
            InitialTransform.GetLocation()
                + (TowardCamera * playground_gym_enemy::k_Label_BehindOffset)
                + FVector(0.0, 0.0, playground_gym_enemy::k_Label_FloorLift),
            FVector(1.0, 1.0, 1.0));
    }

    private float64 Get_CameraYaw() const
    {
        if (ck::Is_NOT_Valid(_Pawn))
        { return 0.0; }

        return _Pawn.Get_CameraYaw();
    }

    //------------------------------------------------------------------------
    // Shape plumbing
    //------------------------------------------------------------------------
    //
    // PMG has no size mutation and no parenting, so a shape that moves is the
    // entity's own Transform fragment driven through the ordinary deferred request
    // (CkPmg/Claude.md, "Pattern: live-tracking overlay").

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
    // the handle naming it have to stop existing together — a stale projectile
    // handle would read as "one is still in flight" and the dummy would never
    // shoot again.
    private void DoDestroyShape(FCk_Handle_Pmg_DebugShape& InOutShape)
    {
        if (ck::Is_NOT_Valid(InOutShape))
        { return; }

        utils_entity_lifetime::Request_DestroyEntity(FCk_Handle(InOutShape));

        InOutShape = utils_pmg_debug_shape::Get_InvalidHandle();
    }
}
