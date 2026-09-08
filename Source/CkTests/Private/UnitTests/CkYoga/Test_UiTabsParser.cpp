#include "CkSlateLayout/CkUiDocument.h"
#include "CkSlateLayout/CkUiWidgetRegistry.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiTabs_Parser,
    "Ck.UiAuthoring.Tabs.ParserSchema",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiTabs_Parser::RunTest(const FString&) -> bool
{
    const auto Wrap = [](const FString& InBody)
    { return TEXT("<ui version=\"1\"><region name=\"main\">") + InBody + TEXT("</region></ui>"); };
    const FString Valid = Wrap(TEXT("<tabs id=\"details\" class=\"fill\" value-bind=\"active-tab\" changed=\"set-active-tab\"><tab id=\"overview\" class=\"panel\" key=\"overview\" label=\"Overview\"><text id=\"facts\">Facts</text></tab><tab id=\"properties\" key=\"properties\" label-bind=\"properties-label\" enabled-bind=\"can-edit\"><column id=\"form\"/></tab></tabs>"));
    FCkUiDocument Document;
    int32 Factories = 0;
    FCkUiWidgetRegistry Registry;
    auto Probe = FCkUiCustomWidgetRegistration{};
    Probe.Schema.Tag = TEXT("probe");
    Probe.Factory = [&Factories](const FCkUiCustomWidgetArguments&, FString&) -> TSharedPtr<SWidget> { ++Factories; return {}; };
    if (!TestTrue(TEXT("Probe factory registers"), Registry.Register(MoveTemp(Probe)).Succeeded)) { return false; }
    const auto Parse = [&Document](const FString& InMarkup)
    { return FCkUiDocumentParser::TryParse(InMarkup, TEXT(".fill { flex-grow: 1; } .panel { gap: 4px; padding: 2px; background-color: #000000; color: #ffffff; }"), {}, Document, TEXT("TabsParserTest")); };

    const FCkUiLoadResult Accepted = Parse(Valid);
    if (!TestTrue(TEXT("Valid tabs document parses"), Accepted.Succeeded))
    { for (const FString& Error : Accepted.Errors) { AddError(Error); } return false; }
    const FCkUiNode* Tabs = Document.Regions.Find(TEXT("main"));
    if (!TestTrue(TEXT("Tabs node and two panels are retained"), Tabs != nullptr && Tabs->Kind == ECkUiNodeKind::Tabs && Tabs->Children.Num() == 2)) { return false; }
    TestEqual(TEXT("Tabs value binding uses FString transport"), Tabs->Binding, FString(TEXT("active-tab")));
    TestEqual(TEXT("Tabs changed callback is retained"), Tabs->Action, FString(TEXT("set-active-tab")));
    TestEqual(TEXT("Literal tab key is retained"), Tabs->Children[0].TabKey, FString(TEXT("overview")));
    TestEqual(TEXT("Literal tab label is stored as text"), Tabs->Children[0].Text, FString(TEXT("Overview")));
    TestEqual(TEXT("Bound label is retained"), Tabs->Children[1].TabLabelBinding, FString(TEXT("properties-label")));
    TestEqual(TEXT("Enabled binding is retained"), Tabs->Children[1].TabEnabledBinding, FString(TEXT("can-edit")));
    TestEqual(TEXT("Tabs accepts flex growth"), Tabs->Style.Grow, 1.0f);
    TestEqual(TEXT("Tab accepts panel gap styling"), Tabs->Children[0].Style.Gap, 4.0f);
    TestTrue(TEXT("Tab accepts header text styling"), Tabs->Children[0].Style.Color.IsSet());
    TestTrue(TEXT("Tab body remains ordinary authored layout"), Tabs->Children[1].Children.Num() == 1 && Tabs->Children[1].Children[0].Kind == ECkUiNodeKind::Column);

    const FCkUiNode Prior = *Tabs;
    const TArray<FString> Rejected = {
        Wrap(TEXT("<tabs id=\"tabs\" changed=\"changed\"><tab id=\"one\" key=\"one\" label=\"One\"/></tabs>")),
        Wrap(TEXT("<tabs id=\"tabs\" value-bind=\"value\"><tab id=\"one\" key=\"one\" label=\"One\"/></tabs>")),
        Wrap(TEXT("<tabs id=\"tabs\" value-bind=\"value\" changed=\"changed\"/>")),
        Wrap(TEXT("<tabs id=\"tabs\" value-bind=\"value\" changed=\"changed\"><text id=\"wrong\">Wrong</text></tabs>")),
        Wrap(TEXT("<column id=\"root\"><tab id=\"wrong\" key=\"one\" label=\"One\"/></column>")),
        Wrap(TEXT("<tabs id=\"tabs\" value-bind=\"value\" changed=\"changed\"><tab id=\"one\" key=\"one\"/><tab id=\"two\" key=\"two\" label=\"Two\"/></tabs>")),
        Wrap(TEXT("<tabs id=\"tabs\" value-bind=\"value\" changed=\"changed\"><tab id=\"one\" key=\"one\" label=\"One\" label-bind=\"one-label\"/></tabs>")),
        Wrap(TEXT("<tabs id=\"tabs\" value-bind=\"value\" changed=\"changed\"><tab id=\"one\" key=\"one\" label=\"One\"/><tab id=\"two\" key=\"one\" label=\"Two\"/></tabs>")),
        Wrap(TEXT("<tabs id=\"tabs\" value-bind=\"value\" changed=\"changed\"><tab id=\"one\" key=\"  \" label=\"One\"/></tabs>"))
    };
    for (const FString& Markup : Rejected)
    {
        const FCkUiLoadResult Result = Parse(Markup);
        TestFalse(TEXT("Malformed tabs declaration rejects"), Result.Succeeded);
        TestTrue(TEXT("Malformed tabs declaration reports diagnostic"), !Result.Errors.IsEmpty());
        const FCkUiNode* Unchanged = Document.Regions.Find(TEXT("main"));
        TestTrue(TEXT("Malformed tabs declaration leaves document untouched"), Unchanged != nullptr && Unchanged->Id == Prior.Id && Unchanged->Children.Num() == Prior.Children.Num());
    }

    const FCkUiLoadResult FactoryRejected = FCkUiDocumentParser::TryParse(
        Wrap(TEXT("<tabs id=\"tabs\" value-bind=\"value\" changed=\"changed\"><probe id=\"factory\"/></tabs>")),
        TEXT(""), {}, Document, TEXT("TabsParserFactoryTest"), Registry.CreateSnapshot());
    TestFalse(TEXT("Misplaced custom node rejects before publication"), FactoryRejected.Succeeded);
    TestEqual(TEXT("Malformed tabs declarations invoke no custom factories"), Factories, 0);

    const FString Templated = TEXT("<ui version=\"1\"><template name=\"tabs-body\"><param name=\"value\" type=\"string-binding\"/><param name=\"changed\" type=\"string-changed\"/><param name=\"label\" type=\"text-binding\"/><param name=\"enabled\" type=\"bool-binding\"/><tabs id=\"tabs\" value-bind-param=\"value\" changed-param=\"changed\"><tab id=\"one\" key=\"one\" label-bind-param=\"label\" enabled-bind-param=\"enabled\"/></tabs></template><region name=\"main\"><use id=\"instance\" template=\"tabs-body\" value-bind=\"active\" changed=\"changed\" label-bind=\"label\" enabled-bind=\"enabled\"/></region></ui>");
    const FCkUiLoadResult TemplatedResult = Parse(Templated);
    TestTrue(TEXT("Typed tabs template bindings parse"), TemplatedResult.Succeeded);
    return true;
}

#endif
