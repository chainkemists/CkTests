// Language=angelscript

//============================================================================
// CK VAT GYM - stations
//============================================================================
//
// Three stations exercising the CkVat playback surface on baked content:
//   - ClipCycle:  single instance; auto-cycles every baked clip (crossfade),
//                 then rate 2.0 / 0.5, freeze, resume. OnClipFinished counter.
//   - Turntable:  single instance rotating in yaw while looping a clip
//                 the VAT-normals check: lighting must stay consistent as it
//                 turns (tangent-frame normals are instance-invariant).
//   - CrowdField: N instances (default 100), RandomPerInstance phase offset,
//                 auto-switches the whole field's clip. Instancing +
//                 write-on-clip-change-only demo.
//
// All stations share the collection contract in CkVatGym_Shared.as and
// rebuild in place on Ck_GymVat_SetCollection.
//
//============================================================================

// ====================================================================================================================
// Station 1 - ClipCycle
// ====================================================================================================================

class UCk_EntityScript_VatGym_ClipCycle : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    private UCk_VatCollection_Data _Collection;
    private FString _CollectionPath = vat_gym::DefaultCollectionPath;
    private FCk_Handle _ProxyEntity;
    private FCk_Handle_VatProxy _Proxy;
    private TArray<FName> _ClipNames;
    private int32 _FinishCount = 0;
    private FString _LastAction = "";

    FCk_Handle_Timer AutoTimer;
    bool AutoRunning = true;
    int32 AutoStep = 0;
    FCkGym_AutoConfig AutoConfig;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        InHandle.Set_DebugName(n"VatGym_ClipCycle");
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, n"TAG_VatGym_ClipCycle");

        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_VatGym_SetCollection, FCk_Delegate_Messaging_OnBroadcast(this, n"OnSetCollection"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_VatGym_PlayClip,      FCk_Delegate_Messaging_OnBroadcast(this, n"OnPlayClip"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_VatGym_SetRate,       FCk_Delegate_Messaging_OnBroadcast(this, n"OnSetRate"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_VatGym_Stop,          FCk_Delegate_Messaging_OnBroadcast(this, n"OnStop"));

        AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(2.5f));

        AutoConfig.Description = "Single VAT instance. Cycles every baked\nclip with a 0.4s crossfade, then rate 2.0,\nrate 0.5, freeze, resume.";
        AutoConfig.GlobalAutoCommand = "Ck_GymVat_Auto [0/1]";
        AutoConfig.PerStationAutoCommand = "panel [U] Auto-drive clip cycle";
        AutoConfig.ManualCommands.Add("Ck_GymVat_PlayClip [name] [rate]");
        AutoConfig.ManualCommands.Add("Ck_GymVat_PlayOnce [name] [rate]");
        AutoConfig.ManualCommands.Add("Ck_GymVat_SetRate [rate]");
        AutoConfig.ManualCommands.Add("Ck_GymVat_Stop");
        AutoConfig.ManualCommands.Add("Ck_GymVat_SetCollection [path]");

        RebuildStation();
        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    private void RebuildStation()
    {
        if (ck::IsValid(_ProxyEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_ProxyEntity);
            _ProxyEntity = FCk_Handle();
            _Proxy = FCk_Handle_VatProxy();
        }

        _ClipNames.Empty();
        _Collection = vat_gym::ResolveCollection(_CollectionPath);
        if (ck::Is_NOT_Valid(_Collection) || _Collection.Get_BakedData().Get_IsBaked() == false)
        { return; }

        for (auto Clip : _Collection.Get_BakedData().Get_BakedClips())
        { _ClipNames.Add(Clip.Get_Name()); }

        // Auto sequence: one step per clip, then the rate/freeze quartet.
        AutoConfig.Steps.Empty();
        auto NumClips = _ClipNames.Num();
        for (auto Index = 0; Index < NumClips; ++Index)
        {
            auto ClipName = _ClipNames[Index];
            AutoConfig.Steps.Add(FCkGym_AutoStep(f"Play '{ClipName}' (fade 0.4s)", Index, Index));
        }
        AutoConfig.Steps.Add(FCkGym_AutoStep("Rate 2.0", NumClips, NumClips));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Rate 0.5", NumClips + 1, NumClips + 1));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Freeze (Stop)", NumClips + 2, NumClips + 2));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Resume clip 0 @ 1.0", NumClips + 3, NumClips + 3));
        AutoConfig.TotalSteps = NumClips + 4;

        auto SelfEntity = ck::ToEntity(this);
        _ProxyEntity = SelfEntity.Request_CreateEntity();
        _ProxyEntity.Set_DebugName(n"VatClipCycle_Instance");
        auto ProxyTransform = utils_transform::Add(_ProxyEntity, InitialTransform, ECk_Replication::DoesNotReplicate);

        auto Params = FCk_Fragment_VatProxy_ParamsData(_Collection);
        if (_ClipNames.Num() > 0)
        { Params.Set_InitialClipName(_ClipNames[0]); }
        _Proxy = utils_vat_proxy::Add(ProxyTransform, Params);
        _Proxy.BindTo_OnClipFinished(FCk_Delegate_VatProxy_OnClipFinished(this, n"OnClipFinished"));
    }

    private void PlayClipAt(int32 InClipIndex, float32 InRate, float32 InFadeSeconds, bool InOnce)
    {
        if (ck::Is_NOT_Valid(_Proxy) || _ClipNames.Num() == 0)
        { return; }

        auto ClipName = _ClipNames[InClipIndex % _ClipNames.Num()];
        auto Request = FCk_Request_VatProxy_PlayClip(ClipName);
        Request.Set_PlayRate(InRate);
        Request.Set_LoopMode(InOnce ? ECk_VatProxy_LoopMode::Once : ECk_VatProxy_LoopMode::Loop);
        Request.Set_TransitionDuration(FCk_Time(InFadeSeconds));
        utils_vat_proxy::Request_PlayClip(_Proxy, Request);
        _LastAction = f"Play '{ClipName}' rate {InRate}";
    }

    UFUNCTION()
    private void OnClipFinished(FCk_Handle_VatProxy InHandle, FName InClipName)
    {
        _FinishCount++;
    }

    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto DisplayText = gym_auto::FormatHeader(AutoConfig, AutoRunning);

        if (ck::Is_NOT_Valid(_Collection) || _Collection.Get_BakedData().Get_IsBaked() == false)
        {
            auto FoundButUnbaked = ck::IsValid(_Collection);
            DisplayText = DisplayText + vat_gym::MissingCollectionText(_CollectionPath, FoundButUnbaked);
        }
        else
        {
            auto ActiveClip = utils_vat_proxy::Get_ActiveClipName(_Proxy);
            DisplayText = f"{DisplayText}Clips: {_ClipNames.Num()}  Active: {ActiveClip}\n";
            DisplayText = f"{DisplayText}OnClipFinished fires: {_FinishCount}\n";
            if (_LastAction != "") { DisplayText = f"{DisplayText}Last: {_LastAction}\n"; }
            DisplayText = DisplayText + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);
        }

        auto Owner = utils_entity_lifetime::Get_LifetimeOwner(ck::ToEntity(this));
        auto& Fragment = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        auto ModeStr = AutoRunning ? "[AUTO]" : "[MANUAL]";
        Fragment.Title = FText::FromString(f"CLIP CYCLE {ModeStr}");
        Fragment.Description = FText::FromString(DisplayText);
    }

    UFUNCTION()
    private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (ck::Is_NOT_Valid(_Proxy) || _ClipNames.Num() == 0 || AutoConfig.TotalSteps <= 0)
        { return; }

        auto NumClips = _ClipNames.Num();
        auto Step = AutoStep % AutoConfig.TotalSteps;

        if (Step < NumClips)
        {
            PlayClipAt(Step, 1.0f, 0.4f, false);
        }
        else if (Step == NumClips)
        {
            utils_vat_proxy::Request_SetPlayRate(_Proxy, 2.0f);
            _LastAction = "Rate 2.0";
        }
        else if (Step == NumClips + 1)
        {
            utils_vat_proxy::Request_SetPlayRate(_Proxy, 0.5f);
            _LastAction = "Rate 0.5";
        }
        else if (Step == NumClips + 2)
        {
            utils_vat_proxy::Request_Stop(_Proxy);
            _LastAction = "Freeze";
        }
        else
        {
            PlayClipAt(0, 1.0f, 0.4f, false);
        }

        AutoStep++;
    }

    UFUNCTION()
    private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning);
    }

    UFUNCTION()
    private void OnSetCollection(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::StopAuto(AutoTimer, AutoRunning);
        auto Typed = InPayload.Get(FCk_Message_VatGym_SetCollection);
        if (Typed.Path != "") { _CollectionPath = Typed.Path; }
        RebuildStation();
    }

    UFUNCTION()
    private void OnPlayClip(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::StopAuto(AutoTimer, AutoRunning);
        auto Typed = InPayload.Get(FCk_Message_VatGym_PlayClip);
        auto ClipIndex = -1;
        for (auto Index = 0; Index < _ClipNames.Num(); ++Index)
        {
            if (_ClipNames[Index] == Typed.ClipName)
            {
                ClipIndex = Index;
                break;
            }
        }
        if (ClipIndex == -1)
        {
            _LastAction = f"Unknown clip '{Typed.ClipName}'";
            return;
        }
        PlayClipAt(ClipIndex, Typed.Rate, Typed.FadeSeconds, Typed.Once);
    }

    UFUNCTION()
    private void OnSetRate(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::StopAuto(AutoTimer, AutoRunning);
        if (ck::Is_NOT_Valid(_Proxy)) { return; }
        auto Typed = InPayload.Get(FCk_Message_VatGym_SetRate);
        utils_vat_proxy::Request_SetPlayRate(_Proxy, Typed.Rate);
        _LastAction = f"Rate {Typed.Rate}";
    }

    UFUNCTION()
    private void OnStop(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::StopAuto(AutoTimer, AutoRunning);
        if (ck::Is_NOT_Valid(_Proxy)) { return; }
        utils_vat_proxy::Request_Stop(_Proxy);
        _LastAction = "Freeze";
    }
}

// ====================================================================================================================
// Station 2 - Turntable (the VAT-normals verify)
// ====================================================================================================================

class UCk_EntityScript_VatGym_Turntable : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    private UCk_VatCollection_Data _Collection;
    private FString _CollectionPath = vat_gym::DefaultCollectionPath;
    private FCk_Handle _ProxyEntity;
    private FCk_Handle_Transform _ProxyTransform;
    private FCk_Handle_VatProxy _Proxy;
    private float32 _Yaw = 0.0f;
    private float32 _DegreesPerSecond = 30.0f;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        InHandle.Set_DebugName(n"VatGym_Turntable");
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, n"TAG_VatGym_Turntable");

        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_VatGym_SetCollection, FCk_Delegate_Messaging_OnBroadcast(this, n"OnSetCollection"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_VatGym_TurnRate,      FCk_Delegate_Messaging_OnBroadcast(this, n"OnTurnRate"));

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));

        RebuildStation();
        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    private void RebuildStation()
    {
        if (ck::IsValid(_ProxyEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_ProxyEntity);
            _ProxyEntity = FCk_Handle();
            _ProxyTransform = FCk_Handle_Transform();
            _Proxy = FCk_Handle_VatProxy();
        }

        // WeightTexture storage on this station: both per-vertex carriers render side by side
        // in the gym (the other stations bake MeshChannels).
        _Collection = vat_gym::ResolveCollection(_CollectionPath, ECk_Vat_BoneWeightStorage::WeightTexture);
        if (ck::Is_NOT_Valid(_Collection) || _Collection.Get_BakedData().Get_IsBaked() == false)
        { return; }

        auto Clips = _Collection.Get_BakedData().Get_BakedClips();
        if (Clips.Num() == 0)
        { return; }

        auto SelfEntity = ck::ToEntity(this);
        _ProxyEntity = SelfEntity.Request_CreateEntity();
        _ProxyEntity.Set_DebugName(n"VatTurntable_Instance");
        _ProxyTransform = utils_transform::Add(_ProxyEntity, InitialTransform, ECk_Replication::DoesNotReplicate);

        auto Params = FCk_Fragment_VatProxy_ParamsData(_Collection);
        Params.Set_InitialClipName(Clips[0].Get_Name());
        _Proxy = utils_vat_proxy::Add(_ProxyTransform, Params);
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        DisplayStats();

        if (ck::Is_NOT_Valid(_ProxyTransform))
        { return; }

        _Yaw += _DegreesPerSecond * float32(InDeltaT.Get_Seconds());
        if (_Yaw >= 360.0f) { _Yaw -= 360.0f; }

        auto BaseRotation = InitialTransform.Rotator();
        auto NewRotation = FRotator(BaseRotation.Pitch, BaseRotation.Yaw + _Yaw, BaseRotation.Roll);
        utils_transform::Request_SetRotation(_ProxyTransform, NewRotation, ECk_LocalWorld::World);
    }

    private void DisplayStats()
    {
        auto DisplayText = FString();

        if (ck::Is_NOT_Valid(_Collection) || _Collection.Get_BakedData().Get_IsBaked() == false)
        {
            auto FoundButUnbaked = ck::IsValid(_Collection);
            DisplayText = vat_gym::MissingCollectionText(_CollectionPath, FoundButUnbaked);
        }
        else
        {
            DisplayText = "THE NORMALS CHECK (Vertex mode):\n";
            DisplayText = f"{DisplayText}Lighting must stay consistent while the\n";
            DisplayText = f"{DisplayText}instance turns - tangent-frame normals\n";
            DisplayText = f"{DisplayText}are invariant under instance rotation.\n";
            DisplayText = f"{DisplayText}Watch mirrored UV islands for inverted\n";
            DisplayText = f"{DisplayText}shading (bake handedness suspect).\n";
            DisplayText = f"{DisplayText}Bone mode lights with bind-pose normals\n";
            DisplayText = f"{DisplayText}(deferred - expect flat-ish shading).\n";
            DisplayText = f"{DisplayText}This station bakes WEIGHT-TEXTURE storage\n";
            DisplayText = f"{DisplayText}(others: mesh channels) - must look identical.\n\n";
            DisplayText = f"{DisplayText}Yaw: {int32(_Yaw)} deg @ {_DegreesPerSecond} deg/s\n\n";
            DisplayText = f"{DisplayText}===== Commands =====\n";
            DisplayText = f"{DisplayText}panel [G] Turntable rate\n";
            DisplayText = f"{DisplayText}Ck_GymVat_SetCollection [path]\n";
        }

        auto Owner = utils_entity_lifetime::Get_LifetimeOwner(ck::ToEntity(this));
        auto& Fragment = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        Fragment.Title = FText::FromString("TURNTABLE (NORMALS)");
        Fragment.Description = FText::FromString(DisplayText);
    }

    UFUNCTION()
    private void OnSetCollection(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto Typed = InPayload.Get(FCk_Message_VatGym_SetCollection);
        if (Typed.Path != "") { _CollectionPath = Typed.Path; }
        RebuildStation();
    }

    UFUNCTION()
    private void OnTurnRate(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto Typed = InPayload.Get(FCk_Message_VatGym_TurnRate);
        _DegreesPerSecond = Typed.DegreesPerSecond;
    }
}

// ====================================================================================================================
// Station 3 - CrowdField
// ====================================================================================================================

class UCk_EntityScript_VatGym_CrowdField : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    private UCk_VatCollection_Data _Collection;
    private FString _CollectionPath = vat_gym::DefaultCollectionPath;
    private TArray<FCk_Handle> _InstanceEntities;
    private TArray<FCk_Handle_VatProxy> _Proxies;
    private TArray<FName> _ClipNames;
    private int32 _Count = 100;
    private int32 _ActiveClipIndex = 0;

    FCk_Handle_Timer AutoTimer;
    bool AutoRunning = true;
    int32 AutoStep = 0;
    FCkGym_AutoConfig AutoConfig;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        InHandle.Set_DebugName(n"VatGym_CrowdField");
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, n"TAG_VatGym_CrowdField");

        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_VatGym_SetCollection, FCk_Delegate_Messaging_OnBroadcast(this, n"OnSetCollection"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_VatGym_FieldCount,    FCk_Delegate_Messaging_OnBroadcast(this, n"OnFieldCount"));

        AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(4.0f));

        AutoConfig.TotalSteps = 1;
        AutoConfig.Description = "Instanced crowd, RandomPerInstance phase\noffset - same clip, desynced playback.\nCustom data writes on clip change ONLY.";
        AutoConfig.GlobalAutoCommand = "Ck_GymVat_Auto [0/1]";
        AutoConfig.PerStationAutoCommand = "panel [F] Auto-drive crowd field";
        AutoConfig.Steps.Add(FCkGym_AutoStep("Switch whole field to next clip", 0, 0));
        AutoConfig.ManualCommands.Add("panel [N] Crowd field count");
        AutoConfig.ManualCommands.Add("Ck_GymVat_SetCollection [path]");

        RebuildStation();
        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    private void RebuildStation()
    {
        for (auto Entity : _InstanceEntities)
        {
            if (ck::IsValid(Entity))
            { utils_entity_lifetime::Request_DestroyEntity(Entity); }
        }
        _InstanceEntities.Empty();
        _Proxies.Empty();
        _ClipNames.Empty();
        _ActiveClipIndex = 0;

        _Collection = vat_gym::ResolveCollection(_CollectionPath);
        if (ck::Is_NOT_Valid(_Collection) || _Collection.Get_BakedData().Get_IsBaked() == false)
        { return; }

        for (auto Clip : _Collection.Get_BakedData().Get_BakedClips())
        { _ClipNames.Add(Clip.Get_Name()); }
        if (_ClipNames.Num() == 0)
        { return; }

        auto SelfEntity = ck::ToEntity(this);
        const float32 Spacing = 150.0f;
        auto Cols = 1;
        while (Cols * Cols < _Count) { Cols++; }
        auto ColCenter = float32(Cols) * 0.5f;

        for (auto Index = 0; Index < _Count; ++Index)
        {
            auto Row = Math::IntegerDivisionTrunc(Index, Cols);
            auto Col = Index % Cols;
            auto Offset = FVector(float32(Row) * -Spacing, (float32(Col) - ColCenter) * Spacing, 0.0f);
            auto SpawnXf = InitialTransform;
            SpawnXf.AddToTranslation(Offset);

            auto Entity = SelfEntity.Request_CreateEntity();
            auto InstanceTransform = utils_transform::Add(Entity, SpawnXf, ECk_Replication::DoesNotReplicate);

            auto Params = FCk_Fragment_VatProxy_ParamsData(_Collection);
            Params.Set_InitialClipName(_ClipNames[0]);
            Params.Set_PhaseOffset(ECk_VatProxy_PhaseOffset::RandomPerInstance);
            auto Proxy = utils_vat_proxy::Add(InstanceTransform, Params);

            _InstanceEntities.Add(Entity);
            _Proxies.Add(Proxy);
        }
    }

    private void PlayFieldClip(int32 InClipIndex)
    {
        if (_ClipNames.Num() == 0)
        { return; }

        _ActiveClipIndex = InClipIndex % _ClipNames.Num();
        auto ClipName = _ClipNames[_ActiveClipIndex];

        for (auto Proxy : _Proxies)
        {
            if (ck::Is_NOT_Valid(Proxy))
            { continue; }
            auto Request = FCk_Request_VatProxy_PlayClip(ClipName);
            Request.Set_TransitionDuration(FCk_Time(0.5f));
            utils_vat_proxy::Request_PlayClip(Proxy, Request);
        }
    }

    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto DisplayText = gym_auto::FormatHeader(AutoConfig, AutoRunning);

        if (ck::Is_NOT_Valid(_Collection) || _Collection.Get_BakedData().Get_IsBaked() == false)
        {
            auto FoundButUnbaked = ck::IsValid(_Collection);
            DisplayText = DisplayText + vat_gym::MissingCollectionText(_CollectionPath, FoundButUnbaked);
        }
        else
        {
            auto ActiveClip = _ClipNames.Num() > 0 ? f"{_ClipNames[_ActiveClipIndex]}" : "None";
            DisplayText = f"{DisplayText}Instances: {_Proxies.Num()}  Clip: {ActiveClip}\n";
            DisplayText = f"{DisplayText}Phases are per-instance random - the\n";
            DisplayText = f"{DisplayText}field must NOT tick in lock-step.\n";
            DisplayText = DisplayText + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);
        }

        auto Owner = utils_entity_lifetime::Get_LifetimeOwner(ck::ToEntity(this));
        auto& Fragment = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        auto ModeStr = AutoRunning ? "[AUTO]" : "[MANUAL]";
        Fragment.Title = FText::FromString(f"CROWD FIELD {ModeStr}");
        Fragment.Description = FText::FromString(DisplayText);
    }

    UFUNCTION()
    private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (_Proxies.Num() == 0)
        { return; }

        PlayFieldClip(_ActiveClipIndex + 1);
        AutoStep++;
    }

    UFUNCTION()
    private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning);
    }

    UFUNCTION()
    private void OnSetCollection(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::StopAuto(AutoTimer, AutoRunning);
        auto Typed = InPayload.Get(FCk_Message_VatGym_SetCollection);
        if (Typed.Path != "") { _CollectionPath = Typed.Path; }
        RebuildStation();
    }

    UFUNCTION()
    private void OnFieldCount(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::StopAuto(AutoTimer, AutoRunning);
        auto Typed = InPayload.Get(FCk_Message_VatGym_FieldCount);
        _Count = Math::Clamp(Typed.Count, 1, 2000);
        RebuildStation();
    }
}
