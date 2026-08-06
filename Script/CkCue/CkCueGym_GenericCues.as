//============================================================================
// CUE GYM - GAMEPLAY TAGS
//============================================================================

namespace Ck
{
	asset Asset_CueGym_Tags of UCk_GameplayTags
	{
		GameplayTags.Add(n"CueGym.Lifetime.AfterOneFrame");
		GameplayTags.Add(n"CueGym.Lifetime.Persistent");
		GameplayTags.Add(n"CueGym.Lifetime.Timed");
		GameplayTags.Add(n"CueGym.Lifetime.Custom");
		GameplayTags.Add(n"CueGym.Concurrency.Multiple");
		GameplayTags.Add(n"CueGym.Concurrency.Restart");
		GameplayTags.Add(n"CueGym.Owner.SkipInvalid");
		GameplayTags.Add(n"CueGym.Owner.RequireValid");
		GameplayTags.Add(n"CueGym.Restart.Restartable");
		GameplayTags.Add(n"CueGym.Transient.NoOwner");
		GameplayTags.Add(n"CueGym.OwnerDestruction.Attached");
	}
}

//============================================================================
// CUE GYM - SPAWN PARAMS
//============================================================================

USTRUCT()
struct FCkCueGym_SpawnParams
{
	UPROPERTY()
	FTransform InitialTransform = FTransform::Identity;

	FCkCueGym_SpawnParams(FTransform InTransform)
	{
		InitialTransform = InTransform;
	}
}

//============================================================================
// CUE GYM - PMG SPHERE HELPER
//============================================================================

namespace CueGym_Pmg
{
	// Draws a PMG filled sphere at entity location + offset, returns handle for cleanup
	FCk_Handle_Pmg_DebugShape DrawSphere(FCk_Handle InEntity, FVector InOffset, FLinearColor InColor, float32 InRadius = 20.0f)
	{
		auto TransformHandle = InEntity.As_Transform();
		if (ck::Is_NOT_Valid(TransformHandle))
		{
			return FCk_Handle_Pmg_DebugShape();
		}

		auto Transform = utils_transform::Get_EntityCurrentTransform(TransformHandle);
		auto Pos = Transform.GetLocation() + InOffset;
		return utils_pmg_basic_shapes::DrawFilledSphere(Pos, InRadius, 12, 12, InColor, true, 2.0f, ECk_Plane_Axis::XY, 0.0f);
	}

	// Draws a PMG filled box at entity location + offset, returns handle for cleanup
	FCk_Handle_Pmg_DebugShape DrawBox(FCk_Handle InEntity, FVector InOffset, FLinearColor InColor, FVector InExtent = FVector(20.0f, 20.0f, 20.0f))
	{
		auto TransformHandle = InEntity.As_Transform();
		if (ck::Is_NOT_Valid(TransformHandle))
		{
			return FCk_Handle_Pmg_DebugShape();
		}

		auto Transform = utils_transform::Get_EntityCurrentTransform(TransformHandle);
		auto Pos = Transform.GetLocation() + InOffset;
		return utils_pmg_basic_shapes::DrawFilledBox(Pos, InExtent, InColor, true, 2.0f, ECk_Plane_Axis::XY, 0.0f);
	}

	// Destroy a previous shape handle if valid
	void DestroyShape(FCk_Handle_Pmg_DebugShape& InOutHandle)
	{
		if (ck::IsValid(InOutHandle))
		{
			utils_entity_lifetime::Request_DestroyEntity(InOutHandle);
		}
	}
}

//============================================================================
// LIFETIME CUES
//============================================================================

// AfterOneFrame: Destroyed immediately after BeginPlay (one-frame lifetime)
class UCk_CueGym_Cue_AfterOneFrame : UCk_GenericCue_EntityScript
{
	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	default _Replication = ECk_Replication::DoesNotReplicate;
	default _LifetimeBehavior = ECk_Cue_LifetimeBehavior::AfterOneFrame;
	default _ConcurrencyPolicy = ECk_Cue_ConcurrencyPolicy::AllowMultiple;

	UFUNCTION(BlueprintOverride)
	FGameplayTag Get_CueName() const
	{
		return GameplayTags::ResolveGameplayTag(n"CueGym.Lifetime.AfterOneFrame");
	}

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
	    auto _CkPerfScope = ck::ScopedStat();
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		ck::Trace("CueGym: AfterOneFrame cue constructed - will be destroyed after one frame");
		return ECk_EntityScript_ConstructionFlow::Finished;
	}
}

// Persistent: Stays alive indefinitely until explicitly destroyed
class UCk_CueGym_Cue_Persistent : UCk_GenericCue_EntityScript
{
	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	default _Replication = ECk_Replication::DoesNotReplicate;
	default _LifetimeBehavior = ECk_Cue_LifetimeBehavior::Persistent;
	default _ConcurrencyPolicy = ECk_Cue_ConcurrencyPolicy::AllowMultiple;

	FCk_Handle_Pmg_DebugShape ShapeHandle;

	UFUNCTION(BlueprintOverride)
	FGameplayTag Get_CueName() const
	{
		return GameplayTags::ResolveGameplayTag(n"CueGym.Lifetime.Persistent");
	}

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
	    auto _CkPerfScope = ck::ScopedStat();
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_CueGym_Cue_Persistent");

		// Tick timer for continuous sphere drawing
		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"DrawTick"));

		ck::Trace("CueGym: Persistent cue constructed - will stay alive indefinitely");
		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION()
	private void DrawTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		CueGym_Pmg::DestroyShape(ShapeHandle);
		ShapeHandle = CueGym_Pmg::DrawSphere(ck::ToEntity(this), FVector(0.0f, 0.0f, 100.0f),
			FLinearColor(0.0f, 1.0f, 0.0f, 0.3f), 20.0f);
	}
}

// Timed: Auto-destroys after _LifetimeDuration seconds
class UCk_CueGym_Cue_Timed : UCk_GenericCue_EntityScript
{
	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	default _Replication = ECk_Replication::DoesNotReplicate;
	default _LifetimeBehavior = ECk_Cue_LifetimeBehavior::Timed;
	default _ConcurrencyPolicy = ECk_Cue_ConcurrencyPolicy::AllowMultiple;
	default _LifetimeDuration = FCk_Time(5.0f);

	FCk_Handle_Pmg_DebugShape ShapeHandle;

	UFUNCTION(BlueprintOverride)
	FGameplayTag Get_CueName() const
	{
		return GameplayTags::ResolveGameplayTag(n"CueGym.Lifetime.Timed");
	}

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
	    auto _CkPerfScope = ck::ScopedStat();
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

		// Tick timer for sphere drawing while alive
		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"DrawTick"));

		ck::Trace("CueGym: Timed cue constructed - will auto-destroy after 5s");
		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION()
	private void DrawTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		CueGym_Pmg::DestroyShape(ShapeHandle);
		ShapeHandle = CueGym_Pmg::DrawSphere(ck::ToEntity(this), FVector(0.0f, 0.0f, 100.0f),
			FLinearColor(0.0f, 0.5f, 1.0f, 0.3f), 20.0f);
	}
}

// Custom: No automatic lifetime management - self-destructs via internal timer
class UCk_CueGym_Cue_Custom : UCk_GenericCue_EntityScript
{
	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	default _Replication = ECk_Replication::DoesNotReplicate;
	default _LifetimeBehavior = ECk_Cue_LifetimeBehavior::Custom;
	default _ConcurrencyPolicy = ECk_Cue_ConcurrencyPolicy::AllowMultiple;

	FCk_Handle_Pmg_DebugShape ShapeHandle;

	UFUNCTION(BlueprintOverride)
	FGameplayTag Get_CueName() const
	{
		return GameplayTags::ResolveGameplayTag(n"CueGym.Lifetime.Custom");
	}

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
	    auto _CkPerfScope = ck::ScopedStat();
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

		// Tick timer for sphere drawing while alive
		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"DrawTick"));

		// Self-destruct timer: 3 seconds
		auto DestroyParams = FCk_Timer_Spec(FCk_Time(3.0f));
		DestroyParams.Set_StartingState(ECk_Timer_State::Running);
		DestroyParams.Set_Behavior(ECk_Timer_Behavior::PauseOnDone);
		auto DestroyTimer = utils_timer::Add(InHandle, DestroyParams);
		DestroyTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnSelfDestructTimer"));

		ck::Trace("CueGym: Custom lifetime cue constructed - will self-destruct after 3s");
		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION()
	private void DrawTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		CueGym_Pmg::DestroyShape(ShapeHandle);
		ShapeHandle = CueGym_Pmg::DrawSphere(ck::ToEntity(this), FVector(0.0f, 0.0f, 100.0f),
			FLinearColor(1.0f, 0.5f, 0.0f, 0.3f), 20.0f);
	}

	UFUNCTION()
	private void OnSelfDestructTimer(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		ck::Trace("CueGym: Custom lifetime cue self-destructing");
		utils_entity_lifetime::Request_DestroyEntity(ck::ToEntity(this));
	}
}

//============================================================================
// CONCURRENCY CUES
//============================================================================

// AllowMultiple: Multiple instances can run simultaneously
class UCk_CueGym_Cue_Multiple : UCk_GenericCue_EntityScript
{
	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	default _Replication = ECk_Replication::DoesNotReplicate;
	default _LifetimeBehavior = ECk_Cue_LifetimeBehavior::Timed;
	default _ConcurrencyPolicy = ECk_Cue_ConcurrencyPolicy::AllowMultiple;
	default _LifetimeDuration = FCk_Time(10.0f);

	float ElapsedTime = 0.0f;
	float LifetimeSeconds = 10.0f;
	FCk_Handle_Pmg_DebugShape ShapeHandle;

	UFUNCTION(BlueprintOverride)
	FGameplayTag Get_CueName() const
	{
		return GameplayTags::ResolveGameplayTag(n"CueGym.Concurrency.Multiple");
	}

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
	    auto _CkPerfScope = ck::ScopedStat();
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_CueGym_Cue_Multiple");

		// Tick timer for animated sphere
		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"DrawTick"));

		ck::Trace("CueGym: AllowMultiple cue spawned");
		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION()
	private void DrawTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		ElapsedTime = ElapsedTime + float(InDeltaT.Get_Seconds());
		auto Progress = Math::Clamp(ElapsedTime / LifetimeSeconds, 0.0, 1.0);

		// Sphere shrinks from 25 -> 5 over lifetime
		auto Radius = float32(Math::Lerp(25.0, 5.0, Progress));

		// Color fades from bright green to dim red over lifetime
		auto Green = float32(1.0 - Progress);
		auto Red = float32(Progress);

		CueGym_Pmg::DestroyShape(ShapeHandle);
		ShapeHandle = CueGym_Pmg::DrawSphere(ck::ToEntity(this), FVector(0.0f, 0.0f, 100.0f),
			FLinearColor(Red, Green, 0.1f, 0.3f), Radius);
	}
}

// RestartExisting: New execution restarts any already-running instance
class UCk_CueGym_Cue_Restart : UCk_GenericCue_EntityScript
{
	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	default _Replication = ECk_Replication::DoesNotReplicate;
	default _LifetimeBehavior = ECk_Cue_LifetimeBehavior::Timed;
	default _ConcurrencyPolicy = ECk_Cue_ConcurrencyPolicy::RestartExisting;
	default _LifetimeDuration = FCk_Time(10.0f);

	int32 RestartCount = 0;
	float ElapsedTime = 0.0f;
	float LifetimeSeconds = 10.0f;
	FCk_Handle_Pmg_DebugShape ShapeHandle;

	UFUNCTION(BlueprintOverride)
	FGameplayTag Get_CueName() const
	{
		return GameplayTags::ResolveGameplayTag(n"CueGym.Concurrency.Restart");
	}

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
	    auto _CkPerfScope = ck::ScopedStat();
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_CueGym_Cue_Restart");

		// Tick timer for animated sphere
		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"DrawTick"));

		ck::Trace("CueGym: RestartExisting cue spawned");
		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION(BlueprintOverride)
	void DoRestart(FCk_Handle InHandle)
	{
	    auto _CkPerfScope = ck::ScopedStat();
		RestartCount++;
		ElapsedTime = 0.0f;
		ck::Trace(f"CueGym: RestartExisting cue restarted (count: {RestartCount})");
	}

	UFUNCTION()
	private void DrawTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		ElapsedTime = ElapsedTime + float(InDeltaT.Get_Seconds());
		auto Progress = Math::Clamp(ElapsedTime / LifetimeSeconds, 0.0, 1.0);

		// Sphere shrinks from 25 -> 5 over lifetime, snaps back to 25 on restart
		auto Radius = float32(Math::Lerp(25.0, 5.0, Progress));

		// Color fades from bright red to dim over lifetime, snaps back on restart
		auto Brightness = float32(1.0 - Progress * 0.7);

		CueGym_Pmg::DestroyShape(ShapeHandle);
		ShapeHandle = CueGym_Pmg::DrawSphere(ck::ToEntity(this), FVector(0.0f, 0.0f, 100.0f),
			FLinearColor(Brightness, 0.1f, 0.1f, 0.3f), Radius);
	}
}

//============================================================================
// OWNER VALIDATION CUES
//============================================================================

// SkipIfInvalid: Cue executes even if owner entity is invalid
class UCk_CueGym_Cue_OwnerSkip : UCk_GenericCue_EntityScript
{
	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	default _Replication = ECk_Replication::DoesNotReplicate;
	default _LifetimeBehavior = ECk_Cue_LifetimeBehavior::Timed;
	default _ConcurrencyPolicy = ECk_Cue_ConcurrencyPolicy::AllowMultiple;
	default _OwnerValidationPolicy = ECk_Cue_OwnerValidationPolicy::SkipIfInvalid;
	default _LifetimeDuration = FCk_Time(5.0f);

	FCk_Handle_Pmg_DebugShape ShapeHandle;

	UFUNCTION(BlueprintOverride)
	FGameplayTag Get_CueName() const
	{
		return GameplayTags::ResolveGameplayTag(n"CueGym.Owner.SkipInvalid");
	}

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
	    auto _CkPerfScope = ck::ScopedStat();
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"DrawTick"));

		ck::Trace("CueGym: SkipIfInvalid cue executed");
		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION()
	private void DrawTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		CueGym_Pmg::DestroyShape(ShapeHandle);
		ShapeHandle = CueGym_Pmg::DrawSphere(ck::ToEntity(this), FVector(0.0f, 0.0f, 100.0f),
			FLinearColor(0.2f, 0.8f, 0.8f, 0.3f), 15.0f);
	}
}

// RequireValid: Cue only executes if owner entity exists
class UCk_CueGym_Cue_OwnerRequire : UCk_GenericCue_EntityScript
{
	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	default _Replication = ECk_Replication::DoesNotReplicate;
	default _LifetimeBehavior = ECk_Cue_LifetimeBehavior::Timed;
	default _ConcurrencyPolicy = ECk_Cue_ConcurrencyPolicy::AllowMultiple;
	default _OwnerValidationPolicy = ECk_Cue_OwnerValidationPolicy::RequireValid;
	default _LifetimeDuration = FCk_Time(5.0f);

	FCk_Handle_Pmg_DebugShape ShapeHandle;

	UFUNCTION(BlueprintOverride)
	FGameplayTag Get_CueName() const
	{
		return GameplayTags::ResolveGameplayTag(n"CueGym.Owner.RequireValid");
	}

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
	    auto _CkPerfScope = ck::ScopedStat();
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"DrawTick"));

		ck::Trace("CueGym: RequireValid cue executed");
		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION()
	private void DrawTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		CueGym_Pmg::DestroyShape(ShapeHandle);
		ShapeHandle = CueGym_Pmg::DrawSphere(ck::ToEntity(this), FVector(0.0f, 0.0f, 100.0f),
			FLinearColor(0.8f, 0.8f, 0.2f, 0.3f), 15.0f);
	}
}

//============================================================================
// RESTART CUE
//============================================================================

// Restartable: Tests the Restart() method via RestartExisting concurrency
class UCk_CueGym_Cue_Restartable : UCk_GenericCue_EntityScript
{
	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	default _Replication = ECk_Replication::DoesNotReplicate;
	default _LifetimeBehavior = ECk_Cue_LifetimeBehavior::Timed;
	default _ConcurrencyPolicy = ECk_Cue_ConcurrencyPolicy::RestartExisting;
	default _LifetimeDuration = FCk_Time(8.0f);

	int32 RestartCount = 0;
	FCk_Handle_Pmg_DebugShape ShapeHandle;

	UFUNCTION(BlueprintOverride)
	FGameplayTag Get_CueName() const
	{
		return GameplayTags::ResolveGameplayTag(n"CueGym.Restart.Restartable");
	}

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
	    auto _CkPerfScope = ck::ScopedStat();
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_CueGym_Cue_Restartable");

		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"DrawTick"));

		ck::Trace("CueGym: Restartable cue constructed");
		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION(BlueprintOverride)
	void DoRestart(FCk_Handle InHandle)
	{
	    auto _CkPerfScope = ck::ScopedStat();
		RestartCount++;
		ck::Trace(f"CueGym: Restartable cue restarted (count: {RestartCount})");
	}

	UFUNCTION()
	private void DrawTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		// Color cycles continuously based on restart count using sine waves
		auto Phase = float(RestartCount) * 0.8f;
		auto Red = float32(Math::Sin(Phase) * 0.5f + 0.5f);
		auto Green = float32(Math::Sin(Phase + 2.094f) * 0.5f + 0.5f);
		auto Blue = float32(Math::Sin(Phase + 4.189f) * 0.5f + 0.5f);

		CueGym_Pmg::DestroyShape(ShapeHandle);
		ShapeHandle = CueGym_Pmg::DrawSphere(ck::ToEntity(this), FVector(0.0f, 0.0f, 100.0f),
			FLinearColor(Red, Green, Blue, 0.3f), 20.0f);
	}
}

//============================================================================
// TRANSIENT CUE
//============================================================================

// Transient: Executes without a persistent owner entity
class UCk_CueGym_Cue_Transient : UCk_GenericCue_EntityScript
{
	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	default _Replication = ECk_Replication::DoesNotReplicate;
	default _LifetimeBehavior = ECk_Cue_LifetimeBehavior::Timed;
	default _ConcurrencyPolicy = ECk_Cue_ConcurrencyPolicy::AllowMultiple;
	default _OwnerValidationPolicy = ECk_Cue_OwnerValidationPolicy::RequireValid;
	default _LifetimeDuration = FCk_Time(5.0f);

	FCk_Handle_Pmg_DebugShape ShapeHandle;

	UFUNCTION(BlueprintOverride)
	FGameplayTag Get_CueName() const
	{
		return GameplayTags::ResolveGameplayTag(n"CueGym.Transient.NoOwner");
	}

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
	    auto _CkPerfScope = ck::ScopedStat();
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_CueGym_Cue_Transient");

		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"DrawTick"));

		ck::Trace("CueGym: Transient cue executed (attached to transient entity)");
		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION()
	private void DrawTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		CueGym_Pmg::DestroyShape(ShapeHandle);
		ShapeHandle = CueGym_Pmg::DrawSphere(ck::ToEntity(this), FVector(0.0f, 0.0f, 100.0f),
			FLinearColor(0.8f, 0.4f, 0.8f, 0.3f), 15.0f);
	}
}

//============================================================================
// OWNER DESTRUCTION CUE
//============================================================================

// OwnerDestruction: Persistent cue that relies on owner destruction to be cleaned up
class UCk_CueGym_Cue_OwnerDestruction : UCk_GenericCue_EntityScript
{
	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	default _Replication = ECk_Replication::DoesNotReplicate;
	default _LifetimeBehavior = ECk_Cue_LifetimeBehavior::Persistent;
	default _ConcurrencyPolicy = ECk_Cue_ConcurrencyPolicy::AllowMultiple;
	default _OwnerValidationPolicy = ECk_Cue_OwnerValidationPolicy::RequireValid;

	FCk_Handle_Pmg_DebugShape ShapeHandle;

	UFUNCTION(BlueprintOverride)
	FGameplayTag Get_CueName() const
	{
		return GameplayTags::ResolveGameplayTag(n"CueGym.OwnerDestruction.Attached");
	}

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
	    auto _CkPerfScope = ck::ScopedStat();
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_CueGym_Cue_OwnerDestruction");

		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"DrawTick"));

		ck::Trace("CueGym: OwnerDestruction cue spawned (persistent, will die with owner)");
		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION()
	private void DrawTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		CueGym_Pmg::DestroyShape(ShapeHandle);
		ShapeHandle = CueGym_Pmg::DrawSphere(ck::ToEntity(this), FVector(0.0f, 0.0f, 100.0f),
			FLinearColor(0.3f, 0.7f, 1.0f, 0.3f), 15.0f);
	}
}
