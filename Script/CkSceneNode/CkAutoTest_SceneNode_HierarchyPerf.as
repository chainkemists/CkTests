// Language=angelscript

//============================================================================
// CK SCENE NODE - PERF READOUT AUTOTESTS (static hierarchy vs one dirty root)
//============================================================================
//
// Paired measurement-only harness. Both arms create the same 512 independent
// bare Transform roots, each with four SceneNode links and one inert
// USceneComponent owned by every link. Static measures the resident hierarchy
// view / parallel-dispatch floor. OneDirtyRoot moves only root zero during the
// sample, so the delta includes exactly one four-link propagation chain and
// its downstream UnrealComponent pushes.
//
// No timing threshold: these are machine-relative readouts. Setup failures and
// zero samples are the only failure conditions.
//============================================================================

class UCk_AutoTest_SceneNode_HierarchyPerf_Static : UCk_AutoTest_Base
{
    private const int32 ChainCount = 512;
    private const int32 LinksPerChain = 4;
    private const float32 WarmupSeconds = 3.0f;
    private const float32 SampleSeconds = 6.0f;

    private FCk_Handle _TestEntity;
    private TArray<FCk_Handle_UnrealComponent> _Components;
    private float32 _Elapsed = 0.0f;
    private float32 _SampleSum = 0.0f;
    private float32 _SampleMax = 0.0f;
    private int32 _SampleCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _TestEntity = InHandle;

        Set_CVarForTest(n"t.MaxFPS", "0");
        Set_CVarForTest(n"r.VSync", "0");

        for (int32 ChainIndex = 0; ChainIndex < ChainCount; ++ChainIndex)
        {
            auto RootEntity = utils_entity_lifetime::Request_CreateEntity(_TestEntity);
            auto ParentTransform = utils_transform::Add(
                RootEntity, FTransform::Identity, ECk_Replication::DoesNotReplicate);
            if (ck::Is_NOT_Valid(ParentTransform))
            {
                FinishFailure(f"Static: failed to add root Transform for chain {ChainIndex}");
                return;
            }

            for (int32 LinkIndex = 0; LinkIndex < LinksPerChain; ++LinkIndex)
            {
                const auto Local = FTransform(
                    FRotator::ZeroRotator,
                    FVector(100.0f, 0.0f, 0.0f),
                    FVector::OneVector);
                auto Node = utils_scene_node::Create(ParentTransform, Local);
                if (ck::Is_NOT_Valid(Node))
                {
                    FinishFailure(f"Static: failed to create node {LinkIndex} for chain {ChainIndex}");
                    return;
                }

                ParentTransform = Node.As_Transform();
                auto NodeEntity = FCk_Handle(ParentTransform);
                const auto Params = utils_unreal_component::Make_Params(
                    USceneComponent, ECk_UnrealComponent_TickPolicy::DoNotTick, n"SceneNodePerf");
                auto Component = utils_unreal_component::Add(NodeEntity, Params);
                if (ck::Is_NOT_Valid(Component))
                {
                    FinishFailure(f"Static: failed to add scene component for node {LinkIndex} in chain {ChainIndex}");
                    return;
                }

                _Components.Add(Component);
            }
        }

        WaitUntil(n"Check_ComponentsReady", n"OnComponentsReady");
    }

    UFUNCTION()
    private void Check_ComponentsReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        for (const auto& Component : _Components)
        {
            if (ck::Is_NOT_Valid(utils_unreal_component::Get_Component(Component)))
            {
                Result.Set(false);
                return;
            }
        }

        Result.Set(true);
    }

    UFUNCTION()
    private void OnComponentsReady(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        utils_timer::Create_Tick(_TestEntity, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        const auto DeltaSeconds = float32(InDeltaT.Get_Seconds());
        _Elapsed += DeltaSeconds;

        if (_Elapsed <= WarmupSeconds)
        { return; }

        if (_Elapsed <= WarmupSeconds + SampleSeconds)
        {
            _SampleSum += DeltaSeconds;
            if (DeltaSeconds > _SampleMax)
            { _SampleMax = DeltaSeconds; }
            ++_SampleCount;
            return;
        }

        if (_SampleCount == 0)
        {
            FinishFailure("Static: no frames sampled");
            return;
        }

        const auto AvgMs = (_SampleSum / float32(_SampleCount)) * 1000.0f;
        const auto MaxMs = _SampleMax * 1000.0f;
        const auto Fps = float32(_SampleCount) / _SampleSum;
        Log(f"[CkSceneNode PERF][Static] chains=512 depth=4 nodes=2048 components=2048 dirtyRoots=0 dirtyDescendants=0 frames={_SampleCount} avg={AvgMs} ms max={MaxMs} ms fps={Fps}");
        FinishSuccess();
    }
}

class ACk_AutoTest_SceneNode_HierarchyPerf_Static_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_SceneNode_HierarchyPerf_Static;
    default _TimeoutSeconds = 45.0f;
}

class UCk_AutoTest_SceneNode_HierarchyPerf_OneDirtyRoot : UCk_AutoTest_Base
{
    private const int32 ChainCount = 512;
    private const int32 LinksPerChain = 4;
    private const float32 WarmupSeconds = 3.0f;
    private const float32 SampleSeconds = 6.0f;
    private const float32 DirtyYawDegrees = 0.01f;

    private FCk_Handle _TestEntity;
    private FCk_Handle_Transform _DirtyRoot;
    private TArray<FCk_Handle_UnrealComponent> _Components;
    private float32 _Elapsed = 0.0f;
    private float32 _SampleSum = 0.0f;
    private float32 _SampleMax = 0.0f;
    private int32 _SampleCount = 0;
    private bool _ApplyPositiveYaw = true;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _TestEntity = InHandle;

        Set_CVarForTest(n"t.MaxFPS", "0");
        Set_CVarForTest(n"r.VSync", "0");

        for (int32 ChainIndex = 0; ChainIndex < ChainCount; ++ChainIndex)
        {
            auto RootEntity = utils_entity_lifetime::Request_CreateEntity(_TestEntity);
            auto ParentTransform = utils_transform::Add(
                RootEntity, FTransform::Identity, ECk_Replication::DoesNotReplicate);
            if (ck::Is_NOT_Valid(ParentTransform))
            {
                FinishFailure(f"OneDirtyRoot: failed to add root Transform for chain {ChainIndex}");
                return;
            }

            if (ChainIndex == 0)
            { _DirtyRoot = ParentTransform; }

            for (int32 LinkIndex = 0; LinkIndex < LinksPerChain; ++LinkIndex)
            {
                const auto Local = FTransform(
                    FRotator::ZeroRotator,
                    FVector(100.0f, 0.0f, 0.0f),
                    FVector::OneVector);
                auto Node = utils_scene_node::Create(ParentTransform, Local);
                if (ck::Is_NOT_Valid(Node))
                {
                    FinishFailure(f"OneDirtyRoot: failed to create node {LinkIndex} for chain {ChainIndex}");
                    return;
                }

                ParentTransform = Node.As_Transform();
                auto NodeEntity = FCk_Handle(ParentTransform);
                const auto Params = utils_unreal_component::Make_Params(
                    USceneComponent, ECk_UnrealComponent_TickPolicy::DoNotTick, n"SceneNodePerf");
                auto Component = utils_unreal_component::Add(NodeEntity, Params);
                if (ck::Is_NOT_Valid(Component))
                {
                    FinishFailure(f"OneDirtyRoot: failed to add scene component for node {LinkIndex} in chain {ChainIndex}");
                    return;
                }

                _Components.Add(Component);
            }
        }

        if (ck::Is_NOT_Valid(_DirtyRoot))
        {
            FinishFailure("OneDirtyRoot: chain zero did not produce a valid root Transform");
            return;
        }

        WaitUntil(n"Check_ComponentsReady", n"OnComponentsReady");
    }

    UFUNCTION()
    private void Check_ComponentsReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        for (const auto& Component : _Components)
        {
            if (ck::Is_NOT_Valid(utils_unreal_component::Get_Component(Component)))
            {
                Result.Set(false);
                return;
            }
        }

        Result.Set(true);
    }

    UFUNCTION()
    private void OnComponentsReady(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        utils_timer::Create_Tick(_TestEntity, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        const auto DeltaSeconds = float32(InDeltaT.Get_Seconds());
        _Elapsed += DeltaSeconds;

        if (_Elapsed <= WarmupSeconds)
        { return; }

        if (_Elapsed <= WarmupSeconds + SampleSeconds)
        {
            const auto Yaw = _ApplyPositiveYaw ? DirtyYawDegrees : -DirtyYawDegrees;
            utils_transform::Request_AddRotationOffset(
                _DirtyRoot, FRotator(0.0f, Yaw, 0.0f), ECk_LocalWorld::World);
            _ApplyPositiveYaw = ! _ApplyPositiveYaw;

            _SampleSum += DeltaSeconds;
            if (DeltaSeconds > _SampleMax)
            { _SampleMax = DeltaSeconds; }
            ++_SampleCount;
            return;
        }

        if (_SampleCount == 0)
        {
            FinishFailure("OneDirtyRoot: no frames sampled");
            return;
        }

        const auto AvgMs = (_SampleSum / float32(_SampleCount)) * 1000.0f;
        const auto MaxMs = _SampleMax * 1000.0f;
        const auto Fps = float32(_SampleCount) / _SampleSum;
        Log(f"[CkSceneNode PERF][OneDirtyRoot] chains=512 depth=4 nodes=2048 components=2048 dirtyRoots=1 dirtyDescendants=4 frames={_SampleCount} avg={AvgMs} ms max={MaxMs} ms fps={Fps}");
        FinishSuccess();
    }
}

class ACk_AutoTest_SceneNode_HierarchyPerf_OneDirtyRoot_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_SceneNode_HierarchyPerf_OneDirtyRoot;
    default _TimeoutSeconds = 45.0f;
}
