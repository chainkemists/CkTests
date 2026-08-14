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
            "Projects",
            "GameplayTags",
            "FunctionalTesting",
            "Gauntlet",
            "EnhancedInput",
            "RenderCore",
            // Direct, not inherited through CkParticles: the CkParticles authoring gate loads a UNiagaraSystem
            // itself, and the transitive public dependency did not put Niagara's import lib on this link
            // (LNK2019 on Z_Construct_UClass_UNiagaraSystem_NoRegister).
            "Niagara",
            "Voice",

            "CkActorRelay",
            "CkAggro",
            "CkAnimation",
            "CkAttribute",
            "CkAudio",
            "CkCamera",
            "CkCore",
            "CkCrowd",
            "CkCue",
            "CkCVar",
            "CkDynamic",
            "CkEcs",
            "CkEcsExt",
            "CkEntityVisualizer",
            "CkEntityCollection",
            "CkEntityExtension",
            "CkEntityTag",
            "CkEqs",
            "CkFx",
            "CkGoap",
            "CkGraphics",
            "CkGrid",
            "CkInput",
            "CkInteraction",
            "CkIntent",
            "CkInventory",
            "CkIskmRenderer",
            "CkIsmRenderer",
            "CkJolt",
            "CkThirdParty",
            "CkLabel",
            "CkLagCompensation",
            "CkLog",
            "CkNavigation",
            "CkObjective",
            // Public dependency on purpose: it carries the CK_WITH_PARTICLES definition that the CkParticles
            // authoring gate keys on. A private dependency would leave that define undetectable here and the
            // gate would silently skip forever.
            "CkParticles",
            "CkPathNetwork",
            "CkPerception",
            "CkPmg",
            "CkPhysics",
            "CkProfile",
            "CkProjectile",
            "CkProvider",
            "CkRecord",
            "CkRelationship",
            "CkRenderTarget",
            "CkResolver",
            "CkResourceLoader",
            "CkSettings",
            "CkShapes",
            "CkSnapshot",
            // CkNetAutomation_Common exposes probe payload types in its public latent-test surface.
            // Adaptive non-unity compilation requires the defining module's import library directly.
            "CkSpatialQuery",
            "CkStateMachine",
            "CkSubstep",
            "CkTagSet",
            "CkTargeting",
            "CkTimer",
            "CkWidgets",
            "CkUICore",
            "CkUnrealComponent",
            "CkUsf",
            "CkVariables",
            "CkVoiceChat",
            "CkVoxelNav",
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
