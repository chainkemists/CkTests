// --------------------------------------------------------------------------------------------------------------------
// Shared judge scene for the "Pixel Art" gym. ONE of these is spawned for the whole gym, because every
// verdict here is view-wide: the stations change how the frame is rendered, not what is in it.
//
// What each piece is FOR (a pixel-art verdict needs all of them, and none substitutes for another):
//   - ground plane      : the grazing-angle test. A flat surface seen nearly edge-on has an enormous depth
//                         gradient with no edge in it, and a threshold that does not scale with view angle
//                         grows a visible staircase of false outlines across it. This is the single most
//                         likely outline defect and it is invisible on any subject that is not a floor.
//   - cube stack        : hard silhouettes and hard creases, at several sizes. The creases are where a
//                         doubled line shows: two texels instead of one means the de-doubling gate failed.
//   - sphere            : curvature, which is where an outline kernel that sums per-neighbour normal
//                         differences (instead of comparing opposed pairs) false-fires all over.
//   - 30-degree ramp    : the in-between case. Neither flat-on nor edge-on, so it catches a grazing-angle
//                         scale that overcorrects and stops finding real edges.
//   - thin rail         : sub-texel-width geometry. At 360p a railing is about one texel wide, which is
//                         where the renderer either holds a stable line or shimmers.
//   - slow rotator      : the motion subject. Camera snapping does nothing for a moving OBJECT, so this is
//                         the documented limit made visible rather than hidden.
//   - key + fill light  : its OWN lighting rather than the map's. Every banding and crease verdict here is
//                         a verdict about lighting, so a scene that inherited whatever the shared gym map
//                         happened to have would not be comparable between runs. The key sits at a low
//                         angle on purpose: it throws a long shadow across the ground plane, which is what
//                         gives the grazing-angle test something to be wrong about.
//
// The scene is deliberately built from engine basic shapes: a pixel-art verdict must not depend on content
// that could itself be the reason something looks wrong.
// --------------------------------------------------------------------------------------------------------------------

class ACk_PixelArtGym_JudgeScene : AActor
{
    UPROPERTY(DefaultComponent, RootComponent)
    USceneComponent Root;

    private UStaticMeshComponent _Rotator;
    private TArray<USceneComponent> _SuppressedMapLights;
    private float _Elapsed = 0.0f;

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto _CkPerfScope = ck::ScopedStat();

        Suppress_MapLighting();
        Build_Lighting();
        Build_Ground();
        Build_CubeStack();
        Build_Sphere();
        Build_Ramp();
        Build_ThinRail();
        Build_Rotator();
        Build_CaptureTripwire();
    }

    UFUNCTION(BlueprintOverride)
    void EndPlay(EEndPlayReason EndPlayReason)
    {
        for (auto Component : _SuppressedMapLights)
        {
            if (ck::IsValid(Component))
            { Component.SetVisibility(true); }
        }

        _SuppressedMapLights.Empty();
    }

    // "Its OWN lighting rather than the map's" has to mean the map's is OFF, not merely outshone: a second
    // directional doubles every shadow - two overlapping penumbrae that read as jitter on thin features
    // and makes the engine's forward-light selection unstable (the on-screen ForwardShadingPriority
    // warning). Suppressed rather than destroyed, and restored on EndPlay, so every other gym keeps the
    // shared map's lighting exactly as it was.
    private void Suppress_MapLighting()
    {
        auto Directionals = TArray<ADirectionalLight>();
        GetAllActorsOfClass(ADirectionalLight, Directionals);

        for (auto Light : Directionals)
        {
            auto Component = Light.LightComponent;

            if (ck::IsValid(Component) && Component.IsVisible())
            {
                Component.SetVisibility(false);
                _SuppressedMapLights.Add(Component);
            }
        }

        auto SkyLights = TArray<ASkyLight>();
        GetAllActorsOfClass(ASkyLight, SkyLights);

        for (auto Sky : SkyLights)
        {
            auto Component = Sky.LightComponent;

            if (ck::IsValid(Component) && Component.IsVisible())
            {
                Component.SetVisibility(false);
                _SuppressedMapLights.Add(Component);
            }
        }

        if (_SuppressedMapLights.Num() > 0)
        { ck::Trace(f"* Pixel Art Gym: suppressed {_SuppressedMapLights.Num()} map light(s) - the judge scene owns the lighting while it is alive"); }
    }

    UFUNCTION(BlueprintOverride)
    void Tick(float InDeltaSeconds)
    {
        if (_Rotator == nullptr)
        { return; }

        _Elapsed += InDeltaSeconds;

        // Slow on purpose: fast rotation hides per-texel instability, which is the thing this subject is
        // here to expose.
        _Rotator.SetRelativeRotation(FRotator(0.0f, _Elapsed * 12.0f, _Elapsed * 5.0f));
    }

    private UStaticMeshComponent Spawn_Shape(FString InMeshPath, FVector InLocation, FVector InScale,
        FRotator InRotation, FLinearColor InColor)
    {
        auto Mesh = Cast<UStaticMesh>(LoadObject(this, InMeshPath));
        auto Material = Cast<UMaterialInterface>(
            LoadObject(this, "/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));

        if (Mesh == nullptr)
        {
            ck::Error(f"[FAIL] PixelArt Gym: could not load {InMeshPath}");
            return nullptr;
        }

        auto Component = UStaticMeshComponent::Create(this);
        Component.SetStaticMesh(Mesh);
        Component.SetRelativeLocation(InLocation);
        Component.SetRelativeScale3D(InScale);
        Component.SetRelativeRotation(InRotation);

        if (Material != nullptr)
        {
            auto Instance = Component.CreateDynamicMaterialInstance(0, Material);
            if (Instance != nullptr)
            { Instance.SetVectorParameterValue(n"Color", InColor); }
        }

        return Component;
    }

    // Shadows are cast, which under this project means VIRTUAL shadow maps (`r.Shadow.Virtual.Enable=1`,
    // Config/DefaultEngine.ini:57). That matters to a pixel-art verdict: a hard shadow-map edge flickers at
    // 360p, and VSM's filtered edge is what holds the shadow boundary still between frames. If a run ever
    // shows a crawling shadow edge, check that CVar before suspecting the camera snap.
    private void Build_Lighting()
    {
        auto KeyLight = UDirectionalLightComponent::Create(this);
        KeyLight.SetRelativeRotation(FRotator(-38.0f, 145.0f, 0.0f));
        KeyLight.SetIntensity(6.0f);
        KeyLight.SetLightColor(FLinearColor(1.0f, 0.96f, 0.88f, 1.0f));
        KeyLight.SetCastShadows(true);

        // Belt over the suppression above: whatever else exists, THIS light wins the forward-shading slot,
        // so the selection can never flip mid-run.
        KeyLight.SetForwardShadingPriority(100);

        // A HARD sun, deliberately: the default 0.54-degree source angle grows a penumbra several texels
        // wide at this scene's depths, and virtual shadow maps sample penumbrae stochastically per frame
        // expecting temporal AA to clean the noise - which this renderer requires OFF. A zero source angle
        // collapses the penumbra to the crisp texel-snapped edge the style wants anyway.
        KeyLight.SetLightSourceAngle(0.0f);

        // Without a fill, everything facing away from the key collapses into one band and the band COUNT
        // becomes unjudgeable on exactly the surfaces the crease test needs.
        auto Fill = USkyLightComponent::Create(this);
        Fill.SetIntensity(1.0f);
        Fill.SetLightColor(FLinearColor(0.55f, 0.62f, 0.80f, 1.0f));
    }

    private void Build_Ground()
    {
        Spawn_Shape("/Engine/BasicShapes/Plane.Plane", FVector(0.0f, 0.0f, 0.0f),
            FVector(60.0f, 60.0f, 1.0f), FRotator::ZeroRotator, FLinearColor(0.30f, 0.32f, 0.30f, 1.0f));
    }

    private void Build_CubeStack()
    {
        Spawn_Shape("/Engine/BasicShapes/Cube.Cube", FVector(0.0f, -300.0f, 100.0f),
            FVector(2.0f, 2.0f, 2.0f), FRotator::ZeroRotator, FLinearColor(0.55f, 0.35f, 0.28f, 1.0f));
        Spawn_Shape("/Engine/BasicShapes/Cube.Cube", FVector(-40.0f, -300.0f, 260.0f),
            FVector(1.2f, 1.2f, 1.2f), FRotator(0.0f, 22.0f, 0.0f), FLinearColor(0.70f, 0.52f, 0.36f, 1.0f));
        Spawn_Shape("/Engine/BasicShapes/Cube.Cube", FVector(30.0f, -270.0f, 370.0f),
            FVector(0.6f, 0.6f, 0.6f), FRotator(0.0f, -14.0f, 0.0f), FLinearColor(0.85f, 0.72f, 0.50f, 1.0f));
    }

    private void Build_Sphere()
    {
        Spawn_Shape("/Engine/BasicShapes/Sphere.Sphere", FVector(0.0f, 0.0f, 150.0f),
            FVector(3.0f, 3.0f, 3.0f), FRotator::ZeroRotator, FLinearColor(0.42f, 0.46f, 0.62f, 1.0f));
    }

    private void Build_Ramp()
    {
        Spawn_Shape("/Engine/BasicShapes/Cube.Cube", FVector(0.0f, 380.0f, 90.0f),
            FVector(4.0f, 2.0f, 0.2f), FRotator(30.0f, 0.0f, 0.0f), FLinearColor(0.38f, 0.50f, 0.40f, 1.0f));
    }

    private void Build_ThinRail()
    {
        // Roughly one texel wide at 360p from the gym's viewing distance - the point of it is to be at the
        // edge of what the resolution can represent at all.
        Spawn_Shape("/Engine/BasicShapes/Cylinder.Cylinder", FVector(-350.0f, 0.0f, 220.0f),
            FVector(0.06f, 0.06f, 4.0f), FRotator(0.0f, 0.0f, 90.0f), FLinearColor(0.80f, 0.80f, 0.84f, 1.0f));
    }

    private void Build_Rotator()
    {
        _Rotator = Spawn_Shape("/Engine/BasicShapes/Cone.Cone", FVector(350.0f, 0.0f, 200.0f),
            FVector(1.5f, 1.5f, 2.0f), FRotator::ZeroRotator, FLinearColor(0.72f, 0.30f, 0.34f, 1.0f));
    }

    // A per-frame scene capture, kept deliberately: its view family renders BETWEEN the game viewport's
    // SetupViewFamily and BeginRenderViewFamily hooks, which is exactly the interleave that once dropped the
    // upscaler for any world holding a minimap-style capture. With the capture alive, a regression of that
    // guard is unmissable - the whole gym goes soft and mis-framed - where without one the defect is invisible
    // in every station. 128x128 keeps its cost negligible.
    private void Build_CaptureTripwire()
    {
        auto Capture = USceneCaptureComponent2D::Create(this);
        Capture.TextureTarget = Rendering::CreateRenderTarget2D(128, 128);
        Capture.bCaptureEveryFrame = true;
        Capture.SetRelativeLocation(FVector(0.0f, 0.0f, 2000.0f));
        Capture.SetRelativeRotation(FRotator(-90.0f, 0.0f, 0.0f));

        // Loud either way: an inert tripwire is worse than none, because it reads as coverage.
        if (ck::Is_NOT_Valid(Capture.TextureTarget))
        {
            ck::Error("[FAIL] Pixel Art Gym: the capture tripwire has NO render target - it captures nothing and the capture-interleave path is not being exercised");
            return;
        }

        ck::Trace("* Capture tripwire alive: a 128x128 scene capture renders every frame beside the gym");
    }
}
