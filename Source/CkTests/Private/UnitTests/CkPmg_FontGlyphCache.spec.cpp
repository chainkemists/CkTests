#include "Misc/AutomationTest.h"
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
