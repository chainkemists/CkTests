class UButtonPress : UInputAction
{
    default ValueType = EInputActionValueType::Boolean;
    default bConsumeInput = false;
};

class UGridInputMappingContext : UInputMappingContext
{
};

class AGridPlayerController : ACk_PlayerController_UE
{
    UPROPERTY(Category = "Input")
    UInputAction RotateAction;
    default RotateAction = UButtonPress();

    UPROPERTY(Category = "Input")
    FEnhancedActionKeyMapping RotateKeyMap;
    default RotateKeyMap.Action = RotateAction;
    default RotateKeyMap.Key = EKeys::R;

    UPROPERTY(Category = "Input")
    UInputMappingContext Context;
    default Context = UGridInputMappingContext();
    default Context.Mappings.Add(RotateKeyMap);

    UPROPERTY(DefaultComponent)
    UEnhancedInputComponent InputComponent;

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        if (GetWorld().GetNetMode() != ENetMode::NM_Client)
        { return; }

		InputComponent = UEnhancedInputComponent::Create(this);
        PushInputComponent(InputComponent);

        UEnhancedInputLocalPlayerSubsystem EnhancedInputSubsystem = UEnhancedInputLocalPlayerSubsystem::Get(this);
        EnhancedInputSubsystem.AddMappingContext(Context, 0, FModifyContextOptions());

        // just for testing
        // InputComponent.BindAction(Action, ETriggerEvent::Triggered, FEnhancedInputActionHandlerDynamicSignature(this, n"Input_Action"));

        auto OutActors = TArray<ACk_GridSystem_GymActor>();
        GetAllActorsOfClass(ACk_GridSystem_GymActor, OutActors);

        for (auto Actor : OutActors)
        {
            Actor.BindRotation(InputComponent, RotateAction);
        }
    }

    UFUNCTION()
    void Input_Action(FInputActionValue ActionValue, float32 ElapsedTime, float32 TriggeredTime, UInputAction SourceAction)
    {
        Print(f"Input_Action[{ActionValue.ToString()}, {ElapsedTime}, {TriggeredTime}, {SourceAction.ToString()}]");
    }
};