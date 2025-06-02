--!strict

local packages = script.Parent.roblox_packages;
local IDialogueContentFitter = require(packages.dialogue_content_fitter_types);
local IEffect = require(packages.effect_types);

type DialogueContentFitter = IDialogueContentFitter.DialogueContentFitter;
type Page = IEffect.Page;
type RichTextTag = IDialogueContentFitter.RichTextTag;

local DialogueContentFitter = {};

function DialogueContentFitter.new(contentContainer: GuiObject, textLabel: TextLabel): DialogueContentFitter

  textLabel = textLabel:Clone();
  textLabel.AutomaticSize = Enum.AutomaticSize.XY;
  textLabel.Size = UDim2.fromScale(0, 0);
  textLabel.MaxVisibleGraphemes = -1;

  local contentContainerParent = contentContainer.Parent;
  contentContainer = contentContainer:Clone();
  contentContainer.Visible = false;

  local function getPages(self: DialogueContentFitter, rawPage: Page): {Page}

    -- We clone the content container to avoid race conditions.
    local contentContainer = self.contentContainer:Clone();
    contentContainer.Parent = contentContainerParent;

    local pages: {Page} = {{}};

    DialogueContentFitter:cleanContentContainer(contentContainer);

    for _, rawComponent in rawPage do

      if typeof(rawComponent) == "string" then 

        contentContainer, pages = DialogueContentFitter:fitText(rawComponent, contentContainer, textLabel, pages);

      else

        contentContainer, pages = rawComponent:fit(contentContainer, textLabel, pages);

      end;

    end

    contentContainer:Destroy();

    return pages;

  end;

  local dialogueContentFitter: DialogueContentFitter = {
    contentContainer = contentContainer;
    textLabel = textLabel;
    getPages = getPages;
  };

  return dialogueContentFitter;

end;

function DialogueContentFitter:cleanContentContainer(contentContainer: GuiObject): ()

  for _, child in contentContainer:GetChildren() do

    if child:IsA("GuiObject") then

      child:Destroy();

    end;

  end

end;

function DialogueContentFitter:clonePages(pages: {Page}): {Page}

  local clonedPages: {Page} = {};
  for _, page in pages do

    local clonedPage: Page = {};
    for _, component in page do

      if typeof(component) == "string" then

        table.insert(clonedPage, component);

      else

        table.insert(clonedPage, table.clone(component));

      end

    end;

    table.insert(clonedPages, clonedPage);

  end;

  return clonedPages;

end;

function DialogueContentFitter:getRichTextTags(text: string): {RichTextTag}

  local richTextTagIndices: {RichTextTag} = {};
  local openTagIndices: {number} = {};
  local textCopy = text;
  local tagPattern = "<[^<>]->";
  local pointer = 1;
  for tag in textCopy:gmatch(tagPattern) do

    -- Get the tag name and attributes.
    local tagText = tag:match("<([^<>]-)>");
    if tagText then

      local firstSpaceIndex = tagText:find(" ");
      local tagTextLength = tagText:len();
      local name = tagText:sub(1, (firstSpaceIndex and firstSpaceIndex - 1) or tagTextLength);
      if name:sub(1, 1) == "/" then

        for _, index in openTagIndices do

          if richTextTagIndices[index].name == name:sub(2) then

            -- Add a tag end offset.
            local _, endOffset = textCopy:find(tagPattern);
            if endOffset then

              richTextTagIndices[index].endOffset = pointer + endOffset;

            end;

            -- Remove the tag from the open tag table.
            table.remove(openTagIndices, index);
            break;

          end

        end

      else

        -- Get the tag start offset.
        local attributes = firstSpaceIndex and tagText:sub(firstSpaceIndex + 1) or "";
        table.insert(richTextTagIndices, {
          name = name;
          attributes = attributes;
          startOffset = textCopy:find(tagPattern) :: number + pointer - 1;
        });
        table.insert(openTagIndices, #richTextTagIndices);

      end

      -- Remove the tag from our copy.
      local _, pointerUpdate = textCopy:find(tagPattern);
      if pointerUpdate then

        pointer += pointerUpdate - 1;
        textCopy = textCopy:sub(pointerUpdate);

      end;

    end;

  end

  return richTextTagIndices;

end;

function DialogueContentFitter:getLineBreakIndices(textLabel: TextLabel): {number}

  -- Iterate through each character.
  local breakpoints: {number} = {};
  local lastSpaceIndex: number = 1;
  local skipCounter = 0;
  local originalText = textLabel.Text;
  local remainingRichTextTags = self:getRichTextTags(originalText);
  textLabel.Text = "";

  for index, character in originalText:split("") do

    -- Check if this is an offset.
    if skipCounter > 0 then

      skipCounter -= 1;
      continue;

    end

    if textLabel.RichText then

      for _, richTextTagIndex in remainingRichTextTags do

        if richTextTagIndex.startOffset == index then

          skipCounter = (`<{richTextTagIndex.name}{if richTextTagIndex.attributes and richTextTagIndex.attributes ~= "" then ` {richTextTagIndex.attributes}` else ""}>`):len() - 1;
          break;

        elseif richTextTagIndex.endOffset :: number - (`</{richTextTagIndex.name}>`):len() == index then

          skipCounter = (`</{richTextTagIndex.name}>`):len() - 1;
          break;

        end

      end

    end;

    if skipCounter > 0 then

      continue;

    end

    -- Keep track of spaces.
    if character == " " then

      lastSpaceIndex = index;

    end

    -- Keep track of the original text bounds.
    local originalTextBounds = textLabel.TextBounds;

    -- Add a character and reformat the text.
    textLabel.Text = textLabel.ContentText .. character;
    if textLabel.RichText then

      for _, richTextTagInfo in remainingRichTextTags do

        local tagStartOffset = richTextTagInfo.startOffset;
        local tagEndOffset = richTextTagInfo.endOffset :: number;
        if index >= tagStartOffset and tagEndOffset > (breakpoints[#breakpoints] or 0) then

          local prefix = `<{richTextTagInfo.name}{if richTextTagInfo.attributes and richTextTagInfo.attributes ~= "" then ` {richTextTagInfo.attributes}` else ""}>`;
          local suffix = `</{richTextTagInfo.name}>`;
          local startOffset = tagStartOffset - (breakpoints[#breakpoints] or 0);
          local endOffset = (tagEndOffset - (breakpoints[#breakpoints] or 0)) - prefix:len() - suffix:len();
          textLabel.Text = textLabel.ContentText:sub(1, startOffset - 1) .. prefix .. textLabel.ContentText:sub(startOffset, endOffset - 1) .. suffix .. textLabel.ContentText:sub(endOffset);

        end

      end

    end;

    if textLabel.TextBounds.Y ~= originalTextBounds.Y then

      textLabel.TextWrapped = false;
      textLabel.TextWrapped = true;

    end

    -- From here, we can guess for a line break because the Y axis of 
    -- the UIListLayout's content size will change if the character causes a line break.
    if textLabel.TextBounds.Y > originalTextBounds.Y then

      -- We should check again with unwrapped text to ensure that 
      -- rich text didn't cause the line break.
      local wrappedTextBounds = textLabel.TextBounds;

      textLabel.TextWrapped = false;

      if textLabel.TextBounds.Y < wrappedTextBounds.Y then

        table.insert(breakpoints, lastSpaceIndex);
        textLabel.Text = originalText:sub(lastSpaceIndex + 1, index);

      end

      textLabel.TextWrapped = true;

    end

  end

  textLabel.Text = originalText;

  return breakpoints;

end

function DialogueContentFitter:fitText(text: string, contentContainer: GuiObject, textLabelTemplate: TextLabel, pages: {Page}): (GuiObject, {Page})

  pages = self:clonePages(pages);
  local uiListLayout = contentContainer:FindFirstChildOfClass("UIListLayout");
  assert(uiListLayout, "[Dialogue Maker] Content container must have a UIListLayout to fit text.");

  -- Fit the text into the content container.
  local canCreateUISizeConstraint = true;
  local remainingText: string = text;

  repeat

    local textLabel = textLabelTemplate:Clone();
    textLabel.Visible = true;
    textLabel.Text = "";
    textLabel.Parent = contentContainer;

    -- Constrain the text label if there is another UI element to the left of it.
    -- This ensures the text doesn't wrap in the middle of the container.
    local uiSizeConstraint: UISizeConstraint?;
    if canCreateUISizeConstraint and textLabel.AbsolutePosition.X > contentContainer.AbsolutePosition.X then

      textLabel.TextWrapped = false;

      local newUISizeConstraint = Instance.new("UISizeConstraint");
      newUISizeConstraint.Name = "NewLineConstraint";
      newUISizeConstraint.MaxSize = Vector2.new(contentContainer.AbsoluteSize.X - (textLabel.AbsolutePosition.X - contentContainer.AbsolutePosition.X), math.huge);
      newUISizeConstraint.Parent = textLabel;
      uiSizeConstraint = newUISizeConstraint;

    else
      
      if not canCreateUISizeConstraint then

        canCreateUISizeConstraint = true;

      end;

      textLabel.TextWrapped = true;

    end;
    
    textLabel.Text = remainingText;

    -- If the text label fits, then we have enough components and pages.
    if textLabel.TextFits and uiListLayout.AbsoluteContentSize.Y <= contentContainer.AbsoluteSize.Y then

      remainingText = "";

    else

      -- Remove a word from the text until the text fits.
      local lastSpaceIndex = 0;
      local shouldCreateNewPage = false;
      repeat

        local _, newLastSpaceIndex = textLabel.Text:find(".* ");

        if newLastSpaceIndex then

          lastSpaceIndex = newLastSpaceIndex;
          textLabel.Text = textLabel.Text:sub(1, lastSpaceIndex - 1);

        elseif uiSizeConstraint then
          
          canCreateUISizeConstraint = false;
          textLabel:Destroy();

        elseif uiListLayout.AbsoluteContentSize.Y > contentContainer.AbsoluteSize.Y then

          shouldCreateNewPage = true;

        else

          error("[Dialogue Maker] Unable to fit text in container even after removing the spaces. The text might be too big or the text container might be too small.");

        end;

      until (textLabel.TextFits and uiListLayout.AbsoluteContentSize.Y <= contentContainer.AbsoluteSize.Y) or shouldCreateNewPage or not canCreateUISizeConstraint;

      -- If needed, try again without the UISizeConstraint so the text can use a new line.
      if not canCreateUISizeConstraint then

        continue;

      end;

      if shouldCreateNewPage then

        -- The text still doesn't fit, so we need to create a new page.
        table.insert(pages, {});
        self:cleanContentContainer(contentContainer);
        continue;

      end;

      -- Save the unused text for the next component.
      remainingText = remainingText:sub(lastSpaceIndex + 1);

    end;

    -- If the text has multiple lines, create another TextLabel to replace the last line of text.
    -- This allows inlined components. Remember how we used the UISizeConstraint to limit the text width?
    local lineBreaks = DialogueContentFitter:getLineBreakIndices(textLabel);
    local lastLineBreakIndex = lineBreaks[#lineBreaks];

    local function addLineHeight(textLabel: TextLabel)

      local lineHeightConstraint = Instance.new("UISizeConstraint");
      lineHeightConstraint.Name = "LineHeightConstraint";
      lineHeightConstraint.MinSize = Vector2.new(0, (#lineBreaks + 1) * textLabel.LineHeight * textLabel.TextSize);
      lineHeightConstraint.Parent = textLabel;

    end;

    if lastLineBreakIndex then

      local paragraphTextLabel = textLabel:Clone();
      paragraphTextLabel.Text = textLabel.Text:sub(1, lastLineBreakIndex);
      paragraphTextLabel.Parent = textLabel.Parent;
      addLineHeight(paragraphTextLabel);
      table.insert(pages[#pages], paragraphTextLabel.Text);

      -- Put the remaining text in the original TextLabel.
      textLabel.Text = textLabel.Text:sub(lastLineBreakIndex + 1);

    end;

    addLineHeight(textLabel);
    table.insert(pages[#pages], textLabel.Text);

  until remainingText == "";

  return contentContainer, pages;

end;

return DialogueContentFitter;