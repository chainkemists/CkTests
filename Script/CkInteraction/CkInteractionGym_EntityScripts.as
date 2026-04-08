// Language=angelscript

namespace Ck
{
    asset Asset_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"InteractionChannel.InteractionGym.Default");
        GameplayTags.Add(n"InteractionChannel.InteractionGym.Secondary");
        GameplayTags.Add(n"InteractionIntent.InteractionGym.Use");
        GameplayTags.Add(n"ResolverDataBundle.InteractionGym.Damage");
        GameplayTags.Add(n"ResolverPhase.InteractionGym.Calculate");
        GameplayTags.Add(n"ResolverPhase.InteractionGym.Apply");
    }

#if EDITOR
    asset InteractionGym_AssetRegistryConfig of UCkAssetRegistryConfig
    {
        AssetDiscoveryRoot = "/CkFoundation/CkInteraction";
        OutputFileName = "interaction_gym_assets.as";
        Namespace = "interaction_gym_assets";
    }
#endif
}

//============================================================================
// INTERACTION GYM - ENTITY SCRIPTS
//============================================================================

//============================================================================
// SPAWN PARAMETERS
//============================================================================

USTRUCT()
struct FInteractionGymSpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FInteractionGymSpawnParams(FTransform InTransform)
    {
        InitialTransform = InTransform;
    }
}

//============================================================================
// MESSAGE TYPES
//============================================================================

USTRUCT()
struct FCk_Message_InteractionGym_Command
{
    FCk_Message_InteractionGym_Command() {}
}

USTRUCT()
struct FCk_Message_InteractionGym_EndManualSuccess
{
    FCk_Message_InteractionGym_EndManualSuccess() {}
}

USTRUCT()
struct FCk_Message_InteractionGym_EndManualFail
{
    FCk_Message_InteractionGym_EndManualFail() {}
}

USTRUCT()
struct FCk_Message_InteractionGym_CancelManual
{
    FCk_Message_InteractionGym_CancelManual() {}
}

USTRUCT()
struct FCk_Message_InteractionGym_ToggleEnabled
{
    FCk_Message_InteractionGym_ToggleEnabled() {}
}

USTRUCT()
struct FCk_Message_InteractionGym_ToggleCustomValidation
{
    FCk_Message_InteractionGym_ToggleCustomValidation() {}
}

USTRUCT()
struct FCk_Message_InteractionGym_StartIntent
{
    FCk_Message_InteractionGym_StartIntent() {}
}

USTRUCT()
struct FCk_Message_InteractionGym_StopIntent
{
    FCk_Message_InteractionGym_StopIntent() {}
}

USTRUCT()
struct FCk_Message_InteractionGym_AddTargets
{
    FCk_Message_InteractionGym_AddTargets() {}
}

USTRUCT()
struct FCk_Message_InteractionGym_RemoveTargets
{
    FCk_Message_InteractionGym_RemoveTargets() {}
}

//============================================================================
// STATION 1: INSTANT INTERACTION
//============================================================================

class UCk_EntityScript_InteractionGym_Instant : UCk_EntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_InteractSource SourceHandle;
    FCk_Handle_InteractTarget TargetHandle;

    int32 InteractionCount = 0;
    FString LastResult = "N/A";

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_InteractionGym_Instant");

        auto Channel = utils_gameplay_tag::ResolveGameplayTag(n"InteractionChannel.InteractionGym.Default");

        // Add InteractSource (no constructor for ParamsData, set field directly)
        auto SourceParams = FCk_Fragment_InteractSource_ParamsData();
        SourceParams._InteractionChannel = Channel;
        SourceHandle = utils_interact_source::Add(InHandle, SourceParams);

        // Add InteractTarget with Instant completion
        auto TargetParams = FCk_Fragment_InteractTarget_ParamsData(Channel);
        TargetParams.Set_CompletionPolicy(ECk_Interaction_CompletionPolicy::Instant);
        TargetHandle = utils_interact_target::Add(InHandle, TargetParams);

        // Bind signals on source
        utils_interact_source::BindTo_OnNewInteraction(
            SourceHandle,
            FCk_Delegate_InteractSource_OnNewInteraction(this, n"OnSourceNewInteraction")
        );
        utils_interact_source::BindTo_OnInteractionFinished(
            SourceHandle,
            FCk_Delegate_InteractSource_OnInteractionFinished(this, n"OnSourceInteractionFinished")
        );

        // Bind signals on target
        utils_interact_target::BindTo_OnNewInteraction(
            TargetHandle,
            FCk_Delegate_InteractTarget_OnNewInteraction(this, n"OnTargetNewInteraction")
        );
        utils_interact_target::BindTo_OnInteractionFinished(
            TargetHandle,
            FCk_Delegate_InteractTarget_OnInteractionFinished(this, n"OnTargetInteractionFinished")
        );

        // Listen for command messages
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_Command, FCk_Delegate_Messaging_OnBroadcast(this, n"OnCommand"));

        // Display timer
        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION()
    private void OnCommand(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto SelfEntity = ck::ToEntity(this);
        auto Request = FCk_Try_InteractTarget_StartInteraction();
        Request.Set_InteractSource(SelfEntity);
        Request.Set_InteractInstigator(SelfEntity);
        utils_interact_target::Request_StartInteraction(TargetHandle, Request);
        ck::Trace("✅ Instant: Interaction triggered");
    }

    UFUNCTION()
    private void OnSourceNewInteraction(FCk_Handle_InteractSource InSource, FCk_Handle_Interaction InInteraction)
    {
        ck::Trace("✅ Instant: Source received new interaction");
    }

    UFUNCTION()
    private void OnSourceInteractionFinished(FCk_Handle_InteractSource InSource, FCk_Handle_Interaction InInteraction, ECk_SucceededFailed SucceededFailed)
    {
        ck::Trace(f"✅ Instant: Source interaction finished - {SucceededFailed}");
    }

    UFUNCTION()
    private void OnTargetNewInteraction(FCk_Handle_InteractTarget InTarget, FCk_Handle_Interaction InInteraction)
    {
        InteractionCount++;
        ck::Trace(f"✅ Instant: Target received new interaction #{InteractionCount}");
    }

    UFUNCTION()
    private void OnTargetInteractionFinished(FCk_Handle_InteractTarget InTarget, FCk_Handle_Interaction InInteraction, ECk_SucceededFailed SucceededFailed)
    {
        if (SucceededFailed == ECk_SucceededFailed::Succeeded)
        {
            LastResult = "Succeeded";
        }
        else
        {
            LastResult = "Failed";
        }
        ck::Trace(f"✅ Instant: Target interaction finished - {LastResult}");
    }

    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto SelfEntity = ck::ToEntity(this);
        auto TitleText = "INSTANT INTERACTION";

        auto DisplayText = "";
        DisplayText = f"{DisplayText}Source and target on same entity, same channel.\n";
        DisplayText = f"{DisplayText}Completion policy: Instant\n\n";
        DisplayText = f"{DisplayText}===== Stats =====\n";
        DisplayText = f"{DisplayText}Interactions Triggered: {InteractionCount}\n";
        DisplayText = f"{DisplayText}Last Result: {LastResult}\n";
        DisplayText = f"{DisplayText}Source Valid: {ck::IsValid(SourceHandle)}\n";
        DisplayText = f"{DisplayText}Target Valid: {ck::IsValid(TargetHandle)}\n";

        auto Instructions = "";
        Instructions = f"{Instructions}Ck_GymInteraction_TriggerInstant";

        CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
    }
}

//============================================================================
// STATION 2: TIMED INTERACTION - SOURCE ENTITY
//============================================================================

class UCk_EntityScript_InteractionGym_TimedSource : UCk_EntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_InteractSource SourceHandle;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_InteractionGym_TimedSource");

        auto SourceParams = FCk_Fragment_InteractSource_ParamsData();
        SourceParams._InteractionChannel = utils_gameplay_tag::ResolveGameplayTag(n"InteractionChannel.InteractionGym.Default");
        SourceHandle = utils_interact_source::Add(InHandle, SourceParams);

        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}

//============================================================================
// STATION 2: TIMED INTERACTION - TARGET ENTITY
//============================================================================

class UCk_EntityScript_InteractionGym_TimedTarget : UCk_EntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_InteractTarget TargetHandle;
    FCk_Handle_Interaction ActiveInteraction;

    int32 CompletionCount = 0;
    FString CurrentState = "Idle";
    FString LastResult = "N/A";

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_InteractionGym_TimedTarget");

        auto TargetParams = FCk_Fragment_InteractTarget_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"InteractionChannel.InteractionGym.Default")
        );
        TargetParams.Set_CompletionPolicy(ECk_Interaction_CompletionPolicy::Timed);
        TargetParams.Set_InteractionDuration(FCk_Time(3.0f));
        TargetHandle = utils_interact_target::Add(InHandle, TargetParams);

        utils_interact_target::BindTo_OnNewInteraction(
            TargetHandle,
            FCk_Delegate_InteractTarget_OnNewInteraction(this, n"OnNewInteraction")
        );
        utils_interact_target::BindTo_OnInteractionFinished(
            TargetHandle,
            FCk_Delegate_InteractTarget_OnInteractionFinished(this, n"OnInteractionFinished")
        );

        // Listen for command messages
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_Command, FCk_Delegate_Messaging_OnBroadcast(this, n"OnCommand"));

        // Display timer
        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION()
    private void OnCommand(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        // Find the source entity by tag
        auto SelfEntity = ck::ToEntity(this);
        auto SourceEntities = utils_entity_tag::ForEach_Entity(SelfEntity, n"TAG_InteractionGym_TimedSource");
        if (SourceEntities.Num() == 0)
        {
            ck::Error("❌ Timed: Source entity not found");
            return;
        }

        auto Request = FCk_Try_InteractTarget_StartInteraction();
        Request.Set_InteractSource(SourceEntities[0]);
        Request.Set_InteractInstigator(SourceEntities[0]);
        utils_interact_target::Request_StartInteraction(TargetHandle, Request);
        ck::Trace("✅ Timed: Start interaction requested");
    }

    UFUNCTION()
    private void OnNewInteraction(FCk_Handle_InteractTarget InTarget, FCk_Handle_Interaction InInteraction)
    {
        ActiveInteraction = InInteraction;
        CurrentState = "In Progress";
        ck::Trace("✅ Timed: Interaction started (3s duration)");
    }

    UFUNCTION()
    private void OnInteractionFinished(FCk_Handle_InteractTarget InTarget, FCk_Handle_Interaction InInteraction, ECk_SucceededFailed SucceededFailed)
    {
        ActiveInteraction = utils_interaction::Get_InvalidHandle();
        CurrentState = "Idle";
        CompletionCount++;
        if (SucceededFailed == ECk_SucceededFailed::Succeeded)
        {
            LastResult = "Succeeded";
        }
        else
        {
            LastResult = "Failed";
        }
        ck::Trace(f"✅ Timed: Interaction finished - {LastResult}");
    }

    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto SelfEntity = ck::ToEntity(this);
        auto TitleText = "TIMED INTERACTION";

        auto ElapsedStr = "0.00";
        auto DurationStr = "3.00";
        if (ck::IsValid(ActiveInteraction))
        {
            auto Elapsed = utils_interaction::Get_InteractionTimeElapsed(ActiveInteraction);
            auto Duration = utils_interaction::Get_InteractionDuration(ActiveInteraction);
            ElapsedStr = f"{Elapsed.Get_Seconds()}";
            DurationStr = f"{Duration.Get_Seconds()}";
        }

        auto DisplayText = "";
        DisplayText = f"{DisplayText}Source and target on separate entities.\n";
        DisplayText = f"{DisplayText}Completion policy: Timed (3 seconds)\n\n";
        DisplayText = f"{DisplayText}===== Stats =====\n";
        DisplayText = f"{DisplayText}State: {CurrentState}\n";
        DisplayText = f"{DisplayText}Elapsed: {ElapsedStr}s / {DurationStr}s\n";
        DisplayText = f"{DisplayText}Completions: {CompletionCount}\n";
        DisplayText = f"{DisplayText}Last Result: {LastResult}\n";

        auto Instructions = "";
        Instructions = f"{Instructions}Ck_GymInteraction_StartTimed";

        CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
    }
}

//============================================================================
// STATION 3: MANUAL INTERACTION
//============================================================================

class UCk_EntityScript_InteractionGym_Manual : UCk_EntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_InteractSource SourceHandle;
    FCk_Handle_InteractTarget TargetHandle;
    FCk_Handle_Interaction ActiveInteraction;

    int32 SuccessCount = 0;
    int32 FailCount = 0;
    int32 CancelCount = 0;
    FString CurrentState = "Idle";
    FString LastResult = "N/A";

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_InteractionGym_Manual");

        auto Channel = utils_gameplay_tag::ResolveGameplayTag(n"InteractionChannel.InteractionGym.Default");

        // Source
        auto SourceParams = FCk_Fragment_InteractSource_ParamsData();
        SourceParams._InteractionChannel = Channel;
        SourceHandle = utils_interact_source::Add(InHandle, SourceParams);

        // Target with ManuallyCompleted
        auto TargetParams = FCk_Fragment_InteractTarget_ParamsData(Channel);
        TargetParams.Set_CompletionPolicy(ECk_Interaction_CompletionPolicy::ManuallyCompleted);
        TargetHandle = utils_interact_target::Add(InHandle, TargetParams);

        utils_interact_target::BindTo_OnNewInteraction(
            TargetHandle,
            FCk_Delegate_InteractTarget_OnNewInteraction(this, n"OnNewInteraction")
        );
        utils_interact_target::BindTo_OnInteractionFinished(
            TargetHandle,
            FCk_Delegate_InteractTarget_OnInteractionFinished(this, n"OnInteractionFinished")
        );

        // Listen for command messages
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_Command, FCk_Delegate_Messaging_OnBroadcast(this, n"OnStartManual"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_EndManualSuccess, FCk_Delegate_Messaging_OnBroadcast(this, n"OnEndManualSuccess"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_EndManualFail, FCk_Delegate_Messaging_OnBroadcast(this, n"OnEndManualFail"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_CancelManual, FCk_Delegate_Messaging_OnBroadcast(this, n"OnCancelManual"));

        // Display timer
        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION()
    private void OnNewInteraction(FCk_Handle_InteractTarget InTarget, FCk_Handle_Interaction InInteraction)
    {
        ActiveInteraction = InInteraction;
        CurrentState = "Active";
        ck::Trace("✅ Manual: Interaction started");
    }

    UFUNCTION()
    private void OnInteractionFinished(FCk_Handle_InteractTarget InTarget, FCk_Handle_Interaction InInteraction, ECk_SucceededFailed SucceededFailed)
    {
        ActiveInteraction = utils_interaction::Get_InvalidHandle();
        CurrentState = "Idle";
        if (SucceededFailed == ECk_SucceededFailed::Succeeded)
        {
            SuccessCount++;
            LastResult = "Succeeded";
        }
        else
        {
            FailCount++;
            LastResult = "Failed";
        }
        ck::Trace(f"✅ Manual: Interaction finished - {LastResult}");
    }

    UFUNCTION()
    private void OnStartManual(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto SelfEntity = ck::ToEntity(this);
        auto Request = FCk_Try_InteractTarget_StartInteraction();
        Request.Set_InteractSource(SelfEntity);
        Request.Set_InteractInstigator(SelfEntity);
        utils_interact_target::Request_StartInteraction(TargetHandle, Request);
    }

    UFUNCTION()
    private void OnEndManualSuccess(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        if (!ck::IsValid(ActiveInteraction))
        {
            ck::Warning("Manual: No active interaction to end");
            return;
        }
        utils_interaction::Request_EndInteraction(ActiveInteraction, FCk_Request_Interaction_EndInteraction(ECk_SucceededFailed::Succeeded));
    }

    UFUNCTION()
    private void OnEndManualFail(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        if (!ck::IsValid(ActiveInteraction))
        {
            ck::Warning("Manual: No active interaction to end");
            return;
        }
        utils_interaction::Request_EndInteraction(ActiveInteraction, FCk_Request_Interaction_EndInteraction(ECk_SucceededFailed::Failed));
    }

    UFUNCTION()
    private void OnCancelManual(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        if (!ck::IsValid(ActiveInteraction))
        {
            ck::Warning("Manual: No active interaction to cancel");
            return;
        }
        auto SelfEntity = ck::ToEntity(this);
        auto Request = FCk_Request_InteractTarget_CancelInteraction();
        Request.Set_InteractSource(SelfEntity);
        utils_interact_target::Request_CancelInteraction(TargetHandle, Request);
        CancelCount++;
    }

    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto SelfEntity = ck::ToEntity(this);
        auto TitleText = "MANUAL INTERACTION";

        auto ActiveCount = utils_interact_target::Get_CurrentInteractions(TargetHandle).Num();

        auto DisplayText = "";
        DisplayText = f"{DisplayText}Source + target with ManuallyCompleted policy.\n";
        DisplayText = f"{DisplayText}Must explicitly end or cancel the interaction.\n\n";
        DisplayText = f"{DisplayText}===== Stats =====\n";
        DisplayText = f"{DisplayText}State: {CurrentState}\n";
        DisplayText = f"{DisplayText}Active Interactions: {ActiveCount}\n";
        DisplayText = f"{DisplayText}Successes: {SuccessCount}\n";
        DisplayText = f"{DisplayText}Failures: {FailCount}\n";
        DisplayText = f"{DisplayText}Cancels: {CancelCount}\n";
        DisplayText = f"{DisplayText}Last Result: {LastResult}\n";

        auto Instructions = "";
        Instructions = f"{Instructions}Ck_GymInteraction_StartManual\n";
        Instructions = f"{Instructions}Ck_GymInteraction_EndManualSuccess\n";
        Instructions = f"{Instructions}Ck_GymInteraction_EndManualFail\n";
        Instructions = f"{Instructions}Ck_GymInteraction_CancelManual";

        CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
    }
}

//============================================================================
// STATION 4: ENABLE/DISABLE & VALIDATION
//============================================================================

class UCk_EntityScript_InteractionGym_Validation : UCk_EntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_InteractSource SourceHandle;
    FCk_Handle_InteractTarget TargetHandle;

    bool IsTargetEnabled = true;
    bool CustomValidationAllowed = true;
    FString LastCanInteractResult = "N/A";
    int32 AttemptCount = 0;
    int32 SuccessCount = 0;
    int32 RejectedCount = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_InteractionGym_Validation");

        auto Channel = utils_gameplay_tag::ResolveGameplayTag(n"InteractionChannel.InteractionGym.Default");

        // Source
        auto SourceParams = FCk_Fragment_InteractSource_ParamsData();
        SourceParams._InteractionChannel = Channel;
        SourceHandle = utils_interact_source::Add(InHandle, SourceParams);

        // Target with custom validation delegate
        auto TargetParams = FCk_Fragment_InteractTarget_ParamsData(Channel);
        TargetParams.Set_CompletionPolicy(ECk_Interaction_CompletionPolicy::Instant);
        TargetParams.Set_CustomCanInteractWithDynamic(
            FCk_Delegate_InteractTarget_CanInteractWith(this, n"OnCanInteractWith")
        );
        TargetHandle = utils_interact_target::Add(InHandle, TargetParams);

        utils_interact_target::BindTo_OnNewInteraction(
            TargetHandle,
            FCk_Delegate_InteractTarget_OnNewInteraction(this, n"OnNewInteraction")
        );

        // Listen for command messages
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_Command, FCk_Delegate_Messaging_OnBroadcast(this, n"OnAttempt"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_ToggleEnabled, FCk_Delegate_Messaging_OnBroadcast(this, n"OnToggleEnabled"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_ToggleCustomValidation, FCk_Delegate_Messaging_OnBroadcast(this, n"OnToggleCustomValidation"));

        // Display timer
        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION()
    private void OnCanInteractWith(FCk_Handle_InteractTarget InTarget, FCk_Handle InInteractSource, FCk_Handle InInteractInstigator, bool& OutResult)
    {
        OutResult = CustomValidationAllowed;
        if (!CustomValidationAllowed)
        {
            ck::Trace("✅ Validation: Custom validation rejected interaction");
        }
    }

    UFUNCTION()
    private void OnNewInteraction(FCk_Handle_InteractTarget InTarget, FCk_Handle_Interaction InInteraction)
    {
        SuccessCount++;
        ck::Trace(f"✅ Validation: Interaction succeeded (#{SuccessCount})");
    }

    UFUNCTION()
    private void OnAttempt(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        AttemptCount++;
        auto SelfEntity = ck::ToEntity(this);

        auto CanInteractResult = utils_interact_target::Get_CanInteractWith(TargetHandle, SelfEntity);

        if (CanInteractResult == ECk_CanInteractWithResult::CanInteractWith)
        {
            LastCanInteractResult = "CanInteractWith";
        }
        else if (CanInteractResult == ECk_CanInteractWithResult::TargetDisabled)
        {
            LastCanInteractResult = "TargetDisabled";
            RejectedCount++;
        }
        else if (CanInteractResult == ECk_CanInteractWithResult::CustomValidationFailed)
        {
            LastCanInteractResult = "CustomValidationFailed";
            RejectedCount++;
        }
        else
        {
            LastCanInteractResult = "Other Rejection";
            RejectedCount++;
        }

        auto Request = FCk_Try_InteractTarget_StartInteraction();
        Request.Set_InteractSource(SelfEntity);
        Request.Set_InteractInstigator(SelfEntity);
        utils_interact_target::Request_StartInteraction(TargetHandle, Request);

        ck::Trace(f"✅ Validation: Attempt #{AttemptCount} - CanInteract: {LastCanInteractResult}");
    }

    UFUNCTION()
    private void OnToggleEnabled(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        IsTargetEnabled = !IsTargetEnabled;
        if (IsTargetEnabled)
        {
            utils_interact_target::Set_Enabled(TargetHandle, ECk_EnableDisable::Enable);
        }
        else
        {
            utils_interact_target::Set_Enabled(TargetHandle, ECk_EnableDisable::Disable);
        }
        ck::Trace(f"✅ Validation: Target enabled = {IsTargetEnabled}");
    }

    UFUNCTION()
    private void OnToggleCustomValidation(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        CustomValidationAllowed = !CustomValidationAllowed;
        ck::Trace(f"✅ Validation: Custom validation allowed = {CustomValidationAllowed}");
    }

    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto SelfEntity = ck::ToEntity(this);
        auto TitleText = "ENABLE/DISABLE & VALIDATION";

        auto EnabledStr = IsTargetEnabled ? "Enabled" : "Disabled";
        auto ValidationStr = CustomValidationAllowed ? "Allowed" : "Blocked";

        auto DisplayText = "";
        DisplayText = f"{DisplayText}Target with custom CanInteractWith validation.\n";
        DisplayText = f"{DisplayText}Toggle enabled state and custom validation.\n\n";
        DisplayText = f"{DisplayText}===== Stats =====\n";
        DisplayText = f"{DisplayText}Target State: {EnabledStr}\n";
        DisplayText = f"{DisplayText}Custom Validation: {ValidationStr}\n";
        DisplayText = f"{DisplayText}Last CanInteract: {LastCanInteractResult}\n";
        DisplayText = f"{DisplayText}Attempts: {AttemptCount}\n";
        DisplayText = f"{DisplayText}Successes: {SuccessCount}\n";
        DisplayText = f"{DisplayText}Rejected: {RejectedCount}\n";

        auto Instructions = "";
        Instructions = f"{Instructions}Ck_GymInteraction_AttemptValidation\n";
        Instructions = f"{Instructions}Ck_GymInteraction_ToggleEnabled\n";
        Instructions = f"{Instructions}Ck_GymInteraction_ToggleCustomValidation";

        CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
    }
}

//============================================================================
// STATION 5: INTERACTION RESOLVER - SOURCE ENTITY (with resolver)
//============================================================================

class UCk_EntityScript_InteractionGym_ResolverSource : UCk_EntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_InteractSource SourceHandle;
    FCk_Handle_InteractionResolver ResolverHandle;

    int32 BestTargetCount = 0;
    bool IntentActive = false;
    int32 TargetChangedCount = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_InteractionGym_ResolverSource");

        // Add InteractSource
        auto SourceParams = FCk_Fragment_InteractSource_ParamsData();
        SourceParams._InteractionChannel = utils_gameplay_tag::ResolveGameplayTag(n"InteractionChannel.InteractionGym.Default");
        SourceHandle = utils_interact_source::Add(InHandle, SourceParams);

        // Add Interaction Resolver with intent-channel mapping
        auto Channels = TArray<FGameplayTag>();
        Channels.Add(utils_gameplay_tag::ResolveGameplayTag(n"InteractionChannel.InteractionGym.Default"));
        Channels.Add(utils_gameplay_tag::ResolveGameplayTag(n"InteractionChannel.InteractionGym.Secondary"));

        auto Mapping = FCk_InteractionResolver_IntentChannelMapping(
            utils_gameplay_tag::ResolveGameplayTag(n"InteractionIntent.InteractionGym.Use"),
            Channels
        );
        Mapping.Set_DistanceSorting(ECk_InteractionResolver_DistanceSorting::Enabled);
        Mapping.Set_MaxConcurrentInteractions(1);

        auto Mappings = TArray<FCk_InteractionResolver_IntentChannelMapping>();
        Mappings.Add(Mapping);

        auto ResolverParams = FCk_InteractionResolver_ParamsData(Mappings);
        ResolverHandle = utils_interaction_resolver::Add(InHandle, ResolverParams);

        // Bind to best targets changed (note: &in syntax for Angelscript array refs)
        utils_interaction_resolver::BindTo_OnBestTargetsChanged(
            ResolverHandle,
            FCk_Delegate_InteractionResolver_OnBestTargetsChanged(this, n"OnBestTargetsChanged")
        );

        // Listen for command messages
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_StartIntent, FCk_Delegate_Messaging_OnBroadcast(this, n"OnStartIntent"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_StopIntent, FCk_Delegate_Messaging_OnBroadcast(this, n"OnStopIntent"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_AddTargets, FCk_Delegate_Messaging_OnBroadcast(this, n"OnAddTargets"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_RemoveTargets, FCk_Delegate_Messaging_OnBroadcast(this, n"OnRemoveTargets"));

        // Display timer
        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION()
    private void OnBestTargetsChanged(FCk_Handle_InteractionResolver InResolver, FGameplayTag InIntent, const TArray<FCk_Handle_InteractTarget>&in InPreviousTargets, const TArray<FCk_Handle_InteractTarget>&in InNewTargets, const TArray<FCk_Handle_InteractTarget>&in InRemovedTargets)
    {
        BestTargetCount = InNewTargets.Num();
        TargetChangedCount++;
        ck::Trace(f"✅ Resolver: Best targets changed - {BestTargetCount} new, {InRemovedTargets.Num()} removed");
    }

    UFUNCTION()
    private void OnStartIntent(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto Request = FCk_Request_InteractionResolver_StartIntent(
            utils_gameplay_tag::ResolveGameplayTag(n"InteractionIntent.InteractionGym.Use")
        );
        utils_interaction_resolver::Request_StartIntent(ResolverHandle, Request);
        IntentActive = true;
        ck::Trace("✅ Resolver: Intent started");
    }

    UFUNCTION()
    private void OnStopIntent(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto Request = FCk_Request_InteractionResolver_StopIntent(
            utils_gameplay_tag::ResolveGameplayTag(n"InteractionIntent.InteractionGym.Use")
        );
        utils_interaction_resolver::Request_StopIntent(ResolverHandle, Request);
        IntentActive = false;
        ck::Trace("✅ Resolver: Intent stopped");
    }

    UFUNCTION()
    private void OnAddTargets(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto SelfEntity = ck::ToEntity(this);
        auto TargetEntities = utils_entity_tag::ForEach_Entity(SelfEntity, n"TAG_InteractionGym_ResolverTarget");
        for (auto TargetEntity : TargetEntities)
        {
            auto TargetHandle = utils_interact_target::TryGet(
                TargetEntity,
                utils_gameplay_tag::ResolveGameplayTag(n"InteractionChannel.InteractionGym.Default")
            );
            if (ck::IsValid(TargetHandle))
            {
                auto Request = FCk_Request_InteractionResolver_AddInteractTarget(TargetHandle);
                utils_interaction_resolver::Request_AddInteractTarget(ResolverHandle, Request);
            }
        }
        ck::Trace(f"✅ Resolver: Added {TargetEntities.Num()} targets");
    }

    UFUNCTION()
    private void OnRemoveTargets(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto SelfEntity = ck::ToEntity(this);
        auto TargetEntities = utils_entity_tag::ForEach_Entity(SelfEntity, n"TAG_InteractionGym_ResolverTarget");
        for (auto TargetEntity : TargetEntities)
        {
            auto TargetHandle = utils_interact_target::TryGet(
                TargetEntity,
                utils_gameplay_tag::ResolveGameplayTag(n"InteractionChannel.InteractionGym.Default")
            );
            if (ck::IsValid(TargetHandle))
            {
                auto Request = FCk_Request_InteractionResolver_RemoveInteractTarget(TargetHandle);
                utils_interaction_resolver::Request_RemoveInteractTarget(ResolverHandle, Request);
            }
        }
        ck::Trace(f"✅ Resolver: Removed {TargetEntities.Num()} targets");
    }

    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto SelfEntity = ck::ToEntity(this);
        auto TitleText = "INTERACTION RESOLVER";

        auto IntentStr = IntentActive ? "Active" : "Inactive";

        auto CurrentBestTargets = utils_interaction_resolver::Get_BestInteractTargets(
            ResolverHandle,
            utils_gameplay_tag::ResolveGameplayTag(n"InteractionIntent.InteractionGym.Use")
        );

        auto DisplayText = "";
        DisplayText = f"{DisplayText}Source with resolver, 3 targets at varying distances.\n";
        DisplayText = f"{DisplayText}Distance sorting enabled, max 1 concurrent interaction.\n\n";
        DisplayText = f"{DisplayText}===== Stats =====\n";
        DisplayText = f"{DisplayText}Intent: {IntentStr}\n";
        DisplayText = f"{DisplayText}Current Best Targets: {CurrentBestTargets.Num()}\n";
        DisplayText = f"{DisplayText}Target Changed Events: {TargetChangedCount}\n";

        auto Instructions = "";
        Instructions = f"{Instructions}Ck_GymInteraction_StartIntent\n";
        Instructions = f"{Instructions}Ck_GymInteraction_StopIntent\n";
        Instructions = f"{Instructions}Ck_GymInteraction_AddTarget\n";
        Instructions = f"{Instructions}Ck_GymInteraction_RemoveTarget";

        CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
    }
}

//============================================================================
// STATION 5: INTERACTION RESOLVER - TARGET ENTITY
//============================================================================

class UCk_EntityScript_InteractionGym_ResolverTarget : UCk_EntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_InteractTarget TargetHandle;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_InteractionGym_ResolverTarget");

        auto TargetParams = FCk_Fragment_InteractTarget_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"InteractionChannel.InteractionGym.Default")
        );
        TargetParams.Set_CompletionPolicy(ECk_Interaction_CompletionPolicy::Instant);
        TargetHandle = utils_interact_target::Add(InHandle, TargetParams);

        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}

//============================================================================
// STATION 6: RESOLVER DATA BUNDLE
//============================================================================

class UCk_EntityScript_InteractionGym_DataBundle : UCk_EntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_ResolverSource ResolverSourceHandle;
    FCk_Handle_ResolverTarget ResolverTargetHandle;

    int32 ResolutionCount = 0;
    FString CurrentPhase = "N/A";
    float32 LastFinalValue = 0.0f;
    int32 PhasesCompleted = 0;
    bool AllPhasesComplete = false;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_InteractionGym_DataBundle");

        // Create ResolverSource with two phases
        auto Phases = TArray<FCk_Fragment_ResolverDataBundle_PhaseInfo>();
        Phases.Add(FCk_Fragment_ResolverDataBundle_PhaseInfo(
            utils_gameplay_tag::ResolveGameplayTag(n"ResolverPhase.InteractionGym.Calculate"),
            ECk_ResolverDataBundle_AllowedOperationsInPhase::ModifierAndMetadata
        ));
        Phases.Add(FCk_Fragment_ResolverDataBundle_PhaseInfo(
            utils_gameplay_tag::ResolveGameplayTag(n"ResolverPhase.InteractionGym.Apply"),
            ECk_ResolverDataBundle_AllowedOperationsInPhase::ModifierAndMetadata
        ));

        auto SourceParams = FCk_Fragment_ResolverSource_ParamsData(Phases);
        ResolverSourceHandle = utils_resolver_source::Add(InHandle, SourceParams);

        // Create ResolverTarget
        auto TargetParams = FCk_Fragment_ResolverTarget_ParamsData();
        ResolverTargetHandle = utils_resolver_target::Add(InHandle, TargetParams);

        // Listen for command messages
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_Command, FCk_Delegate_Messaging_OnBroadcast(this, n"OnInitiateResolution"));

        // Display timer
        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION()
    private void OnInitiateResolution(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto SelfEntity = ck::ToEntity(this);
        AllPhasesComplete = false;
        PhasesCompleted = 0;
        CurrentPhase = "Pending";

        auto BundleName = utils_gameplay_tag::ResolveGameplayTag(n"ResolverDataBundle.InteractionGym.Damage");

        // Build initial modifier operation: BaseValue + 100
        auto InitialModifier = FCk_ResolverDataBundle_ModifierOperation(100.0f);
        InitialModifier.Set_ResolverComponent(ECk_ResolverDataBundle_ModifierComponent::BaseValue);
        InitialModifier.Set_ModifierOperation(ECk_ArithmeticOperations_Basic::Add);

        auto InitialModifierConditional = FCk_ResolverDataBundle_ModifierOperation_Conditional(
            FGameplayTagRequirements(),
            InitialModifier
        );

        auto Request = utils_resolver_source::Make_InitiateNewResolution(
            BundleName,
            ResolverTargetHandle,
            SelfEntity,
            FCk_ResolverDataBundle_MetadataOperation_Conditional(),
            InitialModifierConditional
        );

        utils_resolver_source::Request_InitiateNewResolution(
            ResolverSourceHandle,
            Request,
            FCk_Delegate_ResolverSource_OnNewResolverDataBundle(this, n"OnNewDataBundle")
        );

        ResolutionCount++;
        ck::Trace(f"✅ DataBundle: Resolution #{ResolutionCount} initiated");
    }

    UFUNCTION()
    private void OnNewDataBundle(FCk_Handle_ResolverSource InSource, FCk_Handle InCauser, FCk_Handle_ResolverDataBundle InDataBundle)
    {
        ck::Trace("✅ DataBundle: New data bundle created");

        utils_resolver_data_bundle::BindTo_OnPhaseStart(
            InDataBundle,
            FCk_Delegate_ResolverDataBundle_OnPhaseStart(this, n"OnPhaseStart")
        );
        utils_resolver_data_bundle::BindTo_OnPhaseComplete(
            InDataBundle,
            FCk_Delegate_ResolverDataBundle_OnPhaseComplete(this, n"OnPhaseComplete")
        );
        utils_resolver_data_bundle::BindTo_OnAllPhasesComplete(
            InDataBundle,
            FCk_Delegate_ResolverDataBundle_OnAllPhasesComplete(this, n"OnAllPhasesComplete")
        );
    }

    UFUNCTION()
    private void OnPhaseStart(FCk_Handle_ResolverDataBundle InDataBundle, FGameplayTag InPhase)
    {
        CurrentPhase = InPhase.ToString();
        ck::Trace(f"✅ DataBundle: Phase started - {CurrentPhase}");

        auto CalculateTag = utils_gameplay_tag::ResolveGameplayTag(n"ResolverPhase.InteractionGym.Calculate");
        if (InPhase == CalculateTag)
        {
            auto BonusModifier = FCk_ResolverDataBundle_ModifierOperation(25.0f);
            BonusModifier.Set_ResolverComponent(ECk_ResolverDataBundle_ModifierComponent::BonusValue);
            BonusModifier.Set_ModifierOperation(ECk_ArithmeticOperations_Basic::Add);

            auto BonusConditional = FCk_ResolverDataBundle_ModifierOperation_Conditional(
                FGameplayTagRequirements(),
                BonusModifier
            );

            auto ModRequest = FCk_Request_ResolverDataBundle_ModifierOperation(BonusConditional);
            utils_resolver_data_bundle::Request_AddOperation_Modifier(
                InDataBundle,
                ECk_ResolverDataBundle_PhaseSelection::ThisPhase,
                ModRequest
            );
        }

        auto ApplyTag = utils_gameplay_tag::ResolveGameplayTag(n"ResolverPhase.InteractionGym.Apply");
        if (InPhase == ApplyTag)
        {
            auto MultiplierModifier = FCk_ResolverDataBundle_ModifierOperation(1.5f);
            MultiplierModifier.Set_ResolverComponent(ECk_ResolverDataBundle_ModifierComponent::TotalMultiplier);
            MultiplierModifier.Set_ModifierOperation(ECk_ArithmeticOperations_Basic::Multiply);

            auto MultiplierConditional = FCk_ResolverDataBundle_ModifierOperation_Conditional(
                FGameplayTagRequirements(),
                MultiplierModifier
            );

            auto ModRequest = FCk_Request_ResolverDataBundle_ModifierOperation(MultiplierConditional);
            utils_resolver_data_bundle::Request_AddOperation_Modifier(
                InDataBundle,
                ECk_ResolverDataBundle_PhaseSelection::ThisPhase,
                ModRequest
            );
        }
    }

    UFUNCTION()
    private void OnPhaseComplete(FCk_Handle_ResolverDataBundle InDataBundle, FGameplayTag InPhase, FCk_Payload_ResolverDataBundle_Resolved InPayload)
    {
        PhasesCompleted++;
        LastFinalValue = InPayload.Get_FinalValue();
        ck::Trace(f"✅ DataBundle: Phase complete - {InPhase.ToString()}, value: {LastFinalValue}");
    }

    UFUNCTION()
    private void OnAllPhasesComplete(FCk_Handle_ResolverDataBundle InDataBundle, FCk_Payload_ResolverDataBundle_Resolved InPayload)
    {
        AllPhasesComplete = true;
        LastFinalValue = InPayload.Get_FinalValue();
        ck::Trace(f"✅ DataBundle: All phases complete! Final value: {LastFinalValue}");
    }

    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto SelfEntity = ck::ToEntity(this);
        auto TitleText = "RESOLVER DATA BUNDLE";

        auto CompleteStr = AllPhasesComplete ? "Yes" : "No";

        auto DisplayText = "";
        DisplayText = f"{DisplayText}ResolverSource + ResolverTarget with 2 phases.\n";
        DisplayText = f"{DisplayText}Phases: Calculate (base+bonus), Apply (multiplier).\n\n";
        DisplayText = f"{DisplayText}===== Stats =====\n";
        DisplayText = f"{DisplayText}Resolutions Initiated: {ResolutionCount}\n";
        DisplayText = f"{DisplayText}Current Phase: {CurrentPhase}\n";
        DisplayText = f"{DisplayText}Phases Completed: {PhasesCompleted}\n";
        DisplayText = f"{DisplayText}All Complete: {CompleteStr}\n";
        DisplayText = f"{DisplayText}Final Value: {LastFinalValue}\n";

        auto Instructions = "";
        Instructions = f"{Instructions}Ck_GymInteraction_InitiateResolution";

        CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
    }
}
