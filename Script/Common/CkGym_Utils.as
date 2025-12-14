//--------------------------------------------------------------------------------------------------------------------------

struct FCkGym_Station_SpawnParams_Payload
{
    UPROPERTY()
    FTransform Transform = FTransform::Identity;

    UPROPERTY()
    TArray<FName> Tags;

    // Dimensions
    UPROPERTY()
    float Width = 6.0f;

    UPROPERTY()
    float Depth = 5.0f;

    UPROPERTY()
    float Height = 5.0f;

    // Text Content
    UPROPERTY()
    FText Title = FText::FromString("Title");

    UPROPERTY()
    TArray<FText> Description;

    // Text Styling
    UPROPERTY()
    float TitleScale = 20.0f;

    UPROPERTY()
    float DescriptionScale = 12.0f;

    UPROPERTY()
    FLinearColor TitleColour = FLinearColor::White;

    UPROPERTY()
    FLinearColor DescriptionColour = FLinearColor::White;

    // Layout Options
    UPROPERTY()
    bool SeperateTitlePanel = false;

    UPROPERTY()
    bool FloorText = false;

    UPROPERTY()
    int32 NumberOfLinesBetweenParagraphs = 1;

    UPROPERTY()
    int32 NumberOfSpacesBetweenLines = 0;

    UPROPERTY()
    float TextPadding = 1.0f;

    // Positioning
    UPROPERTY()
    FVector CenterOffset = FVector(250.0f, 0.0f, 200.0f);
};

//--------------------------------------------------------------------------------------------------------------------------

struct FCkGym_Station_TitleAndDescription
{
    UPROPERTY()
    FText Title;

    UPROPERTY()
    FText Description;

    UPROPERTY()
    FText Instructions;
};

//--------------------------------------------------------------------------------------------------------------------------

USTRUCT()
struct FCk_Gym_TransformSpawnParams
{
	UPROPERTY()
	FTransform InitialTransform = FTransform::Identity;

	FCk_Gym_TransformSpawnParams(FTransform InTransform)
	{
		InitialTransform = InTransform;
	}
}

//============================================================================
// COMMON GYM UTILITIES (For all gym types)
//============================================================================

namespace CkGym_Common
{
    void
    Request_SpawnNewStation(
        FCkGym_Station_SpawnParams_Payload InPayload)
    {
        auto Entity = Subsystem::GetWorldSubsystem(UCk_EcsWorld_Subsystem_UE).Get_TransientEntity();
        utils_messaging::Broadcast(Entity, InPayload);
    }


    // Network role detection for display positioning
    FString Get_NetworkRoleTitle(FCk_Handle InEntity)
    {
        auto NetMode = utils_net::Get_EntityNetMode(InEntity);

        if (NetMode == ECk_Net_NetModeType::ClientAndHost)
        {
            return "CLIENT+HOST";
        }
        else if (NetMode == ECk_Net_NetModeType::Host)
        {
            return "HOST";
        }
        else if (NetMode == ECk_Net_NetModeType::Client)
        {
            return "CLIENT";
        }

        return "UNKNOWN";
    }

    // Get horizontal offset based on network role for multi-client display
    FVector Get_NetworkRoleOffset(FCk_Handle InEntity)
    {
        auto NetMode = utils_net::Get_EntityNetMode(InEntity);

        if (NetMode == ECk_Net_NetModeType::Host)
        {
            return FVector(-200.0f, 0.0f, 0.0f); // Host to the left
        }
        else if (NetMode == ECk_Net_NetModeType::Client)
        {
            return FVector(200.0f, 0.0f, 0.0f);  // Client to the right
        }

        return FVector(0.0f, 0.0f, 0.0f); // ClientAndHost stays centered
    }

    // Update station display text using dynamic fragments
    void Update_StationDisplay(FCk_Handle InEntity, FString InTitle, FString InDescription, FString InInstructions)
    {
        auto Owner = utils_entity_lifetime::Get_LifetimeOwner(InEntity);
        if (ck::Is_NOT_Valid(Owner))
        {
            return;
        }

        auto& Fragment = utils_dynamic_fragment::AddOrGet_Fragment(Owner, FCkGym_Station_TitleAndDescription);
        Fragment.Title = FText::FromString(InTitle);
        Fragment.Description = FText::FromString(InDescription);
        Fragment.Instructions = FText::FromString(InInstructions);
    }

    // Draw debug sphere at entity location with offset
    void Draw_DebugSphere(FCk_Handle InEntity, FVector InOffset, FLinearColor InColor, float32 InRadius = 25.0f, float32 InDuration = 2.0f, float32 InThickness = 3.0f)
    {
        auto TransformHandle = InEntity.To_FCk_Handle_Transform();
        if (ck::Is_NOT_Valid(TransformHandle))
        {
            return;
        }

        auto Transform = utils_transform::Get_EntityCurrentTransform(TransformHandle);
        auto SpherePos = Transform.GetLocation() + InOffset;
        utils_debug_draw::DrawDebugSphere(SpherePos, InRadius, 8, InColor, InDuration, InThickness);
    }
}