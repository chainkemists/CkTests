#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/CkUiCollection.h"
#include "CkResourceInspector/CkResourceInspectorModel.h"

#include "Framework/Application/SlateApplication.h"
#include "Misc/AutomationTest.h"
#include "Widgets/Layout/SBox.h"

#if WITH_DEV_AUTOMATION_TESTS
namespace ck_tests_ui_owner_context
{
    struct FObserved
    {
        TArray<int32> Users;
        TArray<int32> PreparedUsers;
    };

    class FUpdate final : public ICkUiPreparedWidgetUpdate
    {
    public:
        void Commit() noexcept override {}
    };

    class FShell final : public ICkUiRetainedWidget
    {
    public:
        FShell(TSharedRef<FObserved> InObserved, const FCkUiCustomWidgetArguments& Args)
            : Observed(InObserved), User(Args.SlateUserIndex), Body(Args.Slots.FindRef(TEXT("body")))
        {
            Root = SNew(SBox)[Body.ToSharedRef()];
        }
        auto GetWidget() const -> TSharedRef<SWidget> override { return Root.ToSharedRef(); }
        auto PrepareReload(const FCkUiCustomWidgetArguments& Args, FString& Error) const -> TUniquePtr<ICkUiPreparedWidgetUpdate> override
        {
            Observed->PreparedUsers.Add(Args.SlateUserIndex);
            if (Args.SlateUserIndex != User || Args.Slots.FindRef(TEXT("body")) != Body)
            { Error = TEXT("Retained owner or body changed."); return {}; }
            return MakeUnique<FUpdate>();
        }
    private:
        TSharedRef<FObserved> Observed;
        int32 User;
        TSharedPtr<SWidget> Body;
        TSharedPtr<SBox> Root;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiOwnerContext,
    "Ck.UiAuthoring.Custom.OwnerContext", EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiOwnerContext::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_owner_context;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Owner context test requires Slate.")); return false; }
    const auto OriginalFocus = FSlateApplication::Get().GetUserFocusedWidget(0);
    const auto Observed = MakeShared<FObserved>();
    FCkUiWidgetRegistry Registry;
    FCkUiCustomWidgetRegistration Probe;
    Probe.Schema.Tag = TEXT("owner-probe");
    Probe.Factory = [Observed](const FCkUiCustomWidgetArguments& Args, FString&) -> TSharedPtr<SWidget>
    {
        Observed->Users.Add(Args.SlateUserIndex);
        return SNew(SBox);
    };
    if (!TestTrue(TEXT("Probe registers"), Registry.Register(MoveTemp(Probe)).Succeeded)) { return false; }
    FCkUiCustomWidgetRegistration Shell;
    Shell.Schema.Tag = TEXT("owner-shell");
    Shell.Schema.Slots = {{TEXT("body"), true}};
    Shell.RetainedFactory = [Observed](const FCkUiCustomWidgetArguments& Args, FString& Error) -> TSharedPtr<ICkUiRetainedWidget>
    {
        Observed->Users.Add(Args.SlateUserIndex);
        if (!Args.Slots.FindRef(TEXT("body")).IsValid()) { Error = TEXT("Body missing."); return {}; }
        return MakeShared<FShell>(Observed, Args);
    };
    if (!TestTrue(TEXT("Shell registers"), Registry.Register(MoveTemp(Shell)).Succeeded)) { return false; }
    TSharedPtr<FCkUiCollection> Items;
    if (!TestTrue(TEXT("Items create"), FCkUiCollection::TryCreate({{TEXT("name"), ECkUiFieldKind::Text}}, Items).Succeeded)) { return false; }
    TArray<FCkUiRecordData> Records;
    for (const TCHAR* Key : {TEXT("a"), TEXT("b")})
    {
        FCkUiRecordData Record; Record.Key = Key;
        Record.Fields.Add(TEXT("name"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(Key)});
        Records.Add(MoveTemp(Record));
    }
    if (!TestTrue(TEXT("Items publish"), Items->TrySetRecords(MoveTemp(Records)).Succeeded)) { return false; }
    FCkUiView::FDataBindings Data;
    Data.SlateUserIndex = 7;
    Data.Collections.Add(TEXT("items"), Items);
    const auto View = FCkUiView::Create({}, {}, {}, {}, Data, Registry.CreateSnapshot());
    const auto Region = View->GetRegion(TEXT("main"));
    const FString Markup = TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><owner-probe id=\"direct\"/><owner-shell id=\"shell\"><slot name=\"body\"><owner-probe id=\"slotted\"/></slot></owner-shell><repeat id=\"repeat\" bind=\"items\"><owner-probe id=\"item\"/></repeat></column></region></ui>");
    const auto Loaded = View->TryReload(Markup, TEXT(""));
    if (!TestTrue(*FString::Join(Loaded.Errors, TEXT("\n")), Loaded.Succeeded)) { return false; }
    TestEqual(TEXT("Direct, shell, slot, and two repeated factories observe context"), Observed->Users.Num(), 5);
    TestTrue(TEXT("Every composed factory inherits host user seven"), !Observed->Users.ContainsByPredicate([](int32 User) { return User != 7; }));
    TestTrue(TEXT("Initial retained preparation inherits host user seven"), Observed->PreparedUsers.Num() == 1 && Observed->PreparedUsers[0] == 7);
    Observed->Users.Reset();
    Observed->PreparedUsers.Reset();
    TestTrue(TEXT("Compatible reload succeeds"), View->TryReload(Markup, TEXT("")).Succeeded);
    TestTrue(TEXT("Retained preparation and nested reload keep context"), Observed->PreparedUsers.Num() == 1 && Observed->PreparedUsers[0] == 7 && !Observed->Users.IsEmpty()
        && !Observed->Users.ContainsByPredicate([](int32 User) { return User != 7; }));

    const FString Leaf = TEXT("<ui version=\"1\"><region name=\"main\"><owner-probe id=\"leaf\"/></region></ui>");
    const int32 Users[] = {2, INDEX_NONE};
    for (int32 User : Users)
    {
        Observed->Users.Reset();
        FCkUiView::FDataBindings OtherData; OtherData.SlateUserIndex = User;
        const auto Other = FCkUiView::Create({}, {}, {}, {}, OtherData, Registry.CreateSnapshot());
        Other->GetRegion(TEXT("main"));
        TestTrue(TEXT("Independent owner context loads"), Other->TryReload(Leaf, TEXT("")).Succeeded);
        TestTrue(TEXT("Independent views neither leak owner nor infer global user"), Observed->Users.Num() == 1 && Observed->Users[0] == User);
    }
    const int64 Revision = View->GetRevision();
    const int32 Calls = Observed->Users.Num();
    TestFalse(TEXT("Markup cannot override host user"), View->TryReload(TEXT("<ui version=\"1\"><region name=\"main\"><owner-probe id=\"leaf\" slate-user-index=\"0\"/></region></ui>"), TEXT("")).Succeeded);
    TestTrue(TEXT("Authored context override rejects before factories/publication"), Observed->Users.Num() == Calls && View->GetRevision() == Revision && View->GetRegion(TEXT("main")) == Region);
    FCkUiView::FDataBindings InvalidData; InvalidData.SlateUserIndex = -2;
    const auto Invalid = FCkUiView::Create({}, {}, {}, {}, InvalidData, Registry.CreateSnapshot());
    Invalid->GetRegion(TEXT("main"));
    TestFalse(TEXT("Malformed negative owner rejects"), Invalid->TryReload(Leaf, TEXT("")).Succeeded);
    TestTrue(TEXT("Malformed owner never calls a factory or publishes partial UI"), Observed->Users.Num() == Calls && Invalid->GetRevision() == 0);
    TSharedPtr<FCkResourceInspectorModel> InvalidModel;
    FString ModelError;
    TestFalse(TEXT("Resource Inspector rejects malformed host context"), FCkResourceInspectorModel::TryCreate({}, InvalidModel, ModelError, -2));
    TestTrue(TEXT("Malformed host context leaves no partially created model"), !InvalidModel.IsValid() && !ModelError.IsEmpty());
    TestTrue(TEXT("Passing context itself never changes keyboard focus"), FSlateApplication::Get().GetUserFocusedWidget(0) == OriginalFocus);
    return true;
}
#endif
