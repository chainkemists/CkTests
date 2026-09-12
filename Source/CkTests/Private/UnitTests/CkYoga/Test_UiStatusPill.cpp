#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/CkUiStatusPill.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/SCkUiTable.h"

#include "Framework/Application/SlateApplication.h"
#include "Misc/AutomationTest.h"
#include "Widgets/Layout/SBorder.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"
#include "Widgets/Views/ITableRow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_status_pill
{
    auto Schema() -> TArray<FCkUiFieldSchema>
    {
        return {
            {TEXT("label"), ECkUiFieldKind::Text},
            {TEXT("foreground"), ECkUiFieldKind::Color},
            {TEXT("outline"), ECkUiFieldKind::Color},
        };
    }

    auto Records(const FString& InLabel, const FLinearColor InForeground, const FLinearColor InOutline) -> TArray<FCkUiRecordData>
    {
        auto Record = FCkUiRecordData{};
        Record.Key = TEXT("resource-0");
        Record.Fields.Add(TEXT("label"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(InLabel)});
        Record.Fields.Add(TEXT("foreground"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Color, .Color = InForeground});
        Record.Fields.Add(TEXT("outline"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Color, .Color = InOutline});
        return {MoveTemp(Record)};
    }

    auto Markup() -> FString
    {
        return TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><table id=\"resources\" bind=\"resources\" row-height=\"20\" class=\"fill\"><table-column id=\"state\" label=\"State\"><status-pill id=\"state-cell\" label-field=\"label\" foreground-field=\"foreground\" outline-field=\"outline\" class=\"state-pill\"/></table-column></table></column></region></ui>");
    }

    auto Stylesheet() -> FString
    {
        return TEXT(".fill { flex-grow: 1; } .state-pill { -ck-status-pill-font-size: 10px; }");
    }

    auto FindPill(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SBorder>
    {
        if (InRoot->GetTag() == TEXT("state-cell") && InRoot->GetTypeAsString() == TEXT("SBorder"))
        { return StaticCastSharedRef<SBorder>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SBorder> Found = FindPill(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto FindText(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<STextBlock>
    {
        if (InRoot->GetTypeAsString() == TEXT("STextBlock")) { return StaticCastSharedRef<STextBlock>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<STextBlock> Found = FindText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto GetOutline(const TSharedPtr<SBorder>& InPill) -> TOptional<FLinearColor>
    {
        const FSlateBrush* Brush = InPill.IsValid() ? InPill->GetBorderImage() : nullptr;
        return Brush != nullptr ? TOptional<FLinearColor>(Brush->OutlineSettings.Color.GetSpecifiedColor()) : TOptional<FLinearColor>{};
    }

    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }

        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
    };

    auto Tick(FSlateApplication& InSlate) -> void { InSlate.PumpMessages(); InSlate.Tick(); InSlate.Tick(); }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkUiStatusPill_SharedRuntime,
    "Ck.UiAuthoring.StatusPill.Runtime",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiStatusPill_SharedRuntime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_status_pill;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Status pill runtime test requires Slate.")); return false; }

    FCkUiWidgetRegistry Registry;
    if (!TestTrue(TEXT("Status pill registration succeeds"), FCkUiStatusPill::Register(Registry).Succeeded)) { return false; }

    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Status pill collection creates"), FCkUiCollection::TryCreate(Schema(), Collection).Succeeded) || !Collection.IsValid()) { return false; }

    auto Data = FCkUiView::FDataBindings{};
    Data.Collections.Add(TEXT("resources"), Collection);
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, MoveTemp(Data), Registry.CreateSnapshot());
    const TSharedRef<SWidget> Region = View->GetRegion(TEXT("main"));
    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{320.0f, 180.0f}).CreateTitleBar(false).HasCloseButton(false)[Region];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);

    if (!TestTrue(TEXT("Status pill table document loads"), View->TryReload(Markup(), Stylesheet(), TEXT("UiStatusPill")).Succeeded)) { return false; }
    if (!TestTrue(TEXT("Initial status pill record commits"), Collection->TrySetRecords(Records(TEXT("Ready"), FLinearColor::Green, FLinearColor::Blue)).Succeeded)) { return false; }
    Tick(Slate);

    const TSharedPtr<SCkUiTable> Table = View->GetTable(TEXT("resources"));
    const TSharedPtr<SListView<SCkUiTable::FRecord>> List = Table.IsValid() ? Table->GetList() : nullptr;
    const TSharedPtr<const FCkUiRecord> First = Collection->FindRecord(TEXT("resource-0"));
    if (!TestTrue(TEXT("Status pill table realizes its production row"), Table.IsValid() && List.IsValid() && First.IsValid() && Table->GetLiveRowCount() > 0)) { return false; }

    List->RequestScrollIntoView(First);
    Tick(Slate);
    const TSharedPtr<ITableRow> InitialRow = List->WidgetFromItem(First);
    const TSharedPtr<SBorder> InitialPill = InitialRow.IsValid() ? FindPill(InitialRow->AsWidget()) : nullptr;
    const TSharedPtr<STextBlock> InitialText = InitialPill.IsValid() ? FindText(InitialPill.ToSharedRef()) : nullptr;
    const TOptional<FLinearColor> InitialOutline = GetOutline(InitialPill);
    if (!TestTrue(TEXT("Generated table cell mounts the real tagged status pill"), InitialPill.IsValid())
        || !TestTrue(TEXT("Mounted status pill exposes its initial label and CSS font size"), InitialText.IsValid()
            && InitialText->GetText().ToString() == TEXT("Ready") && InitialText->GetFont().Size == 10)
        || !TestTrue(TEXT("Mounted status pill reads both initial color bindings"), InitialText.IsValid()
            && InitialText->GetColorAndOpacity().GetSpecifiedColor().Equals(FLinearColor::Green) && InitialOutline.IsSet()
            && InitialOutline.GetValue().Equals(FLinearColor::Blue)))
    { return false; }

    if (!TestTrue(TEXT("Same-key status pill record update commits"), Collection->TrySetRecords(Records(TEXT("Pending"), FLinearColor::Yellow, FLinearColor::Red)).Succeeded)) { return false; }
    Tick(Slate);
    const TSharedPtr<const FCkUiRecord> UpdatedRecord = Collection->FindRecord(TEXT("resource-0"));
    const TSharedPtr<ITableRow> UpdatedRow = UpdatedRecord.IsValid() ? List->WidgetFromItem(UpdatedRecord) : nullptr;
    const TSharedPtr<SBorder> UpdatedPill = UpdatedRow.IsValid() ? FindPill(UpdatedRow->AsWidget()) : nullptr;
    const TSharedPtr<STextBlock> UpdatedText = UpdatedPill.IsValid() ? FindText(UpdatedPill.ToSharedRef()) : nullptr;
    const TOptional<FLinearColor> UpdatedOutline = GetOutline(UpdatedPill);
    TestTrue(TEXT("Same-key update retains the realized status pill widget"), UpdatedPill == InitialPill);
    TestTrue(TEXT("Same-key status pill label binding updates in the mounted table cell"), UpdatedText.IsValid() && UpdatedText->GetText().ToString() == TEXT("Pending"));
    TestTrue(TEXT("Same-key status pill color bindings update in the mounted table cell"), UpdatedText.IsValid()
        && UpdatedText->GetColorAndOpacity().GetSpecifiedColor().Equals(FLinearColor::Yellow) && UpdatedOutline.IsSet()
        && UpdatedOutline.GetValue().Equals(FLinearColor::Red));

    const int64 AcceptedRevision = View->GetRevision();
    const TSharedPtr<SCkUiTable> AcceptedTable = View->GetTable(TEXT("resources"));
    const FCkUiLoadResult MissingOutline = View->TryReload(Markup().Replace(TEXT(" outline-field=\"outline\""), TEXT("")), Stylesheet(), TEXT("UiStatusPillMissingOutline"));
    TestFalse(TEXT("Missing required status pill outline field rejects before table cell realization"), MissingOutline.Succeeded);
    TestEqual(TEXT("Missing outline rejection preserves accepted document revision"), View->GetRevision(), AcceptedRevision);
    TestTrue(TEXT("Missing outline rejection preserves accepted table"), View->GetTable(TEXT("resources")) == AcceptedTable);
    const FCkUiLoadResult WrongOutlineKind = View->TryReload(Markup().Replace(TEXT(" outline-field=\"outline\""), TEXT(" outline-field=\"label\"")), Stylesheet(), TEXT("UiStatusPillWrongOutlineKind"));
    TestFalse(TEXT("Wrong status pill outline field kind rejects before table cell realization"), WrongOutlineKind.Succeeded);
    TestEqual(TEXT("Wrong outline kind rejection preserves accepted document revision"), View->GetRevision(), AcceptedRevision);
    TestTrue(TEXT("Wrong outline kind rejection preserves accepted table"), View->GetTable(TEXT("resources")) == AcceptedTable);
    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
