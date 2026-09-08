#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/CkUiWidgetRegistry.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Misc/AutomationTest.h"
#include "Widgets/Text/STextBlock.h"

#if WITH_DEV_AUTOMATION_TESTS
namespace ck_tests_ui_key_collection_bindings
{
    struct FProbe final
    {
        FCkUiCustomWidgetArguments Arguments;
        int32 Factories = 0;
    };

    auto Markup(const FString& Node = TEXT("<transport id=\"transport\" value-bind=\"key\" options-bind=\"options\" changed=\"changed\"/>")) -> FString
    {
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\">%s</column></region></ui>"), *Node);
    }

    auto Register(const TSharedRef<FProbe>& Probe, FCkUiWidgetRegistry& Registry) -> bool
    {
        FCkUiCustomWidgetRegistration Registration;
        Registration.Schema.Tag = TEXT("transport");
        Registration.Schema.Properties = {
            {TEXT("value"), ECkUiCustomPropertyKind::StringBinding},
            {TEXT("options"), ECkUiCustomPropertyKind::CollectionBinding},
            {TEXT("changed"), ECkUiCustomPropertyKind::StringChanged},
        };
        Registration.Factory = [Probe](const FCkUiCustomWidgetArguments& Arguments, FString&) -> TSharedPtr<SWidget>
        {
            ++Probe->Factories;
            Probe->Arguments = Arguments;
            return SNew(STextBlock);
        };
        return Registry.Register(MoveTemp(Registration)).Succeeded;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiKeyCollectionBindings_Transport,
    "Ck.UiAuthoring.Transport.StringCollectionBindings",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiKeyCollectionBindings_Transport::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_key_collection_bindings;
    const TSharedRef<FProbe> Probe = MakeShared<FProbe>();
    FCkUiWidgetRegistry Registry;
    if (!TestTrue(TEXT("Transport schema registers"), Register(Probe, Registry))) { return false; }
    TSharedPtr<FCkUiCollection> Options;
    if (!TestTrue(TEXT("Collection creates"), FCkUiCollection::TryCreate({{TEXT("key"), ECkUiFieldKind::Text}}, Options).Succeeded)) { return false; }
    FString Key = TEXT("CaseSensitiveKey");
    int32 Changed = 0;
    FString Received;
    auto Data = FCkUiView::FDataBindings{};
    Data.Text.Add(TEXT("wrong-type"), TAttribute<FText>::CreateLambda([] { return FText::FromString(TEXT("present-only-as-text")); }));
    Data.String.Add(TEXT("key"), TAttribute<FString>::CreateLambda([&Key] { return Key; }));
    Data.Collections.Add(TEXT("options"), Options);
    Data.StringChanged.Add(TEXT("changed"), FCkUiOnStringChanged::CreateLambda([&Changed, &Received](const FString& Value) { ++Changed; Received = Value; }));
    TSharedPtr<FCkUiView> View = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, MoveTemp(Data), Registry.CreateSnapshot());
    View->GetRegion(TEXT("main"));
    if (!TestTrue(TEXT("Typed transport document loads"), View->TryReload(Markup(), TEXT(""), TEXT("KeyCollectionTransport")).Succeeded)) { return false; }
    TestEqual(TEXT("Factory runs once"), Probe->Factories, 1);
    if (!TestTrue(TEXT("Factory receives string binding"), Probe->Arguments.StringBindings.Contains(TEXT("value")))
        || !TestTrue(TEXT("Factory receives collection binding"), Probe->Arguments.Collections.Contains(TEXT("options")))
        || !TestTrue(TEXT("Factory receives bound string event"), Probe->Arguments.StringChanged.FindRef(TEXT("changed")).IsBound())) { return false; }
    TestTrue(TEXT("String binding preserves exact case"), Probe->Arguments.StringBindings.FindRef(TEXT("value")).Get().Equals(Key, ESearchCase::CaseSensitive));
    TestTrue(TEXT("Collection preserves shared identity"), Probe->Arguments.Collections.FindRef(TEXT("options")) == Options);
    const int64 Revision = Options->GetRevision();
    Key = TEXT("casesensitivekey");
    TestTrue(TEXT("String binding stays live and case-sensitive"), Probe->Arguments.StringBindings.FindRef(TEXT("value")).Get().Equals(Key, ESearchCase::CaseSensitive));
    auto Record = FCkUiRecordData{};
    Record.Key = TEXT("option-a");
    Record.Fields.Add(TEXT("key"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(TEXT("option-a"))});
    if (!TestTrue(TEXT("Collection publishes a revision"), Options->TrySetRecords({MoveTemp(Record)}).Succeeded)) { return false; }
    TestTrue(TEXT("Captured collection observes revision changes"), Probe->Arguments.Collections.FindRef(TEXT("options"))->GetRevision() > Revision);
    Probe->Arguments.StringChanged.FindRef(TEXT("changed")).Execute(TEXT("SelectedKey"));
    TestTrue(TEXT("Typed string event reaches owner"), Changed == 1 && Received == TEXT("SelectedKey"));

    const int32 Factories = Probe->Factories;
    const int64 ViewRevision = View->GetRevision();
    const auto Reject = [this, &View, &Probe, Factories, ViewRevision](const FString& Name, const FString& Source)
    {
        TestFalse(*Name, View->TryReload(Source, TEXT(""), Name).Succeeded);
        TestEqual(*(Name + TEXT(" invokes no factory")), Probe->Factories, Factories);
        TestEqual(*(Name + TEXT(" preserves revision")), View->GetRevision(), ViewRevision);
    };
    Reject(TEXT("Missing string binding rejects"), Markup(TEXT("<transport id=\"transport\" options-bind=\"options\" changed=\"changed\"/>")));
    Reject(TEXT("Missing collection binding rejects"), Markup(TEXT("<transport id=\"transport\" value-bind=\"key\" changed=\"changed\"/>")));
    Reject(TEXT("Missing string event rejects"), Markup(TEXT("<transport id=\"transport\" value-bind=\"key\" options-bind=\"options\" changed=\"missing\"/>")));
    Reject(TEXT("Wrong-map string binding rejects"), Markup(TEXT("<transport id=\"transport\" value-bind=\"wrong-type\" options-bind=\"options\" changed=\"changed\"/>")));
    const FString Template = TEXT("<ui version=\"1\"><template name=\"transport-template\"><param name=\"value\" type=\"string-binding\"/><param name=\"options\" type=\"collection-binding\"/><param name=\"changed\" type=\"string-changed\"/><transport id=\"probe\" value-bind-param=\"value\" options-bind-param=\"options\" changed-param=\"changed\"/></template><region name=\"main\"><use template=\"transport-template\" id=\"instance\" value-bind=\"key\" options-bind=\"options\" changed=\"changed\"/></region></ui>");
    TestTrue(TEXT("Template propagates all new transports"), View->TryReload(Template, TEXT(""), TEXT("KeyCollectionTemplate")).Succeeded);

    TSharedPtr<FCkUiCollection> Records;
    if (!TestTrue(TEXT("Readonly table collection creates"), FCkUiCollection::TryCreate({{TEXT("key"), ECkUiFieldKind::Text}}, Records).Succeeded)) { return false; }
    auto ReadonlyData = FCkUiView::FDataBindings{};
    ReadonlyData.Collections.Add(TEXT("records"), Records);
    ReadonlyData.Collections.Add(TEXT("options"), Options);
    ReadonlyData.String.Add(TEXT("key"), TAttribute<FString>::CreateLambda([&Key] { return Key; }));
    ReadonlyData.StringChanged.Add(TEXT("changed"), FCkUiOnStringChanged::CreateLambda([](const FString&) {}));
    const TSharedRef<FCkUiView> ReadonlyView = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, MoveTemp(ReadonlyData), Registry.CreateSnapshot());
    ReadonlyView->GetRegion(TEXT("main"));
    const int32 FactoriesBeforeReadonly = Probe->Factories;
    const FString TableMarkup = TEXT("<ui version=\"1\"><region name=\"main\"><table id=\"table\" bind=\"records\"><table-column id=\"column\" label=\"Key\"><transport id=\"cell\" value-bind=\"key\" options-bind=\"options\" changed=\"changed\"/></table-column></table></region></ui>");
    TestFalse(TEXT("Readonly table rejects string edit event"), ReadonlyView->TryReload(TableMarkup, TEXT(""), TEXT("KeyCollectionReadonlyTable")).Succeeded);
    TestEqual(TEXT("Readonly table candidate invokes no factory"), Probe->Factories, FactoriesBeforeReadonly);

    const int32 BeforeRelease = Changed;
    View.Reset();
    Probe->Arguments.StringChanged.FindRef(TEXT("changed")).Execute(TEXT("after-release"));
    TestEqual(TEXT("Released view suppresses string delivery"), Changed, BeforeRelease);
    return true;
}
#endif
