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
            "Gauntlet",
            "EnhancedInput",
            "RenderCore",

            "CkActorRelay",
            "CkAggro",
            "CkAnimation",
            "CkAttribute",
            "CkAudio",
            "CkCamera",
            "CkCore",
            "CkCue",
            "CkCVar",
            "CkEcs",
            "CkEcsExt",
            "CkEntityCollection",
            "CkEntityExtension",
            "CkGraphics",
            "CkGrid",
            "CkInventory",
            "CkIsmRenderer",
            "CkLabel",
            "CkLog",
            "CkPerception",
            "CkPhysics",
            "CkProvider",
            "CkRecord",
            "CkRelationship",
            "CkRenderTarget",
            "CkResolver",
            "CkResourceLoader",
            "CkSettings",
            "CkShapes",
            "CkSnapshot",
            "CkStateMachine",
            "CkSubstep",
            "CkTagSet",
            "CkTargeting",
            "CkUI",
            "CkUnrealComponent",
            "CkUsf",
            "CkVariables",
            "CkWatermark",
        });

        if (Target.bBuildEditor)
        {
            PrivateDependencyModuleNames.AddRange(new string[]
            {
                "UnrealEd",
                "EditorSubsystem",
                "CkUsfEditor",
            });
        }
    }
}
