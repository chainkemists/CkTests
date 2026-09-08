#include "CkSlateLayout/CkFlexText.h"
#include "CkSlateLayout/CkUiDocument.h"
#include "CkSlateLayout/CkUiWidgetRegistry.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Misc/AutomationTest.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/Text/STextBlock.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_button_enabled
{
    struct FProbe final { int32 FactoryCalls = 0; };

    auto RegisterProbe(const TSharedRef<FProbe>& InProbe, FCkUiWidgetRegistry& InRegistry) -> bool
    {
        auto Registration = FCkUiCustomWidgetRegistration{};
        Registration.Schema.Tag = TEXT("button-enabled-probe");
        Registration.Factory = [InProbe](const FCkUiCustomWidgetArguments&, FString&) -> TSharedPtr<SWidget>
        { ++InProbe->FactoryCalls; return SNew(STextBlock); };
        return InRegistry.Register(MoveTemp(Registration)).Succeeded;
    }

    auto FindButton(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SButton>
    {
        if (InRoot->GetTag() == InTag && InRoot->GetTypeAsString() == TEXT("SButton")) { return StaticCastSharedRef<SButton>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SButton> Found = FindButton(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag); Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto Markup(const FString& InBody) -> FString
    {
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\">%s</column></region></ui>"), *InBody);
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiButtonEnabled_ParserAndNativeGate,
    "Ck.UiAuthoring.Button.EnabledBinding.ParserAndNativeGate",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiButtonEnabled_ParserAndNativeGate::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_button_enabled;

    auto DirectDocument = FCkUiDocument{};
    const FCkUiLoadResult DirectResult = FCkUiDocumentParser::TryParse(
        Markup(TEXT("<button id=\"clear\" action=\"clear\" enabled-bind=\"has-selection\">Clear</button>")), TEXT(""), {}, DirectDocument, TEXT("UiButtonEnabledDirect"));
    const FCkUiNode* DirectRoot = DirectDocument.Regions.Find(TEXT("main"));
    TestTrue(TEXT("Ordinary button enabled binding parses"), DirectResult.Succeeded && DirectRoot != nullptr && DirectRoot->Children.Num() == 1
        && DirectRoot->Children[0].ButtonEnabledBinding == TEXT("has-selection"));

    auto Document = FCkUiDocument{};
    const FString TemplateMarkup = TEXT("<ui version=\"1\"><template name=\"clear-button\"><param name=\"enabled\" type=\"bool-binding\"/><param name=\"label\" type=\"text-binding\"/><button id=\"clear\" action=\"clear\" enabled-bind-param=\"enabled\" bind-param=\"label\"/></template><region name=\"main\"><use template=\"clear-button\" id=\"selection\" enabled-bind=\"has-selection\" label-bind=\"label\"/></region></ui>");
    const FCkUiLoadResult TemplateResult = FCkUiDocumentParser::TryParse(TemplateMarkup, TEXT(""), {}, Document, TEXT("UiButtonEnabledTemplate"));
    const FCkUiNode* TemplateButton = Document.Regions.Find(TEXT("main"));
    TestTrue(TEXT("Button enabled binding parses through template forwarding"), TemplateResult.Succeeded && TemplateButton != nullptr
        && TemplateButton->Kind == ECkUiNodeKind::Button && TemplateButton->ButtonEnabledBinding == TEXT("has-selection")
        && TemplateButton->Binding == TEXT("label"));

    const TSharedRef<FProbe> Probe = MakeShared<FProbe>();
    auto Registry = FCkUiWidgetRegistry{};
    if (!TestTrue(TEXT("Button enabled probe registration succeeds"), RegisterProbe(Probe, Registry))) { return false; }

    bool HasSelection = false;
    FText Label = NSLOCTEXT("CkUiButtonTest", "InitialLabel", "Clear selection");
    int32 ClearCalls = 0;
    auto Data = FCkUiView::FDataBindings{};
    Data.Text.Add(TEXT("label"), TAttribute<FText>::CreateLambda([&Label]() { return Label; }));
    Data.Visibility.Add(TEXT("has-selection"), TAttribute<bool>::CreateLambda([&HasSelection]() { return HasSelection; }));
    auto Actions = FCkUiView::FActions{};
    Actions.Add(TEXT("clear"), FSimpleDelegate::CreateLambda([&ClearCalls]() { ++ClearCalls; }));
    TSharedPtr<FCkUiView> View = FCkUiView::Create({}, MoveTemp(Actions), {}, FSlateFontInfo(), MoveTemp(Data), Registry.CreateSnapshot());
    const TSharedRef<SBox> Region = StaticCastSharedRef<SBox>(View->GetRegion(TEXT("main")));
    const FString InitialMarkup = Markup(TEXT("<button id=\"clear\" action=\"clear\" bind=\"label\" enabled-bind=\"has-selection\"/>"));
    if (!TestTrue(TEXT("Enabled button document loads"), View->TryReload(InitialMarkup, TEXT(""), TEXT("UiButtonEnabledInitial")).Succeeded)) { return false; }
    const TSharedRef<SWidget> AcceptedRoot = Region->GetChildren()->GetChildAt(0);
    const int64 AcceptedRevision = View->GetRevision();
    const TSharedPtr<SButton> Button = FindButton(AcceptedRoot, TEXT("clear"));
    if (!TestTrue(TEXT("Authored button is mounted"), Button.IsValid())) { return false; }

    // IsEnabled reads Slate's cached attribute; prepass evaluates the bound value.
    Button->SlatePrepass(1.0f);
    const FChildren* ButtonChildren = Button->GetChildren();
    if (!TestTrue(TEXT("Authored button contains its native text label"), ButtonChildren != nullptr
        && ButtonChildren->Num() == 1 && ButtonChildren->GetChildAt(0)->GetTypeAsString() == TEXT("SCkFlexText"))) { return false; }
    const TSharedRef<SCkFlexText> LabelWidget = StaticCastSharedRef<SCkFlexText>(ConstCastSharedRef<SWidget>(ButtonChildren->GetChildAt(0)));
    TestTrue(TEXT("Button retains localized bound text"), LabelWidget->GetText().IdenticalTo(Label));
    Label = NSLOCTEXT("CkUiButtonTest", "UpdatedLabel", "Clear selected component");
    Button->SlatePrepass(1.0f);
    TestTrue(TEXT("Button updates its existing native label from live text"), LabelWidget->GetText().IdenticalTo(Label));
    TestFalse(TEXT("Native button reflects initially false enabled binding"), Button->IsEnabled());
    Button->SimulateClick();
    TestEqual(TEXT("Disabled SimulateClick cannot dispatch action"), ClearCalls, 0);

    HasSelection = true;
    Button->SlatePrepass(1.0f);
    TestTrue(TEXT("Native button reflects live enabled binding"), Button->IsEnabled());
    Button->SimulateClick();
    TestEqual(TEXT("Enabled native button dispatches action"), ClearCalls, 1);

    HasSelection = false;
    Button->SimulateClick();
    TestEqual(TEXT("Dispatch-time enabled gate rejects a stale simulated click"), ClearCalls, 1);

    const FString MissingBindingMarkup = Markup(TEXT("<button id=\"clear\" action=\"clear\" enabled-bind=\"missing\">Clear</button><button-enabled-probe id=\"probe\"/>"));
    const auto MissingLabel = View->TryReload(Markup(TEXT("<button id=\"clear\" action=\"clear\" bind=\"missing-label\"/><button-enabled-probe id=\"probe\"/>")), TEXT(""), TEXT("UiButtonMissingLabel"));
    TestFalse(TEXT("Missing button label binding rejects before publication"), MissingLabel.Succeeded);
    TestEqual(TEXT("Missing label invokes no custom factory"), Probe->FactoryCalls, 0);
    const FCkUiLoadResult MissingBinding = View->TryReload(MissingBindingMarkup, TEXT(""), TEXT("UiButtonEnabledMissing"));
    TestFalse(TEXT("Missing enabled binding rejects before publication"), MissingBinding.Succeeded);
    TestTrue(TEXT("Missing enabled binding reports a diagnostic"), !MissingBinding.Errors.IsEmpty());
    TestEqual(TEXT("Missing enabled binding preserves revision"), View->GetRevision(), AcceptedRevision);
    TestTrue(TEXT("Missing enabled binding preserves mounted root"), Region->GetChildren()->GetChildAt(0) == AcceptedRoot);
    TestEqual(TEXT("Missing enabled binding invokes no custom factory"), Probe->FactoryCalls, 0);

    HasSelection = true;
    const FString ReplacementMarkup = Markup(TEXT("<button id=\"replacement\" action=\"clear\">Replacement</button>"));
    if (!TestTrue(TEXT("Accepted reload succeeds"), View->TryReload(ReplacementMarkup, TEXT(""), TEXT("UiButtonEnabledReplacement")).Succeeded)) { return false; }
    Button->SimulateClick();
    TestEqual(TEXT("Old button cannot dispatch after accepted reload"), ClearCalls, 1);

    const TSharedPtr<SButton> Replacement = FindButton(Region->GetChildren()->GetChildAt(0), TEXT("replacement"));
    if (!TestTrue(TEXT("Replacement button is mounted"), Replacement.IsValid())) { return false; }
    Replacement->SimulateClick();
    TestEqual(TEXT("Replacement button dispatches after accepted reload"), ClearCalls, 2);
    View.Reset();
    Replacement->SimulateClick();
    TestEqual(TEXT("Released view suppresses native button callback"), ClearCalls, 2);
    return true;
}

#endif
