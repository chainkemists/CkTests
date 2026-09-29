// Language=angelscript
// A plain movable actor whose root component drives an anchor-driven sway node (the Add-on-anchor row).
class ACk_SwayAutoTest_AnchorHelper : AActor
{
    default bReplicates = false;

    UPROPERTY(DefaultComponent, RootComponent)
    USceneComponent SceneRoot;

    default SceneRoot.Mobility = EComponentMobility::Movable;
}

struct FCk_SwayAutoTestFixture
{
    FCk_Handle_Transform Root;
    FCk_Handle_Transform Parent;
    FCk_Handle_Sway Sway;
    FCk_Handle_SceneNode Node;
    FVector Origin;

    // Root and Parent are plain (non-SceneNode) transforms, so Parent moves by world requests; Parent is a
    // lifetime child of Root and the sway node a lifetime child of Parent, so destroying Root tears all down.
    void InitParent(FCk_Handle InOwner, FVector InOrigin = FVector(0.0, 0.0, -40000.0))
    {
        Origin = InOrigin;
        Root = utils_transform::Create(InOwner, FTransform(Origin), ECk_Replication::DoesNotReplicate);
        Parent = utils_transform::Create(Root, FTransform(Origin), ECk_Replication::DoesNotReplicate);
    }

    void Init(FCk_Handle InOwner, FCk_Sway_Spec InSpec, FVector InOrigin = FVector(0.0, 0.0, -40000.0), FTransform InRest = FTransform())
    {
        InitParent(InOwner, InOrigin);
        Sway = utils_sway::Create(Parent, InRest, InSpec);
        if (ck::IsValid(Sway))
        {
            Node = Sway.As_SceneNode();
        }
    }

    void TurnParent(float32 InYawDeg)
    {
        const auto Current = ParentWorld();
        auto Rotation = Current.Rotator();
        Rotation.Yaw += InYawDeg;
        auto Request = FCk_Request_Transform_SetLocationAndRotation(Current.GetLocation(), Rotation);
        Request.Set_LocalWorld(ECk_LocalWorld::World);
        utils_transform::Request_SetLocationAndRotation(Parent, Request);
    }

    void MoveParent(FVector InWorldDelta)
    {
        const auto Current = ParentWorld();
        auto Request = FCk_Request_Transform_SetLocationAndRotation(Current.GetLocation() + InWorldDelta, Current.Rotator());
        Request.Set_LocalWorld(ECk_LocalWorld::World);
        utils_transform::Request_SetLocationAndRotation(Parent, Request);
    }

    // The node's ACTUAL composed pose. CkSway DESIGN section 6: the offset Update computes in frame N is drained by the
    // SceneNode request processor at the start of frame N+1, so this trails Get_SwayOffset by one frame.
    FTransform SwayWorld() const
    {
        return utils_transform::Get_EntityCurrentTransform(Sway.As_Transform());
    }

    FTransform ParentWorld() const
    {
        return utils_transform::Get_EntityCurrentTransform(Parent);
    }

    void Request_Destroy()
    {
        if (ck::IsValid(Root))
        {
            utils_entity_lifetime::Request_DestroyEntity(Root);
        }
    }
}
