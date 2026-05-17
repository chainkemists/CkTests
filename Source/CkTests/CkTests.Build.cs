using System.IO;
using UnrealBuildTool;

public class CkTests : CkModuleRules
{
    public CkTests(ReadOnlyTargetRules Target) : base(Target)
    {
        PrivateIncludePaths.AddRange(new string[] {
            // ... add other private include paths required here ...
        });

        PublicDependencyModuleNames.AddRange(new string[]
        {
            "Core",
            "CoreUObject",
            "DeveloperSettings",
            "Engine",
            "GameplayTags",
            "FunctionalTesting",

            "CkActorRelay",
            "CkAudio",
            "CkCore",
            "CkCue",
            "CkCVar",
            "CkEcs",
            "CkEntityCollection",
            "CkEntityExtension",
            "CkGraphics",
            "CkIsmRenderer",
            "CkLabel",
            "CkLog",
            "CkPerception",
            "CkProvider",
            "CkRecord",
            "CkResourceLoader",
            "CkSettings",
            "CkShapes",
            "CkSubstep",
            "CkUI",
            "CkWatermark",
        });
    }
}
