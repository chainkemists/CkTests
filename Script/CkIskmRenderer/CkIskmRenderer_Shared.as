// Language=angelscript

//============================================================================
// CK ISKM RENDERER GYM — shared tags
//============================================================================
//
// Tags used by the IskmRenderer gym stations. The wrapper assets are
// AS-authored in CkIskmRenderer_Assets.as (Asset_RendererData_Demo,
// Asset_AnimCollection_Demo); raw UE Mannequin content lives under
// /CkTests/Characters/Mannequins/ and is surfaced via the generated
// `assets::` namespace (see /CkTests/Script/Generated/CkTestsAssets.as).
// The single editor-authored artifact is AM_NotifyTest (UAnimMontage
// with >=1 notify), pulled by MontageNotify test + MontageBurst station
// via assets::load::AM_NotifyTest().
//
//============================================================================

namespace Ck
{
    asset IskmRendererGym_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"Gym.Iskm.SpawnArmy");
        GameplayTags.Add(n"Gym.Iskm.OutfitSwap");
        GameplayTags.Add(n"Gym.Iskm.MontageBurst");
        GameplayTags.Add(n"Gym.Iskm.RagdollDemo");
        GameplayTags.Add(n"Gym.Iskm.CustomData");
        GameplayTags.Add(n"Gym.Iskm.TransitionCycle");
        GameplayTags.Add(n"Gym.Iskm.AnimBPDemo");
    }
}
