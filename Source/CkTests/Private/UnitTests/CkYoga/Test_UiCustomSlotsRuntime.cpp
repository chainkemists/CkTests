#include "CkSlateLayout/CkUiWidgetRegistry.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Framework/Application/SlateApplication.h"
#include "Layout/Children.h"
#include "Misc/AutomationTest.h"
#include "Styling/CoreStyle.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Input/SSearchBox.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/SBoxPanel.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_custom_slots_runtime
{
    struct FCustomSlotStats final
    {
        int32 FactoryCalls = 0;
        int32 PrepareCalls = 0;
        int32 CommitCalls = 0;
        int32 LateFactoryCalls = 0;
        TSharedPtr<SWidget> BodyMount;
        TSharedPtr<SWidget> FooterMount;
    };

    class FPreparedUpdate final : public ICkUiPreparedWidgetUpdate
    {
    public:
        explicit FPreparedUpdate(const TSharedRef<FCustomSlotStats>& InStats) : Stats(InStats) {}
        virtual void Commit() noexcept override { ++Stats->CommitCalls; }

    private:
        TSharedRef<FCustomSlotStats> Stats;
    };

    class FPanel final : public ICkUiRetainedWidget
    {
    public:
        FPanel(const TSharedRef<FCustomSlotStats>& InStats, const TSharedRef<SWidget>& InBody, const TSharedRef<SWidget>& InFooter,
            const bool InNestFooter = false)
            : Stats(InStats), Body(InBody), Footer(InFooter)
        {
            if (InNestFooter)
            {
                StaticCastSharedRef<SBox>(Body.ToSharedRef())->SetContent(Footer.ToSharedRef());
                Root = SNew(SVerticalBox)
                    + SVerticalBox::Slot().AutoHeight()[SNew(STextBlock).Text(FText::FromString(TEXT("Malformed retained panel")))]
                    + SVerticalBox::Slot()[Body.ToSharedRef()];
            }
            else
            {
                Root = SNew(SVerticalBox)
                    + SVerticalBox::Slot().AutoHeight()[SNew(STextBlock).Text(FText::FromString(TEXT("Retained panel")))]
                    + SVerticalBox::Slot()[Body.ToSharedRef()]
                    + SVerticalBox::Slot().AutoHeight()[Footer.ToSharedRef()];
            }
        }

        virtual auto GetWidget() const -> TSharedRef<SWidget> override { return Root.ToSharedRef(); }

        virtual auto PrepareReload(const FCkUiCustomWidgetArguments& InArguments, FString& OutFailure) const -> TUniquePtr<ICkUiPreparedWidgetUpdate> override
        {
            ++Stats->PrepareCalls;
            if (InArguments.Slots.FindRef(TEXT("body")) != Body || InArguments.Slots.FindRef(TEXT("footer")) != Footer)
            {
                OutFailure = TEXT("Custom slot mounts changed during retained reload.");
                return nullptr;
            }
            return MakeUnique<FPreparedUpdate>(Stats);
        }

    private:
        TSharedRef<FCustomSlotStats> Stats;
        TSharedPtr<SWidget> Body;
        TSharedPtr<SWidget> Footer;
        TSharedPtr<SWidget> Root;
    };

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

    auto FindSearch(const TSharedRef<SWidget>& InRoot, const FName InTag = FName(TEXT("query"))) -> TSharedPtr<SSearchBox>
    {
        if (InRoot->GetTag() == InTag && InRoot->GetTypeAsString() == TEXT("SSearchBox")) { return StaticCastSharedRef<SSearchBox>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SSearchBox> Found = FindSearch(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag); Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto RegionRoot(const TSharedRef<SWidget>& InRegion) -> TSharedRef<SWidget>
    { return StaticCastSharedRef<SBox>(InRegion)->GetChildren()->GetChildAt(0); }

    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    auto Load(FAutomationTestBase& InTest, const FString& InName, const TSharedRef<FCkUiView>& InView, const FString& InMarkup) -> bool
    {
        const FCkUiLoadResult Result = InView->TryReload(InMarkup, TEXT(""), InName);
        if (!Result.Succeeded) { InTest.AddError(FString::Printf(TEXT("%s errors:\n%s"), *InName, *FString::Join(Result.Errors, TEXT("\n")))); }
        return InTest.TestTrue(*InName, Result.Succeeded);
    }

    auto Markup(const bool InIncludeFooter = true, const bool InMissingChildBinding = false, const bool InLateFailure = false,
        const bool InNestedSlots = false, const bool InNestedContainer = false) -> FString
    {
        const TCHAR* QueryBinding = InMissingChildBinding ? TEXT("missing") : TEXT("query");
        const FString Footer = InIncludeFooter
            ? TEXT("<slot name=\"footer\"><button id=\"footer-button\" action=\"footer-action\">Footer</button></slot>")
            : TEXT("");
        const TCHAR* Late = InLateFailure ? TEXT("<late-factory id=\"late\"/>") : TEXT("");
        const TCHAR* Nested = InNestedSlots
            ? TEXT("<nested-invalid-inspector-panel id=\"nested-panel\"><slot name=\"body\"><text id=\"nested-body\">Nested body</text></slot><slot name=\"footer\"><text id=\"nested-footer\">Nested footer</text></slot></nested-invalid-inspector-panel>")
            : TEXT("");
        const TCHAR* NestedContainer = InNestedContainer
            ? TEXT("<nested-inspector-panel id=\"nested-within-body\"><slot name=\"body\"><column id=\"nested-body\"><search id=\"nested-query\" bind=\"nested-query\"/><button id=\"nested-body-button\" action=\"nested-body-action\">Nested body</button></column></slot><slot name=\"footer\"><button id=\"nested-footer-button\" action=\"nested-footer-action\">Nested footer</button></slot></nested-inspector-panel>")
            : TEXT("");
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\">%s<inspector-panel id=\"panel\"><slot name=\"body\"><column id=\"body\"><search id=\"query\" bind=\"%s\"/><button id=\"body-button\" action=\"body-action\">Body</button>%s</column></slot>%s</inspector-panel>%s</column></region></ui>"), Nested, QueryBinding, NestedContainer, *Footer, Late);
    }

    auto MarkupWithoutPanel() -> FString
    { return TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><text id=\"replacement\">Custom parent removed</text></column></region></ui>"); }

    auto Register(const TSharedRef<FCustomSlotStats>& InStats, const TSharedRef<FCustomSlotStats>& InNestedStats,
        FCkUiWidgetRegistry& InRegistry) -> bool
    {
        FCkUiCustomWidgetRegistration Panel;
        Panel.Schema.Tag = TEXT("inspector-panel");
        Panel.Schema.Slots = {{TEXT("body"), true}, {TEXT("footer"), false}};
        Panel.RetainedFactory = [InStats](const FCkUiCustomWidgetArguments& InArguments, FString& OutFailure) -> TSharedPtr<ICkUiRetainedWidget>
        {
            const TSharedPtr<SWidget> Body = InArguments.Slots.FindRef(TEXT("body"));
            const TSharedPtr<SWidget> Footer = InArguments.Slots.FindRef(TEXT("footer"));
            if (!Body.IsValid() || !Footer.IsValid())
            {
                OutFailure = TEXT("Retained panel requires both declared slot mounts.");
                return nullptr;
            }
            ++InStats->FactoryCalls;
            InStats->BodyMount = Body;
            InStats->FooterMount = Footer;
            return MakeShared<FPanel>(InStats, Body.ToSharedRef(), Footer.ToSharedRef());
        };
        if (!InRegistry.Register(MoveTemp(Panel)).Succeeded) { return false; }

        FCkUiCustomWidgetRegistration NestedPanel;
        NestedPanel.Schema.Tag = TEXT("nested-inspector-panel");
        NestedPanel.Schema.Slots = {{TEXT("footer"), true}, {TEXT("body"), true}};
        NestedPanel.RetainedFactory = [InNestedStats](const FCkUiCustomWidgetArguments& InArguments, FString& OutFailure) -> TSharedPtr<ICkUiRetainedWidget>
        {
            const TSharedPtr<SWidget> Body = InArguments.Slots.FindRef(TEXT("body"));
            const TSharedPtr<SWidget> Footer = InArguments.Slots.FindRef(TEXT("footer"));
            if (!Body.IsValid() || !Footer.IsValid())
            {
                OutFailure = TEXT("Nested retained panel requires both declared slot mounts.");
                return nullptr;
            }
            ++InNestedStats->FactoryCalls;
            return MakeShared<FPanel>(InNestedStats, Body.ToSharedRef(), Footer.ToSharedRef());
        };
        if (!InRegistry.Register(MoveTemp(NestedPanel)).Succeeded) { return false; }

        FCkUiCustomWidgetRegistration InvalidNestedPanel;
        InvalidNestedPanel.Schema.Tag = TEXT("nested-invalid-inspector-panel");
        // The inner footer is declared first so legacy validation's traversal order cannot mask the nested-mount alias.
        InvalidNestedPanel.Schema.Slots = {{TEXT("footer"), true}, {TEXT("body"), true}};
        InvalidNestedPanel.RetainedFactory = [InNestedStats](const FCkUiCustomWidgetArguments& InArguments, FString& OutFailure) -> TSharedPtr<ICkUiRetainedWidget>
        {
            const TSharedPtr<SWidget> Body = InArguments.Slots.FindRef(TEXT("body"));
            const TSharedPtr<SWidget> Footer = InArguments.Slots.FindRef(TEXT("footer"));
            if (!Body.IsValid() || !Footer.IsValid())
            {
                OutFailure = TEXT("Nested retained panel requires both declared slot mounts.");
                return nullptr;
            }
            ++InNestedStats->FactoryCalls;
            return MakeShared<FPanel>(InNestedStats, Body.ToSharedRef(), Footer.ToSharedRef(), true);
        };
        if (!InRegistry.Register(MoveTemp(InvalidNestedPanel)).Succeeded) { return false; }

        FCkUiCustomWidgetRegistration Late;
        Late.Schema.Tag = TEXT("late-factory");
        Late.Factory = [InStats](const FCkUiCustomWidgetArguments&, FString& OutFailure) -> TSharedPtr<SWidget>
        {
            ++InStats->LateFactoryCalls;
            OutFailure = TEXT("Expected late custom factory failure.");
            return nullptr;
        };
        return InRegistry.Register(MoveTemp(Late)).Succeeded;
    }

    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate) {}
        ~FWindowScope()
        {
            Slate.ClearUserFocus(0, EFocusCause::SetDirectly);
            if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); }
        }

        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiCustomSlots_Runtime,
    "Ck.UiAuthoring.CustomSlots.NativeRuntimeAndAtomicity",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiCustomSlots_Runtime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_custom_slots_runtime;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Custom slot runtime test requires Slate.")); return false; }

    const TSharedRef<FCustomSlotStats> Stats = MakeShared<FCustomSlotStats>();
    const TSharedRef<FCustomSlotStats> NestedStats = MakeShared<FCustomSlotStats>();
    FCkUiWidgetRegistry Registry;
    if (!TestTrue(TEXT("Retained custom-slot fixture registers"), Register(Stats, NestedStats, Registry))) { return false; }

    FText Query;
    FText NestedQuery;
    int32 BodyActions = 0;
    int32 FooterActions = 0;
    int32 NestedBodyActions = 0;
    int32 NestedFooterActions = 0;
    FCkUiView::FDataBindings Data;
    Data.Text.Add(TEXT("query"), TAttribute<FText>::CreateLambda([&Query]() { return Query; }));
    Data.TextChanged.Add(TEXT("query"), FOnTextChanged::CreateLambda([&Query](const FText& InText) { Query = InText; }));
    Data.Text.Add(TEXT("nested-query"), TAttribute<FText>::CreateLambda([&NestedQuery]() { return NestedQuery; }));
    Data.TextChanged.Add(TEXT("nested-query"), FOnTextChanged::CreateLambda([&NestedQuery](const FText& InText) { NestedQuery = InText; }));
    FCkUiView::FActions Actions;
    Actions.Add(TEXT("body-action"), FSimpleDelegate::CreateLambda([&BodyActions]() { ++BodyActions; }));
    Actions.Add(TEXT("footer-action"), FSimpleDelegate::CreateLambda([&FooterActions]() { ++FooterActions; }));
    Actions.Add(TEXT("nested-body-action"), FSimpleDelegate::CreateLambda([&NestedBodyActions]() { ++NestedBodyActions; }));
    Actions.Add(TEXT("nested-footer-action"), FSimpleDelegate::CreateLambda([&NestedFooterActions]() { ++NestedFooterActions; }));
    TSharedPtr<FCkUiView> View = FCkUiView::Create({}, MoveTemp(Actions), {}, FCoreStyle::GetDefaultFontStyle(TEXT("Regular"), 12), MoveTemp(Data), Registry.CreateSnapshot());
    const TSharedRef<SWidget> Region = View->GetRegion(TEXT("main"));

    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope(Slate);
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{420.0f, 240.0f})
        .CreateTitleBar(false).HasCloseButton(false).FocusWhenFirstShown(false)[Region];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);

    if (!Load(*this, TEXT("Custom slot runtime initial load"), View.ToSharedRef(), Markup())) { return false; }
    Tick(Slate);
    const TSharedPtr<SSearchBox> Search = FindSearch(Region);
    const TSharedPtr<SButton> BodyButton = FindButton(Region, TEXT("body-button"));
    const TSharedPtr<SButton> FooterButton = FindButton(Region, TEXT("footer-button"));
    if (!TestTrue(TEXT("Mounted custom slots expose real child search and action buttons"), Search.IsValid() && BodyButton.IsValid() && FooterButton.IsValid())) { return false; }
    TestTrue(TEXT("Retained factory receives and mounts both opaque declared slot widgets once"), Stats->FactoryCalls == 1
        && Stats->BodyMount.IsValid() && Stats->FooterMount.IsValid() && FindSearch(Stats->BodyMount.ToSharedRef()) == Search
        && FindButton(Stats->FooterMount.ToSharedRef(), TEXT("footer-button")) == FooterButton);
    TestEqual(TEXT("Initial retained custom preparation publishes once"), Stats->PrepareCalls, 1);
    TestEqual(TEXT("Initial retained custom prepared update commits once"), Stats->CommitCalls, 1);
    BodyButton->SimulateClick();
    FooterButton->SimulateClick();
    TestTrue(TEXT("Child views inherit parent actions through their slot scope"), BodyActions == 1 && FooterActions == 1);

    Search->SetText(FText::FromString(TEXT("Draft query")));
    if (!TestTrue(TEXT("Child search receives Slate focus before parent reload"), Slate.SetKeyboardFocus(Search.ToSharedRef(), EFocusCause::SetDirectly))) { return false; }
    const TSharedPtr<SWidget> FocusedSearch = Slate.GetUserFocusedWidget(0);
    const int64 InitialRevision = View->GetRevision();
    if (!Load(*this, TEXT("Compatible custom-slot parent reload"), View.ToSharedRef(), Markup())) { return false; }
    Tick(Slate);
    const TSharedRef<SWidget> CompatibleRoot = RegionRoot(Region);
    TestTrue(TEXT("Compatible parent reload retains child search identity draft and focus"), FindSearch(Region) == Search
        && Search->GetText().ToString() == TEXT("Draft query") && Query.ToString() == TEXT("Draft query") && Slate.GetUserFocusedWidget(0) == FocusedSearch);
    TestTrue(TEXT("Compatible reload preserves stable opaque slot mount identities"), Stats->FactoryCalls == 1
        && Stats->PrepareCalls == 2 && Stats->CommitCalls == 2 && Stats->BodyMount.IsValid() && Stats->FooterMount.IsValid());
    TestEqual(TEXT("Compatible parent reload advances its revision once"), View->GetRevision(), InitialRevision + 1);

    const auto ExpectRejected = [this, &View, &Region, &CompatibleRoot, &Search, &FocusedSearch, &Stats, &Slate](const FString& InName, const FString& InMarkup)
    {
        const int64 Revision = View->GetRevision();
        const FCkUiLoadResult Result = View->TryReload(InMarkup, TEXT(""), InName);
        TestFalse(*(InName + TEXT(" rejects")), Result.Succeeded);
        TestTrue(*(InName + TEXT(" reports errors")), !Result.Errors.IsEmpty());
        TestEqual(*(InName + TEXT(" preserves revision")), View->GetRevision(), Revision);
        TestTrue(*(InName + TEXT(" preserves mounted root child search and focus")), RegionRoot(Region) == CompatibleRoot
            && FindSearch(Region) == Search && Slate.GetUserFocusedWidget(0) == FocusedSearch);
        TestTrue(*(InName + TEXT(" preserves stable slot mounts")), Stats->BodyMount.IsValid() && Stats->FooterMount.IsValid());
    };
    ExpectRejected(TEXT("Malformed custom slot reload"), Markup().Replace(TEXT("name=\"footer\""), TEXT("name=\"unknown\"")));
    ExpectRejected(TEXT("Missing child search binding reload"), Markup(true, true));
    const int32 PreparesBeforeNested = Stats->PrepareCalls;
    ExpectRejected(TEXT("Nested declared custom slot mounts reload"), Markup(true, false, false, true));
    TestTrue(TEXT("Nested declared slot mounts reject before retained prepare or publication"), NestedStats->FactoryCalls == 1
        && NestedStats->PrepareCalls == 0 && NestedStats->CommitCalls == 0 && Stats->PrepareCalls == PreparesBeforeNested
        && Stats->CommitCalls == PreparesBeforeNested);
    const int32 PreparesBeforeLate = Stats->PrepareCalls;
    ExpectRejected(TEXT("Late custom factory reload"), Markup(true, false, true));
    TestTrue(TEXT("Late factory failure stages retained parent without publishing its prepared update"), Stats->LateFactoryCalls == 1
        && Stats->PrepareCalls == PreparesBeforeLate + 1 && Stats->CommitCalls == PreparesBeforeLate);

    if (!Load(*this, TEXT("Optional footer removal reload"), View.ToSharedRef(), Markup(false))) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Optional footer removal retains the required child search"), FindSearch(Region) == Search && Search->GetText().ToString() == TEXT("Draft query"));
    const int32 FooterBeforeStale = FooterActions;
    FooterButton->SimulateClick();
    TestEqual(TEXT("Held removed optional footer button is inert"), FooterActions, FooterBeforeStale);

    if (!Load(*this, TEXT("Optional footer reinsertion reload"), View.ToSharedRef(), Markup())) { return false; }
    Tick(Slate);
    const TSharedPtr<SButton> ReinsertedFooter = FindButton(Region, TEXT("footer-button"));
    if (!TestTrue(TEXT("Optional footer reinsertion mounts a new active child button"), ReinsertedFooter.IsValid() && ReinsertedFooter != FooterButton)) { return false; }
    ReinsertedFooter->SimulateClick();
    TestEqual(TEXT("Reinserted optional footer dispatches through the parent scope"), FooterActions, FooterBeforeStale + 1);

    const int32 NestedFactoriesBefore = NestedStats->FactoryCalls;
    const int32 NestedPreparesBefore = NestedStats->PrepareCalls;
    const int32 NestedCommitsBefore = NestedStats->CommitCalls;
    if (!Load(*this, TEXT("Nested custom container inside authored parent slot"), View.ToSharedRef(), Markup(true, false, false, false, true))) { return false; }
    Tick(Slate);
    const TSharedPtr<SSearchBox> NestedSearch = FindSearch(Region, TEXT("nested-query"));
    const TSharedPtr<SButton> NestedBodyButton = FindButton(Region, TEXT("nested-body-button"));
    const TSharedPtr<SButton> NestedFooterButton = FindButton(Region, TEXT("nested-footer-button"));
    if (!TestTrue(TEXT("Authored parent slot mounts real nested custom child controls"), NestedSearch.IsValid() && NestedBodyButton.IsValid() && NestedFooterButton.IsValid())) { return false; }
    TestTrue(TEXT("Nested retained container prepares and commits its declared slot mounts"), NestedStats->FactoryCalls == NestedFactoriesBefore + 1
        && NestedStats->PrepareCalls == NestedPreparesBefore + 1 && NestedStats->CommitCalls == NestedCommitsBefore + 1);
    NestedBodyButton->SimulateClick();
    NestedFooterButton->SimulateClick();
    TestTrue(TEXT("Nested custom child controls dispatch actions through the parent scope"), NestedBodyActions == 1 && NestedFooterActions == 1);
    NestedSearch->SetText(FText::FromString(TEXT("Nested draft")));

    if (!Load(*this, TEXT("Compatible nested custom parent reload"), View.ToSharedRef(), Markup(true, false, false, false, true))) { return false; }
    Tick(Slate);
    const TSharedPtr<SSearchBox> ReloadedNestedSearch = FindSearch(Region, TEXT("nested-query"));
    const TSharedPtr<SButton> ReloadedNestedBodyButton = FindButton(Region, TEXT("nested-body-button"));
    const TSharedPtr<SButton> ReloadedNestedFooterButton = FindButton(Region, TEXT("nested-footer-button"));
    TestTrue(TEXT("Compatible parent reload retains nested custom search identity and draft"), ReloadedNestedSearch == NestedSearch
        && NestedSearch->GetText().ToString() == TEXT("Nested draft") && NestedQuery.ToString() == TEXT("Nested draft")
        && NestedStats->FactoryCalls == NestedFactoriesBefore + 1 && NestedStats->PrepareCalls == NestedPreparesBefore + 2
        && NestedStats->CommitCalls == NestedCommitsBefore + 2);
    if (!TestTrue(TEXT("Compatible nested reload rebuilds live child buttons"), ReloadedNestedBodyButton.IsValid() && ReloadedNestedFooterButton.IsValid()
        && ReloadedNestedBodyButton != NestedBodyButton && ReloadedNestedFooterButton != NestedFooterButton)) { return false; }
    NestedBodyButton->SimulateClick();
    NestedFooterButton->SimulateClick();
    TestTrue(TEXT("Replaced nested child buttons are inert after parent reload"), NestedBodyActions == 1 && NestedFooterActions == 1);
    ReloadedNestedBodyButton->SimulateClick();
    ReloadedNestedFooterButton->SimulateClick();
    TestTrue(TEXT("Rebuilt nested custom child controls keep dispatching after parent reload"), NestedBodyActions == 2 && NestedFooterActions == 2);

    const TSharedPtr<SButton> CurrentBodyButton = FindButton(Region, TEXT("body-button"));
    const TSharedPtr<SButton> CurrentFooterButton = FindButton(Region, TEXT("footer-button"));
    if (!TestTrue(TEXT("Current outer custom parent controls remain mounted before removal"), CurrentBodyButton.IsValid() && CurrentFooterButton.IsValid())) { return false; }
    if (!Load(*this, TEXT("Removing custom parent with nested children"), View.ToSharedRef(), MarkupWithoutPanel())) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Parent removal detaches authored and nested child controls"), !FindButton(Region, TEXT("body-button")).IsValid()
        && !FindButton(Region, TEXT("footer-button")).IsValid() && !FindButton(Region, TEXT("nested-body-button")).IsValid()
        && !FindButton(Region, TEXT("nested-footer-button")).IsValid());
    const int32 BodyBeforeParentRemoval = BodyActions;
    const int32 FooterBeforeParentRemoval = FooterActions;
    const int32 NestedBodyBeforeParentRemoval = NestedBodyActions;
    const int32 NestedFooterBeforeParentRemoval = NestedFooterActions;
    CurrentBodyButton->SimulateClick();
    CurrentFooterButton->SimulateClick();
    ReloadedNestedBodyButton->SimulateClick();
    ReloadedNestedFooterButton->SimulateClick();
    TestTrue(TEXT("Held child buttons from a removed custom parent are inert"), BodyActions == BodyBeforeParentRemoval
        && FooterActions == FooterBeforeParentRemoval && NestedBodyActions == NestedBodyBeforeParentRemoval
        && NestedFooterActions == NestedFooterBeforeParentRemoval);

    if (!Load(*this, TEXT("Reinserting custom parent for owner release"), View.ToSharedRef(), Markup(true, false, false, false, true))) { return false; }
    Tick(Slate);
    const TSharedPtr<SButton> ActiveNestedFooterButton = FindButton(Region, TEXT("nested-footer-button"));
    if (!TestTrue(TEXT("Reinserted custom parent has an active nested child button"), ActiveNestedFooterButton.IsValid())) { return false; }
    const int32 BeforeActiveClick = NestedFooterActions;
    ActiveNestedFooterButton->SimulateClick();
    TestEqual(TEXT("Reinserted nested child dispatches before owner release"), NestedFooterActions, BeforeActiveClick + 1);
    const int32 FooterBeforeRelease = FooterActions;
    const int32 NestedFooterBeforeRelease = NestedFooterActions;
    View.Reset();
    Tick(Slate);
    ActiveNestedFooterButton->SimulateClick();
    TestTrue(TEXT("Released parent owner leaves held nested child button inert"), FooterActions == FooterBeforeRelease
        && NestedFooterActions == NestedFooterBeforeRelease);
    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
