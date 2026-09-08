#include "CkSlateLayout/CkUiDocument.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_context_menu_parser
{
    auto Parse(const FString& InMarkup, FCkUiDocument& OutDocument) -> FCkUiLoadResult
    {
        return FCkUiDocumentParser::TryParse(InMarkup, TEXT(""), {}, OutDocument, TEXT("UiContextMenuParserTest"));
    }

    auto Menus() -> FString
    {
        return TEXT("<menu id=\"actions\"><menu-item key=\"run\" label=\"Run\" action=\"run\"/></menu>");
    }

    auto Table(const FString& InAttributes = TEXT("")) -> FString
    {
        return TEXT("<table id=\"table\" bind=\"records\"") + InAttributes
            + TEXT("><table-column id=\"name\" label=\"Name\"><text id=\"value\" bind-field=\"name\"/></table-column></table>");
    }

    auto Tree(const FString& InAttributes = TEXT("")) -> FString
    {
        return TEXT("<tree id=\"tree\" bind=\"nodes\"") + InAttributes
            + TEXT("><row id=\"row\"><text id=\"value\" bind-field=\"name\"/></row></tree>");
    }

    auto Document(const FString& InBody) -> FString
    {
        return TEXT("<ui version=\"1\">") + Menus() + TEXT("<region name=\"main\">") + InBody + TEXT("</region></ui>");
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiContextMenu_Parser,
    "Ck.UiAuthoring.ContextMenus.ParserSchema",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiContextMenu_Parser::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_context_menu_parser;
    FCkUiDocument Parsed;
    const FCkUiLoadResult TableResult = Parse(Document(Table(TEXT(" context-menu=\"actions\""))), Parsed);
    if (!TestTrue(TEXT("Table context menu reference parses"), TableResult.Succeeded))
    {
        for (const FString& Error : TableResult.Errors) { AddError(Error); }
        return false;
    }
    const FCkUiNode* TableNode = Parsed.Regions.Find(TEXT("main"));
    TestTrue(TEXT("Table context menu reference retained"), TableNode != nullptr && TableNode->Kind == ECkUiNodeKind::Table
        && TableNode->ContextMenuReference == TEXT("actions") && TableNode->ContextMenuAction.IsEmpty());

    const FCkUiLoadResult TreeResult = Parse(Document(Tree(TEXT(" context-menu=\"actions\""))), Parsed);
    const FCkUiNode* TreeNode = Parsed.Regions.Find(TEXT("main"));
    TestTrue(TEXT("Tree context menu reference parses and is retained"), TreeResult.Succeeded && TreeNode != nullptr
        && TreeNode->Kind == ECkUiNodeKind::Tree && TreeNode->ContextMenuReference == TEXT("actions"));

    const FCkUiLoadResult LegacyResult = Parse(Document(Table(TEXT(" context-menu-action=\"legacy\""))), Parsed);
    const FCkUiNode* LegacyNode = Parsed.Regions.Find(TEXT("main"));
    TestTrue(TEXT("Legacy table context menu action remains accepted"), LegacyResult.Succeeded && LegacyNode != nullptr
        && LegacyNode->ContextMenuAction == TEXT("legacy") && LegacyNode->ContextMenuReference.IsEmpty());

    const FString Templated = TEXT("<ui version=\"1\">") + Menus()
        + TEXT("<template name=\"table\"><param name=\"context\" type=\"text\"/><table id=\"table\" bind=\"records\" context-menu-param=\"context\"><table-column id=\"name\" label=\"Name\"><text id=\"value\" bind-field=\"name\"/></table-column></table></template><region name=\"main\"><use id=\"instance\" template=\"table\" context=\"actions\"/></region></ui>");
    const FCkUiLoadResult TemplateResult = Parse(Templated, Parsed);
    const FCkUiNode* TemplateNode = Parsed.Regions.Find(TEXT("main"));
    TestTrue(TEXT("Typed context-menu template field expands"), TemplateResult.Succeeded && TemplateNode != nullptr
        && TemplateNode->ContextMenuReference == TEXT("actions"));

    FCkUiDocument Existing;
    Existing.Regions.Add(TEXT("old"), FCkUiNode{.Id = TEXT("old-root")});
    const auto Reject = [this, &Existing](const FString& InName, const FString& InMarkup)
    {
        const FCkUiLoadResult Result = Parse(InMarkup, Existing);
        TestFalse(*InName, Result.Succeeded);
        TestTrue(*(InName + TEXT(" reports a diagnostic")), !Result.Errors.IsEmpty());
        TestTrue(*(InName + TEXT(" preserves prior output")), Existing.Regions.Contains(TEXT("old"))
            && Existing.Regions.Num() == 1 && Existing.Menus.IsEmpty());
    };
    Reject(TEXT("Unknown context menu rejects"), Document(Table(TEXT(" context-menu=\"missing\""))));
    Reject(TEXT("Empty context menu rejects"), Document(Table(TEXT(" context-menu=\"  \""))));
    Reject(TEXT("Context menu conflicts with legacy action"), Document(Table(TEXT(" context-menu=\"actions\" context-menu-action=\"legacy\""))));
    Reject(TEXT("Context menu outside collection rejects"), Document(TEXT("<text id=\"text\" context-menu=\"actions\">Text</text>")));
    Reject(TEXT("Legacy action remains table-only"), Document(Tree(TEXT(" context-menu-action=\"legacy\""))));
    return true;
}

#endif
