// Language=angelscript

//============================================================================
// CK VFX EXAMPLES GYM — HUD: the pair selector
//============================================================================
//
// Adds a SECOND menu on top of the gym cycler (which stays on Tab, untouched):
// V opens a searchable list of the A/B pairs (F-keys are taken by the editor's
// rendering debug modes); Enter activates the selection —
// one pair is live at a time (see the PlayerController for why). The menu's
// mechanics deliberately mirror ACkGym_MenuHUD's cycler menu (arrows with
// key-repeat, type-to-search, Enter/Esc) so the two feel like one tool; the
// logic is adapted here rather than refactored out of the base because the
// cycler menu serves every gym and has no automated coverage to catch a
// regression.
//
// Hands-on-viewport shortcuts while BOTH menus are closed:
//   PgUp/PgDn — previous/next pair    R — restart the active pair in sync
//
//============================================================================

class ACk_VfxExamplesGym_HUD : ACkGym_MenuHUD
{
    //--------------------------------------------------------------------------------------------------------------------------
    // State
    //--------------------------------------------------------------------------------------------------------------------------

    TArray<FCk_VfxExamples_Pair> VfxCachedPairs;
    bool bVfxMenuVisible = false;
    int32 VfxSelectedIndex = 0;

    FString VfxSearchText = "";
    TArray<int32> VfxFilteredIndices;
    int32 VfxScrollOffset = 0;

    // Key repeat (arrows)
    float VfxHeldTimer = 0.0f;
    int32 VfxHeldDirection = 0;

    // Key repeat (letters)
    bool bVfxHasHeldChar = false;
    FKey VfxHeldCharKey;
    FString VfxHeldChar = "";
    float VfxHeldCharTimer = 0.0f;

    // Key repeat (backspace)
    bool bVfxBackspaceHeld = false;
    float VfxBackspaceTimer = 0.0f;

    //--------------------------------------------------------------------------------------------------------------------------
    // Public API
    //--------------------------------------------------------------------------------------------------------------------------

    void Request_ShowVfxMenu()
    {
        VfxCachedPairs = CkVfxExamples::Get_Pairs();
        bVfxMenuVisible = true;
        VfxSearchText = "";
        VfxFilteredIndices.Empty();
        VfxScrollOffset = 0;
        VfxHeldDirection = 0;
        VfxHeldTimer = 0.0f;
        bVfxHasHeldChar = false;
        VfxHeldCharTimer = 0.0f;
        bVfxBackspaceHeld = false;
        VfxBackspaceTimer = 0.0f;

        auto PC = Get_VfxPC();
        if (ck::IsValid(PC) && PC.Get_ActivePairIndex() >= 0 && PC.Get_ActivePairIndex() < VfxCachedPairs.Num())
        {
            VfxSelectedIndex = PC.Get_ActivePairIndex();
        }
        else
        {
            VfxSelectedIndex = 0;
        }
    }

    //--------------------------------------------------------------------------------------------------------------------------
    // Main draw entry point
    //--------------------------------------------------------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    void DrawHUD(int32 SizeX, int32 SizeY)
    {
        auto _CkPerfScope = ck::ScopedStat();

        // Mirror the base's startup suppression — the base check runs inside Super,
        // which the VFX-menu branch below never reaches.
        auto CyclerSubsystem = UCkGym_CyclerSubsystem::Get();
        if (ck::IsValid(CyclerSubsystem) && CyclerSubsystem.SuppressHUDDuringStartup)
        {
            return;
        }

        auto PC = GetOwningPlayerController();

        if (bVfxMenuVisible)
        {
            // Super is not called while the VFX menu is open (the cycler menu and its
            // Tab handling stay dormant), so the shared blink timer must tick here.
            CursorBlinkTimer = CursorBlinkTimer + GetWorld().GetDeltaSeconds();

            if (ck::IsValid(PC))
            {
                if (Tick_VfxHandleInput(PC, GetWorld().GetDeltaSeconds()))
                {
                    return;  // Menu closed this frame
                }
            }

            Draw_VfxMenu(SizeX, SizeY);
            return;
        }

        if (ck::IsValid(PC) && bMenuVisible == false)
        {
            // Toggle + hands-free shortcuts live only in the "no menu open" state, so
            // they can never collide with either menu's text search.
            if (PC.WasInputKeyJustPressed(EKeys::V))
            {
                Request_ShowVfxMenu();
                Draw_VfxMenu(SizeX, SizeY);
                return;
            }

            auto VfxPC = Get_VfxPC();
            if (ck::IsValid(VfxPC))
            {
                if (PC.WasInputKeyJustPressed(EKeys::PageDown)) { VfxPC.Request_ActivatePair(VfxPC.Get_ActivePairIndex() + 1); }
                if (PC.WasInputKeyJustPressed(EKeys::PageUp))   { VfxPC.Request_ActivatePair(VfxPC.Get_ActivePairIndex() - 1); }
                if (PC.WasInputKeyJustPressed(EKeys::R))        { VfxPC.Ck_GymVfxExamples_RestartAll(); }
            }

            Draw_ActivePairReadout();
        }

        Super::DrawHUD(SizeX, SizeY);

        if (bMenuVisible == false)
        {
            Draw_VfxHint(SizeX);
        }
    }

    //--------------------------------------------------------------------------------------------------------------------------
    // Input handling
    //--------------------------------------------------------------------------------------------------------------------------

    private ACk_VfxExamplesGym_PlayerController Get_VfxPC()
    {
        return Cast<ACk_VfxExamplesGym_PlayerController>(GetOwningPlayerController());
    }

    private int32 Get_VfxDisplayCount()
    {
        return VfxSearchText.Len() > 0 ? VfxFilteredIndices.Num() : VfxCachedPairs.Num();
    }

    private int32 Get_VfxRealIndex(int32 InListPos)
    {
        if (VfxSearchText.Len() > 0)
        {
            if (InListPos >= 0 && InListPos < VfxFilteredIndices.Num())
            {
                return VfxFilteredIndices[InListPos];
            }
            return -1;
        }
        return InListPos;
    }

    private int32 Get_VfxSelectedListPosition()
    {
        if (VfxSearchText.Len() > 0)
        {
            for (int32 f = 0; f < VfxFilteredIndices.Num(); f++)
            {
                if (VfxFilteredIndices[f] == VfxSelectedIndex) { return f; }
            }
            return -1;
        }
        return VfxSelectedIndex;
    }

    // Returns true if the menu was closed
    private bool Tick_VfxHandleInput(APlayerController PC, float DeltaTime)
    {
        Tick_VfxArrowNav(PC, DeltaTime);
        Tick_VfxPageNav(PC);
        Tick_VfxLetterInput(PC);
        Tick_VfxBackspace(PC, DeltaTime);
        Tick_VfxHeldChar(PC, DeltaTime);

        if (PC.WasInputKeyJustPressed(EKeys::Enter))
        {
            if (Get_VfxDisplayCount() > 0 && VfxSelectedIndex >= 0 && VfxSelectedIndex < VfxCachedPairs.Num())
            {
                bVfxMenuVisible = false;
                auto VfxPC = Get_VfxPC();
                if (ck::IsValid(VfxPC))
                {
                    VfxPC.Request_ActivatePair(VfxSelectedIndex);
                }
                return true;
            }
        }

        if (PC.WasInputKeyJustPressed(EKeys::Escape))
        {
            if (VfxSearchText.Len() > 0)
            {
                VfxSearchText = "";
                VfxFilteredIndices.Empty();
            }
            else
            {
                bVfxMenuVisible = false;
            }
            return bVfxMenuVisible == false;
        }

        // Tab closes outright so the muscle-memory "Tab = leave the menu" from the
        // cycler keeps working here. V cannot close (it types into the search).
        if (PC.WasInputKeyJustPressed(EKeys::Tab))
        {
            bVfxMenuVisible = false;
            return true;
        }

        return false;
    }

    private void Tick_VfxArrowNav(APlayerController PC, float DeltaTime)
    {
        auto bDownHeld = PC.IsInputKeyDown(EKeys::Down);
        auto bUpHeld = PC.IsInputKeyDown(EKeys::Up);

        if (PC.WasInputKeyJustPressed(EKeys::Down))
        {
            Request_VfxMoveSelection(1);
            VfxHeldDirection = 1;
            VfxHeldTimer = 0.0f;
        }
        else if (PC.WasInputKeyJustPressed(EKeys::Up))
        {
            Request_VfxMoveSelection(-1);
            VfxHeldDirection = -1;
            VfxHeldTimer = 0.0f;
        }
        else if ((VfxHeldDirection == 1 && bDownHeld) || (VfxHeldDirection == -1 && bUpHeld))
        {
            VfxHeldTimer = VfxHeldTimer + DeltaTime;
            if (VfxHeldTimer >= RepeatDelay)
            {
                VfxHeldTimer = VfxHeldTimer - RepeatRate;
                Request_VfxMoveSelection(VfxHeldDirection);
            }
        }
        else
        {
            VfxHeldDirection = 0;
            VfxHeldTimer = 0.0f;
        }
    }

    private void Tick_VfxPageNav(APlayerController PC)
    {
        if (PC.WasInputKeyJustPressed(EKeys::PageDown)) { Request_VfxMoveSelection(MaxVisibleEntries); }
        if (PC.WasInputKeyJustPressed(EKeys::PageUp))   { Request_VfxMoveSelection(-MaxVisibleEntries); }
        if (PC.WasInputKeyJustPressed(EKeys::Home))     { Request_VfxJumpTo(0); }
        if (PC.WasInputKeyJustPressed(EKeys::End))      { Request_VfxJumpTo(Get_VfxDisplayCount() - 1); }
    }

    private void Tick_VfxLetterInput(APlayerController PC)
    {
        Check_VfxLetter(PC, EKeys::A, "a"); Check_VfxLetter(PC, EKeys::B, "b");
        Check_VfxLetter(PC, EKeys::C, "c"); Check_VfxLetter(PC, EKeys::D, "d");
        Check_VfxLetter(PC, EKeys::E, "e"); Check_VfxLetter(PC, EKeys::F, "f");
        Check_VfxLetter(PC, EKeys::G, "g"); Check_VfxLetter(PC, EKeys::H, "h");
        Check_VfxLetter(PC, EKeys::I, "i"); Check_VfxLetter(PC, EKeys::J, "j");
        Check_VfxLetter(PC, EKeys::K, "k"); Check_VfxLetter(PC, EKeys::L, "l");
        Check_VfxLetter(PC, EKeys::M, "m"); Check_VfxLetter(PC, EKeys::N, "n");
        Check_VfxLetter(PC, EKeys::O, "o"); Check_VfxLetter(PC, EKeys::P, "p");
        Check_VfxLetter(PC, EKeys::Q, "q"); Check_VfxLetter(PC, EKeys::R, "r");
        Check_VfxLetter(PC, EKeys::S, "s"); Check_VfxLetter(PC, EKeys::T, "t");
        Check_VfxLetter(PC, EKeys::U, "u"); Check_VfxLetter(PC, EKeys::V, "v");
        Check_VfxLetter(PC, EKeys::W, "w"); Check_VfxLetter(PC, EKeys::X, "x");
        Check_VfxLetter(PC, EKeys::Y, "y"); Check_VfxLetter(PC, EKeys::Z, "z");
        Check_VfxLetter(PC, EKeys::SpaceBar, " ");
    }

    private void Check_VfxLetter(APlayerController PC, FKey InKey, FString InChar)
    {
        if (PC.WasInputKeyJustPressed(InKey))
        {
            Request_VfxAppendLetter(InChar);
            VfxHeldCharKey = InKey;
            VfxHeldChar = InChar;
            bVfxHasHeldChar = true;
            VfxHeldCharTimer = 0.0f;
        }
    }

    private void Tick_VfxHeldChar(APlayerController PC, float DeltaTime)
    {
        if (bVfxHasHeldChar == false)
        {
            return;
        }

        if (PC.IsInputKeyDown(VfxHeldCharKey) == false)
        {
            bVfxHasHeldChar = false;
            VfxHeldCharTimer = 0.0f;
            return;
        }

        VfxHeldCharTimer = VfxHeldCharTimer + DeltaTime;
        if (VfxHeldCharTimer >= RepeatDelay)
        {
            VfxHeldCharTimer = VfxHeldCharTimer - RepeatRate;
            Request_VfxAppendLetter(VfxHeldChar);
        }
    }

    private void Tick_VfxBackspace(APlayerController PC, float DeltaTime)
    {
        if (PC.WasInputKeyJustPressed(EKeys::BackSpace))
        {
            Request_VfxApplyBackspace();
            bVfxBackspaceHeld = true;
            VfxBackspaceTimer = 0.0f;
        }
        else if (bVfxBackspaceHeld && PC.IsInputKeyDown(EKeys::BackSpace))
        {
            VfxBackspaceTimer = VfxBackspaceTimer + DeltaTime;
            if (VfxBackspaceTimer >= RepeatDelay)
            {
                VfxBackspaceTimer = VfxBackspaceTimer - RepeatRate;
                Request_VfxApplyBackspace();
            }
        }
        else
        {
            bVfxBackspaceHeld = false;
        }
    }

    //--------------------------------------------------------------------------------------------------------------------------
    // Selection / search
    //--------------------------------------------------------------------------------------------------------------------------

    private void Request_VfxMoveSelection(int32 InDelta)
    {
        auto DisplayCount = Get_VfxDisplayCount();
        if (DisplayCount == 0)
        {
            return;
        }

        auto Pos = Get_VfxSelectedListPosition();
        if (Pos < 0) { Pos = 0; }

        Pos = Pos + InDelta;

        // Single steps wrap (cycler feel); page jumps clamp.
        if (InDelta == 1 || InDelta == -1)
        {
            if (Pos >= DisplayCount) { Pos = 0; }
            else if (Pos < 0)        { Pos = DisplayCount - 1; }
        }
        else
        {
            if (Pos < 0)             { Pos = 0; }
            if (Pos >= DisplayCount) { Pos = DisplayCount - 1; }
        }

        VfxSelectedIndex = Get_VfxRealIndex(Pos);
    }

    private void Request_VfxJumpTo(int32 InListPos)
    {
        if (Get_VfxDisplayCount() == 0 || InListPos < 0)
        {
            return;
        }
        VfxSelectedIndex = Get_VfxRealIndex(InListPos);
    }

    private void Request_VfxAppendLetter(FString InChar)
    {
        VfxSearchText = f"{VfxSearchText}{InChar}";
        Request_VfxUpdateFilter();
    }

    private void Request_VfxApplyBackspace()
    {
        if (VfxSearchText.Len() == 0)
        {
            return;
        }

        bVfxHasHeldChar = false;
        VfxSearchText = VfxSearchText.LeftChop(1);

        if (VfxSearchText.Len() == 0)
        {
            VfxFilteredIndices.Empty();
        }
        else
        {
            Request_VfxUpdateFilter();
        }
    }

    private void Request_VfxUpdateFilter()
    {
        VfxFilteredIndices.Empty();
        auto SearchLower = VfxSearchText.ToLower();

        for (int32 i = 0; i < VfxCachedPairs.Num(); i++)
        {
            if (VfxCachedPairs[i].DisplayName.ToLower().Contains(SearchLower))
            {
                VfxFilteredIndices.Add(i);
            }
        }

        if (VfxFilteredIndices.Num() > 0)
        {
            VfxSelectedIndex = VfxFilteredIndices[0];
        }

        VfxScrollOffset = 0;
    }

    private void Request_VfxEnsureSelectedVisible(int32 InDisplayCount)
    {
        if (InDisplayCount <= MaxVisibleEntries)
        {
            VfxScrollOffset = 0;
            return;
        }

        auto SelectedListPos = Get_VfxSelectedListPosition();
        if (SelectedListPos < 0)
        {
            return;
        }

        if (SelectedListPos < VfxScrollOffset)
        {
            VfxScrollOffset = SelectedListPos;
        }
        else if (SelectedListPos >= VfxScrollOffset + MaxVisibleEntries)
        {
            VfxScrollOffset = SelectedListPos - MaxVisibleEntries + 1;
        }

        auto MaxScroll = InDisplayCount - MaxVisibleEntries;
        if (VfxScrollOffset > MaxScroll) { VfxScrollOffset = MaxScroll; }
        if (VfxScrollOffset < 0)         { VfxScrollOffset = 0; }
    }

    //--------------------------------------------------------------------------------------------------------------------------
    // Rendering
    //--------------------------------------------------------------------------------------------------------------------------

    private void Draw_VfxMenu(int32 SizeX, int32 SizeY)
    {
        if (VfxCachedPairs.Num() == 0)
        {
            return;
        }

        auto DisplayCount = Get_VfxDisplayCount();
        auto VisibleCount = Math::Min(DisplayCount, MaxVisibleEntries);
        Request_VfxEnsureSelectedVisible(DisplayCount);

        auto TotalHeight = TitleHeight + PaddingY + (float(Math::Max(VisibleCount, 1)) * EntryHeight) + PaddingY + 44.0f;
        auto TotalWidth = EntryWidth + PaddingX * 2.0f;
        auto MenuX = (float(SizeX) - TotalWidth) * 0.5f;
        auto MenuY = (float(SizeY) - TotalHeight) * 0.5f;
        auto EntryStartY = MenuY + TitleHeight + PaddingY;

        DrawRect(FLinearColor(0.02f, 0.05f, 0.02f, 0.85f), MenuX, MenuY, TotalWidth, TotalHeight);

        // Title
        auto bShowCursor = Math::Fmod(CursorBlinkTimer, CursorBlinkRate * 2.0f) < CursorBlinkRate;
        auto Cursor = bShowCursor ? "|" : " ";
        auto CountStr = VfxSearchText.Len() > 0 ? f"({DisplayCount}/{VfxCachedPairs.Num()})" : f"({VfxCachedPairs.Num()})";
        auto TitleStr = f"VFX PAIRS {CountStr}  >  {VfxSearchText}{Cursor}";
        auto TitleColor = (VfxSearchText.Len() > 0 && DisplayCount == 0)
            ? FLinearColor(1.0f, 0.2f, 0.2f, 1.0f)
            : FLinearColor(0.4f, 1.0f, 0.4f, 1.0f);
        DrawText(TitleStr, TitleColor, MenuX + PaddingX, MenuY + 12.0f, nullptr, 1.5f, false);

        // Entries
        if (DisplayCount == 0)
        {
            DrawText("  No matches", FLinearColor(0.5f, 0.5f, 0.5f, 1.0f), MenuX + PaddingX, EntryStartY + 8.0f, nullptr, 1.0f, false);
        }

        auto PC = Get_VfxPC();
        auto ActiveIndex = ck::IsValid(PC) ? PC.Get_ActivePairIndex() : -1;

        for (int32 row = 0; row < VisibleCount; row++)
        {
            auto ListPos = VfxScrollOffset + row;
            if (ListPos >= DisplayCount)
            {
                break;
            }

            auto RealIndex = Get_VfxRealIndex(ListPos);
            auto EntryY = EntryStartY + (float(row) * EntryHeight);
            auto IsSelected = (RealIndex == VfxSelectedIndex);
            auto IsActive = (RealIndex == ActiveIndex);

            if (IsSelected)
            {
                DrawRect(FLinearColor(0.15f, 0.45f, 0.2f, 0.9f), MenuX + 4.0f, EntryY, TotalWidth - 8.0f - ScrollbarWidth - 8.0f, EntryHeight);
            }

            auto TextColor = IsSelected ? FLinearColor(1.0f, 1.0f, 1.0f, 1.0f) : FLinearColor(0.65f, 0.65f, 0.65f, 1.0f);
            if (IsActive && IsSelected == false)
            {
                TextColor = FLinearColor(0.3f, 0.8f, 0.3f, 1.0f);
            }

            auto Prefix = IsSelected ? ">>  " : "      ";
            auto ActiveMarker = IsActive ? "  *" : "";
            DrawText(f"{Prefix}[{RealIndex}]  {VfxCachedPairs[RealIndex].DisplayName}{ActiveMarker}", TextColor, MenuX + PaddingX, EntryY + 8.0f, nullptr, 1.0f, false);
        }

        // Scrollbar (same geometry as the cycler menu)
        if (DisplayCount > MaxVisibleEntries)
        {
            auto TrackX = MenuX + TotalWidth - PaddingX - ScrollbarWidth;
            auto TrackH = float(VisibleCount) * EntryHeight;
            DrawRect(FLinearColor(0.15f, 0.2f, 0.15f, 0.6f), TrackX, EntryStartY, ScrollbarWidth, TrackH);

            auto ThumbH = Math::Max(TrackH * (float(VisibleCount) / float(DisplayCount)), 16.0f);
            auto MaxScroll = DisplayCount - MaxVisibleEntries;
            auto ScrollFrac = (MaxScroll > 0) ? float(VfxScrollOffset) / float(MaxScroll) : 0.0f;
            DrawRect(FLinearColor(0.55f, 0.75f, 0.55f, 0.9f), TrackX, EntryStartY + (TrackH - ThumbH) * ScrollFrac, ScrollbarWidth, ThumbH);
        }

        // Footer: the highlighted pair's credit, then the controls line
        auto FooterY = EntryStartY + (float(Math::Max(VisibleCount, 1)) * EntryHeight) + 8.0f;
        if (VfxSelectedIndex >= 0 && VfxSelectedIndex < VfxCachedPairs.Num())
        {
            DrawText(VfxCachedPairs[VfxSelectedIndex].Credit, FLinearColor(0.6f, 0.6f, 0.4f, 1.0f), MenuX + PaddingX, FooterY, nullptr, 0.8f, false);
        }
        DrawText(
            "Arrows/PgUp/PgDn/Home/End  |  Type: search  |  Enter: activate  |  Esc/Tab: close",
            FLinearColor(0.4f, 0.4f, 0.4f, 1.0f),
            MenuX + PaddingX, FooterY + 18.0f, nullptr, 0.7f, false
        );
    }

    // Persistent top-left readout while no menu is open: which pair is live, and the
    // keys that drive the harness — the gym is unusable without knowing these.
    private void Draw_ActivePairReadout()
    {
        auto PC = Get_VfxPC();
        if (ck::Is_NOT_Valid(PC))
        {
            return;
        }

        if (VfxCachedPairs.Num() == 0)
        {
            VfxCachedPairs = CkVfxExamples::Get_Pairs();
        }

        auto ActiveIndex = PC.Get_ActivePairIndex();
        if (ActiveIndex < 0 || ActiveIndex >= VfxCachedPairs.Num())
        {
            return;
        }

        auto Pair = VfxCachedPairs[ActiveIndex];
        DrawText(f"VFX PAIR [{ActiveIndex}/{VfxCachedPairs.Num() - 1}]  {Pair.DisplayName}", FLinearColor(0.4f, 1.0f, 0.4f, 0.9f), 24.0f, 20.0f, nullptr, 1.2f, false);
        DrawText(Pair.Credit, FLinearColor(0.6f, 0.6f, 0.4f, 0.8f), 24.0f, 44.0f, nullptr, 0.8f, false);
        DrawText("V: pair list  |  PgUp/PgDn: cycle  |  R: restart pair", FLinearColor(0.5f, 0.5f, 0.5f, 0.7f), 24.0f, 62.0f, nullptr, 0.8f, false);

        // Only while the exec overlay is in force: an unannounced multiplier on the recreation half
        // would read as a fidelity gap against the original beside it. Identity values with the
        // overlay ON are still worth announcing — they are overriding the asset.
        if (PC.Get_IsTuneOverlayActive())
        {
            DrawText(PC.Get_TuningReadout(), FLinearColor(0.9f, 0.7f, 0.3f, 0.85f), 24.0f, 80.0f, nullptr, 0.8f, false);
        }

        // Both pedestals stand empty while the recreation's template compiles. Unannounced that reads as a
        // broken port; announced it reads as the one-time cost it is. Sits below the tune line so the two coexist.
        if (PC.Get_IsWaitingForCompile())
        {
            DrawText(
                f"COMPILING {PC.Get_CompileWaitText()} — first run after a regen; editor stays live, effect appears when ready",
                FLinearColor(1.0f, 0.6f, 0.2f, 0.9f), 24.0f, 98.0f, nullptr, 0.8f, false);
        }

        // The freeze warning, and the ONLY thing on screen for the duration of the block it warns about:
        // the PC sets the text a frame BEFORE it spawns, so this paints while the game thread is still
        // alive and then stays frozen on screen — which is exactly the feedback the block otherwise eats.
        // Drawn larger and hotter than the compile line because it announces a stall, not a wait.
        auto SetupBanner = PC.Get_SetupBannerText();
        if (SetupBanner.Len() > 0)
        {
            DrawText(SetupBanner, FLinearColor(1.0f, 0.35f, 0.15f, 0.95f), 24.0f, 116.0f, nullptr, 1.1f, false);
        }
    }

    private void Draw_VfxHint(int32 SizeX)
    {
        // Sits directly under the base's blinking "Press Tab for Gym Menu" hint,
        // matching its cadence via the shared blink timer.
        auto bShowHint = Math::Fmod(CursorBlinkTimer, 2.0f) < 1.5f;
        if (bShowHint == false)
        {
            return;
        }

        DrawText(
            "Press V for VFX Pairs",
            FLinearColor(0.5f, 0.5f, 0.5f, 0.6f),
            float(SizeX) - 280.0f, 40.0f,
            nullptr, 1.0f, false
        );
    }
}
