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

    // When true, the spawned GymStation auto-sizes Width/Height from the
    // title + description text content (and grows at runtime if Update_StationDisplay
    // pushes more text). Width/Height fields above are ignored when AutoSize=true.
    UPROPERTY()
    bool AutoSize = false;

    // Diagnostic overlays — translucent wireframe PMG boxes drawn at each
    // piece's expected world transform. Useful for spotting misaligned pieces.
    UPROPERTY()
    bool ShowDebugOverlays = false;

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
// COLOURED PANEL BODY
//
// A UTextRenderComponent carries ONE colour for the whole component, so a panel
// that wants per-line colour has to be rendered as one component per RUN of
// consecutive same-coloured lines. That constraint is the entire reason this
// fragment exists next to FCkGym_Station_TitleAndDescription rather than
// replacing it: a station that writes the plain fragment keeps rendering through
// the single description component exactly as it always did.
//
// Active is the in-use flag. Mere fragment presence cannot be one — the station
// AddOrGet's it every tick — and a station that legitimately renders zero body
// lines would otherwise be indistinguishable from one that never opted in.
//--------------------------------------------------------------------------------------------------------------------------

USTRUCT()
struct FCkGym_ColoredLine
{
    UPROPERTY()
    FString Text;

    UPROPERTY()
    FColor Colour = FColor(255, 255, 255, 255);

    FCkGym_ColoredLine(FString InText = "", FColor InColour = FColor(255, 255, 255, 255))
    {
        Text = InText;
        Colour = InColour;
    }
}

//--------------------------------------------------------------------------------------------------------------------------

USTRUCT()
struct FCkGym_Station_ColoredBody
{
    UPROPERTY()
    FText Title;

    UPROPERTY()
    TArray<FCkGym_ColoredLine> Lines;

    UPROPERTY()
    FText Instructions;

    UPROPERTY()
    bool Active = false;
}

//--------------------------------------------------------------------------------------------------------------------------
// Shared meaning for every coloured gym panel, so "green" means the same thing
// on every station a viewer walks past.
//--------------------------------------------------------------------------------------------------------------------------

namespace gym_palette
{
    // Neutral body text.
    const FColor White = FColor(255, 255, 255, 255);

    // A check that matched.
    const FColor Green = FColor(80, 220, 120, 255);

    // A check that did not match.
    const FColor Red = FColor(235, 80, 80, 255);

    // Live value differs from its authored default.
    const FColor Amber = FColor(240, 190, 60, 255);

    // The step running right now, and anything the viewer is asked to do.
    const FColor Cyan = FColor(90, 200, 235, 255);

    // Idle / not currently running.
    const FColor Grey = FColor(140, 140, 140, 255);
}

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
    // Spawns a UCk_EntityScript_GymStation entity for the given payload.
    // The entity is tagged with all of InPayload.Tags so the base PC's
    // Get_StationHandle / Get_StationTransform can look it up later.
    //
    // Returns the pending handle so the caller can await OnConstructed —
    // the base PC uses this to count outstanding stations and only call
    // Request_StartGym once they're all up.
    FCk_Handle_PendingEntityScript
    Request_SpawnNewStation(
        FCkGym_Station_SpawnParams_Payload InPayload)
    {
        auto Params = FCk_GymStation_SpawnParams();
        Params.InitialTransform     = InPayload.Transform;
        Params.Width                = double(InPayload.Width);
        Params.Depth                = double(InPayload.Depth);
        Params.Height               = double(InPayload.Height);
        Params.TitleText            = InPayload.Title;
        Params.DescriptionText      = InPayload.Description;
        Params.TitleScale           = double(InPayload.TitleScale);
        Params.DescriptionScale     = double(InPayload.DescriptionScale);
        Params.TitleColour          = InPayload.TitleColour.ToFColor(true);
        Params.DescriptionColour    = InPayload.DescriptionColour.ToFColor(true);
        Params.AutoSize             = InPayload.AutoSize;
        Params.ShowDebugOverlays    = InPayload.ShowDebugOverlays;
        Params.StationTags          = InPayload.Tags;

        return utils_entity_script::Request_SpawnEntity(
            ck::TransientEntity(),
            UCk_EntityScript_GymStation,
            FInstancedStruct::Make(Params));
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

        auto& Fragment = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        Fragment.Title = FText::FromString(InTitle);
        Fragment.Description = FText::FromString(InDescription);
        Fragment.Instructions = FText::FromString(InInstructions);
    }

    // Update station display text with one colour per body line. Same title and
    // instruction channels as Update_StationDisplay above; only the body differs,
    // and it renders through its own components — a station picks one path or the
    // other and the plain path is unchanged for every station that keeps it.
    void Update_StationDisplay_Colored(FCk_Handle InEntity, FString InTitle, const TArray<FCkGym_ColoredLine>&in InBodyLines, FString InInstructions)
    {
        auto Owner = utils_entity_lifetime::Get_LifetimeOwner(InEntity);
        if (ck::Is_NOT_Valid(Owner))
        {
            return;
        }

        auto& Fragment = Owner.AddOrGet_Fragment(FCkGym_Station_ColoredBody);
        Fragment.Title = FText::FromString(InTitle);
        Fragment.Lines = InBodyLines;
        Fragment.Instructions = FText::FromString(InInstructions);
        Fragment.Active = true;
    }

    // Draw debug sphere at entity location with offset
    void Draw_DebugSphere(FCk_Handle InEntity, FVector InOffset, FLinearColor InColor, float32 InRadius = 25.0f, float32 InDuration = 2.0f, float32 InThickness = 3.0f)
    {
        auto TransformHandle = InEntity.As_Transform();
        if (ck::Is_NOT_Valid(TransformHandle))
        {
            return;
        }

        auto Transform = utils_transform::Get_EntityCurrentTransform(TransformHandle);
        auto SpherePos = Transform.GetLocation() + InOffset;
        utils_debug_draw::DrawDebugSphere(SpherePos, InRadius, 8, InColor, InDuration, InThickness);
    }
}