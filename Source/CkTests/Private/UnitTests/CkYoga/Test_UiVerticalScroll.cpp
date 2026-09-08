#include "CkSlateLayout/CkUiDocument.h"
#include "CkSlateLayout/CkFlexText.h"
#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/SCkUiTable.h"

#include "Framework/Application/SlateApplication.h"
#include "Misc/AutomationTest.h"
#include "Styling/CoreStyle.h"
#include "Widgets/Input/SSearchBox.h"
#include "Widgets/Layout/SScrollBox.h"
#include "Widgets/SWindow.h"
#include "Widgets/Views/ITableRow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_vertical_scroll
{
    auto LongBody() -> FString
    {
        FString Result;
        for (int32 Index = 0; Index < 48; ++Index)
        {
            Result += TEXT("A nested authored scroll paragraph has enough words to wrap at a narrow viewport and shrink when the viewport grows. ");
        }
        return Result;
    }

    auto TextMarkup() -> FString
    {
        return TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><scroll id=\"content-scroll\" direction=\"vertical\" class=\"scroll\"><column id=\"content\" class=\"content\"><text id=\"copy\" class=\"copy\" bind=\"body\"/><search id=\"query\" bind=\"query\" placeholder=\"Filter\"/></column></scroll></column></region></ui>");
    }

    auto TextStyles() -> FString
    {
        return TEXT(".scroll { height: 160px; } .content { gap: 8px; } .copy { text-wrap: wrap; text-overflow: clip; }");
    }

    auto TableMarkup() -> FString
    {
        return TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><scroll id=\"outer-scroll\" direction=\"vertical\" class=\"outer\"><column id=\"content\" class=\"content\"><text id=\"heading\">Resources</text><table id=\"resources\" bind=\"resources\" class=\"table\" row-height=\"20\"><table-column id=\"name\" label=\"Name\" sort-field=\"label\"><text id=\"cell\" bind-field=\"label\"/></table-column></table><text id=\"footer\" class=\"footer\">Nested outer-scroll footer</text></column></scroll></column></region></ui>");
    }

    auto TableStyles() -> FString
    {
        return TEXT(".outer { height: 240px; } .content { gap: 6px; } .table { height: 180px; } .footer { height: 160px; }");
    }

    auto IdentifierMarkup() -> FString
    {
        return TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><scroll id=\"identifier-scroll\" direction=\"vertical\" class=\"scroll\"><column id=\"content\" class=\"content\"><text id=\"identifier\" class=\"identifier\" bind=\"identifier\"/></column></scroll></column></region></ui>");
    }

    auto IdentifierStyles(const TCHAR* InOverflowWrap = nullptr) -> FString
    {
        FString Result = TEXT(".scroll { height: 160px; } .content { gap: 0px; } .identifier { text-wrap: wrap; text-overflow: clip; }");
        if (InOverflowWrap != nullptr) { Result += FString::Printf(TEXT(" .identifier { overflow-wrap: %s; }"), InOverflowWrap); }
        return Result;
    }

    auto LongIdentifier() -> FString
    {
        FString Result = TEXT("Texture");
        for (int32 Index = 0; Index < 320; ++Index) { Result += TEXT("_"); }
        return Result;
    }

    auto FindFirstType(const TSharedRef<SWidget>& InRoot, const FString& InType) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTypeAsString() == InType) { return InRoot; }
        const FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SWidget> Found = FindFirstType(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InType); Found.IsValid()) { return Found; }
        }
        return nullptr;
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

    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    auto IsFinite(const FGeometry& InGeometry) -> bool
    {
        const FVector2D Size = InGeometry.GetLocalSize();
        return FMath::IsFinite(Size.X) && FMath::IsFinite(Size.Y) && Size.X >= 0.0f && Size.Y >= 0.0f;
    }

    auto HasError(const FCkUiLoadResult& InResult, const TCHAR* InNeedle) -> bool
    {
        return InResult.Errors.ContainsByPredicate([InNeedle](const FString& Error) { return Error.Contains(InNeedle, ESearchCase::IgnoreCase); });
    }

    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }
        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
    };

    auto Schema() -> TArray<FCkUiFieldSchema>
    {
        return {{TEXT("label"), ECkUiFieldKind::Text}};
    }

    auto Records(const int32 InCount) -> TArray<FCkUiRecordData>
    {
        TArray<FCkUiRecordData> Result;
        Result.Reserve(InCount);
        for (int32 Index = 0; Index < InCount; ++Index)
        {
            FCkUiRecordData Record;
            Record.Key = FString::Printf(TEXT("row-%d"), Index);
            Record.Fields.Add(TEXT("label"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(FString::Printf(TEXT("Resource %d"), Index))});
            Result.Add(MoveTemp(Record));
        }
        return Result;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiVerticalScroll_NestedContent,
    "Ck.UiAuthoring.VerticalScroll.NestedContentRetention",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiVerticalScroll_NestedContent::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_vertical_scroll;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Vertical-scroll nested-content test requires Slate.")); return false; }

    FString Body = LongBody();
    FString Query = TEXT("initial query");
    int32 TextChangedCalls = 0;
    FCkUiView::FDataBindings Data;
    Data.Text.Add(TEXT("body"), TAttribute<FText>::CreateLambda([&Body]() { return FText::FromString(Body); }));
    Data.Text.Add(TEXT("query"), TAttribute<FText>::CreateLambda([&Query]() { return FText::FromString(Query); }));
    Data.TextChanged.Add(TEXT("query"), FOnTextChanged::CreateLambda([&Query, &TextChangedCalls](const FText& InText) { Query = InText.ToString(); ++TextChangedCalls; }));
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {}, {}, FCoreStyle::GetDefaultFontStyle("Regular", 12), MoveTemp(Data));
    const TSharedRef<SWidget> Region = View->GetRegion(TEXT("main"));
    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{320.0f, 240.0f}).CreateTitleBar(false).HasCloseButton(false)[Region];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);

    const FCkUiLoadResult InitialLoad = View->TryReload(TextMarkup(), TextStyles(), TEXT("UiVerticalScrollNested"));
    if (!TestTrue(TEXT("Nested vertical column loads"), InitialLoad.Succeeded))
    {
        for (const FString& Error : InitialLoad.Errors) { AddError(Error); }
        return false;
    }
    Tick(Slate);
    const TSharedPtr<SScrollBox> Scroll = View->GetScroll(TEXT("content-scroll"));
    const TSharedPtr<SWidget> SearchWidget = FindFirstType(Region, TEXT("SSearchBox"));
    const TSharedPtr<SWidget> CopyWidget = FindTagged(Region, TEXT("copy"));
    if (!TestTrue(TEXT("Nested production scroll, search, and text are mounted"), Scroll.IsValid() && SearchWidget.IsValid() && CopyWidget.IsValid())) { return false; }
    const TSharedPtr<SSearchBox> Search = StaticCastSharedPtr<SSearchBox>(SearchWidget);
    if (!TestTrue(TEXT("Nested search has its production type"), Search.IsValid())) { return false; }
    const float NarrowHeight = CopyWidget->GetCachedGeometry().GetLocalSize().Y;
    TestTrue(TEXT("Narrow nested scroll viewport and wrapped text have finite geometry"), IsFinite(Scroll->GetCachedGeometry()) && IsFinite(CopyWidget->GetCachedGeometry())
        && Scroll->GetCachedGeometry().GetLocalSize().X <= 321.0f && CopyWidget->GetCachedGeometry().GetLocalSize().X <= Scroll->GetCachedGeometry().GetLocalSize().X + 1.0f);

    Scroll->SetScrollOffset(120.0f);
    Tick(Slate);
    const float InitialOffset = Scroll->GetScrollOffset();
    if (!TestTrue(TEXT("Nested vertical content scrolls through the real scroll widget"), InitialOffset > 0.0f)) { return false; }

    Body = TEXT("Short content.");
    Tick(Slate);
    TestTrue(*FString::Printf(TEXT("Short content has no remaining scroll extent (end=%g)"), Scroll->GetScrollOffsetOfEnd()), FMath::IsNearlyZero(Scroll->GetScrollOffsetOfEnd()));
    TestTrue(*FString::Printf(TEXT("Content shrink clamps retained scroll offset (offset=%g)"), Scroll->GetScrollOffset()), FMath::IsNearlyZero(Scroll->GetScrollOffset()));
    const float ShortHeight = CopyWidget->GetCachedGeometry().GetLocalSize().Y;

    Body = LongBody();
    Tick(Slate);
    const float RegrownHeight = CopyWidget->GetCachedGeometry().GetLocalSize().Y;
    TestTrue(TEXT("Regrowing content does not restore the obsolete scroll request"), FMath::IsNearlyZero(Scroll->GetScrollOffset()));
    TestTrue(TEXT("Live text binding growth remeasures nested content without a resize"), RegrownHeight > ShortHeight * 4.0f
        && Scroll->GetCachedGeometry().GetLocalSize().X <= 321.0f);
    Scope.Window->Resize(FVector2D{1000.0f, 240.0f});
    Tick(Slate);
    const float WideHeight = CopyWidget->GetCachedGeometry().GetLocalSize().Y;
    TestTrue(TEXT("Wide nested viewport remains finite"), IsFinite(Scroll->GetCachedGeometry()) && IsFinite(CopyWidget->GetCachedGeometry()) && Scroll->GetCachedGeometry().GetLocalSize().X >= 999.0f);
    TestTrue(TEXT("Wider nested column reduces wrapped text height"), NarrowHeight > WideHeight * 1.5f);
    Scroll->SetScrollOffset(120.0f);
    Tick(Slate);
    const float RetainedOffset = Scroll->GetScrollOffset();
    if (!TestTrue(TEXT("Long nested content remains scrollable before retained reload"), Scroll->GetScrollOffsetOfEnd() > RetainedOffset + 1.0f)) { return false; }
    Search->SetText(FText::FromString(TEXT("retained query")));
    if (!TestTrue(TEXT("Search callback updates its live data binding"), Query == TEXT("retained query"))) { return false; }
    if (!TestTrue(TEXT("Nested search receives Slate focus"), Slate.SetKeyboardFocus(Search.ToSharedRef(), EFocusCause::SetDirectly))) { return false; }
    const TSharedPtr<SWidget> FocusedLeaf = Slate.GetUserFocusedWidget(0);
    if (!TestTrue(TEXT("Nested search resolves an exact focused leaf"), FocusedLeaf.IsValid())) { return false; }
    TestTrue(TEXT("Focused leaf belongs to the nested search"), FocusedLeaf == SearchWidget || Slate.HasUserFocusedDescendants(Search.ToSharedRef(), 0));

    const int64 AcceptedRevision = View->GetRevision();
    const FCkUiLoadResult AcceptedLoad = View->TryReload(TextMarkup(), TextStyles().Replace(TEXT("gap: 8px"), TEXT("gap: 10px")), TEXT("UiVerticalScrollNestedReload"));
    if (!TestTrue(TEXT("Accepted nested reload succeeds"), AcceptedLoad.Succeeded))
    {
        for (const FString& Error : AcceptedLoad.Errors) { AddError(Error); }
        return false;
    }
    Tick(Slate);
    TestEqual(TEXT("Accepted nested reload advances revision"), View->GetRevision(), AcceptedRevision + 1);
    TestTrue(TEXT("Accepted nested reload retains the real scroll and search"), View->GetScroll(TEXT("content-scroll")) == Scroll && FindFirstType(Region, TEXT("SSearchBox")) == SearchWidget);
    TestEqual(TEXT("Accepted nested reload retains search value"), Search->GetText().ToString(), Query);
    TestTrue(TEXT("Accepted nested reload restores the exact focused leaf"), Slate.GetUserFocusedWidget(0) == FocusedLeaf);
    TestTrue(TEXT("Accepted nested reload refreshes focused ancestry"), Slate.HasUserFocusedDescendants(Region, 0));
    TestTrue(TEXT("Accepted nested reload preserves the exact vertical offset"), FMath::IsNearlyEqual(Scroll->GetScrollOffset(), RetainedOffset, 1.0f));

    const int32 CallsBeforeRejectedReload = TextChangedCalls;
    const FCkUiLoadResult Rejected = View->TryReload(TextMarkup().Replace(TEXT("class=\"content\""), TEXT("class=\"content\" visible=\"missing\"")), TextStyles(), TEXT("UiVerticalScrollNestedReject"));
    TestFalse(TEXT("Missing nested visibility binding rejects"), Rejected.Succeeded);
    TestTrue(TEXT("Rejected nested reload reports the missing binding"), HasError(Rejected, TEXT("visibility binding")));
    TestEqual(TEXT("Rejected nested reload preserves revision"), View->GetRevision(), AcceptedRevision + 1);
    TestTrue(TEXT("Rejected nested reload preserves real scroll and search identity"), View->GetScroll(TEXT("content-scroll")) == Scroll && FindFirstType(Region, TEXT("SSearchBox")) == SearchWidget);
    TestEqual(TEXT("Rejected nested reload preserves search text"), Search->GetText().ToString(), Query);
    TestTrue(TEXT("Rejected nested reload preserves focused leaf"), Slate.GetUserFocusedWidget(0) == FocusedLeaf);
    TestTrue(TEXT("Rejected nested reload preserves the exact vertical offset"), FMath::IsNearlyEqual(Scroll->GetScrollOffset(), RetainedOffset, 1.0f));
    TestEqual(TEXT("Rejected nested reload does not synthesize a search write"), TextChangedCalls, CallsBeforeRejectedReload);

    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiVerticalScroll_OverflowWrapRuntime,
    "Ck.UiAuthoring.VerticalScroll.OverflowWrapRuntime",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiVerticalScroll_OverflowWrapRuntime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_vertical_scroll;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Overflow-wrap runtime test requires Slate.")); return false; }

    const FString Identifier = LongIdentifier();
    FCkUiView::FDataBindings Data;
    Data.Text.Add(TEXT("identifier"), TAttribute<FText>::CreateLambda([&Identifier]() { return FText::FromString(Identifier); }));
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {}, {}, FCoreStyle::GetDefaultFontStyle("Regular", 12), MoveTemp(Data));
    const TSharedRef<SWidget> Region = View->GetRegion(TEXT("main"));
    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{320.0f, 240.0f}).CreateTitleBar(false).HasCloseButton(false)[Region];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);

    const FCkUiLoadResult NormalLoad = View->TryReload(IdentifierMarkup(), IdentifierStyles(), TEXT("UiVerticalScrollOverflowNormal"));
    if (!TestTrue(TEXT("Normal overflow-wrap document loads"), NormalLoad.Succeeded))
    {
        for (const FString& Error : NormalLoad.Errors) { AddError(Error); }
        return false;
    }
    Tick(Slate);
    const TSharedPtr<SScrollBox> Scroll = View->GetScroll(TEXT("identifier-scroll"));
    const TSharedPtr<SWidget> NormalIdentifier = FindTagged(Region, TEXT("identifier"));
    if (!TestTrue(TEXT("Normal overflow-wrap mounts the real scroll and identifier"), Scroll.IsValid() && NormalIdentifier.IsValid())) { return false; }
    const float NormalHeight = NormalIdentifier->GetCachedGeometry().GetLocalSize().Y;
    TestTrue(TEXT("Normal unbroken identifier remains one clipped line at narrow width"), IsFinite(NormalIdentifier->GetCachedGeometry())
        && NormalIdentifier->GetCachedGeometry().GetLocalSize().X <= Scroll->GetCachedGeometry().GetLocalSize().X + 1.0f
        && NormalHeight > 0.0f);

    const FCkUiLoadResult AnywhereLoad = View->TryReload(IdentifierMarkup(), IdentifierStyles(TEXT("anywhere")), TEXT("UiVerticalScrollOverflowAnywhere"));
    if (!TestTrue(TEXT("Anywhere overflow-wrap reload succeeds"), AnywhereLoad.Succeeded))
    {
        for (const FString& Error : AnywhereLoad.Errors) { AddError(Error); }
        return false;
    }
    Tick(Slate);
    const TSharedPtr<SWidget> AnywhereIdentifier = FindTagged(Region, TEXT("identifier"));
    if (!TestTrue(TEXT("Anywhere reload mounts a new authored identifier"), AnywhereIdentifier.IsValid())) { return false; }
    const float NarrowAnywhereHeight = AnywhereIdentifier->GetCachedGeometry().GetLocalSize().Y;
    TestTrue(TEXT("Anywhere wraps the long unbroken identifier into multiple narrow lines"), NarrowAnywhereHeight > NormalHeight * 2.0f
        && AnywhereIdentifier->GetCachedGeometry().GetLocalSize().X <= Scroll->GetCachedGeometry().GetLocalSize().X + 1.0f);

    Scope.Window->Resize(FVector2D{1000.0f, 240.0f});
    Tick(Slate);
    const float WideAnywhereHeight = AnywhereIdentifier->GetCachedGeometry().GetLocalSize().Y;
    TestTrue(TEXT("Anywhere identifier remains width-bounded at wide size and uses fewer lines"), IsFinite(AnywhereIdentifier->GetCachedGeometry())
        && AnywhereIdentifier->GetCachedGeometry().GetLocalSize().X <= Scroll->GetCachedGeometry().GetLocalSize().X + 1.0f
        && WideAnywhereHeight < NarrowAnywhereHeight * 0.75f);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiVerticalScroll_OverflowWrapValidation,
    "Ck.UiAuthoring.VerticalScroll.OverflowWrapValidation",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiVerticalScroll_OverflowWrapValidation::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_vertical_scroll;
    FCkUiDocument Document;
    const FCkUiLoadResult Valid = FCkUiDocumentParser::TryParse(IdentifierMarkup(), IdentifierStyles(TEXT("normal")), {}, Document, TEXT("UiVerticalScrollOverflowValidation"));
    if (!TestTrue(TEXT("Default normal overflow-wrap parses"), Valid.Succeeded))
    {
        for (const FString& Error : Valid.Errors) { AddError(Error); }
        return false;
    }
    const auto Reject = [this, &Document](const TCHAR* InName, const FString& InMarkup, const FString& InStyles)
    {
        const FCkUiLoadResult Result = FCkUiDocumentParser::TryParse(InMarkup, InStyles, {}, Document, TEXT("UiVerticalScrollOverflowValidation"));
        TestFalse(InName, Result.Succeeded);
        TestTrue(*FString::Printf(TEXT("%s names overflow-wrap"), InName), HasError(Result, TEXT("overflow-wrap")));
        const FCkUiNode* Preserved = Document.Regions.Find(TEXT("main"));
        TestTrue(*FString::Printf(TEXT("%s preserves accepted output"), InName), Preserved != nullptr && Preserved->Id == TEXT("root"));
    };
    Reject(TEXT("Unsupported overflow-wrap value rejects"), IdentifierMarkup(), IdentifierStyles(TEXT("break-word")));
    Reject(TEXT("Overflow-wrap on a non-text node rejects"), TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\" class=\"invalid\"><text id=\"text\">Text</text></column></region></ui>"), TEXT(".invalid { overflow-wrap: anywhere; }"));
    Reject(TEXT("Unused template non-text overflow-wrap rejects"), TEXT("<ui version=\"1\"><template name=\"unused\"><column id=\"root\" class=\"invalid\"><text id=\"text\">Text</text></column></template><region name=\"main\"><text id=\"ok\">Ok</text></region></ui>"), TEXT(".invalid { overflow-wrap: anywhere; }"));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiVerticalScroll_NestedTable,
    "Ck.UiAuthoring.VerticalScroll.NestedTableVirtualization",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiVerticalScroll_NestedTable::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_vertical_scroll;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Vertical-scroll table test requires Slate.")); return false; }

    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Nested-table collection creates"), FCkUiCollection::TryCreate(Schema(), Collection).Succeeded) || !Collection.IsValid()) { return false; }
    FCkUiView::FDataBindings Data;
    Data.Collections.Add(TEXT("resources"), Collection);
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {}, {}, FCoreStyle::GetDefaultFontStyle("Regular", 12), MoveTemp(Data));
    const TSharedRef<SWidget> Region = View->GetRegion(TEXT("main"));
    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{320.0f, 320.0f}).CreateTitleBar(false).HasCloseButton(false)[Region];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    const FCkUiLoadResult InitialLoad = View->TryReload(TableMarkup(), TableStyles(), TEXT("UiVerticalScrollTable"));
    if (!TestTrue(TEXT("Nested bounded table loads"), InitialLoad.Succeeded))
    {
        for (const FString& Error : InitialLoad.Errors) { AddError(Error); }
        return false;
    }
    if (!TestTrue(TEXT("One thousand nested table rows publish"), Collection->TrySetRecords(Records(1000)).Succeeded)) { return false; }
    Tick(Slate);

    const TSharedPtr<SScrollBox> OuterScroll = View->GetScroll(TEXT("outer-scroll"));
    const TSharedPtr<SCkUiTable> Table = View->GetTable(TEXT("resources"));
    const TSharedPtr<SListView<SCkUiTable::FRecord>> List = Table.IsValid() ? Table->GetList() : nullptr;
    if (!TestTrue(TEXT("Nested table uses real outer scroll, authored table, and list"), OuterScroll.IsValid() && Table.IsValid() && List.IsValid())) { return false; }
    TestTrue(TEXT("Nested table and outer viewport have finite bounded geometry"), IsFinite(OuterScroll->GetCachedGeometry()) && IsFinite(Table->GetCachedGeometry())
        && IsFinite(List->GetCachedGeometry()) && Table->GetCachedGeometry().GetLocalSize().Y <= 181.0f
        && List->GetCachedGeometry().GetLocalSize().Y <= 181.0f && OuterScroll->GetCachedGeometry().GetLocalSize().Y <= 241.0f);
    OuterScroll->SetScrollOffset(80.0f);
    Tick(Slate);
    TestTrue(TEXT("Nested table footer makes the real outer scroll movable"), OuterScroll->GetScrollOffset() > 0.0f);
    TestTrue(TEXT("One thousand nested table records realize bounded rows"), Table->GetLiveRowCount() > 0 && Table->GetLiveRowCount() < 128);

    const TSharedPtr<const FCkUiRecord> Thousandth = Collection->FindRecord(TEXT("row-900"));
    if (!TestTrue(TEXT("Offscreen thousandth nested record exists"), Thousandth.IsValid())) { return false; }
    List->RequestScrollIntoView(Thousandth);
    Tick(Slate);
    TestTrue(TEXT("Offscreen thousandth nested record realizes through native list scrolling"), List->WidgetFromItem(Thousandth).IsValid());

    if (!TestTrue(TEXT("Ten thousand nested table rows publish"), Collection->TrySetRecords(Records(10000)).Succeeded)) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Ten thousand nested table records remain virtualized"), Table->GetLiveRowCount() > 0 && Table->GetLiveRowCount() < 128);
    const TSharedPtr<const FCkUiRecord> TenThousandth = Collection->FindRecord(TEXT("row-9000"));
    if (!TestTrue(TEXT("Offscreen ten-thousandth nested record exists"), TenThousandth.IsValid())) { return false; }
    List->RequestScrollIntoView(TenThousandth);
    Tick(Slate);
    TestTrue(TEXT("Offscreen ten-thousandth nested record realizes through native list scrolling"), List->WidgetFromItem(TenThousandth).IsValid());
    return true;
}

#endif
