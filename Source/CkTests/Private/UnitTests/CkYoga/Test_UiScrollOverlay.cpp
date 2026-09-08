#include "CkSlateLayout/CkFlexText.h"
#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/SCkUiTable.h"

#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "Misc/AutomationTest.h"
#include "Widgets/SWindow.h"
#include "Widgets/Layout/SScrollBox.h"
#include "Widgets/Views/ITableRow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_scroll_overlay
{
    auto Schema() -> TArray<FCkUiFieldSchema>
    {
        return {{TEXT("label"), ECkUiFieldKind::Text}};
    }

    auto Records(const int32 InCount) -> TArray<FCkUiRecordData>
    {
        auto Result = TArray<FCkUiRecordData>{};
        Result.Reserve(InCount);
        for (int32 Index = 0; Index < InCount; ++Index)
        {
            auto Record = FCkUiRecordData{};
            Record.Key = FString::Printf(TEXT("row-%d"), Index);
            Record.Fields.Add(TEXT("label"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(FString::Printf(TEXT("Resource %d"), Index))});
            Result.Add(MoveTemp(Record));
        }
        return Result;
    }

    auto Markup() -> FString
    {
        return TEXT("<ui version=\"1\"><region name=\"main\"><overlay id=\"overlay\"><scroll id=\"resource-scroll\" direction=\"horizontal\"><table id=\"resources\" class=\"table-wide\" bind=\"resources\" row-height=\"20\"><table-column id=\"name\" label=\"Name\" sort-field=\"label\"><text id=\"cell\" bind-field=\"label\"/></table-column></table></scroll><text id=\"overlay-label\" class=\"badge\" visible=\"show-badge\">An intentionally long overlay label that must not determine the primary scroll layer desired width</text></overlay></region></ui>");
    }

    auto TemplateMarkup() -> FString
    {
        return TEXT("<ui version=\"1\"><template name=\"scroll-template\"><param name=\"axis\" type=\"text\"/><scroll id=\"scroll\" direction-param=\"axis\"><text id=\"content\">Template content</text></scroll></template><region name=\"main\"><use id=\"templated\" template=\"scroll-template\" axis=\"vertical\"/></region></ui>");
    }

    auto VerticalUseMarkup() -> FString
    {
        return TEXT("<ui version=\"1\"><template name=\"text-child\"><text id=\"text\">Template content</text></template><region name=\"main\"><scroll id=\"vertical-scroll\" direction=\"vertical\"><use id=\"template-child\" template=\"text-child\"/></scroll></region></ui>");
    }

    auto EmptyOverlayMarkup() -> FString
    {
        return TEXT("<ui version=\"1\"><region name=\"main\"><overlay id=\"overlay\"/></region></ui>");
    }

    auto DirectionMarkup(const TCHAR* InDirection) -> FString
    {
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><scroll id=\"direction-scroll\" direction=\"%s\"><text id=\"content\">Direction content</text></scroll></region></ui>"), InDirection);
    }

    auto Styles() -> FString
    {
        return TEXT(".table-wide { min-width: 720px; } .badge { horizontal-align: right; vertical-align: bottom; }");
    }

    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }
        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
    };

    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    auto IsFiniteGeometry(const FGeometry& InGeometry) -> bool
    {
        const FVector2D Size = InGeometry.GetLocalSize();
        return FMath::IsFinite(Size.X) && FMath::IsFinite(Size.Y) && Size.X >= 0.0f && Size.Y > 0.0f;
    }

    auto MouseWheel(const float InDelta) -> FPointerEvent
    {
        return FPointerEvent(0, FVector2D{160.0f, 120.0f}, FVector2D{160.0f, 120.0f}, TSet<FKey>{}, EKeys::Invalid, InDelta, FModifierKeysState{});
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

    auto HasError(const FCkUiLoadResult& InResult, const FString& InText) -> bool
    {
        return InResult.Errors.ContainsByPredicate([&InText](const FString& Error) { return Error.Contains(InText, ESearchCase::IgnoreCase); });
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiScrollOverlay_Runtime,
    "Ck.UiAuthoring.ScrollOverlay.Runtime",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiScrollOverlay_Runtime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_scroll_overlay;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Scroll/overlay runtime test requires initialized Slate.")); return false; }

    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Scroll/overlay collection creates"), FCkUiCollection::TryCreate(Schema(), Collection).Succeeded) || !Collection.IsValid()) { return false; }

    bool bShowBadge = true;
    auto Data = FCkUiView::FDataBindings{};
    Data.Collections.Add(TEXT("resources"), Collection);
    Data.Visibility.Add(TEXT("show-badge"), TAttribute<bool>::CreateLambda([&bShowBadge]() { return bShowBadge; }));
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, MoveTemp(Data));
    const TSharedRef<SWidget> Region = View->GetRegion(TEXT("main"));

    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{320.0f, 240.0f}).CreateTitleBar(false).HasCloseButton(false)[Region];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    if (!TestTrue(TEXT("Horizontal table scroll and overlay load"), View->TryReload(Markup(), Styles(), TEXT("UiScrollOverlay")).Succeeded)) { return false; }
    if (!TestTrue(TEXT("Initial records publish"), Collection->TrySetRecords(Records(1000)).Succeeded)) { return false; }
    Tick(Slate);

    const TSharedPtr<SScrollBox> Scroll = View->GetScroll(TEXT("resource-scroll"));
    const TSharedPtr<SCkUiTable> Table = View->GetTable(TEXT("resources"));
    const TSharedPtr<SListView<SCkUiTable::FRecord>> List = Table.IsValid() ? Table->GetList() : nullptr;
    TSharedPtr<SWidget> Overlay = FindTagged(Region, TEXT("overlay"));
    TSharedPtr<SWidget> Badge = FindTagged(Region, TEXT("overlay-label"));
    if (!TestTrue(TEXT("Real scroll and table retain their public identities"), Scroll.IsValid() && Table.IsValid() && List.IsValid())) { return false; }
    if (!TestTrue(TEXT("Overlay and its authored badge are tagged in the mounted tree"), Overlay.IsValid() && Badge.IsValid())) { return false; }
    TestTrue(TEXT("Narrow host has finite scroll/table geometry"), IsFiniteGeometry(Scroll->GetCachedGeometry()) && IsFiniteGeometry(Table->GetCachedGeometry()));
    TestTrue(TEXT("Table minimum width establishes horizontally scrollable content"), Table->GetCachedGeometry().GetLocalSize().X >= 720.0f && Scroll->GetCachedGeometry().GetLocalSize().X <= 321.0f);
    TestTrue(TEXT("One thousand records realizes bounded native rows"), Table->GetLiveRowCount() > 0 && Table->GetLiveRowCount() < 128);

    const TSharedPtr<const FCkUiRecord> OffscreenOneThousand = Collection->FindRecord(TEXT("row-900"));
    if (!TestTrue(TEXT("Offscreen thousandth record exists"), OffscreenOneThousand.IsValid())) { return false; }
    List->RequestScrollIntoView(OffscreenOneThousand);
    Tick(Slate);
    TestTrue(TEXT("Offscreen table record realizes through native list scrolling"), List->WidgetFromItem(OffscreenOneThousand).IsValid());

    if (!TestTrue(TEXT("Ten thousand records publish"), Collection->TrySetRecords(Records(10000)).Succeeded)) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Ten thousand records remain virtualized"), Table->GetLiveRowCount() > 0 && Table->GetLiveRowCount() < 128);
    const TSharedPtr<const FCkUiRecord> OffscreenTenThousand = Collection->FindRecord(TEXT("row-9000"));
    if (!TestTrue(TEXT("Offscreen ten-thousandth record exists"), OffscreenTenThousand.IsValid())) { return false; }
    List->RequestScrollIntoView(OffscreenTenThousand);
    Tick(Slate);
    TestTrue(TEXT("Offscreen ten-thousandth record realizes through native list scrolling"), List->WidgetFromItem(OffscreenTenThousand).IsValid());
    if (!TestTrue(TEXT("Selected table key commits before retained reload"), Table->TrySelectKey(FString{TEXT("row-9000")}))) { return false; }
    const float ListOffset = List->GetScrollOffset();
    TestTrue(TEXT("Selected key is observable before reload"), Table->GetSelectedKey().IsSet() && Table->GetSelectedKey().GetValue() == TEXT("row-9000"));

    Scroll->SetScrollOffset(120.0f);
    Tick(Slate);
    const float MiddleOffset = Scroll->GetScrollOffset();
    const FReply MiddleWheel = Scroll->OnMouseWheel(Scroll->GetCachedGeometry(), MouseWheel(1.0f));
    Tick(Slate);
    TestTrue(TEXT("Horizontal wheel at a movable offset handles and changes scroll"), MiddleWheel.IsEventHandled() && !FMath::IsNearlyEqual(Scroll->GetScrollOffset(), MiddleOffset));
    Scroll->ScrollToStart();
    Tick(Slate);
    const FReply BoundaryWheel = Scroll->OnMouseWheel(Scroll->GetCachedGeometry(), MouseWheel(1.0f));
    TestTrue(TEXT("Horizontal wheel at its boundary bubbles unhandled"), !BoundaryWheel.IsEventHandled());

    Scroll->SetScrollOffset(120.0f);
    Tick(Slate);
    const float ScrollOffset = Scroll->GetScrollOffset();
    const int64 Revision = View->GetRevision();
    if (!TestTrue(TEXT("Accepted overlay reload succeeds"), View->TryReload(Markup(), Styles() + TEXT(" .badge { color: #ffffff; }"), TEXT("UiScrollOverlayReload")).Succeeded)) { return false; }
    Tick(Slate);
    TestEqual(TEXT("Accepted overlay reload advances revision"), View->GetRevision(), Revision + 1);
    TestTrue(TEXT("Accepted overlay reload retains scroll, table, horizontal offset, selection, and vertical table offset"),
        View->GetScroll(TEXT("resource-scroll")) == Scroll && View->GetTable(TEXT("resources")) == Table
        && FMath::IsNearlyEqual(Scroll->GetScrollOffset(), ScrollOffset)
        && Table->GetSelectedKey().IsSet() && Table->GetSelectedKey().GetValue() == TEXT("row-9000")
        && FMath::IsNearlyEqual(List->GetScrollOffset(), ListOffset));
    Overlay = FindTagged(Region, TEXT("overlay"));
    Badge = FindTagged(Region, TEXT("overlay-label"));
    if (!TestTrue(TEXT("Accepted overlay reload recreates the authored overlay layers"), Overlay.IsValid() && Badge.IsValid())) { return false; }

    Scope.Window->Resize(FVector2D{1000.0f, 240.0f});
    Tick(Slate);
    TestTrue(TEXT("Wide host has finite layout and expands the table to the viewport"), IsFiniteGeometry(Scroll->GetCachedGeometry()) && IsFiniteGeometry(Table->GetCachedGeometry()) && Scroll->GetCachedGeometry().GetLocalSize().X >= 999.0f && Table->GetCachedGeometry().GetLocalSize().X >= 976.0f);

    const FVector2D PrimaryDesired = Scroll->GetDesiredSize();
    const FVector2D OverlayDesired = Overlay->GetDesiredSize();
    TestTrue(TEXT("Long overlay badge does not grow the primary layer desired size"), OverlayDesired.X <= PrimaryDesired.X + KINDA_SMALL_NUMBER && OverlayDesired.Y <= PrimaryDesired.Y + KINDA_SMALL_NUMBER);
    const FVector2D TableSizeBeforeBadgeVisibility = Table->GetCachedGeometry().GetLocalSize();
    bShowBadge = false;
    Tick(Slate);
    TestTrue(TEXT("Overlay badge collapses through its live visibility binding"), Badge->GetVisibility() == EVisibility::Collapsed);
    TestTrue(TEXT("Collapsed overlay badge leaves the primary table arranged"), Table->GetCachedGeometry().GetLocalSize().Equals(TableSizeBeforeBadgeVisibility));
    bShowBadge = true;
    Tick(Slate);
    TestTrue(TEXT("Overlay badge restores without recreating table or scroll"), Badge->GetVisibility() == EVisibility::Visible && View->GetScroll(TEXT("resource-scroll")) == Scroll && View->GetTable(TEXT("resources")) == Table);

    const int64 AcceptedRevision = View->GetRevision();
    const auto Reject = [this, &View, &Scroll, &Table, AcceptedRevision](const FString& InName, const FString& InMarkup)
    {
        const FCkUiLoadResult Result = View->TryReload(InMarkup, Styles(), InName);
        TestFalse(*InName, Result.Succeeded);
        TestTrue(*(InName + TEXT(" reports an error")), !Result.Errors.IsEmpty());
        TestEqual(*(InName + TEXT(" retains revision")), View->GetRevision(), AcceptedRevision);
        TestTrue(*(InName + TEXT(" retains scroll and table")), View->GetScroll(TEXT("resource-scroll")) == Scroll && View->GetTable(TEXT("resources")) == Table);
    };
    Reject(TEXT("Unknown scroll direction rejects"), Markup().Replace(TEXT("direction=\"horizontal\""), TEXT("direction=\"diagonal\"")));
    Reject(TEXT("Invalid table schema rejects"), Markup().Replace(TEXT("sort-field=\"label\""), TEXT("sort-field=\"missing\"")));
    Reject(TEXT("Empty overlay rejects"), EmptyOverlayMarkup());

    const TSharedRef<FCkUiView> DirectionView = FCkUiView::Create({});
    DirectionView->GetRegion(TEXT("main"));
    if (!TestTrue(TEXT("Direct-text horizontal scroll loads before direction retention check"), DirectionView->TryReload(DirectionMarkup(TEXT("horizontal")), TEXT(""), TEXT("UiScrollOverlayDirection")).Succeeded)) { return false; }
    const TSharedPtr<SScrollBox> DirectionScroll = DirectionView->GetScroll(TEXT("direction-scroll"));
    const int64 DirectionRevision = DirectionView->GetRevision();
    const FCkUiLoadResult DirectionChange = DirectionView->TryReload(DirectionMarkup(TEXT("vertical")), TEXT(""), TEXT("UiScrollOverlayDirectionChange"));
    TestFalse(TEXT("Valid direct-text direction change rejects retained scroll"), DirectionChange.Succeeded);
    TestTrue(TEXT("Direction retention rejection identifies direction"), HasError(DirectionChange, TEXT("direction")));
    TestEqual(TEXT("Direction retention rejection retains revision"), DirectionView->GetRevision(), DirectionRevision);
    TestTrue(TEXT("Direction retention rejection retains direct-text scroll"), DirectionView->GetScroll(TEXT("direction-scroll")) == DirectionScroll);

    if (!TestTrue(TEXT("Typed template direction parameter loads"), View->TryReload(TemplateMarkup(), TEXT(""), TEXT("UiScrollOverlayTemplate")).Succeeded)) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Template direction parameter creates retained vertical scroll"), View->GetScroll(TEXT("templated/scroll")).IsValid());
    if (!TestTrue(TEXT("Vertical scroll accepts a use that expands to direct text"), View->TryReload(VerticalUseMarkup(), TEXT(""), TEXT("UiScrollOverlayVerticalUse")).Succeeded)) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Vertical use expansion produces its scroll"), View->GetScroll(TEXT("vertical-scroll")).IsValid());
    auto Parsed = FCkUiDocument{};
    const FCkUiLoadResult UnusedBadTemplate = FCkUiDocumentParser::TryParse(
        TEXT("<ui version=\"1\"><template name=\"unused-bad\"><scroll id=\"bad\" direction=\"diagonal\"><text id=\"text\">x</text></scroll></template><region name=\"main\"><text id=\"ok\">Ok</text></region></ui>"),
        TEXT(""), {}, Parsed, TEXT("UiScrollOverlayUnusedTemplate"));
    TestFalse(TEXT("Unused template with bad literal direction rejects"), UnusedBadTemplate.Succeeded);
    TestTrue(TEXT("Unused bad literal direction reports direction"), HasError(UnusedBadTemplate, TEXT("direction")));
    return true;
}

#endif
