// Language=angelscript

//============================================================================
// CK REWIND HISTORY — NET AUTOMATION TEST: RECORDS ON AUTHORITY ONLY
//============================================================================
//
// Multi-world PIE (server + client). Both worlds create a local entity with a
// RewindHistory feature and let it sit while the record processor runs:
//   - The SERVER world must accumulate frames (it rewinds shots).
//   - The CLIENT world must record NOTHING — clients never rewind, they get
//     rewound against. Recording there would be wasted memory/CPU at best and
//    a cheat surface at worst.
//============================================================================

class UCk_AutoTest_Net_RewindHistory_RecordsOnAuthorityOnly : UCk_AutoTest_NetBase
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_RewindHistory _History;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        auto Target = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        utils_transform::Add(Target, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto HitShapes = TArray<FCk_LagComp_HitShape>();
        HitShapes.Add(FCk_LagComp_HitShape(
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.LagComp.Body"),
            UCk_Utils_Shapes_UE::Make_Sphere(FCk_ShapeSphere_Dimensions(50.0))));

        _History = UCk_Utils_RewindHistory_UE::Add(Target, FCk_Fragment_RewindHistory_ParamsData(HitShapes));

        if (ck::Is_NOT_Valid(_History))
        {
            FinishFailure("RewindHistory Add failed");
            return;
        }

        ScheduleCheck(0.5);
    }

    private void ScheduleCheck(float InDelaySeconds)
    {
        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(InDelaySeconds));
        Params.Set_StartingState(ECk_Timer_State::Running)
              .Set_Behavior(ECk_Timer_Behavior::StopOnDone);
        auto Timer = utils_timer::Add(_SelfHandle, Params);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnCheck"));
    }

    UFUNCTION()
    private void OnCheck(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto FrameCount = _History.Get_RecordedFrameCount();

        if (utils_net::Get_HasAuthority(_SelfHandle))
        {
            Assert_True(FrameCount >= 2,
                f"Server world should have recorded several frames (got {FrameCount})");
        }
        else
        {
            Assert_Equals_Int(FrameCount, 0,
                "Client world must not record hitbox history");
        }

        FinishSuccess();
    }
}
