#include "CkGym_StartupSettings.h"

#define LOCTEXT_NAMESPACE "CkGymStartupSettings"

// --------------------------------------------------------------------------------------------------------------------

UCkGym_StartupSettings::UCkGym_StartupSettings() = default;

auto UCkGym_StartupSettings::GetContainerName() const -> FName
{
    return TEXT("Editor");
}

auto UCkGym_StartupSettings::GetCategoryName() const -> FName
{
    return TEXT("Ck Tests");
}

auto UCkGym_StartupSettings::GetSectionName() const -> FName
{
    return TEXT("Gym Cycler");
}

#if WITH_EDITOR
auto UCkGym_StartupSettings::GetSectionText() const -> FText
{
    return LOCTEXT("SectionText", "Gym Cycler");
}

auto UCkGym_StartupSettings::GetSectionDescription() const -> FText
{
    return LOCTEXT("SectionDescription",
        "Per-user startup preferences for the CkTests gym cycler. "
        "Choose a default gym to skip the Tab menu, or resume the last gym visited.");
}
#endif

#undef LOCTEXT_NAMESPACE
