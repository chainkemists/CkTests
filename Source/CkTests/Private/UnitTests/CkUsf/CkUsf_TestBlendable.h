#pragma once

// Reaching a Stylize subsystem's live blendable MID from a test.
//
// The subsystems keep their MID private and the object on the view actor's post-process component IS that
// MID, so going in through the component tests the path the renderer actually reads instead of a test-only
// accessor. It is matched by PARENT MASTER rather than by "the first MID in the world": a world exercising
// more than one effect carries one view actor per effect, and picking the first would silently read the
// wrong look's parameters.

#include "CoreMinimal.h"

#include "Components/PostProcessComponent.h"
#include "Engine/World.h"
#include "EngineUtils.h"
#include "GameFramework/Actor.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Materials/MaterialInterface.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_usf
{
    inline auto Get_LiveBlendableMidForMaster(
        UWorld* InWorld,
        const UMaterialInterface* InMaster) -> UMaterialInstanceDynamic*
    {
        if (InWorld == nullptr || InMaster == nullptr)
        { return nullptr; }

        for (TActorIterator<AActor> It{InWorld}; It; ++It)
        {
            const auto* ViewPP = It->FindComponentByClass<UPostProcessComponent>();
            if (ViewPP == nullptr)
            { continue; }

            for (const auto& Blendable : ViewPP->Settings.WeightedBlendables.Array)
            {
                auto* Mid = Cast<UMaterialInstanceDynamic>(Blendable.Object);
                if (Mid != nullptr && Mid->Parent == InMaster)
                { return Mid; }
            }
        }

        return nullptr;
    }
}

// --------------------------------------------------------------------------------------------------------------------
