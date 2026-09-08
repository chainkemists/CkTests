#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/SCkUiTable.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_table_selectable
{
    auto Make_Record(
        const FString& InKey,
        const FString& InLabel)
        -> FCkUiRecordData
    {
        auto Result = FCkUiRecordData{};
        Result.Key = InKey;
        Result.Fields.Add(TEXT("label"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(InLabel)});
        return Result;
    }

    auto Markup(const FString& InSelectableAttribute = FString{}) -> FString
    {
        return TEXT("<ui version=\"1\"><region name=\"main\"><table id=\"records\" bind=\"records\" selection-action=\"selected\"")
            + InSelectableAttribute
            + TEXT("><table-column id=\"label\" label=\"Label\"><text id=\"value\" bind-field=\"label\"/></table-column></table></region></ui>");
    }

    auto TemplateMarkup() -> FString
    {
        return TEXT("<ui version=\"1\"><template name=\"selectable-table\"><param name=\"selectable\" type=\"bool\"/><table id=\"records\" bind=\"records\" selection-action=\"selected\" selectable-param=\"selectable\"><table-column id=\"label\" label=\"Label\"><text id=\"value\" bind-field=\"label\"/></table-column></table></template><region name=\"main\"><use template=\"selectable-table\" id=\"templated\" selectable=\"false\"/></region></ui>");
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkUiTable_Selectable,
    "Ck.UiAuthoring.Table.Selectable",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiTable_Selectable::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_table_selectable;

    auto Collection = TSharedPtr<FCkUiCollection>{};
    if (NOT TestTrue(TEXT("Selectable table collection creates"), FCkUiCollection::TryCreate({{TEXT("label"), ECkUiFieldKind::Text}}, Collection).Succeeded)
        || NOT TestTrue(TEXT("Selectable table records publish"), Collection->TrySetRecords({Make_Record(TEXT("alpha"), TEXT("Alpha"))}).Succeeded))
    {
        return false;
    }

    auto Notifications = 0;
    auto Data = FCkUiView::FDataBindings{};
    Data.Collections.Add(TEXT("records"), Collection);
    Data.TableSelectionChanged.Add(TEXT("selected"), FOnCkUiTableSelectionChanged::CreateLambda(
        [&Notifications](TOptional<FString>, ESelectInfo::Type)
        {
            ++Notifications;
        }));
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, MoveTemp(Data));
    View->GetRegion(TEXT("main"));

    if (NOT TestTrue(TEXT("selectable=false table loads"), View->TryReload(Markup(TEXT(" selectable=\"false\"")), TEXT(""), TEXT("UiTableSelectableFalse")).Succeeded))
    {
        return false;
    }
    const TSharedPtr<SCkUiTable> Table = View->GetTable(TEXT("records"));
    const TSharedPtr<SListView<SCkUiTable::FRecord>> List = Table.IsValid() ? Table->GetList() : nullptr;
    if (NOT TestTrue(TEXT("selectable=false exposes the production table and list"), Table.IsValid() && List.IsValid()))
    {
        return false;
    }
    Table->TryRefresh();
    TestEqual(TEXT("selectable=false configures native list selection mode to none"), List->Private_GetSelectionMode(), ESelectionMode::None);
    TestFalse(TEXT("selectable=false rejects nonempty programmatic selection"), Table->TrySelectKey(FString{TEXT("alpha")}, true));
    TestFalse(TEXT("selectable=false keeps no selected key"), Table->GetSelectedKey().IsSet());
    TestEqual(TEXT("selectable=false selection rejection sends no callback"), Notifications, 0);

    const int64 DisabledRevision = View->GetRevision();
    if (NOT TestTrue(TEXT("omitted selectable defaults to enabled"), View->TryReload(Markup(), TEXT(""), TEXT("UiTableSelectableDefault")).Succeeded))
    {
        return false;
    }
    TestEqual(TEXT("default selectable reload advances revision"), View->GetRevision(), DisabledRevision + 1);
    TestTrue(TEXT("default selectable reload retains the table and native list"), View->GetTable(TEXT("records")) == Table && Table->GetList() == List);
    TestEqual(TEXT("omitted selectable uses native single selection"), List->Private_GetSelectionMode(), ESelectionMode::Single);
    Table->TryRefresh();
    TestTrue(TEXT("default selectable accepts nonempty programmatic selection"), Table->TrySelectKey(FString{TEXT("alpha")}, true));
    TestTrue(TEXT("default selectable retains the selected key"), Table->GetSelectedKey() == TOptional<FString>{TEXT("alpha")});
    TestEqual(TEXT("default selectable selection notifies once"), Notifications, 1);

    const int64 SelectedRevision = View->GetRevision();
    const FCkUiLoadResult Rejected = View->TryReload(Markup(TEXT(" selectable=\"sometimes\"")), TEXT(""), TEXT("UiTableSelectableMalformed"));
    TestFalse(TEXT("malformed selectable value rejects"), Rejected.Succeeded);
    TestEqual(TEXT("malformed selectable retains accepted revision"), View->GetRevision(), SelectedRevision);
    TestTrue(TEXT("malformed selectable retains table, list, and selection"), View->GetTable(TEXT("records")) == Table && Table->GetList() == List && Table->GetSelectedKey() == TOptional<FString>{TEXT("alpha")});
    TestEqual(TEXT("malformed selectable sends no callback"), Notifications, 1);

    const int64 EnabledRevision = View->GetRevision();
    if (NOT TestTrue(TEXT("accepted selectable=false reload succeeds"), View->TryReload(Markup(TEXT(" selectable=\"false\"")), TEXT(""), TEXT("UiTableSelectableDisable")).Succeeded))
    {
        return false;
    }
    TestEqual(TEXT("accepted selectable=false reload advances revision"), View->GetRevision(), EnabledRevision + 1);
    TestTrue(TEXT("accepted selectable=false retains native list identity"), View->GetTable(TEXT("records")) == Table && Table->GetList() == List);
    TestEqual(TEXT("accepted selectable=false changes native list selection mode"), List->Private_GetSelectionMode(), ESelectionMode::None);
    TestFalse(TEXT("accepted selectable=false clears the selected key"), Table->GetSelectedKey().IsSet());
    TestEqual(TEXT("accepted selectable=false clears native selected items"), List->GetSelectedItems().Num(), 0);
    TestEqual(TEXT("accepted selectable=false clears silently"), Notifications, 1);

    if (NOT TestTrue(TEXT("template selectable-param transports its boolean value"), View->TryReload(TemplateMarkup(), TEXT(""), TEXT("UiTableSelectableTemplate")).Succeeded))
    {
        return false;
    }
    const TSharedPtr<SCkUiTable> TemplateTable = View->GetTable(TEXT("templated/records"));
    const TSharedPtr<SListView<SCkUiTable::FRecord>> TemplateList = TemplateTable.IsValid() ? TemplateTable->GetList() : nullptr;
    if (NOT TestTrue(TEXT("templated selectable table exposes its production list"), TemplateTable.IsValid() && TemplateList.IsValid()))
    {
        return false;
    }
    TestEqual(TEXT("template selectable=false configures native list selection mode to none"), TemplateList->Private_GetSelectionMode(), ESelectionMode::None);
    TestFalse(TEXT("template selectable=false rejects nonempty programmatic selection"), TemplateTable->TrySelectKey(FString{TEXT("alpha")}, true));
    TestEqual(TEXT("template selectable=false sends no callback"), Notifications, 1);
    return true;
}

#endif
