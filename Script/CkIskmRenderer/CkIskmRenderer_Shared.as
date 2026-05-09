// Language=angelscript

//============================================================================
// CK ISKM RENDERER GYM — shared tags
//============================================================================
//
// Tags used by the IskmRenderer gym stations. The actual demo content lives
// at /CkTests/CkIskmRenderer/Demo/ — the gym stations and Phase Q tests load
// it via utils_i_o::LoadAssetByName, with skip-on-missing-content semantics.
//
// Required content (engineer authors in editor + populates fields):
//   /CkTests/CkIskmRenderer/Demo/RendererData_Demo  (UCk_IskmRenderer_Data)
//     -> _AnimCollection: ref to AnimCollection_Demo (below)
//     -> _Submeshes: at least one entry with Name "Hat"
//     -> _NumCustomDataFloat: >= 1 for the CustomData station/test
//   /CkTests/CkIskmRenderer/Demo/AnimCollection_Demo  (UCk_IskmAnimCollection_Data)
//     -> _Skeleton, _DefaultMesh, _Sequences populated against migrated
//        UE Mannequin assets
//   /CkTests/CkIskmRenderer/Anim/A_NonLoopTest  (UAnimSequence, non-looping)
//     -> for Phase Q1 AnimationFinishes test
//   /CkTests/CkIskmRenderer/Anim/AM_NotifyTest  (UAnimMontage with >=1 notify)
//     -> for Phase Q2 MontageNotify test, and the gym's MontageBurst station
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
    }
}
