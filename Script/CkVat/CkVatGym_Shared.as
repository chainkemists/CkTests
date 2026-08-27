// Language=angelscript

//============================================================================
// CK VAT GYM - shared tags, messages, collection resolution
//============================================================================
//
// Content contract: ZERO setup by default. Stations start on the "AUTO"
// sentinel path, which builds a Bone-mode Mannequin collection at PIE start
// via UCkVat_BakerSubsystem::CreateAndBake_TransientCollection - the bake
// runs in memory (nothing saved to disk) and re-runs each session.
//
// `Ck_GymVat_SetCollection <path>` swaps any BAKED on-disk collection into
// every station - the "curated setups" hook (Vertex mode + low-poly mesh for
// the normals check, High vs Low precision, different meshes).
// `Ck_GymVat_SetCollection AUTO` returns to the self-baked default.
//
// NOTE: the default is Bone mode because the Mannequin exceeds Vertex mode's
// 4096-vert cap; the Turntable normals check needs a Vertex-mode collection
// on a low-poly mesh, supplied via SetCollection.
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
    const FString DefaultCollectionPath = "AUTO";

    UCk_VatCollection_Data LoadCollection(FString InPath)
    {
        auto SoftRef = TSoftObjectPtr<UCk_VatCollection_Data>(FSoftObjectPath(InPath));
        return System::LoadAsset_Blocking(SoftRef);
    }

#if EDITOR
    // The zero-setup default: a Bone-mode Mannequin collection baked in memory at PIE start
    // (transient bake - nothing saved to disk). Returns nullptr if the mannequin content or the
    // baker subsystem is unavailable; callers fall back to the missing-collection display.
    // InWeightStorage: the Turntable station bakes WeightTexture so both per-vertex carriers
    // render side by side in the gym (ClipCycle/CrowdField stay MeshChannels).
    UCk_VatCollection_Data CreateDefaultTransientCollection(ECk_Vat_BoneWeightStorage InWeightStorage)
    {
        auto Skeleton = assets::load::SK_Mannequin();
        auto Mesh = assets::load::SKM_Manny_Simple();
        if (ck::Is_NOT_Valid(Skeleton) || ck::Is_NOT_Valid(Mesh))
        { return nullptr; }

        auto Clips = TArray<FCk_VatCollection_ClipDef>();
        auto Idle = assets::load::MM_Idle();
        auto Walk = assets::load::MF_Unarmed_Walk_Fwd();
        auto Jog = assets::load::MF_Unarmed_Jog_Fwd();
        if (ck::IsValid(Idle)) { Clips.Add(FCk_VatCollection_ClipDef(Idle, n"Idle")); }
        if (ck::IsValid(Walk)) { Clips.Add(FCk_VatCollection_ClipDef(Walk, n"Walk")); }
        if (ck::IsValid(Jog))  { Clips.Add(FCk_VatCollection_ClipDef(Jog, n"Jog")); }
        if (Clips.Num() == 0)
        { return nullptr; }

        auto Baker = Cast<UCkVat_BakerSubsystem>(EditorSubsystem::GetEditorSubsystem(UCkVat_BakerSubsystem));
        if (ck::Is_NOT_Valid(Baker))
        { return nullptr; }

        // (Vertex-mode bisection attempted 2026-07-10: SKM_Manny_Simple has 48705 source verts
        // over the 4096 Vertex cap at LOD0. Bone stays default; Vertex verification wants a higher
        // _SourceLOD or a low-poly mesh via Ck_GymVat_SetCollection.)
        return Baker.CreateAndBake_TransientCollection(Skeleton, Mesh, Clips,
            30, ECk_Vat_BakeMode::Bone, ECk_Vat_Precision::High, InWeightStorage);
    }
#endif

    // Path -> baked collection. "AUTO" = the self-baked transient default (editor only).
    UCk_VatCollection_Data ResolveCollection(FString InPath, ECk_Vat_BoneWeightStorage InAutoWeightStorage = ECk_Vat_BoneWeightStorage::MeshChannels)
    {
        if (InPath == DefaultCollectionPath)
        {
#if EDITOR
            return CreateDefaultTransientCollection(InAutoWeightStorage);
#else
            return nullptr;
#endif
        }
        return LoadCollection(InPath);
    }

    // Rendered on stations when no usable collection resolved.
    // Keep each line under ~55 chars (BP_DemoDisplay does not wrap).
    FString MissingCollectionText(FString InPath, bool InFoundButUnbaked)
    {
        if (InPath == DefaultCollectionPath)
        {
            auto Text = FString("Self-bake FAILED (check the log).\n");
            Text = f"{Text}Mannequin content or the baker\n";
            Text = f"{Text}subsystem unavailable?\n\n";
            Text = f"{Text}Or point at a baked collection:\n";
            Text = f"{Text}Ck_GymVat_SetCollection <path>\n";
            return Text;
        }

        auto Text = InFoundButUnbaked
            ? "Collection found but NOT BAKED.\n"
            : "No baked VatCollection found.\n";
        Text = f"{Text}Path: {InPath}\n\n";
        Text = f"{Text}Bake it: open the asset, click BAKE\n";
        Text = f"{Text}in the details panel, save. Or return\n";
        Text = f"{Text}to the self-baked default:\n";
        Text = f"{Text}Ck_GymVat_SetCollection AUTO\n";
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
