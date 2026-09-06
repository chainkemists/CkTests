// --------------------------------------------------------------------------------------------------------------------
// GroundNav demo frame - the shape every GroundNav gym but the Tuning Range is built on
//
// A gym here is a PICTURE OF SOMETHING HAPPENING, not a panel of readback: a scene, a volume that
// builds itself over it, the field drawn under everything, and a handful of simple walkers patrolling
// between labelled posts with their own routes drawn as they go. The panel is four lines - a caption
// saying what the reader is looking at, a Verdict, and the one to three keys the gym owns - plus T to
// cycle what the picture shows.
//
// What lives here is the part that is the same in every gym: the walker (spawn, patrol, turn round,
// hold on failure, retry on request, observe, draw), the set of them the panel and the verdict read,
// the goal posts, and the panel's shared rows. The scene, the caption, the keys and the verdict rule
// are the gym's. The field itself is FCkGroundNavGym_Field from CkGroundNavGym_Common.as, and the
// debug picture is that file's Request_BakeDebugFieldAt.
//
// DELEGATES ARE THE GYM'S. A struct cannot carry a UFUNCTION, so the crowd's reached/failed signals
// are bound to the PlayerController and forwarded here through Notify_GoalReached / Notify_GoalFailed
// on the set, which finds the walker by its entity handle. That is the whole reason the set exists.
// --------------------------------------------------------------------------------------------------------------------

// Where one walker stands in its patrol, for the panel and the verdict. Reached is momentary - a
// walker turns round the frame it arrives - so a set that reads Walking everywhere is the healthy one.
enum ECkGroundNavDemo_WalkerState
{
    None,        // no body
    Pending,     // asked for a route, not yet moving
    Walking,
    Failed,      // its goal was refused and it holds where it stopped, until Request_Retry
    Idle         // has a body, no route asked of it
}

// ONE patrol walker: a crowd agent on a GroundNav planner, sent between two posts for as long as the
// gym stands. It records what the verdict needs - legs completed, failures, every link id its routes
// ever stepped onto - and draws its own installed route each frame in its own colour.
struct FCkGroundNavDemo_Walker
{
    UPROPERTY() FCk_Handle _Entity;
    UPROPERTY() FCk_Handle_CrowdAgent _Agent;
    UPROPERTY() FCk_Handle_GroundNavPath _Planner;

    UPROPERTY() FString _Name;
    UPROPERTY() FVector _PostA = FVector::ZeroVector;
    UPROPERTY() FVector _PostB = FVector::ZeroVector;
    UPROPERTY() FVector _Goal = FVector::ZeroVector;
    UPROPERTY() FLinearColor _Color = FLinearColor(0.35, 0.80, 1.0, 1.0);

    UPROPERTY() int32 _LegsCompleted = 0;
    UPROPERTY() int32 _Failures = 0;
    UPROPERTY() bool _AwaitsRetry = false;
    UPROPERTY() bool _HasWalked = false;
    UPROPERTY() bool _MoveAsked = false;
    UPROPERTY() TArray<int32> _LinkIdsCrossed;

    // Spawns the body at post A facing post B and asks for the first leg. YAW ONLY on the facing: a
    // post standing higher than the spawn is a fact about the route, not about which way the body
    // faces, and the full rotation would pitch the capsule nose-up before it took a step.
    bool Request_Spawn(
        FCk_Handle InOwner,
        FName InDebugName,
        FVector InPostA,
        FVector InPostB,
        float InRadiusUu,
        float InHeightUu,
        FLinearColor InColor,
        const FCk_Delegate_CrowdAgent_OnGoalReached&in InOnReached,
        const FCk_Delegate_CrowdAgent_OnGoalFailed&in InOnFailed)
    {
        Request_Destroy();

        _Name = InDebugName.ToString();
        _PostA = InPostA;
        _PostB = InPostB;
        _Color = InColor;

        auto Entity = utils_entity_lifetime::Request_CreateEntity(InOwner);
        Entity.Set_DebugName(InDebugName);

        FRotator Facing = FRotator(0.0, (InPostB - InPostA).Rotation().Yaw, 0.0);

        auto Transform = utils_transform::Add(Entity,
            FTransform(Facing, InPostA, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        auto Agent = utils_crowd_agent::Add(Transform,
            FCk_Fragment_CrowdAgent_ParamsData(InRadiusUu, InHeightUu));

        if (ck::Is_NOT_Valid(Agent))
        {
            ck::groundnav::Warning(f"GroundNav demo: walker {_Name} got no crowd agent handle");
            utils_entity_lifetime::Request_DestroyEntity(Entity);
            return false;
        }

        utils_velocity::Add(Entity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(Entity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(Entity);

        // Composed HERE with the radius the crowd's own GroundNav dispatch would have used, so the
        // handle Get_LinksOnPath and the route draw are asked of is one this frame holds.
        _Planner = utils_ground_nav_path::Add(Entity,
            FCk_Fragment_GroundNavPath_ParamsData(InRadiusUu));

        utils_crowd_agent::BindTo_OnGoalReached(Agent, InOnReached,
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::BindTo_OnGoalFailed(Agent, InOnFailed,
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        _Entity = Entity;
        _Agent = Agent;
        _LegsCompleted = 0;
        _Failures = 0;
        _AwaitsRetry = false;
        _HasWalked = false;
        _LinkIdsCrossed.Empty();

        Request_MoveTo(InPostB);

        return true;
    }

    void Request_Destroy()
    {
        if (ck::IsValid(_Entity))
        { utils_entity_lifetime::Request_DestroyEntity(_Entity); }

        _Entity = FCk_Handle();
        _Agent = FCk_Handle_CrowdAgent();
        _Planner = FCk_Handle_GroundNavPath();
        _MoveAsked = false;
        _AwaitsRetry = false;
    }

    bool Get_IsValid()
    { return ck::IsValid(_Agent); }

    // Whether this walker is the one a crowd signal named.
    bool Get_Is(FCk_Handle_CrowdAgent InAgent)
    { return ck::IsValid(_Agent) && FCk_Handle(InAgent) == _Entity; }

    // FORCED when re-asking: a body in a failed hold has the crowd REJECT a plain MoveTo to the goal
    // it just failed towards (CkCrowdAgent_HandleRequests_Processor.cpp, "same failed-held goal"),
    // which is exactly what a retry and a replan ask for. ForceRepath is the request's own way past
    // that rule; a first leg and a turn-round are new goals and need no force.
    void Request_MoveTo(FVector InGoal, bool InForceRepath = false)
    {
        if (ck::Is_NOT_Valid(_Agent))
        { return; }

        _Goal = InGoal;
        _MoveAsked = true;
        _AwaitsRetry = false;

        auto Request = FCk_Request_CrowdAgent_MoveTo(InGoal);
        Request.Set_ForceRepath(InForceRepath);

        utils_crowd_agent::Request_MoveTo(_Agent, Request);
    }

    // The far post from where the body stands - which end it is NEARER, not a world sign test, because
    // the scene sits wherever the grid layout put its station.
    FVector Get_FarPost()
    {
        const auto Here = Get_Location();

        if ((Here - _PostB).Size() < (Here - _PostA).Size())
        { return _PostA; }

        return _PostB;
    }

    // On arrival: one leg done, turn round. A body that reached once and parked says nothing about a
    // field that changes a minute later, and the round trip is what keeps the picture moving.
    void Notify_GoalReached()
    {
        _LegsCompleted += 1;
        Request_MoveTo(Get_FarPost());
    }

    // On refusal: hold and record. Re-asking HERE would be a plan-fail-plan loop for as long as the
    // cause stands (a disabled link, a painted corridor); the gym re-asks at the moment the cause
    // changes, through Request_Retry.
    void Notify_GoalFailed()
    {
        _Failures += 1;
        _AwaitsRetry = true;
    }

    void Request_Retry()
    {
        if (_AwaitsRetry == false)
        { return; }

        Request_MoveTo(Get_FarPost(), true);
    }

    // Re-asks the CURRENT goal - for a gym that changed the ground under a body mid-leg and wants the
    // route re-planned against the new publish without turning the body round.
    void Request_Replan()
    {
        if (ck::Is_NOT_Valid(_Agent))
        { return; }

        Request_MoveTo(_Goal, true);
    }

    FVector Get_Location()
    {
        if (ck::Is_NOT_Valid(_Entity))
        { return FVector::ZeroVector; }

        return utils_transform::Get_EntityCurrentLocation(utils_transform::DoCastChecked(_Entity));
    }

    ECkGroundNavDemo_WalkerState Get_State()
    {
        if (ck::Is_NOT_Valid(_Agent))
        { return ECkGroundNavDemo_WalkerState::None; }

        if (_AwaitsRetry)
        { return ECkGroundNavDemo_WalkerState::Failed; }

        const auto Movement = utils_crowd_agent::Get_MovementState(_Agent);

        if (Movement == ECk_CrowdAgent_MovementState::Walking)
        { return ECkGroundNavDemo_WalkerState::Walking; }

        if (Movement == ECk_CrowdAgent_MovementState::PathPending)
        { return ECkGroundNavDemo_WalkerState::Pending; }

        if (_MoveAsked)
        { return ECkGroundNavDemo_WalkerState::Pending; }

        return ECkGroundNavDemo_WalkerState::Idle;
    }

    FString Get_StateText()
    {
        const auto State = Get_State();

        if (State == ECkGroundNavDemo_WalkerState::Walking)
        { return "walking"; }
        if (State == ECkGroundNavDemo_WalkerState::Pending)
        { return "planning"; }
        if (State == ECkGroundNavDemo_WalkerState::Failed)
        { return "no route - holding"; }
        if (State == ECkGroundNavDemo_WalkerState::Idle)
        { return "idle"; }

        return "none";
    }

    // The link ids the CURRENT route steps onto, off the planner - valid only against the plan that
    // is installed now.
    TArray<int32> Get_LinkIdsOnRoute()
    {
        auto Ids = TArray<int32>();

        if (ck::Is_NOT_Valid(_Planner))
        { return Ids; }

        auto Spans = utils_ground_nav_path::Get_LinksOnPath(_Planner);

        for (int32 Index = 0; Index < Spans.Num(); Index++)
        { Ids.Add(Spans[Index].Get_LinkId()); }

        return Ids;
    }

    // Called once per frame by the set: records that the body has been seen walking, and folds the
    // links its route names into the ever-growing record the verdict reads. The pass that reads the
    // agent is the pass that remembers, so nothing reads it twice to keep it.
    void Do_Observe()
    {
        if (ck::Is_NOT_Valid(_Agent))
        { return; }

        if (utils_crowd_agent::Get_MovementState(_Agent) == ECk_CrowdAgent_MovementState::Walking)
        { _HasWalked = true; }

        auto Ids = Get_LinkIdsOnRoute();

        for (int32 Index = 0; Index < Ids.Num(); Index++)
        {
            if (_LinkIdsCrossed.Contains(Ids[Index]) == false)
            { _LinkIdsCrossed.Add(Ids[Index]); }
        }
    }

    // The route the body is walking, drawn fresh each frame with zero lifetime: a replan replaces the
    // whole waypoint array, and a persistent line would leave the abandoned route lying under the new
    // one. Link spans are drawn over the top in orange, twice as thick.
    void Do_DrawRoute(float InRiseUu, float InThickness)
    {
        if (ck::Is_NOT_Valid(_Planner))
        { return; }

        const auto Waypoints = utils_ground_nav_path::Get_Result(_Planner).Get_Waypoints();

        if (Waypoints.Num() < 2)
        { return; }

        FVector Rise = FVector(0.0, 0.0, InRiseUu);
        FLinearColor RouteColor = _Color;
        FLinearColor LinkColor = FLinearColor(1.0, 0.55, 0.10, 1.0);

        for (int32 Index = 0; Index < Waypoints.Num() - 1; Index++)
        {
            utils_debug_draw::DrawDebugLine(Waypoints[Index] + Rise, Waypoints[Index + 1] + Rise,
                RouteColor, 0.0f, float32(InThickness));
        }

        auto Spans = utils_ground_nav_path::Get_LinksOnPath(_Planner);

        for (int32 SpanIndex = 0; SpanIndex < Spans.Num(); SpanIndex++)
        {
            const auto Entry = Spans[SpanIndex].Get_EntryWaypointIndex();
            const auto Exit = Spans[SpanIndex].Get_ExitWaypointIndex();

            if (Waypoints.IsValidIndex(Entry) == false || Waypoints.IsValidIndex(Exit) == false)
            { continue; }

            for (int32 Index = Entry; Index < Exit; Index++)
            {
                utils_debug_draw::DrawDebugLine(Waypoints[Index] + Rise, Waypoints[Index + 1] + Rise,
                    LinkColor, 0.0f, float32(InThickness * 2.0f));
            }
        }
    }

    // A body that has no route to draw still needs to be findable: a small sphere in its colour over
    // its head, and its state beside it when it is not simply walking.
    void Do_DrawBody(float InHeightUu)
    {
        if (ck::Is_NOT_Valid(_Entity))
        { return; }

        const auto Here = Get_Location();
        FVector Head = Here + FVector(0.0, 0.0, InHeightUu + 20.0);
        FLinearColor Color = _Color;

        utils_debug_draw::DrawDebugSphere(Head, 12.0, 8, Color, 0.0, 1.5);

        const auto State = Get_State();

        if (State == ECkGroundNavDemo_WalkerState::Walking)
        { return; }

        FLinearColor TextColor = FLinearColor(1.0, 0.35, 0.25, 1.0);

        if (State != ECkGroundNavDemo_WalkerState::Failed)
        { TextColor = FLinearColor(0.85, 0.85, 0.85, 1.0); }

        utils_debug_draw::DrawDebugString(Head + FVector(0.0, 0.0, 25.0), Get_StateText(), TextColor, 0.0f);
    }
}

// The walkers a gym holds, and the questions the panel and the verdict ask of them together.
struct FCkGroundNavDemo_WalkerSet
{
    UPROPERTY() TArray<FCkGroundNavDemo_Walker> _Walkers;

    UPROPERTY() float _RouteRiseUu = 15.0f;
    UPROPERTY() float _RouteThickness = 5.0f;
    UPROPERTY() float _BodyHeightUu = 180.0f;

    int32 Get_Count()
    { return _Walkers.Num(); }

    // Spawns one more walker patrolling A <-> B and returns whether it stands.
    bool Request_Add(
        FCk_Handle InOwner,
        FName InDebugName,
        FVector InPostA,
        FVector InPostB,
        float InRadiusUu,
        float InHeightUu,
        FLinearColor InColor,
        const FCk_Delegate_CrowdAgent_OnGoalReached&in InOnReached,
        const FCk_Delegate_CrowdAgent_OnGoalFailed&in InOnFailed)
    {
        auto Walker = FCkGroundNavDemo_Walker();

        if (Walker.Request_Spawn(InOwner, InDebugName, InPostA, InPostB, InRadiusUu, InHeightUu, InColor,
                InOnReached, InOnFailed) == false)
        { return false; }

        _BodyHeightUu = InHeightUu;
        _Walkers.Add(Walker);

        return true;
    }

    void Request_DestroyAll()
    {
        for (int32 Index = 0; Index < _Walkers.Num(); Index++)
        { _Walkers[Index].Request_Destroy(); }

        _Walkers.Empty();
    }

    // Forwarded from the PlayerController's bound UFUNCTIONs.
    void Notify_GoalReached(FCk_Handle_CrowdAgent InAgent)
    {
        for (int32 Index = 0; Index < _Walkers.Num(); Index++)
        {
            if (_Walkers[Index].Get_Is(InAgent))
            {
                _Walkers[Index].Notify_GoalReached();
                return;
            }
        }
    }

    void Notify_GoalFailed(FCk_Handle_CrowdAgent InAgent)
    {
        for (int32 Index = 0; Index < _Walkers.Num(); Index++)
        {
            if (_Walkers[Index].Get_Is(InAgent))
            {
                _Walkers[Index].Notify_GoalFailed();
                return;
            }
        }
    }

    // Re-asks every walker that is holding on a refusal. The gym calls this at the moment the cause
    // may have gone - a link re-enabled, paint released, a repair published - and at no other time.
    void Request_RetryAll()
    {
        for (int32 Index = 0; Index < _Walkers.Num(); Index++)
        { _Walkers[Index].Request_Retry(); }
    }

    // Re-plans every walker against the current publish without turning any of them round.
    void Request_ReplanAll()
    {
        for (int32 Index = 0; Index < _Walkers.Num(); Index++)
        { _Walkers[Index].Request_Replan(); }
    }

    // Once per frame from the PlayerController's Tick: observe, then draw every route and body.
    void Do_Tick()
    {
        for (int32 Index = 0; Index < _Walkers.Num(); Index++)
        {
            _Walkers[Index].Do_Observe();
            _Walkers[Index].Do_DrawRoute(_RouteRiseUu, _RouteThickness);
            _Walkers[Index].Do_DrawBody(_BodyHeightUu);
        }
    }

    // Per-walker reads for a gym whose verdict names individuals (W0 through the pillars, W1 up the
    // ramp, W2 refused by design). Out-of-range asks answer None / false rather than ensure.
    ECkGroundNavDemo_WalkerState Get_State(int32 InIndex)
    {
        if (_Walkers.IsValidIndex(InIndex) == false)
        { return ECkGroundNavDemo_WalkerState::None; }

        return _Walkers[InIndex].Get_State();
    }

    bool Get_HasWalked(int32 InIndex)
    {
        if (_Walkers.IsValidIndex(InIndex) == false)
        { return false; }

        return _Walkers[InIndex]._HasWalked;
    }

    int32 Get_WalkingCount()
    {
        int32 Count = 0;

        for (int32 Index = 0; Index < _Walkers.Num(); Index++)
        {
            if (_Walkers[Index].Get_State() == ECkGroundNavDemo_WalkerState::Walking)
            { Count += 1; }
        }

        return Count;
    }

    int32 Get_FailedCount()
    {
        int32 Count = 0;

        for (int32 Index = 0; Index < _Walkers.Num(); Index++)
        {
            if (_Walkers[Index].Get_State() == ECkGroundNavDemo_WalkerState::Failed)
            { Count += 1; }
        }

        return Count;
    }

    int32 Get_PendingCount()
    {
        int32 Count = 0;

        for (int32 Index = 0; Index < _Walkers.Num(); Index++)
        {
            if (_Walkers[Index].Get_State() == ECkGroundNavDemo_WalkerState::Pending)
            { Count += 1; }
        }

        return Count;
    }

    int32 Get_LegsCompleted()
    {
        int32 Count = 0;

        for (int32 Index = 0; Index < _Walkers.Num(); Index++)
        { Count += _Walkers[Index]._LegsCompleted; }

        return Count;
    }

    int32 Get_TotalFailures()
    {
        int32 Count = 0;

        for (int32 Index = 0; Index < _Walkers.Num(); Index++)
        { Count += _Walkers[Index]._Failures; }

        return Count;
    }

    bool Get_AnyHasWalked()
    {
        for (int32 Index = 0; Index < _Walkers.Num(); Index++)
        {
            if (_Walkers[Index]._HasWalked)
            { return true; }
        }

        return false;
    }

    bool Get_AllHaveWalked()
    {
        if (_Walkers.Num() == 0)
        { return false; }

        for (int32 Index = 0; Index < _Walkers.Num(); Index++)
        {
            if (_Walkers[Index]._HasWalked == false)
            { return false; }
        }

        return true;
    }

    // Every link id any walker's route has ever stepped onto, in first-seen order.
    TArray<int32> Get_LinkIdsEverCrossed()
    {
        auto Ids = TArray<int32>();

        for (int32 WalkerIndex = 0; WalkerIndex < _Walkers.Num(); WalkerIndex++)
        {
            auto Crossed = _Walkers[WalkerIndex]._LinkIdsCrossed;

            for (int32 Index = 0; Index < Crossed.Num(); Index++)
            {
                if (Ids.Contains(Crossed[Index]) == false)
                { Ids.Add(Crossed[Index]); }
            }
        }

        return Ids;
    }

    // One line for the panel: "3 walking - 12 legs done" and the exceptions when there are any.
    FString Get_StatusText()
    {
        if (_Walkers.Num() == 0)
        { return "no walkers"; }

        FString Text = f"{Get_WalkingCount()} of {_Walkers.Num()} walking - {Get_LegsCompleted()} legs done";

        const auto Pending = Get_PendingCount();
        const auto Failed = Get_FailedCount();

        if (Pending > 0)
        { Text += f" - {Pending} planning"; }

        if (Failed > 0)
        { Text += f" - {Failed} holding with no route"; }

        return Text;
    }
}

namespace CkGroundNavDemo
{
    //------------------------------------------------------------------------
    // Posts and captions in the world
    //------------------------------------------------------------------------

    // A goal post: a vertical line from the ground, a sphere at its top and its label. Drawn each frame
    // with zero lifetime so a Clear does not take it and a scene that moves its posts keeps them true.
    void Draw_GoalPost(FVector InWhere, FString InLabel, FLinearColor InColor)
    {
        FVector Base = InWhere;
        FVector Top = InWhere + FVector(0.0, 0.0, 220.0);
        FLinearColor Color = InColor;

        utils_debug_draw::DrawDebugLine(Base, Top, Color, 0.0f, 3.0f);
        utils_debug_draw::DrawDebugSphere(Top, 18.0, 8, Color, 0.0, 2.0);
        utils_debug_draw::DrawDebugString(Top + FVector(0.0, 0.0, 30.0), InLabel, Color, 0.0f);
    }

    // A caption standing in the world beside the thing it names - the one-line "what this is" a
    // reader sees without looking at the panel.
    void Draw_WorldCaption(FVector InWhere, FString InText)
    {
        FLinearColor Color = FLinearColor(1.0, 1.0, 1.0, 1.0);

        utils_debug_draw::DrawDebugString(InWhere, InText, Color, 0.0f);
    }

    // The walkers' colours, so several on one scene can be told apart in the picture and the panel.
    FLinearColor Get_WalkerColor(int32 InIndex)
    {
        auto Colors = TArray<FLinearColor>();
        Colors.Add(FLinearColor(0.35, 0.80, 1.00, 1.0));
        Colors.Add(FLinearColor(0.55, 1.00, 0.45, 1.0));
        Colors.Add(FLinearColor(1.00, 0.85, 0.30, 1.0));
        Colors.Add(FLinearColor(1.00, 0.45, 0.85, 1.0));
        Colors.Add(FLinearColor(0.70, 0.60, 1.00, 1.0));
        Colors.Add(FLinearColor(0.40, 1.00, 0.90, 1.0));
        Colors.Add(FLinearColor(1.00, 0.60, 0.40, 1.0));
        Colors.Add(FLinearColor(0.85, 0.85, 0.85, 1.0));

        return Colors[InIndex % Colors.Num()];
    }

    //------------------------------------------------------------------------
    // The panel - four lines, in this order, on every demo gym
    //------------------------------------------------------------------------

    // Rows 0-2: the caption, the Verdict, the walkers. A gym appends its own keyed rows after these
    // and then Get_DrawModeRow, so its first keyed row is index k_DemoHeaderRowCount.
    const int32 k_DemoHeaderRowCount = 3;

    TArray<FCkGym_ControlRow> Get_HeaderRows(FString InCaption, FString InVerdict, bool InVerdictFails, FString InWalkersText)
    {
        auto Rows = TArray<FCkGym_ControlRow>();

        Rows.Add(CkGym_Control::Status("This shows", InCaption));
        Rows.Add(CkGym_Control::Status("Verdict", InVerdict, InVerdictFails));
        Rows.Add(CkGym_Control::Status("Walkers", InWalkersText));

        return Rows;
    }

    // T cycles what the picture under the walkers shows; the gym re-bakes on the new mode.
    FCkGym_ControlRow Get_DrawModeRow(int32 InDrawMode)
    {
        const auto Labels = CkGroundNavGym::Get_DrawModeLabels();
        const auto Mode = Math::Clamp(InDrawMode, 0, CkGroundNavGym::Get_DrawModeCount() - 1);

        return CkGym_Control::Cycle(EKeys::T, "T", "Picture", Labels[Mode]);
    }

    // A verdict that waits for the walkers before it judges: a gym's rule only applies once a body
    // has been seen moving, and before that the row says so instead of failing.
    FString Get_VerdictPendingText(const FCkGroundNavGym_Field&in InField)
    {
        FCkGroundNavGym_Field Field = InField;

        if (Field.Get_IsBuilt() == false)
        { return "field building - verdict pending"; }

        return "walkers starting - verdict pending";
    }
}
