#include "CkSlateLayout/CkFlexText.h"
#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/CkFlexLayoutTypes.h"
#include "Styling/CoreStyle.h"
#include "CkSlateLayout/SCkUiRepeat.h"
#include "CkSlateLayout/CkUiWidgetRegistry.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Framework/Application/SlateApplication.h"
#include "Layout/Children.h"
#include "Misc/AutomationTest.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Input/SSearchBox.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_repeat
{
    struct FProbe final
    {
        int32 FactoryCalls = 0;
        int32 PrepareCalls = 0;
        int32 CommitCalls = 0;
        int32 FailingFactoryCalls = 0;
    };

    struct FRepeatProbeState final
    {
        TAttribute<FText> Title;
        TAttribute<bool> Visible;
        TAttribute<FLinearColor> Tint;
    };

    class FRepeatProbeWidget;

    class FPreparedRepeatProbeUpdate final : public ICkUiPreparedWidgetUpdate
    {
    public:
        FPreparedRepeatProbeUpdate(const TSharedRef<FRepeatProbeWidget>& InWidget, const TSharedRef<FProbe>& InProbe, const TAttribute<FText>& InTitle,
            const TAttribute<bool>& InVisible, const TAttribute<FLinearColor>& InTint)
            : _Widget(InWidget), _Probe(InProbe), _Title(InTitle), _Visible(InVisible), _Tint(InTint) {}

        virtual void Commit() noexcept override;

    private:
        TSharedRef<FRepeatProbeWidget> _Widget;
        TSharedRef<FProbe> _Probe;
        TAttribute<FText> _Title;
        TAttribute<bool> _Visible;
        TAttribute<FLinearColor> _Tint;
    };

    class FRepeatProbeWidget final : public ICkUiRetainedWidget, public TSharedFromThis<FRepeatProbeWidget>
    {
    public:
        FRepeatProbeWidget(const TSharedRef<FProbe>& InProbe, const TAttribute<FText>& InTitle, const TAttribute<bool>& InVisible, const TAttribute<FLinearColor>& InTint)
            : _Probe(InProbe), _State(MakeShared<FRepeatProbeState>())
        {
            SetBindings(InTitle, InVisible, InTint);
            const TSharedRef<FRepeatProbeState> State = _State;
            _Widget = SNew(STextBlock).Tag(FName(TEXT("repeat-probe")))
                .Text_Lambda([State]() { return State->Title.Get(FText::GetEmpty()); })
                .Visibility_Lambda([State]() { return State->Visible.Get(false) ? EVisibility::Visible : EVisibility::Collapsed; })
                .ColorAndOpacity_Lambda([State]() { return FSlateColor(State->Tint.Get(FLinearColor::Transparent)); });
        }

        virtual auto GetWidget() const -> TSharedRef<SWidget> override { return _Widget.ToSharedRef(); }

        virtual auto PrepareReload(const FCkUiCustomWidgetArguments& InArguments, FString& OutFailure) const -> TUniquePtr<ICkUiPreparedWidgetUpdate> override
        {
            ++_Probe->PrepareCalls;
            const TAttribute<FText>* Title = InArguments.TextBindings.Find(TEXT("title"));
            const TAttribute<bool>* Visible = InArguments.BoolBindings.Find(TEXT("shown"));
            const TAttribute<FLinearColor>* Tint = InArguments.ColorBindings.Find(TEXT("tint"));
            if (Title == nullptr || Visible == nullptr || Tint == nullptr)
            {
                OutFailure = TEXT("Repeat probe bindings are required.");
                return nullptr;
            }
            return MakeUnique<FPreparedRepeatProbeUpdate>(ConstCastSharedRef<FRepeatProbeWidget>(AsShared()), _Probe, *Title, *Visible, *Tint);
        }

        void SetBindings(const TAttribute<FText>& InTitle, const TAttribute<bool>& InVisible, const TAttribute<FLinearColor>& InTint) noexcept
        {
            _State->Title = InTitle;
            _State->Visible = InVisible;
            _State->Tint = InTint;
        }

    private:
        TSharedRef<FProbe> _Probe;
        TSharedRef<FRepeatProbeState> _State;
        TSharedPtr<STextBlock> _Widget;
    };

    void FPreparedRepeatProbeUpdate::Commit() noexcept
    {
        ++_Probe->CommitCalls;
        _Widget->SetBindings(_Title, _Visible, _Tint);
    }

    auto Schema() -> TArray<FCkUiFieldSchema>
    {
        return {{TEXT("title"), ECkUiFieldKind::Text}, {TEXT("visible"), ECkUiFieldKind::Bool}, {TEXT("tint"), ECkUiFieldKind::Color}};
    }

    auto Record(const FString& InKey, const FString& InTitle, const bool InVisible = true) -> FCkUiRecordData
    {
        auto Result = FCkUiRecordData{};
        Result.Key = InKey;
        Result.Fields.Add(TEXT("title"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(InTitle)});
        Result.Fields.Add(TEXT("visible"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Bool, .Bool = InVisible});
        Result.Fields.Add(TEXT("tint"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Color, .Color = InVisible ? FLinearColor::Green : FLinearColor::Red});
        return Result;
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

    auto FindSearch(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SSearchBox>
    {
        if (InRoot->GetTag() == InTag && InRoot->GetTypeAsString() == TEXT("SSearchBox")) { return StaticCastSharedRef<SSearchBox>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SSearchBox> Found = FindSearch(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag); Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto FindText(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<STextBlock>
    {
        if (InRoot->GetTag() == InTag && InRoot->GetTypeAsString() == TEXT("STextBlock")) { return StaticCastSharedRef<STextBlock>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<STextBlock> Found = FindText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag); Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto RegionRoot(const TSharedRef<FCkUiView>& InView) -> TSharedRef<SWidget>
    {
        return StaticCastSharedRef<SBox>(InView->GetRegion(TEXT("main")))->GetChildren()->GetChildAt(0);
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

    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    auto TestSuccessfulLoad(FAutomationTestBase& InTest, const FString& InDescription, const FCkUiLoadResult& InResult) -> bool
    {
        if (!InResult.Succeeded)
        { InTest.AddError(FString::Printf(TEXT("%s errors:\n%s"), *InDescription, *FString::Join(InResult.Errors, TEXT("\n")))); }
        return InTest.TestTrue(InDescription, InResult.Succeeded);
    }

    auto Markup(const FString& InItemChildren) -> FString
    {
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><repeat id=\"rows\" bind=\"items\"><row id=\"item\"><search id=\"query\" bind=\"query\"/><repeat-probe id=\"probe\" title-field=\"title\" shown-field=\"visible\" tint-field=\"tint\"/><button id=\"toggle\" item-action=\"toggle\" bind-field=\"title\"/>%s</row></repeat></column></region></ui>"), *InItemChildren);
    }

    auto RegisterProbes(const TSharedRef<FProbe>& InProbe, FCkUiWidgetRegistry& InRegistry) -> bool
    {
        auto Probe = FCkUiCustomWidgetRegistration{};
        Probe.Schema.Tag = TEXT("repeat-probe");
        Probe.Schema.Properties = {
            {TEXT("title"), ECkUiCustomPropertyKind::TextBinding, true},
            {TEXT("shown"), ECkUiCustomPropertyKind::BoolBinding, true},
            {TEXT("tint"), ECkUiCustomPropertyKind::ColorBinding, true},
        };
        Probe.RetainedFactory = [InProbe](const FCkUiCustomWidgetArguments& InArguments, FString& OutFailure) -> TSharedPtr<ICkUiRetainedWidget>
        {
            const TAttribute<FText>* Title = InArguments.TextBindings.Find(TEXT("title"));
            const TAttribute<bool>* Visible = InArguments.BoolBindings.Find(TEXT("shown"));
            const TAttribute<FLinearColor>* Tint = InArguments.ColorBindings.Find(TEXT("tint"));
            if (Title == nullptr || Visible == nullptr || Tint == nullptr)
            {
                OutFailure = TEXT("Repeat probe bindings are required.");
                return nullptr;
            }
            ++InProbe->FactoryCalls;
            return MakeShared<FRepeatProbeWidget>(InProbe, *Title, *Visible, *Tint);
        };
        if (!InRegistry.Register(MoveTemp(Probe)).Succeeded) { return false; }

        auto Failing = FCkUiCustomWidgetRegistration{};
        Failing.Schema.Tag = TEXT("repeat-fail");
        Failing.Schema.Properties = {{TEXT("title"), ECkUiCustomPropertyKind::TextBinding, true}};
        Failing.Factory = [InProbe](const FCkUiCustomWidgetArguments& InArguments, FString& OutFailure) -> TSharedPtr<SWidget>
        {
            ++InProbe->FailingFactoryCalls;
            const TAttribute<FText>* Title = InArguments.TextBindings.Find(TEXT("title"));
            if (Title != nullptr && Title->Get(FText::GetEmpty()).ToString() == TEXT("Bravo"))
            {
                OutFailure = TEXT("Expected repeat child factory failure.");
                return nullptr;
            }
            return SNew(STextBlock).Tag(FName(TEXT("repeat-fail")));
        };
        return InRegistry.Register(MoveTemp(Failing)).Succeeded;
    }

    auto MakeView(const TSharedPtr<FCkUiCollection>& InCollection, const TSharedPtr<const FCkUiWidgetRegistrySnapshot>& InRegistry,
        TArray<FString>& InOutActions, FText& InOutQuery) -> TSharedRef<FCkUiView>
    {
        auto Data = FCkUiView::FDataBindings{};
        Data.Collections.Add(TEXT("items"), InCollection);
        Data.Text.Add(TEXT("query"), TAttribute<FText>::CreateLambda([&InOutQuery]() { return InOutQuery; }));
        Data.TextChanged.Add(TEXT("query"), FOnTextChanged::CreateLambda([&InOutQuery](const FText& InText) { InOutQuery = InText; }));
        Data.ItemActions.Add(TEXT("toggle"), FCkUiOnItemAction::CreateLambda([&InOutActions](const FString InKey) { InOutActions.Add(InKey); }));
        return FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, MoveTemp(Data), InRegistry);
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiRepeat_EmptyPreflight,
    "Ck.UiAuthoring.Repeat.EmptyPreflight",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiRepeat_EmptyPreflight::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_repeat;
    const TSharedRef<FProbe> Probe = MakeShared<FProbe>();
    auto Registry = FCkUiWidgetRegistry{};
    if (!TestTrue(TEXT("Repeat probe registration succeeds"), RegisterProbes(Probe, Registry))) { return false; }
    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Repeat collection schema creates"), FCkUiCollection::TryCreate(Schema(), Collection).Succeeded) || !Collection.IsValid()) { return false; }
    TArray<FString> Actions;
    FText Query;
    const TSharedRef<FCkUiView> View = MakeView(Collection, Registry.CreateSnapshot(), Actions, Query);
    View->GetRegion(TEXT("main"));
    if (!TestSuccessfulLoad(*this, TEXT("Empty repeat validates and loads its item schema"), View->TryReload(Markup(TEXT("")), TEXT(""), TEXT("UiRepeatEmpty")))) { return false; }
    const TSharedPtr<SCkUiRepeat> Repeat = View->GetRepeat(TEXT("rows"));
    TestTrue(TEXT("Empty repeat is retained and has no item failure"), Repeat.IsValid() && Repeat->GetItemCount() == 0 && Repeat->GetLastFailure().IsEmpty());
    TestEqual(TEXT("Empty repeat does not instantiate item custom widgets"), Probe->FactoryCalls, 0);

    const int64 Revision = View->GetRevision();
    const FCkUiLoadResult Invalid = View->TryReload(Markup(TEXT("<repeat-probe id=\"missing-fields\"/>")), TEXT(""), TEXT("UiRepeatMissingFields"));
    TestFalse(TEXT("Repeat child schema rejects even with no records"), Invalid.Succeeded);
    TestEqual(TEXT("Empty repeat schema rejection preserves revision"), View->GetRevision(), Revision);
    TestEqual(TEXT("Empty repeat schema rejection invokes no factory"), Probe->FactoryCalls, 0);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiRepeat_KeyedRetentionAndActions,
    "Ck.UiAuthoring.Repeat.KeyedRetentionAndActions",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiRepeat_KeyedRetentionAndActions::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_repeat;
    const TSharedRef<FProbe> Probe = MakeShared<FProbe>();
    auto Registry = FCkUiWidgetRegistry{};
    if (!TestTrue(TEXT("Repeat runtime probe registration succeeds"), RegisterProbes(Probe, Registry))) { return false; }
    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Repeat runtime collection creates"), FCkUiCollection::TryCreate(Schema(), Collection).Succeeded)) { return false; }
    if (!TestTrue(TEXT("Repeat runtime records publish"), Collection->TrySetRecords({Record(TEXT("a"), TEXT("Alpha")), Record(TEXT("b"), TEXT("Bravo"))}).Succeeded)) { return false; }
    TArray<FString> Actions;
    FText Query;
    const TSharedRef<FCkUiView> View = MakeView(Collection, Registry.CreateSnapshot(), Actions, Query);
    View->GetRegion(TEXT("main"));
    if (!TestSuccessfulLoad(*this, TEXT("Repeat runtime document loads"), View->TryReload(Markup(TEXT("")), TEXT(""), TEXT("UiRepeatRuntime")))) { return false; }
    const TSharedPtr<SCkUiRepeat> Repeat = View->GetRepeat(TEXT("rows"));
    if (!TestTrue(TEXT("Repeat projects both stable keys"), Repeat.IsValid() && Repeat->GetItemCount() == 2)) { return false; }
    const TSharedPtr<SWidget> AItem = Repeat->GetItemWidget(TEXT("a"));
    const TSharedPtr<SWidget> BItem = Repeat->GetItemWidget(TEXT("b"));
    if (!TestTrue(TEXT("Repeat exposes both mounted item roots"), AItem.IsValid() && BItem.IsValid())) { return false; }
    const TSharedPtr<SSearchBox> ASearch = FindSearch(AItem.ToSharedRef(), TEXT("query"));
    const TSharedPtr<STextBlock> AProbe = FindText(AItem.ToSharedRef(), TEXT("repeat-probe"));
    const TSharedPtr<SButton> AButton = FindButton(AItem.ToSharedRef(), TEXT("toggle"));
    const TSharedPtr<SButton> BButton = FindButton(BItem.ToSharedRef(), TEXT("toggle"));
    if (!TestTrue(TEXT("Repeat item mounts real native search custom scope and action button"), ASearch.IsValid() && AProbe.IsValid() && AButton.IsValid() && BButton.IsValid())) { return false; }
    AButton->SimulateClick();
    BButton->SimulateClick();
    TestTrue(TEXT("Item actions dispatch their own stable keys without table selection"), Actions == TArray<FString>{TEXT("a"), TEXT("b")});

    if (!TestTrue(TEXT("Same-key value change and reorder publish"), Collection->TrySetRecords({Record(TEXT("b"), TEXT("Bravo updated"), false), Record(TEXT("a"), TEXT("Alpha updated"))}).Succeeded)
        || !TestTrue(TEXT("Repeat refreshes changed and reordered records"), Repeat->TryRefresh())) { return false; }
    const TSharedPtr<SWidget> UpdatedA = Repeat->GetItemWidget(TEXT("a"));
    const TSharedPtr<SWidget> UpdatedB = Repeat->GetItemWidget(TEXT("b"));
    if (!TestTrue(TEXT("Updated repeat keys remain mounted"), UpdatedA.IsValid() && UpdatedB.IsValid())) { return false; }
    TestTrue(TEXT("Same keys retain their repeat item roots across value change and reorder"), UpdatedA == AItem && UpdatedB == BItem);
    TestTrue(TEXT("Same key retains native search and custom widget identity"), FindSearch(UpdatedA.ToSharedRef(), TEXT("query")) == ASearch
        && FindText(UpdatedA.ToSharedRef(), TEXT("repeat-probe")) == AProbe);
    const TSharedPtr<SButton> UpdatedBButton = FindButton(UpdatedB.ToSharedRef(), TEXT("toggle"));
    const FChildren* UpdatedBChildren = UpdatedBButton.IsValid() ? UpdatedBButton->GetChildren() : nullptr;
    TSharedPtr<SCkFlexText> UpdatedBLabel;
    if (UpdatedBChildren != nullptr && UpdatedBChildren->Num() == 1
        && UpdatedBChildren->GetChildAt(0)->GetTypeAsString() == TEXT("SCkFlexText"))
    {
        UpdatedBLabel = StaticCastSharedRef<SCkFlexText>(ConstCastSharedRef<SWidget>(UpdatedBChildren->GetChildAt(0)));
    }
    TestTrue(TEXT("Per-item field binding keeps a native button label"), UpdatedBLabel.IsValid());
    if (UpdatedBLabel.IsValid())
    {
        TestEqual(TEXT("Per-item field binding updates the retained button label"), UpdatedBLabel->GetText().ToString(), FString(TEXT("Bravo updated")));
    }
    const TSharedPtr<STextBlock> UpdatedAProbe = FindText(UpdatedA.ToSharedRef(), TEXT("repeat-probe"));
    if (!TestTrue(TEXT("Updated custom item remains mounted"), UpdatedAProbe.IsValid())) { return false; }
    TestEqual(TEXT("Custom field binding updates live scoped text"), UpdatedAProbe->GetText().ToString(), FString(TEXT("Alpha updated")));

    const int64 BeforeReload = View->GetRevision();
    if (!TestSuccessfulLoad(*this, TEXT("Compatible parent reload succeeds"), View->TryReload(Markup(TEXT("<text id=\"compatible\">Reloaded</text>")), TEXT(""), TEXT("UiRepeatCompatible")))) { return false; }
    const TSharedPtr<SCkUiRepeat> ReloadedRepeat = View->GetRepeat(TEXT("rows"));
    TestEqual(TEXT("Compatible repeat reload advances parent revision once"), View->GetRevision(), BeforeReload + 1);
    TestTrue(TEXT("Compatible reload retains per-key native and custom item identities"), ReloadedRepeat == Repeat
        && ReloadedRepeat->GetItemWidget(TEXT("a")) == AItem && FindSearch(AItem.ToSharedRef(), TEXT("query")) == ASearch
        && FindText(AItem.ToSharedRef(), TEXT("repeat-probe")) == AProbe);
    TestTrue(TEXT("Retained custom probes prepare and publish detached updates without recreation"), Probe->FactoryCalls == 2
        && Probe->PrepareCalls >= 2 && Probe->CommitCalls == Probe->PrepareCalls);

    if (!TestTrue(TEXT("Removing key B publishes"), Collection->TrySetRecords({Record(TEXT("a"), TEXT("Alpha updated"))}).Succeeded)
        || !TestTrue(TEXT("Repeat removes B"), ReloadedRepeat->TryRefresh() && !ReloadedRepeat->GetItemWidget(TEXT("b")).IsValid())) { return false; }
    const int32 ActionsBeforeStale = Actions.Num();
    BButton->SimulateClick();
    TestEqual(TEXT("Held removed item button cannot dispatch"), Actions.Num(), ActionsBeforeStale);
    if (!TestTrue(TEXT("Reinserting B publishes"), Collection->TrySetRecords({Record(TEXT("a"), TEXT("Alpha updated")), Record(TEXT("b"), TEXT("Bravo reinserted"))}).Succeeded)
        || !TestTrue(TEXT("Repeat reinserts B"), ReloadedRepeat->TryRefresh())) { return false; }
    const TSharedPtr<SWidget> ReinsertedBItem = ReloadedRepeat->GetItemWidget(TEXT("b"));
    if (!TestTrue(TEXT("Reinserted item is mounted"), ReinsertedBItem.IsValid())) { return false; }
    const TSharedPtr<SButton> ReinsertedB = FindButton(ReinsertedBItem.ToSharedRef(), TEXT("toggle"));
    if (!TestTrue(TEXT("Reinserted key gets a new native button"), ReinsertedB.IsValid() && ReinsertedB != BButton)) { return false; }
    ReinsertedB->SimulateClick();
    TestEqual(TEXT("Reinserted item action still targets its stable key"), Actions.Last(), FString(TEXT("b")));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiRepeat_FailedChildAtomicity,
    "Ck.UiAuthoring.Repeat.FailedChildAtomicity",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiRepeat_FailedChildAtomicity::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_repeat;
    const TSharedRef<FProbe> Probe = MakeShared<FProbe>();
    auto Registry = FCkUiWidgetRegistry{};
    if (!TestTrue(TEXT("Repeat atomicity probe registration succeeds"), RegisterProbes(Probe, Registry))) { return false; }
    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Repeat atomicity collection creates"), FCkUiCollection::TryCreate(Schema(), Collection).Succeeded)
        || !TestTrue(TEXT("Repeat atomicity records publish"), Collection->TrySetRecords({Record(TEXT("a"), TEXT("Alpha")), Record(TEXT("b"), TEXT("Bravo"))}).Succeeded)) { return false; }
    TArray<FString> Actions;
    FText Query;
    const TSharedRef<FCkUiView> View = MakeView(Collection, Registry.CreateSnapshot(), Actions, Query);
    const TSharedRef<SWidget> Region = View->GetRegion(TEXT("main"));
    if (!TestSuccessfulLoad(*this, TEXT("Repeat atomicity baseline loads"), View->TryReload(Markup(TEXT("")), TEXT(""), TEXT("UiRepeatAtomicBaseline")))) { return false; }
    const TSharedRef<SWidget> Root = RegionRoot(View);
    const TSharedPtr<SCkUiRepeat> Repeat = View->GetRepeat(TEXT("rows"));
    if (!TestTrue(TEXT("Repeat atomicity baseline projects both items"), Repeat.IsValid() && Repeat->GetItemCount() == 2)) { return false; }
    const TSharedPtr<SWidget> Item = Repeat->GetItemWidget(TEXT("a"));
    const TSharedPtr<SButton> Button = Item.IsValid() ? FindButton(Item.ToSharedRef(), TEXT("toggle")) : nullptr;
    if (!TestTrue(TEXT("Repeat atomicity baseline has mounted action"), Button.IsValid())) { return false; }
    const int64 Revision = View->GetRevision();
    const FCkUiLoadResult Rejected = View->TryReload(Markup(TEXT("<repeat-fail id=\"late\" title-field=\"title\"/>")), TEXT(""), TEXT("UiRepeatAtomicFailure"));
    TestFalse(TEXT("Later repeat child factory failure rejects parent reload"), Rejected.Succeeded);
    TestEqual(TEXT("Later child factory failure preserves parent revision"), View->GetRevision(), Revision);
    TestTrue(TEXT("Later child factory failure preserves mounted parent root and item identity"), RegionRoot(View) == Root
        && View->GetRepeat(TEXT("rows")) == Repeat && Repeat->GetItemWidget(TEXT("a")) == Item);
    TestTrue(TEXT("Later Bravo child failure reports repeat staging failure"), !Rejected.Errors.IsEmpty() && Probe->FailingFactoryCalls == 2);
    Button->SimulateClick();
    TestTrue(TEXT("Old mounted item action remains active after rejected reload"), Actions == TArray<FString>{TEXT("a")});
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiRepeat_RemovedItemClearsFocus,
    "Ck.UiAuthoring.Repeat.RemovedItemClearsFocus",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiRepeat_RemovedItemClearsFocus::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_repeat;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Repeat focus removal requires an initialized Slate application.")); return false; }

    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope(Slate);
    const TSharedRef<FProbe> Probe = MakeShared<FProbe>();
    auto Registry = FCkUiWidgetRegistry{};
    if (!TestTrue(TEXT("Repeat focus probe registration succeeds"), RegisterProbes(Probe, Registry))) { return false; }
    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Repeat focus collection creates"), FCkUiCollection::TryCreate(Schema(), Collection).Succeeded)
        || !TestTrue(TEXT("Repeat focus records publish"), Collection->TrySetRecords({Record(TEXT("a"), TEXT("Alpha")), Record(TEXT("b"), TEXT("Bravo"))}).Succeeded)) { return false; }
    TArray<FString> Actions;
    FText Query;
    const TSharedRef<FCkUiView> View = MakeView(Collection, Registry.CreateSnapshot(), Actions, Query);
    const TSharedRef<SWidget> Region = View->GetRegion(TEXT("main"));
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D(360.0f, 180.0f))
        .CreateTitleBar(false).HasCloseButton(false).FocusWhenFirstShown(false)[Region];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    if (!TestSuccessfulLoad(*this, TEXT("Repeat focus fixture loads"), View->TryReload(Markup(TEXT("")), TEXT(""), TEXT("UiRepeatFocusRemoval")))) { return false; }
    Tick(Slate);

    const TSharedPtr<SCkUiRepeat> Repeat = View->GetRepeat(TEXT("rows"));
    const TSharedPtr<SWidget> BItem = Repeat.IsValid() ? Repeat->GetItemWidget(TEXT("b")) : nullptr;
    const TSharedPtr<SSearchBox> BSearch = BItem.IsValid() ? FindSearch(BItem.ToSharedRef(), TEXT("query")) : nullptr;
    if (!TestTrue(TEXT("Repeat focus fixture mounts B search"), BItem.IsValid() && BSearch.IsValid())
        || !TestTrue(TEXT("Slate focuses B search before removal"), Slate.SetKeyboardFocus(BSearch.ToSharedRef(), EFocusCause::SetDirectly))) { return false; }
    TestTrue(TEXT("B item owns the focused descendant before removal"), Slate.HasUserFocusedDescendants(BItem.ToSharedRef(), 0));

    if (!TestTrue(TEXT("Removing focused B publishes"), Collection->TrySetRecords({Record(TEXT("a"), TEXT("Alpha"))}).Succeeded)
        || !TestTrue(TEXT("Repeat removes focused B"), Repeat->TryRefresh() && !Repeat->GetItemWidget(TEXT("b")).IsValid())) { return false; }
    Tick(Slate);
    TestFalse(TEXT("Removing a repeat item clears Slate focus"), Slate.GetUserFocusedWidget(0).IsValid());
    TestFalse(TEXT("Held removed repeat item no longer owns Slate focus"), Slate.HasUserFocusedDescendants(BItem.ToSharedRef(), 0));
    Collection->TrySetRecords({Record(TEXT("a"), TEXT("Alpha")), Record(TEXT("b"), TEXT("Bravo"))});
    if (!TestTrue(TEXT("Repeat remounts B for parent reload"), Repeat->TryRefresh())) { return false; }
    Tick(Slate);
    const auto RestoredB = Repeat->GetItemWidget(TEXT("b"));
    const auto RestoredSearch = FindSearch(RestoredB.ToSharedRef(), TEXT("query"));
    if (!TestTrue(TEXT("Restored B takes focus"), RestoredSearch.IsValid()
        && Slate.SetKeyboardFocus(RestoredSearch.ToSharedRef(), EFocusCause::SetDirectly))) { return false; }
    Collection->TrySetRecords({Record(TEXT("a"), TEXT("Alpha"))});
    if (!TestSuccessfulLoad(*this, TEXT("Parent reload removes focused B before repeat tick"),
        View->TryReload(Markup(TEXT("")), TEXT(""), TEXT("UiRepeatParentRemoval")))) { return false; }
    TestFalse(TEXT("Retained repeat container cannot preserve removed descendant focus"), Slate.GetUserFocusedWidget(0).IsValid());
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiRepeat_IncrementalFailureAtomicity,
    "Ck.UiAuthoring.Repeat.IncrementalFailureAtomicity",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiRepeat_IncrementalFailureAtomicity::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_repeat;
    const TSharedRef<FProbe> Probe = MakeShared<FProbe>();
    auto Registry = FCkUiWidgetRegistry{};
    if (!TestTrue(TEXT("Incremental repeat failure probe registration succeeds"), RegisterProbes(Probe, Registry))) { return false; }
    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Incremental repeat failure collection creates"), FCkUiCollection::TryCreate(Schema(), Collection).Succeeded)
        || !TestTrue(TEXT("Incremental repeat failure initial A publishes"), Collection->TrySetRecords({Record(TEXT("a"), TEXT("Alpha"))}).Succeeded)) { return false; }
    TArray<FString> Actions;
    FText Query;
    const TSharedRef<FCkUiView> View = MakeView(Collection, Registry.CreateSnapshot(), Actions, Query);
    View->GetRegion(TEXT("main"));
    if (!TestSuccessfulLoad(*this, TEXT("Incremental repeat failure baseline loads"), View->TryReload(Markup(TEXT("<repeat-fail id=\"late\" title-field=\"title\"/>")), TEXT(""), TEXT("UiRepeatIncrementalFailure")))) { return false; }
    const TSharedPtr<SCkUiRepeat> Repeat = View->GetRepeat(TEXT("rows"));
    const TSharedPtr<SWidget> AItem = Repeat.IsValid() ? Repeat->GetItemWidget(TEXT("a")) : nullptr;
    const TSharedPtr<SButton> AButton = AItem.IsValid() ? FindButton(AItem.ToSharedRef(), TEXT("toggle")) : nullptr;
    if (!TestTrue(TEXT("Incremental repeat failure baseline mounts A action"), Repeat.IsValid() && AItem.IsValid() && AButton.IsValid())) { return false; }

    if (!TestTrue(TEXT("Incremental repeat failure publishes failing B addition"), Collection->TrySetRecords({Record(TEXT("a"), TEXT("Alpha")), Record(TEXT("b"), TEXT("Bravo"))}).Succeeded)) { return false; }
    TestFalse(TEXT("Repeat rejects a collection-driven failing item addition"), Repeat->TryRefresh());
    TestTrue(TEXT("Incremental failure preserves the old item topology and identity"), Repeat->GetItemCount() == 1
        && Repeat->GetItemWidget(TEXT("a")) == AItem && !Repeat->GetItemWidget(TEXT("b")).IsValid());
    TestFalse(TEXT("Incremental failure records the staging error"), Repeat->GetLastFailure().IsEmpty());
    AButton->SimulateClick();
    TestTrue(TEXT("Incremental failure keeps the old item action live"), Actions == TArray<FString>{TEXT("a")});
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiRepeat_CollectionReplacement,
    "Ck.UiAuthoring.Repeat.CollectionReplacement",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiRepeat_CollectionReplacement::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_repeat;
    TSharedPtr<FCkUiCollection> First, Second;
    if (!TestTrue(TEXT("First schema creates"), FCkUiCollection::TryCreate(Schema(), First).Succeeded)
        || !TestTrue(TEXT("Second schema creates"), FCkUiCollection::TryCreate(Schema(), Second).Succeeded)) { return false; }
    First->TrySetRecords({Record(TEXT("a"), TEXT("First"))});
    Second->TrySetRecords({Record(TEXT("a"), TEXT("Second"))});
    TArray<FString> Actions;
    FCkUiView::FDataBindings Data;
    Data.Collections.Add(TEXT("first"), First);
    Data.Collections.Add(TEXT("second"), Second);
    Data.ItemActions.Add(TEXT("toggle"), FCkUiOnItemAction::CreateLambda([&Actions](FString Key) { Actions.Add(Key); }));
    const auto View = FCkUiView::Create({}, {}, {}, FCoreStyle::GetDefaultFontStyle("Regular", 12), MoveTemp(Data));
    View->GetRegion(TEXT("main"));
    const FString FirstMarkup = TEXT("<ui version=\"1\"><region name=\"main\"><repeat id=\"rows\" bind=\"first\"><button id=\"toggle\" bind-field=\"title\" item-action=\"toggle\"/></repeat></region></ui>");
    if (!TestSuccessfulLoad(*this, TEXT("First collection loads"), View->TryReload(FirstMarkup, TEXT("")))) { return false; }
    const auto OldRepeat = View->GetRepeat(TEXT("rows"));
    const auto OldItem = OldRepeat->GetItemWidget(TEXT("a"));
    const auto OldButton = FindButton(OldItem.ToSharedRef(), TEXT("toggle"));
    if (!TestTrue(TEXT("Old action exists"), OldButton.IsValid())) { return false; }
    if (!TestSuccessfulLoad(*this, TEXT("Second collection replaces first"), View->TryReload(FirstMarkup.Replace(TEXT("first"), TEXT("second")), TEXT("")))) { return false; }
    const auto Current = View->GetRepeat(TEXT("rows"));
    TestTrue(TEXT("Different collection replaces presenter and item scope"), Current != OldRepeat && Current->GetItemWidget(TEXT("a")) != OldItem);
    OldButton->SimulateClick();
    TestTrue(TEXT("Held old collection action is inert"), Actions.IsEmpty());
    Second->TrySetRecords({Record(TEXT("a"), TEXT("Second")), Record(TEXT("b"), TEXT("Added"))});
    TestTrue(TEXT("New collection subscription triggers topology refresh"), Current->TryRefresh() && Current->GetItemCount() == 2);
    First->TrySetRecords({Record(TEXT("c"), TEXT("Obsolete"))});
    TestFalse(TEXT("Old presenter cannot refresh replacement"), OldRepeat->TryRefresh());
    TestEqual(TEXT("Old collection publication leaves current topology intact"), Current->GetItemCount(), 2);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiRepeat_ConstrainedGeometry,
    "Ck.UiAuthoring.Repeat.ConstrainedGeometry",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiRepeat_ConstrainedGeometry::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_repeat;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Repeat geometry requires Slate.")); return false; }
    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Geometry schema creates"), FCkUiCollection::TryCreate(Schema(), Collection).Succeeded)) { return false; }
    const FString Body = TEXT("Runtime material properties remain readable in a narrow inspector. Surface facts describe the selected component and should wrap without overlapping the following card. ");
    Collection->TrySetRecords({Record(TEXT("a"), Body + Body), Record(TEXT("b"), Body)});
    FCkUiView::FDataBindings Data;
    Data.Collections.Add(TEXT("items"), Collection);
    const auto View = FCkUiView::Create({}, {}, {}, FCoreStyle::GetDefaultFontStyle("Regular", 12), MoveTemp(Data));
    const auto Region = View->GetRegion(TEXT("main"));
    const FString Document = TEXT("<ui version=\"1\"><region name=\"main\"><scroll id=\"scroll\"><repeat id=\"rows\" bind=\"items\" class=\"cards\"><column id=\"card\"><text id=\"body\" bind-field=\"title\" visible-field=\"visible\" class=\"body\"/></column></repeat></scroll></region></ui>");
    if (!TestSuccessfulLoad(*this, TEXT("Geometry document loads"), View->TryReload(Document, TEXT(".cards { gap: 12px; padding: 8px; } .body { text-wrap: wrap; }")))) { return false; }
    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope(Slate);
    Scope.Window = SNew(SWindow).ClientSize(FVector2D(280.0f, 500.0f)).CreateTitleBar(false)[Region];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    Tick(Slate);
    const auto Repeat = View->GetRepeat(TEXT("rows"));
    const auto A = Repeat->GetItemWidget(TEXT("a"));
    const auto B = Repeat->GetItemWidget(TEXT("b"));
    const float NarrowHeight = A->GetCachedGeometry().GetLocalSize().Y;
    TestTrue(TEXT("Narrow cards have positive width-bounded geometry"), NarrowHeight > 0.0f && A->GetCachedGeometry().GetLocalSize().X <= 280.0f);
    const float ABottom = A->GetCachedGeometry().LocalToAbsolute(A->GetCachedGeometry().GetLocalSize()).Y;
    TestTrue(TEXT("Wrapped repeated cards do not overlap"), B->GetCachedGeometry().GetAbsolutePosition().Y >= ABottom);
    const auto Measure = Repeat->GetMetaData<FCkFlexMeasureMetaData>();
    if (!TestTrue(TEXT("Repeat exposes constraint-aware measurement"), Measure.IsValid())) { return false; }
    for (const float Scale : {1.0f, 1.5f, 2.0f})
    {
        const auto Size = Measure->Measure({.AvailableWidth = 280.0f, .WidthMode = YGMeasureModeExactly, .LayoutScale = Scale});
        TestTrue(TEXT("DPI measurement stays finite and width constrained"), FMath::IsFinite(Size.X) && FMath::IsFinite(Size.Y) && Size.Y > 0.0f && Size.X <= 281.0f);
    }
    Scope.Window->Resize(FVector2D(900.0f, 500.0f));
    Tick(Slate);
    TestTrue(TEXT("Wider repeated card wraps to fewer lines"), A->GetCachedGeometry().GetLocalSize().Y < NarrowHeight);
    const float ExpandedHeight = A->GetCachedGeometry().GetLocalSize().Y;
    Collection->TrySetRecords({Record(TEXT("a"), Body + Body, false), Record(TEXT("b"), Body)});
    Tick(Slate);
    TestTrue(TEXT("Live collapse preserves item identity and reduces height"), Repeat->GetItemWidget(TEXT("a")) == A && A->GetCachedGeometry().GetLocalSize().Y < ExpandedHeight);
    return true;
}

#endif
