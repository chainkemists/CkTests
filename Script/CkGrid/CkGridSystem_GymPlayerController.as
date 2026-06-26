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

    UPROPERTY(Category = "Input")
    UInputMappingContext Context;

    UPROPERTY(DefaultComponent)
    UEnhancedInputComponent InputComponent;

    UFUNCTION(BlueprintOverride)
    void ConstructionScript()
    {
        auto _CkPerfScope = ck::ScopedStat();
        RotateAction = UButtonPress();

        Context = UGridInputMappingContext();
        Context.MapKey(RotateAction, EKeys::R);
    }

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (GetWorld().GetNetMode() != ENetMode::NM_Client)
        { return; }

		InputComponent = UEnhancedInputComponent::Create(this);
        PushInputComponent(InputComponent);

        UEnhancedInputLocalPlayerSubsystem EnhancedInputSubsystem = UEnhancedInputLocalPlayerSubsystem::Get(this);
        // TODO: UE 5.7 - AddMappingContext signature changed in AngelScript bindings
        //EnhancedInputSubsystem.AddMappingContext(Context, 0);

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
        Print(f"Input_Action[{ElapsedTime}, {TriggeredTime}, {SourceAction.ToString()}]");
    }
};