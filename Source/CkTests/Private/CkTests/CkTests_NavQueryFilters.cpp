#include "CkNavigation/NavSurface/CkNavFilterDefinition_DataAsset.h"
#include "CkNavigation/NavSurface/CkNavFilterDefinition_Registry.h"
#include "CkNavigation/NavSurface/CkNavSurface_GameplayTags.h"

#include <NativeGameplayTags.h>

// --------------------------------------------------------------------------------------------------------------------

// An agent filter owned by the test suite, for AutoTests that need a host filter with an exclusion of
// its own. CkFoundation registers no filter that excludes an area a test can paint, and a project's
// filters (Nav.Filter.Customer belongs to the game) are not portable fixtures. It excludes
// Nav.Area.Restricted, the framework's paintable cost area.
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_Nav_Filter_ExcludeRestricted, "Nav.Filter.CkTests.ExcludeRestricted");

// --------------------------------------------------------------------------------------------------------------------

namespace ck_tests_nav_query_filters
{
    const auto FilterRegistration = ck::nav_surface::FFilterRegistrar{[]
    {
        auto Definition = FCk_NavFilter_Definition{};
        Definition.Set_ExcludedAreaTags(FGameplayTagContainer{TAG_Nav_Area_Restricted.GetTag()});
        ck::nav_surface::Register_FilterDefinition(TAG_CkTests_Nav_Filter_ExcludeRestricted, Definition);
    }};
}

// --------------------------------------------------------------------------------------------------------------------
