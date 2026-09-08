#include "CkSlateLayout/CkUiWidgetRegistry.h"
#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/CkUiTreeCollection.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Misc/AutomationTest.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/Text/STextBlock.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_text_events
{
    struct FProbe final
    {
        int32 FactoryCalls = 0;
        int32 FactoryChangedAttempts = 0;
        int32 FactoryCommittedAttempts = 0;
        bool CanDispatchDuringFactory = true;
        FCkUiCustomWidgetArguments Arguments;
    };

    auto Register(const TSharedRef<FProbe>& InProbe, FCkUiWidgetRegistry& InRegistry) -> bool
    {
        auto Registration = FCkUiCustomWidgetRegistration{};
        Registration.Schema.Tag = TEXT("text-event-probe");
        Registration.Schema.Properties = {
            {TEXT("value"), ECkUiCustomPropertyKind::TextBinding},
            {TEXT("changed"), ECkUiCustomPropertyKind::TextChanged},
            {TEXT("committed"), ECkUiCustomPropertyKind::TextCommitted},
        };
        Registration.Factory = [InProbe](const FCkUiCustomWidgetArguments& InArguments, FString&) -> TSharedPtr<SWidget>
        {
            ++InProbe->FactoryCalls;
            InProbe->Arguments = InArguments;
            InProbe->CanDispatchDuringFactory = InArguments.CanDispatchEvents.Get();
            ++InProbe->FactoryChangedAttempts;
            InArguments.TextChanged.FindRef(TEXT("changed")).Execute(FText::FromString(TEXT("construction")));
            ++InProbe->FactoryCommittedAttempts;
            InArguments.TextCommitted.FindRef(TEXT("committed")).Execute(FText::FromString(TEXT("construction")), ETextCommit::OnEnter);
            return SNew(STextBlock);
        };
        return InRegistry.Register(MoveTemp(Registration)).Succeeded;
    }

    auto RegisterOptionalEventProbe(const TSharedRef<FProbe>& InProbe, FCkUiWidgetRegistry& InRegistry) -> bool
    {
        auto Registration = FCkUiCustomWidgetRegistration{};
        Registration.Schema.Tag = TEXT("optional-event-probe");
        Registration.Schema.Properties = {{TEXT("changed"), ECkUiCustomPropertyKind::TextChanged, false}};
        Registration.Factory = [InProbe](const FCkUiCustomWidgetArguments&, FString&) -> TSharedPtr<SWidget>
        { ++InProbe->FactoryCalls; return SNew(STextBlock); };
        return InRegistry.Register(MoveTemp(Registration)).Succeeded;
    }

    auto Markup(const FString& InNode = TEXT("<text-event-probe id=\"editor\" value-bind=\"value\" changed=\"changed\" committed=\"committed\"/>")) -> FString
    {
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\">%s</column></region></ui>"), *InNode);
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiTextEvents_CustomArgumentsAndAtomicity,
    "Ck.UiAuthoring.Custom.TextEvents.ArgumentsAndAtomicity",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiTextEvents_CustomArgumentsAndAtomicity::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_text_events;
    const TSharedRef<FProbe> Probe = MakeShared<FProbe>();
    auto Registry = FCkUiWidgetRegistry{};
    if (!TestTrue(TEXT("Text-event registry registration succeeds"), Register(Probe, Registry))) { return false; }
    if (!TestTrue(TEXT("Optional event registry registration succeeds"), RegisterOptionalEventProbe(Probe, Registry))) { return false; }

    auto Data = FCkUiView::FDataBindings{};
    Data.Text.Add(TEXT("value"), TAttribute<FText>::CreateLambda([] { return FText::FromString(TEXT("initial")); }));
    int32 ChangedCalls = 0;
    int32 CommittedCalls = 0;
    FString ChangedPayload;
    FString CommittedPayload;
    ETextCommit::Type CommitReason = ETextCommit::Default;
    Data.TextChanged.Add(TEXT("changed"), FOnTextChanged::CreateLambda([&ChangedCalls, &ChangedPayload](const FText& InText) { ++ChangedCalls; ChangedPayload = InText.ToString(); }));
    Data.TextCommitted.Add(TEXT("committed"), FOnTextCommitted::CreateLambda([&CommittedCalls, &CommittedPayload, &CommitReason](const FText& InText, const ETextCommit::Type InReason) { ++CommittedCalls; CommittedPayload = InText.ToString(); CommitReason = InReason; }));
    Data.TextChanged.Add(TEXT("unbound"), FOnTextChanged{});
    TSharedPtr<FCkUiView> View = FCkUiView::Create({}, {}, {}, FSlateFontInfo(), MoveTemp(Data), Registry.CreateSnapshot());
    const TSharedRef<SBox> Region = StaticCastSharedRef<SBox>(View->GetRegion(TEXT("main")));
    if (!TestTrue(TEXT("Text-event document loads"), View->TryReload(Markup(), TEXT(""), TEXT("UiTextEventsInitial")).Succeeded)) { return false; }
    const TSharedRef<SWidget> AcceptedRoot = Region->GetChildren()->GetChildAt(0);
    TestEqual(TEXT("Factory receives one typed event control"), Probe->FactoryCalls, 1);
    TestFalse(TEXT("Factory cannot dispatch events during staging"), Probe->CanDispatchDuringFactory);
    TestEqual(TEXT("Factory attempts changed dispatch during staging"), Probe->FactoryChangedAttempts, 1);
    TestEqual(TEXT("Factory attempts committed dispatch during staging"), Probe->FactoryCommittedAttempts, 1);
    TestEqual(TEXT("Construction dispatches reach no consumer"), ChangedCalls + CommittedCalls, 0);
    TestTrue(TEXT("Factory receives live text binding"), Probe->Arguments.TextBindings.Contains(TEXT("value")) && Probe->Arguments.TextBindings.FindRef(TEXT("value")).Get().ToString() == TEXT("initial"));
    TestTrue(TEXT("Factory receives changed callback"), Probe->Arguments.TextChanged.FindRef(TEXT("changed")).IsBound());
    TestTrue(TEXT("Factory receives committed callback"), Probe->Arguments.TextCommitted.FindRef(TEXT("committed")).IsBound());
    TestTrue(TEXT("Arguments expose binding identity"), Probe->Arguments.BindingNames.FindRef(TEXT("value")) == TEXT("value") && Probe->Arguments.BindingNames.FindRef(TEXT("changed")) == TEXT("changed") && Probe->Arguments.BindingNames.FindRef(TEXT("committed")) == TEXT("committed"));
    TestTrue(TEXT("Factory may dispatch events after accepted load"), Probe->Arguments.CanDispatchEvents.Get());
    Probe->Arguments.TextChanged.FindRef(TEXT("changed")).Execute(FText::FromString(TEXT("edit")));
    Probe->Arguments.TextCommitted.FindRef(TEXT("committed")).Execute(FText::FromString(TEXT("edit")), ETextCommit::OnEnter);
    TestEqual(TEXT("Changed callback reaches consumer"), ChangedCalls, 1);
    TestEqual(TEXT("Committed callback reaches consumer"), CommittedCalls, 1);
    TestEqual(TEXT("Changed callback preserves text payload"), ChangedPayload, FString(TEXT("edit")));
    TestEqual(TEXT("Committed callback preserves text payload"), CommittedPayload, FString(TEXT("edit")));
    TestEqual(TEXT("Committed callback preserves reason"), CommitReason, ETextCommit::OnEnter);

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
    Reject(TEXT("Missing required changed event rejects"), Markup(TEXT("<text-event-probe id=\"editor\" value-bind=\"value\" committed=\"committed\"/>")));
    Reject(TEXT("Missing required committed event rejects"), Markup(TEXT("<text-event-probe id=\"editor\" value-bind=\"value\" changed=\"changed\"/>")));
    Reject(TEXT("Missing committed binding rejects"), Markup(TEXT("<text-event-probe id=\"editor\" value-bind=\"value\" changed=\"changed\" committed=\"missing\"/>")));
    Reject(TEXT("Supplied but unbound changed event rejects"), Markup(TEXT("<text-event-probe id=\"editor\" value-bind=\"value\" changed=\"unbound\" committed=\"committed\"/>")));

    auto Document = FCkUiDocument{};
    const FString TemplateMarkup = TEXT("<ui version=\"1\"><template name=\"editor\"><param name=\"value\" type=\"text-binding\"/><param name=\"changed\" type=\"text-changed\"/><param name=\"committed\" type=\"text-committed\"/><text-event-probe id=\"input\" value-bind-param=\"value\" changed-param=\"changed\" committed-param=\"committed\"/></template><region name=\"main\"><use template=\"editor\" id=\"one\" value-bind=\"value\" changed=\"changed\" committed=\"committed\"/></region></ui>");
    const FCkUiLoadResult TemplateResult = FCkUiDocumentParser::TryParse(TemplateMarkup, TEXT(""), {}, Document, TEXT("UiTextEventsTemplate"), Registry.CreateSnapshot());
    const FCkUiNode* Root = Document.Regions.Find(TEXT("main"));
    TestTrue(TEXT("Text-event template forwarding parses"), TemplateResult.Succeeded && Root != nullptr && Root->CustomProperties.FindRef(TEXT("changed")).Kind == ECkUiCustomPropertyKind::TextChanged && Root->CustomProperties.FindRef(TEXT("committed")).Kind == ECkUiCustomPropertyKind::TextCommitted);
    TestTrue(TEXT("Text-event template reload reaches the real factory pipeline"), View->TryReload(TemplateMarkup, TEXT(""), TEXT("UiTextEventsTemplateReload")).Succeeded);
    const int32 ChangedBeforeRelease = ChangedCalls;
    const int32 CommittedBeforeRelease = CommittedCalls;
    View.Reset();
    Probe->Arguments.TextChanged.FindRef(TEXT("changed")).Execute(FText::FromString(TEXT("after-release")));
    Probe->Arguments.TextCommitted.FindRef(TEXT("committed")).Execute(FText::FromString(TEXT("after-release")), ETextCommit::OnCleared);
    TestEqual(TEXT("Released view suppresses changed delivery"), ChangedCalls, ChangedBeforeRelease);
    TestEqual(TEXT("Released view suppresses committed delivery"), CommittedCalls, CommittedBeforeRelease);

    auto Collection = TSharedPtr<FCkUiCollection>{};
    auto Tree = TSharedPtr<FCkUiTreeCollection>{};
    if (!TestTrue(TEXT("Readonly table collection creates"), FCkUiCollection::TryCreate({{TEXT("label"), ECkUiFieldKind::Text}}, Collection).Succeeded)
        || !TestTrue(TEXT("Readonly tree collection creates"), FCkUiTreeCollection::TryCreate({{TEXT("label"), ECkUiFieldKind::Text}}, Tree).Succeeded)) { return false; }
    auto ReadonlyData = FCkUiView::FDataBindings{};
    ReadonlyData.Collections.Add(TEXT("records"), Collection);
    ReadonlyData.Trees.Add(TEXT("nodes"), Tree);
    ReadonlyData.TextChanged.Add(TEXT("changed"), FOnTextChanged::CreateLambda([](const FText&) {}));
    const TSharedRef<FCkUiView> ReadonlyView = FCkUiView::Create({}, {}, {}, FSlateFontInfo(), MoveTemp(ReadonlyData), Registry.CreateSnapshot());
    ReadonlyView->GetRegion(TEXT("main"));
    const int32 FactoriesBeforeReadonly = Probe->FactoryCalls;
    const FString TableMarkup = TEXT("<ui version=\"1\"><region name=\"main\"><table id=\"table\" bind=\"records\"><table-column id=\"column\" label=\"Label\"><optional-event-probe id=\"cell\" changed=\"changed\"/></table-column></table></region></ui>");
    const FString TreeMarkup = TEXT("<ui version=\"1\"><region name=\"main\"><tree id=\"tree\" bind=\"nodes\"><row id=\"row\"><optional-event-probe id=\"cell\" changed=\"changed\"/></row></tree></region></ui>");
    TestFalse(TEXT("Table rejects supplied optional editable event"), ReadonlyView->TryReload(TableMarkup, TEXT(""), TEXT("UiTextEventsReadonlyTable")).Succeeded);
    TestFalse(TEXT("Tree rejects supplied optional editable event"), ReadonlyView->TryReload(TreeMarkup, TEXT(""), TEXT("UiTextEventsReadonlyTree")).Succeeded);
    TestEqual(TEXT("Readonly editable event candidates invoke no factory"), Probe->FactoryCalls, FactoriesBeforeReadonly);
    return true;
}

#endif
