// Language=angelscript

class ACk_ProceduralAnimationDebugger_PieFixture : AActor
{
    default bReplicates = false;

    UPROPERTY(DefaultComponent, RootComponent)
    USceneComponent SceneRoot;

    private FCk_Handle _Owner;
    private TArray<FCkProceduralAnimationGym_Fixture> _Courses;
    private bool _Ended = false;
    private bool _ResetPending = false;

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto Pending = utils_entity_script_with_actor::Request_SpawnEntityScript_OnActor(
            this, UCk_ProceduralAnimationDebugger_PieFixture_EntityScript);
        utils_pending_entity_script::Promise_OnConstructed(Pending,
            FCk_Delegate_EntityScript_Constructed(this, n"OnConstructed"));
    }

    UFUNCTION()
    private void OnConstructed(FCk_Handle_EntityScript InEntityScript)
    {
        auto Handle = FCk_Handle(InEntityScript);
        if (_Ended)
        {
            utils_entity_lifetime::Request_DestroyEntity(Handle);
            return;
        }
        _Owner = Handle;
        for (auto Index = 0; Index < 3; Index++)
        {
            _Courses.Add(FCkProceduralAnimationGym_Fixture());
        }
        _ResetPending = true;
    }

    UFUNCTION(BlueprintOverride)
    void Tick(float InDeltaSeconds)
    {
        if (_Ended || ck::Is_NOT_Valid(_Owner))
        {
            return;
        }
        if (_ResetPending)
        {
            for (auto Course : _Courses)
            {
                if (Course.Get_IsDestroyed() == false)
                {
                    return;
                }
            }
            auto Created = _Courses[0].Create(_Owner, FVector(120000.0, 30000.0, 600.0),
                ECkProceduralAnimationGym_Course::Uneven, false);
            Created = _Courses[1].Create(_Owner, FVector(120000.0, 33000.0, 600.0),
                ECkProceduralAnimationGym_Course::RampWall, false) && Created;
            Created = _Courses[2].Create(_Owner, FVector(120000.0, 37000.0, 600.0),
                ECkProceduralAnimationGym_Course::Ring, false) && Created;
            if (Created == false)
            {
                ck::Error("[FAIL] Procedural animation debugger PIE fixture could not create its three courses");
            }
            _ResetPending = false;
        }
        for (auto Index = 0; Index < _Courses.Num(); Index++)
        {
            _Courses[Index].Update(true, false);
            if (_Courses[Index].CompositionError.IsEmpty() == false)
            {
                ck::Error(f"[FAIL] Procedural animation debugger PIE fixture: {_Courses[Index].CompositionError}");
                _Courses[Index].CompositionError = "";
            }
        }
    }

    UFUNCTION()
    int32 Request_ResetFixture()
    {
        if (_Ended || ck::Is_NOT_Valid(_Owner))
        {
            return 0;
        }
        for (auto Index = 0; Index < _Courses.Num(); Index++)
        {
            _Courses[Index].Request_Destroy();
        }
        _ResetPending = true;
        return 1;
    }

    // Destroys the hip segment of the first crawler's first leg, which fails exactly that leg's rig.
    UFUNCTION()
    int32 Request_DestroyFirstSegment()
    {
        if (_Ended || _ResetPending || _Courses.Num() != 3 ||
            _Courses[0].Get_IsReady() == false || _Courses[0].Crawlers[0].Legs.Num() == 0)
        {
            return 0;
        }
        auto Rig = utils_procedural_rig::DoCast(_Courses[0].Crawlers[0].Legs[0]);
        if (Rig.IsSet() == false)
        {
            return 0;
        }
        auto Segments = utils_procedural_rig::Get_Chain(Rig.GetValue()).Get_Segments();
        if (Segments.Num() == 0)
        {
            return 0;
        }
        auto Segment = FCk_Handle(Segments[0]);
        utils_entity_lifetime::Request_DestroyEntity(Segment);
        return 1;
    }

    UFUNCTION(BlueprintOverride)
    void EndPlay(EEndPlayReason InReason)
    {
        _Ended = true;
        if (ck::IsValid(_Owner))
        {
            utils_entity_lifetime::Request_DestroyEntity(_Owner);
        }
    }
}
