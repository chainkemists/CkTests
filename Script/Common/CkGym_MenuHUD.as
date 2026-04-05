class ACkGym_MenuHUD : AHUD
{
    TArray<FCkGym_Entry> CachedRegistry;
    bool bMenuVisible = false;
    int32 SelectedIndex = 0;

    // Input buffer (numbers or text search)
    FString InputBuffer = "";
    bool bSearchMode = false;

    // Filtered indices when searching by name
    TArray<int32> FilteredIndices;

    // Cursor blink
    float CursorBlinkTimer = 0.0f;
    float CursorBlinkRate = 0.5f;

    // Key repeat
    float RepeatDelay = 0.35f;
    float RepeatRate = 0.08f;
    float HeldTimer = 0.0f;
    int32 HeldDirection = 0;

    // Layout
    float EntryHeight = 36.0f;
    float EntryWidth = 460.0f;
    float TitleHeight = 48.0f;
    float PaddingX = 24.0f;
    float PaddingY = 16.0f;

    void Request_ShowMenu()
    {
        CachedRegistry = CkGym_Cycler::Get_GymRegistry();
        bMenuVisible = true;
        InputBuffer = "";
        bSearchMode = false;
        HeldDirection = 0;
        HeldTimer = 0.0f;
        FilteredIndices.Empty();

        // Start with current gym selected
        auto Subsystem = UCkGym_CyclerSubsystem::Get();
        if (Subsystem.CurrentGymIndex >= 0 && Subsystem.CurrentGymIndex < CachedRegistry.Num())
        {
            SelectedIndex = Subsystem.CurrentGymIndex;
        }
        else
        {
            SelectedIndex = 0;
        }
    }

    void Request_ToggleMenu()
    {
        if (bMenuVisible)
        {
            bMenuVisible = false;
        }
        else
        {
            Request_ShowMenu();
        }
    }

    void Request_ClearInput()
    {
        InputBuffer = "";
        bSearchMode = false;
        FilteredIndices.Empty();
    }

    UFUNCTION(BlueprintOverride)
    void DrawHUD(int32 SizeX, int32 SizeY)
    {
        auto PC = GetOwningPlayerController();
        auto DeltaTime = GetWorld().GetDeltaSeconds();

        // Toggle menu with Tab (works in any gym)
        if (ck::IsValid(PC) && PC.WasInputKeyJustPressed(EKeys::Tab))
        {
            Request_ToggleMenu();
        }

        // Tab hint when menu is closed
        if (bMenuVisible == false)
        {
            CursorBlinkTimer = CursorBlinkTimer + DeltaTime;
            auto bShowHint = Math::Fmod(CursorBlinkTimer, 2.0f) < 1.5f;
            if (bShowHint)
            {
                DrawText(
                    "Press Tab for Gym Menu",
                    FLinearColor(0.5f, 0.5f, 0.5f, 0.6f),
                    float(SizeX) - 280.0f, float(SizeY) - 40.0f,
                    nullptr, 1.0f, false
                );
            }
            return;
        }

        if (CachedRegistry.Num() == 0)
        {
            return;
        }

        auto NumEntries = CachedRegistry.Num();
        auto CurrentGymIndex = UCkGym_CyclerSubsystem::Get().CurrentGymIndex;

        // Handle keyboard input
        if (ck::IsValid(PC))
        {
            auto bDownHeld = PC.IsInputKeyDown(EKeys::Down);
            auto bUpHeld = PC.IsInputKeyDown(EKeys::Up);

            // Arrow navigation
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

            // Letter input → search mode
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

            // Number input (only in non-search mode)
            if (bSearchMode == false)
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
            }

            // Backspace
            if (PC.WasInputKeyJustPressed(EKeys::BackSpace) && InputBuffer.Len() > 0)
            {
                InputBuffer = InputBuffer.LeftChop(1);
                if (InputBuffer.Len() == 0)
                {
                    Request_ClearInput();
                }
                else if (bSearchMode)
                {
                    Request_UpdateSearchFilter(NumEntries);
                }
                else
                {
                    auto ParsedIndex = String::Conv_StringToInt(InputBuffer);
                    if (ParsedIndex >= 0 && ParsedIndex < NumEntries)
                    {
                        SelectedIndex = ParsedIndex;
                    }
                }
            }

            // Enter confirms selection
            if (PC.WasInputKeyJustPressed(EKeys::Enter))
            {
                if (Get_IsSelectionValid(NumEntries))
                {
                    bMenuVisible = false;
                    CkGym_Cycler::Request_TravelToGym(SelectedIndex);
                    return;
                }
            }

            if (PC.WasInputKeyJustPressed(EKeys::Escape))
            {
                if (InputBuffer.Len() > 0)
                {
                    Request_ClearInput();
                }
                else
                {
                    bMenuVisible = false;
                }
                return;
            }

            // Arrow keys clear number input (but keep search filter active)
            if (bSearchMode == false && (PC.WasInputKeyJustPressed(EKeys::Up) || PC.WasInputKeyJustPressed(EKeys::Down)))
            {
                Request_ClearInput();
            }
        }

        // Layout
        auto DisplayCount = bSearchMode ? FilteredIndices.Num() : NumEntries;
        auto TotalHeight = TitleHeight + PaddingY + (float(Math::Max(DisplayCount, 1)) * EntryHeight) + PaddingY + 24.0f;
        auto TotalWidth = EntryWidth + PaddingX * 2.0f;
        auto MenuX = (float(SizeX) - TotalWidth) * 0.5f;
        auto MenuY = (float(SizeY) - TotalHeight) * 0.5f;

        // Background
        DrawRect(FLinearColor(0.02f, 0.02f, 0.05f, 0.85f), MenuX, MenuY, TotalWidth, TotalHeight);

        // Title + input display with blinking cursor
        CursorBlinkTimer = CursorBlinkTimer + DeltaTime;
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

        // Entries
        auto EntryStartY = MenuY + TitleHeight + PaddingY;

        if (bSearchMode)
        {
            // Show only filtered results
            if (FilteredIndices.Num() == 0)
            {
                DrawText("  No matches", FLinearColor(0.5f, 0.5f, 0.5f, 1.0f), MenuX + PaddingX, EntryStartY + 8.0f, nullptr, 1.0f, false);
            }
            else
            {
                for (int32 f = 0; f < FilteredIndices.Num(); f++)
                {
                    auto RealIndex = FilteredIndices[f];
                    auto EntryY = EntryStartY + (float(f) * EntryHeight);
                    auto IsSelected = (RealIndex == SelectedIndex);
                    auto IsCurrent = (RealIndex == CurrentGymIndex);

                    if (IsSelected)
                    {
                        DrawRect(FLinearColor(0.15f, 0.25f, 0.55f, 0.9f), MenuX + 4.0f, EntryY, TotalWidth - 8.0f, EntryHeight);
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
        }
        else
        {
            // Show full list
            for (int32 i = 0; i < NumEntries; i++)
            {
                auto EntryY = EntryStartY + (float(i) * EntryHeight);
                auto IsSelected = (i == SelectedIndex);
                auto IsCurrent = (i == CurrentGymIndex);

                if (IsSelected)
                {
                    DrawRect(FLinearColor(0.15f, 0.25f, 0.55f, 0.9f), MenuX + 4.0f, EntryY, TotalWidth - 8.0f, EntryHeight);
                }

                auto TextColor = IsSelected ? FLinearColor(1.0f, 1.0f, 1.0f, 1.0f) : FLinearColor(0.65f, 0.65f, 0.65f, 1.0f);
                auto Prefix = IsSelected ? ">>  " : "      ";
                auto CurrentMarker = IsCurrent ? "  *" : "";
                auto EntryText = f"{Prefix}[{i}]  {CachedRegistry[i].DisplayName}{CurrentMarker}";

                if (IsCurrent && IsSelected == false)
                {
                    TextColor = FLinearColor(0.3f, 0.8f, 0.3f, 1.0f);
                }

                DrawText(EntryText, TextColor, MenuX + PaddingX, EntryY + 8.0f, nullptr, 1.0f, false);
            }
        }

        // Footer
        auto FooterY = EntryStartY + (float(Math::Max(DisplayCount, 1)) * EntryHeight) + 8.0f;
        DrawText("Arrows: navigate  |  Type: search or #index  |  Enter: select  |  Esc/Tab: close", FLinearColor(0.4f, 0.4f, 0.4f, 1.0f), MenuX + PaddingX, FooterY, nullptr, 0.7f, false);
    }

    //--------------------------------------------------------------------------------------------------------------------------
    // Helpers
    //--------------------------------------------------------------------------------------------------------------------------

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

    void Request_CheckLetterInput(APlayerController PC, FKey InKey, FString InChar)
    {
        if (PC.WasInputKeyJustPressed(InKey))
        {
            // First letter switches to search mode
            if (bSearchMode == false && InputBuffer.Len() == 0)
            {
                bSearchMode = true;
            }

            // Only add if we're in search mode (ignore letters if already typing numbers)
            if (bSearchMode)
            {
                InputBuffer = f"{InputBuffer}{InChar}";
                Request_UpdateSearchFilter(CachedRegistry.Num());
            }
        }
    }

    void Request_CheckNumberInput(APlayerController PC, FKey InKey, FString InDigit, int32 InNumEntries)
    {
        if (PC.WasInputKeyJustPressed(InKey))
        {
            InputBuffer = f"{InputBuffer}{InDigit}";
            auto ParsedIndex = String::Conv_StringToInt(InputBuffer);
            if (ParsedIndex >= 0 && ParsedIndex < InNumEntries)
            {
                SelectedIndex = ParsedIndex;
            }
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

        // Auto-select first match
        if (FilteredIndices.Num() > 0)
        {
            SelectedIndex = FilteredIndices[0];
        }
    }

    void Request_MoveSelection(int32 InDirection, int32 InNumEntries)
    {
        if (bSearchMode && FilteredIndices.Num() > 0)
        {
            // Navigate within filtered results
            int32 CurrentFilterPos = -1;
            for (int32 f = 0; f < FilteredIndices.Num(); f++)
            {
                if (FilteredIndices[f] == SelectedIndex)
                {
                    CurrentFilterPos = f;
                    break;
                }
            }
            if (CurrentFilterPos < 0)
            {
                CurrentFilterPos = 0;
            }
            CurrentFilterPos = CurrentFilterPos + InDirection;
            if (CurrentFilterPos >= FilteredIndices.Num())
            {
                CurrentFilterPos = 0;
            }
            else if (CurrentFilterPos < 0)
            {
                CurrentFilterPos = FilteredIndices.Num() - 1;
            }
            SelectedIndex = FilteredIndices[CurrentFilterPos];
        }
        else
        {
            SelectedIndex = SelectedIndex + InDirection;
            if (SelectedIndex >= InNumEntries)
            {
                SelectedIndex = 0;
            }
            else if (SelectedIndex < 0)
            {
                SelectedIndex = InNumEntries - 1;
            }
        }
    }
}
