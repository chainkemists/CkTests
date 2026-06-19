#include "Misc/AutomationTest.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "CkPmg/CkPmg_FontGlyphCache.h"

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkPmg_FontGlyph_FreeTypeLinks,
    "Ck.Pmg.FontGlyph.FreeTypeLinks",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkPmg_FontGlyph_FreeTypeLinks::RunTest(const FString& Parameters)
{
#if CK_PMG_WITH_FREETYPE
    TestTrue(TEXT("FreeType FT_Init_FreeType succeeds"),
        ck::pmg::FontGlyph_SelfTest_FreeTypeInitDone());
#else
    AddInfo(TEXT("CK_PMG_WITH_FREETYPE=0 (server/no-freetype target) — skipped"));
#endif
    return true;
}

// Engine-shipped TTF, always present — lets us test glyph extraction without the bundled CJK asset.
static FString EngineTestFontPath()
{
    return FPaths::EngineContentDir() / TEXT("Slate/Fonts/Roboto-Regular.ttf");
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkPmg_FontGlyph_ExtractsAndCaches,
    "Ck.Pmg.FontGlyph.ExtractsAndCaches",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkPmg_FontGlyph_ExtractsAndCaches::RunTest(const FString& Parameters)
{
#if CK_PMG_WITH_FREETYPE
    TArray<uint8> Bytes;
    if (!TestTrue(TEXT("loaded engine Roboto TTF"), FFileHelper::LoadFileToArray(Bytes, *EngineTestFontPath())))
    { return false; }

    auto& Cache = ck::pmg::FFontGlyphCache::Get();
    const int32 Face = Cache.EnsureFace(Bytes);
    TestTrue(TEXT("face key is valid"), Face != INDEX_NONE);
    if (Face == INDEX_NONE) { return false; }

    // 'A' (U+0041) is a single outer contour, no holes -> verts+tris, advance > 0.
    const auto& GlyphA = Cache.GetOrBuildGlyph(Face, 0x41);
    TestTrue(TEXT("'A' has geometry"), GlyphA.bHasGeometry);
    TestTrue(TEXT("'A' has >=1 contour"), GlyphA.Contours.Num() >= 1);
    TestTrue(TEXT("'A' has filled triangles"), GlyphA.TessTris.Num() >= 1);
    TestTrue(TEXT("'A' advance > 0"), GlyphA.AdvanceEm > 0.0f);

    // 'O' has a hole -> at least 2 contours, still produces a fillable annulus.
    const auto& GlyphO = Cache.GetOrBuildGlyph(Face, 0x4F);
    TestTrue(TEXT("'O' has >=2 contours (hole)"), GlyphO.Contours.Num() >= 2);
    TestTrue(TEXT("'O' has filled triangles"), GlyphO.TessTris.Num() >= 1);

    // Cache hit: same address on repeat lookup.
    const auto& GlyphA2 = Cache.GetOrBuildGlyph(Face, 0x41);
    TestEqual(TEXT("repeat lookup returns cached entry (same address)"),
        (const void*)&GlyphA2, (const void*)&GlyphA);

    // Space (U+0020): advance > 0, no geometry.
    const auto& Space = Cache.GetOrBuildGlyph(Face, 0x20);
    TestFalse(TEXT("space has no geometry"), Space.bHasGeometry);
    TestTrue(TEXT("space advance > 0"), Space.AdvanceEm > 0.0f);
#else
    AddInfo(TEXT("CK_PMG_WITH_FREETYPE=0 — skipped"));
#endif
    return true;
}
