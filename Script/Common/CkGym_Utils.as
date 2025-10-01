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