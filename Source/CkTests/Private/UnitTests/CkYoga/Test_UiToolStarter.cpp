#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/CkUiDialog.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/SCkUiTable.h"

#include "Framework/Application/SlateApplication.h"
#include "Interfaces/IPluginManager.h"
#include "Misc/AutomationTest.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Styling/CoreStyle.h"
#include "Widgets/SWindow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_tool_starter
{
    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    auto Text(const FString& InValue) -> FCkUiFieldValue
    {
        return {.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(InValue)};
    }

    auto Color(const FLinearColor InValue) -> FCkUiFieldValue
    {
        return {.Kind = ECkUiFieldKind::Color, .Color = InValue};
    }

    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }
        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
    };

}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiToolStarter,
    "Ck.CapabilityGallery.ToolStarter.InstalledContract",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiToolStarter::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_tool_starter;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Starter installed-resource test requires Slate.")); return false; }
    const TSharedPtr<IPlugin> Plugin = IPluginManager::Get().FindPlugin(TEXT("CkTests"));
    if (!TestTrue(TEXT("CkTests plugin resolves"), Plugin.IsValid())) { return false; }

    FCkUiWidgetRegistry Registry;
    if (!TestTrue(TEXT("Starter dialog adapter registers"), FCkUiDialog::Register(Registry).Succeeded)) { return false; }

    TSharedPtr<FCkUiCollection> Records;
    if (!TestTrue(TEXT("Starter records collection creates"), FCkUiCollection::TryCreate({
        {TEXT("name"), ECkUiFieldKind::Text},
        {TEXT("description"), ECkUiFieldKind::Text},
        {TEXT("color"), ECkUiFieldKind::Color},
        {TEXT("tooltip"), ECkUiFieldKind::Text}}, Records).Succeeded)) { return false; }
    FCkUiRecordData Record;
    Record.Key = TEXT("record-a");
    Record.Fields.Add(TEXT("name"), Text(TEXT("Installed record")));
    Record.Fields.Add(TEXT("description"), Text(TEXT("Loaded through the starter resource.")));
    Record.Fields.Add(TEXT("color"), Color(FLinearColor{0.2f, 0.6f, 0.9f, 1.0f}));
    Record.Fields.Add(TEXT("tooltip"), Text(TEXT("Starter record tooltip")));
    if (!TestTrue(TEXT("Starter record publishes"), Records->TrySetRecords({MoveTemp(Record)}).Succeeded)) { return false; }

    FString Query;
    FString SelectedKey;
    const FString Title = TEXT("Installed starter");
    const FString Status = TEXT("Ready");
    const FString SelectedName = TEXT("Installed record");
    const FString SelectedDescription = TEXT("Selected details");
    const FString ConfirmCopy = TEXT("Remove this record?");
    bool bEmpty = false;
    bool bConfirmOpen = false;
    bool bEnabled = true;
    int32 RefreshCalls = 0;
    int32 ClearFilterCalls = 0;
    int32 DeleteRequests = 0;
    int32 CancelCalls = 0;
    int32 ConfirmCalls = 0;
    FCkUiView::FDataBindings Data;
    Data.SlateUserIndex = 0;
    const auto AddStaticText = [&Data](const TCHAR* InName, FString InValue)
    {
        Data.Text.Add(InName, TAttribute<FText>::CreateLambda([Value = MoveTemp(InValue)]() { return FText::FromString(Value); }));
    };
    AddStaticText(TEXT("starter-title"), Title);
    AddStaticText(TEXT("starter-status"), Status);
    Data.Text.Add(TEXT("starter-query"), TAttribute<FText>::CreateLambda([&Query]() { return FText::FromString(Query); }));
    AddStaticText(TEXT("starter-selected-name"), SelectedName);
    AddStaticText(TEXT("starter-selected-description"), SelectedDescription);
    AddStaticText(TEXT("starter-confirm-copy"), ConfirmCopy);
    Data.Visibility.Add(TEXT("starter-empty"), TAttribute<bool>::CreateLambda([&bEmpty]() { return bEmpty; }));
    Data.Visibility.Add(TEXT("starter-confirm-open"), TAttribute<bool>::CreateLambda([&bConfirmOpen]() { return bConfirmOpen; }));
    Data.Visibility.Add(TEXT("starter-enabled"), TAttribute<bool>::CreateLambda([&bEnabled]() { return bEnabled; }));
    Data.Collections.Add(TEXT("starter-records"), Records);
    Data.TextChanged.Add(TEXT("starter-query"), FOnTextChanged::CreateLambda([&Query](const FText& InValue) { Query = InValue.ToString(); }));
    Data.TableSelectionChanged.Add(TEXT("starter-select-record"), FOnCkUiTableSelectionChanged::CreateLambda([&SelectedKey](TOptional<FString> InKey, ESelectInfo::Type) { SelectedKey = InKey.IsSet() ? InKey.GetValue() : FString{}; }));

    FCkUiView::FActions Actions;
    Actions.Add(TEXT("starter-refresh"), FSimpleDelegate::CreateLambda([&RefreshCalls]() { ++RefreshCalls; }));
    Actions.Add(TEXT("starter-clear-filter"), FSimpleDelegate::CreateLambda([&ClearFilterCalls, &Query]() { ++ClearFilterCalls; Query.Reset(); }));
    Actions.Add(TEXT("starter-request-delete"), FSimpleDelegate::CreateLambda([&DeleteRequests]() { ++DeleteRequests; }));
    Actions.Add(TEXT("starter-cancel-delete"), FSimpleDelegate::CreateLambda([&CancelCalls, &bConfirmOpen]() { ++CancelCalls; bConfirmOpen = false; }));
    Actions.Add(TEXT("starter-confirm-delete"), FSimpleDelegate::CreateLambda([&ConfirmCalls, &bConfirmOpen]() { ++ConfirmCalls; bConfirmOpen = false; }));
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, MoveTemp(Actions), {}, FCoreStyle::GetDefaultFontStyle("Regular", 12), MoveTemp(Data), Registry.CreateSnapshot());
    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{960.0f, 640.0f})
        .CreateTitleBar(false).HasCloseButton(false)[View->GetRegion(TEXT("main"))];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);

    const FString Directory = FPaths::Combine(Plugin->GetBaseDir(), TEXT("Resources/CapabilityGallery/Templates"));
    const FString MarkupPath = FPaths::Combine(Directory, TEXT("GalleryStarter.ui.html"));
    const FString StylesheetPath = FPaths::Combine(Directory, TEXT("GalleryStarter.ui.css"));
    View->GetRegion(TEXT("main"));
    const FCkUiLoadResult Loaded = View->ReloadFiles(MarkupPath, StylesheetPath);
    if (!TestTrue(TEXT("Installed starter resource loads through FCkUiView"), Loaded.Succeeded))
    {
        for (const FString& Error : Loaded.Errors) { AddError(Error); }
        return false;
    }
    Tick(Slate);
    const TSharedPtr<SWidget> AcceptedRegion = View->GetRegion(TEXT("main"));
    const TSharedPtr<SCkUiTable> AcceptedTable = View->GetTable(TEXT("starter-confirm-dialog/content/starter-records"));
    if (!TestTrue(TEXT("Accepted starter exposes the main region and qualified table"), AcceptedRegion.IsValid() && AcceptedTable.IsValid())) { return false; }
    TestTrue(TEXT("Starter table projects the supplied typed record"), AcceptedTable->TrySelectKey(TOptional<FString>{FString(TEXT("record-a"))}, true));
    TestEqual(TEXT("Starter table dispatches documented selection callback"), SelectedKey, FString(TEXT("record-a")));

    FString Markup;
    if (!TestTrue(TEXT("Installed starter markup reads for a file-backed malformed reload"), FFileHelper::LoadFileToString(Markup, *MarkupPath))) { return false; }
    if (!TestTrue(TEXT("Malformed reload references a missing search binding"), Markup.ReplaceInline(TEXT(" bind=\"starter-query\""), TEXT(" bind=\"starter-query-missing\""), ESearchCase::CaseSensitive) == 1)) { return false; }
    FString Stylesheet;
    if (!TestTrue(TEXT("Installed starter stylesheet reads for the in-memory malformed reload"), FFileHelper::LoadFileToString(Stylesheet, *StylesheetPath))) { return false; }
    const FCkUiLoadResult Rejected = View->TryReload(Markup, Stylesheet, TEXT("GalleryStarterMissingBinding"));
    TestFalse(TEXT("Missing required starter callback rejects"), Rejected.Succeeded);
    TestTrue(TEXT("Rejected starter reload preserves the accepted region and table"), View->GetRegion(TEXT("main")) == AcceptedRegion
        && View->GetTable(TEXT("starter-confirm-dialog/content/starter-records")) == AcceptedTable);
    return true;
}

#endif
