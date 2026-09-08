#include "CkSlateLayout/CkUiDocument.h"
#include "CkSlateLayout/CkUiWidgetRegistry.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Misc/AutomationTest.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/Text/STextBlock.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_templates
{
    auto Parse(const FString& InMarkup, FCkUiDocument& OutDocument, const TSharedPtr<const FCkUiWidgetRegistrySnapshot>& InRegistry = {}) -> FCkUiLoadResult
    {
        return FCkUiDocumentParser::TryParse(InMarkup, TEXT(".card { gap: 4px; }"), {}, OutDocument, TEXT("UiTemplateTest"), InRegistry);
    }

    auto ValidMarkup() -> FString
    {
        return TEXT("<ui version=\"1\"><template name=\"metric\"><param name=\"title\" type=\"text\"/><param name=\"value\" type=\"text-binding\"/><column id=\"card\" class=\"card\"><text id=\"title\" text-param=\"title\"/><text id=\"value\" bind-param=\"value\"/></column></template><region name=\"main\"><use template=\"metric\" id=\"cpu\" title=\"CPU\" value-bind=\"cpu\"/></region></ui>");
    }

    auto HasError(const FCkUiLoadResult& InResult) -> bool { return !InResult.Errors.IsEmpty(); }

    auto RegionContent(const TSharedRef<FCkUiView>& InView) -> TSharedRef<SWidget>
    {
        return StaticCastSharedRef<SBox>(InView->GetRegion(TEXT("main")))->GetChildren()->GetChildAt(0);
    }

    struct FCounts final { int32 Factories = 0; int32 Prepares = 0; int32 Commits = 0; int32 Actions = 0; TWeakPtr<SWidget> RetainedWidget; };
    class FUpdate final : public ICkUiPreparedWidgetUpdate
    {
    public:
        explicit FUpdate(const TSharedRef<FCounts>& InCounts) : Counts(InCounts) {}
        virtual void Commit() noexcept override { ++Counts->Commits; }
        TSharedRef<FCounts> Counts;
    };
    class FRetained final : public ICkUiRetainedWidget
    {
    public:
        explicit FRetained(const TSharedRef<FCounts>& InCounts) : Counts(InCounts), Widget(SNew(STextBlock).Text(FText::FromString(TEXT("retained")))) {}
        virtual auto GetWidget() const -> TSharedRef<SWidget> override { return Widget; }
        virtual auto PrepareReload(const FCkUiCustomWidgetArguments&, FString&) const -> TUniquePtr<ICkUiPreparedWidgetUpdate> override { ++Counts->Prepares; return MakeUnique<FUpdate>(Counts); }
        TSharedRef<FCounts> Counts;
        TSharedRef<STextBlock> Widget;
    };

    auto RegisterTypedProbe(FCkUiWidgetRegistry& InRegistry) -> bool
    {
        auto Registration = FCkUiCustomWidgetRegistration{};
        Registration.Schema.Tag = TEXT("probe");
        Registration.Schema.Properties = {
            {TEXT("title"), ECkUiCustomPropertyKind::Text}, {TEXT("rank"), ECkUiCustomPropertyKind::Number},
            {TEXT("enabled"), ECkUiCustomPropertyKind::Bool}, {TEXT("tone"), ECkUiCustomPropertyKind::Color},
            {TEXT("label"), ECkUiCustomPropertyKind::TextBinding}, {TEXT("action"), ECkUiCustomPropertyKind::Action}};
        Registration.Factory = [](const FCkUiCustomWidgetArguments&, FString&) -> TSharedPtr<SWidget> { return SNew(STextBlock); };
        return InRegistry.Register(MoveTemp(Registration)).Succeeded;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiTemplates_Parse,
    "Ck.UiAuthoring.Templates.ParseExpansionAndRejection",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiTemplates_Parse::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_templates;
    auto Document = FCkUiDocument{};
    const FCkUiLoadResult Valid = Parse(ValidMarkup(), Document);
    if (!TestTrue(TEXT("Typed template use expands"), Valid.Succeeded)) { return false; }
    const FCkUiNode* Root = Document.Regions.Find(TEXT("main"));
    if (!TestNotNull(TEXT("Expanded region exists"), Root)) { return false; }
    TestEqual(TEXT("Expanded root id is prefixed by use id"), Root->Id, FString(TEXT("cpu/card")));
    if (!TestEqual(TEXT("Expanded metric has two leaves"), Root->Children.Num(), 2)) { return false; }
    TestEqual(TEXT("Literal parameter becomes text"), Root->Children[0].Text, FString(TEXT("CPU")));
    TestEqual(TEXT("Binding parameter becomes binding"), Root->Children[1].Binding, FString(TEXT("cpu")));
    TestEqual(TEXT("Expanded child ids stay local to use"), Root->Children[1].Id, FString(TEXT("cpu/value")));
    TestEqual(TEXT("Template body CSS applies after expansion"), Root->Style.Gap, 4.0f);
    const FString Nested = TEXT("<ui version=\"1\"><template name=\"inner\"><param name=\"value\" type=\"text\"/><text id=\"leaf\" text-param=\"value\"/></template><template name=\"outer\"><param name=\"title\" type=\"text\"/><column id=\"card\"><use template=\"inner\" id=\"inner\" value-param=\"title\"/></column></template><region name=\"main\"><use template=\"outer\" id=\"cpu\" title=\"CPU\"/></region></ui>");
    auto NestedDocument = FCkUiDocument{};
    const FCkUiLoadResult NestedResult = Parse(Nested, NestedDocument);
    if (!TestTrue(TEXT("Nested template use expands"), NestedResult.Succeeded)) { return false; }
    const FCkUiNode* NestedRoot = NestedDocument.Regions.Find(TEXT("main"));
    if (!TestNotNull(TEXT("Nested expanded root exists"), NestedRoot) || !TestEqual(TEXT("Nested outer id is prefixed"), NestedRoot->Id, FString(TEXT("cpu/card"))) || !TestEqual(TEXT("Nested outer has inner leaf"), NestedRoot->Children.Num(), 1)) { return false; }
    TestEqual(TEXT("Nested leaf has complete use prefix"), NestedRoot->Children[0].Id, FString(TEXT("cpu/inner/leaf")));
    TestEqual(TEXT("Nested parameter forwarding retains literal text"), NestedRoot->Children[0].Text, FString(TEXT("CPU")));
    const int32 FirstTemplateEnd = Nested.Find(TEXT("</template>")) + FString(TEXT("</template>")).Len();
    const int32 RegionsStart = Nested.Find(TEXT("<region"));
    const FString ForwardReference = FString(TEXT("<ui version=\"1\">")) + Nested.Mid(FirstTemplateEnd, RegionsStart - FirstTemplateEnd)
        + Nested.Mid(FString(TEXT("<ui version=\"1\">")).Len(), FirstTemplateEnd - FString(TEXT("<ui version=\"1\">")).Len()) + Nested.Mid(RegionsStart);
    auto ForwardDocument = FCkUiDocument{};
    TestTrue(TEXT("Template signatures support forward declaration order"), Parse(ForwardReference, ForwardDocument).Succeeded);

    auto OrdinaryParentDocument = FCkUiDocument{};
    const FString OrdinaryParent = TEXT("<ui version=\"1\"><template name=\"item\"><text id=\"leaf\">value</text></template><region name=\"main\"><column id=\"root\"><use template=\"item\" id=\"first\"/><use template=\"item\" id=\"second\"/></column></region></ui>");
    if (!TestTrue(TEXT("Templates compose inside ordinary layout nodes"), Parse(OrdinaryParent, OrdinaryParentDocument).Succeeded)) { return false; }
    const FCkUiNode* OrdinaryRoot = OrdinaryParentDocument.Regions.Find(TEXT("main"));
    if (!TestNotNull(TEXT("Ordinary parent exists"), OrdinaryRoot) || !TestEqual(TEXT("Two instances emitted"), OrdinaryRoot->Children.Num(), 2)) { return false; }
    TestEqual(TEXT("First instance has independent identity"), OrdinaryRoot->Children[0].Id, FString(TEXT("first/leaf")));
    TestEqual(TEXT("Second instance has independent identity"), OrdinaryRoot->Children[1].Id, FString(TEXT("second/leaf")));

    auto BuiltinDocument = FCkUiDocument{};
    const FString Builtins = TEXT("<ui version=\"1\"><template name=\"controls\"><param name=\"query\" type=\"search-binding\"/><param name=\"picture\" type=\"image-binding\"/><param name=\"canvas\" type=\"native-binding\"/><param name=\"shown\" type=\"bool-binding\"/><param name=\"hint\" type=\"text\"/><column id=\"root\" visible-param=\"shown\"><search id=\"query\" bind-param=\"query\" placeholder-param=\"hint\"/><image id=\"image\" bind-param=\"picture\"/><native id=\"canvas\" bind-param=\"canvas\"/></column></template><region name=\"main\"><use template=\"controls\" id=\"controls\" query-bind=\"search\" picture-bind=\"preview\" canvas-bind=\"graph\" shown-bind=\"visible\" hint=\"Find resources\"/></region></ui>");
    if (!TestTrue(TEXT("Builtin parameter binding kinds expand"), Parse(Builtins, BuiltinDocument).Succeeded)) { return false; }
    const FCkUiNode* BuiltinRoot = BuiltinDocument.Regions.Find(TEXT("main"));
    if (!TestNotNull(TEXT("Builtin template root exists"), BuiltinRoot) || !TestEqual(TEXT("Three builtin controls emitted"), BuiltinRoot->Children.Num(), 3)) { return false; }
    TestEqual(TEXT("Visibility reference resolves"), BuiltinRoot->VisibilityBinding, FString(TEXT("visible")));
    TestEqual(TEXT("Search reference resolves"), BuiltinRoot->Children[0].Binding, FString(TEXT("search")));
    TestEqual(TEXT("Placeholder reference resolves"), BuiltinRoot->Children[0].Placeholder, FString(TEXT("Find resources")));
    TestEqual(TEXT("Image reference resolves"), BuiltinRoot->Children[1].Binding, FString(TEXT("preview")));
    TestEqual(TEXT("Native reference resolves"), BuiltinRoot->Children[2].Binding, FString(TEXT("graph")));

    auto TypedRegistry = FCkUiWidgetRegistry{};
    if (!TestTrue(TEXT("Typed custom template leaf registers"), RegisterTypedProbe(TypedRegistry))) { return false; }
    const FString TypedMarkup = TEXT("<ui version=\"1\"><template name=\"typed\"><param name=\"title\" type=\"text\"/><param name=\"rank\" type=\"number\"/><param name=\"enabled\" type=\"bool\"/><param name=\"tone\" type=\"color\"/><param name=\"label\" type=\"text-binding\"/><param name=\"action\" type=\"action\"/><probe id=\"leaf\" title-param=\"title\" rank-param=\"rank\" enabled-param=\"enabled\" tone-param=\"tone\" label-bind-param=\"label\" action-param=\"action\"/></template><region name=\"main\"><use template=\"typed\" id=\"cpu\" title=\"CPU\" rank=\"2.5\" enabled=\"true\" tone=\"#112233\" label-bind=\"model-label\" action=\"activate\"/></region></ui>");
    auto TypedDocument = FCkUiDocument{};
    const FCkUiLoadResult TypedResult = Parse(TypedMarkup, TypedDocument, TypedRegistry.CreateSnapshot());
    if (!TestTrue(TEXT("Typed literal and binding template arguments expand"), TypedResult.Succeeded)) { return false; }
    const FCkUiNode* TypedRoot = TypedDocument.Regions.Find(TEXT("main"));
    if (!TestNotNull(TEXT("Typed custom leaf exists"), TypedRoot)) { return false; }
    const FCkUiCustomPropertyValue* Rank = TypedRoot->CustomProperties.Find(TEXT("rank"));
    const FCkUiCustomPropertyValue* Enabled = TypedRoot->CustomProperties.Find(TEXT("enabled"));
    const FCkUiCustomPropertyValue* Tone = TypedRoot->CustomProperties.Find(TEXT("tone"));
    const FCkUiCustomPropertyValue* Label = TypedRoot->CustomProperties.Find(TEXT("label"));
    const FCkUiCustomPropertyValue* Action = TypedRoot->CustomProperties.Find(TEXT("action"));
    TestTrue(TEXT("Custom text literal forwarded"), TypedRoot->CustomProperties.FindRef(TEXT("title")).Text.EqualTo(FText::FromString(TEXT("CPU"))));
    TestTrue(TEXT("Custom number literal forwarded"), Rank != nullptr && Rank->Kind == ECkUiCustomPropertyKind::Number && FMath::IsNearlyEqual(Rank->Number, 2.5f));
    TestTrue(TEXT("Custom bool literal forwarded"), Enabled != nullptr && Enabled->Bool);
    TestTrue(TEXT("Custom color literal forwarded"), Tone != nullptr && Tone->Color.Equals(FLinearColor(FColor(0x11, 0x22, 0x33))));
    TestTrue(TEXT("Custom text binding forwarded"), Label != nullptr && Label->Name == TEXT("model-label"));
    TestTrue(TEXT("Custom action forwarded"), Action != nullptr && Action->Name == TEXT("activate"));
    auto EscapedDocument = FCkUiDocument{};
    const FCkUiLoadResult EscapedResult = Parse(ValidMarkup().Replace(TEXT("title=\"CPU\""), TEXT("title=\"&lt;button&gt;literal&lt;/button&gt;\"")), EscapedDocument);
    if (!TestTrue(TEXT("Escaped markup is accepted as literal parameter text"), EscapedResult.Succeeded)) { return false; }
    const FCkUiNode* EscapedRoot = EscapedDocument.Regions.Find(TEXT("main"));
    TestTrue(TEXT("Escaped markup remains text instead of a node"), EscapedRoot != nullptr && EscapedRoot->Children.Num() == 2 && EscapedRoot->Children[0].Text == TEXT("<button>literal</button>"));

    auto Existing = FCkUiDocument{};
    Existing.Regions.Add(TEXT("old"), FCkUiNode{.Id = TEXT("old-root")});
    const auto Reject = [this, &Existing](const FString& InName, const FString& InMarkup)
    {
        const FCkUiLoadResult Result = Parse(InMarkup, Existing);
        TestFalse(*InName, Result.Succeeded);
        TestTrue(*(InName + TEXT(" reports an error")), HasError(Result));
        TestTrue(*(InName + TEXT(" leaves prior output untouched")), Existing.Regions.Contains(TEXT("old")) && Existing.Regions.Num() == 1);
        const FCkUiNode* Old = Existing.Regions.Find(TEXT("old"));
        TestTrue(*(InName + TEXT(" preserves prior root fields")), Old != nullptr && Old->Id == TEXT("old-root"));
    };
    Reject(TEXT("Missing required template argument"), ValidMarkup().Replace(TEXT(" value-bind=\"cpu\""), TEXT("")));
    Reject(TEXT("Unknown template argument"), ValidMarkup().Replace(TEXT(" title=\"CPU\""), TEXT(" title=\"CPU\" typo=\"x\"")));
    Reject(TEXT("Binding type mismatch"), ValidMarkup().Replace(TEXT(" value-bind=\"cpu\""), TEXT(" value=\"cpu\"")));
    Reject(TEXT("Reference type must match target field"), ValidMarkup().Replace(TEXT("type=\"text-binding\""), TEXT("type=\"image-binding\"")));
    Reject(TEXT("Expanded id collides with ordinary authored id"), TEXT("<ui version=\"1\"><template name=\"item\"><text id=\"leaf\">value</text></template><region name=\"main\"><column id=\"root\"><use template=\"item\" id=\"one\"/><text id=\"one/leaf\">collision</text></column></region></ui>"));
    Reject(TEXT("Conflicting parameter reference"), TEXT("<ui version=\"1\"><template name=\"t\"><param name=\"title\" type=\"text\"/><text id=\"title\" text-param=\"title\">literal</text></template><region name=\"main\"><use template=\"t\" id=\"one\" title=\"CPU\"/></region></ui>"));
    Reject(TEXT("Duplicate template definition"), TEXT("<ui version=\"1\"><template name=\"a\"><text id=\"x\">x</text></template><template name=\"a\"><text id=\"x\">x</text></template><region name=\"main\"><use template=\"a\" id=\"a\"/></region></ui>"));
    Reject(TEXT("Duplicate template parameter"), TEXT("<ui version=\"1\"><template name=\"a\"><param name=\"x\" type=\"text\"/><param name=\"x\" type=\"text\"/><text id=\"x\">x</text></template><region name=\"main\"><use template=\"a\" id=\"a\" x=\"x\"/></region></ui>"));
    Reject(TEXT("Duplicate template local id"), TEXT("<ui version=\"1\"><template name=\"a\"><column id=\"x\"><text id=\"x\">x</text></column></template><region name=\"main\"><use template=\"a\" id=\"a\"/></region></ui>"));
    Reject(TEXT("Expanded id collision rejects"), TEXT("<ui version=\"1\"><template name=\"a\"><text id=\"leaf\">x</text></template><region name=\"main\"><column id=\"root\"><use template=\"a\" id=\"same\"/><use template=\"a\" id=\"same\"/></column></region></ui>"));
    Reject(TEXT("Unused invalid template validates"), TEXT("<ui version=\"1\"><template name=\"bad\"><param name=\"x\" type=\"unknown\"/><text id=\"x\">x</text></template><region name=\"main\"><text id=\"ok\">ok</text></region></ui>"));
    Reject(TEXT("Template cycle rejects"), TEXT("<ui version=\"1\"><template name=\"a\"><use template=\"b\" id=\"b\"/></template><template name=\"b\"><use template=\"a\" id=\"a\"/></template><region name=\"main\"><use template=\"a\" id=\"root\"/></region></ui>"));
    Reject(TEXT("Unused bad parameter reference validates"), TEXT("<ui version=\"1\"><template name=\"bad\"><param name=\"x\" type=\"text\"/><text id=\"x\" text-param=\"missing\"/></template><region name=\"main\"><text id=\"ok\">ok</text></region></ui>"));
    Reject(TEXT("Unused template validates required builtin action"), TEXT("<ui version=\"1\"><template name=\"bad\"><button id=\"action\">Missing action</button></template><region name=\"main\"><text id=\"ok\">ok</text></region></ui>"));
    Reject(TEXT("Unused template validates unsupported body style"), TEXT("<ui version=\"1\"><template name=\"bad\"><text id=\"leaf\" class=\"card\">Invalid gap on text</text></template><region name=\"main\"><text id=\"ok\">ok</text></region></ui>"));
    Reject(TEXT("Structural ids cannot use parameters"), TEXT("<ui version=\"1\"><template name=\"bad\"><param name=\"name\" type=\"text\"/><text id-param=\"name\">Invalid id reference</text></template><region name=\"main\"><use template=\"bad\" id=\"root\" name=\"leaf\"/></region></ui>"));
    Reject(TEXT("Unused template cycle validates"), TEXT("<ui version=\"1\"><template name=\"a\"><use template=\"b\" id=\"b\"/></template><template name=\"b\"><use template=\"a\" id=\"a\"/></template><region name=\"main\"><text id=\"ok\">ok</text></region></ui>"));
    for (const FString& BadNumber : {FString(TEXT("NaN")), FString(TEXT("1junk"))})
    {
        auto NumericOutput = FCkUiDocument{};
        NumericOutput.Regions.Add(TEXT("old"), FCkUiNode{.Id = TEXT("old-root")});
        const FString NumericMarkup = FString::Printf(TEXT("<ui version=\"1\"><template name=\"numeric\"><param name=\"rank\" type=\"number\"/><probe id=\"leaf\" title=\"ok\" rank-param=\"rank\" enabled=\"true\" tone=\"#ffffff\" label-bind=\"label\" action=\"act\"/></template><region name=\"main\"><use template=\"numeric\" id=\"one\" rank=\"%s\"/></region></ui>"), *BadNumber);
        const FCkUiLoadResult NumericResult = Parse(NumericMarkup, NumericOutput, TypedRegistry.CreateSnapshot());
        TestFalse(*FString::Printf(TEXT("Typed numeric %s rejects"), *BadNumber), NumericResult.Succeeded);
        TestTrue(*FString::Printf(TEXT("Typed numeric %s preserves output"), *BadNumber), NumericOutput.Regions.Contains(TEXT("old")) && NumericOutput.Regions.Num() == 1);
    }
    FString LargeMarkup = TEXT("<ui version=\"1\"><template name=\"pair\"><column id=\"pair\"><text id=\"a\">a</text><text id=\"b\">b</text></column></template><region name=\"main\"><column id=\"root\">");
    for (int32 Index = 0; Index < 257; ++Index) { LargeMarkup += FString::Printf(TEXT("<use template=\"pair\" id=\"u%d\"/>"), Index); }
    LargeMarkup += TEXT("</column></region></ui>");
    Reject(TEXT("Expanded template node limit rejects"), LargeMarkup);
    FString DeepMarkup = TEXT("<ui version=\"1\">");
    for (int32 Index = 0; Index < 34; ++Index)
    {
        if (Index == 33) { DeepMarkup += FString::Printf(TEXT("<template name=\"t%d\"><text id=\"leaf\">leaf</text></template>"), Index); }
        else { DeepMarkup += FString::Printf(TEXT("<template name=\"t%d\"><column id=\"node\"><use template=\"t%d\" id=\"next\"/></column></template>"), Index, Index + 1); }
    }
    DeepMarkup += TEXT("<region name=\"main\"><use template=\"t0\" id=\"root\"/></region></ui>");
    Reject(TEXT("Expanded template depth limit rejects"), DeepMarkup);
    FString Boundary = TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\">");
    for (int32 Index = 0; Index < 511; ++Index) { Boundary += FString::Printf(TEXT("<text id=\"n%d\">value</text>"), Index); }
    auto BoundaryDocument = FCkUiDocument{};
    TestTrue(TEXT("Ordinary 512-node document stays accepted"), Parse(Boundary + TEXT("</column></region></ui>"), BoundaryDocument).Succeeded);
    Reject(TEXT("Ordinary 513-node document rejects"), Boundary + TEXT("<text id=\"extra\">extra</text></column></region></ui>"));
    FString UnusedLarge = TEXT("<ui version=\"1\"><template name=\"unused\"><column id=\"root\">");
    for (int32 Index = 0; Index < 513; ++Index) { UnusedLarge += FString::Printf(TEXT("<text id=\"n%d\">value</text>"), Index); }
    Reject(TEXT("Unused declarations obey source node budget"), UnusedLarge + TEXT("</column></template><region name=\"main\"><text id=\"ok\">ok</text></region></ui>"));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiTemplates_ViewAtomicity,
    "Ck.UiAuthoring.Templates.ViewAtomicity",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiTemplates_ViewAtomicity::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_templates;
    const TSharedRef<FCounts> Counts = MakeShared<FCounts>();
    auto Registry = FCkUiWidgetRegistry{};
    auto Registration = FCkUiCustomWidgetRegistration{};
    Registration.Schema.Tag = TEXT("retained");
    Registration.RetainedFactory = [Counts](const FCkUiCustomWidgetArguments&, FString&) -> TSharedPtr<ICkUiRetainedWidget>
    { ++Counts->Factories; const TSharedRef<FRetained> Component = MakeShared<FRetained>(Counts); Counts->RetainedWidget = Component->Widget; return Component; };
    if (!TestTrue(TEXT("Retained template factory registers"), Registry.Register(MoveTemp(Registration)).Succeeded)) { return false; }
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {{TEXT("act"), FSimpleDelegate::CreateLambda([Counts] { ++Counts->Actions; })}}, {}, FSlateFontInfo{}, {}, Registry.CreateSnapshot());
    View->GetRegion(TEXT("main"));
    const FString Accepted = TEXT("<ui version=\"1\"><template name=\"card\"><column id=\"card\"><retained id=\"leaf\"/><button id=\"action\" action=\"act\">Act</button></column></template><region name=\"main\"><use template=\"card\" id=\"one\"/></region></ui>");
    if (!TestTrue(TEXT("Template view initial load succeeds"), View->TryReload(Accepted, TEXT(""), TEXT("TemplateViewInitial")).Succeeded)) { return false; }
    const TSharedRef<SWidget> Root = RegionContent(View);
    const TSharedPtr<SWidget> RetainedWidget = Counts->RetainedWidget.Pin();
    if (!TestTrue(TEXT("Initial retained template exposes its underlying widget"), RetainedWidget.IsValid())) { return false; }
    const int64 Revision = View->GetRevision();
    const int32 Factories = Counts->Factories;
    const int32 Prepares = Counts->Prepares;
    const int32 Commits = Counts->Commits;
    const FString Malformed = TEXT("<ui version=\"1\"><template name=\"card\"><column id=\"card\"><retained id=\"leaf\"/><button id=\"action\" action=\"act\">Act</button></column></template><region name=\"main\"><column id=\"outer\"><use template=\"card\" id=\"one\"/><use template=\"missing\" id=\"late\"/></column></region></ui>");
    const FCkUiLoadResult Rejected = View->TryReload(Malformed, TEXT(""), TEXT("TemplateViewMalformed"));
    TestFalse(TEXT("Late unknown template reload rejects"), Rejected.Succeeded);
    TestTrue(TEXT("Malformed template reports errors"), HasError(Rejected));
    TestEqual(TEXT("Malformed template preserves revision"), View->GetRevision(), Revision);
    TestTrue(TEXT("Malformed template preserves mounted root"), RegionContent(View) == Root);
    TestEqual(TEXT("Malformed template invokes no factory"), Counts->Factories, Factories);
    TestEqual(TEXT("Malformed template invokes no prepare"), Counts->Prepares, Prepares);
    TestEqual(TEXT("Malformed template invokes no commit"), Counts->Commits, Commits);
    TestEqual(TEXT("Rejected template emits no action"), Counts->Actions, 0);
    const FString Reloaded = TEXT("<ui version=\"1\"><template name=\"card\"><column id=\"card\"><retained id=\"leaf\"/><text id=\"note\">reloaded</text></column></template><region name=\"main\"><use template=\"card\" id=\"one\"/></region></ui>");
    if (!TestTrue(TEXT("Accepted template reload succeeds"), View->TryReload(Reloaded, TEXT(""), TEXT("TemplateViewReload")).Succeeded)) { return false; }
    const TSharedPtr<SWidget> ReloadedWidget = Counts->RetainedWidget.Pin();
    TestTrue(TEXT("Accepted template reload preserves retained widget identity"), ReloadedWidget.IsValid() && ReloadedWidget == RetainedWidget);
    TestEqual(TEXT("Accepted retained reload prepares once"), Counts->Prepares, Prepares + 1);
    TestEqual(TEXT("Accepted retained reload commits once"), Counts->Commits, Commits + 1);
    return true;
}

#endif
