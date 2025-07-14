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

    FInstancedStruct ToInstancedStruct() const
    {
        FInstancedStruct Result;
        Result.InitializeAs(this);

        return Result;
    }
};

class UTestEntt : UCk_EntityScript_UE
{
    UPROPERTY(Replicated)
    FTestEnttParams DummyParams;

    default _Replication = ECk_Replication::Replicates;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Print("TestEntt BeginPlay", 10.0f);
    }

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
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

	UPROPERTY(DefaultComponent)
	UCk_EntityBridge_ActorComponent_UE EntityBridge;
	default EntityBridge._ConstructionScript = UCk_Entity_ConstructionScript_WithTransform_PDA;
	default EntityBridge._Replication = ECk_Replication::Replicates;
	default EntityBridge._OnReplicationComplete_MC.AddUFunction(this, n"OnReplicationComplete");

	UFUNCTION()
	private void OnReplicationComplete(FCk_Handle InEntity)
	{
		if (System::IsServer())
		{
            auto EnttHandle = utils_entity_script::Request_SpawnEntity(InEntity, UTestEntt, FTestEnttParams().ToInstancedStruct());
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
        InInputComp.BindAction(InAction, ETriggerEvent::Started, FEnhancedInputActionHandlerDynamicSignature(this, n"Rotate"));
    }

	UFUNCTION()
	private void Rotate(FInputActionValue ActionValue, float32 ElapsedTime, float32 TriggeredTime, const UInputAction SourceAction)
	{
        auto RotationOffset = FCk_Request_Transform_AddRotationOffset();
        RotationOffset._DeltaRotation = FRotator(0, 90, 0);
        UCk_Utils_Transform_TypeUnsafe_UE::Request_AddRotationOffset(GridB.H(), RotationOffset);
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
        // auto Asset = utils_object::LoadAssetByName("/AutoSettings/InputMapping/DefaultKeySeparator.DefaultKeySeparator",
        //     ECk_Utils_Object_AssetSearchScope::All, ECk_Utils_Object_AssetSearchStrategy::ExactOnly);
        // Print(f"Asset: {Asset._Asset}", 0.0f);
        // Print(f"Asset: {Asset._AssetPath}", 0.0f);

        // auto Assets = utils_object::LoadAssetsByName("MovableCube_IsmRendererData_DA", ECk_Utils_Object_AssetSearchScope::All);

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

		auto Request = FCk_Request_Transform_SetLocation();
		Request._NewLocation = HitResult.ImpactPoint;

		auto CellsA = UCk_Utils_2dGridSystem_UE::ForEach_Cell(GridA, ECk_2dGridSystem_CellFilter::NoFilter);
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

		auto CellsB = UCk_Utils_2dGridSystem_UE::ForEach_Cell(GridB, ECk_2dGridSystem_CellFilter::NoFilter);
		for (auto Cell : CellsB)
		{
			auto WorldBounds = utils_2d_grid_cell::Get_Bounds(Cell, ECk_LocalWorld::World);
			if (UCk_Utils_2dGridCell_UE::Get_IsDisabled(Cell))
			{
				DrawBox(WorldBounds, FLinearColor::Gray);
			}
			else
			{
				DrawBox(WorldBounds, FLinearColor::Black);
			}
		}

        auto Intersection = UCk_Utils_2dGridSystem_UE::Get_Intersections(GridA, GridB);
		auto IntersectingCells = UCk_Utils_2dGridSystem_UE::Get_IntersectingCells(GridA, GridB);

		for (auto CellIntersection : IntersectingCells)
		{
			auto CellAWorldBounds = utils_2d_grid_cell::Get_Bounds(CellIntersection._CellA, ECk_LocalWorld::World);
			auto CellBWorldBounds = utils_2d_grid_cell::Get_Bounds(CellIntersection._CellB, ECk_LocalWorld::World);

			DrawBox(CellAWorldBounds, FLinearColor::Red, 10.0f);
			DrawBox(CellBWorldBounds, FLinearColor::Green, 15.0f);
		}

        if (Intersection._HasValidSnapPosition)
        {
            auto SnapPosition = FVector(Intersection._SnapPosition.X, Intersection._SnapPosition.Y, 0.0);

            System::DrawDebugSphere(SnapPosition, 50.0f);

            if (SnapPosition.Distance(HitResult.ImpactPoint) < 50.0f)
            {
                Request._NewLocation = FVector(Intersection._SnapPosition.X, Intersection._SnapPosition.Y, 0.0);
            }
        }

                UCk_Utils_Transform_TypeUnsafe_UE::Request_SetLocation(GridB.H(), Request);
	}

	UFUNCTION()
	FCk_Handle_2dGridSystem
	CreateTestGrid(
		FCk_Handle InAnyHandle,
		UCk_IsmRenderer_Data InIsmData,
		FIntPoint InDimentions,
        FTransform InTransform = FTransform::Identity)
	{
		auto Params = FCk_Fragment_2dGridSystem_ParamsData();
		{
			Params._CellSize = _CellSize;
			Params._Dimensions = InDimentions;
            Params._DefaultCellState = ECk_EnableDisable::Enable;
		}

		auto NewHandle = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner();
		UCk_Utils_Handle_UE::Set_DebugName(NewHandle, n"Grid System");

		auto NewHandleTransform = UCk_Utils_Transform_UE::Add(NewHandle, InTransform, ECk_Replication::DoesNotReplicate);
		auto Grid = UCk_Utils_2dGridSystem_UE::Add(NewHandleTransform, Params);
        UCk_Utils_2dGridSystem_UE::Request_SetPivotToAnchor(Grid, ECk_2dGridSystem_PivotAnchor::Center);

		auto AllCells = UCk_Utils_2dGridSystem_UE::ForEach_Cell(Grid, ECk_2dGridSystem_CellFilter::NoFilter);

		for (auto& Cell : AllCells)
		{
			auto IsmParams = FCk_Fragment_IsmProxy_ParamsData();
			{
				// IsmParams._IsmRenderer = Cast<UCk_IsmRenderer_Data>(UCk_Utils_Object_UE::LoadAssetByName("MovableCube_IsmRendererData_DA"));
				IsmParams._IsmRenderer = InIsmData;
			}

			auto CellAsTransform = UCk_Utils_Transform_UE::Add(Cell.H(), FTransform(), ECk_Replication::DoesNotReplicate);
			UCk_Utils_Handle_UE::Set_DebugName(CellAsTransform.H(), n"Cell");
			auto GridAsTransform = Grid.H().To_FCk_Handle_Transform();

			auto Point = UCk_Utils_2dGridCell_UE::Get_Coordinate(Cell, ECk_2dGridSystem_CoordinateType::Rotated);
			auto CellLocalPos = FVector(Point.X * Params._CellSize.X, Point.Y * Params._CellSize.Y, 0);
			auto CellWorldPos = FTransform().TransformPosition(CellLocalPos);
			auto LocalTransform = FTransform(CellLocalPos);
			auto WorldTransform = FTransform(CellWorldPos);

			auto CellProxy = UCk_Utils_SceneNode_UE::Create(GridAsTransform, LocalTransform);
			UCk_Utils_IsmProxy_UE::Add(CellProxy.H(), IsmParams);
		}

		return Grid;
	}
};