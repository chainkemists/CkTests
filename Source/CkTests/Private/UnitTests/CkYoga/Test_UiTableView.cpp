#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/SCkUiTable.h"
#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiTable_ViewValidation,
    "Ck.UiAuthoring.Table.ViewSchemaAndRetainedReload",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiTable_ViewValidation::RunTest(const FString&) -> bool
{
    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Typed collection creates"), FCkUiCollection::TryCreate({
        {TEXT("label"), ECkUiFieldKind::Text}, {TEXT("rank"), ECkUiFieldKind::Number},
        {TEXT("enabled"), ECkUiFieldKind::Bool}, {TEXT("optionalLabel"), ECkUiFieldKind::Text, false}}, Collection).Succeeded)) { return false; }
    FCkUiView::FDataBindings Data;
    Data.Collections.Add(TEXT("resources"), Collection);
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {}, {}, {}, MoveTemp(Data));
    const TSharedRef<SWidget> Mount = View->GetRegion(TEXT("main"));
    const auto Markup = [](const FString& Field, const FString& Sort = TEXT("label"))
    {
        return TEXT("<ui version=\"1\"><region name=\"main\"><table id=\"inventory\" bind=\"resources\"><table-column id=\"name\" label=\"Name\" sort-field=\"")
            + Sort + TEXT("\"><text id=\"value\" bind-field=\"") + Field + TEXT("\" visible-field=\"enabled\"/></table-column></table></region></ui>");
    };
    const FCkUiLoadResult Initial = View->TryReload(Markup(TEXT("label")), TEXT(""));
    if (!TestTrue(TEXT("Production view accepts authored table"), Initial.Succeeded))
    {
        for (const FString& Error : Initial.Errors) { AddError(Error); }
        return false;
    }
    const TSharedPtr<SCkUiTable> Table = View->GetTable(TEXT("inventory"));
    if (!TestTrue(TEXT("Authored table is available by ID"), Table.IsValid())) { return false; }
    const TSharedPtr<SListView<SCkUiTable::FRecord>> List = Table->GetList();
    if (!TestTrue(TEXT("Production list exists"), List.IsValid())) { return false; }
    const int64 Revision = View->GetRevision();
    for (const FString& Invalid : {Markup(TEXT("missing")), Markup(TEXT("rank")),
        Markup(TEXT("optionalLabel")), Markup(TEXT("label"), TEXT("missing"))})
    {
        const FCkUiLoadResult Rejected = View->TryReload(Invalid, TEXT(""));
        TestFalse(TEXT("Missing, wrong-type, or unsupported optional row reference rejects"), Rejected.Succeeded);
        TestTrue(TEXT("Schema rejection has diagnostic"), !Rejected.Errors.IsEmpty());
        TestEqual(TEXT("Rejected reload retains revision"), View->GetRevision(), Revision);
        TestTrue(TEXT("Rejected reload retains table and native list"), View->GetTable(TEXT("inventory")) == Table && Table->GetList() == List);
    }
    TestTrue(TEXT("Valid header edit reloads"), View->TryReload(Markup(TEXT("label")).Replace(TEXT("label=\"Name\""), TEXT("label=\"Resource\"")), TEXT("")).Succeeded);
    TestTrue(TEXT("Accepted markup reload retains table and native list"), View->GetTable(TEXT("inventory")) == Table && Table->GetList() == List);
    TestEqual(TEXT("Accepted reload advances once"), View->GetRevision(), Revision + 1);
    return true;
}

#endif
