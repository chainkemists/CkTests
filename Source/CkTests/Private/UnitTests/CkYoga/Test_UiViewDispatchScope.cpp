#include "CkSlateLayout/CkFlexText.h"
#include "CkSlateLayout/CkUiWidgetRegistry.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Layout/Children.h"
#include "Misc/AutomationTest.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Input/SSearchBox.h"
#include "Widgets/Text/STextBlock.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_view_dispatch_scope
{
    struct FProbe final
    {
        int32 FactoryCalls = 0;
        bool CanDispatchDuringFactory = true;
        FCkUiCustomWidgetArguments Arguments;
    };

    auto RegisterProbe(const TSharedRef<FProbe>& InProbe, FCkUiWidgetRegistry& InRegistry) -> bool
    {
        auto Registration = FCkUiCustomWidgetRegistration{};
        Registration.Schema.Tag = TEXT("dispatch-scope-probe");
        Registration.Schema.Properties = {
            {TEXT("label"), ECkUiCustomPropertyKind::TextBinding},
            {TEXT("action"), ECkUiCustomPropertyKind::Action},
            {TEXT("changed"), ECkUiCustomPropertyKind::TextChanged},
        };
        Registration.Factory = [InProbe](const FCkUiCustomWidgetArguments& InArguments, FString&) -> TSharedPtr<SWidget>
        {
            ++InProbe->FactoryCalls;
            InProbe->CanDispatchDuringFactory = InArguments.CanDispatchEvents.Get();
            InProbe->Arguments = InArguments;
            return SNew(STextBlock);
        };
        return InRegistry.Register(MoveTemp(Registration)).Succeeded;
    }

    auto FindButton(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SButton>
    {
        if (InRoot->GetTag() == InTag && InRoot->GetTypeAsString() == TEXT("SButton"))
        {
            return StaticCastSharedRef<SButton>(InRoot);
        }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SButton> Found = FindButton(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag); Found.IsValid())
            {
                return Found;
            }
        }
        return {};
    }

    auto FindSearch(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SSearchBox>
    {
        if (InRoot->GetTag() == InTag && InRoot->GetTypeAsString() == TEXT("SSearchBox"))
        {
            return StaticCastSharedRef<SSearchBox>(InRoot);
        }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SSearchBox> Found = FindSearch(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag); Found.IsValid())
            {
                return Found;
            }
        }
        return {};
    }

    auto Markup(const FString& InBody) -> FString
    {
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\">%s</column></region></ui>"), *InBody);
    }

    auto InitialMarkup() -> FString
    {
        return Markup(TEXT("<button id=\"button\" action=\"action\" bind=\"label\"/><dispatch-scope-probe id=\"custom\" label-bind=\"label\" action=\"action\" changed=\"query\"/><search id=\"search\" bind=\"query\"/>"));
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkUiViewDispatchScope_Runtime,
    "Ck.UiAuthoring.View.DispatchScope.Runtime",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiViewDispatchScope_Runtime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_view_dispatch_scope;

    const TSharedRef<FProbe> Probe = MakeShared<FProbe>();
    auto Registry = FCkUiWidgetRegistry{};
    if (NOT TestTrue(TEXT("Dispatch-scope probe registration succeeds"), RegisterProbe(Probe, Registry)))
    {
        return false;
    }

    auto CanDispatch = false;
    auto Label = NSLOCTEXT("Ck.UiAuthoring.Test", "DispatchScopeLabelInitial", "Initial label");
    auto Query = FText::GetEmpty();
    auto ActionCalls = 0;
    auto ChangedCalls = 0;
    auto Data = FCkUiView::FDataBindings{};
    Data.CanDispatchEvents = TAttribute<bool>::CreateLambda([&CanDispatch]() { return CanDispatch; });
    Data.Text.Add(TEXT("label"), TAttribute<FText>::CreateLambda([&Label]() { return Label; }));
    Data.Text.Add(TEXT("query"), TAttribute<FText>::CreateLambda([&Query]() { return Query; }));
    Data.TextChanged.Add(TEXT("query"), FOnTextChanged::CreateLambda([&ChangedCalls, &Query](const FText& InText)
    {
        ++ChangedCalls;
        Query = InText;
    }));
    auto Actions = FCkUiView::FActions{};
    Actions.Add(TEXT("action"), FSimpleDelegate::CreateLambda([&ActionCalls]() { ++ActionCalls; }));
    TSharedPtr<FCkUiView> View = FCkUiView::Create({}, MoveTemp(Actions), {}, FSlateFontInfo{}, MoveTemp(Data), Registry.CreateSnapshot());
    const TSharedRef<SWidget> Region = View->GetRegion(TEXT("main"));
    if (NOT TestTrue(TEXT("Dispatch-scope document loads"), View->TryReload(InitialMarkup(), TEXT(""), TEXT("UiViewDispatchScopeInitial")).Succeeded))
    {
        return false;
    }

    const TSharedPtr<SButton> Button = FindButton(Region, TEXT("button"));
    const TSharedPtr<SSearchBox> Search = FindSearch(Region, TEXT("search"));
    if (NOT TestTrue(TEXT("Dispatch-scope document mounts native button and search"), Button.IsValid() && Search.IsValid()))
    {
        return false;
    }
    Button->SlatePrepass(1.0f);
    const FChildren* ButtonChildren = Button->GetChildren();
    if (NOT TestTrue(TEXT("Dispatch-scope button mounts its native text label"), ButtonChildren != nullptr
        && ButtonChildren->Num() == 1 && ButtonChildren->GetChildAt(0)->GetTypeAsString() == TEXT("SCkFlexText")))
    {
        return false;
    }
    const TSharedRef<SCkFlexText> LabelWidget = StaticCastSharedRef<SCkFlexText>(ConstCastSharedRef<SWidget>(ButtonChildren->GetChildAt(0)));
    TestEqual(TEXT("Custom factory runs once"), Probe->FactoryCalls, 1);
    TestFalse(TEXT("Custom factory cannot dispatch while the view stages"), Probe->CanDispatchDuringFactory);
    TestFalse(TEXT("Custom arguments expose disabled live dispatch eligibility"), Probe->Arguments.CanDispatchEvents.Get());
    TestTrue(TEXT("Custom factory receives an action and text event callback"), Probe->Arguments.Actions.FindRef(TEXT("action")).IsBound()
        && Probe->Arguments.TextChanged.FindRef(TEXT("changed")).IsBound());

    TestTrue(TEXT("Native button retains passive localized text"), LabelWidget->GetText().IdenticalTo(Label));
    Label = NSLOCTEXT("Ck.UiAuthoring.Test", "DispatchScopeLabelUpdated", "Updated label");
    Button->SlatePrepass(1.0f);
    TestTrue(TEXT("Passive text binding updates while dispatch is disabled"), LabelWidget->GetText().IdenticalTo(Label));

    Button->SimulateClick();
    Probe->Arguments.Actions.FindRef(TEXT("action")).Execute();
    Probe->Arguments.TextChanged.FindRef(TEXT("changed")).Execute(FText::FromString(TEXT("custom blocked")));
    Search->SetText(FText::FromString(TEXT("search blocked")));
    TestEqual(TEXT("Disabled dispatch suppresses native and custom actions"), ActionCalls, 0);
    TestEqual(TEXT("Disabled dispatch suppresses custom and native form events"), ChangedCalls, 0);

    CanDispatch = true;
    TestTrue(TEXT("Custom arguments observe enabled dispatch without reload"), Probe->Arguments.CanDispatchEvents.Get());
    Button->SimulateClick();
    Probe->Arguments.Actions.FindRef(TEXT("action")).Execute();
    Probe->Arguments.TextChanged.FindRef(TEXT("changed")).Execute(FText::FromString(TEXT("custom live")));
    Search->SetText(FText::FromString(TEXT("search live")));
    TestEqual(TEXT("Enabled dispatch resumes native and custom actions"), ActionCalls, 2);
    TestEqual(TEXT("Enabled dispatch resumes custom and native search events"), ChangedCalls, 2);
    TestEqual(TEXT("Native search event preserves its entered text"), Query.ToString(), FString(TEXT("search live")));

    const int64 RevisionBeforeReject = View->GetRevision();
    const FCkUiLoadResult Rejected = View->TryReload(Markup(TEXT("<button id=\"button\" action=\"missing\"/>")), TEXT(""), TEXT("UiViewDispatchScopeRejected"));
    TestFalse(TEXT("Rejected reload fails"), Rejected.Succeeded);
    TestEqual(TEXT("Rejected reload preserves revision"), View->GetRevision(), RevisionBeforeReject);
    TestTrue(TEXT("Rejected reload preserves native button identity"), FindButton(Region, TEXT("button")) == Button);
    const int32 ActionsBeforeRejectProbe = ActionCalls;
    const int32 ChangesBeforeRejectProbe = ChangedCalls;
    Button->SimulateClick();
    Probe->Arguments.Actions.FindRef(TEXT("action")).Execute();
    Search->SetText(FText::FromString(TEXT("search after reject")));
    TestEqual(TEXT("Rejected reload preserves active action dispatch"), ActionCalls, ActionsBeforeRejectProbe + 2);
    TestEqual(TEXT("Rejected reload preserves active native search dispatch"), ChangedCalls, ChangesBeforeRejectProbe + 1);

    if (NOT TestTrue(TEXT("Accepted replacement reload succeeds"), View->TryReload(Markup(TEXT("<button id=\"replacement\" action=\"action\"/>")), TEXT(""), TEXT("UiViewDispatchScopeReplacement")).Succeeded))
    {
        return false;
    }
    const int32 ActionsBeforeStaleCallbacks = ActionCalls;
    Button->SimulateClick();
    TestEqual(TEXT("Accepted reload makes stale native button inert"), ActionCalls, ActionsBeforeStaleCallbacks);

    const TSharedPtr<SButton> Replacement = FindButton(Region, TEXT("replacement"));
    if (NOT TestTrue(TEXT("Replacement native button mounts"), Replacement.IsValid()))
    {
        return false;
    }
    Replacement->SimulateClick();
    TestEqual(TEXT("Replacement button dispatches while view lives"), ActionCalls, ActionsBeforeStaleCallbacks + 1);
    const int32 ChangesBeforeRelease = ChangedCalls;
    View.Reset();
    TestFalse(TEXT("Released view disables retained custom eligibility"), Probe->Arguments.CanDispatchEvents.Get());
    Probe->Arguments.TextChanged.FindRef(TEXT("changed")).Execute(FText::FromString(TEXT("released custom")));
    Search->SetText(FText::FromString(TEXT("released search")));
    TestEqual(TEXT("Released view suppresses retained form events"), ChangedCalls, ChangesBeforeRelease);
    Replacement->SimulateClick();
    Probe->Arguments.Actions.FindRef(TEXT("action")).Execute();
    TestEqual(TEXT("Released view makes retained native callbacks inert"), ActionCalls, ActionsBeforeStaleCallbacks + 1);

    auto DefaultCalls = 0;
    auto DefaultActions = FCkUiView::FActions{};
    DefaultActions.Add(TEXT("default-action"), FSimpleDelegate::CreateLambda([&DefaultCalls]() { ++DefaultCalls; }));
    auto DefaultData = FCkUiView::FDataBindings{};
    const TSharedPtr<FCkUiView> DefaultView = FCkUiView::Create({}, MoveTemp(DefaultActions), {}, FSlateFontInfo{}, MoveTemp(DefaultData), Registry.CreateSnapshot());
    const TSharedRef<SWidget> DefaultRegion = DefaultView->GetRegion(TEXT("main"));
    if (NOT TestTrue(TEXT("Unset dispatch eligibility document loads"), DefaultView->TryReload(Markup(TEXT("<button id=\"default\" action=\"default-action\"/>")), TEXT(""), TEXT("UiViewDispatchScopeDefault")).Succeeded))
    {
        return false;
    }
    const TSharedPtr<SButton> DefaultButton = FindButton(DefaultRegion, TEXT("default"));
    if (NOT TestTrue(TEXT("Unset dispatch eligibility mounts native button"), DefaultButton.IsValid()))
    {
        return false;
    }
    DefaultButton->SimulateClick();
    TestEqual(TEXT("Unset dispatch eligibility defaults to enabled"), DefaultCalls, 1);
    return true;
}

#endif
