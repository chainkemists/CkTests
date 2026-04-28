//============================================================================
// SCENE NODE + TWEEN GYM — GAME MODE & PLAYER CONTROLLER
//
// Stations progress from simple to complex, each driving a scene-node parent
// chain with a Tween on the root. Exercises the interaction between the Tween
// ApplyToTransform processor, the Transform HandleRequests processor, and the
// layered SceneNode Update processors — a dependency gap between these leaves
// descendants stuck at initial world positions while the tweened root moves.
//
// STATIONS:
//   1. SIMPLE — Tweened root + single scene-node child (1 hop).
//   2. CHAIN  — Tweened root + 3-level chain (root -> A -> B).
//   3. DEEP   — Tweened root + 5-level chain, stress-tests propagation depth.
//
// Each station draws filled shapes at every node and a dashed line between
// each parent/child pair (redrawn every frame). DESYNC status flips to true
// when the ECS-reported leaf world drifts from the AS-composed expected world
// by more than 5 units — the signature of broken propagation.
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

    UFUNCTION(Exec, DisplayName="SceneNodeTween Gym - Auto")
    void Ck_GymSceneNodeTween_Auto(int32 InEnabled = 1)
    {
        auto Enabled = InEnabled != 0;
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_SceneNodeTweenGym_Station"))
        { utils_messaging::Broadcast(E, FCk_Message_Gym_AutoSet(Enabled)); }
    }

    UFUNCTION(Exec, DisplayName="SceneNodeTween Gym - Reset")
    void Ck_GymSceneNodeTween_Reset()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_SceneNodeTweenGym_Station"))
        { utils_messaging::Broadcast(E, FCk_Message_SceneNodeTweenGym_Reset()); }
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
