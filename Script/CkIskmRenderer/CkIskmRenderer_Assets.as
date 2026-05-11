// Language=angelscript

//============================================================================
// CK ISKM RENDERER GYM — wrapper assets
//============================================================================
//
// AS-authored UDataAssets that wire migrated UE Mannequin content (loaded via
// the `assets::` namespace from /CkTests/Script/Generated/CkTestsAssets.as)
// into the two PDA shapes the IskmRenderer expects.
//
// Why AS-authored: editor-binary `.uasset` diffs are unreviewable, and field
// changes here (new sequences, submeshes, anim instance class) live in source
// control as text.
//
// Engine-init safety: `assets::load::*` ensures-fail when called before
// UTypedElementRegistry is ready (e.g. during AS __InitDefaults). The
// CkFoundation `UCk_DeferredAssetInit_UE` system re-runs each literal asset's
// `__Init_<Name>` chain on `OnFEngineLoopInitComplete` (and again on
// AS hot-reload), so the assets::load:: calls below get a real value
// once the engine is safe — even though the first pass returns null.
//
// Cross-file consumers reach the wrappers via `iskm_assets::RendererData_Demo()`
// / `iskm_assets::AnimCollection_Demo()` — bare `Asset_Foo` symbols are NOT
// visible across `.as` files (mirrors the `inv_gym_items::Potion()` pattern
// in CkInventoryGym_Assets.as).
//
//============================================================================

asset Asset_AnimCollection_Demo of UCk_IskmAnimCollection_Data
{
    _Skeleton = assets::load::SK_Mannequin();
    _DefaultMesh = assets::load::SKM_Manny_Simple();

    // SequenceDef has no CK_DEFINE_CONSTRUCTORS — populate via local then Add.
    FCk_IskmAnimCollection_SequenceDef IdleDef;
    IdleDef._Sequence = assets::load::MM_Idle();
    IdleDef._Name = n"Idle";
    _Sequences.Add(IdleDef);

    FCk_IskmAnimCollection_SequenceDef JumpDef;
    JumpDef._Sequence = assets::load::MM_Jump();
    JumpDef._Name = n"Jump";
    _Sequences.Add(JumpDef);

    FCk_IskmAnimCollection_SequenceDef WalkDef;
    WalkDef._Sequence = assets::load::MF_Unarmed_Walk_Fwd();
    WalkDef._Name = n"Walk_Fwd";
    _Sequences.Add(WalkDef);

    FCk_IskmAnimCollection_SequenceDef JogDef;
    JogDef._Sequence = assets::load::MF_Unarmed_Jog_Fwd();
    JogDef._Name = n"Jog_Fwd";
    _Sequences.Add(JogDef);
}

asset Asset_RendererData_Demo of UCk_IskmRenderer_Data
{
    _AnimCollection = Asset_AnimCollection_Demo;

    // _DefaultAnimInstanceClass intentionally unset so proxies fall back to
    // UCk_IskmNotify_AnimInstance (Sequence mode), which:
    //   1. Lets tests' Request_PlayAnimation / Request_PlayMontage work
    //      without an explicit Request_SetAnimInstanceClass(NullClass) flip.
    //   2. Avoids the framework warning "AnimInstance class [X] does NOT
    //      derive from UCk_IskmNotify_AnimInstance" — ABP_Unarmed is the
    //      stock UE third-person AnimBP, not Ck-derived. The AutoTest
    //      harness escalates that warning to Error → all wrapper-using
    //      tests fail.
    // Gym stations that want idle animation opt INTO ABP_Unarmed at
    // construction via Request_SetAnimInstanceClass(assets::load::ABP_Unarmed_Class()).

    // OutfitSwap station + Q3 OutfitAttach test require a "Hat" entry.
    FCk_IskmRenderer_MeshDesc HatDesc;
    HatDesc._Name = n"Hat";
    HatDesc._Mesh = assets::load::SKM_Manny_Simple();
    _Submeshes.Add(HatDesc);

    // CustomData station + Q5 CustomDataSuccess test require slot 0 valid.
    _NumCustomDataFloat = 1;
}

//============================================================================
// ACCESSORS — bare `Asset_Foo` symbols aren't visible across files. Cross-file
// consumers reach the wrappers via these namespaced functions.
//============================================================================

namespace iskm_assets
{
    UCk_IskmAnimCollection_Data AnimCollection_Demo() { return Asset_AnimCollection_Demo; }
    UCk_IskmRenderer_Data       RendererData_Demo()   { return Asset_RendererData_Demo;   }
}
