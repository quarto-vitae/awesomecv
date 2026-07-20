--[[
  Render Markdown headings as Awesome-CV section headings.

  Awesome-CV names its heading commands \cvsection and \cvsubsection, leaving
  LaTeX's own \section alone. Bridging that here rather than by redefining
  \section in awesome-cv.cls keeps the class a near-verbatim copy of upstream,
  and leaves \section meaning what it usually does in raw LaTeX.

  Only levels 1 and 2 are remapped, because those are the only two the class
  styles. Level 3 and below fall through to the article class's own
  \subsubsection.

  In a cover letter the class offers \lettersection instead, sized to sit in
  running text rather than to open a page of listings, so top-level headings go
  there. Which of the two documents is being written is read from the
  `awesomecv-letter` metadata set by the letter format in _extension.yml.
]]

local function raw(s)
  return pandoc.RawInline("latex", s)
end

local function heading_command(level, letter)
  if level == 1 then
    -- \lettersection takes its argument the same way \cvsection does, and
    -- likewise issues \phantomsection, so the \label below still resolves.
    return letter and "\\lettersection" or "\\cvsection"
  elseif level == 2 then
    return "\\cvsubsection"
  end
end

local function rewrite_header(letter)
  return function(el)
    local cmd = heading_command(el.level, letter)
    if not cmd then
      return nil
    end

    -- Build the call around the heading's inlines rather than stringifying
    -- them, so emphasis, links and inline code in a heading survive.
    local inlines = pandoc.List({ raw(cmd .. "{") })
    inlines:extend(el.content)
    inlines:insert(raw("}"))

    -- The section commands issue \phantomsection, so a \label placed after one
    -- resolves to the right page for \ref and for cross-references such as
    -- @sec-education.
    if el.identifier and el.identifier ~= "" then
      inlines:insert(raw("\\label{" .. el.identifier .. "}"))
    end

    return pandoc.Plain(inlines)
  end
end

-- The whole document is walked from here rather than by defining a top-level
-- Header function, because the metadata saying which format this is must be
-- read before any heading is rewritten, and Pandoc walks Meta *after* blocks.
function Pandoc(doc)
  if not FORMAT:match("latex") then
    return nil
  end

  local letter = doc.meta["awesomecv-letter"] == true
  return doc:walk({ Header = rewrite_header(letter) })
end
