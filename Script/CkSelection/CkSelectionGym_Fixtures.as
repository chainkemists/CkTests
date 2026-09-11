// Language=angelscript

namespace selection_gym
{
    FGameplayTag Get_RootLabel()
    {
        return utils_gameplay_tag::ResolveGameplayTag(n"Ck.Debug.Selection.Root");
    }

    FCk_Handle Create_Candidate(FCk_Handle InLifetimeParent, FName InDebugName, FVector InLocation)
    {
        auto Candidate = utils_entity_lifetime::Request_CreateEntity(InLifetimeParent);
        Candidate.Set_DebugName(InDebugName);
        Candidate.Request_OverrideToSelf();
        utils_transform::Add(
            Candidate,
            FTransform(FRotator::ZeroRotator, InLocation, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        utils_gameplay_label::Add(Candidate, Get_RootLabel());
        return Candidate;
    }

    FCk_Handle Create_OrdinaryChild(FCk_Handle InLifetimeParent, FName InDebugName)
    {
        auto Child = utils_entity_lifetime::Request_CreateEntity(InLifetimeParent);
        Child.Set_DebugName(InDebugName);
        return Child;
    }

    FCk_Handle Create_OrdinaryTransformChild(FCk_Handle InLifetimeParent, FName InDebugName, FVector InLocation)
    {
        auto Child = Create_OrdinaryChild(InLifetimeParent, InDebugName);
        utils_transform::Add(
            Child,
            FTransform(FRotator::ZeroRotator, InLocation, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        return Child;
    }

    FCk_Handle Create_CompositeCandidate(FCk_Handle InLifetimeParent, FVector InLocation)
    {
        auto Candidate = Create_Candidate(InLifetimeParent, n"Selection.Composite.Root", InLocation);
        auto Transform = Candidate.As_Transform();

        auto SceneNodeOffset = FTransform(FRotator::ZeroRotator, FVector(0.0f, 150.0f, 100.0f), FVector::OneVector);
        utils_scene_node::Create(Transform, SceneNodeOffset);

        auto OrdinaryChild = Create_OrdinaryTransformChild(
            Candidate,
            n"Selection.Composite.OrdinaryChild",
            InLocation + FVector(0.0f, -150.0f, 0.0f));
        Create_OrdinaryChild(OrdinaryChild, n"Selection.Composite.NoTransformDescendant");

        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(1.0f));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        utils_timer::Add(Candidate, TimerParams);

        auto AttributeName = utils_gameplay_tag::ResolveGameplayTag(n"Ck.Debug.Selection.Composite.Counter");
        utils_integer_attribute::Add(Candidate, AttributeName, 7, ECk_Replication::DoesNotReplicate);

        utils_state_machine::Add(
            Candidate,
            FCk_Fragment_StateMachine_ParamsData(UCk_SelectionGym_State_Idle));
        return Candidate;
    }
}

class UCk_SelectionGym_State_Idle : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
    }
}
