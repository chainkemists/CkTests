#include "CkSlateLayout/CkUiDocument.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_menus
{
    auto Parse(const FString& InMarkup, FCkUiDocument& OutDocument) -> FCkUiLoadResult
    {
        return FCkUiDocumentParser::TryParse(InMarkup, TEXT(".menu { color: #ffffff; }"), {}, OutDocument, TEXT("UiMenusParserTest"));
    }

    auto ValidMarkup() -> FString
    {
        return TEXT("<ui version=\"1\"><menu id=\"actions\"><menu-item key=\"refresh\" label=\"Refresh\" action=\"refresh\" enabled-bind=\"can-refresh\" visible-bind=\"show-refresh\" tooltip=\"Refresh the data\"/><separator key=\"sep\"/><submenu key=\"more\" label-bind=\"more-label\" menu=\"more\" tooltip-bind=\"more-tip\"/></menu><menu id=\"more\"><menu-item key=\"about\" label=\"About\" action=\"about\"/></menu><region name=\"main\"><row id=\"toolbar\"><menu-button id=\"actions-button\" class=\"menu\" menu=\"actions\" label-bind=\"actions-label\" enabled-bind=\"can-open\" visible=\"show-actions\"/></row></region></ui>");
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiMenus_Parser,
    "Ck.UiAuthoring.Menus.ParserSchema",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiMenus_Parser::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_menus;
    FCkUiDocument Document;
    const FCkUiLoadResult Accepted = Parse(ValidMarkup(), Document);
    if (!TestTrue(TEXT("Menu document with forward reference parses"), Accepted.Succeeded))
    { for (const FString& Error : Accepted.Errors) { AddError(Error); } return false; }
    const FCkUiMenu* Actions = Document.Menus.Find(TEXT("actions"));
    if (!TestTrue(TEXT("Actions menu retains three entries"), Actions != nullptr && Actions->Entries.Num() == 3)) { return false; }
    TestEqual(TEXT("Item kind retained"), Actions->Entries[0].Kind, ECkUiMenuEntryKind::Item);
    TestEqual(TEXT("Item action retained"), Actions->Entries[0].Action, FString(TEXT("refresh")));
    TestEqual(TEXT("Item enabled binding retained"), Actions->Entries[0].EnabledBinding, FString(TEXT("can-refresh")));
    TestEqual(TEXT("Submenu reference retained"), Actions->Entries[2].MenuReference, FString(TEXT("more")));
    const FCkUiNode* Toolbar = Document.Regions.Find(TEXT("main"));
    if (!TestTrue(TEXT("Menu button is retained"), Toolbar != nullptr && Toolbar->Children.Num() == 1 && Toolbar->Children[0].Kind == ECkUiNodeKind::MenuButton)) { return false; }
    const FCkUiNode& MenuButton = Toolbar->Children[0];
    TestEqual(TEXT("Menu button reference retained"), MenuButton.MenuReference, FString(TEXT("actions")));
    TestEqual(TEXT("Menu button label binding uses generic binding transport"), MenuButton.Binding, FString(TEXT("actions-label")));
    TestEqual(TEXT("Menu button enabled binding uses tab enabled transport"), MenuButton.TabEnabledBinding, FString(TEXT("can-open")));

    FCkUiDocument Existing;
    Existing.Regions.Add(TEXT("old"), FCkUiNode{.Id = TEXT("old-root")});
    const auto Reject = [this, &Existing](const FString& InName, const FString& InMarkup)
    {
        const FCkUiLoadResult Result = Parse(InMarkup, Existing);
        TestFalse(*InName, Result.Succeeded);
        TestTrue(*(InName + TEXT(" reports a diagnostic")), !Result.Errors.IsEmpty());
        TestTrue(*(InName + TEXT(" preserves output atomically")), Existing.Regions.Contains(TEXT("old")) && Existing.Regions.Num() == 1 && Existing.Menus.IsEmpty());
    };
    Reject(TEXT("Missing menu button target rejects"), TEXT("<ui version=\"1\"><region name=\"main\"><menu-button id=\"open\" menu=\"missing\" label=\"Open\"/></region></ui>"));
    Reject(TEXT("Menu entry requires label form"), TEXT("<ui version=\"1\"><menu id=\"actions\"><menu-item key=\"run\" action=\"run\"/></menu><region name=\"main\"><text id=\"ok\">ok</text></region></ui>"));
    Reject(TEXT("Menu labels are exclusive"), TEXT("<ui version=\"1\"><menu id=\"actions\"><menu-item key=\"run\" label=\"Run\" label-bind=\"run-label\" action=\"run\"/></menu><region name=\"main\"><text id=\"ok\">ok</text></region></ui>"));
    Reject(TEXT("Empty literal menu label rejects"), TEXT("<ui version=\"1\"><menu id=\"actions\"><menu-item key=\"run\" label=\"  \" action=\"run\"/></menu><region name=\"main\"><text id=\"ok\">ok</text></region></ui>"));
    Reject(TEXT("Empty menu binding rejects"), TEXT("<ui version=\"1\"><menu id=\"actions\"><menu-item key=\"run\" label=\"Run\" action=\"run\" enabled-bind=\"\"/></menu><region name=\"main\"><text id=\"ok\">ok</text></region></ui>"));
    Reject(TEXT("Menu entry child rejects"), TEXT("<ui version=\"1\"><menu id=\"actions\"><menu-item key=\"run\" label=\"Run\" action=\"run\"><text id=\"wrong\">Wrong</text></menu-item></menu><region name=\"main\"><text id=\"ok\">ok</text></region></ui>"));
    Reject(TEXT("Duplicate trimmed keys reject"), TEXT("<ui version=\"1\"><menu id=\"actions\"><separator key=\"sep\"/><separator key=\" sep \"/></menu><region name=\"main\"><text id=\"ok\">ok</text></region></ui>"));
    Reject(TEXT("Recursive menus reject"), TEXT("<ui version=\"1\"><menu id=\"a\"><submenu key=\"b\" label=\"B\" menu=\"b\"/></menu><menu id=\"b\"><submenu key=\"a\" label=\"A\" menu=\"a\"/></menu><region name=\"main\"><text id=\"ok\">ok</text></region></ui>"));
    FString ExplosiveMenus = TEXT("<ui version=\"1\"><menu id=\"leaf\"><menu-item key=\"run\" label=\"Run\" action=\"run\"/></menu>");
    for (int32 Index = 0; Index < 10; ++Index)
    {
        const FString Child = Index == 0 ? FString(TEXT("leaf")) : FString::Printf(TEXT("m%d"), Index - 1);
        ExplosiveMenus += FString::Printf(TEXT("<menu id=\"m%d\"><submenu key=\"left\" label=\"Left\" menu=\"%s\"/><submenu key=\"right\" label=\"Right\" menu=\"%s\"/></menu>"), Index, *Child, *Child);
    }
    ExplosiveMenus += TEXT("<region name=\"main\"><menu-button id=\"open\" menu=\"m9\" label=\"Open\"/></region></ui>");
    Reject(TEXT("Repeated submenu expansion obeys entry budget"), ExplosiveMenus);
    Reject(TEXT("Menu button labels are exclusive"), TEXT("<ui version=\"1\"><menu id=\"actions\"><separator key=\"sep\"/></menu><region name=\"main\"><menu-button id=\"open\" menu=\"actions\" label=\"Open\" label-bind=\"open-label\"/></region></ui>"));

    const FString Templated = TEXT("<ui version=\"1\"><menu id=\"actions\"><separator key=\"sep\"/></menu><template name=\"menu-trigger\"><param name=\"menu\" type=\"text\"/><param name=\"label\" type=\"text-binding\"/><param name=\"enabled\" type=\"bool-binding\"/><menu-button id=\"trigger\" menu-param=\"menu\" label-bind-param=\"label\" enabled-bind-param=\"enabled\"/></template><region name=\"main\"><use id=\"instance\" template=\"menu-trigger\" menu=\"actions\" label-bind=\"actions-label\" enabled-bind=\"can-open\"/></region></ui>");
    FCkUiDocument TemplateDocument;
    const FCkUiLoadResult TemplateResult = Parse(Templated, TemplateDocument);
    if (!TestTrue(TEXT("Typed menu button template fields parse"), TemplateResult.Succeeded)) { return false; }
    const FCkUiNode* TemplateButton = TemplateDocument.Regions.Find(TEXT("main"));
    TestTrue(TEXT("Typed template fields expand into menu button contract"), TemplateButton != nullptr && TemplateButton->Kind == ECkUiNodeKind::MenuButton
        && TemplateButton->MenuReference == TEXT("actions") && TemplateButton->Binding == TEXT("actions-label") && TemplateButton->TabEnabledBinding == TEXT("can-open"));
    return true;
}

#endif
