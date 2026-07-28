#include "CkPathNetwork/Detector/CkPathNetwork_Detector.h"

#include <Misc/AutomationTest.h>

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Detector_GeneratedOutputSourceFence,
    "Ck.PathNetwork.Detector.GeneratedOutputSourceFence",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_PathNetwork_Detector_GeneratedOutputSourceFence::
    RunTest(
        const FString& Parameters)
{
    auto Points = TArray<FCk_PathNetwork_RibbonPoint>{
        FCk_PathNetwork_RibbonPoint{FVector::ZeroVector, 50.0f},
        FCk_PathNetwork_RibbonPoint{FVector{100.0, 0.0, 0.0}, 50.0f}};

    auto Generated = FCk_PathNetwork_Ribbon{Points};
    Generated.Set_Source(ECk_PathNetwork_RibbonSource::Generated);
    TestTrue(
        TEXT("Generated-only detector output is accepted"),
        ck::pathnetwork::Get_AreAllRibbonSourcesGenerated(
            TArray<FCk_PathNetwork_Ribbon>{Generated}));

    auto Authored = FCk_PathNetwork_Ribbon{Points};
    Authored.Set_Source(ECk_PathNetwork_RibbonSource::Authored);
    TestFalse(
        TEXT("An authored ribbon cannot enter through generated detector output"),
        ck::pathnetwork::Get_AreAllRibbonSourcesGenerated(
            TArray<FCk_PathNetwork_Ribbon>{Generated, Authored}));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
