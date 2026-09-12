#include "CkSlateLayout/CkFlexText.h"
#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/CkUiFloatSeries.h"
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
#include "Widgets/SBoxPanel.h"
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

    auto FindFlexText(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SCkFlexText>
    {
        if (InRoot->GetTag() == InTag && InRoot->GetTypeAsString() == TEXT("SCkFlexText"))
        {
            return StaticCastSharedRef<SCkFlexText>(InRoot);
        }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SCkFlexText> Found = FindFlexText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag); Found.IsValid())
            {
                return Found;
            }
        }
        return {};
    }

    auto FindRepeat(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SCkUiRepeat>
    {
        if (InRoot->GetTag() == InTag && InRoot->GetTypeAsString() == TEXT("SCkUiRepeat")) { return StaticCastSharedRef<SCkUiRepeat>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SCkUiRepeat> Found = FindRepeat(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag); Found.IsValid()) { return Found; }
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

    struct FItemEventProbe final
    {
        int32 FactoryCalls = 0;
        int32 SlotFactoryCalls = 0;
        int32 SlotPrepareCalls = 0;
        TMap<FString, FCkUiCustomWidgetArguments> Arguments;
    };

    class FItemEventSlotPreparedUpdate final : public ICkUiPreparedWidgetUpdate
    {
    public:
        virtual void Commit() noexcept override {}
    };

    class FItemEventSlotPanel final : public ICkUiRetainedWidget
    {
    public:
        FItemEventSlotPanel(const TSharedRef<FItemEventProbe>& InProbe, const TSharedRef<SWidget>& InBody)
            : _Probe(InProbe), _Body(InBody)
        {
            _Root = SNew(SVerticalBox)
                + SVerticalBox::Slot()[_Body];
        }

        virtual auto GetWidget() const -> TSharedRef<SWidget> override { return _Root.ToSharedRef(); }

        virtual auto PrepareReload(const FCkUiCustomWidgetArguments& InArguments, FString& OutFailure) const -> TUniquePtr<ICkUiPreparedWidgetUpdate> override
        {
            if (InArguments.Slots.FindRef(TEXT("body")) != _Body)
            {
                OutFailure = TEXT("Repeat typed-event slot mount changed during retained reload.");
                return nullptr;
            }
            ++_Probe->SlotPrepareCalls;
            return MakeUnique<FItemEventSlotPreparedUpdate>();
        }

    private:
        TSharedRef<FItemEventProbe> _Probe;
        TSharedRef<SWidget> _Body;
        TSharedPtr<SWidget> _Root;
    };

    auto RegisterItemEventProbes(const TSharedRef<FItemEventProbe>& InProbe, FCkUiWidgetRegistry& InRegistry) -> bool
    {
        const auto Register = [&InProbe, &InRegistry](const FString& Tag, const ECkUiCustomPropertyKind Kind) -> bool
        {
            auto Registration = FCkUiCustomWidgetRegistration{};
            Registration.Schema.Tag = Tag;
            Registration.Schema.Properties = {{Kind == ECkUiCustomPropertyKind::BoolChanged ? TEXT("changed") : TEXT("committed"), Kind, true}};
            Registration.Factory = [InProbe, Tag](const FCkUiCustomWidgetArguments& InArguments, FString&) -> TSharedPtr<SWidget>
            {
                ++InProbe->FactoryCalls;
                InProbe->Arguments.Add(Tag, InArguments);
                return SNew(STextBlock).Tag(FName(*Tag));
            };
            return InRegistry.Register(MoveTemp(Registration)).Succeeded;
        };
        return Register(TEXT("repeat-bool-event"), ECkUiCustomPropertyKind::BoolChanged)
            && Register(TEXT("repeat-number-event"), ECkUiCustomPropertyKind::NumberCommitted)
            && Register(TEXT("repeat-integer-event"), ECkUiCustomPropertyKind::IntegerCommitted);
    }

    auto RegisterItemEventSlotProbe(const TSharedRef<FItemEventProbe>& InProbe, FCkUiWidgetRegistry& InRegistry) -> bool
    {
        auto Registration = FCkUiCustomWidgetRegistration{};
        Registration.Schema.Tag = TEXT("repeat-event-slot");
        Registration.Schema.Slots = {{TEXT("body"), true}};
        Registration.RetainedFactory = [InProbe](const FCkUiCustomWidgetArguments& InArguments, FString& OutFailure) -> TSharedPtr<ICkUiRetainedWidget>
        {
            const TSharedPtr<SWidget> Body = InArguments.Slots.FindRef(TEXT("body"));
            if (!Body.IsValid())
            {
                OutFailure = TEXT("Repeat typed-event slot requires its body mount.");
                return nullptr;
            }
            ++InProbe->SlotFactoryCalls;
            return MakeShared<FItemEventSlotPanel>(InProbe, Body.ToSharedRef());
        };
        return InRegistry.Register(MoveTemp(Registration)).Succeeded;
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

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiRepeat_NestedChildBinding,
    "Ck.UiAuthoring.Repeat.NestedChildBinding",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiRepeat_NestedChildBinding::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_repeat;
    const TSharedRef<FProbe> Probe = MakeShared<FProbe>();
    auto Registry = FCkUiWidgetRegistry{};
    if (!TestTrue(TEXT("Nested repeat failure probe registration succeeds"), RegisterProbes(Probe, Registry))) { return false; }
    const auto Leaf = [](const FString& InKey, const FString& InTitle)
    {
        FCkUiRecordData Result;
        Result.Key = InKey;
        Result.Fields.Add(TEXT("title"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(InTitle)});
        return Result;
    };
    const auto Band = [](const FString& InKey, const FString& InTitle, TArray<FCkUiRecordData> InLeaves)
    {
        FCkUiRecordData Result;
        Result.Key = InKey;
        Result.Fields.Add(TEXT("title"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(InTitle)});
        Result.Children.Add(TEXT("leaves"), MoveTemp(InLeaves));
        return Result;
    };
    const auto Parent = [&Band](const FString& InKey, const FString& InTitle, TArray<FCkUiRecordData> InBands)
    {
        FCkUiRecordData Result;
        Result.Key = InKey;
        Result.Fields.Add(TEXT("title"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(InTitle)});
        Result.Children.Add(TEXT("bands"), MoveTemp(InBands));
        return Result;
    };
    FCkUiCollectionSchema Schema;
    Schema.Fields = {{TEXT("title"), ECkUiFieldKind::Text}};
    FCkUiChildCollectionSchema Bands;
    Bands.Name = TEXT("bands");
    Bands.Fields = {{TEXT("title"), ECkUiFieldKind::Text}};
    Bands.Children = {{TEXT("leaves"), {{TEXT("title"), ECkUiFieldKind::Text}}}};
    Schema.Children.Add(MoveTemp(Bands));
    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Hierarchical repeat collection creates"), FCkUiCollection::TryCreateHierarchical(MoveTemp(Schema), Collection).Succeeded)
        || !TestTrue(TEXT("Initial parent and child records publish"), Collection->TrySetRecords({
            Parent(TEXT("a"), TEXT("Alpha"), {Band(TEXT("a-1"), TEXT("Alpha one"), {Leaf(TEXT("a-1-i"), TEXT("Alpha one first")), Leaf(TEXT("a-1-ii"), TEXT("Alpha one second"))}), Band(TEXT("a-2"), TEXT("Alpha two"), {Leaf(TEXT("a-2-i"), TEXT("Alpha two first"))})}),
            Parent(TEXT("b"), TEXT("Bravo"), {Band(TEXT("b-1"), TEXT("Bravo one"), {Leaf(TEXT("b-1-i"), TEXT("Bravo one first"))})}),
        }).Succeeded)) { return false; }

    TArray<FString> Actions;
    auto Data = FCkUiView::FDataBindings{};
    Data.Collections.Add(TEXT("parents"), Collection);
    Data.ItemActions.Add(TEXT("child-action"), FCkUiOnItemAction::CreateLambda([&Actions](const FString InKey) { Actions.Add(InKey); }));
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {}, {}, FCoreStyle::GetDefaultFontStyle(TEXT("Regular"), 12), MoveTemp(Data), Registry.CreateSnapshot());
    const TSharedRef<SWidget> Region = View->GetRegion(TEXT("main"));
    const FString Markup = TEXT("<ui version=\"1\"><region name=\"main\"><repeat id=\"parents\" bind=\"parents\"><column id=\"parent\"><text id=\"parent-title\" bind-field=\"title\"/><button id=\"parent-action\" bind-field=\"title\" item-action=\"child-action\"/><repeat id=\"bands\" child-bind=\"bands\"><row id=\"band\"><text id=\"band-title\" bind-field=\"title\"/><repeat-fail id=\"band-fail\" title-field=\"title\"/><button id=\"band-action\" bind-field=\"title\" item-action=\"child-action\"/><repeat id=\"leaves\" child-bind=\"leaves\"><text id=\"leaf-title\" bind-field=\"title\"/></repeat></row></repeat></column></repeat></region></ui>");
    if (!TestSuccessfulLoad(*this, TEXT("Nested child-bound repeat loads"), View->TryReload(Markup, TEXT(""), TEXT("UiRepeatNested")))) { return false; }
    const TSharedPtr<SCkUiRepeat> Parents = View->GetRepeat(TEXT("parents"));
    const TSharedPtr<SWidget> ParentA = Parents.IsValid() ? Parents->GetItemWidget(TEXT("a")) : nullptr;
    const TSharedPtr<SWidget> ParentB = Parents.IsValid() ? Parents->GetItemWidget(TEXT("b")) : nullptr;
    const TSharedPtr<SCkUiRepeat> BandsA = ParentA.IsValid() ? FindRepeat(ParentA.ToSharedRef(), TEXT("bands")) : nullptr;
    const TSharedPtr<SCkUiRepeat> BandsB = ParentB.IsValid() ? FindRepeat(ParentB.ToSharedRef(), TEXT("bands")) : nullptr;
    if (!TestTrue(TEXT("Every parent mounts only its own child repeat"), Parents.IsValid() && Parents->GetItemCount() == 2
        && BandsA.IsValid() && BandsA->GetItemCount() == 2 && BandsB.IsValid() && BandsB->GetItemCount() == 1)) { return false; }
    const TSharedPtr<SWidget> A1 = BandsA->GetItemWidget(TEXT("a-1"));
    const TSharedPtr<SWidget> A2 = BandsA->GetItemWidget(TEXT("a-2"));
    const TSharedPtr<SWidget> B1 = BandsB->GetItemWidget(TEXT("b-1"));
    const TSharedPtr<SCkUiRepeat> LeavesA1 = A1.IsValid() ? FindRepeat(A1.ToSharedRef(), TEXT("leaves")) : nullptr;
    const TSharedPtr<SCkUiRepeat> LeavesB1 = B1.IsValid() ? FindRepeat(B1.ToSharedRef(), TEXT("leaves")) : nullptr;
    const TSharedPtr<SWidget> A1FirstLeaf = LeavesA1.IsValid() ? LeavesA1->GetItemWidget(TEXT("a-1-i")) : nullptr;
    const TSharedPtr<SButton> ParentAction = ParentA.IsValid() ? FindButton(ParentA.ToSharedRef(), TEXT("parent-action")) : nullptr;
    const TSharedPtr<SButton> HeldRemovedAction = A1.IsValid() ? FindButton(A1.ToSharedRef(), TEXT("band-action")) : nullptr;
    if (!TestTrue(TEXT("Nested children mount keyed item roots and actions"), A1.IsValid() && A2.IsValid() && ParentAction.IsValid() && HeldRemovedAction.IsValid()
        && !BandsB->GetItemWidget(TEXT("a-1")).IsValid())) { return false; }
    if (!TestTrue(TEXT("Grandchild repeat resolves from each band without parent leakage"), LeavesA1.IsValid() && LeavesB1.IsValid()
        && LeavesA1->GetItemCount() == 2 && LeavesB1->GetItemCount() == 1 && LeavesA1->GetItemWidget(TEXT("a-1-i")).IsValid()
        && !LeavesB1->GetItemWidget(TEXT("a-1-i")).IsValid())) { return false; }
    ParentAction->SimulateClick();
    HeldRemovedAction->SimulateClick();
    if (!TestTrue(TEXT("Nested scopes dispatch their own stable keys"), Actions == TArray<FString>{TEXT("a"), TEXT("a-1")})) { return false; }

    if (!TestTrue(TEXT("Same-parent child update and reorder publishes"), Collection->TrySetRecords({
            Parent(TEXT("a"), TEXT("Alpha updated"), {Band(TEXT("a-2"), TEXT("Alpha two updated"), {Leaf(TEXT("a-2-i"), TEXT("Alpha two first"))}), Band(TEXT("a-1"), TEXT("Alpha one updated"), {Leaf(TEXT("a-1-i"), TEXT("Alpha one first updated")), Leaf(TEXT("a-1-ii"), TEXT("Alpha one second"))})}),
            Parent(TEXT("b"), TEXT("Bravo"), {Band(TEXT("b-1"), TEXT("Bravo one"), {Leaf(TEXT("b-1-i"), TEXT("Bravo one first"))})}),
        }).Succeeded)
        || !TestTrue(TEXT("Parent refresh propagates to dirty child presenter"), Parents->TryRefresh())) { return false; }
    const TSharedPtr<SWidget> UpdatedA1 = BandsA->GetItemWidget(TEXT("a-1"));
    const TSharedPtr<SWidget> UpdatedA2 = BandsA->GetItemWidget(TEXT("a-2"));
    if (!TestTrue(TEXT("Child keys retain their item roots across reorder"), UpdatedA1 == A1 && UpdatedA2 == A2)) { return false; }
    const TSharedPtr<SCkUiRepeat> UpdatedLeavesA1 = UpdatedA1.IsValid() ? FindRepeat(UpdatedA1.ToSharedRef(), TEXT("leaves")) : nullptr;
    TestTrue(TEXT("Child publication during parent refresh preserves the retained grandchild presenter and item"),
        UpdatedLeavesA1 == LeavesA1 && UpdatedLeavesA1.IsValid() && UpdatedLeavesA1->GetItemWidget(TEXT("a-1-i")) == A1FirstLeaf);
    const TSharedPtr<SCkFlexText> UpdatedParentTitle = FindFlexText(ParentA.ToSharedRef(), TEXT("parent-title"));
    const TSharedPtr<SCkFlexText> UpdatedBandTitle = FindFlexText(UpdatedA1.ToSharedRef(), TEXT("band-title"));
    const TSharedPtr<SCkFlexText> UpdatedLeafTitle = FindFlexText(A1FirstLeaf.ToSharedRef(), TEXT("leaf-title"));
    TestEqual(TEXT("Parent field binding updates through the child transaction"), UpdatedParentTitle.IsValid() ? UpdatedParentTitle->GetText().ToString() : FString{}, FString(TEXT("Alpha updated")));
    TestEqual(TEXT("Nested field binding updates through the parent transaction"), UpdatedBandTitle.IsValid() ? UpdatedBandTitle->GetText().ToString() : FString{}, FString(TEXT("Alpha one updated")));
    TestEqual(TEXT("Grandchild field binding updates through the parent transaction"), UpdatedLeafTitle.IsValid() ? UpdatedLeafTitle->GetText().ToString() : FString{}, FString(TEXT("Alpha one first updated")));
    const int32 ActionsBeforeHeldParent = Actions.Num();
    ParentAction->SimulateClick();
    TestEqual(TEXT("Held pre-refresh parent action is inert"), Actions.Num(), ActionsBeforeHeldParent);
    const TSharedPtr<SButton> UpdatedParentAction = FindButton(ParentA.ToSharedRef(), TEXT("parent-action"));
    const TSharedPtr<SButton> UpdatedBandAction = FindButton(UpdatedA1.ToSharedRef(), TEXT("band-action"));
    if (!TestTrue(TEXT("Reordered keyed items retain their current actions"), UpdatedParentAction.IsValid() && UpdatedBandAction.IsValid())) { return false; }
    UpdatedParentAction->SimulateClick();
    UpdatedBandAction->SimulateClick();
    TestTrue(TEXT("Reordered nested scopes dispatch their stable keys"), Actions == TArray<FString>{TEXT("a"), TEXT("a-1"), TEXT("a"), TEXT("a-1")});

    if (!TestTrue(TEXT("Descendant preparation failure publishes without changing parent topology"), Collection->TrySetRecords({
            Parent(TEXT("a"), TEXT("Alpha updated"), {Band(TEXT("a-2"), TEXT("Alpha two updated"), {Leaf(TEXT("a-2-i"), TEXT("Alpha two first"))}), Band(TEXT("a-1"), TEXT("Alpha one updated"), {Leaf(TEXT("a-1-i"), TEXT("Alpha one first")), Leaf(TEXT("a-1-ii"), TEXT("Alpha one second"))})}),
            Parent(TEXT("b"), TEXT("Bravo"), {Band(TEXT("b-1"), TEXT("Bravo one"), {Leaf(TEXT("b-1-i"), TEXT("Bravo one first"))}), Band(TEXT("b-2"), TEXT("Bravo"), {Leaf(TEXT("b-2-i"), TEXT("Bravo two first"))})}),
        }).Succeeded)
        || !TestFalse(TEXT("Parent refresh fails when a dirty descendant rejects preparation"), Parents->TryRefresh())) { return false; }
    TestTrue(TEXT("Parent exposes the descendant failure and preserves the child topology"),
        Parents->GetLastFailure().Contains(TEXT("Expected repeat child factory failure.")) && !BandsB->GetItemWidget(TEXT("b-2")).IsValid());
    const int32 FailedFactoryCallsBeforeRetry = Probe->FailingFactoryCalls;
    TestFalse(TEXT("Failed parent remains dirty and retries its descendant"), Parents->TryRefresh());
    TestTrue(TEXT("Retry re-enters the failed descendant transaction"), Probe->FailingFactoryCalls > FailedFactoryCallsBeforeRetry);

    if (!TestTrue(TEXT("Repaired descendant data publishes"), Collection->TrySetRecords({
            Parent(TEXT("a"), TEXT("Alpha updated"), {Band(TEXT("a-2"), TEXT("Alpha two updated"), {Leaf(TEXT("a-2-i"), TEXT("Alpha two first"))}), Band(TEXT("a-1"), TEXT("Alpha one updated"), {Leaf(TEXT("a-1-i"), TEXT("Alpha one first")), Leaf(TEXT("a-1-ii"), TEXT("Alpha one second"))})}),
            Parent(TEXT("b"), TEXT("Bravo"), {Band(TEXT("b-1"), TEXT("Bravo one"), {Leaf(TEXT("b-1-i"), TEXT("Bravo one first"))}), Band(TEXT("b-2"), TEXT("Bravo repaired"), {Leaf(TEXT("b-2-i"), TEXT("Bravo two first"))})}),
        }).Succeeded)
        || !TestTrue(TEXT("Parent retry commits the repaired descendant"), Parents->TryRefresh())) { return false; }
    TestTrue(TEXT("Successful retry clears parent failure and mounts the repaired child"),
        Parents->GetLastFailure().IsEmpty() && BandsB->GetItemWidget(TEXT("b-2")).IsValid());

    const int64 Revision = View->GetRevision();
    const TSharedRef<SWidget> Root = RegionRoot(View);
    FCkUiRecordData MissingChildRecord;
    MissingChildRecord.Key = TEXT("invalid");
    MissingChildRecord.Fields.Add(TEXT("title"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(TEXT("Invalid"))});
    const FCkUiLoadResult MissingChildRecordResult = Collection->TrySetRecords({MoveTemp(MissingChildRecord)});
    if (!TestFalse(TEXT("Schema-valid parent fields without the declared child collection reject"), MissingChildRecordResult.Succeeded)) { return false; }
    TestTrue(TEXT("Missing child record input cannot partially publish the mounted hierarchy"), RegionRoot(View) == Root
        && Parents->GetItemWidget(TEXT("a")) == ParentA && BandsA->GetItemWidget(TEXT("a-1")) == A1);
    const FCkUiLoadResult MissingChild = View->TryReload(Markup.Replace(TEXT("child-bind=\"bands\""), TEXT("child-bind=\"missing\"")), TEXT(""), TEXT("UiRepeatNestedMissing"));
    TestFalse(TEXT("Missing named child collection rejects the nested repeat"), MissingChild.Succeeded);
    TestTrue(TEXT("Missing child binding leaves the committed parent and children untouched"), View->GetRevision() == Revision
        && RegionRoot(View) == Root && View->GetRepeat(TEXT("parents")) == Parents && BandsA->GetItemWidget(TEXT("a-1")) == A1);

    if (!TestTrue(TEXT("Removing a parent and its child collection publishes"), Collection->TrySetRecords({
            Parent(TEXT("b"), TEXT("Bravo"), {Band(TEXT("b-1"), TEXT("Bravo one"), {Leaf(TEXT("b-1-i"), TEXT("Bravo one first"))})}),
        }).Succeeded)
        || !TestTrue(TEXT("Parent refresh tears down removed child scope"), Parents->TryRefresh() && !Parents->GetItemWidget(TEXT("a")).IsValid())) { return false; }
    const int32 ActionsBeforeStale = Actions.Num();
    HeldRemovedAction->SimulateClick();
    TestEqual(TEXT("Held child action is inert after its parent scope is destroyed"), Actions.Num(), ActionsBeforeStale);

    auto CollisionData = FCkUiView::FDataBindings{};
    CollisionData.Collections.Add(TEXT("parents"), Collection);
    CollisionData.ItemActions.Add(TEXT("child-action"), FCkUiOnItemAction::CreateLambda([](const FString) {}));
    auto CollisionActions = FCkUiView::FActions{};
    CollisionActions.Add(TEXT("@item:child-action"), FSimpleDelegate::CreateLambda([]() {}));
    const TSharedRef<FCkUiView> CollisionView = FCkUiView::Create({}, MoveTemp(CollisionActions), {}, FSlateFontInfo{}, MoveTemp(CollisionData));
    CollisionView->GetRegion(TEXT("main"));
    TestFalse(TEXT("Caller-supplied top-level repeat action aliases remain reserved"), CollisionView->TryReload(Markup, TEXT(""), TEXT("UiRepeatReservedAlias")).Succeeded);

    auto FieldCollisionData = FCkUiView::FDataBindings{};
    FieldCollisionData.Collections.Add(TEXT("parents"), Collection);
    FieldCollisionData.ItemActions.Add(TEXT("child-action"), FCkUiOnItemAction::CreateLambda([](const FString) {}));
    FieldCollisionData.Text.Add(TEXT("@field:title"), TAttribute<FText>(FText::FromString(TEXT("Caller value"))));
    const TSharedRef<FCkUiView> FieldCollisionView = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, MoveTemp(FieldCollisionData));
    FieldCollisionView->GetRegion(TEXT("main"));
    TestFalse(TEXT("Caller-supplied top-level repeat field aliases remain reserved"), FieldCollisionView->TryReload(Markup, TEXT(""), TEXT("UiRepeatReservedFieldAlias")).Succeeded);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiRepeat_ItemTypedEvents,
    "Ck.UiAuthoring.Repeat.ItemTypedEvents",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiRepeat_ItemTypedEvents::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_repeat;
    const TSharedRef<FItemEventProbe> Probe = MakeShared<FItemEventProbe>();
    auto Registry = FCkUiWidgetRegistry{};
    if (!TestTrue(TEXT("Repeat typed-event probe registration succeeds"), RegisterItemEventProbes(Probe, Registry))
        || !TestTrue(TEXT("Repeat typed-event slot probe registration succeeds"), RegisterItemEventSlotProbe(Probe, Registry))) { return false; }

    const auto Leaf = [](const FString& Key, const FString& Title)
    {
        FCkUiRecordData Result;
        Result.Key = Key;
        Result.Fields.Add(TEXT("title"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(Title)});
        return Result;
    };
    const auto Parent = [&Leaf](const FString& Key, const FString& LeafKey, const FString& LeafTitle)
    {
        FCkUiRecordData Result;
        Result.Key = Key;
        Result.Fields.Add(TEXT("title"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(Key)});
        auto Children = TArray<FCkUiRecordData>{};
        Children.Add(Leaf(LeafKey, LeafTitle));
        Result.Children.Add(TEXT("children"), MoveTemp(Children));
        return Result;
    };
    FCkUiCollectionSchema Schema;
    Schema.Fields = {{TEXT("title"), ECkUiFieldKind::Text}};
    Schema.Children = {{TEXT("children"), {{TEXT("title"), ECkUiFieldKind::Text}}}};
    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Repeat typed-event collection creates"), FCkUiCollection::TryCreateHierarchical(MoveTemp(Schema), Collection).Succeeded)
        || !TestTrue(TEXT("Repeat typed-event initial record publishes"), Collection->TrySetRecords({Parent(TEXT("outer"), TEXT("inner"), TEXT("inner"))}).Succeeded)) { return false; }

    TArray<FString> BoolKeys;
    TArray<bool> BoolValues;
    TArray<FString> NumberKeys;
    TArray<float> NumberValues;
    TArray<ETextCommit::Type> NumberReasons;
    TArray<FString> IntegerKeys;
    TArray<int32> IntegerValues;
    TArray<ETextCommit::Type> IntegerReasons;
    TArray<FString> ActionKeys;
    auto Data = FCkUiView::FDataBindings{};
    Data.Collections.Add(TEXT("parents"), Collection);
    Data.ItemActions.Add(TEXT("child-action"), FCkUiOnItemAction::CreateLambda([&](const FString Key) { ActionKeys.Add(Key); }));
    Data.ItemBoolChanged.Add(TEXT("toggle"), FCkUiOnItemBoolChanged::CreateLambda([&](const FString Key, const bool Value) { BoolKeys.Add(Key); BoolValues.Add(Value); }));
    Data.ItemNumberCommitted.Add(TEXT("float"), FCkUiOnItemNumberCommitted::CreateLambda([&](const FString Key, const float Value, const ETextCommit::Type Reason) { NumberKeys.Add(Key); NumberValues.Add(Value); NumberReasons.Add(Reason); }));
    Data.ItemIntegerCommitted.Add(TEXT("integer"), FCkUiOnItemIntegerCommitted::CreateLambda([&](const FString Key, const int32 Value, const ETextCommit::Type Reason) { IntegerKeys.Add(Key); IntegerValues.Add(Value); IntegerReasons.Add(Reason); }));
    Data.ItemBoolChanged.Add(TEXT("toggle-b"), FCkUiOnItemBoolChanged::CreateLambda([&](const FString Key, const bool Value) { BoolKeys.Add(Key); BoolValues.Add(Value); }));
    Data.ItemNumberCommitted.Add(TEXT("float-b"), FCkUiOnItemNumberCommitted::CreateLambda([&](const FString Key, const float Value, const ETextCommit::Type Reason) { NumberKeys.Add(Key); NumberValues.Add(Value); NumberReasons.Add(Reason); }));
    Data.ItemIntegerCommitted.Add(TEXT("integer-b"), FCkUiOnItemIntegerCommitted::CreateLambda([&](const FString Key, const int32 Value, const ETextCommit::Type Reason) { IntegerKeys.Add(Key); IntegerValues.Add(Value); IntegerReasons.Add(Reason); }));
    TSharedPtr<FCkUiView> View = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, MoveTemp(Data), Registry.CreateSnapshot());
    View->GetRegion(TEXT("main"));
    const FString Markup = TEXT("<ui version=\"1\"><region name=\"main\"><repeat id=\"parents\" bind=\"parents\"><column id=\"parent\"><repeat-event-slot id=\"event-slot\"><slot name=\"body\"><repeat id=\"children\" child-bind=\"children\"><column id=\"child\"><text id=\"child-title\" bind-field=\"title\"/><button id=\"child-action\" item-action=\"child-action\">Run child action</button><repeat-bool-event id=\"bool\" item-changed=\"toggle\"/><repeat-number-event id=\"number\" item-committed=\"float\"/><repeat-integer-event id=\"integer\" item-committed=\"integer\"/></column></repeat></slot></repeat-event-slot></column></repeat></region></ui>");
    const FString AlternateMarkup = Markup.Replace(TEXT("item-changed=\"toggle\""), TEXT("item-changed=\"toggle-b\""))
        .Replace(TEXT("item-committed=\"float\""), TEXT("item-committed=\"float-b\""))
        .Replace(TEXT("item-committed=\"integer\""), TEXT("item-committed=\"integer-b\""));
    if (!TestSuccessfulLoad(*this, TEXT("Nested repeat typed item events load"), View->TryReload(Markup, TEXT(""), TEXT("UiRepeatItemTypedEvents")))) { return false; }
    const FCkUiCustomWidgetArguments BoolArguments = Probe->Arguments.FindRef(TEXT("repeat-bool-event"));
    const FCkUiCustomWidgetArguments NumberArguments = Probe->Arguments.FindRef(TEXT("repeat-number-event"));
    const FCkUiCustomWidgetArguments IntegerArguments = Probe->Arguments.FindRef(TEXT("repeat-integer-event"));
    if (!TestTrue(TEXT("Typed item events reach custom factories after validation"), BoolArguments.BoolChanged.FindRef(TEXT("changed")).IsBound()
        && NumberArguments.NumberCommitted.FindRef(TEXT("committed")).IsBound() && IntegerArguments.IntegerCommitted.FindRef(TEXT("committed")).IsBound())) { return false; }
    BoolArguments.BoolChanged.FindRef(TEXT("changed")).Execute(true);
    NumberArguments.NumberCommitted.FindRef(TEXT("committed")).Execute(4.25f, ETextCommit::OnEnter);
    IntegerArguments.IntegerCommitted.FindRef(TEXT("committed")).Execute(7, ETextCommit::OnUserMovedFocus);
    TestTrue(TEXT("Nested typed events use the innermost item key"), BoolKeys == TArray<FString>{TEXT("inner")}
        && NumberKeys == TArray<FString>{TEXT("inner")} && IntegerKeys == TArray<FString>{TEXT("inner")});
    TestTrue(TEXT("Typed item events preserve bool, float, integer, and commit reasons"), BoolValues == TArray<bool>{true}
        && NumberValues == TArray<float>{4.25f} && NumberReasons == TArray<ETextCommit::Type>{ETextCommit::OnEnter}
        && IntegerValues == TArray<int32>{7} && IntegerReasons == TArray<ETextCommit::Type>{ETextCommit::OnUserMovedFocus});
    const TSharedPtr<SCkUiRepeat> InitialParents = View->GetRepeat(TEXT("parents"));
    const TSharedPtr<SWidget> InitialParent = InitialParents.IsValid() ? InitialParents->GetItemWidget(TEXT("outer")) : nullptr;
    const TSharedPtr<SCkUiRepeat> InitialChildren = InitialParent.IsValid() ? FindRepeat(InitialParent.ToSharedRef(), TEXT("children")) : nullptr;
    const TSharedPtr<SWidget> InitialChild = InitialChildren.IsValid() ? InitialChildren->GetItemWidget(TEXT("inner")) : nullptr;
    const TSharedPtr<SButton> InitialChildAction = InitialChild.IsValid() ? FindButton(InitialChild.ToSharedRef(), TEXT("child-action")) : nullptr;
    if (!TestTrue(TEXT("Nested slot child mounts its keyed action"), InitialChildAction.IsValid())) { return false; }
    InitialChildAction->SimulateClick();
    TestTrue(TEXT("Nested slot item action uses the innermost stable key"), ActionKeys == TArray<FString>{TEXT("inner")});

    TestTrue(TEXT("Retained typed item aliases accept handler changes and repeated reloads"),
        View->TryReload(AlternateMarkup, TEXT(""), TEXT("UiRepeatItemTypedAlternate")).Succeeded
        && View->TryReload(AlternateMarkup, TEXT(""), TEXT("UiRepeatItemTypedAlternateRepeat")).Succeeded
        && View->TryReload(Markup, TEXT(""), TEXT("UiRepeatItemTypedOriginal")).Succeeded);
    if (!TestTrue(TEXT("Nested custom slot retains its mount across compatible typed-event reloads"), Probe->SlotFactoryCalls == 1 && Probe->SlotPrepareCalls >= 3)) { return false; }

    const FCkUiCustomWidgetArguments ReloadedBoolArguments = Probe->Arguments.FindRef(TEXT("repeat-bool-event"));
    const FCkUiCustomWidgetArguments ReloadedNumberArguments = Probe->Arguments.FindRef(TEXT("repeat-number-event"));
    const FCkUiCustomWidgetArguments ReloadedIntegerArguments = Probe->Arguments.FindRef(TEXT("repeat-integer-event"));
    ReloadedBoolArguments.BoolChanged.FindRef(TEXT("changed")).Execute(false);
    ReloadedNumberArguments.NumberCommitted.FindRef(TEXT("committed")).Execute(8.5f, ETextCommit::OnUserMovedFocus);
    ReloadedIntegerArguments.IntegerCommitted.FindRef(TEXT("committed")).Execute(11, ETextCommit::OnCleared);
    if (!TestTrue(TEXT("Typed events inside a retained custom slot dispatch the innermost stable key after reload"),
        BoolKeys.Last() == TEXT("inner") && NumberKeys.Last() == TEXT("inner") && IntegerKeys.Last() == TEXT("inner")
        && !BoolValues.Last() && NumberValues.Last() == 8.5f && NumberReasons.Last() == ETextCommit::OnUserMovedFocus
        && IntegerValues.Last() == 11 && IntegerReasons.Last() == ETextCommit::OnCleared)) { return false; }

    const TSharedPtr<SCkUiRepeat> Parents = View->GetRepeat(TEXT("parents"));
    if (!TestTrue(TEXT("Typed-event parent repeat mounts"), Parents.IsValid())
        || !TestTrue(TEXT("Replacing a record with the same key publishes"), Collection->TrySetRecords({Parent(TEXT("outer"), TEXT("inner"), TEXT("inner replacement"))}).Succeeded)
        || !TestTrue(TEXT("Replacement refresh succeeds"), Parents->TryRefresh())) { return false; }
    const int32 CallsBeforeReplaced = BoolKeys.Num() + NumberKeys.Num() + IntegerKeys.Num();
    ReloadedBoolArguments.BoolChanged.FindRef(TEXT("changed")).Execute(false);
    ReloadedNumberArguments.NumberCommitted.FindRef(TEXT("committed")).Execute(9.0f, ETextCommit::OnCleared);
    ReloadedIntegerArguments.IntegerCommitted.FindRef(TEXT("committed")).Execute(9, ETextCommit::OnCleared);
    TestEqual(TEXT("Callbacks held by replaced records are inert"), BoolKeys.Num() + NumberKeys.Num() + IntegerKeys.Num(), CallsBeforeReplaced);

    const TSharedPtr<SWidget> UpdatedParent = Parents->GetItemWidget(TEXT("outer"));
    const TSharedPtr<SCkUiRepeat> UpdatedChildren = UpdatedParent.IsValid() ? FindRepeat(UpdatedParent.ToSharedRef(), TEXT("children")) : nullptr;
    const TSharedPtr<SWidget> UpdatedChild = UpdatedChildren.IsValid() ? UpdatedChildren->GetItemWidget(TEXT("inner")) : nullptr;
    const TSharedPtr<SCkFlexText> UpdatedChildTitle = UpdatedChild.IsValid() ? FindFlexText(UpdatedChild.ToSharedRef(), TEXT("child-title")) : nullptr;
    const TSharedPtr<SButton> UpdatedChildAction = UpdatedChild.IsValid() ? FindButton(UpdatedChild.ToSharedRef(), TEXT("child-action")) : nullptr;
    if (!TestTrue(TEXT("Same-key nested slot replacement updates the field and preserves its action"), UpdatedChildTitle.IsValid()
        && UpdatedChildTitle->GetText().ToString() == TEXT("inner replacement") && UpdatedChildAction.IsValid())) { return false; }
    UpdatedChildAction->SimulateClick();
    TestTrue(TEXT("Same-key nested slot action uses the live innermost key"), ActionKeys.Num() == 2 && ActionKeys.Last() == TEXT("inner"));

    const FCkUiCustomWidgetArguments CurrentBoolArguments = Probe->Arguments.FindRef(TEXT("repeat-bool-event"));
    const FCkUiCustomWidgetArguments CurrentNumberArguments = Probe->Arguments.FindRef(TEXT("repeat-number-event"));
    const FCkUiCustomWidgetArguments CurrentIntegerArguments = Probe->Arguments.FindRef(TEXT("repeat-integer-event"));
    CurrentBoolArguments.BoolChanged.FindRef(TEXT("changed")).Execute(false);
    CurrentNumberArguments.NumberCommitted.FindRef(TEXT("committed")).Execute(10.5f, ETextCommit::OnUserMovedFocus);
    CurrentIntegerArguments.IntegerCommitted.FindRef(TEXT("committed")).Execute(13, ETextCommit::OnCleared);
    if (!TestTrue(TEXT("Replacement installs live innermost callbacks for every typed event"), BoolKeys.Last() == TEXT("inner") && !BoolValues.Last()
        && NumberKeys.Last() == TEXT("inner") && NumberValues.Last() == 10.5f && NumberReasons.Last() == ETextCommit::OnUserMovedFocus
        && IntegerKeys.Last() == TEXT("inner") && IntegerValues.Last() == 13 && IntegerReasons.Last() == ETextCommit::OnCleared)) { return false; }

    const int64 RevisionBeforeSlotReject = View->GetRevision();
    const int32 SlotFactoriesBeforeReject = Probe->SlotFactoryCalls;
    TestFalse(TEXT("Rejected nested slot candidate leaves the accepted item live"), View->TryReload(
        Markup.Replace(TEXT("item-action=\"child-action\""), TEXT("item-action=\"missing-child-action\"")), TEXT(""), TEXT("UiRepeatItemTypedSlotReject")).Succeeded);
    if (!TestTrue(TEXT("Rejected nested slot candidate retains the accepted revision and slot subtree"), View->GetRevision() == RevisionBeforeSlotReject
        && Probe->SlotFactoryCalls == SlotFactoriesBeforeReject && View->GetRepeat(TEXT("parents")) == Parents
        && Parents->GetItemWidget(TEXT("outer")) == UpdatedParent && FindRepeat(UpdatedParent.ToSharedRef(), TEXT("children")) == UpdatedChildren
        && UpdatedChildren->GetItemWidget(TEXT("inner")) == UpdatedChild
        && UpdatedChildTitle->GetText().ToString() == TEXT("inner replacement"))) { return false; }
    const int32 BoolCallsBeforeSlotReject = BoolKeys.Num();
    const int32 ActionsBeforeSlotReject = ActionKeys.Num();
    CurrentBoolArguments.BoolChanged.FindRef(TEXT("changed")).Execute(true);
    UpdatedChildAction->SimulateClick();
    if (!TestTrue(TEXT("Rejected nested slot candidate preserves live innermost callback and action provenance"), BoolKeys.Num() == BoolCallsBeforeSlotReject + 1
        && BoolKeys.Last() == TEXT("inner") && BoolValues.Last() && ActionKeys.Num() == ActionsBeforeSlotReject + 1 && ActionKeys.Last() == TEXT("inner"))) { return false; }

    if (!TestTrue(TEXT("Child-only replacement publishes"), Collection->TrySetRecords({Parent(TEXT("outer"), TEXT("inner"), TEXT("inner child-only replacement"))}).Succeeded)
        || !TestTrue(TEXT("Child-only replacement refresh succeeds"), Parents->TryRefresh())) { return false; }
    const int32 BoolCallsBeforeChildOnlyStale = BoolKeys.Num();
    CurrentBoolArguments.BoolChanged.FindRef(TEXT("changed")).Execute(false);
    if (!TestTrue(TEXT("Child-only replacement makes the prior nested callback inert"), BoolKeys.Num() == BoolCallsBeforeChildOnlyStale)) { return false; }
    const FCkUiCustomWidgetArguments ChildOnlyCurrentBoolArguments = Probe->Arguments.FindRef(TEXT("repeat-bool-event"));
    ChildOnlyCurrentBoolArguments.BoolChanged.FindRef(TEXT("changed")).Execute(true);
    if (!TestTrue(TEXT("Child-only replacement restages a live nested callback for the same key"), BoolKeys.Num() == BoolCallsBeforeChildOnlyStale + 1
        && BoolKeys.Last() == TEXT("inner") && BoolValues.Last())) { return false; }

    if (!TestTrue(TEXT("Unchanged sibling publishes beside the current parent"), Collection->TrySetRecords({
            Parent(TEXT("outer"), TEXT("inner"), TEXT("inner child-only replacement")),
            Parent(TEXT("sibling"), TEXT("sibling-inner"), TEXT("sibling")),
        }).Succeeded)
        || !TestTrue(TEXT("Sibling publication refresh succeeds"), Parents->TryRefresh())) { return false; }
    const FCkUiCustomWidgetArguments SiblingBoolArguments = Probe->Arguments.FindRef(TEXT("repeat-bool-event"));
    const int32 BoolCallsBeforeSiblingProbe = BoolKeys.Num();
    SiblingBoolArguments.BoolChanged.FindRef(TEXT("changed")).Execute(true);
    if (!TestTrue(TEXT("Sibling nested callback initially routes its own stable key"), BoolKeys.Num() == BoolCallsBeforeSiblingProbe + 1
        && BoolKeys.Last() == TEXT("sibling-inner") && BoolValues.Last())) { return false; }
    if (!TestTrue(TEXT("Changing one sibling record publishes"), Collection->TrySetRecords({
            Parent(TEXT("outer"), TEXT("inner"), TEXT("inner sibling replacement")),
            Parent(TEXT("sibling"), TEXT("sibling-inner"), TEXT("sibling")),
        }).Succeeded)
        || !TestTrue(TEXT("Changed-sibling refresh succeeds"), Parents->TryRefresh())) { return false; }
    const int32 BoolCallsBeforeUnchangedSibling = BoolKeys.Num();
    SiblingBoolArguments.BoolChanged.FindRef(TEXT("changed")).Execute(false);
    if (!TestTrue(TEXT("Unchanged sibling retains its live nested callback when another sibling changes"), BoolKeys.Num() == BoolCallsBeforeUnchangedSibling + 1
        && BoolKeys.Last() == TEXT("sibling-inner") && !BoolValues.Last())) { return false; }

    if (!TestTrue(TEXT("Removing the active parent publishes"), Collection->TrySetRecords({}).Succeeded)
        || !TestTrue(TEXT("Removal refresh succeeds"), Parents->TryRefresh())) { return false; }
    const int32 CallsBeforeRemoved = BoolKeys.Num();
    CurrentBoolArguments.BoolChanged.FindRef(TEXT("changed")).Execute(true);
    TestEqual(TEXT("Callbacks held by removed records are inert"), BoolKeys.Num(), CallsBeforeRemoved);

    const int32 FactoriesBeforeReject = Probe->FactoryCalls;
    auto InvalidData = FCkUiView::FDataBindings{};
    InvalidData.Collections.Add(TEXT("parents"), Collection);
    InvalidData.ItemActions.Add(TEXT("child-action"), FCkUiOnItemAction::CreateLambda([](const FString) {}));
    const TSharedRef<FCkUiView> InvalidView = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, MoveTemp(InvalidData), Registry.CreateSnapshot());
    InvalidView->GetRegion(TEXT("main"));
    TestFalse(TEXT("Missing typed item handler rejects before custom factories"), InvalidView->TryReload(Markup, TEXT(""), TEXT("UiRepeatItemTypedMissing")).Succeeded);
    TestEqual(TEXT("Missing typed item handler invokes no custom factory"), Probe->FactoryCalls, FactoriesBeforeReject);
    auto WrongTypeData = FCkUiView::FDataBindings{};
    WrongTypeData.Collections.Add(TEXT("parents"), Collection);
    WrongTypeData.ItemActions.Add(TEXT("child-action"), FCkUiOnItemAction::CreateLambda([](const FString) {}));
    WrongTypeData.ItemNumberCommitted.Add(TEXT("toggle"), FCkUiOnItemNumberCommitted::CreateLambda([](const FString, const float, const ETextCommit::Type) {}));
    const TSharedRef<FCkUiView> WrongTypeView = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, MoveTemp(WrongTypeData), Registry.CreateSnapshot());
    WrongTypeView->GetRegion(TEXT("main"));
    TestFalse(TEXT("Wrong typed item handler rejects before custom factories"), WrongTypeView->TryReload(Markup, TEXT(""), TEXT("UiRepeatItemTypedWrongType")).Succeeded);
    TestEqual(TEXT("Wrong typed item handler invokes no custom factory"), Probe->FactoryCalls, FactoriesBeforeReject);
    auto AliasCollisionData = FCkUiView::FDataBindings{};
    AliasCollisionData.Collections.Add(TEXT("parents"), Collection);
    AliasCollisionData.ItemActions.Add(TEXT("child-action"), FCkUiOnItemAction::CreateLambda([](const FString) {}));
    AliasCollisionData.ItemBoolChanged.Add(TEXT("toggle"), FCkUiOnItemBoolChanged::CreateLambda([](const FString, const bool) {}));
    AliasCollisionData.ItemNumberCommitted.Add(TEXT("float"), FCkUiOnItemNumberCommitted::CreateLambda([](const FString, const float, const ETextCommit::Type) {}));
    AliasCollisionData.ItemNumberCommitted.Add(TEXT("float-b"), FCkUiOnItemNumberCommitted::CreateLambda([](const FString, const float, const ETextCommit::Type) {}));
    AliasCollisionData.ItemIntegerCommitted.Add(TEXT("integer"), FCkUiOnItemIntegerCommitted::CreateLambda([](const FString, const int32, const ETextCommit::Type) {}));
    AliasCollisionData.NumberCommitted.Add(TEXT("@item-number:float-b"), FCkUiOnNumberCommitted::CreateLambda([](const float, const ETextCommit::Type) {}));
    const TSharedRef<FCkUiView> AliasCollisionView = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, MoveTemp(AliasCollisionData), Registry.CreateSnapshot());
    AliasCollisionView->GetRegion(TEXT("main"));
    const FCkUiLoadResult AliasCollision = AliasCollisionView->TryReload(Markup, TEXT(""), TEXT("UiRepeatItemTypedAliasCollision"));
    TestFalse(TEXT("Caller-owned reserved alias for an unused typed handler rejects"), AliasCollision.Succeeded);
    TestTrue(TEXT("Typed alias collision is diagnosed before custom factories"),
        FString::Join(AliasCollision.Errors, TEXT("\n")).Contains(TEXT("Reserved repeat item event alias collision.")));
    TestEqual(TEXT("Typed alias collision invokes no custom factory"), Probe->FactoryCalls, FactoriesBeforeReject);
    if (!TestSuccessfulLoad(*this, TEXT("Compatible typed item-event reload remains valid"), View->TryReload(Markup, TEXT(""), TEXT("UiRepeatItemTypedCompatible")))) { return false; }
    const int64 Revision = View->GetRevision();
    TestFalse(TEXT("Conflicting ordinary and item event attributes reject"), View->TryReload(Markup.Replace(TEXT("item-changed=\"toggle\""), TEXT("changed=\"ordinary\" item-changed=\"toggle\"")), TEXT(""), TEXT("UiRepeatItemTypedConflict")).Succeeded);
    TestEqual(TEXT("Rejected item-event reload retains the committed document"), View->GetRevision(), Revision);
    TestFalse(TEXT("Item event outside a repeat item rejects before factories"), InvalidView->TryReload(TEXT("<ui version=\"1\"><region name=\"main\"><repeat-bool-event id=\"outside\" item-changed=\"toggle\"/></region></ui>"), TEXT(""), TEXT("UiRepeatItemTypedScope")).Succeeded);
    TestEqual(TEXT("Scope rejection invokes no custom factory"), Probe->FactoryCalls, FactoriesBeforeReject);
    if (!TestTrue(TEXT("Owner-release record publishes"), Collection->TrySetRecords({Parent(TEXT("outer"), TEXT("inner"), TEXT("inner"))}).Succeeded)
        || !TestTrue(TEXT("Owner-release repeat refresh succeeds"), Parents->TryRefresh())) { return false; }
    const FCkUiCustomWidgetArguments ReleasedArguments = Probe->Arguments.FindRef(TEXT("repeat-bool-event"));
    const int32 CallsBeforeRelease = BoolKeys.Num();
    View.Reset();
    ReleasedArguments.BoolChanged.FindRef(TEXT("changed")).Execute(true);
    TestEqual(TEXT("Owner-released typed item callbacks are inert"), BoolKeys.Num(), CallsBeforeRelease);
    return true;
}

namespace ck_tests_ui_repeat_series_action
{
    struct FProbe final
    {
        int32 Factories = 0;
        FCkUiCustomWidgetArguments Arguments;
        TWeakPtr<const FCkUiFloatSeries> Series;
    };

    auto Record(const TSharedPtr<FCkUiFloatSeries>& InSeries) -> FCkUiRecordData
    {
        FCkUiRecordData Result;
        Result.Key = TEXT("one");
        Result.Fields.Add(TEXT("samples"), FCkUiFieldValue{.Kind = ECkUiFieldKind::FloatSeries, .FloatSeries = InSeries});
        return Result;
    }

    auto Register(const TSharedRef<FProbe>& InProbe, FCkUiWidgetRegistry& InRegistry) -> bool
    {
        FCkUiCustomWidgetRegistration Registration;
        Registration.Schema.Tag = TEXT("series-action-row");
        Registration.Schema.Properties = {
            {TEXT("action"), ECkUiCustomPropertyKind::Action, true},
            {TEXT("samples"), ECkUiCustomPropertyKind::FloatSeriesBinding, true},
        };
        Registration.Factory = [InProbe](const FCkUiCustomWidgetArguments& InArguments, FString& OutFailure) -> TSharedPtr<SWidget>
        {
            const FSimpleDelegate* Action = InArguments.Actions.Find(TEXT("action"));
            const TWeakPtr<const FCkUiFloatSeries>* Series = InArguments.FloatSeriesBindings.Find(TEXT("samples"));
            if (Action == nullptr || !Action->IsBound() || Series == nullptr || !Series->IsValid())
            { OutFailure = TEXT("Series action row requires live samples and action."); return nullptr; }
            ++InProbe->Factories;
            InProbe->Arguments = InArguments;
            InProbe->Series = *Series;
            return SNew(STextBlock).Tag(FName(TEXT("series-action-row")));
        };
        if (!InRegistry.Register(MoveTemp(Registration)).Succeeded) { return false; }
        FCkUiCustomWidgetRegistration Unsupported;
        Unsupported.Schema.Tag = TEXT("unsupported-series-action-row");
        Unsupported.Schema.Properties = {
            {TEXT("trigger"), ECkUiCustomPropertyKind::Action, true},
            {TEXT("samples"), ECkUiCustomPropertyKind::FloatSeriesBinding, true},
        };
        Unsupported.Factory = [InProbe](const FCkUiCustomWidgetArguments&, FString&) -> TSharedPtr<SWidget>
        { ++InProbe->Factories; return SNew(STextBlock); };
        return InRegistry.Register(MoveTemp(Unsupported)).Succeeded;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiRepeat_CustomActionAndFloatSeries,
    "Ck.UiAuthoring.Repeat.CustomActionAndFloatSeries",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiRepeat_CustomActionAndFloatSeries::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_repeat_series_action;
    const TSharedRef<FProbe> Probe = MakeShared<FProbe>();
    FCkUiWidgetRegistry Registry;
    if (!TestTrue(TEXT("Custom action-series row registers"), Register(Probe, Registry))) { return false; }
    TSharedPtr<FCkUiFloatSeries> First;
    TSharedPtr<FCkUiFloatSeries> Second;
    if (!TestTrue(TEXT("First series creates"), FCkUiFloatSeries::TryCreate({1.0f}, First).Succeeded)
        || !TestTrue(TEXT("Second series creates"), FCkUiFloatSeries::TryCreate({2.0f, 3.0f}, Second).Succeeded)) { return false; }
    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Series collection creates"), FCkUiCollection::TryCreate({{TEXT("samples"), ECkUiFieldKind::FloatSeries, true}}, Collection).Succeeded)
        || !TestTrue(TEXT("Initial series record publishes"), Collection->TrySetRecords({Record(First)}).Succeeded)) { return false; }
    TArray<FString> Keys;
    FCkUiView::FDataBindings Data;
    Data.Collections.Add(TEXT("rows"), Collection);
    Data.ItemActions.Add(TEXT("select"), FCkUiOnItemAction::CreateLambda([&Keys](const FString& InKey) { Keys.Add(InKey); }));
    TSharedPtr<FCkUiView> View = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, MoveTemp(Data), Registry.CreateSnapshot());
    View->GetRegion(TEXT("main"));
    const FString Markup = TEXT("<ui version=\"1\"><region name=\"main\"><repeat id=\"rows\" bind=\"rows\"><series-action-row id=\"row\" item-action=\"select\" samples-field=\"samples\"/></repeat></region></ui>");
    if (!TestTrue(TEXT("Custom repeat action and series load"), View->TryReload(Markup, TEXT(""), TEXT("RepeatCustomSeriesInitial")).Succeeded)) { return false; }
    const FCkUiCustomWidgetArguments FirstArguments = Probe->Arguments;
    TestTrue(TEXT("Custom row receives exact non-owning series"), Probe->Series.Pin().Get() == First.Get());
    FirstArguments.Actions.FindRef(TEXT("action")).Execute();
    TestTrue(TEXT("Custom item action uses stable record key"), Keys == TArray<FString>{TEXT("one")});
    const int64 SamePointerRevision = Collection->FindRecord(TEXT("one"))->GetRevision();
    if (!TestTrue(TEXT("Live series mutation succeeds"), First->TrySetSamples({5.0f}).Succeeded)
        || !TestTrue(TEXT("Same series pointer publishes"), Collection->TrySetRecords({Record(First)}).Succeeded)) { return false; }
    TestEqual(TEXT("Same series pointer preserves record revision"), Collection->FindRecord(TEXT("one"))->GetRevision(), SamePointerRevision);
    TestTrue(TEXT("Custom row observes live series mutation"), Probe->Series.Pin()->GetSamples() == TArray<float>({5.0f}));
    if (!TestTrue(TEXT("Replacement series publishes"), Collection->TrySetRecords({Record(Second)}).Succeeded)
        || !TestTrue(TEXT("Replacement refresh succeeds"), View->GetRepeat(TEXT("rows"))->TryRefresh())) { return false; }
    const int32 CallsBeforeStale = Keys.Num();
    FirstArguments.Actions.FindRef(TEXT("action")).Execute();
    TestEqual(TEXT("Record replacement makes old custom action inert"), Keys.Num(), CallsBeforeStale);
    const FCkUiCustomWidgetArguments SecondArguments = Probe->Arguments;
    SecondArguments.Actions.FindRef(TEXT("action")).Execute();
    TestTrue(TEXT("Replacement custom action remains live"), Keys.Last() == TEXT("one") && Probe->Series.Pin().Get() == Second.Get());
    const int64 AcceptedRevision = View->GetRevision();
    const int32 FactoriesBeforeReject = Probe->Factories;
    TestFalse(TEXT("Non-canonical custom item action rejects before factories"), View->TryReload(
        Markup.Replace(TEXT("series-action-row"), TEXT("unsupported-series-action-row")), TEXT(""), TEXT("RepeatCustomSeriesUnsupported")).Succeeded);
    TestEqual(TEXT("Unsupported custom item action runs no factory"), Probe->Factories, FactoriesBeforeReject);
    TestFalse(TEXT("Ordinary and item custom actions conflict atomically"), View->TryReload(Markup.Replace(TEXT("item-action=\"select\""), TEXT("action=\"ordinary\" item-action=\"select\"")), TEXT(""), TEXT("RepeatCustomSeriesConflict")).Succeeded);
    TestEqual(TEXT("Rejected custom action candidate preserves view revision"), View->GetRevision(), AcceptedRevision);
    TestEqual(TEXT("Rejected custom action candidate runs no factory"), Probe->Factories, FactoriesBeforeReject);
    const TWeakPtr<FCkUiFloatSeries> Released = Second;
    Second.Reset();
    TestFalse(TEXT("Expired required series record is rejected"), Collection->TrySetRecords({Record(Second)}).Succeeded);
    TestTrue(TEXT("Expired host series has no collection-owned lifetime"), Collection->FindRecord(TEXT("one"))->GetRevision() > SamePointerRevision && !Released.IsValid());
    View.Reset();
    const int32 CallsBeforeOwnerRelease = Keys.Num();
    SecondArguments.Actions.FindRef(TEXT("action")).Execute();
    TestEqual(TEXT("Owner release makes custom item action inert"), Keys.Num(), CallsBeforeOwnerRelease);
    return true;
}

#endif
