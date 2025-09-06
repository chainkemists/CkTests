namespace ck
{
    asset Asset_RegularCube of UCk_IsmRenderer_Data
    {
        _Mesh = Cast<UStaticMesh>(utils_i_o::LoadAssetByName("/Engine/EngineMeshes/Cube.Cube",
            ECk_AssetSearchScope::Engine)._Asset);
        _Mobility = ECk_Mobility::Movable;
    }

    // Background cube with inverted normals - useful for future visual elements
    asset Asset_BackgroundCube of UCk_IsmRenderer_Data
    {
        _Mesh = Cast<UStaticMesh>(utils_i_o::LoadAssetByName("/Engine/EngineMeshes/BackgroundCube.BackgroundCube",
            ECk_AssetSearchScope::Engine)._Asset);
        _Mobility = ECk_Mobility::Movable;
    }

    // Station marker asset for visual indicators
    asset Asset_StationMarker of UCk_IsmRenderer_Data
    {
        _Mesh = Cast<UStaticMesh>(utils_i_o::LoadAssetByName("/Engine/EngineMeshes/Cube.Cube",
            ECk_AssetSearchScope::Engine)._Asset);
        _Mobility = ECk_Mobility::Movable;
    }
}

