#include "CkAutoTestMapConfig.h"

// --------------------------------------------------------------------------------------------------------------------

auto
    UCkAutoTestMapConfig::
    Get_DisplayName() const
    -> FString
{
    if (TargetMap.IsNull())
    { return FString::Printf(TEXT("%s [no target map]"), *GetName()); }

    return FString::Printf(TEXT("%s -> %s"), *GetName(), *TargetMap.GetAssetName());
}

// --------------------------------------------------------------------------------------------------------------------
