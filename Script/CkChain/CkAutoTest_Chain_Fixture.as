// Language=angelscript
struct FCk_ChainAutoTestFixture
{
    FCk_Handle Owner;
    FCk_Handle_Transform Head;
    FCk_Handle_Chain Chain;
    TArray<FCk_Handle_Transform> Links;
    FCk_Handle_Tween Tween;

    void Init(FCk_Handle InOwner, ECk_Chain_Solver InSolver = ECk_Chain_Solver::PathHistory,
        ECk_Chain_HistorySeed InSeed = ECk_Chain_HistorySeed::StraightBehindHead, float32 InTeleportCm = 0.0f,
        float32 InSpacingCm = 10.0f)
    {
        Owner = InOwner;
        Head = Spawn(FVector::ZeroVector);
        auto Params = FCk_Chain_Spec(InSolver);
        Params.Set_HistorySeed(InSeed);
        Params.Set_TeleportDistanceCm(InTeleportCm);
        Params.Set_SampleSpacingCm(InSpacingCm);
        Chain = utils_chain::Add(Head, Params);
    }

    FCk_Handle_Transform Spawn(FVector InLocation)
    {
        auto LocalOwner = Owner;
        auto Entity = utils_entity_lifetime::Request_CreateEntity(LocalOwner);
        return utils_transform::Add(Entity, FTransform(FRotator::ZeroRotator, InLocation, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
    }

    void Attach(float32 InDistance, FVector InLocation = FVector(0.0, 500.0, 0.0))
    {
        auto Link = Spawn(InLocation);
        Links.Add(Link);
        utils_chain::Request_AttachLink(Chain,
            FCk_Request_Chain_AttachLink(Link, FCk_ChainLink_Spec(InDistance)),
            FCk_Delegate_Request_OnCompleted());
    }

    bool Ready(int32 InCount) const
    {
        if (ck::Is_NOT_Valid(Chain) || utils_chain::Get_NumLinks(Chain) != InCount)
        {
            return false;
        }
        for (auto Link : Links)
        {
            if (ck::Is_NOT_Valid(Link) || !utils_chain_link::Has(Link))
            {
                return false;
            }
        }
        return true;
    }

    FVector Location(int32 InIndex) const
    {
        return utils_transform::Get_EntityCurrentLocation(Links[InIndex]);
    }

    void Move(FVector InTarget)
    {
        utils_transform::Request_SetLocation(Head, FCk_Request_Transform_SetLocation(InTarget));
    }

    void StartTween(FVector InTarget, float32 InSeconds = 0.5f)
    {
        Tween = utils_tween::Create_TweenEntityLocation(Head, InTarget, InSeconds,
            ECk_TweenEasing::Linear, ECk_TweenLoopType::None, 0, 0.0f,
            ECk_TweenCompletionBehavior::DoNothing);
    }
}
