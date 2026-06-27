UENUM()
enum EOffsetType
{
    PosX,
    NegX,
    PosY,
    NegY
}

struct FTestEnttParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;
};

class UTestEntt : UCk_GenericEntityScript_UE
{
    UPROPERTY(Replicated)
    FTestEnttParams DummyParams;

    default _Replication = ECk_Replication::Replicates;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        Print("TestEntt BeginPlay", 10.0f);
    }

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        Print("TestEntt BeginPlay", 10.0f);
        return ECk_EntityScript_ConstructionFlow::Finished;
    }
};

UCLASS(Blueprintable)
class ACk_GridSystem_GymActor : AActor
{
    UPROPERTY()
    FVector2D _CellSize;
    default _CellSize = FVector2D(100.0f, 100.0f);

	UPROPERTY()
	FCk_Handle_2dGridSystem GridA;

	UPROPERTY()
	FCk_Handle_2dGridSystem GridB;

	UPROPERTY(Category = "Config")
	UCk_IsmRenderer_Data _RenderData;
    default _RenderData = Cast<UCk_IsmRenderer_Data>(utils_i_o::LoadAssetByName("/CkTests/CkIsmRenderer/MovableIsm/MovableCube_IsmRendererData_DA.MovableCube_IsmRendererData_DA",
        ECk_AssetSearchScope::All, ECk_AssetSearchStrategy::ExactOnly)._Asset);

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (HasAuthority())
        {
            auto SpawnParams = FCk_EntityScript_WithActor_SpawnParams();
            SpawnParams._OwningActor = this;
            auto PendingEntity = utils_entity_script::Request_SpawnEntity(
                ck::TransientEntity(), UCk_EntityScript_WithActor_UE, SpawnParams);
            utils_pending_entity_script::Promise_OnConstructed(
                PendingEntity, FCk_Delegate_EntityScript_Constructed(this, n"OnEntityConstructed"));
        }
    }

	UFUNCTION()
	void OnEntityConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
	{
        auto InEntity = FCk_Handle(InEntityScriptHandle);

		if (System::IsServer())
		{
            auto EnttHandle = utils_entity_script::Request_SpawnEntity(InEntity, UTestEntt, FTestEnttParams());
            utils_pending_entity_script::Promise_OnConstructed(EnttHandle, FCk_Delegate_EntityScript_Constructed(this, n"OnEnttConstructed"));

			return;
		}

		GridA = CreateTestGrid(InEntity, _RenderData, FIntPoint(10, 10), FTransform(FVector(1000, 1000, 0)));
		GridB = CreateTestGrid(InEntity, _RenderData, FIntPoint(4, 2), FTransform(FRotator(0, 0, 0)));
	}

    UFUNCTION()
    private void OnEnttConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        Print("OnEnttConstructed", 10.0f);
    }

    void BindRotation(UEnhancedInputComponent InInputComp, UInputAction InAction)
    {
        InInputComp.BindAction(n"Rotate", EInputEvent::IE_Pressed, FInputActionHandlerDynamicSignature(this, n"Rotate"));
    }

	UFUNCTION()
	private void Rotate(FKey Key)
	{
        auto RotationOffset = FCk_Request_Transform_AddRotationOffset(FRotator(0, 90, 0));
        GridB.H().Request_AddRotationOffset(RotationOffset);
	}

	UFUNCTION(Server)
	void
	UpdateTransform(
		FTransform InTransform)
	{
		SetActorTransform(InTransform);
	}

	void
	DrawBox(
		FBox2D InBox,
		FLinearColor InColor,
        float InZPos = 5.0)
	{
		auto Center = (InBox.Min + InBox.Max) * 0.5;
		auto Extent = (InBox.Max - InBox.Min) * 0.5;
		System::DrawDebugBox(FVector(Center.X, Center.Y, 5.0), FVector(Extent.X, Extent.Y, InZPos), InColor, FRotator(), 0.0, 5.0);
	}

	UFUNCTION(BlueprintOverride)
	void
	Tick(
		float DeltaSeconds)
	{
		auto PlayerController = Gameplay::GetPlayerController(0);
		auto PlayerPawn = Gameplay::GetPlayerPawn(0);

		if (!IsValid(PlayerPawn))
		{
			return;
		}

		if (System::IsServer())
		{
			return;
		}

		auto HitResult = FHitResult();
		if (!System::LineTraceSingle(PlayerPawn.GetActorLocation(),
            PlayerPawn.GetActorLocation() + PlayerController.GetActorForwardVector() * 5000.0f,
            ETraceTypeQuery::Visibility,
            false,
            TArray<AActor>(),
            EDrawDebugTrace::ForOneFrame,
            HitResult,
            true))
		{
			return;
		}

		auto Request = FCk_Request_Transform_SetLocation(HitResult.ImpactPoint);

		auto CellsA = utils_2d_grid_system::ForEach_Cell(GridA, ECk_2dGridSystem_CellFilter::NoFilter);
		for (auto Cell : CellsA)
		{
			auto WorldBounds = utils_2d_grid_cell::Get_Bounds(Cell, ECk_LocalWorld::World);
			if (utils_2d_grid_cell::Get_IsDisabled(Cell))
			{
				DrawBox(WorldBounds, FLinearColor::Gray);
			}
			else
			{
				DrawBox(WorldBounds, FLinearColor::Purple);
			}
		}

		auto CellsB = utils_2d_grid_system::ForEach_Cell(GridB, ECk_2dGridSystem_CellFilter::NoFilter);
		for (auto Cell : CellsB)
		{
			auto WorldBounds = utils_2d_grid_cell::Get_Bounds(Cell, ECk_LocalWorld::World);
			if (utils_2d_grid_cell::Get_IsDisabled(Cell))
			{
				DrawBox(WorldBounds, FLinearColor::Gray);
			}
			else
			{
				DrawBox(WorldBounds, FLinearColor::Black);
			}
		}

        auto Intersection = utils_2d_grid_system::Get_Intersections(GridA, GridB);
		auto IntersectingCells = utils_2d_grid_system::Get_IntersectingCells(GridA, GridB);

		for (auto CellIntersection : IntersectingCells)
		{
			auto CellAWorldBounds = utils_2d_grid_cell::Get_Bounds(CellIntersection.Get_CellA(), ECk_LocalWorld::World);
			auto CellBWorldBounds = utils_2d_grid_cell::Get_Bounds(CellIntersection.Get_CellB(), ECk_LocalWorld::World);

			DrawBox(CellAWorldBounds, FLinearColor::Red, 10.0f);
			DrawBox(CellBWorldBounds, FLinearColor::Green, 15.0f);
		}

        if (Intersection.Get_HasValidSnapPosition())
        {
            auto SnapPosition = FVector(Intersection.Get_SnapPosition().X, Intersection.Get_SnapPosition().Y, 0.0);

            System::DrawDebugSphere(SnapPosition, 50.0f);

            if (SnapPosition.Distance(HitResult.ImpactPoint) < 50.0f)
            {
                Request = FCk_Request_Transform_SetLocation(FVector(Intersection.Get_SnapPosition().X, Intersection.Get_SnapPosition().Y, 0.0));
            }
        }

        FCk_Handle H;
        GridB.H().Request_SetLocation(Request);
	}

	UFUNCTION()
	FCk_Handle_2dGridSystem
	CreateTestGrid(
		FCk_Handle InAnyHandle,
		UCk_IsmRenderer_Data InIsmData,
		FIntPoint InDimentions,
        FTransform InTransform = FTransform::Identity)
	{
		auto Params = FCk_Fragment_2dGridSystem_ParamsData(InDimentions, _CellSize);
		Params.Set_DefaultCellState(ECk_EnableDisable::Enable);

		auto NewHandle = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner();
        NewHandle.Set_DebugName(n"Grid System");

        FCk_Handle_Probe P;

		auto NewHandleTransform = utils_transform::Add(NewHandle, InTransform, ECk_Replication::DoesNotReplicate);
		auto Grid = utils_2d_grid_system::Add(NewHandleTransform, Params);
        utils_2d_grid_system::Request_SetPivotToAnchor(Grid, ECk_2dGridSystem_PivotAnchor::Center);

		auto AllCells = utils_2d_grid_system::ForEach_Cell(Grid, ECk_2dGridSystem_CellFilter::NoFilter);

		for (auto& Cell : AllCells)
		{
			auto IsmParams = FCk_Fragment_IsmProxy_ParamsData();
			{
				IsmParams._IsmRenderer = InIsmData;
			}

			auto CellAsTransform = utils_transform::Add(Cell.H(), FTransform(), ECk_Replication::DoesNotReplicate);
            CellAsTransform.H().Set_DebugName(n"Cell");
			auto GridAsTransform = Grid.As_Transform();

			auto Point = utils_2d_grid_cell::Get_Coordinate(Cell, ECk_2dGridSystem_CoordinateType::Rotated);
			auto CellLocalPos = FVector(Point.X * Params.Get_CellSize().X, Point.Y * Params.Get_CellSize().Y, 0);
			auto CellWorldPos = FTransform().TransformPosition(CellLocalPos);
			auto LocalTransform = FTransform(CellLocalPos);
			auto WorldTransform = FTransform(CellWorldPos);

			auto CellProxy = UCk_Utils_SceneNode_UE::Create(GridAsTransform, LocalTransform).As_Transform();
			UCk_Utils_IsmProxy_UE::Add(CellProxy, IsmParams);
		}

		return Grid;
	}
};