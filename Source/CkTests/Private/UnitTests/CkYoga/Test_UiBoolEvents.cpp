#include "CkSlateLayout/CkUiWidgetRegistry.h"
#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/CkUiTreeCollection.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Misc/AutomationTest.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/Text/STextBlock.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_bool_events
{
    struct FProbe final
    {
        int32 FactoryCalls = 0;
        int32 FactoryDispatchAttempts = 0;
        bool CanDispatchDuringFactory = true;
        FCkUiCustomWidgetArguments Arguments;
    };

    auto Register(const TSharedRef<FProbe>& InProbe, FCkUiWidgetRegistry& InRegistry) -> bool
    {
        auto Registration = FCkUiCustomWidgetRegistration{};
        Registration.Schema.Tag = TEXT("bool-event-probe");
        Registration.Schema.Properties = {
            {TEXT("value"), ECkUiCustomPropertyKind::BoolBinding},
            {TEXT("changed"), ECkUiCustomPropertyKind::BoolChanged},
        };
        Registration.Factory = [InProbe](const FCkUiCustomWidgetArguments& InArguments, FString&) -> TSharedPtr<SWidget>
        {
            ++InProbe->FactoryCalls;
            InProbe->Arguments = InArguments;
            InProbe->CanDispatchDuringFactory = InArguments.CanDispatchEvents.Get();
            ++InProbe->FactoryDispatchAttempts;
            InArguments.BoolChanged.FindRef(TEXT("changed")).Execute(true);
            return SNew(STextBlock);
        };
        return InRegistry.Register(MoveTemp(Registration)).Succeeded;
    }

    auto RegisterOptionalEventProbe(const TSharedRef<FProbe>& InProbe, FCkUiWidgetRegistry& InRegistry) -> bool
    {
        auto Registration = FCkUiCustomWidgetRegistration{};
        Registration.Schema.Tag = TEXT("optional-bool-event-probe");
        Registration.Schema.Properties = {{TEXT("changed"), ECkUiCustomPropertyKind::BoolChanged, false}};
        Registration.Factory = [InProbe](const FCkUiCustomWidgetArguments&, FString&) -> TSharedPtr<SWidget>
        { ++InProbe->FactoryCalls; return SNew(STextBlock); };
        return InRegistry.Register(MoveTemp(Registration)).Succeeded;
    }

    auto Markup(const FString& InNode = TEXT("<bool-event-probe id=\"editor\" value-bind=\"value\" changed=\"changed\"/>")) -> FString
    {
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\">%s</column></region></ui>"), *InNode);
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiBoolEvents_CustomArgumentsAndAtomicity,
    "Ck.UiAuthoring.Custom.BoolEvents.ArgumentsAndAtomicity",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiBoolEvents_CustomArgumentsAndAtomicity::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_bool_events;
    const TSharedRef<FProbe> Probe = MakeShared<FProbe>();
    auto Registry = FCkUiWidgetRegistry{};
    if (!TestTrue(TEXT("Bool-event registry registration succeeds"), Register(Probe, Registry))) { return false; }
    if (!TestTrue(TEXT("Optional bool-event registry registration succeeds"), RegisterOptionalEventProbe(Probe, Registry))) { return false; }

    bool Value = false;
    int32 ChangedCalls = 0;
    bool ChangedPayload = false;
    auto Data = FCkUiView::FDataBindings{};
    Data.Visibility.Add(TEXT("value"), TAttribute<bool>::CreateLambda([&Value]() { return Value; }));
    Data.BoolChanged.Add(TEXT("changed"), FCkUiOnBoolChanged::CreateLambda([&ChangedCalls, &ChangedPayload](const bool InValue) { ++ChangedCalls; ChangedPayload = InValue; }));
    Data.BoolChanged.Add(TEXT("unbound"), FCkUiOnBoolChanged{});
    TSharedPtr<FCkUiView> View = FCkUiView::Create({}, {}, {}, FSlateFontInfo(), MoveTemp(Data), Registry.CreateSnapshot());
    const TSharedRef<SBox> Region = StaticCastSharedRef<SBox>(View->GetRegion(TEXT("main")));
    if (!TestTrue(TEXT("Bool-event document loads"), View->TryReload(Markup(), TEXT(""), TEXT("UiBoolEventsInitial")).Succeeded)) { return false; }
    const TSharedRef<SWidget> AcceptedRoot = Region->GetChildren()->GetChildAt(0);
    TestEqual(TEXT("Factory receives one typed bool event control"), Probe->FactoryCalls, 1);
    TestFalse(TEXT("Factory cannot dispatch bool events during staging"), Probe->CanDispatchDuringFactory);
    TestEqual(TEXT("Factory attempts bool dispatch during staging"), Probe->FactoryDispatchAttempts, 1);
    TestEqual(TEXT("Construction bool dispatch reaches no consumer"), ChangedCalls, 0);
    TestTrue(TEXT("Factory receives live bool binding"), Probe->Arguments.BoolBindings.Contains(TEXT("value")) && !Probe->Arguments.BoolBindings.FindRef(TEXT("value")).Get());
    TestTrue(TEXT("Factory receives bool-changed callback"), Probe->Arguments.BoolChanged.FindRef(TEXT("changed")).IsBound());
    TestTrue(TEXT("Arguments expose bool binding identity"), Probe->Arguments.BindingNames.FindRef(TEXT("value")) == TEXT("value") && Probe->Arguments.BindingNames.FindRef(TEXT("changed")) == TEXT("changed"));
    TestTrue(TEXT("Factory may dispatch bool events after accepted load"), Probe->Arguments.CanDispatchEvents.Get());
    Probe->Arguments.BoolChanged.FindRef(TEXT("changed")).Execute(true);
    TestEqual(TEXT("Bool changed callback reaches consumer"), ChangedCalls, 1);
    TestTrue(TEXT("Bool changed callback preserves true payload"), ChangedPayload);
    Probe->Arguments.BoolChanged.FindRef(TEXT("changed")).Execute(false);
    TestEqual(TEXT("Second bool changed callback reaches consumer"), ChangedCalls, 2);
    TestFalse(TEXT("Bool changed callback preserves false payload"), ChangedPayload);

    const int64 Revision = View->GetRevision();
    const int32 Factories = Probe->FactoryCalls;
    const auto Reject = [this, &View, &Probe, &Region, AcceptedRoot, Revision, Factories](const FString& InName, const FString& InMarkup)
    {
        const FCkUiLoadResult Result = View->TryReload(InMarkup, TEXT(""), InName);
        TestFalse(*InName, Result.Succeeded);
        TestTrue(*(InName + TEXT(" has a diagnostic")), !Result.Errors.IsEmpty());
        TestEqual(*(InName + TEXT(" preserves revision")), View->GetRevision(), Revision);
        TestTrue(*(InName + TEXT(" preserves mounted tree")), Region->GetChildren()->GetChildAt(0) == AcceptedRoot);
        TestEqual(*(InName + TEXT(" invokes no factory")), Probe->FactoryCalls, Factories);
    };
    Reject(TEXT("Missing required bool event rejects"), Markup(TEXT("<bool-event-probe id=\"editor\" value-bind=\"value\"/>")));
    Reject(TEXT("Missing bool event binding rejects"), Markup(TEXT("<bool-event-probe id=\"editor\" value-bind=\"value\" changed=\"missing\"/>")));
    Reject(TEXT("Supplied but unbound bool event rejects"), Markup(TEXT("<bool-event-probe id=\"editor\" value-bind=\"value\" changed=\"unbound\"/>")));

    auto Document = FCkUiDocument{};
    const FString TemplateMarkup = TEXT("<ui version=\"1\"><template name=\"editor\"><param name=\"value\" type=\"bool-binding\"/><param name=\"changed\" type=\"bool-changed\"/><bool-event-probe id=\"input\" value-bind-param=\"value\" changed-param=\"changed\"/></template><region name=\"main\"><use template=\"editor\" id=\"one\" value-bind=\"value\" changed=\"changed\"/></region></ui>");
    const FCkUiLoadResult TemplateResult = FCkUiDocumentParser::TryParse(TemplateMarkup, TEXT(""), {}, Document, TEXT("UiBoolEventsTemplate"), Registry.CreateSnapshot());
    const FCkUiNode* Root = Document.Regions.Find(TEXT("main"));
    TestTrue(TEXT("Bool-event template forwarding parses"), TemplateResult.Succeeded && Root != nullptr && Root->CustomProperties.FindRef(TEXT("changed")).Kind == ECkUiCustomPropertyKind::BoolChanged);
    TestTrue(TEXT("Bool-event template reload reaches real factory pipeline"), View->TryReload(TemplateMarkup, TEXT(""), TEXT("UiBoolEventsTemplateReload")).Succeeded);
    const int32 ChangedBeforeRelease = ChangedCalls;
    View.Reset();
    Probe->Arguments.BoolChanged.FindRef(TEXT("changed")).Execute(true);
    TestEqual(TEXT("Released view suppresses bool changed delivery"), ChangedCalls, ChangedBeforeRelease);

    auto Collection = TSharedPtr<FCkUiCollection>{};
    auto Tree = TSharedPtr<FCkUiTreeCollection>{};
    if (!TestTrue(TEXT("Readonly table collection creates"), FCkUiCollection::TryCreate({{TEXT("label"), ECkUiFieldKind::Text}}, Collection).Succeeded)
        || !TestTrue(TEXT("Readonly tree collection creates"), FCkUiTreeCollection::TryCreate({{TEXT("label"), ECkUiFieldKind::Text}}, Tree).Succeeded)) { return false; }
    auto ReadonlyData = FCkUiView::FDataBindings{};
    ReadonlyData.Collections.Add(TEXT("records"), Collection);
    ReadonlyData.Trees.Add(TEXT("nodes"), Tree);
    ReadonlyData.BoolChanged.Add(TEXT("changed"), FCkUiOnBoolChanged::CreateLambda([](const bool) {}));
    const TSharedRef<FCkUiView> ReadonlyView = FCkUiView::Create({}, {}, {}, FSlateFontInfo(), MoveTemp(ReadonlyData), Registry.CreateSnapshot());
    ReadonlyView->GetRegion(TEXT("main"));
    const int32 FactoriesBeforeReadonly = Probe->FactoryCalls;
    const FString TableMarkup = TEXT("<ui version=\"1\"><region name=\"main\"><table id=\"table\" bind=\"records\"><table-column id=\"column\" label=\"Label\"><optional-bool-event-probe id=\"cell\" changed=\"changed\"/></table-column></table></region></ui>");
    const FString TreeMarkup = TEXT("<ui version=\"1\"><region name=\"main\"><tree id=\"tree\" bind=\"nodes\"><row id=\"row\"><optional-bool-event-probe id=\"cell\" changed=\"changed\"/></row></tree></region></ui>");
    TestFalse(TEXT("Table rejects supplied optional bool event"), ReadonlyView->TryReload(TableMarkup, TEXT(""), TEXT("UiBoolEventsReadonlyTable")).Succeeded);
    TestFalse(TEXT("Tree rejects supplied optional bool event"), ReadonlyView->TryReload(TreeMarkup, TEXT(""), TEXT("UiBoolEventsReadonlyTree")).Succeeded);
    TestEqual(TEXT("Readonly bool event candidates invoke no factory"), Probe->FactoryCalls, FactoriesBeforeReadonly);
    return true;
}

#endif
