#include "Misc/AutomationTest.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Interfaces/IPluginManager.h"
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
    AddInfo(FString::Printf(TEXT("'A': contours=%d tessVerts=%d tessTris=%d advanceEm=%.4f"),
        GlyphA.Contours.Num(), GlyphA.TessVerts.Num(), GlyphA.TessTris.Num(), GlyphA.AdvanceEm));
    AddInfo(FString::Printf(TEXT("'O': contours=%d tessVerts=%d tessTris=%d"),
        GlyphO.Contours.Num(), GlyphO.TessVerts.Num(), GlyphO.TessTris.Num()));
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

    // Font-fallback coverage query: Roboto has 'A' but not an emoji codepoint.
    TestTrue(TEXT("Roboto reports coverage of 'A' (U+0041)"), Cache.FaceHasCodepoint(Face, 0x41));
    TestFalse(TEXT("Roboto reports NO coverage of emoji U+1F600"), Cache.FaceHasCodepoint(Face, 0x1F600));
#else
    AddInfo(TEXT("CK_PMG_WITH_FREETYPE=0 — skipped"));
#endif
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkPmg_FontGlyph_BundledEmojiFontLoads,
    "Ck.Pmg.FontGlyph.BundledEmojiFontLoads",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkPmg_FontGlyph_BundledEmojiFontLoads::RunTest(const FString& Parameters)
{
#if CK_PMG_WITH_FREETYPE
    const TSharedPtr<IPlugin> Plugin = IPluginManager::Get().FindPlugin(TEXT("CkFoundation"));
    if (!TestTrue(TEXT("found CkFoundation plugin"), Plugin.IsValid())) { return false; }

    const FString Path = Plugin->GetBaseDir() / TEXT("Source/CkPmg/Resources/NotoEmoji-Medium.ttf");
    TArray<uint8> Bytes;
    if (!TestTrue(TEXT("loaded bundled NotoEmoji-Medium.ttf"), FFileHelper::LoadFileToArray(Bytes, *Path)))
    { return false; }

    auto& Cache = ck::pmg::FFontGlyphCache::Get();
    const int32 Face = Cache.EnsureFace(Bytes);
    TestTrue(TEXT("emoji face valid"), Face != INDEX_NONE);
    if (Face != INDEX_NONE)
    {
        // U+1F600 GRINNING FACE — Noto Emoji covers it; a text font would not.
        TestTrue(TEXT("Noto Emoji covers U+1F600"), Cache.FaceHasCodepoint(Face, 0x1F600));
        const auto& Glyph = Cache.GetOrBuildGlyph(Face, 0x1F600);
        TestTrue(TEXT("U+1F600 produces contours"), Glyph.Contours.Num() >= 1);
    }
#else
    AddInfo(TEXT("CK_PMG_WITH_FREETYPE=0 — skipped"));
#endif
    return true;
}
