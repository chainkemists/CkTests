using System.IO;
using UnrealBuildTool;

public class CkTests : CkModuleRules
{
    public CkTests(ReadOnlyTargetRules Target) : base(Target)
    {
        PrivateIncludePaths.AddRange(new string[] {
            // ... add other private include paths required here ...
        });

        PrivateDependencyModuleNames.AddRange(new string[]
        {
            // The layout lifecycle fixture creates and activates CommonUI widgets directly.
            "UMG",
            "CommonUI",
            "Text3D",
            "PhysicsCore",
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
            "RHI",
            // The CkJolt dynamic-mesh bake tests author a runtime FDynamicMesh3 (GeometryCore) on an
            // ADynamicMeshActor (GeometryFramework) — the exact runtime-generated geometry that bake serves.
            "GeometryCore",
            "GeometryFramework",
            // Direct, not inherited through CkParticles: the CkParticles authoring gate loads a UNiagaraSystem
            // itself, and the transitive public dependency did not put Niagara's import lib on this link
            // (LNK2019 on Z_Construct_UClass_UNiagaraSystem_NoRegister).
            "Niagara",
            "Voice",
            // The gym switchboard (Slate viewport widget styled with the shared CkStyle tokens).
            // Slate/SlateCore are reachable transitively via CkWidgets/CkUICore, but transitive
            // links are luck, not policy.
            "Slate",
            "SlateCore",
            "InputCore",
            "CkEditorTools",

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
            "CkDebugScene",
            "CkDynamic",
            "CkEcs",
            "CkEcsExt",
            "CkEntityVisualizer",
            "CkEntityCollection",
            // Level-root persistence contracts exercise authored/runtime CkEntitySpawner identity stamping.
            "CkEntitySpawner",
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
            "CkMinimap",
            "CkPerception",
            "CkPixelArtRenderer",
            "CkPmg",
            "CkPhysics",
            "CkProfile",
            "CkProjectile",
            "CkProvider",
            "CkQueue",
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
            "CkUI",
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
                // The Jolt incremental-cook planner and index remap are pure functions living in the
                // editor cooker; their tests link against it directly.
                "CkJoltEditor",
            });
        }
    }
}
