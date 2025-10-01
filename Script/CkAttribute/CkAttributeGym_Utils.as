//============================================================================
// ATTRIBUTE GYM UTILITIES (For attribute testing specifically)
//============================================================================

namespace CkGym_Attribute
{
    // Create attribute progress bar with value and max
    FString Create_ProgressBar(float32 InValue, float32 InMaxValue, int32 InBarWidth = 20, ECk_ASCII_ProgressBar_Style InStyle = ECk_ASCII_ProgressBar_Style::Equal_Symbol)
    {
        auto Percentage = FCk_FloatRange_0to1(InValue / InMaxValue);
        return utils_debug_draw::Create_ASCII_ProgressBar(
            Percentage,
            InBarWidth,
            ECk_ForwardReverse::Forward,
            InStyle
        );
    }

    // Create clamping status string
    FString Get_ClampingStatus(float32 InCurrentValue, float32 InInputValue)
    {
        if (InCurrentValue != InInputValue)
        {
            return " [CLAMPED]";
        }
        return " [NORMAL]";
    }

    // Draw clamping event indicator
    void Draw_ClampIndicator(FCk_Handle InEntity, FVector InOffset, FLinearColor InColor)
    {
        CkGym_Common::Draw_DebugSphere(InEntity, InOffset, InColor, 25.0f, 2.0f, 3.0f);
    }
}