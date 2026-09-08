#include "CkSlateLayout/CkUiDocument.h"
#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/CkUiWidgetRegistry.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/SCkUiTable.h"

#include "Misc/AutomationTest.h"
#include "Widgets/Input/SSearchBox.h"
#include "Widgets/Text/STextBlock.h"
#include "Widgets/Views/SHeaderRow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_localized_labels
{
    struct FProbe final { int32 FactoryCalls = 0; };

    auto RegisterProbe(const TSharedRef<FProbe>& InProbe, FCkUiWidgetRegistry& InRegistry) -> bool
    {
        auto Registration = FCkUiCustomWidgetRegistration{};
        Registration.Schema.Tag = TEXT("localized-label-probe");
        Registration.Factory = [InProbe](const FCkUiCustomWidgetArguments&, FString&) -> TSharedPtr<SWidget>
        { ++InProbe->FactoryCalls; return SNew(STextBlock); };
        return InRegistry.Register(MoveTemp(Registration)).Succeeded;
    }

    auto Make_Record() -> FCkUiRecordData
    {
        auto Result = FCkUiRecordData{};
        Result.Key = TEXT("row");
        Result.Fields.Add(TEXT("label"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = NSLOCTEXT("Ck.UiAuthoring.Test", "LocalizedRow", "Localized row")});
        return Result;
    }

    auto Markup(
        const FString& InColumnAttributes = TEXT("label-bind=\"header\""),
        const FString& InSearchAttributes = TEXT("placeholder-bind=\"placeholder\""),
        const int32 InRowHeight = 24) -> FString
    {
        return FString::Printf(
            TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><localized-label-probe id=\"probe\"/><search id=\"query\" bind=\"query\" %s/><table id=\"records\" bind=\"records\" row-height=\"%d\"><table-column id=\"label\" %s><text id=\"value\" bind-field=\"label\"/></table-column></table></column></region></ui>"),
            *InSearchAttributes,
            InRowHeight,
            *InColumnAttributes);
    }

    auto TemplateMarkup() -> FString
    {
        return TEXT("<ui version=\"1\"><template name=\"localized\"><param name=\"header\" type=\"text-binding\"/><param name=\"hint\" type=\"text-binding\"/><column id=\"root\"><search id=\"query\" bind=\"query\" placeholder-bind-param=\"hint\"/><table id=\"records\" bind=\"records\"><table-column id=\"label\" label-bind-param=\"header\"><text id=\"value\" bind-field=\"label\"/></table-column></table></column></template><region name=\"main\"><use template=\"localized\" id=\"templated\" header-bind=\"header\" hint-bind=\"placeholder\"/></region></ui>");
    }

    auto Find_Search(const TSharedRef<SWidget>& InWidget) -> TSharedPtr<SSearchBox>
    {
        if (InWidget->GetTypeAsString() == TEXT("SSearchBox"))
        {
            return StaticCastSharedRef<SSearchBox>(InWidget);
        }

        const FChildren* Children = InWidget->GetChildren();
        if (Children == nullptr)
        {
            return {};
        }
        for (auto Index = 0; Index < Children->Num(); ++Index)
        {
            const TSharedPtr<SSearchBox> Found = Find_Search(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)));
            if (Found.IsValid())
            {
                return Found;
            }
        }
        return {};
    }

    auto Get_HeaderText(const TSharedPtr<SListView<SCkUiTable::FRecord>>& InList) -> FText
    {
        const TSharedPtr<SHeaderRow> Header = InList.IsValid() ? InList->GetHeaderRow() : nullptr;
        return Header.IsValid() && Header->GetColumns().Num() == 1
            ? Header->GetColumns()[0].DefaultText.Get()
            : FText::GetEmpty();
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkUi_LocalizedLabels,
    "Ck.UiAuthoring.LocalizedLabels",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUi_LocalizedLabels::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_localized_labels;

    auto Collection = TSharedPtr<FCkUiCollection>{};
    if (NOT TestTrue(TEXT("Localized-label collection creates"), FCkUiCollection::TryCreate({{TEXT("label"), ECkUiFieldKind::Text}}, Collection).Succeeded)
        || NOT TestTrue(TEXT("Localized-label record publishes"), Collection->TrySetRecords({Make_Record()}).Succeeded))
    {
        return false;
    }

    const TSharedRef<FProbe> Probe = MakeShared<FProbe>();
    auto Registry = FCkUiWidgetRegistry{};
    if (NOT TestTrue(TEXT("Localized-label probe registration succeeds"), RegisterProbe(Probe, Registry)))
    {
        return false;
    }

    auto HeaderText = NSLOCTEXT("Ck.UiAuthoring.Test", "LocalizedHeaderInitial", "Localized header initial");
    auto PlaceholderText = NSLOCTEXT("Ck.UiAuthoring.Test", "LocalizedPlaceholderInitial", "Localized placeholder initial");
    auto QueryText = FText::GetEmpty();
    auto HeaderRequests = 0;
    auto PlaceholderRequests = 0;
    auto Data = FCkUiView::FDataBindings{};
    Data.Collections.Add(TEXT("records"), Collection);
    Data.Text.Add(TEXT("header"), TAttribute<FText>::CreateLambda([&HeaderText, &HeaderRequests]() { ++HeaderRequests; return HeaderText; }));
    Data.Text.Add(TEXT("placeholder"), TAttribute<FText>::CreateLambda([&PlaceholderText, &PlaceholderRequests]() { ++PlaceholderRequests; return PlaceholderText; }));
    Data.Text.Add(TEXT("query"), TAttribute<FText>::CreateLambda([&QueryText]() { return QueryText; }));
    Data.TextChanged.Add(TEXT("query"), FOnTextChanged::CreateLambda([&QueryText](const FText& InText) { QueryText = InText; }));
    Data.Text.Add(TEXT("unset"), TAttribute<FText>{});
    TSharedPtr<FCkUiView> View = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, MoveTemp(Data), Registry.CreateSnapshot());
    const TSharedRef<SWidget> Region = View->GetRegion(TEXT("main"));

    if (NOT TestTrue(TEXT("Localized table label and search placeholder document loads"), View->TryReload(Markup(), TEXT(""), TEXT("UiLocalizedLabelsInitial")).Succeeded))
    {
        return false;
    }
    TestEqual(TEXT("Accepted document invokes the preceding probe factory"), Probe->FactoryCalls, 1);
    const TSharedPtr<SCkUiTable> Table = View->GetTable(TEXT("records"));
    const TSharedPtr<SListView<SCkUiTable::FRecord>> List = Table.IsValid() ? Table->GetList() : nullptr;
    const TSharedPtr<SSearchBox> Search = Find_Search(Region);
    if (NOT TestTrue(TEXT("Localized document mounts the production table list and search"), Table.IsValid() && List.IsValid() && Search.IsValid()))
    {
        return false;
    }
    TestTrue(TEXT("Native header column retains the localized FText attribute"), Get_HeaderText(List).IdenticalTo(HeaderText));
    TestTrue(TEXT("Native search retains the localized FText hint attribute"), Search->GetHintText().IdenticalTo(PlaceholderText));

    HeaderText = NSLOCTEXT("Ck.UiAuthoring.Test", "LocalizedHeaderUpdated", "Localized header updated");
    PlaceholderText = NSLOCTEXT("Ck.UiAuthoring.Test", "LocalizedPlaceholderUpdated", "Localized placeholder updated");
    TestTrue(TEXT("Native header observes live localized label changes"), Get_HeaderText(List).IdenticalTo(HeaderText));
    TestTrue(TEXT("Native search observes live localized placeholder changes"), Search->GetHintText().IdenticalTo(PlaceholderText));

    const int64 InitialRevision = View->GetRevision();
    if (NOT TestTrue(TEXT("Compatible localized reload succeeds"), View->TryReload(Markup(TEXT("label-bind=\"header\""), TEXT("placeholder-bind=\"placeholder\""), 25), TEXT(""), TEXT("UiLocalizedLabelsCompatible")).Succeeded))
    {
        return false;
    }
    TestEqual(TEXT("Compatible localized reload advances revision"), View->GetRevision(), InitialRevision + 1);
    TestTrue(TEXT("Compatible localized reload retains table list and search identity"), View->GetTable(TEXT("records")) == Table && Table->GetList() == List && Find_Search(Region) == Search);
    TestTrue(TEXT("Compatible localized reload retains the live header FText"), Get_HeaderText(List).IdenticalTo(HeaderText));
    TestTrue(TEXT("Compatible localized reload retains the live search hint FText"), Search->GetHintText().IdenticalTo(PlaceholderText));

    const auto Expect_Rejected = [this, &View, &Table, &List, &Search, &Region, &HeaderText, &PlaceholderText, &Probe](
                                     const FString& InName,
                                     const FString& InMarkup)
    {
        const int64 Revision = View->GetRevision();
        const int32 FactoryCalls = Probe->FactoryCalls;
        const FCkUiLoadResult Rejected = View->TryReload(InMarkup, TEXT(""), InName);
        TestFalse(*(InName + TEXT(" rejects")), Rejected.Succeeded);
        TestEqual(*(InName + TEXT(" retains revision")), View->GetRevision(), Revision);
        TestTrue(*(InName + TEXT(" retains table list and search")), View->GetTable(TEXT("records")) == Table && Table->GetList() == List && Find_Search(Region) == Search);
        TestTrue(*(InName + TEXT(" retains header FText")), Get_HeaderText(List).IdenticalTo(HeaderText));
        TestTrue(*(InName + TEXT(" retains search hint FText")), Search->GetHintText().IdenticalTo(PlaceholderText));
        TestEqual(*(InName + TEXT(" invokes no preceding custom factory")), Probe->FactoryCalls, FactoryCalls);
    };
    Expect_Rejected(TEXT("Conflicting table-column label forms"), Markup(TEXT("label=\"Literal\" label-bind=\"header\"")));
    Expect_Rejected(TEXT("Conflicting search placeholder forms"), Markup(TEXT("label-bind=\"header\""), TEXT("placeholder=\"Literal\" placeholder-bind=\"placeholder\"")));
    Expect_Rejected(TEXT("Missing table-column header"), Markup(FString{}));
    Expect_Rejected(TEXT("Missing localized header binding"), Markup(TEXT("label-bind=\"missing\"")));
    Expect_Rejected(TEXT("Unset localized header binding"), Markup(TEXT("label-bind=\"unset\"")));
    Expect_Rejected(TEXT("Missing localized placeholder binding"), Markup(TEXT("label-bind=\"header\""), TEXT("placeholder-bind=\"missing\"")));
    Expect_Rejected(TEXT("Unset localized placeholder binding"), Markup(TEXT("label-bind=\"header\""), TEXT("placeholder-bind=\"unset\"")));

    if (NOT TestTrue(TEXT("Template forwards localized label and placeholder bindings"), View->TryReload(TemplateMarkup(), TEXT(""), TEXT("UiLocalizedLabelsTemplate")).Succeeded))
    {
        return false;
    }
    const TSharedPtr<SCkUiTable> TemplateTable = View->GetTable(TEXT("templated/records"));
    const TSharedPtr<SListView<SCkUiTable::FRecord>> TemplateList = TemplateTable.IsValid() ? TemplateTable->GetList() : nullptr;
    const TSharedPtr<SSearchBox> TemplateSearch = Find_Search(Region);
    if (NOT TestTrue(TEXT("Template mounts production table list and search"), TemplateTable.IsValid() && TemplateList.IsValid() && TemplateSearch.IsValid()))
    {
        return false;
    }
    TestTrue(TEXT("Template forwards localized header FText identity"), Get_HeaderText(TemplateList).IdenticalTo(HeaderText));
    TestTrue(TEXT("Template forwards localized search hint FText identity"), TemplateSearch->GetHintText().IdenticalTo(PlaceholderText));

    const int32 HeaderRequestsBeforeRelease = HeaderRequests;
    const int32 PlaceholderRequestsBeforeRelease = PlaceholderRequests;
    const TWeakPtr<FCkUiView> WeakView = View;
    View.Reset();
    TestFalse(TEXT("Retained native widgets do not retain the released view"), WeakView.IsValid());
    TestTrue(TEXT("Released view leaves retained native table list and search valid"), TemplateList.IsValid() && TemplateSearch.IsValid());
    TestTrue(TEXT("Released view clears retained native header text"), Get_HeaderText(TemplateList).IsEmpty());
    TestTrue(TEXT("Released view clears retained native search hint"), TemplateSearch->GetHintText().IsEmpty());
    TestEqual(TEXT("Released view does not invoke retained header binding"), HeaderRequests, HeaderRequestsBeforeRelease);
    TestEqual(TEXT("Released view does not invoke retained placeholder binding"), PlaceholderRequests, PlaceholderRequestsBeforeRelease);
    return true;
}

#endif
