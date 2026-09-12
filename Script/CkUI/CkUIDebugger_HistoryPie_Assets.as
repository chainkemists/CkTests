// Language=angelscript

// Literal assets keep the CkUIDebugger PIE fixture source-controlled without
// requiring a separately authored GameplayTag asset, DataAsset, or Widget BP.
namespace ck_tests_ui_debugger_history_pie
{
    asset CkTests_UIDebugger_HistoryPie_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"CkTests.UI.Layer.CkUIDebugger.HistoryPie");
        GameplayTags.Add(n"CkTests.UI.Layer.CkUIDebugger.HistoryPie.Secondary");
    }

    // Deliberately has no designer widget tree. The PIE test pushes this concrete
    // script class to verify the production layout path accepts a non-WBP widget.
    class UCkTests_UIDebugger_HistoryPie_Widget : UCk_ActivatableWidget_UE
    {
    }

    asset CkTests_UIDebugger_HistoryPie_Layout of UCk_UI_LayoutConfigAsset_UE
    {
        FCk_UI_LayerConfig HistoryLayer;
        // Register immediately as well as publishing the source-owned tag asset above: the
        // layout literal initializes in the same startup pass and needs a valid tag value now.
        HistoryLayer._LayerTag = utils_gameplay_tag::ResolveGameplayTag(
            n"CkTests.UI.Layer.CkUIDebugger.HistoryPie", "CkUIDebugger authored PIE fixture");
        HistoryLayer._LayerWidgetClass = UCk_UI_LayerStack_UE;
        HistoryLayer.Set_InputMode(ECk_UI_InputMode::GameAndUI);
        HistoryLayer.Set_TransitionDuration(FCk_Time(0.0));

        _LayerConfigs.Add(HistoryLayer);

        FCk_UI_LayerConfig SecondaryLayer;
        SecondaryLayer._LayerTag = utils_gameplay_tag::ResolveGameplayTag(
            n"CkTests.UI.Layer.CkUIDebugger.HistoryPie.Secondary", "CkUIDebugger authored PIE fixture");
        SecondaryLayer._LayerWidgetClass = UCk_UI_LayerStack_UE;
        SecondaryLayer.Set_Priority(20);
        SecondaryLayer.Set_InputMode(ECk_UI_InputMode::UIOnly);
        SecondaryLayer.Set_TransitionDuration(FCk_Time(0.0));

        _LayerConfigs.Add(SecondaryLayer);
    }
}
