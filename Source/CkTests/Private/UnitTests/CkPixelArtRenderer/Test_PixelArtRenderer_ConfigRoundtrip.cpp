// C++ unit test for the pixel-art renderer's per-world config registry (CkPixelArtRenderer).
//
// The registry is the ONLY channel between the game-side configuration and the scene view extension's game-thread
// hooks, so "what was set is what is read back" and "a world nobody configured reads as unset" are the two
// properties every later phase depends on — an unset read must stay unset rather than resolving to a default,
// because a silently-defaulted world would render pixelated when nothing asked it to.
//
// Surface in Session Frontend: CkTests.UnitTests.CkPixelArtRenderer.ConfigRegistry.<scenario>

#include "Misc/AutomationTest.h"

#include "Engine/World.h"
#include "Misc/ScopeExit.h"

#include "CkPixelArtRenderer/CkPixelArtRenderer_State.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_pixel_art_config_roundtrip
{
    auto Make_Config(
        int32 InInternalHeight,
        int32 InMarginTexels)
        -> FCk_PixelArt_RenderConfig
    {
        auto Config = FCk_PixelArt_RenderConfig{};
        Config.Enabled = true;
        Config.InternalHeight = InInternalHeight;
        Config.MarginTexels = InMarginTexels;
        Config.SnapEnabled = false;
        Config.FilterMode = ECk_PixelArt_UpscaleFilter::Nearest;

        return Config;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_PixelArtRenderer_ConfigRoundtrip,
    "CkTests.UnitTests.CkPixelArtRenderer.ConfigRegistry.Roundtrip",
    kCkUnitTestFlags)

bool FCkTest_PixelArtRenderer_ConfigRoundtrip::RunTest(const FString& Parameters)
{
    constexpr auto InformEngineOfWorld = false;

    auto* World = UWorld::CreateWorld(EWorldType::Game, InformEngineOfWorld);
    TestNotNull(TEXT("test world was created"), World);

    if (World == nullptr)
    { return false; }

    ON_SCOPE_EXIT
    {
        FCk_PixelArtRenderer_StateRegistry::Clear(World);
        World->DestroyWorld(InformEngineOfWorld);
    };

    TestFalse(TEXT("an unconfigured world reads as unset"),
        FCk_PixelArtRenderer_StateRegistry::TryGet(World).IsSet());

    const auto Written = ck_test_pixel_art_config_roundtrip::Make_Config(180, 3);
    FCk_PixelArtRenderer_StateRegistry::Set(World, Written);

    const auto ReadBack = FCk_PixelArtRenderer_StateRegistry::TryGet(World);
    TestTrue(TEXT("a configured world reads as set"), ReadBack.IsSet());

    if (ReadBack.IsSet())
    {
        TestTrue (TEXT("Enabled roundtrips"),        ReadBack->Enabled);
        TestEqual(TEXT("InternalHeight roundtrips"), ReadBack->InternalHeight, 180);
        TestEqual(TEXT("MarginTexels roundtrips"),   ReadBack->MarginTexels, 3);
        TestFalse(TEXT("SnapEnabled roundtrips"),    ReadBack->SnapEnabled);
        TestTrue (TEXT("FilterMode roundtrips"),     ReadBack->FilterMode == ECk_PixelArt_UpscaleFilter::Nearest);
    }

    // Set is a replace, not a merge: a second write must not leave any field of the first behind.
    const auto Replacement = ck_test_pixel_art_config_roundtrip::Make_Config(360, 2);
    FCk_PixelArtRenderer_StateRegistry::Set(World, Replacement);

    const auto Replaced = FCk_PixelArtRenderer_StateRegistry::TryGet(World);
    TestTrue(TEXT("the replacement reads as set"), Replaced.IsSet());

    if (Replaced.IsSet())
    {
        TestEqual(TEXT("InternalHeight was replaced"), Replaced->InternalHeight, 360);
        TestEqual(TEXT("MarginTexels was replaced"),   Replaced->MarginTexels, 2);
    }

    FCk_PixelArtRenderer_StateRegistry::Clear(World);

    TestFalse(TEXT("a cleared world reads as unset again"),
        FCk_PixelArtRenderer_StateRegistry::TryGet(World).IsSet());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_PixelArtRenderer_ConfigIsPerWorld,
    "CkTests.UnitTests.CkPixelArtRenderer.ConfigRegistry.IsPerWorld",
    kCkUnitTestFlags)

bool FCkTest_PixelArtRenderer_ConfigIsPerWorld::RunTest(const FString& Parameters)
{
    constexpr auto InformEngineOfWorld = false;

    auto* WorldA = UWorld::CreateWorld(EWorldType::Game, InformEngineOfWorld);
    auto* WorldB = UWorld::CreateWorld(EWorldType::Game, InformEngineOfWorld);

    TestNotNull(TEXT("world A was created"), WorldA);
    TestNotNull(TEXT("world B was created"), WorldB);

    if (WorldA == nullptr || WorldB == nullptr)
    { return false; }

    ON_SCOPE_EXIT
    {
        FCk_PixelArtRenderer_StateRegistry::Clear(WorldA);
        FCk_PixelArtRenderer_StateRegistry::Clear(WorldB);
        WorldA->DestroyWorld(InformEngineOfWorld);
        WorldB->DestroyWorld(InformEngineOfWorld);
    };

    FCk_PixelArtRenderer_StateRegistry::Set(WorldA, ck_test_pixel_art_config_roundtrip::Make_Config(180, 3));

    // PIE runs several worlds at once; configuring one must never pixelate the others.
    TestTrue (TEXT("the configured world reads as set"),   FCk_PixelArtRenderer_StateRegistry::TryGet(WorldA).IsSet());
    TestFalse(TEXT("the other world is still unset"),      FCk_PixelArtRenderer_StateRegistry::TryGet(WorldB).IsSet());

    FCk_PixelArtRenderer_StateRegistry::Clear(WorldA);

    TestFalse(TEXT("clearing one world leaves it unset"),  FCk_PixelArtRenderer_StateRegistry::TryGet(WorldA).IsSet());
    TestFalse(TEXT("clearing one world leaves the other unset"),
        FCk_PixelArtRenderer_StateRegistry::TryGet(WorldB).IsSet());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_PixelArtRenderer_ConfigRejectsNullWorld,
    "CkTests.UnitTests.CkPixelArtRenderer.ConfigRegistry.RejectsNullWorld",
    kCkUnitTestFlags)

bool FCkTest_PixelArtRenderer_ConfigRejectsNullWorld::RunTest(const FString& Parameters)
{
    // A null world key must not become a live registry entry that every unconfigured world then matches.
    TestFalse(TEXT("a null world reads as unset"),
        FCk_PixelArtRenderer_StateRegistry::TryGet(nullptr).IsSet());

    return true;
}
