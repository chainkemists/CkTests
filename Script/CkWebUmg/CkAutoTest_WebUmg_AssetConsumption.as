// Language=angelscript
//
// CK WEBUMG — AUTOMATION TEST: PageAsset consumption from AngelScript
// The three-environments face of the Gate 4 emission surface: load a corpus bundle through the
// Utils BFL, then read the report and the data-ck binding surface — all from script.

class UCk_AutoTest_WebUmg_AssetConsumption : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Asset = UCk_Utils_WebUmg_UE::TryLoad_PageAssetFromJson(
            "Tools/ckwebumg-extract/corpus/golden/smoke.ckui.json");
        Assert_True(IsValid(Asset), "smoke corpus bundle must load into a PageAsset");

        Assert_True(UCk_Utils_WebUmg_UE::Get_NodeCount(Asset) > 0,
            "loaded asset must carry the node tree");

        bool Found = false;
        auto HealthBar = UCk_Utils_WebUmg_UE::Get_NamedNode(Asset, "HealthBar", Found);
        Assert_True(Found, "data-ck-name lookup must resolve HealthBar");
        Assert_True(HealthBar._CkBind == "Health",
            "data-ck-bind must survive to the asset (HealthBar binds Health)");

        Assert_True(UCk_Utils_WebUmg_UE::Get_ConversionReport(Asset).Num() == 0,
            "the smoke page is fully in-surface; its report must be empty");

        FinishSuccess();
    }
}
