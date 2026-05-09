// Language=angelscript

//============================================================================
// CK ISKM RENDERER GYM — shared assets
//============================================================================
//
// Tags + asset stamps used across the IskmRenderer gym stations.
//
// The asset stamps below are intentionally empty-body — they declare the
// asset shape so the engineer can find them in the Content Browser and
// populate the fields manually:
//
//   IskmRenderer_DemoAnimCollectionData : UCk_IskmAnimCollection_Data
//     - Skeleton:    set to a real USkeleton (e.g. UE Mannequin)
//     - DefaultMesh: set to a real USkeletalMesh
//     - Sequences:   add 2-3 entries (Idle, Walk, Wave) with valid UAnimSequenceBase
//
//   IskmRenderer_DemoRendererData : UCk_IskmRenderer_Data
//     - AnimCollection: set to IskmRenderer_DemoAnimCollectionData
//     - Submeshes: 3+ entries, each with Name + Mesh (e.g. Hat / Jacket / Body)
//     - NumCustomDataFloat: 4 (Tint.r, Tint.g, Tint.b, FadeAlpha)
//     - DefaultAnimInstanceClass: leave empty for sequence mode
//
// The gym stations will silently no-op if these fields are unauthored —
// they early-return on null AnimCollection / null Sequences. Authoring the
// content turns the visual demo on.
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

    asset IskmRenderer_DemoAnimCollectionData of UCk_IskmAnimCollection_Data
    {
        // Engineer fills Skeleton, DefaultMesh, Sequences in the editor.
    }

    asset IskmRenderer_DemoRendererData of UCk_IskmRenderer_Data
    {
        // Engineer fills AnimCollection (point at IskmRenderer_DemoAnimCollectionData),
        // Submeshes, NumCustomDataFloat in the editor.
    }
}
