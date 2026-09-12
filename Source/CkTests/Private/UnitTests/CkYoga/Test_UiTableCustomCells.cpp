#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/CkUiWidgetRegistry.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/SCkUiTable.h"

#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "Misc/AutomationTest.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"
#include "Widgets/Views/ITableRow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_table_custom_cells
{
    struct FCustomCellProbe final { int32 Factories = 0; bool bSawTypedAttributes = false; };

    struct FActionCellProbe final
    {
        TArray<FSimpleDelegate> Actions;
        TArray<TWeakPtr<SButton>> Buttons;
    };

    class FNoopPreparedUpdate final : public ICkUiPreparedWidgetUpdate
    {
    public:
        virtual void Commit() noexcept override {}
    };

    class FActionCell final : public ICkUiRetainedWidget
    {
    public:
        explicit FActionCell(const FSimpleDelegate& InAction)
            : Widget(SNew(SButton).OnClicked_Lambda([InAction]()
            {
                InAction.ExecuteIfBound();
                return FReply::Handled();
            })[SNew(STextBlock).Text(FText::FromString(TEXT("Action cell")))]) {}

        virtual auto GetWidget() const -> TSharedRef<SWidget> override { return Widget; }
        virtual auto PrepareReload(const FCkUiCustomWidgetArguments&, FString&) const -> TUniquePtr<ICkUiPreparedWidgetUpdate> override
        { return MakeUnique<FNoopPreparedUpdate>(); }
        auto GetButton() const -> TSharedRef<SButton> { return Widget; }

    private:
        TSharedRef<SButton> Widget;
    };

    auto Records(const int32 InCount, const FString& InSuffix = TEXT("")) -> TArray<FCkUiRecordData>
    {
        auto Result = TArray<FCkUiRecordData>{}; Result.Reserve(InCount);
        for (int32 Index = 0; Index < InCount; ++Index)
        {
            auto Row = FCkUiRecordData{}; Row.Key = FString::Printf(TEXT("row-%d"), Index);
            Row.Fields.Add(TEXT("fraction"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Number, .Number = static_cast<float>(Index) / FMath::Max(1, InCount)});
            Row.Fields.Add(TEXT("tint"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Color, .Color = Index % 2 == 0 ? FLinearColor::Red : FLinearColor::Green});
            Row.Fields.Add(TEXT("label"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(FString::Printf(TEXT("Meter %d%s"), Index, *InSuffix))});
            Result.Add(MoveTemp(Row));
        }
        return Result;
    }

    auto Schema() -> TArray<FCkUiFieldSchema>
    {
        return {{TEXT("fraction"), ECkUiFieldKind::Number}, {TEXT("tint"), ECkUiFieldKind::Color}, {TEXT("label"), ECkUiFieldKind::Text}};
    }

    auto RegisterMeter(const TSharedRef<FCustomCellProbe>& InStats, FCkUiWidgetRegistry& InRegistry) -> bool
    {
        auto Registration = FCkUiCustomWidgetRegistration{};
        Registration.Schema.Tag = TEXT("meter");
        Registration.Schema.Properties = {{TEXT("fraction"), ECkUiCustomPropertyKind::NumberBinding}, {TEXT("tint"), ECkUiCustomPropertyKind::ColorBinding}, {TEXT("label"), ECkUiCustomPropertyKind::TextBinding}};
        Registration.Factory = [InStats](const FCkUiCustomWidgetArguments& Args, FString& Failure) -> TSharedPtr<SWidget>
        {
            ++InStats->Factories;
            const TAttribute<float>* Fraction = Args.NumberBindings.Find(TEXT("fraction"));
            const TAttribute<FLinearColor>* Tint = Args.ColorBindings.Find(TEXT("tint"));
            const TAttribute<FText>* Label = Args.TextBindings.Find(TEXT("label"));
            if (Fraction == nullptr || Tint == nullptr || Label == nullptr) { Failure = TEXT("Meter factory did not receive all typed bindings."); return nullptr; }
            InStats->bSawTypedAttributes = Fraction->IsSet() && Tint->IsSet() && Label->IsSet();
            return SNew(STextBlock).Text(*Label).ColorAndOpacity(TAttribute<FSlateColor>::CreateLambda([Tint = *Tint, Fraction = *Fraction]() { auto Color = Tint.Get(FLinearColor::White); Color.A *= Fraction.Get(1.0f); return FSlateColor(Color); }));
        };
        return InRegistry.Register(MoveTemp(Registration)).Succeeded;
    }

    auto RegisterActionCell(const TSharedRef<FActionCellProbe>& InProbe, FCkUiWidgetRegistry& InRegistry) -> bool
    {
        auto Registration = FCkUiCustomWidgetRegistration{};
        Registration.Schema.Tag = TEXT("actioncell");
        Registration.Schema.Properties = {{TEXT("action"), ECkUiCustomPropertyKind::Action}};
        Registration.RetainedFactory = [InProbe](const FCkUiCustomWidgetArguments& InArguments, FString& OutFailure) -> TSharedPtr<ICkUiRetainedWidget>
        {
            const FSimpleDelegate* Action = InArguments.Actions.Find(TEXT("action"));
            if (Action == nullptr || !Action->IsBound()) { OutFailure = TEXT("Action cell requires its canonical action."); return nullptr; }
            InProbe->Actions.Add(*Action);
            const TSharedRef<FActionCell> Cell = MakeShared<FActionCell>(*Action);
            InProbe->Buttons.Add(Cell->GetButton());
            return Cell;
        };
        return InRegistry.Register(MoveTemp(Registration)).Succeeded;
    }

    auto Markup() -> FString
    {
        return TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><table id=\"table\" class=\"fill\" bind=\"records\" row-height=\"20\"><table-column id=\"meter-column\" label=\"Meter\"><meter id=\"meter\" fraction-field=\"fraction\" tint-field=\"tint\" label-field=\"label\"/></table-column></table></column></region></ui>");
    }

    auto FindText(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<STextBlock>
    {
        if (InRoot->GetTypeAsString() == TEXT("STextBlock")) { return StaticCastSharedRef<STextBlock>(InRoot); }
        const FChildren* Children = InRoot->GetChildren(); if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        { if (const TSharedPtr<STextBlock> Found = FindText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; } }
        return nullptr;
    }

    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }
        FSlateApplication& Slate; TSharedPtr<SWindow> Window;
    };
    auto Tick(FSlateApplication& InSlate) -> void { InSlate.PumpMessages(); InSlate.Tick(); InSlate.Tick(); }

    auto IsMountedBelow(const TSharedRef<SWidget>& InWidget, const TSharedRef<SWidget>& InAncestor) -> bool
    {
        TSharedPtr<SWidget> Current = InWidget;
        while (Current.IsValid())
        {
            if (Current.Get() == &InAncestor.Get()) { return true; }
            Current = Current->GetParentWidget();
        }
        return false;
    }

    auto ClickMountedButton(FSlateApplication& InSlate, const TSharedRef<SWindow>& InWindow, const TSharedRef<SButton>& InButton) -> bool
    {
        if (!InWindow->GetNativeWindow().IsValid()) { return false; }
        const FGeometry Geometry = InButton->GetCachedGeometry();
        if (Geometry.GetLocalSize().X <= 0.0f || Geometry.GetLocalSize().Y <= 0.0f) { return false; }
        const FVector2D Position = Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f);
        InSlate.SetCursorPos(Position);
        InSlate.ProcessMouseMoveEvent(FPointerEvent(0, FSlateApplication::CursorPointerIndex, Position, Position,
            TSet<FKey>{}, EKeys::Invalid, 0.0f, FModifierKeysState{}));
        const bool bDown = InSlate.ProcessMouseButtonDownEvent(InWindow->GetNativeWindow(), FPointerEvent(0,
            FSlateApplication::CursorPointerIndex, Position, Position, TSet<FKey>{EKeys::LeftMouseButton},
            EKeys::LeftMouseButton, 0.0f, FModifierKeysState{}));
        const bool bUp = InSlate.ProcessMouseButtonUpEvent(FPointerEvent(0, FSlateApplication::CursorPointerIndex,
            Position, Position, TSet<FKey>{}, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{}));
        Tick(InSlate);
        return bDown && bUp;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiTableCustomCells_Runtime,
    "Ck.UiAuthoring.Table.CustomCellsTypedBindings",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiTableCustomCells_Runtime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_table_custom_cells;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Custom table cells require initialized Slate.")); return false; }
    const TSharedRef<FCustomCellProbe> Stats = MakeShared<FCustomCellProbe>();
    auto Registry = FCkUiWidgetRegistry{};
    if (!TestTrue(TEXT("Stateless meter cell registration succeeds"), RegisterMeter(Stats, Registry))) { return false; }
    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Custom cell collection creates"), FCkUiCollection::TryCreate(Schema(), Collection).Succeeded) || !Collection.IsValid()) { return false; }
    auto Data = FCkUiView::FDataBindings{}; Data.Collections.Add(TEXT("records"), Collection);
    Data.Number.Add(TEXT("global"), TAttribute<float>(1.0f));
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, MoveTemp(Data), Registry.CreateSnapshot());
    const TSharedRef<SWidget> Region = View->GetRegion(TEXT("main"));
    FSlateApplication& Slate = FSlateApplication::Get(); FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{320.0f, 180.0f}).CreateTitleBar(false).HasCloseButton(false)[Region];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    if (!TestTrue(TEXT("Custom-cell table document loads"), View->TryReload(Markup(), TEXT(".fill { flex-grow: 1; }"), TEXT("UiTableCustomCells")).Succeeded)) { return false; }
    Scope.Window->Resize(FVector2D{320.0f, 180.0f});
    if (!TestTrue(TEXT("Custom-cell data commits"), Collection->TrySetRecords(Records(1000)).Succeeded)) { return false; }
    Tick(Slate);
    const TSharedPtr<SCkUiTable> Table = View->GetTable(TEXT("table"));
    const TSharedPtr<SListView<SCkUiTable::FRecord>> List = Table.IsValid() ? Table->GetList() : nullptr;
    const TSharedPtr<const FCkUiRecord> First = Collection->FindRecord(TEXT("row-0"));
    if (!TestTrue(TEXT("Custom table realizes bounded rows"), Table.IsValid() && List.IsValid() && Table->GetLiveRowCount() > 0 && Table->GetLiveRowCount() < 128) || !TestTrue(TEXT("Custom cell factory receives typed bindings"), Stats->bSawTypedAttributes)) { return false; }
    List->RequestScrollIntoView(First); Tick(Slate);
    const TSharedPtr<ITableRow> FirstRow = First.IsValid() ? List->WidgetFromItem(First) : nullptr;
    const TSharedPtr<STextBlock> FirstText = FirstRow.IsValid() ? FindText(FirstRow->AsWidget()) : nullptr;
    if (!TestTrue(TEXT("Generated custom cell exposes live native text"), FirstText.IsValid() && FirstText->GetText().ToString() == TEXT("Meter 0"))) { return false; }
    const int32 FactoriesBeforeUpdate = Stats->Factories;
    auto UpdatedRecords = Records(1000, TEXT(" updated"));
    UpdatedRecords[0].Fields.FindChecked(TEXT("fraction")).Number = 0.75f;
    UpdatedRecords[0].Fields.FindChecked(TEXT("tint")).Color = FLinearColor::Blue;
    if (!TestTrue(TEXT("Same-key custom cell update commits"), Collection->TrySetRecords(MoveTemp(UpdatedRecords)).Succeeded)) { return false; }
    Tick(Slate);
    const TSharedPtr<ITableRow> UpdatedRow = List->WidgetFromItem(Collection->FindRecord(TEXT("row-0")));
    const TSharedPtr<STextBlock> UpdatedText = UpdatedRow.IsValid() ? FindText(UpdatedRow->AsWidget()) : nullptr;
    TestEqual(TEXT("Same-key updates do not recreate stateless cell factories"), Stats->Factories, FactoriesBeforeUpdate);
    TestTrue(TEXT("Same-key custom cell text binding updates in generated row"), UpdatedText.IsValid() && UpdatedText->GetText().ToString() == TEXT("Meter 0 updated"));
    if (UpdatedText.IsValid())
    {
        TestEqual(TEXT("Numeric field updates the real widget opacity"), UpdatedText->GetColorAndOpacity().GetSpecifiedColor().A, 0.75f);
        TestTrue(TEXT("Color field updates the real widget tint"), UpdatedText->GetColorAndOpacity().GetSpecifiedColor() == FLinearColor(0.0f, 0.0f, 1.0f, 0.75f));
    }
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiTableCustomCells_Validation,
    "Ck.UiAuthoring.Table.CustomCellsValidation",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiTableCustomCells_Validation::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_table_custom_cells;
    const TSharedRef<FCustomCellProbe> Stats = MakeShared<FCustomCellProbe>();
    auto Registry = FCkUiWidgetRegistry{};
    if (!TestTrue(TEXT("Validation meter registration succeeds"), RegisterMeter(Stats, Registry))) { return false; }
    int32 RetainedFactoryCalls = 0;
    auto Retained = FCkUiCustomWidgetRegistration{};
    Retained.Schema.Tag = TEXT("retainedmeter");
    Retained.Schema.Properties = {{TEXT("label"), ECkUiCustomPropertyKind::TextBinding}, {TEXT("action"), ECkUiCustomPropertyKind::Action}, {TEXT("changed"), ECkUiCustomPropertyKind::TextChanged, false}};
    Retained.RetainedFactory = [&RetainedFactoryCalls](const FCkUiCustomWidgetArguments&, FString&) -> TSharedPtr<ICkUiRetainedWidget> { ++RetainedFactoryCalls; return nullptr; };
    if (!TestTrue(TEXT("Retained custom registration succeeds"), Registry.Register(MoveTemp(Retained)).Succeeded)) { return false; }
    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Validation collection creates"), FCkUiCollection::TryCreate(Schema(), Collection).Succeeded) || !Collection.IsValid()) { return false; }
    auto Data = FCkUiView::FDataBindings{}; Data.Collections.Add(TEXT("records"), Collection);
    Data.Number.Add(TEXT("global"), TAttribute<float>(1.0f));
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, MoveTemp(Data), Registry.CreateSnapshot());
    View->GetRegion(TEXT("main"));
    if (!TestTrue(TEXT("Valid empty custom table passes preflight"), View->TryReload(Markup(), TEXT(".fill { flex-grow: 1; }")).Succeeded)) { return false; }
    TestEqual(TEXT("Empty table creates no row factories"), Stats->Factories, 0);
    const FString CellTemplate = TEXT("<template name=\"metercell\"><param name=\"tint\" type=\"color-binding\"/><meter id=\"meter\" fraction-field=\"fraction\" tint-field-param=\"tint\" label-field=\"label\"/></template>");
    const FString TemplateMarkup = Markup().Replace(TEXT("<ui version=\"1\">"), *(TEXT("<ui version=\"1\">") + CellTemplate))
        .Replace(TEXT("<meter id=\"meter\" fraction-field=\"fraction\" tint-field=\"tint\" label-field=\"label\"/>"), TEXT("<use id=\"rowmeter\" template=\"metercell\" tint-bind=\"tint\"/>"));
    TestTrue(TEXT("Typed color field flows through reusable cell template"), View->TryReload(TemplateMarkup, TEXT(".fill { flex-grow: 1; }")).Succeeded);
    const auto Reject = [this, &View, &Stats, &RetainedFactoryCalls](const FString& InName, const FString& InMarkup)
    {
        const int32 Factories = Stats->Factories;
        const FCkUiLoadResult Result = View->TryReload(InMarkup, TEXT(".fill { flex-grow: 1; }"), TEXT("UiTableCustomCellReject"));
        TestFalse(*InName, Result.Succeeded);
        TestTrue(*(InName + TEXT(" reports a failure")), !Result.Errors.IsEmpty());
        TestEqual(*(InName + TEXT(" invokes no stateless factory")), Stats->Factories, Factories);
        TestEqual(*(InName + TEXT(" invokes no retained factory")), RetainedFactoryCalls, 0);
    };
    Reject(TEXT("Missing custom field binding rejects before factories"), Markup().Replace(TEXT(" fraction-field=\"fraction\""), TEXT("")));
    Reject(TEXT("Wrong custom field kind rejects before factories"), Markup().Replace(TEXT("fraction-field=\"fraction\""), TEXT("fraction-field=\"label\"")));
    Reject(TEXT("Field then global binding conflicts"), Markup().Replace(TEXT("fraction-field=\"fraction\""), TEXT("fraction-field=\"fraction\" fraction-bind=\"global\"")));
    Reject(TEXT("Global binding then field conflicts"), Markup().Replace(TEXT("fraction-field=\"fraction\""), TEXT("fraction-bind=\"global\" fraction-field=\"fraction\"")));
    Reject(TEXT("Retained custom table cell rejects before factories"), Markup().Replace(TEXT("<meter id=\"meter\" fraction-field=\"fraction\" tint-field=\"tint\" label-field=\"label\"/>"), TEXT("<retainedmeter id=\"meter\" label-field=\"label\"/>")));
    Reject(TEXT("Retained editable table-cell event rejects before factories"), Markup().Replace(TEXT("<meter id=\"meter\" fraction-field=\"fraction\" tint-field=\"tint\" label-field=\"label\"/>"), TEXT("<retainedmeter id=\"meter\" label-field=\"label\" item-action=\"probe\" changed=\"changed\"/>")));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiTableCustomCells_Actions,
    "Ck.UiAuthoring.Table.CustomCellsActions",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiTableCustomCells_Actions::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_table_custom_cells;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Table cell actions require initialized Slate.")); return false; }
    const TSharedRef<FActionCellProbe> Probe = MakeShared<FActionCellProbe>();
    auto Registry = FCkUiWidgetRegistry{};
    if (!TestTrue(TEXT("Action-cell registration succeeds"), RegisterActionCell(Probe, Registry))) { return false; }
    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Action collection creates"), FCkUiCollection::TryCreate(Schema(), Collection).Succeeded) || !Collection.IsValid()) { return false; }
    TArray<FString> ActionKeys;
    TArray<FString> ContextKeys;
    TSharedPtr<SCkUiTable> Table;
    auto Data = FCkUiView::FDataBindings{};
    Data.Collections.Add(TEXT("records"), Collection);
    Data.ItemActions.Add(TEXT("probe"), FCkUiOnItemAction::CreateLambda([&ActionKeys](const FString& InKey) { ActionKeys.Add(InKey); }));
    Data.TableContextMenus.Add(TEXT("legacy"), FOnContextMenuOpening::CreateLambda([&Table, &ContextKeys]() -> TSharedPtr<SWidget>
    {
        const TOptional<FString> Key = Table.IsValid() ? Table->GetContextMenuKey() : TOptional<FString>{};
        ContextKeys.Add(Key.Get(TEXT("missing-context-key")));
        return SNew(STextBlock).Text(FText::FromString(TEXT("Legacy menu")));
    }));
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, MoveTemp(Data), Registry.CreateSnapshot());
    const TSharedRef<SWidget> Region = View->GetRegion(TEXT("main"));
    FSlateApplication& Slate = FSlateApplication::Get(); FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{320.0f, 180.0f}).CreateTitleBar(false).HasCloseButton(false)[Region];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    const FString Markup = TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><table id=\"table\" class=\"fill\" bind=\"records\" context-menu-action=\"legacy\"><table-column id=\"action\" label=\"Action\"><actioncell id=\"cell\" item-action=\"probe\"/></table-column></table></column></region></ui>");
    const FCkUiLoadResult ActionLoad = View->TryReload(Markup, TEXT(".fill { flex-grow: 1; }"), TEXT("UiTableCustomCellActions"));
    if (!TestTrue(TEXT("Action-cell table document loads"), ActionLoad.Succeeded))
    {
        AddError(FString::Join(ActionLoad.Errors, TEXT("\n")));
        return false;
    }
    if (!TestTrue(TEXT("Action-cell records publish"), Collection->TrySetRecords(Records(1)).Succeeded)) { return false; }
    Tick(Slate);
    Table = View->GetTable(TEXT("table"));
    const TSharedPtr<SListView<SCkUiTable::FRecord>> List = Table.IsValid() ? Table->GetList() : nullptr;
    if (!TestTrue(TEXT("Action cell mounts in a native table"), Table.IsValid() && List.IsValid() && !Probe->Actions.IsEmpty())) { return false; }
    const FSimpleDelegate InitialAction = Probe->Actions.Last();
    const TSharedPtr<SButton> InitialButton = Probe->Buttons.Last().Pin();
    const TSharedPtr<const FCkUiRecord> InitialRecord = Collection->FindRecord(TEXT("row-0"));
    List->RequestScrollIntoView(InitialRecord);
    Tick(Slate);
    const TSharedPtr<ITableRow> InitialRow = InitialRecord.IsValid() ? List->WidgetFromItem(InitialRecord) : nullptr;
    if (!TestTrue(TEXT("Mounted action exposes a real button under its generated row"), InitialButton.IsValid() && InitialRow.IsValid()
        && IsMountedBelow(InitialButton.ToSharedRef(), InitialRow->AsWidget()))) { return false; }
    if (!TestTrue(TEXT("Mounted action handles routed Slate pointer down and up"), ClickMountedButton(Slate, Scope.Window.ToSharedRef(), InitialButton.ToSharedRef()))) { return false; }
    if (!TestEqual(TEXT("Mounted action delivers its stable key"), ActionKeys.Num(), 1) || !TestEqual(TEXT("Mounted action key is current"), ActionKeys[0], FString(TEXT("row-0")))) { return false; }

    const int32 ActionsBeforeSameKeyUpdate = Probe->Actions.Num();
    if (!TestTrue(TEXT("Same-key replacement publishes"), Collection->TrySetRecords(Records(1, TEXT(" replacement"))).Succeeded)) { return false; }
    Tick(Slate);
    const TSharedPtr<const FCkUiRecord> UpdatedRecord = Collection->FindRecord(TEXT("row-0"));
    const TSharedPtr<ITableRow> UpdatedActionRow = UpdatedRecord.IsValid() ? List->WidgetFromItem(UpdatedRecord) : nullptr;
    if (!TestEqual(TEXT("Same-key update does not recreate the retained action"), Probe->Actions.Num(), ActionsBeforeSameKeyUpdate)
        || !TestTrue(TEXT("Same-key update keeps the original button mounted"), InitialButton.IsValid() && UpdatedActionRow.IsValid()
            && IsMountedBelow(InitialButton.ToSharedRef(), UpdatedActionRow->AsWidget()))) { return false; }
    InitialAction.ExecuteIfBound();
    if (!TestEqual(TEXT("Held action remains live after same-key replacement"), ActionKeys.Num(), 2)
        || !TestEqual(TEXT("Held action retains its stable key after same-key replacement"), ActionKeys.Last(), FString(TEXT("row-0")))) { return false; }

    if (!TestTrue(TEXT("Removal publishes"), Collection->TrySetRecords({}).Succeeded)
        || !TestTrue(TEXT("Same-key reinsertion publishes"), Collection->TrySetRecords(Records(1, TEXT(" reinserted"))).Succeeded)) { return false; }
    Tick(Slate);
    InitialAction.ExecuteIfBound();
    TestEqual(TEXT("Held action is inert after removal and reinsertion"), ActionKeys.Num(), 2);
    if (!TestTrue(TEXT("Reinsertion realizes a new held action"), Probe->Actions.Num() > ActionsBeforeSameKeyUpdate)) { return false; }
    const FSimpleDelegate ReinsertionAction = Probe->Actions.Last();
    ReinsertionAction.ExecuteIfBound();
    TestEqual(TEXT("Reinserted action remains live before reload"), ActionKeys.Num(), 3);

    const int32 ActionsBeforeReload = Probe->Actions.Num();
    if (!TestTrue(TEXT("Accepted reload succeeds"), View->TryReload(Markup, TEXT(".fill { flex-grow: 1; }"), TEXT("UiTableCustomCellActionsReload")).Succeeded)) { return false; }
    ReinsertionAction.ExecuteIfBound();
    TestEqual(TEXT("Held action is inert after accepted reload"), ActionKeys.Num(), 3);
    if (!TestTrue(TEXT("Reload realizes a current action"), Probe->Actions.Num() > ActionsBeforeReload)) { return false; }
    const FSimpleDelegate ReloadedAction = Probe->Actions.Last();
    ReloadedAction.ExecuteIfBound();
    if (!TestEqual(TEXT("Newly realized action dispatches exactly once after reload"), ActionKeys.Num(), 4)
        || !TestEqual(TEXT("Newly realized action uses its current row key"), ActionKeys.Last(), FString(TEXT("row-0")))) { return false; }

    const int32 ActionsBeforeDynamicRealization = Probe->Actions.Num();
    if (!TestTrue(TEXT("Second record publishes after the accepted reload"), Collection->TrySetRecords(Records(2)).Succeeded)) { return false; }
    Tick(Slate);
    List->RequestScrollIntoView(Collection->FindRecord(TEXT("row-1")));
    Tick(Slate);
    if (!TestTrue(TEXT("Later row realization creates a current-config action"), Probe->Actions.Num() > ActionsBeforeDynamicRealization)) { return false; }
    const FSimpleDelegate DynamicallyRealizedAction = Probe->Actions.Last();
    DynamicallyRealizedAction.ExecuteIfBound();
    if (!TestEqual(TEXT("Later realized action dispatches exactly once"), ActionKeys.Num(), 5)
        || !TestEqual(TEXT("Later realized action uses its current row key"), ActionKeys.Last(), FString(TEXT("row-1")))) { return false; }
    if (!TestTrue(TEXT("Selection chooses a different row before context menu"), Table->TrySelectKey(TOptional<FString>{FString(TEXT("row-0"))}))) { return false; }
    const TSet<FKey> ReleasedButtons;
    const FVector2D Position = List->GetCachedGeometry().LocalToAbsolute(FVector2D{10.0f, 10.0f});
    const FPointerEvent RightUp{0, Position, Position, ReleasedButtons, EKeys::RightMouseButton, 0.0f, FModifierKeysState{}};
    List->Private_OnItemRightClicked(Collection->FindRecord(TEXT("row-1")), RightUp);
    if (!TestEqual(TEXT("Legacy context callback observes its exact right-clicked key"), ContextKeys.Num(), 1)) { return false; }
    TestEqual(TEXT("Legacy context callback key is independent from selection"), ContextKeys[0], FString(TEXT("row-1")));
    TestEqual(TEXT("Legacy context key does not alter selection"), Table->GetSelectedKey().Get(TEXT("missing-selection")), FString(TEXT("row-0")));
    TestFalse(TEXT("Legacy context key clears after construction"), Table->GetContextMenuKey().IsSet());
    Slate.DismissAllMenus();
    const int32 ContextCallbacksBeforeKeyboard = ContextKeys.Num();
    const FModifierKeysState Shift{true, false, false, false, false, false, false, false, false};
    const FReply KeyboardReply = List->OnKeyDown(List->GetCachedGeometry(), FKeyEvent(EKeys::F10, Shift, 0, false, 0, 0));
    if (!TestTrue(TEXT("Legacy Shift+F10 handles the command"), KeyboardReply.IsEventHandled())
        || !TestEqual(TEXT("Legacy Shift+F10 constructs one context menu"), ContextKeys.Num(), ContextCallbacksBeforeKeyboard + 1)) { return false; }
    TestEqual(TEXT("Legacy Shift+F10 observes the selected row key"), ContextKeys.Last(), FString(TEXT("row-0")));
    TestEqual(TEXT("Legacy Shift+F10 preserves selection"), Table->GetSelectedKey().Get(TEXT("missing-selection")), FString(TEXT("row-0")));
    TestFalse(TEXT("Legacy Shift+F10 cannot leave a stale context key"), Table->GetContextMenuKey().IsSet());
    Slate.DismissAllMenus();
    return true;
}

#endif
