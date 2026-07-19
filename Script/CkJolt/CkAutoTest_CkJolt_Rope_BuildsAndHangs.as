// Language=angelscript

//============================================================================
// CK JOLT — AUTOMATION TEST: ROPE BUILDER PRODUCES A HANGING CHAIN
//============================================================================
//
// Create_Rope with 6 Rigid segments (40uu each) from a WORLD anchor must
// return 6 segment bodies + 6 links, and after settling the LAST segment's
// center must hang ~220uu below the anchor (5.5 * 40) with no lateral drift —
// i.e. the point-constraint chain is inextensible and anchored.
//
// Placed at an isolated Y so it never touches other autotests' physics bodies.
//============================================================================

class UCk_AutoTest_CkJolt_Rope_BuildsAndHangs : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Transform _TailTransform;

    private FVector _Anchor = FVector(0.0, 87000.0, 600.0);
    private int32 _SegmentCount = 6;
    private float _SegmentLength = 40.0;

    private float _Elapsed = 0.0;
    private float _StableTime = 0.0;
    private FVector _Last = FVector::ZeroVector;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        auto RopeParams = FCk_JoltRope_ParamsData(_Anchor);
        RopeParams.Set_SegmentCount(_SegmentCount);
        RopeParams.Set_SegmentLength(_SegmentLength);
        RopeParams.Set_SegmentRadius(5.0);
        RopeParams.Set_LinkMode(ECk_JoltRope_LinkMode::Rigid);
        // Heavy damping so the chain stops swinging well inside the test window.
        RopeParams.Set_LinearDamping(1.5);
        RopeParams.Set_AngularDamping(1.5);

        auto Rope = utils_jolt_rope::Create_Rope(_SelfHandle, RopeParams);

        Assert_Equals_Int(Rope.Get_Segments().Num(), _SegmentCount, "Segment count");
        Assert_Equals_Int(Rope.Get_Links().Num(), _SegmentCount, "Link count (anchor link + between-segments)");

        if (Rope.Get_Segments().Num() != _SegmentCount)
        {
            FinishFailure("Rope build incomplete — cannot continue to the hang check");
            return;
        }

        auto TailBody = Rope.Get_Segments()[_SegmentCount - 1];
        _TailTransform = utils_transform::DoCastChecked(TailBody);

        _Last = utils_transform::Get_EntityCurrentLocation(_TailTransform);
        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _Elapsed += float(InDeltaT.Get_Seconds());

        auto Current = utils_transform::Get_EntityCurrentLocation(_TailTransform);

        if ((Current - _Last).Size() < 0.1)
        { _StableTime += float(InDeltaT.Get_Seconds()); }
        else
        { _StableTime = 0.0; }

        _Last = Current;

        if (_StableTime >= 0.25)
        {
            auto ExpectedTailZ = _Anchor.Z - (float(_SegmentCount) - 0.5) * _SegmentLength;
            Assert_True(Math::Abs(Current.Z - ExpectedTailZ) <= 25.0,
                f"Rope tail should hang at ~Z={ExpectedTailZ} (got {Current.Z})");
            Assert_True(Math::Abs(Current.X - _Anchor.X) <= 15.0,
                f"Rope should hang straight down (X drift {Current.X - _Anchor.X})");
            FinishSuccess();
            return;
        }

        if (_Elapsed > 15.0)
        {
            FinishFailure(f"Rope never settled after {_Elapsed} seconds (tail Z={_Last.Z})");
        }
    }
}
