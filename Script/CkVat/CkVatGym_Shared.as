// Language=angelscript

//============================================================================
// CK VAT GYM — shared tags, messages, collection loading
//============================================================================
//
// Content contract: unlike the Iskm gym (whose wrapper assets are AS-authored),
// a VAT collection's bake outputs are SERIALIZED editor content — the gym
// cannot author one in script. The gym loads a baked UCk_VatCollection_Data
// from a conventional path (below) and every station renders a how-to when
// it's missing or unbaked. Point the gym at any other collection at runtime
// with `Ck_GymVat_SetCollection <path>` — that is the "curated setups" hook
// (vertex vs bone mode, High vs Low precision, different meshes).
//
// One-time setup for the default path (see also the station display text):
//   1. Content browser -> /CkTests/CkVat/ -> new UCk_VatCollection_Data
//      named DA_VatCollection_Gym.
//   2. Set Skeleton + SourceMesh (e.g. SK_Mannequin + SKM_Manny_Simple) and
//      2-3 clips (e.g. MM_Idle / MF_Unarmed_Walk_Fwd / MF_Unarmed_Jog_Fwd).
//      NOTE: Vertex mode caps at 4096 verts — use Bone mode for the
//      mannequin; Vertex mode (and the new VAT normals) wants a low-poly mesh.
//   3. Click the Bake button in the details panel, save.
//
//============================================================================

namespace Ck
{
    asset VatGym_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"Gym.Vat.ClipCycle");
        GameplayTags.Add(n"Gym.Vat.Turntable");
        GameplayTags.Add(n"Gym.Vat.CrowdField");
    }
}

namespace vat_gym
{
    const FString DefaultCollectionPath = "/CkTests/CkVat/DA_VatCollection_Gym.DA_VatCollection_Gym";

    UCk_VatCollection_Data LoadCollection(FString InPath)
    {
        auto SoftRef = TSoftObjectPtr<UCk_VatCollection_Data>(FSoftObjectPath(InPath));
        return System::LoadAsset_Blocking(SoftRef);
    }

    // Multi-line how-to rendered on stations while no usable collection exists.
    // Keep each line under ~55 chars (BP_DemoDisplay does not wrap).
    FString MissingCollectionText(FString InPath, bool InFoundButUnbaked)
    {
        auto Text = InFoundButUnbaked
            ? "Collection found but NOT BAKED.\n"
            : "No baked VatCollection found.\n";
        Text = f"{Text}Path: {InPath}\n\n";
        Text = f"{Text}Setup (once):\n";
        Text = f"{Text} 1. Create a UCk_VatCollection_Data asset\n";
        Text = f"{Text}    at the path above.\n";
        Text = f"{Text} 2. Set Skeleton, SourceMesh and Clips\n";
        Text = f"{Text}    (Bone mode for the Mannequin —\n";
        Text = f"{Text}    Vertex mode caps at 4096 verts).\n";
        Text = f"{Text} 3. Click BAKE in the details panel, save.\n";
        Text = f"{Text} 4. Re-enter the gym, or run:\n";
        Text = f"{Text}    Ck_GymVat_SetCollection <path>\n";
        return Text;
    }
}

// ---------------------------------------------------------------------------
// Console -> station messages
// ---------------------------------------------------------------------------

USTRUCT()
struct FCk_Message_VatGym_SetCollection
{
    FString Path;

    FCk_Message_VatGym_SetCollection(FString InPath = "")
    {
        Path = InPath;
    }
}

USTRUCT()
struct FCk_Message_VatGym_PlayClip
{
    FName ClipName;
    float32 Rate = 1.0f;
    float32 FadeSeconds = 0.4f;
    bool Once = false;
}

USTRUCT()
struct FCk_Message_VatGym_SetRate
{
    float32 Rate = 1.0f;

    FCk_Message_VatGym_SetRate(float32 InRate = 1.0f)
    {
        Rate = InRate;
    }
}

USTRUCT()
struct FCk_Message_VatGym_Stop
{
}

USTRUCT()
struct FCk_Message_VatGym_FieldCount
{
    int32 Count = 100;

    FCk_Message_VatGym_FieldCount(int32 InCount = 100)
    {
        Count = InCount;
    }
}

USTRUCT()
struct FCk_Message_VatGym_TurnRate
{
    float32 DegreesPerSecond = 30.0f;

    FCk_Message_VatGym_TurnRate(float32 InDegreesPerSecond = 30.0f)
    {
        DegreesPerSecond = InDegreesPerSecond;
    }
}
