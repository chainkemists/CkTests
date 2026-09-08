#include "CkSlateLayout/CkUiWidgetRegistry.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Framework/Application/SlateApplication.h"
#include "Layout/Children.h"
#include "Misc/AutomationTest.h"
#include "Widgets/Input/SEditableText.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/SBoxPanel.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_retained_registry
{
    auto RootMarkup(const FString& InChildren) -> FString
    {
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"only\"><column id=\"root\">%s</column></region></ui>"), *InChildren);
    }

    auto RetainedMarkup(const FString& InState, const FString& InLabel, const FString& InSuffix = TEXT("")) -> FString
    {
        return RootMarkup(FString::Printf(TEXT("<retained id=\"card\" state=\"%s\" label=\"%s\"/>%s"), *InState, *InLabel, *InSuffix));
    }

    auto RegionContent(const TSharedRef<FCkUiView>& InView) -> TSharedRef<SWidget>
    {
        return StaticCastSharedRef<SBox>(InView->GetRegion(TEXT("only")))->GetChildren()->GetChildAt(0);
    }

    auto FindTagged(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTag() == InTag) { return InRoot; }
        const FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SWidget> Found = FindTagged(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag); Found.IsValid()) { return Found; }
        }
        return nullptr;
    }

    auto HasError(const FCkUiLoadResult& InResult, const FString& InNeedle) -> bool
    {
        for (const FString& Error : InResult.Errors) { if (Error.Contains(InNeedle)) { return true; } }
        return false;
    }

    struct FSlateWindowScope final
    {
        explicit FSlateWindowScope(FSlateApplication& InSlate)
            : Slate(InSlate), PreviousFocus(Slate.GetUserFocusedWidget(0)) {}

        ~FSlateWindowScope()
        {
            for (const TSharedRef<SWindow>& Window : Windows) { Slate.DestroyWindowImmediately(Window); }
            if (PreviousFocus.IsValid()) { Slate.SetKeyboardFocus(PreviousFocus, EFocusCause::SetDirectly); }
            else { Slate.ClearKeyboardFocus(EFocusCause::SetDirectly); }
        }

        void Add(const TSharedRef<SWindow>& InWindow)
        {
            Slate.AddWindow(InWindow, false);
            Windows.Add(InWindow);
        }

        FSlateApplication& Slate;
        TSharedPtr<SWidget> PreviousFocus;
        TArray<TSharedRef<SWindow>> Windows;
    };

    struct FRetainedFixtureStats final
    {
        int32 FactoryCalls = 0;
        int32 GetWidgetCalls = 0;
        int32 PrepareCalls = 0;
        int32 CommitCalls = 0;
        int32 DestructCalls = 0;
        int32 FailingFactoryCalls = 0;
        FString CommittedLabel;
        TArray<TWeakPtr<class FComponent>> Instances;
    };

    class FPreparedUpdate final : public ICkUiPreparedWidgetUpdate
    {
    public:
        FPreparedUpdate(const TSharedRef<FRetainedFixtureStats>& InStats, FString InLabel)
            : _Stats(InStats), _Label(MoveTemp(InLabel)) {}

        virtual void Commit() noexcept override
        {
            ++_Stats->CommitCalls;
            _Stats->CommittedLabel = MoveTemp(_Label);
        }

    private:
        TSharedRef<FRetainedFixtureStats> _Stats;
        FString _Label;
    };

    class FComponent final : public ICkUiRetainedWidget
    {
    public:
        explicit FComponent(const TSharedRef<FRetainedFixtureStats>& InStats)
            : _Stats(InStats), _Input(SNew(SEditableText).Tag(FName(TEXT("retained-input"))).Text(FText::FromString(TEXT("initial draft"))))
        {
            _Root = SNew(SVerticalBox)
                + SVerticalBox::Slot()[SNew(STextBlock).Tag(FName(TEXT("retained-label"))).Text_Lambda([Stats = _Stats]() { return FText::FromString(Stats->CommittedLabel); })]
                + SVerticalBox::Slot()[_Input];
        }

        virtual ~FComponent() override { ++_Stats->DestructCalls; }

        virtual auto GetWidget() const -> TSharedRef<SWidget> override
        {
            ++_Stats->GetWidgetCalls;
            return _Root.ToSharedRef();
        }

        virtual auto PrepareReload(const FCkUiCustomWidgetArguments& InArguments, FString& OutFailure) const -> TUniquePtr<ICkUiPreparedWidgetUpdate> override
        {
            ++_Stats->PrepareCalls;
            const FText* Label = InArguments.TextProperties.Find(TEXT("label"));
            if (Label == nullptr) { OutFailure = TEXT("Missing label."); return nullptr; }
            if (Label->ToString() == TEXT("prepare-fail")) { OutFailure = TEXT("Expected prepare failure."); return nullptr; }
            if (Label->ToString() == TEXT("prepare-null")) { return nullptr; }
            if (Label->ToString() == TEXT("prepare-diagnostic"))
            {
                OutFailure = TEXT("Expected prepare diagnostic.");
                return MakeUnique<FPreparedUpdate>(_Stats, Label->ToString());
            }
            return MakeUnique<FPreparedUpdate>(_Stats, Label->ToString());
        }

    private:
        TSharedRef<FRetainedFixtureStats> _Stats;
        TSharedPtr<SWidget> _Root;
        TSharedRef<SEditableText> _Input;
    };

    auto MakeRetainedRegistration(const TSharedRef<FRetainedFixtureStats>& InStats) -> FCkUiCustomWidgetRegistration
    {
        auto Registration = FCkUiCustomWidgetRegistration{};
        Registration.Schema.Tag = TEXT("retained");
        Registration.Schema.Properties = {
            {TEXT("state"), ECkUiCustomPropertyKind::Text, true},
            {TEXT("label"), ECkUiCustomPropertyKind::Text, true},
        };
        Registration.Schema.StateKeyProperty = TEXT("state");
        Registration.RetainedFactory = [InStats](const FCkUiCustomWidgetArguments&, FString&) -> TSharedPtr<ICkUiRetainedWidget>
        {
            ++InStats->FactoryCalls;
            const TSharedPtr<FComponent> Component = MakeShared<FComponent>(InStats);
            InStats->Instances.Add(Component);
            return Component;
        };
        return Registration;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiRetainedRegistry_Schema,
    "Ck.UiAuthoring.RetainedRegistry.Schema",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiRetainedRegistry_Schema::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_retained_registry;
    const TSharedRef<FRetainedFixtureStats> Stats = MakeShared<FRetainedFixtureStats>();
    auto Registry = FCkUiWidgetRegistry{};

    auto NoFactory = FCkUiCustomWidgetRegistration{};
    NoFactory.Schema.Tag = TEXT("no-factory");
    TestFalse(TEXT("Registration rejects no factory"), Registry.Register(MoveTemp(NoFactory)).Succeeded);

    auto BothFactories = MakeRetainedRegistration(Stats);
    BothFactories.Factory = [](const FCkUiCustomWidgetArguments&, FString&) -> TSharedPtr<SWidget> { return SNew(STextBlock); };
    TestFalse(TEXT("Registration rejects both stateless and retained factories"), Registry.Register(MoveTemp(BothFactories)).Succeeded);

    auto MissingStateProperty = MakeRetainedRegistration(Stats);
    MissingStateProperty.Schema.StateKeyProperty = TEXT("missing");
    TestFalse(TEXT("State key must name a schema property"), Registry.Register(MoveTemp(MissingStateProperty)).Succeeded);

    auto BindingStateProperty = MakeRetainedRegistration(Stats);
    BindingStateProperty.Schema.Properties[0].Kind = ECkUiCustomPropertyKind::TextBinding;
    TestFalse(TEXT("State key must be literal text"), Registry.Register(MoveTemp(BindingStateProperty)).Succeeded);

    auto OptionalStateProperty = MakeRetainedRegistration(Stats);
    OptionalStateProperty.Schema.Properties[0].bRequired = false;
    TestFalse(TEXT("State key must be required"), Registry.Register(MoveTemp(OptionalStateProperty)).Succeeded);

    auto StatelessStateKey = FCkUiCustomWidgetRegistration{};
    StatelessStateKey.Schema.Tag = TEXT("stateless-key");
    StatelessStateKey.Schema.Properties = {{TEXT("state"), ECkUiCustomPropertyKind::Text, true}};
    StatelessStateKey.Schema.StateKeyProperty = TEXT("state");
    StatelessStateKey.Factory = [](const FCkUiCustomWidgetArguments&, FString&) -> TSharedPtr<SWidget> { return SNew(STextBlock); };
    TestFalse(TEXT("State key rejects a stateless factory"), Registry.Register(MoveTemp(StatelessStateKey)).Succeeded);

    TestTrue(TEXT("Well-formed retained registration succeeds"), Registry.Register(MakeRetainedRegistration(Stats)).Succeeded);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiRetainedRegistry_Lifecycle,
    "Ck.UiAuthoring.RetainedRegistry.LifecycleAndAtomicity",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiRetainedRegistry_Lifecycle::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_retained_registry;
    if (!FSlateApplication::IsInitialized())
    {
        AddError(TEXT("Retained component focus coverage requires an initialized Slate application."));
        return false;
    }

    const TSharedRef<FRetainedFixtureStats> Stats = MakeShared<FRetainedFixtureStats>();
    auto Registry = FCkUiWidgetRegistry{};
    if (!TestTrue(TEXT("Retained fixture registration succeeds"), Registry.Register(MakeRetainedRegistration(Stats)).Succeeded)) { return false; }
    auto Alternate = MakeRetainedRegistration(Stats);
    Alternate.Schema.Tag = TEXT("alternate-retained");
    if (!TestTrue(TEXT("Alternate retained registration succeeds"), Registry.Register(MoveTemp(Alternate)).Succeeded)) { return false; }
    auto Failing = FCkUiCustomWidgetRegistration{};
    Failing.Schema.Tag = TEXT("late-fail");
    Failing.Factory = [Stats](const FCkUiCustomWidgetArguments&, FString& OutFailure) -> TSharedPtr<SWidget>
    {
        ++Stats->FailingFactoryCalls;
        OutFailure = TEXT("Expected late factory failure.");
        return nullptr;
    };
    if (!TestTrue(TEXT("Late-failure fixture registration succeeds"), Registry.Register(MoveTemp(Failing)).Succeeded)) { return false; }

    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, {}, Registry.CreateSnapshot());
    const TSharedRef<SWidget> Region = View->GetRegion(TEXT("only"));
    FSlateApplication& Slate = FSlateApplication::Get();
    FSlateWindowScope Windows{Slate};
    const TSharedRef<SEditableText> ExternalInput = SNew(SEditableText).Text(FText::FromString(TEXT("external")));
    const TSharedRef<SWindow> Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{320.0f, 120.0f})
        .CreateTitleBar(false).HasCloseButton(false).FocusWhenFirstShown(false)
        [SNew(SVerticalBox) + SVerticalBox::Slot()[Region] + SVerticalBox::Slot()[ExternalInput]];
    Windows.Add(Window);

    if (!TestTrue(TEXT("Initial retained component loads"), View->TryReload(RetainedMarkup(TEXT("stable"), TEXT("first")), TEXT(""), TEXT("RetainedInitial")).Succeeded)) { return false; }
    const TSharedRef<SWidget> InitialRoot = RegionContent(View);
    TSharedPtr<SEditableText> Input = StaticCastSharedPtr<SEditableText>(FindTagged(InitialRoot, TEXT("retained-input")));
    const TSharedPtr<STextBlock> Label = StaticCastSharedPtr<STextBlock>(FindTagged(InitialRoot, TEXT("retained-label")));
    if (!TestTrue(TEXT("Retained component exposes real editable input"), Input.IsValid())
        || !TestTrue(TEXT("Retained component exposes committed Slate label"), Label.IsValid())) { return false; }
    TestEqual(TEXT("Initial retained factory runs once"), Stats->FactoryCalls, 1);
    TestEqual(TEXT("Initial retained factory exposes its widget once"), Stats->GetWidgetCalls, 1);
    TestEqual(TEXT("Initial retained prepare runs once"), Stats->PrepareCalls, 1);
    TestEqual(TEXT("Initial retained commit runs once"), Stats->CommitCalls, 1);
    TestEqual(TEXT("Initial retained config commits"), Stats->CommittedLabel, FString(TEXT("first")));
    TestEqual(TEXT("Initial retained Slate label reflects committed config"), Label->GetText().ToString(), FString(TEXT("first")));
    Input->SetText(FText::FromString(TEXT("unsaved draft")));
    if (!TestTrue(TEXT("Retained input receives Slate focus"), Slate.SetKeyboardFocus(Input.ToSharedRef(), EFocusCause::SetDirectly))) { return false; }
    TSharedPtr<SWidget> FocusedLeaf = Slate.GetUserFocusedWidget(0);
    if (!TestTrue(TEXT("Retained input resolves an exact focused leaf"), FocusedLeaf.IsValid())) { return false; }

    if (!TestTrue(TEXT("Compatible retained reload succeeds"), View->TryReload(RetainedMarkup(TEXT("stable"), TEXT("updated"), TEXT("<text id=\"structure\">new ancestry</text>")), TEXT(""), TEXT("RetainedCompatible")).Succeeded)) { return false; }
    const TSharedRef<SWidget> UpdatedRoot = RegionContent(View);
    TSharedPtr<SEditableText> UpdatedInput = StaticCastSharedPtr<SEditableText>(FindTagged(UpdatedRoot, TEXT("retained-input")));
    if (!TestTrue(TEXT("Compatible reload retains a valid editable input"), UpdatedInput.IsValid())) { return false; }
    TestTrue(TEXT("Compatible reload replaces authored ancestry"), UpdatedRoot != InitialRoot);
    TestTrue(TEXT("Compatible reload preserves exact retained widget"), UpdatedInput == Input);
    TestEqual(TEXT("Compatible reload reuses the cached retained widget"), Stats->GetWidgetCalls, 1);
    TestEqual(TEXT("Compatible reload preserves draft text"), UpdatedInput->GetText().ToString(), FString(TEXT("unsaved draft")));
    TestTrue(TEXT("Compatible reload restores the exact focused leaf"), Slate.GetUserFocusedWidget(0) == FocusedLeaf);
    TestTrue(TEXT("Focused retained leaf is under new authored root"), Slate.HasUserFocusedDescendants(UpdatedRoot, 0));
    TestEqual(TEXT("Compatible reload prepares retained widget again"), Stats->PrepareCalls, 2);
    TestEqual(TEXT("Compatible reload commits config exactly once"), Stats->CommitCalls, 2);
    TestEqual(TEXT("Compatible reload swaps config during commit"), Stats->CommittedLabel, FString(TEXT("updated")));
    TestEqual(TEXT("Compatible reload updates retained Slate label after commit"), Label->GetText().ToString(), FString(TEXT("updated")));

    const int64 AcceptedRevision = View->GetRevision();
    const int32 AcceptedCommits = Stats->CommitCalls;
    const int32 AcceptedPrepares = Stats->PrepareCalls;
    const auto AssertRejected = [this, &View, &UpdatedRoot, &UpdatedInput, &Label, &Slate, &FocusedLeaf, &Stats, AcceptedRevision, AcceptedCommits](const FString& InName, const FString& InMarkup, const FString& InError)
    {
        const FCkUiLoadResult Result = View->TryReload(InMarkup, TEXT(""), InName);
        TestFalse(*InName, Result.Succeeded);
        TestTrue(*(InName + TEXT(" reports failure")), HasError(Result, InError));
        TestEqual(*(InName + TEXT(" preserves revision")), View->GetRevision(), AcceptedRevision);
        TestTrue(*(InName + TEXT(" preserves root")), RegionContent(View) == UpdatedRoot);
        TestTrue(*(InName + TEXT(" preserves retained widget")), FindTagged(UpdatedRoot, TEXT("retained-input")) == UpdatedInput);
        TestEqual(*(InName + TEXT(" preserves draft")), UpdatedInput->GetText().ToString(), FString(TEXT("unsaved draft")));
        TestTrue(*(InName + TEXT(" preserves focus")), Slate.GetUserFocusedWidget(0) == FocusedLeaf);
        TestEqual(*(InName + TEXT(" publishes no config update")), Stats->CommitCalls, AcceptedCommits);
        TestEqual(*(InName + TEXT(" preserves committed config")), Stats->CommittedLabel, FString(TEXT("updated")));
        TestEqual(*(InName + TEXT(" preserves retained Slate label")), Label->GetText().ToString(), FString(TEXT("updated")));
    };
    AssertRejected(TEXT("Late stateless factory failure"), RetainedMarkup(TEXT("stable"), TEXT("late"), TEXT("<late-fail id=\"late\"/>")), TEXT("Expected late factory failure"));
    TestEqual(TEXT("Late factory failure still prepares earlier retained component"), Stats->PrepareCalls, AcceptedPrepares + 1);
    AssertRejected(TEXT("Retained prepare failure"), RetainedMarkup(TEXT("stable"), TEXT("prepare-fail")), TEXT("Expected prepare failure"));
    TestEqual(TEXT("Prepare failure invokes prepare without commit"), Stats->PrepareCalls, AcceptedPrepares + 2);
    AssertRejected(TEXT("Retained null prepared update"), RetainedMarkup(TEXT("stable"), TEXT("prepare-null")), TEXT("returned no prepared update"));
    TestEqual(TEXT("Null prepared update invokes prepare without commit"), Stats->PrepareCalls, AcceptedPrepares + 3);
    AssertRejected(TEXT("Retained diagnostic prepared update"), RetainedMarkup(TEXT("stable"), TEXT("prepare-diagnostic")), TEXT("Expected prepare diagnostic"));
    TestEqual(TEXT("Diagnostic prepared update invokes prepare without commit"), Stats->PrepareCalls, AcceptedPrepares + 4);
    AssertRejected(TEXT("Retained empty state key"), RetainedMarkup(TEXT(""), TEXT("updated")), TEXT("non-empty state key"));
    TestEqual(TEXT("Empty state key fails before prepare"), Stats->PrepareCalls, AcceptedPrepares + 4);
    AssertRejected(TEXT("Retained state key change"), RetainedMarkup(TEXT("different"), TEXT("updated")), TEXT("cannot change state key"));
    TestEqual(TEXT("State key failure occurs before prepare"), Stats->PrepareCalls, AcceptedPrepares + 4);
    AssertRejected(TEXT("Retained id type change"), RootMarkup(TEXT("<text id=\"card\">replacement</text>")), TEXT("cannot change kind"));
    TestEqual(TEXT("Id type failure occurs before prepare"), Stats->PrepareCalls, AcceptedPrepares + 4);
    AssertRejected(TEXT("Retained custom tag change"), RootMarkup(TEXT("<alternate-retained id=\"card\" state=\"stable\" label=\"updated\"/>")), TEXT("cannot change kind"));
    TestEqual(TEXT("Custom tag failure occurs before prepare"), Stats->PrepareCalls, AcceptedPrepares + 4);

    if (!TestTrue(TEXT("Fixture tracked the initial retained component"), !Stats->Instances.IsEmpty())) { return false; }
    const TWeakPtr<FComponent> RemovedComponent = Stats->Instances[0];
    const TWeakPtr<SEditableText> RemovedInput = Input;
    FocusedLeaf.Reset();
    Input.Reset();
    if (!TestTrue(TEXT("Valid retained removal succeeds"), View->TryReload(RootMarkup(TEXT("<text id=\"replacement\">removed</text>")), TEXT(""), TEXT("RetainedRemoval")).Succeeded)) { return false; }
    const TSharedRef<SWidget> RemovedRoot = RegionContent(View);
    TestTrue(TEXT("Retained removal replaces authored root"), RemovedRoot != UpdatedRoot);
    TestFalse(TEXT("Removed retained component clears focus"), Slate.GetUserFocusedWidget(0).IsValid());
    TestFalse(TEXT("Held pre-removal root no longer owns focused retained leaf"), Slate.HasUserFocusedDescendants(UpdatedRoot, 0));
    TestFalse(TEXT("Held old root and widget do not retain removed component"), RemovedComponent.IsValid());
    TestTrue(TEXT("Intentional external widget reference remains valid until released"), UpdatedInput.IsValid());
    UpdatedInput.Reset();
    TestFalse(TEXT("Held old root does not retain removed component widget"), RemovedInput.IsValid());

    if (!TestTrue(TEXT("Retained component can be re-added"), View->TryReload(RetainedMarkup(TEXT("stable"), TEXT("readded")), TEXT(""), TEXT("RetainedReadded")).Succeeded)) { return false; }
    const TSharedRef<SWidget> ReaddedRoot = RegionContent(View);
    const TSharedPtr<SEditableText> ReaddedInput = StaticCastSharedPtr<SEditableText>(FindTagged(ReaddedRoot, TEXT("retained-input")));
    if (!TestTrue(TEXT("Re-added retained component creates a new widget"), ReaddedInput.IsValid())) { return false; }
    TestEqual(TEXT("Re-add creates a second retained instance"), Stats->FactoryCalls, 2);
    TestEqual(TEXT("Re-add reads a widget only from the new retained instance"), Stats->GetWidgetCalls, 2);
    TestEqual(TEXT("Re-add prepares the new retained instance"), Stats->PrepareCalls, AcceptedPrepares + 5);
    TestEqual(TEXT("Re-add commits its config once"), Stats->CommitCalls, AcceptedCommits + 1);
    TestEqual(TEXT("Re-add commits fresh config"), Stats->CommittedLabel, FString(TEXT("readded")));

    if (!TestTrue(TEXT("External input receives focus"), Slate.SetKeyboardFocus(ExternalInput, EFocusCause::SetDirectly))) { return false; }
    TestTrue(TEXT("Retained reload leaves external focus unchanged"), View->TryReload(RetainedMarkup(TEXT("stable"), TEXT("external")), TEXT(""), TEXT("RetainedExternalFocus")).Succeeded);
    TestTrue(TEXT("External focus remains outside retained reload"), Slate.GetUserFocusedWidget(0) == ExternalInput);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiRetainedRegistry_Aliases,
    "Ck.UiAuthoring.RetainedRegistry.RejectsDuplicateAndAliasedOutputs",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiRetainedRegistry_Aliases::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_retained_registry;
    const TSharedRef<FRetainedFixtureStats> Stats = MakeShared<FRetainedFixtureStats>();
    auto Registry = FCkUiWidgetRegistry{};
    if (!TestTrue(TEXT("Primary retained fixture registers"), Registry.Register(MakeRetainedRegistration(Stats)).Succeeded)) { return false; }

    const TSharedPtr<FComponent> ParentedComponent = MakeShared<FComponent>(Stats);
    const TSharedRef<SBox> Parent = SNew(SBox)[ParentedComponent->GetWidget()];
    auto Parented = MakeRetainedRegistration(Stats);
    Parented.Schema.Tag = TEXT("parented-retained");
    Parented.RetainedFactory = [ParentedComponent](const FCkUiCustomWidgetArguments&, FString&) -> TSharedPtr<ICkUiRetainedWidget> { return ParentedComponent; };
    if (!TestTrue(TEXT("Parented retained fixture registers"), Registry.Register(MoveTemp(Parented)).Succeeded)) { return false; }

    auto Alias = MakeRetainedRegistration(Stats);
    Alias.Schema.Tag = TEXT("alias-retained");
    Alias.RetainedFactory = [Stats](const FCkUiCustomWidgetArguments&, FString& OutFailure) -> TSharedPtr<ICkUiRetainedWidget>
    {
        const TSharedPtr<FComponent> Existing = Stats->Instances.IsEmpty() ? nullptr : Stats->Instances[0].Pin();
        if (!Existing.IsValid()) { OutFailure = TEXT("Expected existing retained output."); }
        return Existing;
    };
    if (!TestTrue(TEXT("Alias retained fixture registers"), Registry.Register(MoveTemp(Alias)).Succeeded)) { return false; }

    const TSharedRef<FComponent> SharedComponent = MakeShared<FComponent>(Stats);
    const TSharedRef<SWidget> SharedOutput = SharedComponent->GetWidget();
    auto SharedStateless = FCkUiCustomWidgetRegistration{};
    SharedStateless.Schema.Tag = TEXT("shared-stateless");
    SharedStateless.Factory = [SharedOutput](const FCkUiCustomWidgetArguments&, FString&) -> TSharedPtr<SWidget> { return SharedOutput; };
    if (!TestTrue(TEXT("Shared stateless fixture registers"), Registry.Register(MoveTemp(SharedStateless)).Succeeded)) { return false; }
    auto SharedRetained = MakeRetainedRegistration(Stats);
    SharedRetained.Schema.Tag = TEXT("shared-retained");
    SharedRetained.RetainedFactory = [SharedComponent](const FCkUiCustomWidgetArguments&, FString&) -> TSharedPtr<ICkUiRetainedWidget> { return SharedComponent; };
    if (!TestTrue(TEXT("Shared retained fixture registers"), Registry.Register(MoveTemp(SharedRetained)).Succeeded)) { return false; }

    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, {}, Registry.CreateSnapshot());
    View->GetRegion(TEXT("only"));
    if (!TestTrue(TEXT("Primary retained fixture loads"), View->TryReload(RetainedMarkup(TEXT("stable"), TEXT("first")), TEXT(""), TEXT("RetainedAliasInitial")).Succeeded)) { return false; }
    const TSharedRef<SWidget> AcceptedRoot = RegionContent(View);
    const int64 AcceptedRevision = View->GetRevision();
    const int32 FactoryBeforeRejects = Stats->FactoryCalls;
    const auto AssertReject = [this, &View, &AcceptedRoot, AcceptedRevision](const FString& InName, const FString& InMarkup, const FString& InNeedle)
    {
        const FCkUiLoadResult Result = View->TryReload(InMarkup, TEXT(""), InName);
        TestFalse(*InName, Result.Succeeded);
        TestTrue(*(InName + TEXT(" reports the retained-output error")), HasError(Result, InNeedle));
        TestEqual(*(InName + TEXT(" preserves revision")), View->GetRevision(), AcceptedRevision);
        TestTrue(*(InName + TEXT(" preserves mounted root")), RegionContent(View) == AcceptedRoot);
    };

    AssertReject(TEXT("Duplicate retained id"), RootMarkup(TEXT("<retained id=\"card\" state=\"stable\" label=\"first\"/><retained id=\"card\" state=\"stable\" label=\"second\"/>")), TEXT("duplicate id"));
    TestEqual(TEXT("Duplicate id is rejected before retained factory work"), Stats->FactoryCalls, FactoryBeforeRejects);
    AssertReject(TEXT("Parented retained output"), RootMarkup(TEXT("<parented-retained id=\"parented\" state=\"stable\" label=\"parented\"/>")), TEXT("already mounted"));
    AssertReject(TEXT("Previous retained output reused by another id"), RootMarkup(TEXT("<retained id=\"card\" state=\"stable\" label=\"first\"/><alias-retained id=\"alias\" state=\"stable\" label=\"alias\"/>")), TEXT("already mounted"));
    TestTrue(TEXT("Parented fixture remains mounted under its original owner"), ParentedComponent->GetWidget()->GetParentWidget().Get() == &Parent.Get());

    const TSharedRef<const FCkUiWidgetRegistrySnapshot> RegistryView = Registry.CreateSnapshot();
    const TSharedRef<FCkUiView> MixedView = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, {}, RegistryView);
    MixedView->GetRegion(TEXT("only"));
    const FString StatelessThenRetained = RootMarkup(TEXT("<shared-stateless id=\"stateless\"/><shared-retained id=\"retained\" state=\"stable\" label=\"shared\"/>"));
    const FString RetainedThenStateless = RootMarkup(TEXT("<shared-retained id=\"retained\" state=\"stable\" label=\"shared\"/><shared-stateless id=\"stateless\"/>"));
    const FCkUiLoadResult FirstStagedAlias = MixedView->TryReload(StatelessThenRetained, TEXT(""), TEXT("RetainedAliasStatelessFirst"));
    TestFalse(TEXT("New stateless output cannot alias a new retained output"), FirstStagedAlias.Succeeded);
    TestTrue(TEXT("Stateless-first alias rejects during parent or shared-widget admission"), HasError(FirstStagedAlias, TEXT("already mounted")) || HasError(FirstStagedAlias, TEXT("aliases")));
    TestEqual(TEXT("Stateless-first alias publishes no revision"), MixedView->GetRevision(), int64{0});
    const FCkUiLoadResult SecondStagedAlias = MixedView->TryReload(RetainedThenStateless, TEXT(""), TEXT("RetainedAliasRetainedFirst"));
    TestFalse(TEXT("New retained output cannot alias a new stateless output"), SecondStagedAlias.Succeeded);
    TestTrue(TEXT("Retained-first alias reports a shared widget"), HasError(SecondStagedAlias, TEXT("aliases")));
    TestEqual(TEXT("Retained-first alias publishes no revision"), MixedView->GetRevision(), int64{0});
    const FCkUiLoadResult DuplicateNewRetained = MixedView->TryReload(RootMarkup(TEXT("<shared-retained id=\"first\" state=\"stable\" label=\"shared\"/><shared-retained id=\"second\" state=\"stable\" label=\"shared\"/>")), TEXT(""), TEXT("RetainedAliasDuplicateNew"));
    TestFalse(TEXT("Two new retained ids cannot publish one shared output"), DuplicateNewRetained.Succeeded);
    TestTrue(TEXT("Two new retained ids report shared-widget admission"), HasError(DuplicateNewRetained, TEXT("aliases")));
    TestEqual(TEXT("Two new retained ids publish no revision"), MixedView->GetRevision(), int64{0});

    const TSharedRef<FCkUiView> PriorView = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, {}, RegistryView);
    PriorView->GetRegion(TEXT("only"));
    if (!TestTrue(TEXT("Shared stateless fixture mounts before retained alias attempt"), PriorView->TryReload(RootMarkup(TEXT("<shared-stateless id=\"stateless\"/>")), TEXT(""), TEXT("RetainedAliasPriorStateless")).Succeeded)) { return false; }
    const TSharedRef<SWidget> PriorRoot = RegionContent(PriorView);
    const int64 PriorRevision = PriorView->GetRevision();
    const FCkUiLoadResult PriorAlias = PriorView->TryReload(RootMarkup(TEXT("<shared-retained id=\"retained\" state=\"stable\" label=\"shared\"/>")), TEXT(""), TEXT("RetainedAliasPriorOutput"));
    TestFalse(TEXT("Retained output cannot reuse a prior stateless descendant"), PriorAlias.Succeeded);
    TestTrue(TEXT("Prior stateless descendant alias reports already mounted output"), HasError(PriorAlias, TEXT("already mounted")));
    TestEqual(TEXT("Prior stateless descendant alias preserves revision"), PriorView->GetRevision(), PriorRevision);
    TestTrue(TEXT("Prior stateless descendant alias preserves root"), RegionContent(PriorView) == PriorRoot);
    return true;
}

#endif
