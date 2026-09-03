#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkJoltEditor/Cook/CkJoltCook_MapSelection.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_jolt_cook_map_selection
{
    using namespace ck::jolt::cook;

    static auto Make_Input() -> FCk_Jolt_PackagingMapSelectionInput
    {
        auto Input = FCk_Jolt_PackagingMapSelectionInput{};
        Input._bPackagingMaps = true;
        Input._AuthoredMapsToCook = {TEXT("/Game/Maps/Main"), TEXT("/Game/Maps/Menu")};
        Input._DirectoriesToNeverCook = {TEXT("/Game/Maps/AutoTests/")};
        Input._JoltExcludedMapPathPrefixes = {TEXT("/Game/Maps/Gyms")};
        Input._CookedDataRootPath = TEXT("/Game/CkJoltData");
        return Input;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltCook_PackagingMapSelection,
    "Ck.Jolt.Cook.PackagingMapSelection",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkTest_JoltCook_PackagingMapSelection::RunTest(const FString& Parameters)
{
    using namespace ck::jolt::cook;
    using namespace ck_test_jolt_cook_map_selection;

    // Explicit maps retain their authored order and do not need to live under an always-cook directory.
    {
        auto Input = Make_Input();
        Input._AuthoredMapsToCook.Add(TEXT("/Game/Maps/Main"));
        const auto Result = Select_PackagingMaps(Input);
        TestTrue(TEXT("authored maps accepted"), Result._Failure.IsEmpty());
        TestEqual(TEXT("duplicates removed"), Result._MapPackageNames.Num(), 2);
        if (Result._MapPackageNames.Num() == 2)
        {
            TestEqual(TEXT("first authored map stays first"), Result._MapPackageNames[0], FString{TEXT("/Game/Maps/Main")});
            TestEqual(TEXT("second authored map stays second"), Result._MapPackageNames[1], FString{TEXT("/Game/Maps/Menu")});
        }
    }

    // A valid prefix must never leak a partial cook plan when a later entry is rejected.
    const auto RejectedMaps = TArray<FString>{
        TEXT(""), TEXT("Main"), TEXT("/Game/Maps/Main.Main"), TEXT("/Game/Maps/Main.umap")};
    for (const auto& RejectedMap : RejectedMaps)
    {
        auto Input = Make_Input();
        Input._AuthoredMapsToCook.Add(RejectedMap);
        const auto Result = Select_PackagingMaps(Input);
        TestFalse(*FString::Printf(TEXT("reject [%s] with explanation"), *RejectedMap), Result._Failure.IsEmpty());
        TestEqual(*FString::Printf(TEXT("reject [%s] without partial plan"), *RejectedMap), Result._MapPackageNames.Num(), 0);
    }

    {
        auto Input = Make_Input();
        Input._AuthoredMapsToCook.Reset();
        const auto Result = Select_PackagingMaps(Input);
        TestTrue(TEXT("no configured maps yields an empty selection"), Result._MapPackageNames.IsEmpty());
    }

    {
        auto Input = Make_Input();
        Input._bCookAll = true;
        const auto Result = Select_PackagingMaps(Input);
        TestFalse(TEXT("CookAll cannot pretend an entry-map list covers every world"), Result._Failure.IsEmpty());
        TestTrue(TEXT("CookAll rejection has no plan"), Result._MapPackageNames.IsEmpty());
    }

    for (const auto AlsoSingleMap : {false, true})
    {
        auto Input = Make_Input();
        Input._bMap = AlsoSingleMap;
        Input._bAllMaps = NOT AlsoSingleMap;
        const auto Result = Select_PackagingMaps(Input);
        TestFalse(TEXT("conflicting map selection fails"), Result._Failure.IsEmpty());
        TestTrue(TEXT("conflicting selection has no plan"), Result._MapPackageNames.IsEmpty());
    }

    {
        auto Input = Make_Input();
        Input._AuthoredMapsToCook = {TEXT("/Game/Maps/AutoTestsExtra/Main"), TEXT("/Game/Maps/GymsExtra/Main")};
        const auto Result = Select_PackagingMaps(Input);
        TestTrue(TEXT("directory exclusion respects path component boundaries"), Result._Failure.IsEmpty());
        TestEqual(TEXT("similarly named directories remain eligible"), Result._MapPackageNames.Num(), 2);
    }

    // Directory discovery is a second source, not a restriction on explicit MapsToCook. Its order
    // must not depend on asset-registry enumeration; overlaps must not cook the same map twice.
    {
        auto Input = Make_Input();
        Input._DirectoriesToAlwaysCook = {TEXT("/Game/Always/"), TEXT("/Game/Always/Nested"), TEXT("/Game/Maps")};
        Input._DiscoveredAlwaysCookMapCandidates = {
            TEXT("/Game/Always/ZWorld"), TEXT("/Game/Maps/Main"), TEXT("/Game/Always/Nested/AWorld"),
            TEXT("/Game/Always/Nested/AWorld"), TEXT("/Game/Marketplace/Demo"), TEXT("/Game/AlwaysExtra/NotSelected")};
        const auto Result = Select_PackagingMaps(Input);
        TestTrue(TEXT("union accepted"), Result._Success);
        const auto Expected = TArray<FString>{TEXT("/Game/Maps/Main"), TEXT("/Game/Maps/Menu"),
            TEXT("/Game/Always/Nested/AWorld"), TEXT("/Game/Always/ZWorld")};
        TestTrue(TEXT("explicit maps plus sorted directory maps, once each, without unrelated candidates"),
            Result._MapPackageNames == Expected);
    }

    {
        auto Input = Make_Input();
        Input._AuthoredMapsToCook.Reset();
        Input._DirectoriesToAlwaysCook = {TEXT("Always/")};
        Input._DiscoveredAlwaysCookMapCandidates = {TEXT("/Game/Always/Nested/World")};
        const auto Result = Select_PackagingMaps(Input);
        TestTrue(TEXT("directories alone are sufficient"), Result._Success);
        TestTrue(TEXT("relative always-cook directory resolves under Game"),
            Result._MapPackageNames == Input._DiscoveredAlwaysCookMapCandidates);
    }

    // NeverCook takes precedence over either inclusion source. The output root is never an input.
    {
        auto Input = Make_Input();
        Input._AuthoredMapsToCook.Add(TEXT("/Game/Maps/AutoTests/ExplicitTest"));
        Input._DirectoriesToAlwaysCook = {TEXT("/Game")};
        Input._DirectoriesToNeverCook.Add(TEXT("RelativeNever/"));
        Input._DiscoveredAlwaysCookMapCandidates = {TEXT("/Game/Maps/AutoTests/DirectoryTest"),
            TEXT("/Game/Maps/Gyms/World"), TEXT("/Game/CkJoltData/World"), TEXT("/Game/RelativeNever/World")};
        const auto Result = Select_PackagingMaps(Input);
        TestTrue(TEXT("exclusions filter rather than reject the complete cook plan"), Result._Success);
        TestTrue(TEXT("all exclusion sources apply to explicit and discovered maps"),
            Result._MapPackageNames == TArray<FString>{TEXT("/Game/Maps/Main"), TEXT("/Game/Maps/Menu")});
    }

    {
        auto Input = Make_Input();
        Input._AuthoredMapsToCook.Reset();
        Input._DiscoveredAlwaysCookMapCandidates = {TEXT("/Game/Marketplace/Demo")};
        const auto Result = Select_PackagingMaps(Input);
        TestTrue(TEXT("empty directory filter never means all candidate maps"), Result._MapPackageNames.IsEmpty());
    }

    {
        auto Input = Make_Input();
        Input._AuthoredMapsToCook = {TEXT("/Engine/Maps/Entry")};
        Input._DirectoriesToAlwaysCook = {TEXT("/CkFoundation/Maps")};
        Input._DiscoveredAlwaysCookMapCandidates = {TEXT("/CkFoundation/Maps/PluginWorld")};
        const auto Result = Select_PackagingMaps(Input);
        TestTrue(TEXT("mounted engine and plugin content may be packaged"), Result._Success);
        TestEqual(TEXT("selection supports both engine and plugin roots"), Result._MapPackageNames.Num(), 2);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
