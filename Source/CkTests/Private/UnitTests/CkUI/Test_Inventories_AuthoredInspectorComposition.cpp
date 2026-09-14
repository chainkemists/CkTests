#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/Validation/CkIsValid.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Fragment.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Net/CkNet_Utils.h"
#include "CkEcsDebugger/Inspectors/CkInspector_Inventories.h"
#include "CkEcsDebugger/Models/CkDebuggerModel_EntitySelection.h"
#include "CkInventory/Inventory/DataOnly/CkInventory_DataOnly_Utils.h"
#include "CkInventory/Inventory/CkInventory_Utils.h"
#include "CkInventory/Item/CkItem_Definition.h"
#include "CkInventory/Item/CkItem_Utils.h"
#include "CkInventory/ItemTrait/Stackable/CkItemTrait_Stackable.h"
#include "CkInventory/ItemTrait/Stackable/CkItemTrait_Stackable_Utils.h"
#include "CkInventory/ItemTrait/Tags/CkItemTrait_Tags.h"
#include "CkInventory/ItemTrait/Tags/CkItemTrait_Tags_Utils.h"
#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/SCkUiRepeat.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include "Framework/Application/SlateApplication.h"
#include "Framework/Application/SlateUser.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Interfaces/IPluginManager.h"
#include "Layout/WidgetPath.h"
#include "Misc/AutomationTest.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "UObject/UnrealType.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Input/SEditableTextBox.h"
#include "Widgets/SNullWidget.h"
#include "Widgets/SWindow.h"

namespace ck_tests_inventories_authored_inspector
{
    constexpr auto kFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    auto FindTagged(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTag() == InTag && InRoot->GetVisibility().IsVisible()) { return InRoot; }
        FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const auto Found = FindTagged(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag);
                Found.IsValid()) { return Found; }
        }
        return nullptr;
    }

    auto FindType(const TSharedRef<SWidget>& InRoot, const FString& InType) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTypeAsString() == InType && InRoot->GetVisibility().IsVisible()) { return InRoot; }
        FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const auto Found = FindType(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InType);
                Found.IsValid()) { return Found; }
        }
        return nullptr;
    }

    auto FindInput(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SEditableTextBox>
    {
        const auto Host = FindTagged(InRoot, InTag);
        if (NOT Host.IsValid()) { return nullptr; }
        auto Input = FindType(Host.ToSharedRef(), TEXT("SEditableTextBox"));
        if (NOT Input.IsValid()) { Input = FindType(Host.ToSharedRef(), TEXT("SCkUiTextInputBox")); }
        return Input.IsValid() ? StaticCastSharedPtr<SEditableTextBox>(Input) : nullptr;
    }

    auto FindButton(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SButton>
    {
        const auto Host = FindTagged(InRoot, InTag);
        const auto Button = Host.IsValid() ? FindType(Host.ToSharedRef(), TEXT("SButton")) : nullptr;
        return Button.IsValid() ? StaticCastSharedPtr<SButton>(Button) : nullptr;
    }

    auto Tick(FSlateApplication& InSlate) -> void
    { InSlate.PumpMessages(); InSlate.Tick(); InSlate.Tick(); }

    auto Key(const FKey InKey) -> FKeyEvent
    { return FKeyEvent{InKey, FModifierKeysState{}, 0, false, 0, 0}; }

    auto Commit(FSlateApplication& InSlate, const TSharedRef<SEditableTextBox>& InInput, const FString& InValue) -> bool
    {
        InSlate.SetUserFocus(0, InInput, EFocusCause::SetDirectly);
        Tick(InSlate);
        InInput->SetText(FText::FromString(InValue));
        const bool Handled = InSlate.ProcessKeyDownEvent(Key(EKeys::Enter));
        Tick(InSlate);
        return Handled;
    }

    auto WidgetPathContains(const FWidgetPath& InPath, const TSharedRef<SWidget>& InWidget) -> bool
    {
        for (int32 Index = 0; Index < InPath.Widgets.Num(); ++Index)
        {
            if (InPath.Widgets[Index].Widget == InWidget) { return true; }
        }
        return false;
    }

    struct FPhysicalClickResult final
    {
        bool WindowValid = false;
        bool NativeWindowValid = false;
        bool EnabledBeforeDown = false;
        bool GeometryValid = false;
        bool TargetPathValid = false;
        bool Targeted = false;
        bool DownHandled = false;
        bool CapturedAfterDown = false;
        bool CaptorValidAfterDown = false;
        bool CaptorPathContainsTarget = false;
        bool TargetedBeforeUp = false;
        bool UpHandled = false;
        bool WidgetPathValid = false;
        FVector2D LocalSize = FVector2D::ZeroVector;
        FVector2D AbsolutePosition = FVector2D::ZeroVector;
        FString WidgetPath;
        FString TargetLeafType;
        FName TargetLeafTag;
        FString CaptorType;
        FName CaptorTag;

        auto Succeeded() const -> bool { return Targeted && DownHandled && UpHandled; }
    };

    auto ClickDetailed(FSlateApplication& InSlate, const TSharedRef<SWidget>& InWidget) -> FPhysicalClickResult
    {
        auto Result = FPhysicalClickResult{};
        const TSharedPtr<SWindow> Window = InSlate.FindWidgetWindow(InWidget);
        Result.WindowValid = Window.IsValid();
        Result.NativeWindowValid = Window.IsValid() && Window->GetNativeWindow().IsValid();
        if (NOT Result.NativeWindowValid) { return Result; }
        Window->BringToFront(true);
        Tick(InSlate);
        InSlate.ReleaseAllPointerCapture(0);
        FWidgetPath WidgetPath;
        Result.WidgetPathValid = InSlate.GeneratePathToWidgetUnchecked(InWidget, WidgetPath, EVisibility::All);
        TOptional<FGeometry> ArrangedTargetGeometry;
        for (int32 Index = 0; Index < WidgetPath.Widgets.Num(); ++Index)
        {
            const FArrangedWidget& Arranged = WidgetPath.Widgets[Index];
            if (Arranged.Widget == InWidget) { ArrangedTargetGeometry = Arranged.Geometry; }
            const EVisibility Visibility = Arranged.Widget->GetVisibility();
            const FVector2D Size = Arranged.Geometry.GetLocalSize();
            Result.WidgetPath += FString::Printf(TEXT("[%d:%s tag=%s visible=%d self-hit=%d child-hit=%d size=(%.1f,%.1f)]"),
                Index, *Arranged.Widget->GetTypeAsString(), *Arranged.Widget->GetTag().ToString(),
                Visibility.IsVisible(), Visibility.IsHitTestVisible(), Visibility.AreChildrenHitTestVisible(), Size.X, Size.Y);
        }
        Result.EnabledBeforeDown = InWidget->IsEnabled();
        const FGeometry Geometry = ArrangedTargetGeometry.IsSet()
            ? ArrangedTargetGeometry.GetValue() : InWidget->GetCachedGeometry();
        Result.LocalSize = Geometry.GetLocalSize();
        Result.GeometryValid = Result.LocalSize.X > 0.0f && Result.LocalSize.Y > 0.0f;
        if (NOT Result.GeometryValid) { return Result; }
        Result.AbsolutePosition = Geometry.LocalToAbsolute(Result.LocalSize * 0.5f);
        const TSet<FKey> NoButtons;
        const TSet<FKey> LeftDown{EKeys::LeftMouseButton};
        const FPointerEvent MoveEvent(0, FSlateApplication::CursorPointerIndex,
            Result.AbsolutePosition, Result.AbsolutePosition, NoButtons, EKeys::Invalid, 0.0f, FModifierKeysState{});
        const FPointerEvent DownEvent(0, FSlateApplication::CursorPointerIndex,
            Result.AbsolutePosition, Result.AbsolutePosition, LeftDown, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        const FPointerEvent UpEvent(0, FSlateApplication::CursorPointerIndex,
            Result.AbsolutePosition, Result.AbsolutePosition, NoButtons, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        InSlate.SetCursorPos(Result.AbsolutePosition);
        InSlate.ProcessMouseMoveEvent(MoveEvent, true);
        const FWidgetPath TargetPath = InSlate.LocateWindowUnderMouse(
            Result.AbsolutePosition, InSlate.GetInteractiveTopLevelWindows(), false, 0);
        Result.TargetPathValid = TargetPath.IsValid();
        if (Result.TargetPathValid && TargetPath.Widgets.Num() > 0)
        {
            const TSharedRef<SWidget> TargetLeaf = TargetPath.Widgets.Last().Widget;
            Result.TargetLeafType = TargetLeaf->GetTypeAsString();
            Result.TargetLeafTag = TargetLeaf->GetTag();
        }
        Result.Targeted = WidgetPathContains(TargetPath, InWidget);
        if (NOT Result.Targeted) { return Result; }
        Result.DownHandled = InSlate.ProcessMouseButtonDownEvent(Window->GetNativeWindow(), DownEvent);
        Result.CapturedAfterDown = InWidget->HasMouseCapture();
        const TSharedPtr<FSlateUser> CursorUser = InSlate.GetUser(0);
        const TSharedPtr<SWidget> Captor = CursorUser.IsValid()
            ? CursorUser->GetPointerCaptor(FSlateApplication::CursorPointerIndex) : nullptr;
        Result.CaptorValidAfterDown = Captor.IsValid();
        Result.CaptorType = Captor.IsValid() ? Captor->GetTypeAsString() : TEXT("<none>");
        Result.CaptorTag = Captor.IsValid() ? Captor->GetTag() : NAME_None;
        const FWidgetPath CaptorPath = CursorUser.IsValid()
            ? CursorUser->GetCaptorPath(FSlateApplication::CursorPointerIndex,
                FWeakWidgetPath::EInterruptedPathHandling::ReturnInvalid, &DownEvent)
            : FWidgetPath{};
        Result.CaptorPathContainsTarget = CaptorPath.IsValid() && WidgetPathContains(CaptorPath, InWidget);
        const FWidgetPath UpTargetPath = InSlate.LocateWindowUnderMouse(
            Result.AbsolutePosition, InSlate.GetInteractiveTopLevelWindows(), false, 0);
        Result.TargetedBeforeUp = WidgetPathContains(UpTargetPath, InWidget);
        Result.UpHandled = InSlate.ProcessMouseButtonUpEvent(UpEvent);
        Tick(InSlate);
        return Result;
    }

    auto MakeAuthorityNetSettings() -> FCk_Net_ConnectionSettings
    {
        return FCk_Net_ConnectionSettings{
            ECk_Replication::DoesNotReplicate,
            ECk_Net_NetModeType::ClientAndHost,
            ECk_Net_EntityNetRole::Authority};
    }

    auto MakeRecordIdentity(const FCk_Handle& InHandle) -> FString
    {
        const auto& Entity = InHandle.Get_Entity();
        return FString::Printf(TEXT("%u:%u"), static_cast<uint32>(Entity.Get_ID()),
            static_cast<uint32>(Entity.Get_VersionNumber()));
    }

    struct FScenario
    {
        bool FixtureCreated = false;
        bool UiReady = false;
        FCk_Handle Owner;
        FCk_Handle Subject;
        FCk_Handle_Inventory_DataOnly Inventory;
        FCk_Handle_Item Item;
        FGameplayTag TestTag;
        TUniquePtr<FCkInspector_Inventories> Inspector;
        TSharedPtr<FCkDebuggerModel_EntitySelection> Selection;
        FCk_Handle Navigated;
        int32 BoundBeforeHeldInput = INDEX_NONE;
        int32 StackBeforeHeldAction = INDEX_NONE;
        FString Markup;
        FString Stylesheet;
        FString InventoryRecordKey;
        FString InventoryMeterRecordKey;
        FString ItemRecordKey;
        TSharedPtr<SCkInspector_InventoriesAuthored> Authored;
        TSharedPtr<FCkUiView> View;
        TSharedPtr<SEditableTextBox> BoundInput;
        TSharedPtr<SEditableTextBox> ConsumeInput;
        TSharedPtr<SEditableTextBox> TagInput;
        TSharedPtr<SButton> InventoryButton;
        TSharedPtr<SButton> ItemButton;
        TSharedPtr<SButton> ConsumeButton;
        TSharedPtr<SButton> AddTagButton;
        TSharedPtr<SButton> RemoveTagButton;
        TSharedPtr<SWindow> Window;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Inventories_AuthoredInspectorComposition,
    "Ck.UiAuthoring.EcsDebugger.InventoriesInspector.AuthoredComposition",
    ck_tests_inventories_authored_inspector::kFlags)

bool FCkTest_Inventories_AuthoredInspectorComposition::RunTest(const FString&)
{
    using namespace ck_tests_inventories_authored_inspector;
    const auto Scenario = MakeShared<FScenario>();
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, Scenario](UWorld* InWorld)
        {
            if (NOT FSlateApplication::IsInitialized()) { AddError(TEXT("Inventories fixture requires Slate")); return; }
            Scenario->Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld);
            Scenario->Subject = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Scenario->Owner);
            const auto Params = UCk_Utils_Inventory_DataOnly_UE::Make_Params_Bounded(FGameplayTag{}, 4,
                FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic{}, FCk_Delegate_Inventory_CustomCanStackItems_Dynamic{});
            Scenario->Inventory = UCk_Utils_Inventory_DataOnly_UE::Add(
                Scenario->Subject, Params, ECk_Replication::DoesNotReplicate);
            Scenario->InventoryRecordKey = TEXT("inventory/") + MakeRecordIdentity(Scenario->Inventory);
            auto InventoryEntity = FCk_Handle{Scenario->Inventory};
            UCk_Utils_Net_UE::Add(InventoryEntity, MakeAuthorityNetSettings());

            auto* StackTrait = NewObject<UCk_ItemTrait_Stackable>(GetTransientPackage());
            auto* TagsTrait = NewObject<UCk_ItemTrait_Tags>(GetTransientPackage());
            const auto* InitialCount = FindFProperty<FIntProperty>(UCk_ItemTrait_Stackable::StaticClass(), TEXT("_InitialCount"));
            if (InitialCount != nullptr) { InitialCount->SetPropertyValue_InContainer(StackTrait, 5); }
            const TArray<UCk_ItemTrait*> Traits{StackTrait, TagsTrait};
            auto* Definition = UCk_Utils_Item_UE::GetOrCreate_TransientItemDefinition(GetTransientPackage(),
                FName{TEXT("Ck_InventoriesAuthoredFixtureItem")},
                FCk_InventoryItem_CoreInfo{FText::FromString(TEXT("Fixture Stack"))}, Traits);
            auto ItemEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Scenario->Inventory);
            Scenario->Item = UCk_Utils_Item_UE::Add(ItemEntity, Definition);
            Scenario->InventoryMeterRecordKey = Scenario->InventoryRecordKey + TEXT("/meter");
            Scenario->ItemRecordKey = Scenario->InventoryRecordKey + TEXT("/item/") + MakeRecordIdentity(Scenario->Item);
            ItemEntity = FCk_Handle{Scenario->Item};
            UCk_Utils_Net_UE::Add(ItemEntity, MakeAuthorityNetSettings());
            UCk_Utils_Inventory_UE::RecordOfInventoryItems_Utils::Request_Connect(
                InventoryEntity, Scenario->Item, ECk_Record_LabelRequirementPolicy::Optional);
            ck::TUtils_Item_ParentInventory::AddOrReplace(Scenario->Item, Scenario->Inventory);
            Scenario->TestTag = TAG_IntegerAttribute_InventoryItem_StackCount;
            if (NOT TestTrue(TEXT("fixture creates bounded inventory and five-unit tagged stack"),
                ck::IsValid(Scenario->Subject) && ck::IsValid(Scenario->Inventory) && ck::IsValid(Scenario->Item)
                    && Scenario->TestTag.IsValid()
                    && UCk_Utils_ItemTrait_Stackable_UE::Get_StackCount(Scenario->Item) == 5
                    && UCk_Utils_ItemTrait_Tags_UE::Get_HasTagsFeature(Scenario->Item))) { return; }

            Scenario->FixtureCreated = true;
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, Scenario](UWorld*)
        {
            if (NOT Scenario->FixtureCreated) { return; }
            const auto Inventories = UCk_Utils_Inventory_UE::RecordOfInventories_Utils::Get_ValidEntries(
                Scenario->Subject);
            if (NOT TestTrue(TEXT("canonical inventory creation connects the subject before mounting"),
                Inventories.Contains(Scenario->Inventory))) { return; }

            Scenario->Inspector = MakeUnique<FCkInspector_Inventories>();
            Scenario->Selection = MakeShared<FCkDebuggerModel_EntitySelection>();
            Scenario->Selection->OnSelectionChanged.AddLambda([Raw = &Scenario.Get()](const TArray<FCk_Handle>& Selection)
            { Raw->Navigated = Selection.IsEmpty() ? FCk_Handle{} : Selection[0]; });
            Scenario->Inspector->Set_SelectionModel(Scenario->Selection);
            const TSharedRef<SWidget> Rendered = Scenario->Inspector->Build_Inspector(Scenario->Subject);
            if (NOT TestEqual(TEXT("Inventories mounts authored composition"), Rendered->GetTypeAsString(),
                FString{TEXT("SCkInspector_InventoriesAuthored")}))
            { AddError(Scenario->Inspector->Get_LastAuthoredLoadError()); return; }
            Scenario->Authored = StaticCastSharedRef<SCkInspector_InventoriesAuthored>(Rendered);
            Scenario->View = Scenario->Authored->Get_View();
            if (NOT TestTrue(TEXT("authored hierarchy publishes inventory, control, and item records"),
                Scenario->View.IsValid() && Scenario->Authored->Get_IsAvailable()
                    && Scenario->Authored->Get_CanRequest()
                    && Scenario->Authored->Get_RecordsCollection()->GetRecords().Num() == 3)) { return; }

            auto& Slate = FSlateApplication::Get();
            Scenario->Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{760.0f, 640.0f})
                .CreateTitleBar(false).HasCloseButton(false)[Rendered];
            Slate.AddWindow(Scenario->Window.ToSharedRef(), true);
            Tick(Slate);
            Rendered->SlatePrepass(1.0f);
            const auto& Records = Scenario->Authored->Get_RecordsCollection()->GetRecords();
            const TSharedPtr<SCkUiRepeat> Repeat = Scenario->View->GetRepeat(TEXT("inventory-records"));
            TSharedPtr<SWidget> HeaderItem;
            TSharedPtr<SWidget> MeterItem;
            TSharedPtr<SWidget> InventoryItem;
            if (Repeat.IsValid())
            {
                for (const auto& Record : Records)
                {
                    if (NOT Record.IsValid()) { continue; }
                    const FString& Key = Record->GetKey();
                    if (Key.EndsWith(TEXT("/meter"))) { MeterItem = Repeat->GetItemWidget(Key); }
                    else if (Key.Contains(TEXT("/item/"))) { InventoryItem = Repeat->GetItemWidget(Key); }
                    else { HeaderItem = Repeat->GetItemWidget(Key); }
                }
            }
            Scenario->BoundInput = MeterItem.IsValid() ? FindInput(MeterItem.ToSharedRef(), TEXT("inventory-bound")) : nullptr;
            Scenario->ConsumeInput = InventoryItem.IsValid() ? FindInput(InventoryItem.ToSharedRef(), TEXT("inventory-consume-count")) : nullptr;
            Scenario->TagInput = InventoryItem.IsValid() ? FindInput(InventoryItem.ToSharedRef(), TEXT("inventory-tag")) : nullptr;
            Scenario->InventoryButton = HeaderItem.IsValid() ? FindButton(HeaderItem.ToSharedRef(), TEXT("inventory-select")) : nullptr;
            Scenario->ItemButton = InventoryItem.IsValid() ? FindButton(InventoryItem.ToSharedRef(), TEXT("inventory-item-select")) : nullptr;
            Scenario->ConsumeButton = InventoryItem.IsValid() ? FindButton(InventoryItem.ToSharedRef(), TEXT("inventory-consume")) : nullptr;
            Scenario->AddTagButton = InventoryItem.IsValid() ? FindButton(InventoryItem.ToSharedRef(), TEXT("inventory-tag-add")) : nullptr;
            Scenario->RemoveTagButton = InventoryItem.IsValid() ? FindButton(InventoryItem.ToSharedRef(), TEXT("inventory-tag-remove")) : nullptr;
            if (NOT TestTrue(TEXT("authored inventory materializes bound, consume, and tag editors"),
                Scenario->BoundInput.IsValid() && Scenario->ConsumeInput.IsValid() && Scenario->TagInput.IsValid()
                    && Scenario->InventoryButton.IsValid() && Scenario->ItemButton.IsValid()
                    && Scenario->ConsumeButton.IsValid() && Scenario->AddTagButton.IsValid()
                    && Scenario->RemoveTagButton.IsValid())) { return; }
            const TSharedPtr<IPlugin> Plugin = IPluginManager::Get().FindPlugin(TEXT("CkDebugger"));
            const FString Root = Plugin.IsValid() ? FPaths::Combine(Plugin->GetBaseDir(), TEXT("Resources/UI")) : FString{};
            if (NOT TestTrue(TEXT("installed Inventories resources are readable"), Plugin.IsValid()
                && FFileHelper::LoadFileToString(Scenario->Markup, *FPaths::Combine(Root, TEXT("EcsInspectorInventories.ui.html")))
                && FFileHelper::LoadFileToString(Scenario->Stylesheet, *FPaths::Combine(Root, TEXT("EcsInspectorInventories.ui.css")))))
            { return; }
            TestTrue(TEXT("HTML owns inventory controls without native ports"),
                Scenario->Markup.Contains(TEXT("inventory-bound")) && Scenario->Markup.Contains(TEXT("inventory-consume"))
                    && Scenario->Markup.Contains(TEXT("inventory-tag-add")) && NOT Scenario->Markup.Contains(TEXT("<native")));
            Scenario->UiReady = true;
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, Scenario](UWorld*)
        {
            if (NOT Scenario->UiReady) { return; }
            auto& Slate = FSlateApplication::Get();
            const auto GetItemWidget = [Scenario](const FString& InKey) -> TSharedPtr<SWidget>
            {
                const TSharedPtr<SCkUiRepeat> Repeat = Scenario->View->GetRepeat(TEXT("inventory-records"));
                return Repeat.IsValid() ? Repeat->GetItemWidget(InKey) : nullptr;
            };
            const auto GetButton = [&GetItemWidget](const FString& InKey, const FName InTag) -> TSharedPtr<SButton>
            {
                const TSharedPtr<SWidget> Item = GetItemWidget(InKey);
                return Item.IsValid() ? FindButton(Item.ToSharedRef(), InTag) : nullptr;
            };
            const auto GetInput = [&GetItemWidget](const FString& InKey, const FName InTag) -> TSharedPtr<SEditableTextBox>
            {
                const TSharedPtr<SWidget> Item = GetItemWidget(InKey);
                return Item.IsValid() ? FindInput(Item.ToSharedRef(), InTag) : nullptr;
            };
            const TSharedPtr<const FCkUiRecord> CurrentRecord =
                Scenario->Authored->Get_RecordsCollection()->FindRecord(Scenario->InventoryRecordKey);
            const FCkUiFieldValue* InventoryVisible = CurrentRecord.IsValid()
                ? CurrentRecord->FindField(TEXT("inventory-visible")) : nullptr;
            const TSharedPtr<SCkUiRepeat> CurrentRepeat = Scenario->View->GetRepeat(TEXT("inventory-records"));
            const TSharedPtr<SWidget> CurrentHeader = CurrentRepeat.IsValid()
                ? CurrentRepeat->GetItemWidget(Scenario->InventoryRecordKey) : nullptr;
            const TSharedPtr<SButton> CurrentInventoryButton = CurrentHeader.IsValid()
                ? FindButton(CurrentHeader.ToSharedRef(), TEXT("inventory-select")) : nullptr;
            const bool ReplacedBeforeFirstPaint = CurrentInventoryButton.IsValid()
                && CurrentInventoryButton != Scenario->InventoryButton;
            const bool SavedAttached = Slate.FindWidgetWindow(Scenario->InventoryButton.ToSharedRef()).IsValid();
            const bool CurrentAttached = CurrentInventoryButton.IsValid()
                && Slate.FindWidgetWindow(CurrentInventoryButton.ToSharedRef()).IsValid();
            const FPhysicalClickResult InventoryClick = CurrentInventoryButton.IsValid()
                ? ClickDetailed(Slate, CurrentInventoryButton.ToSharedRef()) : FPhysicalClickResult{};
            const TSharedPtr<SWidget> HeaderAfterClick = CurrentRepeat.IsValid()
                ? CurrentRepeat->GetItemWidget(Scenario->InventoryRecordKey) : nullptr;
            const TSharedPtr<SButton> ButtonAfterClick = HeaderAfterClick.IsValid()
                ? FindButton(HeaderAfterClick.ToSharedRef(), TEXT("inventory-select")) : nullptr;
            const bool RetainedDuringClick = ButtonAfterClick == CurrentInventoryButton;
            const bool SelectedInventory = Scenario->Navigated == Scenario->Inventory;
            TestTrue(FString::Printf(TEXT("Inventory select routed click: record=%d visible=%d current=%d replaced-before-first-paint=%d saved-attached=%d current-attached=%d retained-during-click=%d window=%d native=%d enabled=%d geometry=%d size=(%.1f,%.1f) absolute=(%.1f,%.1f) widget-path-valid=%d widget-path=%s hit-path=%d targeted=%d leaf=%s tag=%s down=%d captured=%d captor=%d type=%s tag=%s captor-path-target=%d targeted-before-up=%d up=%d selected=%d"),
                CurrentRecord.IsValid(), InventoryVisible != nullptr && InventoryVisible->Kind == ECkUiFieldKind::Bool
                    && InventoryVisible->Bool, CurrentInventoryButton.IsValid(), ReplacedBeforeFirstPaint,
                SavedAttached, CurrentAttached, RetainedDuringClick,
                InventoryClick.WindowValid, InventoryClick.NativeWindowValid, InventoryClick.EnabledBeforeDown,
                InventoryClick.GeometryValid, InventoryClick.LocalSize.X, InventoryClick.LocalSize.Y,
                InventoryClick.AbsolutePosition.X, InventoryClick.AbsolutePosition.Y, InventoryClick.WidgetPathValid,
                *InventoryClick.WidgetPath, InventoryClick.TargetPathValid,
                InventoryClick.Targeted, *InventoryClick.TargetLeafType, *InventoryClick.TargetLeafTag.ToString(),
                InventoryClick.DownHandled, InventoryClick.CapturedAfterDown, InventoryClick.CaptorValidAfterDown,
                *InventoryClick.CaptorType, *InventoryClick.CaptorTag.ToString(),
                InventoryClick.CaptorPathContainsTarget, InventoryClick.TargetedBeforeUp, InventoryClick.UpHandled,
                SelectedInventory), CurrentRecord.IsValid()
                    && InventoryVisible != nullptr && InventoryVisible->Kind == ECkUiFieldKind::Bool
                    && InventoryVisible->Bool && CurrentAttached && RetainedDuringClick
                    && InventoryClick.Succeeded() && SelectedInventory);
            const TSharedPtr<SButton> CurrentItemButton = GetButton(
                Scenario->ItemRecordKey, TEXT("inventory-item-select"));
            if (NOT TestTrue(TEXT("current item navigation control is attached"), CurrentItemButton.IsValid()
                && Slate.FindWidgetWindow(CurrentItemButton.ToSharedRef()).IsValid())) { return; }
            TestTrue(TEXT("physical item navigation activates"),
                ClickDetailed(Slate, CurrentItemButton.ToSharedRef()).Succeeded());
            TestTrue(TEXT("item navigation selects the routed item"), Scenario->Navigated == Scenario->Item);

            const TSharedPtr<SEditableTextBox> CurrentBoundInput = GetInput(
                Scenario->InventoryMeterRecordKey, TEXT("inventory-bound"));
            if (NOT TestTrue(TEXT("current bound editor is attached"), CurrentBoundInput.IsValid()
                && Slate.FindWidgetWindow(CurrentBoundInput.ToSharedRef()).IsValid())) { return; }
            TestTrue(TEXT("physical bound editor commits"), Commit(Slate, CurrentBoundInput.ToSharedRef(), TEXT("7")));

            const TSharedPtr<SEditableTextBox> CurrentConsumeInput = GetInput(
                Scenario->ItemRecordKey, TEXT("inventory-consume-count"));
            if (NOT TestTrue(TEXT("current consume editor is attached"), CurrentConsumeInput.IsValid()
                && Slate.FindWidgetWindow(CurrentConsumeInput.ToSharedRef()).IsValid())) { return; }
            TestTrue(TEXT("physical consume editor stages two units"), Commit(Slate, CurrentConsumeInput.ToSharedRef(), TEXT("2")));
            const TSharedPtr<SButton> CurrentConsumeButton = GetButton(
                Scenario->ItemRecordKey, TEXT("inventory-consume"));
            if (NOT TestTrue(TEXT("current consume action is attached"), CurrentConsumeButton.IsValid()
                && Slate.FindWidgetWindow(CurrentConsumeButton.ToSharedRef()).IsValid())) { return; }
            TestTrue(TEXT("physical consume action activates"),
                ClickDetailed(Slate, CurrentConsumeButton.ToSharedRef()).Succeeded());

            const TSharedPtr<SEditableTextBox> CurrentTagInput = GetInput(
                Scenario->ItemRecordKey, TEXT("inventory-tag"));
            if (NOT TestTrue(TEXT("current tag editor is attached"), CurrentTagInput.IsValid()
                && Slate.FindWidgetWindow(CurrentTagInput.ToSharedRef()).IsValid())) { return; }
            TestTrue(TEXT("physical tag editor stages a registered tag"),
                Commit(Slate, CurrentTagInput.ToSharedRef(), Scenario->TestTag.ToString()));
            const TSharedPtr<SButton> CurrentAddTagButton = GetButton(
                Scenario->ItemRecordKey, TEXT("inventory-tag-add"));
            if (NOT TestTrue(TEXT("current add-tag action is attached"), CurrentAddTagButton.IsValid()
                && Slate.FindWidgetWindow(CurrentAddTagButton.ToSharedRef()).IsValid())) { return; }
            TestTrue(TEXT("physical add-tag action activates"),
                ClickDetailed(Slate, CurrentAddTagButton.ToSharedRef()).Succeeded());
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(2));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, Scenario](UWorld*)
        {
            if (NOT Scenario->UiReady) { return; }
            TestEqual(TEXT("physical bound request reaches the production processor"),
                UCk_Utils_Inventory_DataOnly_UE::Get_BoundMax(Scenario->Inventory).Get(-1), 7);
            TestEqual(TEXT("physical consume request reaches the production processor"),
                UCk_Utils_ItemTrait_Stackable_UE::Get_StackCount(Scenario->Item), 3);
            TestTrue(TEXT("physical add-tag request reaches the production processor"),
                UCk_Utils_ItemTrait_Tags_UE::HasTagExact(Scenario->Item, Scenario->TestTag));
            const TSharedPtr<SCkUiRepeat> Repeat = Scenario->View->GetRepeat(TEXT("inventory-records"));
            const TSharedPtr<SWidget> ItemWidget = Repeat.IsValid()
                ? Repeat->GetItemWidget(Scenario->ItemRecordKey) : nullptr;
            const TSharedPtr<SButton> RemoveTagButton = ItemWidget.IsValid()
                ? FindButton(ItemWidget.ToSharedRef(), TEXT("inventory-tag-remove")) : nullptr;
            if (NOT TestTrue(TEXT("current remove-tag action survives the processor refresh"),
                RemoveTagButton.IsValid())) { return; }
            TestTrue(TEXT("physical remove-tag action activates"), ClickDetailed(
                FSlateApplication::Get(), RemoveTagButton.ToSharedRef()).Succeeded());
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(2));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, Scenario](UWorld*)
        {
            if (NOT Scenario->UiReady) { return; }
            TestFalse(TEXT("physical remove-tag request reaches the production processor"),
                UCk_Utils_ItemTrait_Tags_UE::HasTagExact(Scenario->Item, Scenario->TestTag));
            const int64 Revision = Scenario->View->GetRevision();
            const TSharedRef<SWidget> MainBefore = Scenario->View->GetRegion(TEXT("main"));
            TestTrue(TEXT("compatible Inventories reload retains the view"),
                Scenario->View->TryReload(Scenario->Markup, Scenario->Stylesheet, TEXT("Inventories compatible")).Succeeded
                    && Scenario->View->GetRevision() > Revision);
            const int64 AcceptedRevision = Scenario->View->GetRevision();
            TestFalse(TEXT("missing item action rejects Inventories reload atomically"),
                Scenario->View->TryReload(
                    Scenario->Markup.Replace(TEXT("inventory-consume"), TEXT("inventory-missing-consume")),
                    Scenario->Stylesheet, TEXT("Inventories rejected")).Succeeded);
            TestTrue(TEXT("rejected reload preserves exact tree and revision"),
                &Scenario->View->GetRegion(TEXT("main")).Get() == &MainBefore.Get()
                    && Scenario->View->GetRevision() == AcceptedRevision);

            const auto& Records = Scenario->Authored->Get_RecordsCollection()->GetRecords();
            const TSharedPtr<SCkUiRepeat> Repeat = Scenario->View->GetRepeat(TEXT("inventory-records"));
            TSharedPtr<SWidget> MeterItem;
            TSharedPtr<SWidget> InventoryItem;
            if (Repeat.IsValid())
            {
                for (const auto& Record : Records)
                {
                    if (NOT Record.IsValid()) { continue; }
                    const FString& Key = Record->GetKey();
                    if (Key.EndsWith(TEXT("/meter"))) { MeterItem = Repeat->GetItemWidget(Key); }
                    else if (Key.Contains(TEXT("/item/"))) { InventoryItem = Repeat->GetItemWidget(Key); }
                }
            }
            Scenario->BoundInput = MeterItem.IsValid()
                ? FindInput(MeterItem.ToSharedRef(), TEXT("inventory-bound")) : nullptr;
            Scenario->ConsumeButton = InventoryItem.IsValid()
                ? FindButton(InventoryItem.ToSharedRef(), TEXT("inventory-consume")) : nullptr;
            if (NOT TestTrue(TEXT("compatible reload republishes current controls"),
                Scenario->BoundInput.IsValid() && Scenario->ConsumeButton.IsValid())) { return; }
            UCk_Utils_Inventory_UE::RecordOfInventories_Utils::Request_Disconnect(
                Scenario->Subject, Scenario->Inventory);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(2));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, Scenario](UWorld*)
        {
            auto& Slate = FSlateApplication::Get();
            if (Scenario->UiReady)
            {
                Tick(Slate);
                TestFalse(TEXT("disconnected inventory retires the authored route"), Scenario->Authored->Get_IsAvailable());
                TestFalse(TEXT("disconnected inventory disables authored requests"), Scenario->Authored->Get_CanRequest());
                Scenario->BoundBeforeHeldInput = UCk_Utils_Inventory_DataOnly_UE::Get_BoundMax(Scenario->Inventory).Get(-1);
                Scenario->StackBeforeHeldAction = UCk_Utils_ItemTrait_Stackable_UE::Get_StackCount(Scenario->Item);
                Commit(Slate, Scenario->BoundInput.ToSharedRef(), TEXT("9"));
                ClickDetailed(Slate, Scenario->ConsumeButton.ToSharedRef());
            }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(2));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, Scenario](UWorld*)
        {
            auto& Slate = FSlateApplication::Get();
            if (Scenario->UiReady)
            {
                TestTrue(TEXT("held controls cannot mutate after relationship loss"),
                    UCk_Utils_Inventory_DataOnly_UE::Get_BoundMax(Scenario->Inventory).Get(-1)
                        == Scenario->BoundBeforeHeldInput
                        && UCk_Utils_ItemTrait_Stackable_UE::Get_StackCount(Scenario->Item)
                        == Scenario->StackBeforeHeldAction);

                Scenario->Subject.Add<ck::FTag_DestroyEntity_Initiate>();
                TestFalse(TEXT("pending destruction remains unavailable"), Scenario->Authored->Get_IsAvailable());

                TSharedPtr<SCkInspector_InventoriesAuthored> DestructorAuthored;
                TWeakPtr<FCkUiView> DestructorView;
                auto DestructorInspector = MakeUnique<FCkInspector_Inventories>();
                const TSharedRef<SWidget> DestructorRendered = DestructorInspector->Build_Inspector(Scenario->Inventory);
                if (TestEqual(TEXT("Inventories destructor fixture mounts authored composition"),
                    DestructorRendered->GetTypeAsString(), FString{TEXT("SCkInspector_InventoriesAuthored")}))
                {
                    DestructorAuthored = StaticCastSharedRef<SCkInspector_InventoriesAuthored>(DestructorRendered);
                    DestructorView = DestructorAuthored->Get_View();
                    DestructorInspector.Reset();
                    TestTrue(TEXT("Inventories destructor releases retained view"), DestructorAuthored->Is_Inert()
                        && NOT DestructorAuthored->Is_Mounted() && NOT DestructorView.IsValid());
                }

                Scenario->Inspector->OnDeactivated();
                TestTrue(TEXT("Inventories deactivation releases retained view"), Scenario->Authored->Is_Inert()
                    && NOT Scenario->Authored->Get_View().IsValid());
            }
            else if (Scenario->Inspector.IsValid())
            {
                Scenario->Inspector->OnDeactivated();
            }
            if (Scenario->Window.IsValid()) { Slate.DestroyWindowImmediately(Scenario->Window.ToSharedRef()); }
            Scenario->Window.Reset();
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif
