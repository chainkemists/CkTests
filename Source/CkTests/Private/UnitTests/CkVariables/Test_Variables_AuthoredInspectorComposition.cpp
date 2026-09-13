#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/Validation/CkIsValid.h"
#include "CkDebuggerCommon/Styles/CkDebuggerStyle.h"
#include "CkDebuggerCommon/Widgets/SCkDebug_EntityRef.h"
#include "CkDebuggerCommon/Widgets/SCkDebug_Switch.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Fragment.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcsDebugger/Inspectors/CkInspectorWidgetBuilder.h"
#include "CkEcsDebugger/Inspectors/CkInspector_Variables.h"
#include "CkEcsDebugger/Models/CkDebuggerModel_EntitySelection.h"
#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/SCkUiRepeat.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkVariables/CkUnrealVariables_Fragment.h"
#include "CkVariables/CkUnrealVariables_Utils.h"

#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Interfaces/IPluginManager.h"
#include "Misc/AutomationTest.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Widgets/Input/SEditableTextBox.h"
#include "Widgets/SNullWidget.h"
#include "Widgets/SWindow.h"

namespace ck_tests_variables_authored
{
    constexpr auto kFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    auto FindTagged(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTag() == InTag && InRoot->GetVisibility().IsVisible()) { return InRoot; }
        FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const auto Found = FindTagged(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag);
                Found.IsValid())
            { return Found; }
        }
        return nullptr;
    }

    auto FindInput(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SEditableTextBox>
    {
        if (InRoot->GetTag() == InTag && InRoot->GetVisibility().IsVisible()
            && (InRoot->GetTypeAsString() == TEXT("SEditableTextBox")
                || InRoot->GetTypeAsString() == TEXT("SCkUiTextInputBox")))
        { return StaticCastSharedRef<SEditableTextBox>(InRoot); }
        FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const auto Found = FindInput(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag);
                Found.IsValid())
            { return Found; }
        }
        return nullptr;
    }

    auto FindSwitch(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SCkDebug_Switch>
    {
        if (InRoot->GetTag() == InTag && InRoot->GetVisibility().IsVisible()
            && InRoot->GetTypeAsString() == TEXT("SCkDebug_Switch"))
        { return StaticCastSharedRef<SCkDebug_Switch>(InRoot); }
        FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const auto Found = FindSwitch(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag);
                Found.IsValid())
            { return Found; }
        }
        return nullptr;
    }

    auto FindEntityRef(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SCkDebug_EntityRef>
    {
        if (InRoot->GetTypeAsString() == TEXT("SCkDebug_EntityRef") && InRoot->GetVisibility().IsVisible())
        { return StaticCastSharedRef<SCkDebug_EntityRef>(InRoot); }
        FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const auto Found = FindEntityRef(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)));
                Found.IsValid())
            { return Found; }
        }
        return nullptr;
    }

    auto Tick(FSlateApplication& InSlate) -> void
    { InSlate.PumpMessages(); InSlate.Tick(); InSlate.Tick(); }

    auto Commit(
        FSlateApplication& InSlate,
        const TSharedRef<SEditableTextBox>& InInput,
        const FString& InValue) -> bool
    {
        InSlate.SetUserFocus(0, InInput, EFocusCause::SetDirectly);
        Tick(InSlate);
        InInput->SetText(FText::FromString(InValue));
        if (NOT InSlate.ProcessKeyDownEvent(FKeyEvent{EKeys::Enter, FModifierKeysState{}, 0, false, 0, 0}))
        { return false; }
        Tick(InSlate);
        return true;
    }

    auto Toggle(const TSharedRef<SCkDebug_Switch>& InSwitch) -> void
    {
        const FGeometry Geometry = FGeometry::MakeRoot(FVector2D{30.0f, 17.0f}, FSlateLayoutTransform{});
        const TSet<FKey> PressedButtons{EKeys::LeftMouseButton};
        const FPointerEvent Click{0, FVector2D{5.0f, 5.0f}, FVector2D{5.0f, 5.0f}, PressedButtons,
            EKeys::LeftMouseButton, 0.0f, FModifierKeysState{}};
        InSwitch->OnMouseButtonDown(Geometry, Click);
    }

    auto Follow(const TSharedRef<SCkDebug_EntityRef>& InEntityRef) -> bool
    {
        const FGeometry Geometry = FGeometry::MakeRoot(FVector2D{120.0f, 20.0f}, FSlateLayoutTransform{});
        const TSet<FKey> PressedButtons{EKeys::LeftMouseButton};
        const FPointerEvent Click{0, FVector2D{5.0f, 5.0f}, FVector2D{5.0f, 5.0f}, PressedButtons,
            EKeys::LeftMouseButton, 0.0f, FModifierKeysState{}};
        return InEntityRef->OnMouseButtonDown(Geometry, Click).IsEventHandled();
    }

    auto Field(
        const TSharedPtr<FCkUiCollection>& InCollection,
        const FString& InKey,
        const FString& InField) -> const FCkUiFieldValue*
    {
        const auto Record = InCollection.IsValid() ? InCollection->FindRecord(InKey) : nullptr;
        return Record.IsValid() ? Record->FindField(InField) : nullptr;
    }

    struct FScenario
    {
        FCk_Handle Owner;
        FCk_Handle Entity;
        FCk_Handle Target;
        FCk_Handle DestructorEntity;
        TUniquePtr<FCkInspector_Variables> Inspector;
        TSharedPtr<FCkDebuggerModel_EntitySelection> Selection;
        FCk_Handle Navigated;
        TSharedPtr<SCkInspector_VariablesAuthored> Authored;
        TSharedPtr<FCkUiView> View;
        TSharedPtr<FCkUiCollection> Records;
        TSharedPtr<SCkDebug_Switch> BoolSwitch;
        TSharedPtr<SEditableTextBox> IntegerInput;
        TSharedPtr<SEditableTextBox> NumberInput;
        TSharedPtr<SEditableTextBox> StringInput;
        TSharedPtr<SEditableTextBox> AxisInput;
        TSharedPtr<SCkDebug_EntityRef> EntityRef;
        TSharedPtr<SWindow> Window;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Variables_AuthoredInspectorComposition,
    "Ck.UiAuthoring.EcsDebugger.VariablesInspector.AuthoredComposition",
    ck_tests_variables_authored::kFlags)

bool FCkTest_Variables_AuthoredInspectorComposition::RunTest(const FString&)
{
    using namespace ck_tests_variables_authored;
    const auto Scenario = MakeShared<FScenario>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, Scenario](UWorld* InWorld)
        {
            Scenario->Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld);
            Scenario->Entity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Scenario->Owner);
            Scenario->Target = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Scenario->Owner);
            Scenario->DestructorEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Scenario->Owner);
            if (NOT TestTrue(TEXT("fixture creates live variable entities"),
                ck::IsValid(Scenario->Entity) && ck::IsValid(Scenario->Target)
                    && ck::IsValid(Scenario->DestructorEntity)))
            { return; }

            UCk_Utils_Variables_Bool_UE::Set_ByName(Scenario->Entity, TEXT("Enabled"), true);
            UCk_Utils_Variables_Int32_UE::Set_ByName(Scenario->Entity, TEXT("Count"), 7);
            UCk_Utils_Variables_Float_UE::Set_ByName(Scenario->Entity, TEXT("Speed"), 1.5f);
            UCk_Utils_Variables_String_UE::Set_ByName(Scenario->Entity, TEXT("Label"), TEXT("Alpha"));
            UCk_Utils_Variables_Text_UE::Set_ByName(
                Scenario->Entity, TEXT("Localized"), FText::FromString(TEXT("Read only")));
            UCk_Utils_Variables_Vector_UE::Set_ByName(
                Scenario->Entity, TEXT("Direction"), FVector{1.0, 2.0, 3.0});
            UCk_Utils_Variables_Entity_UE::Set_ByName(
                Scenario->Entity, TEXT("Target"), Scenario->Target);
            UCk_Utils_Variables_Bool_UE::Set_ByName(
                Scenario->DestructorEntity, TEXT("Alive"), true);

            Scenario->Inspector = MakeUnique<FCkInspector_Variables>();
            Scenario->Selection = MakeShared<FCkDebuggerModel_EntitySelection>();
            Scenario->Selection->OnSelectionChanged.AddLambda(
                [RawScenario = &Scenario.Get()](const TArray<FCk_Handle>& InSelection)
                {
                    RawScenario->Navigated = InSelection.IsEmpty() ? FCk_Handle{} : InSelection[0];
                });
            Scenario->Inspector->Set_SelectionModel(Scenario->Selection);

            auto NativeRows = TMap<FString, FString>{};
            {
                const FCkInspector_RowCaptureScope Capture{};
                Scenario->Inspector->Build_Inspector(Scenario->Entity);
                NativeRows = Capture.Get_Rows();
            }
            TestTrue(TEXT("native capture preserves every seeded variable label"),
                NativeRows.Contains(TEXT("Enabled")) && NativeRows.Contains(TEXT("Count"))
                    && NativeRows.Contains(TEXT("Speed")) && NativeRows.Contains(TEXT("Label"))
                    && NativeRows.Contains(TEXT("Localized")) && NativeRows.Contains(TEXT("Direction"))
                    && NativeRows.Contains(TEXT("Target")));

            const TSet<FString> DiffLabels{TEXT("Count")};
            TSharedRef<SWidget> Rendered = SNullWidget::NullWidget;
            {
                const FCkInspector_DiffMarkScope DiffScope{&DiffLabels};
                Rendered = Scenario->Inspector->Build_Inspector(Scenario->Entity);
            }
            if (NOT TestEqual(TEXT("Variables mounts the authored inspector"),
                Rendered->GetTypeAsString(), FString{TEXT("SCkInspector_VariablesAuthored")}))
            {
                AddError(Scenario->Inspector->Get_LastAuthoredLoadError());
                return;
            }
            Scenario->Authored = StaticCastSharedRef<SCkInspector_VariablesAuthored>(Rendered);
            Scenario->View = Scenario->Authored->Get_View();
            Scenario->Records = Scenario->Authored->Get_RecordsCollection();
            if (NOT TestTrue(TEXT("authored Variables owns a mounted view and record collection"),
                Scenario->Authored->Get_IsAvailable() && Scenario->View.IsValid()
                    && Scenario->Records.IsValid() && Scenario->Records->GetRecords().Num() == 7))
            { return; }

            const FCkUiFieldValue* Bool = Field(Scenario->Records, TEXT("Bool/Enabled"), TEXT("bool-value"));
            const FCkUiFieldValue* Count = Field(Scenario->Records, TEXT("Int32/Count"), TEXT("integer-value"));
            const FCkUiFieldValue* Speed = Field(Scenario->Records, TEXT("Float/Speed"), TEXT("number-value"));
            const FCkUiFieldValue* Label = Field(Scenario->Records, TEXT("String/Label"), TEXT("value-text"));
            const FCkUiFieldValue* Localized = Field(Scenario->Records, TEXT("Text/Localized"), TEXT("value-text"));
            const FCkUiFieldValue* Axis = Field(Scenario->Records, TEXT("Vector/Direction"), TEXT("axis-0"));
            const FCkUiFieldValue* Diff = Field(Scenario->Records, TEXT("Int32/Count"), TEXT("diff-color"));
            TestTrue(TEXT("authored records preserve typed scalar, text, vector and native diff projection"),
                Bool != nullptr && Bool->Kind == ECkUiFieldKind::Bool && Bool->Bool
                    && Count != nullptr && Count->Kind == ECkUiFieldKind::Integer && Count->Integer == 7
                    && Speed != nullptr && Speed->Kind == ECkUiFieldKind::Number && FMath::IsNearlyEqual(Speed->Number, 1.5f)
                    && Label != nullptr && Label->Text.ToString() == TEXT("Alpha")
                    && Localized != nullptr && Localized->Text.ToString() == TEXT("Read only")
                    && Axis != nullptr && FMath::IsNearlyEqual(Axis->Number, 1.0f)
                    && Diff != nullptr && Diff->Color == CkStyle::Accent());

            auto& Slate = FSlateApplication::Get();
            Scenario->Window = SNew(SWindow).ClientSize(FVector2D{900.0f, 700.0f})[Rendered];
            Slate.AddWindow(Scenario->Window.ToSharedRef(), true);
            Tick(Slate);
            Rendered->SlatePrepass(1.0f);
            const TSharedPtr<SCkUiRepeat> Repeat = Scenario->View->GetRepeat(TEXT("variables-records"));
            const TSharedPtr<SWidget> BoolItem = Repeat.IsValid() ? Repeat->GetItemWidget(TEXT("Bool/Enabled")) : nullptr;
            const TSharedPtr<SWidget> IntegerItem = Repeat.IsValid() ? Repeat->GetItemWidget(TEXT("Int32/Count")) : nullptr;
            const TSharedPtr<SWidget> NumberItem = Repeat.IsValid() ? Repeat->GetItemWidget(TEXT("Float/Speed")) : nullptr;
            const TSharedPtr<SWidget> StringItem = Repeat.IsValid() ? Repeat->GetItemWidget(TEXT("String/Label")) : nullptr;
            const TSharedPtr<SWidget> VectorItem = Repeat.IsValid() ? Repeat->GetItemWidget(TEXT("Vector/Direction")) : nullptr;
            const TSharedPtr<SWidget> EntityItem = Repeat.IsValid() ? Repeat->GetItemWidget(TEXT("Entity/Target")) : nullptr;
            Scenario->BoolSwitch = BoolItem.IsValid() ? FindSwitch(BoolItem.ToSharedRef(), TEXT("variable-bool")) : nullptr;
            Scenario->IntegerInput = IntegerItem.IsValid() ? FindInput(IntegerItem.ToSharedRef(), TEXT("variable-integer")) : nullptr;
            Scenario->NumberInput = NumberItem.IsValid() ? FindInput(NumberItem.ToSharedRef(), TEXT("variable-number")) : nullptr;
            Scenario->StringInput = StringItem.IsValid() ? FindInput(StringItem.ToSharedRef(), TEXT("variable-text-input")) : nullptr;
            Scenario->AxisInput = VectorItem.IsValid() ? FindInput(VectorItem.ToSharedRef(), TEXT("variable-axis-0")) : nullptr;
            const auto EntityHost = EntityItem.IsValid() ? FindTagged(EntityItem.ToSharedRef(), TEXT("variable-entity")) : nullptr;
            Scenario->EntityRef = EntityHost.IsValid() ? FindEntityRef(EntityHost.ToSharedRef()) : nullptr;
            TestTrue(TEXT("physical Bool switch materializes"), Scenario->BoolSwitch.IsValid());
            TestTrue(TEXT("physical integer input materializes"), Scenario->IntegerInput.IsValid());
            TestTrue(TEXT("physical number input materializes"), Scenario->NumberInput.IsValid());
            TestTrue(TEXT("physical String input materializes"), Scenario->StringInput.IsValid());
            TestTrue(TEXT("physical vector-axis input materializes"), Scenario->AxisInput.IsValid());
            TestTrue(TEXT("physical Entity reference action materializes"), Scenario->EntityRef.IsValid());
            if (NOT TestTrue(TEXT("authored repeat materializes every representative physical control"),
                Scenario->BoolSwitch.IsValid() && Scenario->IntegerInput.IsValid()
                    && Scenario->NumberInput.IsValid() && Scenario->StringInput.IsValid()
                    && Scenario->AxisInput.IsValid() && Scenario->EntityRef.IsValid()))
            { return; }

            Toggle(Scenario->BoolSwitch.ToSharedRef());
            TestFalse(TEXT("physical Bool switch dispatches through its retained item binding"),
                Scenario->Entity.Get<ck::FFragment_Variable_Bool>().Get_Variables().FindChecked(TEXT("Enabled")));
            TestTrue(TEXT("physical integer input commits through its retained item binding"),
                Commit(Slate, Scenario->IntegerInput.ToSharedRef(), TEXT("42")));
            TestEqual(TEXT("integer commit mutates its typed target"),
                Scenario->Entity.Get<ck::FFragment_Variable_Int32>().Get_Variables().FindChecked(TEXT("Count")), 42);
            TestTrue(TEXT("physical number input commits through its retained item binding"),
                Commit(Slate, Scenario->NumberInput.ToSharedRef(), TEXT("3.25")));
            TestTrue(TEXT("number commit mutates its typed target"),
                FMath::IsNearlyEqual(Scenario->Entity.Get<ck::FFragment_Variable_Float>().Get_Variables().FindChecked(TEXT("Speed")), 3.25f));
            TestTrue(TEXT("physical String input commits through its retained item binding"),
                Commit(Slate, Scenario->StringInput.ToSharedRef(), TEXT("Beta")));
            TestEqual(TEXT("String commit mutates its typed target"),
                Scenario->Entity.Get<ck::FFragment_Variable_String>().Get_Variables().FindChecked(TEXT("Label")), FString{TEXT("Beta")});
            TestTrue(TEXT("physical vector-axis input commits through its retained item binding"),
                Commit(Slate, Scenario->AxisInput.ToSharedRef(), TEXT("9.5")));
            TestTrue(TEXT("vector-axis commit mutates only its typed target"),
                FMath::IsNearlyEqual(Scenario->Entity.Get<ck::FFragment_Variable_Vector>().Get_Variables().FindChecked(TEXT("Direction")).X, 9.5));
            TestTrue(TEXT("physical Entity reference dispatches navigation"), Follow(Scenario->EntityRef.ToSharedRef()));
            TestTrue(TEXT("Entity navigation mutates only the debugger selection route"),
                Scenario->Navigated == Scenario->Target);

            const TSharedPtr<IPlugin> Plugin = IPluginManager::Get().FindPlugin(TEXT("CkDebugger"));
            auto Markup = FString{}; auto Stylesheet = FString{};
            const FString Root = Plugin.IsValid() ? FPaths::Combine(Plugin->GetBaseDir(), TEXT("Resources/UI")) : FString{};
            if (NOT TestTrue(TEXT("installed Variables authored resources are readable"),
                Plugin.IsValid()
                    && FFileHelper::LoadFileToString(Markup, *FPaths::Combine(Root, TEXT("EcsInspectorVariables.ui.html")))
                    && FFileHelper::LoadFileToString(Stylesheet, *FPaths::Combine(Root, TEXT("EcsInspectorVariables.ui.css")))))
            { return; }
            TestTrue(TEXT("HTML owns the complete repeated variable layout without native ports"),
                Markup.Contains(TEXT("id=\"variables-records\""))
                    && Markup.Contains(TEXT("item-changed=\"variable-bool-changed\""))
                    && Markup.Contains(TEXT("item-committed=\"variable-axis-2-committed\""))
                    && Markup.Contains(TEXT("id=\"variable-entity\""))
                    && NOT Markup.Contains(TEXT("<native")));

            const int64 Revision = Scenario->View->GetRevision();
            const TSharedRef<SWidget> MainBefore = Scenario->View->GetRegion(TEXT("main"));
            TestTrue(TEXT("compatible Variables reload advances the retained view"),
                Scenario->View->TryReload(Markup, Stylesheet, TEXT("Variables compatible candidate")).Succeeded
                    && Scenario->View->GetRevision() > Revision);
            const int64 CompatibleRevision = Scenario->View->GetRevision();
            TestFalse(TEXT("missing Variables item binding is rejected atomically"),
                Scenario->View->TryReload(
                    Markup.Replace(TEXT("variable-bool-changed"), TEXT("variable-missing-bool")),
                    Stylesheet, TEXT("Variables rejected candidate")).Succeeded);
            TestTrue(TEXT("rejected Variables reload preserves its exact tree and revision"),
                &Scenario->View->GetRegion(TEXT("main")).Get() == &MainBefore.Get()
                    && Scenario->View->GetRevision() == CompatibleRevision);

            const int32 BeforeTopology = Scenario->Records->GetRecords().Num();
            UCk_Utils_Variables_Bool_UE::Set_ByName(Scenario->Entity, TEXT("Later"), true);
            Scenario->Authored->Tick(
                FGeometry::MakeRoot(FVector2D{900.0f, 700.0f}, FSlateLayoutTransform{}), 0.0, 0.0f);
            TestTrue(TEXT("live variable topology reconciles into the retained repeat"),
                Scenario->Records->GetRecords().Num() == BeforeTopology + 1
                    && Scenario->Records->FindRecord(TEXT("Bool/Later")).IsValid());

            Scenario->Entity.Try_Remove<ck::FFragment_Variable_String>();
            Scenario->Authored->Tick(
                FGeometry::MakeRoot(FVector2D{900.0f, 700.0f}, FSlateLayoutTransform{}), 0.0, 0.0f);
            Commit(Slate, Scenario->StringInput.ToSharedRef(), TEXT("MustNotReturn"));
            TestTrue(TEXT("removed variable fragments retire their records and stale editors fail closed"),
                NOT Scenario->Entity.Has<ck::FFragment_Variable_String>()
                    && NOT Scenario->Records->FindRecord(TEXT("String/Label")).IsValid());

            TSharedPtr<SCkInspector_VariablesAuthored> DestructorAuthored;
            TWeakPtr<FCkUiView> DestructorView;
            {
                auto DestructorInspector = MakeUnique<FCkInspector_Variables>();
                DestructorAuthored = StaticCastSharedRef<SCkInspector_VariablesAuthored>(
                    DestructorInspector->Build_Inspector(Scenario->DestructorEntity));
                DestructorView = DestructorAuthored->Get_View();
            }
            TestTrue(TEXT("Variables inspector destruction releases its retained authored view"),
                DestructorAuthored.IsValid() && DestructorAuthored->Is_Inert()
                    && NOT DestructorAuthored->Is_Mounted() && NOT DestructorView.IsValid());

            Scenario->Entity.Add<ck::FTag_DestroyEntity_Initiate>();
            Toggle(Scenario->BoolSwitch.ToSharedRef());
            TestFalse(TEXT("pending destruction disables Variables inspection"),
                Scenario->Inspector->CanInspect(Scenario->Entity));
            TestFalse(TEXT("pending destruction hides the authored Variables surface"),
                Scenario->Authored->Get_IsAvailable());
            TestFalse(TEXT("pending destruction leaves the held Bool control inert"),
                Scenario->Entity.Get<ck::FFragment_Variable_Bool>().Get_Variables().FindChecked(TEXT("Enabled")));

            Scenario->Inspector->OnDeactivated();
            TestTrue(TEXT("Variables deactivation releases every retained view and collection"),
                Scenario->Authored->Is_Inert() && NOT Scenario->Authored->Is_Mounted()
                    && NOT Scenario->Authored->Get_View().IsValid()
                    && NOT Scenario->Authored->Get_RecordsCollection().IsValid());
            if (Scenario->Window.IsValid())
            {
                Slate.DestroyWindowImmediately(Scenario->Window.ToSharedRef());
                Scenario->Window.Reset();
            }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif
