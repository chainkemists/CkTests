//============================================================================
// SCENE NODE + TWEEN GYM - GAME MODE & PLAYER CONTROLLER
//
// Stations progress from simple to complex, each driving a scene-node parent
// chain with a Tween on the root. Exercises the interaction between the Tween
// ApplyToTransform processor, the Transform HandleRequests processor, and the
// layered SceneNode Update processors - a dependency gap between these leaves
// descendants stuck at initial world positions while the tweened root moves.
//
// STATIONS:
//   1. SIMPLE - Tweened root + single scene-node child (1 hop).
//   2. CHAIN  - Tweened root + 3-level chain (root -> A -> B).
//   3. DEEP   - Tweened root + 5-level chain, stress-tests propagation depth.
//
// Each station draws filled shapes at every node and a dashed line between
// each parent/child pair (redrawn every frame). DESYNC status flips to true
// when the ECS-reported leaf world drifts from the AS-composed expected world
// by more than 5 units - the signature of broken propagation.
//============================================================================

namespace Ck
{
    asset Asset_SceneNodeTweenGym_Tags of UCk_GameplayTags
    {
        // no tags required beyond what the station uses internally
    }
}

//============================================================================
// Console-command -> station messages
//============================================================================

USTRUCT()
struct FCk_Message_SceneNodeTweenGym_Reset
{
};

//============================================================================
// Player controller
//============================================================================

class ACk_SceneNodeTweenGym_PlayerController : ACk_Gym_Base_PlayerController
{
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.SceneNodeTween.Simple");
            Station.Title = FText::FromString("TWEEN + SCENE NODE (SIMPLE)");
            Station.AutoSize = true;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Root tween + 1 scene-node child."));
            Description.Add(FText::FromString("Child tracks the tweened root via"));
            Description.Add(FText::FromString("single-hop transform propagation."));
            Description.Add(FText::FromString(""));
            Description.Add(FText::FromString("Purple sphere: co-located with the"));
            Description.Add(FText::FromString("cyan child box (leaf IS the child)."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.SceneNodeTween.Chain");
            Station.Title = FText::FromString("TWEEN + SCENE NODE (CHAIN)");
            Station.AutoSize = true;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Root tween + 3-level chain"));
            Description.Add(FText::FromString("(root -> A yaw45 -> B roll30)."));
            Description.Add(FText::FromString("Exercises multi-layer rotation"));
            Description.Add(FText::FromString("composition under a tweened root."));
            Description.Add(FText::FromString(""));
            Description.Add(FText::FromString("Purple sphere: co-located with the"));
            Description.Add(FText::FromString("purple B box (leaf IS node B)."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.SceneNodeTween.Deep");
            Station.Title = FText::FromString("TWEEN + SCENE NODE (DEEP)");
            Station.AutoSize = true;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Root tween + 5-level chain."));
            Description.Add(FText::FromString("Stress-tests propagation depth —"));
            Description.Add(FText::FromString("every layer must observe the"));
            Description.Add(FText::FromString("previous layer's update each frame."));
            Description.Add(FText::FromString(""));
            Description.Add(FText::FromString("Purple sphere: OFFSET from the last"));
            Description.Add(FText::FromString("box. It sits at the end of the 5th"));
            Description.Add(FText::FromString("local offset (its own link), so it"));
            Description.Add(FText::FromString("is past link 4 by the 5th local."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        return Stations;
    }

    void Request_StartGym() override
    {
        Request_SpawnStation("Gym.SceneNodeTween.Simple", UCk_EntityScript_SceneNodeTweenGym_SimpleStation);
        Request_SpawnStation("Gym.SceneNodeTween.Chain",  UCk_EntityScript_SceneNodeTweenGym_ChainStation);
        Request_SpawnStation("Gym.SceneNodeTween.Deep",   UCk_EntityScript_SceneNodeTweenGym_DeepStation);
    }

    private void Request_SpawnStation(FString InStationTag, TSubclassOf<UCk_EntityScript_UE> InScriptClass)
    {
        auto StationTransform = Get_StationAnchorTransform(InStationTag, ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);
        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle(InStationTag),
            InScriptClass,
            FInstancedStruct::Make(SpawnParams));
    }

    private void DoSetAuto(bool InEnabled)
    {
        _AutoRunning = InEnabled;
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_SceneNodeTweenGym_Station"))
        { utils_messaging::Broadcast(E, FCk_Message_Gym_AutoSet(InEnabled)); }
    }

    private void DoReset()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_SceneNodeTweenGym_Station"))
        { utils_messaging::Broadcast(E, FCk_Message_SceneNodeTweenGym_Reset()); }
    }

    //--------------------------------------------------------------------------------------------------------------------------
    // CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
    //
    // Pausing the tweens is what makes a desync readable - a frozen chain can be compared node by node,
    // a moving one cannot. That is the control worth having on screen.
    //--------------------------------------------------------------------------------------------------------------------------

    // The stations own the flag (gym_auto), start with it running, and expose no readback - so the
    // panel mirrors what this controller last broadcast. Nothing else writes it: the stations only
    // flip their own Auto through gym_auto::StopAuto, which none of these three stations calls.
    private bool _AutoRunning = true;

    FString Get_ControlPanelTitle() override
    {
        return "SCENE NODE + TWEEN";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Toggle(EKeys::J, "J", "Auto (all stations)", _AutoRunning));
        Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Reset all stations"));
        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex == 0) { DoSetAuto(!_AutoRunning); }
        else if (InRowIndex == 1) { DoReset(); }
    }
}

//============================================================================
// GAME MODE
//============================================================================

class ACk_SceneNodeTweenGym_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_SceneNodeTweenGym_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
