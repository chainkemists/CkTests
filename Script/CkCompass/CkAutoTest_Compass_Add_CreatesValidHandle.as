// Language=angelscript

//============================================================================
// CK COMPASS - AUTOMATION TEST: Add creates valid handle; heading sources
//============================================================================
//
// Adding a Compass to an entity with Transform returns a valid handle.
// Heading resolution is pinned for two sources:
//   - Manual: Request_SetManualHeading(37) -> Get_Heading == 37.
//   - EntityTransform: an owner whose transform yaw is 90 -> Get_Heading == 90.
//
// Isolated Y band: 56000.
//============================================================================

class UCk_AutoTest_Compass_Add_CreatesValidHandle : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle_Compass _ManualCompass;
    private FCk_Handle_Compass _TransformCompass;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        // Manual-heading compass.
        auto ManualHost = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        ManualHost.Request_OverrideToSelf();
        utils_transform::Add(ManualHost, FTransform(FRotator::ZeroRotator, FVector(0.0, 56000.0, 0.0)),
            ECk_Replication::DoesNotReplicate);

        auto ManualParams = FCk_Fragment_Compass_ParamsData();
        ManualParams.Set_HeadingSource(ECk_Compass_HeadingSource::Manual);
        _ManualCompass = utils_compass::Add(ManualHost, ManualParams);

        Assert_True(ck::IsValid(_ManualCompass),
            "utils_compass::Add should return a valid FCk_Handle_Compass");
        Assert_True(_ManualCompass == ManualHost,
            "Compass composes directly onto the host - the typed handle wraps the same entity");

        _ManualCompass.Request_SetManualHeading(37.0);

        // EntityTransform-heading compass on a host rotated to yaw 90.
        auto RotatedHost = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        RotatedHost.Request_OverrideToSelf();
        utils_transform::Add(RotatedHost,
            FTransform(FRotator(0.0, 90.0, 0.0), FVector(0.0, 56100.0, 0.0)),
            ECk_Replication::DoesNotReplicate);

        auto TransformParams = FCk_Fragment_Compass_ParamsData();
        TransformParams.Set_HeadingSource(ECk_Compass_HeadingSource::EntityTransform);
        _TransformCompass = utils_compass::Add(RotatedHost, TransformParams);

        WaitUntil(n"Check_ManualHeadingApplied", n"OnSettled_Projection");
    }

    // Request_SetManualHeading is deferred; its value landing is the settling
    // event and the only thing this test can wait on. This compass reads no
    // POIs, so there is no shared-world membership to confuse it. The
    // EntityTransform heading resolves on the same pass, so its correctness
    // stays an assertion - a broken transform-heading source is REPORTED with
    // the observed value rather than timing out anonymously.
    UFUNCTION()
    private void Check_ManualHeadingApplied(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(Math::Abs(utils_compass::Get_Heading(_ManualCompass) - 37.0) < 0.1);
    }

    UFUNCTION()
    private void OnSettled_Projection(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto ManualHeading = utils_compass::Get_Heading(_ManualCompass);
        Assert_True(Math::Abs(ManualHeading - 37.0) < 0.1,
            f"Manual heading source should report the requested heading (got {ManualHeading})");

        auto TransformHeading = utils_compass::Get_Heading(_TransformCompass);
        Assert_True(Math::Abs(TransformHeading - 90.0) < 0.5,
            f"EntityTransform heading source should report the owner transform yaw (got {TransformHeading})");

        FinishSuccess();
    }
}
