// Language=angelscript

//============================================================================
// CK USF OUTLINE GYM/TESTS - shared ISM renderer data
//============================================================================
//
// The entity-outline gym stations and autotests render IsmProxy entities through a TRANSIENT
// renderer (engine cube + a generated CkUsf look master as the slot-0 override). Generated
// surface looks bake 'bUsedWithInstancedStaticMeshes' at generation time (CkUsf_Generator), so
// this dodges the usage-flag ensure that engine materials (WorldGridMaterial, AnimSharing*)
// trip on first ISM setup. Everything loads at call time - not asset-literal init - so headless
// runs are safe (the /Engine registry scan hasn't finished when literals initialize).
//============================================================================

namespace usf_outline_assets
{
    UCk_IsmRenderer_Data EntityRenderer(FCk_Handle InHandle)
    {
        auto Mesh = Cast<UStaticMesh>(LoadObject(nullptr, "/Engine/BasicShapes/Cube.Cube"));
        auto LookMaterial = Cast<UMaterialInterface>(LoadObject(nullptr,
            "/CkFoundation/CkUsf/GeneratedLooks/M_CkUsf_Look_LitMetal.M_CkUsf_Look_LitMetal"));
        auto World = utils_entity_lifetime::Get_WorldForEntity(InHandle);

        if (!ck::IsValid(Mesh) || !ck::IsValid(LookMaterial) || !ck::IsValid(World))
        { return nullptr; }

        auto Overrides = TArray<FCk_MeshMaterialOverride>();
        Overrides.Add(FCk_MeshMaterialOverride(0, LookMaterial));

        return UCk_Utils_IsmRenderer_TransientFactory_UE::GetOrCreate_ForMeshWithMaterials(
            World, Mesh, Overrides, ECk_Mobility::Movable);
    }
}
