--[[
  Render Markdown headings as Awesome-CV section headings.

  Awesome-CV names its heading commands \cvsection and \cvsubsection, leaving
  LaTeX's own \section alone. Bridging that here rather than by redefining
  \section in awesome-cv.cls keeps the class a near-verbatim copy of upstream,
  and leaves \section meaning what it usually does in raw LaTeX.

  Only levels 1 and 2 are remapped, because those are the only two the class
  styles. Level 3 and below fall through to the article class's own
  \subsubsection.
]]

local function raw(s)
  return pandoc.RawInline("latex", s)
end

function Header(el)
  if not FORMAT:match("latex") then
    return nil
  end

  local cmd
  if el.level == 1 then
    cmd = "\\cvsection"
  elseif el.level == 2 then
    cmd = "\\cvsubsection"
  else
    return nil
  end

  -- Build the call around the heading's inlines rather than stringifying them,
  -- so emphasis, links and inline code in a heading survive.
  local inlines = pandoc.List({ raw(cmd .. "{") })
  inlines:extend(el.content)
  inlines:insert(raw("}"))

  -- \cvsection issues \phantomsection, so a \label placed after it resolves to
  -- the right page for \ref and for cross-references such as @sec-education.
  if el.identifier and el.identifier ~= "" then
    inlines:insert(raw("\\label{" .. el.identifier .. "}"))
  end

  return pandoc.Plain(inlines)
end
