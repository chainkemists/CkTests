#include "CkSlateLayout/CkUiWidgetRegistry.h"
#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/CkUiTreeCollection.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Misc/AutomationTest.h"

#include <limits>
#include "Widgets/Layout/SBox.h"
#include "Widgets/Text/STextBlock.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_number_events
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
        Registration.Schema.Tag = TEXT("number-event-probe");
        Registration.Schema.Properties = {
            {TEXT("value"), ECkUiCustomPropertyKind::NumberBinding},
            {TEXT("changed"), ECkUiCustomPropertyKind::NumberChanged},
            {TEXT("committed"), ECkUiCustomPropertyKind::NumberCommitted},
        };
        Registration.Factory = [InProbe](const FCkUiCustomWidgetArguments& InArguments, FString&) -> TSharedPtr<SWidget>
        {
            ++InProbe->FactoryCalls;
            InProbe->Arguments = InArguments;
            InProbe->CanDispatchDuringFactory = InArguments.CanDispatchEvents.Get();
            ++InProbe->FactoryChangedAttempts;
            InArguments.NumberChanged.FindRef(TEXT("changed")).Execute(1.0f);
            ++InProbe->FactoryCommittedAttempts;
            InArguments.NumberCommitted.FindRef(TEXT("committed")).Execute(1.0f, ETextCommit::OnEnter);
            return SNew(STextBlock);
        };
        return InRegistry.Register(MoveTemp(Registration)).Succeeded;
    }

    auto RegisterOptionalEventProbe(const TSharedRef<FProbe>& InProbe, FCkUiWidgetRegistry& InRegistry) -> bool
    {
        auto Registration = FCkUiCustomWidgetRegistration{};
        Registration.Schema.Tag = TEXT("optional-number-event-probe");
        Registration.Schema.Properties = {
            {TEXT("changed"), ECkUiCustomPropertyKind::NumberChanged, false},
            {TEXT("committed"), ECkUiCustomPropertyKind::NumberCommitted, false},
        };
        Registration.Factory = [InProbe](const FCkUiCustomWidgetArguments&, FString&) -> TSharedPtr<SWidget>
        { ++InProbe->FactoryCalls; return SNew(STextBlock); };
        return InRegistry.Register(MoveTemp(Registration)).Succeeded;
    }

    auto Markup(const FString& InNode = TEXT("<number-event-probe id=\"editor\" value-bind=\"value\" changed=\"changed\" committed=\"committed\"/>")) -> FString
    {
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\">%s</column></region></ui>"), *InNode);
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiNumberEvents_CustomArgumentsAndAtomicity,
    "Ck.UiAuthoring.Custom.NumberEvents.ArgumentsAndAtomicity",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiNumberEvents_CustomArgumentsAndAtomicity::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_number_events;
    const TSharedRef<FProbe> Probe = MakeShared<FProbe>();
    auto Registry = FCkUiWidgetRegistry{};
    if (!TestTrue(TEXT("Number-event registry registration succeeds"), Register(Probe, Registry))) { return false; }
    if (!TestTrue(TEXT("Optional number-event registry registration succeeds"), RegisterOptionalEventProbe(Probe, Registry))) { return false; }

    float Value = 3.5f;
    int32 ChangedCalls = 0;
    int32 CommittedCalls = 0;
    float ChangedPayload = 0.0f;
    float CommittedPayload = 0.0f;
    ETextCommit::Type CommitReason = ETextCommit::Default;
    auto Data = FCkUiView::FDataBindings{};
    Data.Number.Add(TEXT("value"), TAttribute<float>::CreateLambda([&Value]() { return Value; }));
    Data.NumberChanged.Add(TEXT("changed"), FCkUiOnNumberChanged::CreateLambda([&ChangedCalls, &ChangedPayload](const float InValue) { ++ChangedCalls; ChangedPayload = InValue; }));
    Data.NumberCommitted.Add(TEXT("committed"), FCkUiOnNumberCommitted::CreateLambda([&CommittedCalls, &CommittedPayload, &CommitReason](const float InValue, const ETextCommit::Type InReason) { ++CommittedCalls; CommittedPayload = InValue; CommitReason = InReason; }));
    Data.NumberChanged.Add(TEXT("unbound"), FCkUiOnNumberChanged{});
    Data.NumberCommitted.Add(TEXT("unbound-committed"), FCkUiOnNumberCommitted{});
    TSharedPtr<FCkUiView> View = FCkUiView::Create({}, {}, {}, FSlateFontInfo(), MoveTemp(Data), Registry.CreateSnapshot());
    const TSharedRef<SBox> Region = StaticCastSharedRef<SBox>(View->GetRegion(TEXT("main")));
    if (!TestTrue(TEXT("Number-event document loads"), View->TryReload(Markup(), TEXT(""), TEXT("UiNumberEventsInitial")).Succeeded)) { return false; }
    const TSharedRef<SWidget> AcceptedRoot = Region->GetChildren()->GetChildAt(0);
    TestEqual(TEXT("Factory receives one typed number event control"), Probe->FactoryCalls, 1);
    TestFalse(TEXT("Factory cannot dispatch number events during staging"), Probe->CanDispatchDuringFactory);
    TestEqual(TEXT("Factory attempts changed dispatch during staging"), Probe->FactoryChangedAttempts, 1);
    TestEqual(TEXT("Factory attempts committed dispatch during staging"), Probe->FactoryCommittedAttempts, 1);
    TestEqual(TEXT("Construction number dispatches reach no consumer"), ChangedCalls + CommittedCalls, 0);
    TestTrue(TEXT("Factory receives live number binding"), Probe->Arguments.NumberBindings.Contains(TEXT("value")) && Probe->Arguments.NumberBindings.FindRef(TEXT("value")).Get() == 3.5f);
    TestTrue(TEXT("Factory receives number changed callback"), Probe->Arguments.NumberChanged.FindRef(TEXT("changed")).IsBound());
    TestTrue(TEXT("Factory receives number committed callback"), Probe->Arguments.NumberCommitted.FindRef(TEXT("committed")).IsBound());
    TestTrue(TEXT("Arguments expose number binding identity"), Probe->Arguments.BindingNames.FindRef(TEXT("value")) == TEXT("value") && Probe->Arguments.BindingNames.FindRef(TEXT("changed")) == TEXT("changed") && Probe->Arguments.BindingNames.FindRef(TEXT("committed")) == TEXT("committed"));
    TestTrue(TEXT("Factory may dispatch number events after accepted load"), Probe->Arguments.CanDispatchEvents.Get());
    Probe->Arguments.NumberChanged.FindRef(TEXT("changed")).Execute(7.25f);
    Probe->Arguments.NumberCommitted.FindRef(TEXT("committed")).Execute(8.5f, ETextCommit::OnUserMovedFocus);
    TestEqual(TEXT("Number changed callback reaches consumer"), ChangedCalls, 1);
    TestEqual(TEXT("Number changed callback preserves payload"), ChangedPayload, 7.25f);
    TestEqual(TEXT("Number committed callback reaches consumer"), CommittedCalls, 1);
    TestEqual(TEXT("Number committed callback preserves payload"), CommittedPayload, 8.5f);
    TestEqual(TEXT("Number committed callback preserves reason"), CommitReason, ETextCommit::OnUserMovedFocus);
    Probe->Arguments.NumberChanged.FindRef(TEXT("changed")).Execute(std::numeric_limits<float>::quiet_NaN());
    Probe->Arguments.NumberChanged.FindRef(TEXT("changed")).Execute(std::numeric_limits<float>::infinity());
    Probe->Arguments.NumberCommitted.FindRef(TEXT("committed")).Execute(std::numeric_limits<float>::quiet_NaN(), ETextCommit::OnEnter);
    Probe->Arguments.NumberCommitted.FindRef(TEXT("committed")).Execute(-std::numeric_limits<float>::infinity(), ETextCommit::OnEnter);
    TestEqual(TEXT("Non-finite numeric events reach no consumer"), ChangedCalls + CommittedCalls, 2);

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
    Reject(TEXT("Missing required number changed event rejects"), Markup(TEXT("<number-event-probe id=\"editor\" value-bind=\"value\" committed=\"committed\"/>")));
    Reject(TEXT("Missing required number committed event rejects"), Markup(TEXT("<number-event-probe id=\"editor\" value-bind=\"value\" changed=\"changed\"/>")));
    Reject(TEXT("Missing number event binding rejects"), Markup(TEXT("<number-event-probe id=\"editor\" value-bind=\"value\" changed=\"missing\" committed=\"committed\"/>")));
    Reject(TEXT("Supplied but unbound number changed event rejects"), Markup(TEXT("<number-event-probe id=\"editor\" value-bind=\"value\" changed=\"unbound\" committed=\"committed\"/>")));
    Reject(TEXT("Supplied but unbound number committed event rejects"), Markup(TEXT("<number-event-probe id=\"editor\" value-bind=\"value\" changed=\"changed\" committed=\"unbound-committed\"/>")));

    auto Document = FCkUiDocument{};
    const FString TemplateMarkup = TEXT("<ui version=\"1\"><template name=\"editor\"><param name=\"value\" type=\"number-binding\"/><param name=\"changed\" type=\"number-changed\"/><param name=\"committed\" type=\"number-committed\"/><number-event-probe id=\"input\" value-bind-param=\"value\" changed-param=\"changed\" committed-param=\"committed\"/></template><region name=\"main\"><use template=\"editor\" id=\"one\" value-bind=\"value\" changed=\"changed\" committed=\"committed\"/></region></ui>");
    const FCkUiLoadResult TemplateResult = FCkUiDocumentParser::TryParse(TemplateMarkup, TEXT(""), {}, Document, TEXT("UiNumberEventsTemplate"), Registry.CreateSnapshot());
    const FCkUiNode* Root = Document.Regions.Find(TEXT("main"));
    TestTrue(TEXT("Number-event template forwarding parses"), TemplateResult.Succeeded && Root != nullptr && Root->CustomProperties.FindRef(TEXT("changed")).Kind == ECkUiCustomPropertyKind::NumberChanged && Root->CustomProperties.FindRef(TEXT("committed")).Kind == ECkUiCustomPropertyKind::NumberCommitted);
    TestTrue(TEXT("Number-event template reload reaches real factory pipeline"), View->TryReload(TemplateMarkup, TEXT(""), TEXT("UiNumberEventsTemplateReload")).Succeeded);
    const int32 CallsBeforeRelease = ChangedCalls + CommittedCalls;
    View.Reset();
    Probe->Arguments.NumberChanged.FindRef(TEXT("changed")).Execute(9.0f);
    Probe->Arguments.NumberCommitted.FindRef(TEXT("committed")).Execute(9.0f, ETextCommit::OnCleared);
    TestEqual(TEXT("Released view suppresses number event delivery"), ChangedCalls + CommittedCalls, CallsBeforeRelease);

    auto Collection = TSharedPtr<FCkUiCollection>{};
    auto Tree = TSharedPtr<FCkUiTreeCollection>{};
    if (!TestTrue(TEXT("Readonly table collection creates"), FCkUiCollection::TryCreate({{TEXT("label"), ECkUiFieldKind::Text}}, Collection).Succeeded)
        || !TestTrue(TEXT("Readonly tree collection creates"), FCkUiTreeCollection::TryCreate({{TEXT("label"), ECkUiFieldKind::Text}}, Tree).Succeeded)) { return false; }
    auto ReadonlyData = FCkUiView::FDataBindings{};
    ReadonlyData.Collections.Add(TEXT("records"), Collection);
    ReadonlyData.Trees.Add(TEXT("nodes"), Tree);
    ReadonlyData.NumberChanged.Add(TEXT("changed"), FCkUiOnNumberChanged::CreateLambda([](const float) {}));
    ReadonlyData.NumberCommitted.Add(TEXT("committed"), FCkUiOnNumberCommitted::CreateLambda([](const float, const ETextCommit::Type) {}));
    const TSharedRef<FCkUiView> ReadonlyView = FCkUiView::Create({}, {}, {}, FSlateFontInfo(), MoveTemp(ReadonlyData), Registry.CreateSnapshot());
    ReadonlyView->GetRegion(TEXT("main"));
    const int32 FactoriesBeforeReadonly = Probe->FactoryCalls;
    const FString TableMarkup = TEXT("<ui version=\"1\"><region name=\"main\"><table id=\"table\" bind=\"records\"><table-column id=\"column\" label=\"Label\"><optional-number-event-probe id=\"cell\" changed=\"changed\" committed=\"committed\"/></table-column></table></region></ui>");
    const FString TreeMarkup = TEXT("<ui version=\"1\"><region name=\"main\"><tree id=\"tree\" bind=\"nodes\"><row id=\"row\"><optional-number-event-probe id=\"cell\" changed=\"changed\" committed=\"committed\"/></row></tree></region></ui>");
    TestFalse(TEXT("Table rejects supplied optional number events"), ReadonlyView->TryReload(TableMarkup, TEXT(""), TEXT("UiNumberEventsReadonlyTable")).Succeeded);
    TestFalse(TEXT("Tree rejects supplied optional number events"), ReadonlyView->TryReload(TreeMarkup, TEXT(""), TEXT("UiNumberEventsReadonlyTree")).Succeeded);
    TestEqual(TEXT("Readonly number event candidates invoke no factory"), Probe->FactoryCalls, FactoriesBeforeReadonly);
    return true;
}

#endif
