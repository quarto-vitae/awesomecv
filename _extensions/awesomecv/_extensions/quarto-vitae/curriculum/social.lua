--- Normalising the `social` front matter into one shape for every template.
---
--- An author lists contact details by service name, written the way that
--- service itself writes them:
---
---   social:
---     - email: marie.curie@example.org
---     - github: mcurie
---     - mastodon: "@mcurie@fosstodon.org"
---     - custom:
---         - icon: flask
---           text: "[Curie Laboratory](https://curie.fr)"
---
--- This module replaces that list with one whose every item has the same
--- fields (`service`, `title`, `icon`, `url`, `label`, `handle`, `is`, and the
--- service's own parts), so a template renders the whole header with one loop
--- and knows nothing about any particular service. The defaults here (icons,
--- link formats, labels) are only defaults: a template overrides them with
--- pandoc's own `$if(social.is.<service>)$` conditionals.
---
--- A list is the primary form because pandoc sorts YAML map keys, so only a
--- list preserves the order the author wrote. A map is accepted too, and is put
--- in the order of SERVICES below.

local M = {}

--------------------------------------------------------------------------------
-- String helpers
--------------------------------------------------------------------------------

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function strip_at(s)
  return (s:gsub("^@", ""))
end

local function has_scheme(s)
  return s:match("^%a[%w+.-]*:") ~= nil
end

--- `https://www.github.com/mcurie/` -> `github.com/mcurie`, for comparing a
--- URL the author gave against the base URL a service is known by.
local function normalise_url(s)
  s = s:gsub("^%a[%w+.-]*://", ""):gsub("^www%.", ""):gsub("/+$", "")
  return s
end

--- Keep only what a `tel:` or `wa.me` link may carry: digits and a leading +.
local function dial_digits(s)
  local plus = s:match("^%s*%+") and "+" or ""
  return plus .. s:gsub("%D", "")
end

--------------------------------------------------------------------------------
-- Service registry
--
-- Each service maps a handle to its parts:
--   parse(handle) -> { url = string|nil, label = string|nil, parts = {...} }
-- `label` nil means the label is the value exactly as the author wrote it,
-- markdown included. `from_url(url)` recovers a handle from a full profile URL,
-- returning nil when the URL is not one of this service's.
--------------------------------------------------------------------------------

--- A service whose profile URL is a fixed base followed by the handle, which
--- is most of them. The handle loses a leading @, since authors write
--- `@mcurie` and `mcurie` interchangeably.
local function profile(title, icon, base)
  local prefix = normalise_url(base)
  return {
    title = title,
    icon = icon,
    parse = function(h)
      h = strip_at(h)
      return { url = base .. h, label = h, handle = h }
    end,
    from_url = function(u)
      local rest = normalise_url(u)
      if rest:sub(1, #prefix) ~= prefix then return nil end
      rest = rest:sub(#prefix + 1)
      -- `github.com` must not claim `github.community/…`: after a base that
      -- ends in a name, the handle starts at a new path segment.
      if prefix:match("[%w]$") then
        rest = rest:match("^/(.*)$")
        if not rest then return nil end
      end
      return rest:match("^@?([^/?#]+)")
    end,
  }
end

--- Ordered: this is the order a map-form `social` is rendered in.
local SERVICES = {
  { "address", {
    title = "Address", icon = "location-dot",
    parse = function(h) return { handle = h } end,
  } },
  { "phone", {
    title = "Phone", icon = "phone",
    parse = function(h) return { url = "tel:" .. dial_digits(h), handle = h } end,
    from_url = function(u) return u:match("^tel:(.+)$") end,
  } },
  { "email", {
    title = "Email", icon = "envelope",
    parse = function(h) return { url = "mailto:" .. h, handle = h } end,
    from_url = function(u) return u:match("^mailto:(.+)$") end,
  } },
  { "website", {
    title = "Website", icon = "globe",
    parse = function(h)
      local url = has_scheme(h) and h or ("https://" .. h)
      local label = h:gsub("^%a[%w+.-]*://", ""):gsub("/+$", "")
      return { url = url, label = label, handle = h }
    end,
    -- Any URL is a website, so the URL is the handle as given.
    from_url = function(u) return u end,
  } },
  { "whatsapp", {
    title = "WhatsApp", icon = "whatsapp",
    parse = function(h)
      return { url = "https://wa.me/" .. dial_digits(h):gsub("^%+", ""), handle = h }
    end,
  } },
  { "telegram", profile("Telegram", "telegram", "https://t.me/") },
  { "skype", {
    title = "Skype", icon = "skype",
    parse = function(h) return { url = "skype:" .. h .. "?chat", label = h, handle = h } end,
  } },
  { "orcid", profile("ORCID", "orcid", "https://orcid.org/") },
  { "googlescholar", {
    title = "Google Scholar", icon = "google-scholar",
    -- A profile id is meaningless to a reader, so the label names the service.
    parse = function(h)
      return {
        url = "https://scholar.google.com/citations?user=" .. h,
        label = "Google Scholar", handle = h, parts = { id = h },
      }
    end,
    from_url = function(u)
      if not normalise_url(u):match("^scholar%.google%.") then return nil end
      return u:match("[?&]user=([^&#]+)")
    end,
  } },
  { "researchgate", profile("ResearchGate", "researchgate", "https://www.researchgate.net/profile/") },
  { "github", profile("GitHub", "github", "https://github.com/") },
  { "gitlab", profile("GitLab", "gitlab", "https://gitlab.com/") },
  { "bitbucket", profile("Bitbucket", "bitbucket", "https://bitbucket.org/") },
  { "stackoverflow", {
    title = "Stack Overflow", icon = "stack-overflow",
    -- Profiles are addressed by number; the name after it is cosmetic and
    -- optional, so `123456` and `123456/marie-curie` both work.
    parse = function(h)
      local id, slug = h:match("^(%d+)/?([^/]*)$")
      if not id then
        quarto.log.warning(
          "vitae: social: stackoverflow '" .. h .. "' should be the user id, " ..
          "optionally with the profile name, such as 123456/marie-curie")
        return { url = "https://stackoverflow.com/users/" .. h, label = h, handle = h }
      end
      if slug == "" then slug = nil end
      return {
        url = "https://stackoverflow.com/users/" .. id .. (slug and ("/" .. slug) or ""),
        label = slug or id, handle = h, parts = { id = id, slug = slug },
      }
    end,
    from_url = function(u)
      local rest = normalise_url(u)
      return rest:match("^stackoverflow%.com/users/(%d+/?[^/?#]*)")
    end,
  } },
  { "kaggle", profile("Kaggle", "kaggle", "https://www.kaggle.com/") },
  { "hackerrank", profile("HackerRank", "hackerrank", "https://www.hackerrank.com/profile/") },
  { "linkedin", profile("LinkedIn", "linkedin", "https://www.linkedin.com/in/") },
  { "mastodon", {
    title = "Mastodon", icon = "mastodon",
    -- Written `@user@instance`, as Mastodon itself writes it.
    parse = function(h)
      local user, instance = strip_at(h):match("^([^@]+)@(.+)$")
      if not user then
        quarto.log.warning(
          "vitae: social: mastodon '" .. h .. "' needs its instance, " ..
          "written as @user@instance, such as @mcurie@fosstodon.org")
        return { label = h, handle = h }
      end
      return {
        url = "https://" .. instance .. "/@" .. user,
        label = "@" .. user .. "@" .. instance,
        handle = h, parts = { user = user, instance = instance },
      }
    end,
    from_url = function(u)
      local instance, user = normalise_url(u):match("^([^/]+)/@([^/?#]+)$")
      return instance and ("@" .. user .. "@" .. instance) or nil
    end,
  } },
  { "bluesky", profile("Bluesky", "bluesky", "https://bsky.app/profile/") },
  { "x", profile("X", "x-twitter", "https://x.com/") },
  { "twitter", profile("Twitter", "twitter", "https://twitter.com/") },
  { "xing", profile("XING", "xing", "https://www.xing.com/profile/") },
  { "reddit", profile("Reddit", "reddit", "https://www.reddit.com/user/") },
  { "medium", profile("Medium", "medium", "https://medium.com/@") },
}

local BY_NAME, ORDER = {}, {}
for i, pair in ipairs(SERVICES) do
  BY_NAME[pair[1]] = pair[2]
  ORDER[pair[1]] = i
end
ORDER.custom = #SERVICES + 1

--- Keys an author may give in the map form of a known service.
local OVERRIDE_KEYS = { handle = true, url = true, label = true, icon = true, title = true }

--- Keys a custom entry may carry.
local CUSTOM_KEYS = { icon = true, text = true, url = true, title = true }

--------------------------------------------------------------------------------
-- Target format
--------------------------------------------------------------------------------

--- How a URL reaches the template. Pandoc escapes metadata strings as body
--- text, which is wrong inside \href{} or a Typst string, so for those formats
--- the URL is escaped here for its context and passed as raw markup.
local function url_value(url)
  if quarto.doc.is_format("latex") then
    url = url:gsub("\\", "/"):gsub("([%%#])", "\\%1")
    return pandoc.MetaInlines({ pandoc.RawInline("latex", url) })
  elseif quarto.doc.is_format("typst") then
    url = url:gsub("\\", "\\\\"):gsub('"', '\\"')
    return pandoc.MetaInlines({ pandoc.RawInline("typst", url) })
  end
  -- HTML attribute escaping, and anything else, is right as text.
  return pandoc.MetaInlines({ pandoc.Str(url) })
end

local function text_value(s)
  return pandoc.MetaInlines(pandoc.Inlines(s))
end

--- Metadata as inlines, whichever shape it arrived in.
local function as_inlines(value)
  local t = pandoc.utils.type(value)
  if t == "Inlines" then return value end
  if t == "Blocks" then return pandoc.utils.blocks_to_inlines(value) end
  return pandoc.Inlines(pandoc.utils.stringify(value))
end

local function is_map(value)
  return pandoc.utils.type(value) == "table" and value[1] == nil and next(value) ~= nil
end

local function is_list(value)
  return pandoc.utils.type(value) == "List"
end

--------------------------------------------------------------------------------
-- Normalisation
--------------------------------------------------------------------------------

--- Closest known service name, for the warning about a typo.
local function suggest(name)
  local best, best_d = nil, math.huge
  for known in pairs(ORDER) do
    -- Levenshtein distance; names are short, so this is cheap.
    local prev = {}
    for j = 0, #known do prev[j] = j end
    for i = 1, #name do
      local cur = { [0] = i }
      for j = 1, #known do
        local cost = name:sub(i, i) == known:sub(j, j) and 0 or 1
        cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
      end
      prev = cur
    end
    if prev[#known] < best_d then best, best_d = known, prev[#known] end
  end
  if best_d <= 2 then return best end
end

local function item(fields)
  local out = {}
  for k, v in pairs(fields) do out[k] = v end
  return pandoc.MetaMap(out)
end

--- One known service entry: `github: mcurie`, or the map form
--- `github: {handle: mcurie, label: "Marie Curie"}`.
local function known_entry(name, value)
  local service = BY_NAME[name]
  local overrides = {}

  if is_map(value) then
    for k, v in pairs(value) do
      if OVERRIDE_KEYS[k] then
        overrides[k] = v
      else
        quarto.log.warning(
          "vitae: social: ignoring unknown key '" .. k .. "' on " .. name ..
          "; expected one of handle, url, label, icon, title")
      end
    end
    if overrides.handle == nil and overrides.url == nil then
      quarto.log.warning("vitae: social: " .. name .. " needs a handle or a url; skipping")
      return nil
    end
  else
    overrides.handle = value
  end

  local written = overrides.handle
  local handle = written and trim(pandoc.utils.stringify(written))
  local given_url = overrides.url and trim(pandoc.utils.stringify(overrides.url))

  -- A full URL in place of a handle: recover the handle where the service can,
  -- so that labels and parts still come out right.
  if handle and has_scheme(handle) and name ~= "website" then
    local recovered = service.from_url and service.from_url(handle)
    if recovered then
      given_url = given_url or handle
      handle, written = recovered, nil
    else
      given_url = given_url or handle
    end
  end

  local parsed = handle and service.parse(handle) or { handle = given_url }
  local url = given_url or parsed.url

  local fields = {
    service = pandoc.MetaString(name),
    title = overrides.title and as_inlines(overrides.title) or text_value(service.title),
    icon = pandoc.MetaString(overrides.icon and pandoc.utils.stringify(overrides.icon) or service.icon),
    handle = text_value(parsed.handle or handle or ""),
    is = pandoc.MetaMap({ [name] = true }),
  }
  if url then fields.url = url_value(url) end

  -- Which fields the author set, so a template's own defaults can yield to
  -- them: `$if(social.given.icon)$…$elseif(social.is.github)$…`.
  local given = {}
  for _, k in ipairs({ "url", "label", "icon", "title" }) do
    if overrides[k] ~= nil then given[k] = true end
  end
  if next(given) then fields.given = pandoc.MetaMap(given) end

  if overrides.label then
    fields.label = as_inlines(overrides.label)
  elseif parsed.label then
    fields.label = text_value(parsed.label)
  elseif written then
    -- As written, so that markdown in an address or phone number survives.
    fields.label = as_inlines(written)
  else
    fields.label = text_value(handle or given_url)
  end

  for k, v in pairs(parsed.parts or {}) do
    fields[k] = text_value(v)
  end
  return item(fields)
end

--- One custom entry: `{icon: flask, text: "[Lab](https://…)"}`.
local function custom_entry(value)
  if not is_map(value) then
    quarto.log.warning(
      "vitae: social: each custom entry should be a map with icon and text, " ..
      "such as {icon: flask, text: \"[Lab](https://example.org)\"}; skipping")
    return nil
  end
  for k in pairs(value) do
    if not CUSTOM_KEYS[k] then
      quarto.log.warning(
        "vitae: social: ignoring unknown key '" .. k .. "' on a custom entry" ..
        "; expected icon, text, url or title")
    end
  end
  if value.text == nil then
    quarto.log.warning("vitae: social: custom entry needs text; skipping")
    return nil
  end

  local fields = {
    service = pandoc.MetaString("custom"),
    label = as_inlines(value.text),
    is = pandoc.MetaMap({ custom = true }),
  }
  if value.icon then fields.icon = pandoc.MetaString(pandoc.utils.stringify(value.icon)) end
  if value.title then fields.title = as_inlines(value.title) end
  if value.url then fields.url = url_value(trim(pandoc.utils.stringify(value.url))) end
  return item(fields)
end

--- Expand one `name: value` pair onto `out`. `custom` holds a list, and adds
--- each of its entries in place.
local function add_pair(out, name, value)
  if name == "custom" then
    local entries = is_list(value) and value or { value }
    for _, v in ipairs(entries) do
      local e = custom_entry(v)
      if e then out:insert(e) end
    end
  elseif BY_NAME[name] then
    local e = known_entry(name, value)
    if e then out:insert(e) end
  else
    local guess = suggest(name)
    quarto.log.warning(
      "vitae: social: unknown service '" .. name .. "'" ..
      (guess and ("; did you mean '" .. guess .. "'?") or "") ..
      " Use custom for anything else.")
  end
end

--- Normalise `meta.social` in place. Returns the metadata, changed or not.
function M.normalise(meta)
  local social = meta.social
  if social == nil then return meta end

  local out = pandoc.List({})

  if is_list(social) then
    for _, entry in ipairs(social) do
      if is_map(entry) then
        -- Usually one pair per item, but `- {github: a, gitlab: b}` is read
        -- as both, in the fixed order since the map's own order is lost.
        local names = {}
        for name in pairs(entry) do names[#names + 1] = name end
        table.sort(names, function(a, b)
          return (ORDER[a] or math.huge) < (ORDER[b] or math.huge)
        end)
        for _, name in ipairs(names) do add_pair(out, name, entry[name]) end
      else
        quarto.log.warning(
          "vitae: social: each item should be service: value, such as " ..
          "- github: mcurie; skipping '" .. pandoc.utils.stringify(entry) .. "'")
      end
    end
  elseif is_map(social) then
    local names = {}
    for name in pairs(social) do names[#names + 1] = name end
    table.sort(names, function(a, b)
      local oa, ob = ORDER[a] or math.huge, ORDER[b] or math.huge
      if oa ~= ob then return oa < ob end
      return a < b
    end)
    for _, name in ipairs(names) do add_pair(out, name, social[name]) end
  else
    quarto.log.warning(
      "vitae: social should be a list of service: value items, such as " ..
      "- github: mcurie")
    return meta
  end

  meta.social = pandoc.MetaList(out)
  return meta
end

--- The registry, for documentation and tests.
M.services = SERVICES

return M
