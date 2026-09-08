#include "CkSlateLayout/CkUiWidgetRegistry.h"
#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiCustomSlots_Parser, "Ck.UiAuthoring.CustomSlots.SchemaAndTemplates",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)
auto FCkUiCustomSlots_Parser::RunTest(const FString&) -> bool
{
    int32 Factories = 0;
    FCkUiCustomWidgetRegistration Registration;
    Registration.Schema.Tag = TEXT("inspector-card");
    Registration.Schema.Slots = {{TEXT("body"), true}, {TEXT("footer"), false}};
    Registration.RetainedFactory = [&Factories](const FCkUiCustomWidgetArguments&, FString&) -> TSharedPtr<ICkUiRetainedWidget>
    { ++Factories; return {}; };
    FCkUiWidgetRegistry Registry;
    auto Invalid = Registration;
    Invalid.Schema.Slots.Add({TEXT("body"), false});
    TestFalse(TEXT("Duplicate slots reject atomically"), Registry.Register(Invalid).Succeeded);
    TestTrue(TEXT("Rejected registration leaves tag available"), Registry.Register(Registration).Succeeded);
    const auto Snapshot = Registry.CreateSnapshot();
    TestEqual(TEXT("Snapshot preserves required and optional declarations"), Snapshot->Find(TEXT("inspector-card"))->Schema.Slots.Num(), 2);
    auto Stateless = Registration;
    Stateless.Schema.Tag = TEXT("stateless-card");
    Stateless.RetainedFactory = {};
    Stateless.Factory = [](const FCkUiCustomWidgetArguments&, FString&) -> TSharedPtr<SWidget> { return {}; };
    TestFalse(TEXT("Stateless registrations cannot own persistent slots"), Registry.Register(Stateless).Succeeded);
    auto BadName = Registration;
    BadName.Schema.Tag = TEXT("bad-card");
    BadName.Schema.Slots = {{TEXT("bad name"), true}};
    TestFalse(TEXT("Invalid slot identifiers reject"), Registry.Register(BadName).Succeeded);
    auto Reserved = Registration;
    Reserved.Schema.Tag = TEXT("slot");
    TestFalse(TEXT("Slot wrapper tag is reserved"), Registry.Register(Reserved).Succeeded);
    auto TooMany = Registration;
    TooMany.Schema.Tag = TEXT("large-card");
    TooMany.Schema.Slots.Reset();
    for (int32 Index = 0; Index < 17; ++Index) { TooMany.Schema.Slots.Add({FString::Printf(TEXT("slot%d"), Index), false}); }
    TestFalse(TEXT("Slot schema count is bounded"), Registry.Register(TooMany).Succeeded);

    const auto Parse = [&Snapshot](const FString& Markup, FCkUiDocument& Document)
    { return FCkUiDocumentParser::TryParse(Markup, TEXT(""), {}, Document, TEXT("CustomSlots"), Snapshot); };
    const auto Wrap = [](const FString& Content)
    { return TEXT("<ui version=\"1\"><region name=\"main\"><inspector-card id=\"card\">") + Content + TEXT("</inspector-card></region></ui>"); };
    const FString Body = TEXT("<slot name=\"body\"><text id=\"copy\">Body</text></slot>");
    FCkUiDocument Document;
    const auto Loaded = Parse(Wrap(Body), Document);
    if (!TestTrue(TEXT("Required body with omitted optional footer parses"), Loaded.Succeeded))
    { AddError(FString::Join(Loaded.Errors, TEXT("\n"))); return false; }
    const auto& Root = Document.Regions.FindChecked(TEXT("main"));
    TestEqual(TEXT("Slot wrapper emits only its authored root"), Root.Children.Num(), 1);
    TestEqual(TEXT("Typed root retains slot ownership name"), Root.Children[0].CustomSlotName, FString(TEXT("body")));
    TestEqual(TEXT("Slot does not rename ordinary authored identity"), Root.Children[0].Id, FString(TEXT("copy")));
    const FString Template = TEXT("<ui version=\"1\"><template name=\"copy-template\"><text id=\"text\">Templated body</text></template><region name=\"main\"><inspector-card id=\"card\"><slot name=\"body\"><use id=\"instance\" template=\"copy-template\"/></slot></inspector-card></region></ui>");
    const auto ExpandedResult = Parse(Template, Document);
    if (!TestTrue(TEXT("Template use can supply a slot root"), ExpandedResult.Succeeded))
    { AddError(FString::Join(ExpandedResult.Errors, TEXT("\n"))); return false; }
    const auto& Expanded = Document.Regions.FindChecked(TEXT("main")).Children[0];
    TestEqual(TEXT("Expanded slot root retains lexical template identity"), Expanded.Id, FString(TEXT("instance/text")));
    TestEqual(TEXT("Expansion preserves slot name"), Expanded.CustomSlotName, FString(TEXT("body")));
    for (const FString& InvalidBody : {
        FString{}, Body + Body,
        FString(TEXT("<slot name=\"other\"><text id=\"x\">x</text></slot>")),
        FString(TEXT("<slot name=\"body\"/>")),
        FString(TEXT("<slot name=\"body\"><text id=\"x\"/><text id=\"y\"/></slot>")),
        FString(TEXT("<slot name=\"body\" id=\"extra\"><text id=\"x\"/></slot>")),
        FString(TEXT("<text id=\"x\">Unslotted</text>"))})
    {
        TestFalse(TEXT("Invalid container slots reject"), Parse(Wrap(InvalidBody), Document).Succeeded);
    }
    TestEqual(TEXT("Parsing and registration never invoke factories"), Factories, 0);
    return true;
}
#endif
