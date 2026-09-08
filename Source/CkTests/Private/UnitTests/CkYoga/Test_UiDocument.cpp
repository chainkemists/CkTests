#include "CkSlateLayout/CkUiDocument.h"
#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_document
{
    auto Parse(const FString& InMarkup, const FString& InStylesheet, const TMap<FString, FString>& InTokens, FCkUiDocument& OutDocument) -> FCkUiLoadResult
    {
        return FCkUiDocumentParser::TryParse(InMarkup, InStylesheet, InTokens, OutDocument, TEXT("UiAuthoringTest"));
    }

    auto ValidMarkup() -> FString
    {
        return TEXT("<ui version=\"1\"><region name=\"inventory\"><column id=\"root\" class=\"panel\"><native id=\"search\" bind=\"search\"/><text id=\"heading\" class=\"heading strong\">Details</text><button id=\"clear\" class=\"heading\" action=\"clear\">Clear</button></column></region></ui>");
    }

    auto ValidStyles() -> FString
    {
        return TEXT(".panel { gap: var(--space-s); padding: 2px 4px 6px 8px; background-color: var(--surface); } .heading { font-size: var(--font-heading); color: var(--text-strong); font-weight: normal; } .strong { font-weight: bold; min-width: 20px; max-width: 40px; horizontal-align: center; }");
    }

    auto DynamicMarkup() -> FString
    {
        return TEXT("<ui version=\"1\"><region name=\"inventory\"><column id=\"root\"><row id=\"toolbar\"><native id=\"host\" bind=\"host\"/><text id=\"caption\">Caption</text><button id=\"apply\" action=\"apply\">Apply</button><search id=\"query\" bind=\"query\" placeholder=\"Filter inventory\"/><image id=\"thumbnail\" bind=\"thumbnail\"/></row><scroll id=\"results\" visible=\"has-results\"><text id=\"summary\" bind=\"summary\"/></scroll></column></region></ui>");
    }

    auto Tokens() -> TMap<FString, FString>
    {
        return {{TEXT("--space-s"), TEXT("6px")}, {TEXT("--font-heading"), TEXT("18")}, {TEXT("--text-strong"), TEXT("#AABBCCDD")}, {TEXT("--surface"), TEXT("#102030")}};
    }

    auto HasError(const FCkUiLoadResult& InResult, const FString& InNeedle) -> bool
    {
        for (const auto& Error : InResult.Errors) { if (Error.Contains(InNeedle)) { return true; } }
        return false;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiAuthoringParser_Valid,
    "Ck.UiAuthoring.Parser.ValidDocumentStylesTokens",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiAuthoringParser_Valid::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_document;
    auto Document = FCkUiDocument{};
    const auto Result = Parse(ValidMarkup(), ValidStyles(), Tokens(), Document);
    TestTrue(TEXT("Valid document succeeds"), Result.Succeeded);
    TestEqual(TEXT("One named region"), Document.Regions.Num(), 1);
    const auto* Root = Document.Regions.Find(TEXT("inventory"));
    if (!TestNotNull(TEXT("Inventory root exists"), Root)) { return false; }
    TestEqual(TEXT("Column child count"), Root->Children.Num(), 3);
    TestEqual(TEXT("Gap resolves token"), Root->Style.Gap, 6.0f);
    TestEqual(TEXT("Four-value padding left follows CSS order"), Root->Style.Padding.Left, 8.0f);
    TestEqual(TEXT("Four-value padding top follows CSS order"), Root->Style.Padding.Top, 2.0f);
    const auto& Heading = Root->Children[1];
    TestEqual(TEXT("Text content retained"), Heading.Text, FString(TEXT("Details")));
    TestTrue(TEXT("Multiple classes apply in stylesheet order"), Heading.Style.Bold);
    TestEqual(TEXT("Font size resolves token"), Heading.Style.FontSize.GetValue(), 18.0f);
    TestEqual(TEXT("Style minimum width"), Heading.Style.MinWidth, 20.0f);
    TestEqual(TEXT("Style maximum width"), Heading.Style.MaxWidth.GetValue(), 40.0f);
    TestEqual(TEXT("Alpha color parses"), Heading.Style.Color.GetValue().A, 221.0f / 255.0f);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiAuthoringParser_PaddingTokens,
    "Ck.UiAuthoring.Parser.PaddingTokenComponents",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiAuthoringParser_PaddingTokens::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_document;
    const auto ParsePadding = [this](const FString& InStylesheet, const TMap<FString, FString>& InTokens, const FString& InName) -> TOptional<FMargin>
    {
        auto Document = FCkUiDocument{};
        const FCkUiLoadResult Result = Parse(
            TEXT("<ui version=\"1\"><region name=\"inventory\"><column id=\"root\" class=\"panel\"/></region></ui>"),
            InStylesheet, InTokens, Document);
        if (!TestTrue(*InName, Result.Succeeded))
        {
            for (const FString& Error : Result.Errors) { AddError(Error); }
            return {};
        }
        const FCkUiNode* Root = Document.Regions.Find(TEXT("inventory"));
        if (!TestNotNull(*(InName + TEXT(" root exists")), Root)) { return {}; }
        return Root->Style.Padding;
    };

    const TOptional<FMargin> TwoValue = ParsePadding(TEXT(".panel { padding: 0 var(--space-s); }"), Tokens(), TEXT("Zero and token padding succeeds"));
    if (!TestTrue(TEXT("Two-value token padding resolves"), TwoValue.IsSet())) { return false; }
    TestEqual(TEXT("Zero and token padding keeps vertical zero"), TwoValue->Top, 0.0f);
    TestEqual(TEXT("Zero and token padding resolves horizontal token"), TwoValue->Left, 6.0f);

    const auto FourTokens = TMap<FString, FString>{{TEXT("--top"), TEXT("1px")}, {TEXT("--right"), TEXT("2px")},
        {TEXT("--bottom"), TEXT("3px")}, {TEXT("--left"), TEXT("4px")}};
    const TOptional<FMargin> FourValue = ParsePadding(TEXT(".panel { padding: var(--top) var(--right) var(--bottom) var(--left); }"), FourTokens, TEXT("Four token padding succeeds"));
    if (!TestTrue(TEXT("Four-value token padding resolves"), FourValue.IsSet())) { return false; }
    TestEqual(TEXT("Four token padding maps top"), FourValue->Top, 1.0f);
    TestEqual(TEXT("Four token padding maps right"), FourValue->Right, 2.0f);
    TestEqual(TEXT("Four token padding maps bottom"), FourValue->Bottom, 3.0f);
    TestEqual(TEXT("Four token padding maps left"), FourValue->Left, 4.0f);

    const TOptional<FMargin> ShorthandToken = ParsePadding(TEXT(".panel { padding: var(--panel-padding); }"),
        {{TEXT("--panel-padding"), TEXT("2px 5px")}}, TEXT("Whole padding shorthand token succeeds"));
    if (!TestTrue(TEXT("Whole shorthand token padding resolves"), ShorthandToken.IsSet())) { return false; }
    TestEqual(TEXT("Whole shorthand token maps vertical"), ShorthandToken->Top, 2.0f);
    TestEqual(TEXT("Whole shorthand token maps horizontal"), ShorthandToken->Left, 5.0f);

    const TOptional<FMargin> WhitespaceToken = ParsePadding(TEXT(".panel { padding: var( --space-s ); }"), Tokens(), TEXT("Whitespace token padding succeeds"));
    if (!TestTrue(TEXT("Whitespace token padding resolves"), WhitespaceToken.IsSet())) { return false; }
    TestEqual(TEXT("Whitespace token padding preserves legacy token trimming"), WhitespaceToken->Left, 6.0f);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiAuthoringParser_Rejects,
    "Ck.UiAuthoring.Parser.RejectsInvalidAndPreservesOutput",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiAuthoringParser_Rejects::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_document;
    auto Existing = FCkUiDocument{};
    Existing.Regions.Add(TEXT("old"), FCkUiNode{.Id = TEXT("old-root")});
    const auto ExpectReject = [this, &Existing](const FString& InName, const FString& InMarkup, const FString& InStylesheet, const TMap<FString, FString>& InTokens)
    {
        const auto Result = Parse(InMarkup, InStylesheet, InTokens, Existing);
        TestFalse(*InName, Result.Succeeded);
        TestEqual(*(InName + TEXT(" preserves output")), Existing.Regions.Num(), 1);
        TestTrue(*(InName + TEXT(" retained original region")), Existing.Regions.Contains(TEXT("old")));
    };
    ExpectReject(TEXT("Malformed XML"), TEXT("<ui version=\"1\"><region name=\"x\"><column id=\"x\"></region></ui>"), TEXT(""), {});
    ExpectReject(TEXT("Duplicate id"), TEXT("<ui version=\"1\"><region name=\"x\"><column id=\"a\"><text id=\"a\">x</text></column></region></ui>"), TEXT(""), {});
    ExpectReject(TEXT("Missing id"), TEXT("<ui version=\"1\"><region name=\"x\"><text>x</text></region></ui>"), TEXT(""), {});
    ExpectReject(TEXT("Unknown attribute"), TEXT("<ui version=\"1\"><region name=\"x\"><text id=\"a\" onclick=\"x\">x</text></region></ui>"), TEXT(""), {});
    ExpectReject(TEXT("Button cannot bind data"), TEXT("<ui version=\"1\"><region name=\"x\"><button id=\"a\" bind=\"value\" action=\"apply\">Apply</button></region></ui>"), TEXT(""), {});
    ExpectReject(TEXT("Text cannot declare an action"), TEXT("<ui version=\"1\"><region name=\"x\"><text id=\"a\" action=\"apply\">Text</text></region></ui>"), TEXT(""), {});
    ExpectReject(TEXT("Row cannot declare a placeholder"), TEXT("<ui version=\"1\"><region name=\"x\"><row id=\"a\" placeholder=\"Filter\"/></region></ui>"), TEXT(""), {});
    ExpectReject(TEXT("Leaf children"), TEXT("<ui version=\"1\"><region name=\"x\"><text id=\"a\"><text id=\"b\">x</text></text></region></ui>"), TEXT(""), {});
    ExpectReject(TEXT("Button cannot have children"), TEXT("<ui version=\"1\"><region name=\"x\"><button id=\"a\" action=\"apply\"><text id=\"b\">x</text></button></region></ui>"), TEXT(""), {});
    ExpectReject(TEXT("Search cannot have children"), TEXT("<ui version=\"1\"><region name=\"x\"><search id=\"a\" bind=\"query\"><text id=\"b\">x</text></search></region></ui>"), TEXT(""), {});
    ExpectReject(TEXT("Late leaf child preserves parsed output"), TEXT("<ui version=\"1\"><region name=\"x\"><column id=\"root\"><row id=\"toolbar\"><native id=\"host\" bind=\"host\"/><text id=\"caption\">Caption</text><button id=\"apply\" action=\"apply\">Apply</button><search id=\"query\" bind=\"query\"/><image id=\"thumbnail\" bind=\"thumbnail\"/></row><scroll id=\"results\"><text id=\"summary\">Summary</text></scroll><image id=\"late\" bind=\"late\"><text id=\"child\">Late</text></image></column></region></ui>"), TEXT(""), {});
    ExpectReject(TEXT("Unsupported selector"), ValidMarkup(), TEXT("#panel { gap: 1; }"), {});
    ExpectReject(TEXT("Unsupported property"), ValidMarkup(), TEXT(".panel { position: absolute; }"), {});
    ExpectReject(TEXT("Unsupported property in unmatched class"), ValidMarkup(), TEXT(".unused { position: absolute; }"), {});
    ExpectReject(TEXT("Unknown class"), TEXT("<ui version=\"1\"><region name=\"x\"><text id=\"a\" class=\"typo\">x</text></region></ui>"), TEXT(""), {});
    ExpectReject(TEXT("Invalid number"), ValidMarkup(), TEXT(".panel { gap: NaN; }"), {});
    ExpectReject(TEXT("Infinite number"), ValidMarkup(), TEXT(".panel { gap: Infinity; }"), {});
    ExpectReject(TEXT("Trailing numeric junk"), ValidMarkup(), TEXT(".panel { gap: 2oops; }"), {});
    ExpectReject(TEXT("Invalid bounds"), ValidMarkup(), TEXT(".panel { min-width: 10; max-width: 9; }"), {});
    ExpectReject(TEXT("Missing token"), ValidMarkup(), TEXT(".panel { gap: var(--missing); }"), {});
    ExpectReject(TEXT("Missing padding component token"), ValidMarkup(), TEXT(".panel { padding: 0 var(--missing); }"), {});
    ExpectReject(TEXT("Malformed padding component token"), ValidMarkup(), TEXT(".panel { padding: 0 var(--space-s; }"), Tokens());
    ExpectReject(TEXT("Cyclic padding component token"), ValidMarkup(), TEXT(".panel { padding: 0 var(--a); }"), {{TEXT("--a"), TEXT("var(--b)")}, {TEXT("--b"), TEXT("var(--a)")}});
    ExpectReject(TEXT("Padding rejects more than four components"), ValidMarkup(), TEXT(".panel { padding: 0 1 2 3 4; }"), {});
    ExpectReject(TEXT("Padding token expansion is bounded"), ValidMarkup(), TEXT(".panel { padding: 0 var(--oversize); }"), {{TEXT("--oversize"), FString::ChrN(1024 * 1024, TEXT('1'))}});
    ExpectReject(TEXT("Cyclic token"), ValidMarkup(), TEXT(".panel { gap: var(--a); }"), {{TEXT("--a"), TEXT("var(--b)")}, {TEXT("--b"), TEXT("var(--a)")}});
    ExpectReject(TEXT("Container property on text"), ValidMarkup(), ValidStyles() + TEXT(" .heading { background-color: #FFFFFF; }"), Tokens());
    ExpectReject(TEXT("Text property on container"), ValidMarkup(), ValidStyles() + TEXT(" .panel { font-size: 12; }"), Tokens());
    ExpectReject(TEXT("Invalid font weight"), ValidMarkup(), TEXT(".heading { font-weight: 600; }"), {});
    ExpectReject(TEXT("Font size cap"), ValidMarkup(), TEXT(".heading { font-size: 513px; }"), {});
    ExpectReject(TEXT("Duplicate native binding"), TEXT("<ui version=\"1\"><region name=\"x\"><column id=\"r\"><native id=\"a\" bind=\"same\"/><native id=\"b\" bind=\"same\"/></column></region></ui>"), TEXT(""), {});
    ExpectReject(TEXT("Duplicate XML attribute"), TEXT("<ui version=\"1\"><region name=\"x\"><text id=\"a\" id=\"b\">x</text></region></ui>"), TEXT(""), {});
    ExpectReject(TEXT("Native text content"), TEXT("<ui version=\"1\"><region name=\"x\"><native id=\"a\" bind=\"b\">x</native></region></ui>"), TEXT(""), {});
    ExpectReject(TEXT("Search unknown attribute"), TEXT("<ui version=\"1\"><region name=\"x\"><search id=\"query\" bind=\"query\" unexpected=\"x\"/></region></ui>"), TEXT(""), {});
    ExpectReject(TEXT("Search missing binding"), TEXT("<ui version=\"1\"><region name=\"x\"><search id=\"query\" placeholder=\"Filter\"/></region></ui>"), TEXT(""), {});
    ExpectReject(TEXT("Image missing binding"), TEXT("<ui version=\"1\"><region name=\"x\"><image id=\"thumbnail\"/></region></ui>"), TEXT(""), {});
    ExpectReject(TEXT("Image cannot have children"), TEXT("<ui version=\"1\"><region name=\"x\"><image id=\"thumbnail\" bind=\"thumbnail\"><text id=\"child\">x</text></image></region></ui>"), TEXT(""), {});
    ExpectReject(TEXT("Scroll requires a child"), TEXT("<ui version=\"1\"><region name=\"x\"><scroll id=\"results\"/></region></ui>"), TEXT(""), {});
    ExpectReject(TEXT("Scroll allows exactly one child"), TEXT("<ui version=\"1\"><region name=\"x\"><scroll id=\"results\"><text id=\"first\">One</text><text id=\"second\">Two</text></scroll></region></ui>"), TEXT(""), {});
    ExpectReject(TEXT("Text cannot mix literal and bound content"), TEXT("<ui version=\"1\"><region name=\"x\"><text id=\"summary\" bind=\"summary\">Summary</text></region></ui>"), TEXT(""), {});
    ExpectReject(TEXT("Visibility binding must be a name"), TEXT("<ui version=\"1\"><region name=\"x\"><text id=\"summary\" visible=\"not valid\">Summary</text></region></ui>"), TEXT(""), {});
    ExpectReject(TEXT("Three value padding is outside subset"), ValidMarkup(), TEXT(".panel { padding: 1 2 3; }"), {});
    ExpectReject(TEXT("XML declaration rejected explicitly"), TEXT("<?xml version=\"1.0\"?><ui version=\"1\"><region name=\"x\"><text id=\"a\">x</text></region></ui>"), TEXT(""), {});
    ExpectReject(TEXT("Trailing XML garbage"), TEXT("<ui version=\"1\"><region name=\"x\"><text id=\"a\">x</text></region></ui> trailing"), TEXT(""), {});
    ExpectReject(TEXT("Second XML root"), TEXT("<ui version=\"1\"><region name=\"x\"><text id=\"a\">x</text></region></ui><ui version=\"1\"><region name=\"y\"><text id=\"b\">y</text></region></ui>"), TEXT(""), {});
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiAuthoringParser_DynamicNodes,
    "Ck.UiAuthoring.Parser.DynamicNodes",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiAuthoringParser_DynamicNodes::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_document;
    auto Document = FCkUiDocument{};
    const FCkUiLoadResult Result = Parse(DynamicMarkup(), TEXT(""), {}, Document);
    if (!TestTrue(TEXT("Dynamic document succeeds"), Result.Succeeded)) { return false; }
    const FCkUiNode* Root = Document.Regions.Find(TEXT("inventory"));
    if (!TestNotNull(TEXT("Dynamic inventory root exists"), Root) || !TestEqual(TEXT("Root has toolbar and scroll"), Root->Children.Num(), 2)) { return false; }
    TestEqual(TEXT("Column node kind"), Root->Kind, ECkUiNodeKind::Column);
    const FCkUiNode& Toolbar = Root->Children[0];
    TestEqual(TEXT("Row node kind"), Toolbar.Kind, ECkUiNodeKind::Row);
    if (!TestEqual(TEXT("Toolbar has five leaf kinds"), Toolbar.Children.Num(), 5)) { return false; }
    TestEqual(TEXT("Native node kind"), Toolbar.Children[0].Kind, ECkUiNodeKind::Native);
    TestEqual(TEXT("Text node kind"), Toolbar.Children[1].Kind, ECkUiNodeKind::Text);
    TestEqual(TEXT("Button node kind"), Toolbar.Children[2].Kind, ECkUiNodeKind::Button);
    TestEqual(TEXT("Search node kind"), Toolbar.Children[3].Kind, ECkUiNodeKind::Search);
    TestEqual(TEXT("Search binding retained"), Toolbar.Children[3].Binding, FString(TEXT("query")));
    TestEqual(TEXT("Image node kind"), Toolbar.Children[4].Kind, ECkUiNodeKind::Image);
    TestEqual(TEXT("Image binding retained"), Toolbar.Children[4].Binding, FString(TEXT("thumbnail")));
    const FCkUiNode& Scroll = Root->Children[1];
    TestEqual(TEXT("Scroll node kind"), Scroll.Kind, ECkUiNodeKind::Scroll);
    TestEqual(TEXT("Visibility binding retained"), Scroll.VisibilityBinding, FString(TEXT("has-results")));
    if (!TestEqual(TEXT("Scroll retains its sole child"), Scroll.Children.Num(), 1)) { return false; }
    TestEqual(TEXT("Bound text node kind"), Scroll.Children[0].Kind, ECkUiNodeKind::Text);
    TestEqual(TEXT("Text binding retained"), Scroll.Children[0].Binding, FString(TEXT("summary")));
    return true;
}

#endif
