// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_ResetAndOwnerDestruction : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private FCk_Handle _Owner;
    private FVector _FirstOrigin = FVector(120000.0, 45000.0, 600.0);
    private FVector _SecondOrigin = FVector(120000.0, 47500.0, 900.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Owner = InHandle;
        _Owner = utils_entity_lifetime::Request_CreateEntity(Owner);
        _Owner.Request_OverrideToSelf();
        if (_Fixture.Create(_Owner, _FirstOrigin, ECkProceduralAnimationGym_Course::Flat, false) == false)
        {
            FinishFailure("The owned locomotion fixture could not be created");
            return;
        }
        Add_Step_WaitUntil("first fixture walks", n"Check_Walking", 1200);
        Add_Step("request reset", n"Step_Reset");
        Add_Step_WaitUntil("old entities AND old collision have left the world", n"Check_FirstDestroyed");
        Add_Step("rebuild at a different non-origin height", n"Step_Rebuild");
        Add_Step_WaitUntil("rebuilt fixture walks using fresh contacts", n"Check_Walking", 1200);
        Add_Step("destroy only the external lifetime owner", n"Step_DestroyOwner");
        Add_Step_WaitUntil("owner destruction removes every body and visual part", n"Check_AllDestroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_Walking(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        auto Result = OutResult;
        Result.Set(_Fixture.Get_HasObservedWalking());
    }

    UFUNCTION()
    private void Step_Reset(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(HasFloor(_FirstOrigin), "The first fixture published actual collision before reset");
        _Fixture.Request_Destroy();
        Assert_True(_Fixture.Create(_Owner, _SecondOrigin, ECkProceduralAnimationGym_Course::Flat, false) == false,
            "A reset cannot overlap replacement geometry with a still-live lifetime subtree");
    }

    bool HasFloor(FVector InOrigin)
    {
        auto Hit = utils_jolt_query::Get_RayCast(InOrigin + FVector(0.0, 0.0, 100.0),
            InOrigin - FVector(0.0, 0.0, 100.0), FCk_Jolt_QueryFilter());
        return Hit.Get_HasHit();
    }

    UFUNCTION()
    private void Check_FirstDestroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Fixture.Get_IsDestroyed() && HasFloor(_FirstOrigin) == false);
    }

    UFUNCTION()
    private void Step_Rebuild(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_Fixture.Create(_Owner, _SecondOrigin, ECkProceduralAnimationGym_Course::Flat, false),
            "The same fixture can rebuild after retirement without retaining old contacts");
    }

    UFUNCTION()
    private void Step_DestroyOwner(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(HasFloor(_FirstOrigin) == false && HasFloor(_SecondOrigin),
            "Only replacement collision remains after reset");
        utils_entity_lifetime::Request_DestroyEntity(_Owner);
    }

    UFUNCTION()
    private void Check_AllDestroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::Is_NOT_Valid(_Owner) && _Fixture.Get_IsDestroyed() && HasFloor(_SecondOrigin) == false);
    }
}
