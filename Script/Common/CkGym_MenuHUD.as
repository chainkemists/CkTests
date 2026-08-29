class ACkGym_MenuHUD : AHUD
{
    //--------------------------------------------------------------------------------------------------------------------------
    // State
    //--------------------------------------------------------------------------------------------------------------------------

    TArray<FCkGym_Entry> CachedRegistry;
    bool bMenuVisible = false;
    int32 SelectedIndex = 0;

    // Input buffer (numbers or text search)
    FString InputBuffer = "";
    bool bSearchMode = false;
    TArray<int32> FilteredIndices;

    // Cursor blink
    float CursorBlinkTimer = 0.0f;
    float CursorBlinkRate = 0.5f;

    // Key repeat (arrows)
    float RepeatDelay = 0.35f;
    float RepeatRate = 0.08f;
    float HeldTimer = 0.0f;
    int32 HeldDirection = 0;

    // Key repeat (letters/numbers)
    bool bHasHeldChar = false;
    bool bHeldCharIsLetter = false;
    FKey HeldCharKey;
    FString HeldChar = "";
    float HeldCharTimer = 0.0f;

    // Key repeat (backspace)
    bool bBackspaceHeld = false;
    float BackspaceTimer = 0.0f;

    // Layout
    float EntryHeight = 36.0f;
    float EntryWidth = 460.0f;
    float TitleHeight = 48.0f;
    float PaddingX = 24.0f;
    float PaddingY = 16.0f;
    float ScrollbarWidth = 6.0f;
    int32 MaxVisibleEntries = 20;

    // Scroll state - index into the active list of the first visible row
    int32 ScrollOffset = 0;

    //--------------------------------------------------------------------------------------------------------------------------
    // Public API
    //--------------------------------------------------------------------------------------------------------------------------

    void Request_ShowMenu()
    {
        CachedRegistry = CkGym_Cycler::Get_GymRegistry();
        bMenuVisible = true;
        InputBuffer = "";
        bSearchMode = false;
        HeldDirection = 0;
        HeldTimer = 0.0f;
        bHasHeldChar = false;
        HeldCharTimer = 0.0f;
        bBackspaceHeld = false;
        BackspaceTimer = 0.0f;
        ScrollOffset = 0;
        FilteredIndices.Empty();

        auto CurrentGymIndex = UCk_Utils_GymRegistry_UE::Get_CurrentGymIndex();
        if (CurrentGymIndex >= 0 && CurrentGymIndex < CachedRegistry.Num())
        {
            SelectedIndex = CurrentGymIndex;
        }
        else
        {
            SelectedIndex = 0;
        }
    }

    void Request_ToggleMenu()
    {
        if (bMenuVisible) { bMenuVisible = false; }
        else              { Request_ShowMenu(); }
    }

    void Request_ClearInput()
    {
        InputBuffer = "";
        bSearchMode = false;
        bHasHeldChar = false;
        FilteredIndices.Empty();
    }

    //--------------------------------------------------------------------------------------------------------------------------
    // Main draw entry point
    //--------------------------------------------------------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    void DrawHUD(int32 SizeX, int32 SizeY)
    {
        auto _CkPerfScope = ck::ScopedStat();
        // Suppress all HUD output (and ignore Tab) while a startup-gym
        // auto-travel is in flight. This prevents the cycler menu / tab-hint
        // from flashing on the launcher level during the brief transition
        // to the user's chosen Default / Last gym.
        if (UCk_Utils_GymRegistry_UE::Get_SuppressHUDDuringStartup())
        {
            return;
        }

        auto PC = GetOwningPlayerController();
        auto DeltaTime = GetWorld().GetDeltaSeconds();
        CursorBlinkTimer = CursorBlinkTimer + DeltaTime;

        // Tab toggles menu from any gym
        if (ck::IsValid(PC) && PC.WasInputKeyJustPressed(EKeys::Tab))
        {
            Request_ToggleMenu();
        }

        if (bMenuVisible == false)
        {
            Draw_TabHint(SizeX, SizeY);
            return;
        }

        if (CachedRegistry.Num() == 0)
        {
            return;
        }

        auto NumEntries = CachedRegistry.Num();

        // Input handling
        if (ck::IsValid(PC))
        {
            if (Tick_HandleInput(PC, DeltaTime, NumEntries))
            {
                return;  // Menu closed (Enter/Escape on a valid action)
            }
        }

        // Layout
        auto DisplayCount = bSearchMode ? FilteredIndices.Num() : NumEntries;
        auto VisibleCount = Math::Min(DisplayCount, MaxVisibleEntries);
        Request_EnsureSelectedVisible(DisplayCount);

        auto TotalHeight = TitleHeight + PaddingY + (float(Math::Max(VisibleCount, 1)) * EntryHeight) + PaddingY + 24.0f;
        auto TotalWidth = EntryWidth + PaddingX * 2.0f;
        auto MenuX = (float(SizeX) - TotalWidth) * 0.5f;
        auto MenuY = (float(SizeY) - TotalHeight) * 0.5f;
        auto EntryStartY = MenuY + TitleHeight + PaddingY;

        // Render
        Draw_Background(MenuX, MenuY, TotalWidth, TotalHeight);
        Draw_Title(MenuX, MenuY, NumEntries);
        Draw_Entries(MenuX, EntryStartY, TotalWidth, VisibleCount, DisplayCount);
        Draw_Scrollbar(MenuX, EntryStartY, TotalWidth, VisibleCount, DisplayCount);
        Draw_Footer(MenuX, EntryStartY, VisibleCount);
    }

    //--------------------------------------------------------------------------------------------------------------------------
    // Input handling
    //--------------------------------------------------------------------------------------------------------------------------

    // Returns true if the menu was closed
    bool Tick_HandleInput(APlayerController PC, float DeltaTime, int32 NumEntries)
    {
        Tick_HandleArrowNav(PC, DeltaTime, NumEntries);
        Tick_HandlePageNav(PC, NumEntries);
        Tick_HandleLetterInput(PC);

        if (bSearchMode == false)
        {
            Tick_HandleNumberInput(PC, NumEntries);
        }

        Tick_HandleBackspace(PC, DeltaTime, NumEntries);

        if (PC.WasInputKeyJustPressed(EKeys::Enter))
        {
            if (Get_IsSelectionValid(NumEntries))
            {
                bMenuVisible = false;
                CkGym_Cycler::Request_TravelToGym(SelectedIndex);
                return true;
            }
        }

        if (PC.WasInputKeyJustPressed(EKeys::Escape))
        {
            if (InputBuffer.Len() > 0) { Request_ClearInput(); }
            else                       { bMenuVisible = false; }
            return true;
        }

        // Arrow keys clear number input but keep search filter
        if (bSearchMode == false && (PC.WasInputKeyJustPressed(EKeys::Up) || PC.WasInputKeyJustPressed(EKeys::Down)))
        {
            Request_ClearInput();
        }

        Request_ProcessHeldChar(PC, DeltaTime, NumEntries);
        return false;
    }

    void Tick_HandleArrowNav(APlayerController PC, float DeltaTime, int32 NumEntries)
    {
        auto bDownHeld = PC.IsInputKeyDown(EKeys::Down);
        auto bUpHeld = PC.IsInputKeyDown(EKeys::Up);

        if (PC.WasInputKeyJustPressed(EKeys::Down))
        {
            Request_MoveSelection(1, NumEntries);
            HeldDirection = 1;
            HeldTimer = 0.0f;
        }
        else if (PC.WasInputKeyJustPressed(EKeys::Up))
        {
            Request_MoveSelection(-1, NumEntries);
            HeldDirection = -1;
            HeldTimer = 0.0f;
        }
        else if ((HeldDirection == 1 && bDownHeld) || (HeldDirection == -1 && bUpHeld))
        {
            HeldTimer = HeldTimer + DeltaTime;
            if (HeldTimer >= RepeatDelay)
            {
                HeldTimer = HeldTimer - RepeatRate;
                Request_MoveSelection(HeldDirection, NumEntries);
            }
        }
        else
        {
            HeldDirection = 0;
            HeldTimer = 0.0f;
        }
    }

    void Tick_HandlePageNav(APlayerController PC, int32 NumEntries)
    {
        if (PC.WasInputKeyJustPressed(EKeys::PageDown))
        {
            Request_MoveSelectionByPage(MaxVisibleEntries, NumEntries);
        }
        if (PC.WasInputKeyJustPressed(EKeys::PageUp))
        {
            Request_MoveSelectionByPage(-MaxVisibleEntries, NumEntries);
        }
        if (PC.WasInputKeyJustPressed(EKeys::Home))
        {
            Request_JumpToFirst();
        }
        if (PC.WasInputKeyJustPressed(EKeys::End))
        {
            Request_JumpToLast();
        }
    }

    void Tick_HandleLetterInput(APlayerController PC)
    {
        Request_CheckLetterInput(PC, EKeys::A, "a"); Request_CheckLetterInput(PC, EKeys::B, "b");
        Request_CheckLetterInput(PC, EKeys::C, "c"); Request_CheckLetterInput(PC, EKeys::D, "d");
        Request_CheckLetterInput(PC, EKeys::E, "e"); Request_CheckLetterInput(PC, EKeys::F, "f");
        Request_CheckLetterInput(PC, EKeys::G, "g"); Request_CheckLetterInput(PC, EKeys::H, "h");
        Request_CheckLetterInput(PC, EKeys::I, "i"); Request_CheckLetterInput(PC, EKeys::J, "j");
        Request_CheckLetterInput(PC, EKeys::K, "k"); Request_CheckLetterInput(PC, EKeys::L, "l");
        Request_CheckLetterInput(PC, EKeys::M, "m"); Request_CheckLetterInput(PC, EKeys::N, "n");
        Request_CheckLetterInput(PC, EKeys::O, "o"); Request_CheckLetterInput(PC, EKeys::P, "p");
        Request_CheckLetterInput(PC, EKeys::Q, "q"); Request_CheckLetterInput(PC, EKeys::R, "r");
        Request_CheckLetterInput(PC, EKeys::S, "s"); Request_CheckLetterInput(PC, EKeys::T, "t");
        Request_CheckLetterInput(PC, EKeys::U, "u"); Request_CheckLetterInput(PC, EKeys::V, "v");
        Request_CheckLetterInput(PC, EKeys::W, "w"); Request_CheckLetterInput(PC, EKeys::X, "x");
        Request_CheckLetterInput(PC, EKeys::Y, "y"); Request_CheckLetterInput(PC, EKeys::Z, "z");
        Request_CheckLetterInput(PC, EKeys::SpaceBar, " ");
    }

    void Tick_HandleNumberInput(APlayerController PC, int32 NumEntries)
    {
        Request_CheckNumberInput(PC, EKeys::Zero, "0", NumEntries);
        Request_CheckNumberInput(PC, EKeys::One, "1", NumEntries);
        Request_CheckNumberInput(PC, EKeys::Two, "2", NumEntries);
        Request_CheckNumberInput(PC, EKeys::Three, "3", NumEntries);
        Request_CheckNumberInput(PC, EKeys::Four, "4", NumEntries);
        Request_CheckNumberInput(PC, EKeys::Five, "5", NumEntries);
        Request_CheckNumberInput(PC, EKeys::Six, "6", NumEntries);
        Request_CheckNumberInput(PC, EKeys::Seven, "7", NumEntries);
        Request_CheckNumberInput(PC, EKeys::Eight, "8", NumEntries);
        Request_CheckNumberInput(PC, EKeys::Nine, "9", NumEntries);

        Request_CheckNumberInput(PC, EKeys::NumPadZero, "0", NumEntries);
        Request_CheckNumberInput(PC, EKeys::NumPadOne, "1", NumEntries);
        Request_CheckNumberInput(PC, EKeys::NumPadTwo, "2", NumEntries);
        Request_CheckNumberInput(PC, EKeys::NumPadThree, "3", NumEntries);
        Request_CheckNumberInput(PC, EKeys::NumPadFour, "4", NumEntries);
        Request_CheckNumberInput(PC, EKeys::NumPadFive, "5", NumEntries);
        Request_CheckNumberInput(PC, EKeys::NumPadSix, "6", NumEntries);
        Request_CheckNumberInput(PC, EKeys::NumPadSeven, "7", NumEntries);
        Request_CheckNumberInput(PC, EKeys::NumPadEight, "8", NumEntries);
        Request_CheckNumberInput(PC, EKeys::NumPadNine, "9", NumEntries);
    }

    void Tick_HandleBackspace(APlayerController PC, float DeltaTime, int32 NumEntries)
    {
        if (PC.WasInputKeyJustPressed(EKeys::BackSpace))
        {
            Request_ApplyBackspace(NumEntries);
            bBackspaceHeld = true;
            BackspaceTimer = 0.0f;
        }
        else if (bBackspaceHeld && PC.IsInputKeyDown(EKeys::BackSpace))
        {
            BackspaceTimer = BackspaceTimer + DeltaTime;
            if (BackspaceTimer >= RepeatDelay)
            {
                BackspaceTimer = BackspaceTimer - RepeatRate;
                Request_ApplyBackspace(NumEntries);
            }
        }
        else
        {
            bBackspaceHeld = false;
        }
    }

    //--------------------------------------------------------------------------------------------------------------------------
    // Rendering
    //--------------------------------------------------------------------------------------------------------------------------

    void Draw_TabHint(int32 SizeX, int32 SizeY)
    {
        auto bShowHint = Math::Fmod(CursorBlinkTimer, 2.0f) < 1.5f;
        if (bShowHint == false)
        {
            return;
        }

        DrawText(
            "Press Tab for Gym Menu",
            FLinearColor(0.5f, 0.5f, 0.5f, 0.6f),
            float(SizeX) - 280.0f, 20.0f,
            nullptr, 1.0f, false
        );
    }

    void Draw_Background(float MenuX, float MenuY, float TotalWidth, float TotalHeight)
    {
        DrawRect(FLinearColor(0.02f, 0.02f, 0.05f, 0.85f), MenuX, MenuY, TotalWidth, TotalHeight);
    }

    void Draw_Title(float MenuX, float MenuY, int32 NumEntries)
    {
        auto bShowCursor = Math::Fmod(CursorBlinkTimer, CursorBlinkRate * 2.0f) < CursorBlinkRate;
        auto Cursor = bShowCursor ? "|" : " ";
        auto CountStr = bSearchMode ? f"({FilteredIndices.Num()}/{NumEntries})" : f"({NumEntries})";

        auto TitleStr = f"GYM CYCLER {CountStr}  >  {Cursor}";
        auto TitleColor = FLinearColor(1.0f, 0.9f, 0.0f, 1.0f);

        if (InputBuffer.Len() > 0)
        {
            auto ModeLabel = bSearchMode ? "search" : "#";
            TitleStr = f"GYM CYCLER {CountStr}  {ModeLabel}> {InputBuffer}{Cursor}";
            if (Get_IsSelectionValid(NumEntries) == false)
            {
                TitleColor = FLinearColor(1.0f, 0.2f, 0.2f, 1.0f);
            }
        }

        DrawText(TitleStr, TitleColor, MenuX + PaddingX, MenuY + 12.0f, nullptr, 1.5f, false);
    }

    void Draw_Entries(float MenuX, float EntryStartY, float TotalWidth, int32 VisibleCount, int32 DisplayCount)
    {
        if (DisplayCount == 0)
        {
            DrawText("  No matches", FLinearColor(0.5f, 0.5f, 0.5f, 1.0f), MenuX + PaddingX, EntryStartY + 8.0f, nullptr, 1.0f, false);
            return;
        }

        auto CurrentGymIndex = UCk_Utils_GymRegistry_UE::Get_CurrentGymIndex();

        for (int32 row = 0; row < VisibleCount; row++)
        {
            auto ListPos = ScrollOffset + row;
            if (ListPos >= DisplayCount)
            {
                break;
            }

            auto RealIndex = bSearchMode ? FilteredIndices[ListPos] : ListPos;
            auto EntryY = EntryStartY + (float(row) * EntryHeight);
            auto IsSelected = (RealIndex == SelectedIndex);
            auto IsCurrent = (RealIndex == CurrentGymIndex);

            if (IsSelected)
            {
                DrawRect(FLinearColor(0.15f, 0.25f, 0.55f, 0.9f), MenuX + 4.0f, EntryY, TotalWidth - 8.0f - ScrollbarWidth - 8.0f, EntryHeight);
            }

            auto TextColor = IsSelected ? FLinearColor(1.0f, 1.0f, 1.0f, 1.0f) : FLinearColor(0.65f, 0.65f, 0.65f, 1.0f);
            auto Prefix = IsSelected ? ">>  " : "      ";
            auto CurrentMarker = IsCurrent ? "  *" : "";
            auto EntryText = f"{Prefix}[{RealIndex}]  {CachedRegistry[RealIndex].DisplayName}{CurrentMarker}";

            if (IsCurrent && IsSelected == false)
            {
                TextColor = FLinearColor(0.3f, 0.8f, 0.3f, 1.0f);
            }

            DrawText(EntryText, TextColor, MenuX + PaddingX, EntryY + 8.0f, nullptr, 1.0f, false);
        }
    }

    void Draw_Scrollbar(float MenuX, float EntryStartY, float TotalWidth, int32 VisibleCount, int32 DisplayCount)
    {
        // Only draw if scrolling is needed
        if (DisplayCount <= MaxVisibleEntries)
        {
            return;
        }

        auto TrackX = MenuX + TotalWidth - PaddingX - ScrollbarWidth;
        auto TrackY = EntryStartY;
        auto TrackH = float(VisibleCount) * EntryHeight;

        // Track background
        DrawRect(FLinearColor(0.15f, 0.15f, 0.2f, 0.6f), TrackX, TrackY, ScrollbarWidth, TrackH);

        // Thumb
        auto ThumbH = TrackH * (float(VisibleCount) / float(DisplayCount));
        auto MinThumbH = 16.0f;
        if (ThumbH < MinThumbH) { ThumbH = MinThumbH; }

        auto MaxScroll = DisplayCount - MaxVisibleEntries;
        auto ScrollFrac = (MaxScroll > 0) ? float(ScrollOffset) / float(MaxScroll) : 0.0f;
        auto ThumbY = TrackY + (TrackH - ThumbH) * ScrollFrac;

        DrawRect(FLinearColor(0.55f, 0.6f, 0.75f, 0.9f), TrackX, ThumbY, ScrollbarWidth, ThumbH);
    }

    void Draw_Footer(float MenuX, float EntryStartY, int32 VisibleCount)
    {
        auto FooterY = EntryStartY + (float(Math::Max(VisibleCount, 1)) * EntryHeight) + 8.0f;
        DrawText(
            "Arrows/PgUp/PgDn/Home/End  |  Type: search or #index  |  Enter: select  |  Esc/Tab: close",
            FLinearColor(0.4f, 0.4f, 0.4f, 1.0f),
            MenuX + PaddingX, FooterY, nullptr, 0.7f, false
        );
    }

    //--------------------------------------------------------------------------------------------------------------------------
    // Selection / scroll helpers
    //--------------------------------------------------------------------------------------------------------------------------

    int32 Get_SelectedListPosition()
    {
        if (bSearchMode)
        {
            for (int32 f = 0; f < FilteredIndices.Num(); f++)
            {
                if (FilteredIndices[f] == SelectedIndex) { return f; }
            }
            return -1;
        }
        return SelectedIndex;
    }

    int32 Get_RealIndexFromListPos(int32 ListPos)
    {
        if (bSearchMode)
        {
            if (ListPos >= 0 && ListPos < FilteredIndices.Num())
            {
                return FilteredIndices[ListPos];
            }
            return -1;
        }
        return ListPos;
    }

    int32 Get_ActiveListCount()
    {
        return bSearchMode ? FilteredIndices.Num() : CachedRegistry.Num();
    }

    void Request_EnsureSelectedVisible(int32 InDisplayCount)
    {
        if (InDisplayCount <= MaxVisibleEntries)
        {
            ScrollOffset = 0;
            return;
        }

        auto SelectedListPos = Get_SelectedListPosition();
        if (SelectedListPos < 0)
        {
            return;
        }

        if (SelectedListPos < ScrollOffset)
        {
            ScrollOffset = SelectedListPos;
        }
        else if (SelectedListPos >= ScrollOffset + MaxVisibleEntries)
        {
            ScrollOffset = SelectedListPos - MaxVisibleEntries + 1;
        }

        auto MaxScroll = InDisplayCount - MaxVisibleEntries;
        if (ScrollOffset > MaxScroll) { ScrollOffset = MaxScroll; }
        if (ScrollOffset < 0)         { ScrollOffset = 0; }
    }

    bool Get_IsSelectionValid(int32 InNumEntries)
    {
        if (bSearchMode)
        {
            return FilteredIndices.Num() > 0 && SelectedIndex >= 0 && SelectedIndex < InNumEntries;
        }

        if (InputBuffer.Len() > 0)
        {
            auto ParsedIndex = String::Conv_StringToInt(InputBuffer);
            return ParsedIndex >= 0 && ParsedIndex < InNumEntries;
        }

        return SelectedIndex >= 0 && SelectedIndex < InNumEntries;
    }

    //--------------------------------------------------------------------------------------------------------------------------
    // Selection movement
    //--------------------------------------------------------------------------------------------------------------------------

    void Request_MoveSelection(int32 InDirection, int32 InNumEntries)
    {
        auto ActiveCount = Get_ActiveListCount();
        if (ActiveCount == 0)
        {
            return;
        }

        auto Pos = Get_SelectedListPosition();
        if (Pos < 0) { Pos = 0; }

        Pos = Pos + InDirection;
        if (Pos >= ActiveCount) { Pos = 0; }
        else if (Pos < 0)       { Pos = ActiveCount - 1; }

        SelectedIndex = Get_RealIndexFromListPos(Pos);
    }

    void Request_MoveSelectionByPage(int32 InDelta, int32 InNumEntries)
    {
        auto ActiveCount = Get_ActiveListCount();
        if (ActiveCount == 0)
        {
            return;
        }

        auto Pos = Get_SelectedListPosition();
        if (Pos < 0) { Pos = 0; }

        Pos = Pos + InDelta;
        if (Pos < 0)             { Pos = 0; }
        if (Pos >= ActiveCount)  { Pos = ActiveCount - 1; }

        SelectedIndex = Get_RealIndexFromListPos(Pos);
    }

    void Request_JumpToFirst()
    {
        if (Get_ActiveListCount() == 0) { return; }
        SelectedIndex = Get_RealIndexFromListPos(0);
    }

    void Request_JumpToLast()
    {
        auto ActiveCount = Get_ActiveListCount();
        if (ActiveCount == 0) { return; }
        SelectedIndex = Get_RealIndexFromListPos(ActiveCount - 1);
    }

    //--------------------------------------------------------------------------------------------------------------------------
    // Input buffer / search filter
    //--------------------------------------------------------------------------------------------------------------------------

    void Request_AppendLetter(FString InChar)
    {
        if (bSearchMode == false && InputBuffer.Len() == 0)
        {
            bSearchMode = true;
        }

        if (bSearchMode)
        {
            InputBuffer = f"{InputBuffer}{InChar}";
            Request_UpdateSearchFilter(CachedRegistry.Num());
        }
    }

    void Request_AppendDigit(FString InDigit, int32 InNumEntries)
    {
        InputBuffer = f"{InputBuffer}{InDigit}";
        auto ParsedIndex = String::Conv_StringToInt(InputBuffer);
        if (ParsedIndex >= 0 && ParsedIndex < InNumEntries)
        {
            SelectedIndex = ParsedIndex;
        }
    }

    void Request_ApplyBackspace(int32 InNumEntries)
    {
        if (InputBuffer.Len() == 0)
        {
            return;
        }

        bHasHeldChar = false;
        InputBuffer = InputBuffer.LeftChop(1);

        if (InputBuffer.Len() == 0)
        {
            Request_ClearInput();
        }
        else if (bSearchMode)
        {
            Request_UpdateSearchFilter(InNumEntries);
        }
        else
        {
            auto ParsedIndex = String::Conv_StringToInt(InputBuffer);
            if (ParsedIndex >= 0 && ParsedIndex < InNumEntries)
            {
                SelectedIndex = ParsedIndex;
            }
        }
    }

    void Request_CheckLetterInput(APlayerController PC, FKey InKey, FString InChar)
    {
        if (PC.WasInputKeyJustPressed(InKey))
        {
            Request_AppendLetter(InChar);
            HeldCharKey = InKey;
            HeldChar = InChar;
            bHeldCharIsLetter = true;
            bHasHeldChar = true;
            HeldCharTimer = 0.0f;
        }
    }

    void Request_CheckNumberInput(APlayerController PC, FKey InKey, FString InDigit, int32 InNumEntries)
    {
        if (PC.WasInputKeyJustPressed(InKey))
        {
            Request_AppendDigit(InDigit, InNumEntries);
            HeldCharKey = InKey;
            HeldChar = InDigit;
            bHeldCharIsLetter = false;
            bHasHeldChar = true;
            HeldCharTimer = 0.0f;
        }
    }

    void Request_ProcessHeldChar(APlayerController PC, float DeltaTime, int32 InNumEntries)
    {
        if (bHasHeldChar == false)
        {
            return;
        }

        if (PC.IsInputKeyDown(HeldCharKey) == false)
        {
            bHasHeldChar = false;
            HeldCharTimer = 0.0f;
            return;
        }

        HeldCharTimer = HeldCharTimer + DeltaTime;
        if (HeldCharTimer >= RepeatDelay)
        {
            HeldCharTimer = HeldCharTimer - RepeatRate;
            if (bHeldCharIsLetter) { Request_AppendLetter(HeldChar); }
            else                   { Request_AppendDigit(HeldChar, InNumEntries); }
        }
    }

    void Request_UpdateSearchFilter(int32 InNumEntries)
    {
        FilteredIndices.Empty();
        auto SearchLower = InputBuffer.ToLower();

        for (int32 i = 0; i < InNumEntries; i++)
        {
            auto NameLower = CachedRegistry[i].DisplayName.ToLower();
            if (NameLower.Contains(SearchLower))
            {
                FilteredIndices.Add(i);
            }
        }

        if (FilteredIndices.Num() > 0)
        {
            SelectedIndex = FilteredIndices[0];
        }

        ScrollOffset = 0;
    }
}
