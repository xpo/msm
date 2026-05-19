-- mSM exporter : deck.md (+ images locales) -> HTML autonome.
-- Utilisé par build.lua (CLI) et par main.lua (touche E dans l'app).
local M = {}

local PLACEHOLDER = "__MSM_EMBED_PLACEHOLDER_53a8b__"

local MIME = {
  png = "image/png", jpg = "image/jpeg", jpeg = "image/jpeg",
  gif = "image/gif", svg = "image/svg+xml", webp = "image/webp",
  bmp = "image/bmp", ico = "image/x-icon",
}

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b64_pure(data)
  local out, n = {}, #data
  for i = 1, n, 3 do
    local a = data:byte(i)
    local b = data:byte(i + 1) or 0
    local c = data:byte(i + 2) or 0
    local t = a * 65536 + b * 256 + c
    local i1 = math.floor(t / 262144) % 64 + 1
    local i2 = math.floor(t / 4096) % 64 + 1
    local i3 = math.floor(t / 64) % 64 + 1
    local i4 = t % 64 + 1
    out[#out + 1] = B64:sub(i1, i1) .. B64:sub(i2, i2)
      .. ((i + 1 > n) and "=" or B64:sub(i3, i3))
      .. ((i + 2 > n) and "=" or B64:sub(i4, i4))
  end
  return table.concat(out)
end

local function b64_popen(path)
  local quoted = "'" .. path:gsub("'", "'\\''") .. "'"
  local h = io.popen("base64 -i " .. quoted .. " 2>/dev/null || base64 " .. quoted .. " 2>/dev/null")
  if not h then return nil end
  local s = h:read("*a") or ""
  h:close()
  if #s == 0 then return nil end
  return (s:gsub("%s", ""))
end

local function read_bin(path)
  local f = io.open(path, "rb"); if not f then return nil end
  local d = f:read("*a"); f:close(); return d
end

local function script_safe(s)
  return (s:gsub("</(%a+)", function(tag)
    if tag:lower() == "script" then return "<\\/" .. tag end
    return "</" .. tag
  end))
end

-- Inline les images locales d'un markdown en data: URLs.
-- Retourne (markdown_modifié, nb_inliné, nb_introuvable)
function M.inline_images(md, deck_dir)
  local inlined, missing = 0, 0
  local new_md = md:gsub("(!%[[^%]]*%]%()([^)]+)(%))", function(open, src, close)
    if src:match("^%s*$") or src:match("^https?://") or src:match("^data:") then
      return nil
    end
    local abs = src:match("^/") and src or ((deck_dir or "") .. src)
    local data = read_bin(abs)
    if not data then missing = missing + 1; return nil end
    local ext = (abs:match("%.([^.]+)$") or ""):lower()
    local mime = MIME[ext] or "application/octet-stream"
    local b64 = b64_popen(abs) or b64_pure(data)
    inlined = inlined + 1
    return open .. "data:" .. mime .. ";base64," .. b64 .. close
  end)
  return new_md, inlined, missing
end

-- Construit le HTML complet à partir d'un markdown et d'un template HTML.
-- md_path: chemin du .md source (utilisé pour localiser les images et le nom du deck)
-- template_html: contenu brut de msm.html (contenant le placeholder)
function M.build_from_path(md_path, template_html)
  local md = read_bin(md_path)
  if not md then return nil, "cannot read " .. tostring(md_path) end
  local deck_dir = md_path:match("^(.*/)") or ""
  return M.build_from_md(md, deck_dir, template_html, md_path:match("([^/\\]+)$") or "deck")
end

function M.build_from_md(md, deck_dir, template_html, deck_name)
  local md2, inlined, missing = M.inline_images(md, deck_dir)
  local html = template_html

  local nm = (deck_name or "deck"):gsub('"', "&quot;")
  html = html:gsub('(id="deck%-embed")', '%1 data-name="' .. nm .. '"', 1)

  local found = false
  html = html:gsub(PLACEHOLDER, function()
    found = true
    return script_safe(md2)
  end, 1)
  if not found then return nil, "placeholder introuvable dans le template" end
  return html, { inlined = inlined, missing = missing }
end

return M
