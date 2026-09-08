#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/CkUiWidgetRegistry.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/SCkUiTable.h"

#include "Framework/Application/SlateApplication.h"
#include "Misc/AutomationTest.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"
#include "Widgets/Views/ITableRow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_table_custom_cells
{
    struct FCustomCellProbe final { int32 Factories = 0; bool bSawTypedAttributes = false; };

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
    Retained.Schema.Properties = {{TEXT("label"), ECkUiCustomPropertyKind::TextBinding}};
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
    return true;
}

#endif
