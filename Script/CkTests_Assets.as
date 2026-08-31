/*
+-------------------------------------------------------------------------+
| AUTO GENERATE ASSETS IN THESE FOLDERS                                   |
+-------------------------------------------------------------------------+
*/

#if editor
asset CkTestsAssets of UCkAssetRegistryConfig
{
    AssetDiscoveryRoot = "/CkTests/";
    OutputFileName = "CkTestsAssets.as";

    // The AutoTests level carries the Recast provider's own nav-data actor. Discovery is
    // path-based, so it would otherwise be handed to script as a named accessor - and no test
    // is allowed to reach for a provider-specific navigation type.
    ExcludedAssetClasses.Add(n"RecastNavMesh");
}
#endif
