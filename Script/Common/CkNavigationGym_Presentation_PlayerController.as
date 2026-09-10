enum ECkNavigationGym_PresentationMode
{
    Baseline,
    Hero,
    Diagnostic
}

struct FCkNavigationGym_PresentationMaterial
{
    UPROPERTY()
    UStaticMeshComponent Mesh;

    UPROPERTY()
    UMaterialInterface Original;

    UPROPERTY()
    UMaterialInstanceDynamic Showcase;
}

namespace CkNavigationGymPresentation
{
    void Request_RegisterActor(AActor InActor)
    {
        if (ck::Is_NOT_Valid(InActor))
        { return; }
        InActor.Tags.AddUnique(n"CkNavigationGym.Presentation");
        auto PC = Cast<ACk_NavigationGym_Presentation_PlayerController>(Gameplay::GetPlayerController(0));
        if (ck::IsValid(PC))
        { PC.Request_RefreshPresentationMaterials(); }
    }
}

class ACk_NavigationGym_Presentation_PlayerController : ACk_Gym_Base_PlayerController
{
    private ECkNavigationGym_PresentationMode _PresentationMode = ECkNavigationGym_PresentationMode::Baseline;
    private TArray<FCkNavigationGym_PresentationMaterial> _PresentationMaterials;

    FVector Get_PresentationCentre()
    { return FVector::ZeroVector; }

    FVector Get_PresentationExtent()
    { return FVector(1500.0, 1500.0, 300.0); }

    FString Get_PresentationCaption()
    { return "Navigation proving ground"; }

    void Request_PresentationBaselineView()
    { Request_PresentationFrame(); }

    ECkNavigationGym_PresentationMode Get_PresentationMode()
    { return _PresentationMode; }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Append_PresentationControls(Rows);
        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    { Request_HandlePresentationControl(InRowIndex); }

    FString Get_PresentationProvider()
    {
        return utils_nav_surface::Get_Provider() == ECk_NavSurface_Provider::GroundNav
            ? "GroundNav" : "Recast";
    }

    FCkGym_ControlRow Get_PresentationVerdict()
    {
        auto Rows = Get_ControlRows();
        for (auto Row : Rows)
        {
            if (Row.Kind == ECkGym_ControlKind::Status && Row.Label == "Verdict")
            { return Row; }
        }
        return CkGym_Control::Status("Observation", "Follow the six scenarios; arrival/failure evidence is in the log");
    }

    void Append_PresentationControls(TArray<FCkGym_ControlRow>& InOutRows)
    {
        InOutRows.Add(CkGym_Control::Action(EKeys::Home, "Home", "Hero view"));
        InOutRows.Add(CkGym_Control::Action(EKeys::End, "End", "Diagnostic view"));
        InOutRows.Add(CkGym_Control::Action(EKeys::BackSpace, "Backspace", "Original baseline view"));
        InOutRows.Add(CkGym_Control::Status("Provider", Get_PresentationProvider()));
    }

    bool Request_HandlePresentationControl(int32 InRowIndex)
    {
        auto Rows = Get_ControlRows();
        if (Rows.IsValidIndex(InRowIndex) == false)
        { return false; }

        const auto Key = Rows[InRowIndex].Key;
        if (Key == EKeys::Home)
        { Ck_NavShowcase_Hero(); return true; }
        if (Key == EKeys::End)
        { Ck_NavShowcase_Diagnostic(); return true; }
        if (Key == EKeys::BackSpace)
        { Ck_NavShowcase_Baseline(); return true; }
        return false;
    }

    UFUNCTION(Exec)
    void Ck_NavShowcase_Hero()
    {
        if (Request_PresentationFrame() == false)
        { return; }
        Do_SetPresentationMaterials(true);
        _PresentationMode = ECkNavigationGym_PresentationMode::Hero;
    }

    UFUNCTION(Exec)
    void Ck_NavShowcase_Diagnostic()
    {
        if (Request_PresentationFrame() == false)
        { return; }
        Do_SetPresentationMaterials(true);
        _PresentationMode = ECkNavigationGym_PresentationMode::Diagnostic;
    }

    UFUNCTION(Exec)
    void Ck_NavShowcase_Baseline()
    {
        Do_SetPresentationMaterials(false);
        _PresentationMode = ECkNavigationGym_PresentationMode::Baseline;
        Request_PresentationBaselineView();
    }

    bool Request_PresentationFrame()
    {
        auto ViewPawn = GetControlledPawn();
        if (ck::Is_NOT_Valid(ViewPawn) || ck::Is_NOT_Valid(PlayerCameraManager))
        { return false; }

        const auto Centre = Get_PresentationCentre();
        const auto Extent = Get_PresentationExtent();
        const auto HorizontalFov = PlayerCameraManager.GetFOVAngle();
        const auto FovIsValid = HorizontalFov >= 10.0 && HorizontalFov <= 150.0;
        if (Centre.ContainsNaN() || Extent.ContainsNaN() || Extent.X <= 0.0 ||
            Extent.Y <= 0.0 || Extent.Z <= 0.0 || FovIsValid == false)
        { return false; }

        // Fit a bounding sphere inside the vertical field of a 16:9 view, leaving room for captions.
        const auto VerticalHalfFov = Math::Atan(Math::Tan(Math::DegreesToRadians(HorizontalFov * 0.5)) / (16.0 / 9.0));
        const auto Distance = Extent.Size() * 1.18 / Math::Sin(VerticalHalfFov);
        FRotator Rotation = FRotator(-48.0, 135.0, 0.0);
        ViewPawn.SetActorLocation(Centre - Rotation.Vector() * Distance);
        SetControlRotation(Rotation);
        return true;
    }

    UFUNCTION(Exec)
    void Ck_NavShowcase_Record()
    {
        auto ViewPawn = GetControlledPawn();
        if (ck::Is_NOT_Valid(ViewPawn) || ck::Is_NOT_Valid(PlayerCameraManager))
        {
            ck::groundnav::Log("[NAV-SHOWCASE] record rejected: no possessed view pawn or camera manager");
            return;
        }

        int32 Width = 0;
        int32 Height = 0;
        GetViewportSize(Width, Height);
        const auto Location = ViewPawn.GetActorLocation();
        const auto Rotation = GetControlRotation();
        const auto HorizontalFov = PlayerCameraManager.GetFOVAngle();
        const auto Verdict = Get_PresentationVerdict();
        ck::groundnav::Log(f"[NAV-SHOWCASE] scene={Get_ControlPanelTitle()} provider={Get_PresentationProvider()} mode={int32(_PresentationMode)} resolution={Width}x{Height} camera={Location} rotation={Rotation} fov={HorizontalFov} verdict={Verdict.Value} warning={Verdict.Warn}");
        auto Rows = Get_ControlRows();
        for (auto Row : Rows)
        { ck::groundnav::Log(f"[NAV-SHOWCASE-CONTROL] key={Row.KeyLabel} label={Row.Label} value={Row.Value} enabled={Row.Enabled}"); }
    }

    private void Do_SetPresentationMaterials(bool InShowcase)
    {
        if (InShowcase)
        { Do_CollectPresentationMaterials(); }

        for (auto Entry : _PresentationMaterials)
        {
            if (ck::Is_NOT_Valid(Entry.Mesh))
            { continue; }
            Entry.Mesh.SetMaterial(0, InShowcase ? Entry.Showcase : Entry.Original);
        }
    }

    void Request_RefreshPresentationMaterials()
    {
        if (_PresentationMode != ECkNavigationGym_PresentationMode::Baseline)
        { Do_SetPresentationMaterials(true); }
    }

    private void Do_CollectPresentationMaterials()
    {
        for (int32 Index = _PresentationMaterials.Num() - 1; Index >= 0; Index--)
        {
            if (ck::Is_NOT_Valid(_PresentationMaterials[Index].Mesh))
            { _PresentationMaterials.RemoveAt(Index); }
        }
        TArray<AActor> Actors;
        GetAllActorsOfClass(Actors);
        for (auto Actor : Actors)
        {
            if (Actor.ActorHasTag(n"CkNavigationGym.Presentation") == false)
            { continue; }
            auto PresentationComponents = Actor.GetComponentsByClass(UStaticMeshComponent);
            for (auto Component : PresentationComponents)
            {
                auto Mesh = Cast<UStaticMeshComponent>(Component);
                if (ck::Is_NOT_Valid(Mesh))
                { continue; }
                bool AlreadyRegistered = false;
                for (auto Entry : _PresentationMaterials)
                {
                    if (Entry.Mesh == Mesh)
                    { AlreadyRegistered = true; break; }
                }
                if (AlreadyRegistered)
                { continue; }

                auto Original = Mesh.GetMaterial(0);
                if (ck::Is_NOT_Valid(Original))
                { continue; }
                auto Showcase = Mesh.CreateDynamicMaterialInstance(0, Original);
                if (ck::Is_NOT_Valid(Showcase))
                { continue; }
                const auto Scale = Mesh.GetWorldScale();
                FLinearColor Tint = FLinearColor(0.12, 0.18, 0.25, 1.0);
                if (Scale.Z > Math::Min(Scale.X, Scale.Y))
                { Tint = FLinearColor(0.62, 0.39, 0.16, 1.0); }
                Showcase.SetVectorParameterValue(n"Color", Tint);

                FCkNavigationGym_PresentationMaterial Entry;
                Entry.Mesh = Mesh;
                Entry.Original = Original;
                Entry.Showcase = Showcase;
                _PresentationMaterials.Add(Entry);
            }
        }
    }
}
