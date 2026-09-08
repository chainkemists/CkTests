#include "CkSlateLayout/CkUiDocument.h"
#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiTable_Schema,
    "Ck.UiAuthoring.Table.SchemaAndAtomicRejection",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiTable_Schema::RunTest(const FString&) -> bool
{
    const auto Wrap = [](const FString& Body)
    { return TEXT("<ui version=\"1\"><region name=\"main\">") + Body + TEXT("</region></ui>"); };
    const FString Cell = TEXT("<text id=\"value\" bind-field=\"label\" visible-field=\"enabled\"/>");
    const auto Table = [](const FString& Body)
    { return TEXT("<table id=\"inventory\" bind=\"resources\" row-height=\"28\" filter-bind=\"query\" selection-action=\"select\">") + Body + TEXT("</table>"); };
    const auto Column = [](const FString& Body)
    { return TEXT("<table-column id=\"name\" label=\"Resource\" sort-field=\"label\">") + Body + TEXT("</table-column>"); };
    FCkUiDocument Document;
    const auto Parse = [&Document](const FString& Markup)
    { return FCkUiDocumentParser::TryParse(Markup, TEXT(""), {}, Document, TEXT("TableSchemaTest")); };
    const FCkUiLoadResult Accepted = Parse(Wrap(Table(Column(Cell))));
    if (!TestTrue(TEXT("Authored table with typed row references parses"), Accepted.Succeeded))
    {
        for (const FString& Error : Accepted.Errors) { AddError(Error); }
        return false;
    }
    const FCkUiNode* Root = Document.Regions.Find(TEXT("main"));
    if (!TestTrue(TEXT("Table root and one column exist"), Root != nullptr && Root->Kind == ECkUiNodeKind::Table
        && Root->Children.Num() == 1 && Root->Children[0].Children.Num() == 1)) { return false; }
    TestEqual(TEXT("Collection binding retained"), Root->Binding, FString(TEXT("resources")));
    TestEqual(TEXT("Row height retained"), Root->RowHeight, 28.0f);
    TestEqual(TEXT("Filter binding retained"), Root->FilterBinding, FString(TEXT("query")));
    TestEqual(TEXT("Selection action retained"), Root->SelectionAction, FString(TEXT("select")));
    TestEqual(TEXT("Header label retained"), Root->Children[0].Header, FString(TEXT("Resource")));
    const FCkUiNode& ParsedCell = Root->Children[0].Children[0];
    TestEqual(TEXT("Row text reference retained"), ParsedCell.FieldBindings.FindRef(TEXT("bind")), FString(TEXT("label")));
    TestEqual(TEXT("Row visibility reference retained"), ParsedCell.FieldBindings.FindRef(TEXT("visible")), FString(TEXT("enabled")));
    TestTrue(TEXT("Row references do not become global bindings"), ParsedCell.Binding.IsEmpty() && ParsedCell.VisibilityBinding.IsEmpty());

    const TArray<FString> RejectedBodies = {
        Column(Cell),
        Table(Cell),
        Table(Column(TEXT(""))),
        Table(Column(Cell + TEXT("<text id=\"extra\">extra</text>"))),
        TEXT("<text id=\"outside\" bind-field=\"label\"/>"),
        Table(Column(TEXT("<text id=\"value\" bind=\"global\" bind-field=\"label\"/>"))),
        Table(Column(TEXT("<text id=\"value\" bind-field=\"label\">literal</text>"))),
        Table(Column(TEXT("<text id=\"value\" bind-field=\"bad field\"/>"))),
        Table(Column(TEXT("<text id=\"value\" visible=\"global\" visible-field=\"enabled\">x</text>"))),
        TEXT("<table id=\"bad\" bind=\"resources\" row-height=\"0\">") + Column(Cell) + TEXT("</table>")
    };
    for (const FString& Body : RejectedBodies)
    {
        const FCkUiLoadResult Rejected = Parse(Wrap(Body));
        TestFalse(*FString::Printf(TEXT("Invalid schema rejects: %s"), *Body), Rejected.Succeeded);
        TestTrue(TEXT("Rejection includes a diagnostic"), !Rejected.Errors.IsEmpty());
        const FCkUiNode* Unchanged = Document.Regions.Find(TEXT("main"));
        TestTrue(TEXT("Rejected document leaves accepted output intact"), Unchanged != nullptr
            && Unchanged->Id == TEXT("inventory") && Unchanged->Children.Num() == 1
            && Unchanged->Children[0].Header == TEXT("Resource"));
    }
    const FString Template = TEXT("<ui version=\"1\"><template name=\"cell\"><param name=\"field\" type=\"text-binding\"/><text id=\"value\" bind-field-param=\"field\"/></template><region name=\"main\">")
        + Table(Column(TEXT("<use id=\"row\" template=\"cell\" field-bind=\"label\"/>"))) + TEXT("</region></ui>");
    const FCkUiLoadResult TemplateResult = Parse(Template);
    if (TestTrue(TEXT("Reusable cell template preserves row-field scope"), TemplateResult.Succeeded))
    {
        const FCkUiNode* TemplateRoot = Document.Regions.Find(TEXT("main"));
        if (TestTrue(TEXT("Expanded cell exists"), TemplateRoot != nullptr && TemplateRoot->Children.Num() == 1
            && TemplateRoot->Children[0].Children.Num() == 1))
        {
            const FCkUiNode& ExpandedCell = TemplateRoot->Children[0].Children[0];
            TestEqual(TEXT("Expanded field remains a row reference"), ExpandedCell.FieldBindings.FindRef(TEXT("bind")), FString(TEXT("label")));
            TestEqual(TEXT("Cell instance namespaces its ID"), ExpandedCell.Id, FString(TEXT("row/value")));
        }
    }
    TestTrue(TEXT("Image row field satisfies its required binding"), Parse(Wrap(Table(Column(TEXT("<image id=\"icon\" bind-field=\"icon\"/>"))))).Succeeded);
    return true;
}

#endif
