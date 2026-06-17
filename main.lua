-- mSM — .md Slide Machine
local parser = require("parser")
local exporter = require("exporter")
local inline = require("inline")
local utf8 = require("utf8")

local function filter_glyphs(text, font)
  if not text or text == "" or not font then return text or "" end
  if font:hasGlyphs(text) then return text end
  local parts = {}
  for _, code in utf8.codes(text) do
    local ch = utf8.char(code)
    if font:hasGlyphs(ch) then parts[#parts + 1] = ch end
  end
  return table.concat(parts)
end

local deck_path
local deck_dir = ""
local meta, slides = {}, {}
local raw_slides_src = {}
local raw_fm_src = ""
local fonts = {}
local theme = {}

local current, previous = 1, 1
local trans_t = 1 -- 1 = no transition in progress

-- file watcher
local watch_mtime = nil
local watch_timer = 0
local WATCH_INTERVAL = 0.6

-- editor state
local edit_mode = false
local edit_text = ""
local edit_cursor = 1     -- 1..#edit_text+1 (position byte-based)
local edit_anchor = 1     -- début de sélection (== cursor si pas de sélection)
local edit_caret_seed = 0 -- pour faire clignoter / re-stabiliser le curseur
local edit_dragging = false
local edit_last_click_t = 0
local edit_last_click_pos = 0
local edit_click_count = 0
-- undo / redo
local undo_stack = {}
local redo_stack = {}
local last_action = ""        -- "type", "delete", "other", "undo", "redo"
local last_action_t = 0
local UNDO_CAP = 200
local TYPE_COALESCE = 1.0     -- secondes : groupe les frappes consécutives

local function trim_blank_lines(s)
  s = (s or ""):gsub("^[\r\n]+", "")
  s = s:gsub("[\r\n]+$", "")
  return s
end

local function file_mtime(path)
  if not path then return nil end
  local quoted = path:gsub("'", "'\\''")
  local h = io.popen("stat -f %m '" .. quoted .. "' 2>/dev/null")
  if not h then return nil end
  local s = h:read("*a") or ""
  h:close()
  return tonumber(s)
end
local flash_msg, flash_t = nil, 0
local function flash(msg, seconds)
  flash_msg = msg
  flash_t = seconds or 3.5
end

local THEMES = {
  dark  = { background = "#111318", color = "#eef2f7", accent = "#ff7a59", muted = "#8a93a3",
            h2 = "#7dd3fc", h3 = "#c4b5fd", note = "#a8c0e0" },
  light = { background = "#ffffff", color = "#1a1d21", accent = "#2563eb", muted = "#6b7280",
            h2 = "#0891b2", h3 = "#7c3aed", note = "#475569" },
  cream = { background = "#f4ead5", color = "#2b2a26", accent = "#b34f2e", muted = "#7a6f56",
            h2 = "#5e6f41", h3 = "#8a5c30", note = "#8a7a5e" },
  slate = { background = "#1e293b", color = "#f1f5f9", accent = "#38bdf8", muted = "#94a3b8",
            h2 = "#a78bfa", h3 = "#f472b6", note = "#cbd5e1" },
  solar = { background = "#fdf6e3", color = "#073642", accent = "#b58900", muted = "#657b83",
            h2 = "#268bd2", h3 = "#d33682", note = "#586e75" },
}

local function hex(h, fallback)
  h = (h or fallback):gsub("#", "")
  return {
    tonumber(h:sub(1, 2), 16) / 255,
    tonumber(h:sub(3, 4), 16) / 255,
    tonumber(h:sub(5, 6), 16) / 255,
    1,
  }
end

local function read_bytes(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

local function path_exists(p)
  if not p or p == "" then return false end
  local f = io.open(p, "rb")
  if f then f:close(); return true end
  return false
end

local function resolve(path)
  if path:match("^/") or path:match("^%a:[/\\]") then return path end
  return deck_dir .. path
end

-- ---------- Mermaid ----------
-- Pré-rendu des blocs ```mermaid en PNG via mmdc. Cache local par hash.
-- Fallback gracieux en bloc code si mmdc absent ou échec.
local function find_mmdc()
  -- 1. Helper Swift bundlé dans le .app (préféré, ~100 Ko, no install)
  local src = love.filesystem.getSource()
  if src then
    -- src ressemble à /Applications/mSM.app/Contents/Resources/mSM.love
    -- ou /Users/xxx/DEV/mdslidemachine/ pour `love .`
    local bundled = src:gsub("/Resources/[^/]+%.love$", "/MacOS/mmd-render")
    if bundled ~= src and path_exists(bundled) then return bundled end
  end
  -- 2. mmd-render à côté du .app (mode dev / love .)
  if path_exists("./mSM.app/Contents/MacOS/mmd-render") then
    return "./mSM.app/Contents/MacOS/mmd-render"
  end
  -- 3. mmdc système (fallback npm install)
  if path_exists("/opt/homebrew/bin/mmdc") then return "/opt/homebrew/bin/mmdc" end
  if path_exists("/usr/local/bin/mmdc") then return "/usr/local/bin/mmdc" end
  local h = io.popen("which mmdc 2>/dev/null")
  if h then
    local p = (h:read("*a") or ""):gsub("[\n\r%s]", "")
    h:close()
    if p ~= "" then return p end
  end
  return nil
end

local function md5_string(s)
  local tmp = os.tmpname()
  local f = io.open(tmp, "w"); if not f then return nil end
  f:write(s); f:close()
  local h = io.popen("md5 -q '" .. tmp .. "' 2>/dev/null")
  if not h then os.remove(tmp); return nil end
  local res = (h:read("*a") or ""):gsub("[\n\r%s]", "")
  h:close(); os.remove(tmp)
  if res == "" then return nil end
  return res:sub(1, 16)
end

local function ensure_mermaid_png(src, out_path)
  if path_exists(out_path) then return true end
  local mmdc = find_mmdc()
  if not mmdc then io.stderr:write("mSM mermaid: mmdc introuvable\n") return false end
  local tmp_in = os.tmpname() .. ".mmd"
  local f = io.open(tmp_in, "w"); if not f then return false end
  f:write(src); f:close()
  local cmd = string.format(
    "%q -i %q -o %q -b transparent -w 1600 2>&1",
    mmdc, tmp_in, out_path
  )
  local h = io.popen(cmd)
  local out = h and h:read("*a") or ""
  if h then h:close() end
  os.remove(tmp_in)
  local ok = path_exists(out_path)
  if not ok then
    io.stderr:write("mSM mermaid: echec rendu (" .. out .. ")\n")
  end
  return ok
end

local function load_image(src)
  local data = read_bytes(resolve(src))
  if not data then return nil end
  local ok, fd = pcall(love.filesystem.newFileData, data, src)
  if not ok then return nil end
  local ok2, imgdata = pcall(love.image.newImageData, fd)
  if not ok2 then return nil end
  return love.graphics.newImage(imgdata)
end

local function load_font(path, size)
  if not path or path == "" then return love.graphics.newFont(size) end
  local data = read_bytes(path)
  if not data then return love.graphics.newFont(size) end
  local fd = love.filesystem.newFileData(data, "deckfont")
  return love.graphics.newFont(fd, size)
end

-- Polices système avec variantes Bold/Italic/BoldItalic, pour un vrai contraste
-- regular↔bold plutôt que le double-draw simulé.
local MAC_FAMILY = {
  r  = "/System/Library/Fonts/Supplemental/Arial.ttf",
  b  = "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
  i  = "/System/Library/Fonts/Supplemental/Arial Italic.ttf",
  bi = "/System/Library/Fonts/Supplemental/Arial Bold Italic.ttf",
}

local function derive_family(base_path)
  -- Depuis un chemin "X.ttf" (ou "X-Regular.ttf"), tente de localiser les variantes
  -- Bold / Italic / BoldItalic via les conventions usuelles (-Bold, Bold, " Bold").
  local dir, name, ext = base_path:match("^(.-)([^/]+)%.([%w]+)$")
  if not dir then return { r = base_path } end
  local stem = name:gsub("%-?[Rr]egular$", "")
  local e = "." .. ext
  local candidates = {
    b  = { stem .. "-Bold" .. e,       stem .. " Bold" .. e,       stem .. "Bold" .. e },
    i  = { stem .. "-Italic" .. e,     stem .. " Italic" .. e,     stem .. "Italic" .. e },
    bi = { stem .. "-BoldItalic" .. e, stem .. " Bold Italic" .. e, stem .. "BoldItalic" .. e },
  }
  local out = { r = base_path }
  for key, list in pairs(candidates) do
    for _, cand in ipairs(list) do
      local full = dir .. cand
      if path_exists(full) then out[key] = full; break end
    end
  end
  return out
end

local function resolve_family(meta_font)
  -- priorité : meta.font (custom) → Arial macOS → default LÖVE
  if meta_font and meta_font ~= "" then
    local p = resolve(meta_font)
    if path_exists(p) then return derive_family(p) end
  end
  if path_exists(MAC_FAMILY.r) then return MAC_FAMILY end
  return { r = nil } -- fallback LÖVE
end

local function lfs(path, size)
  return path and load_font(path, size) or love.graphics.newFont(size)
end

local function apply_theme()
  local base = THEMES[meta.theme or ""] or THEMES.dark
  theme.background = hex(meta.background, base.background)
  theme.color      = hex(meta.color,      base.color)
  theme.accent     = hex(meta.accent,     base.accent)
  theme.muted      = hex(meta.muted,      base.muted)
  theme.h2         = hex(meta.h2,         base.h2)
  theme.h3         = hex(meta.h3,         base.h3)
  theme.note       = hex(meta.note,       base.note)
  theme.fontSize   = tonumber(meta.fontSize)   or 34
  theme.titleSize  = tonumber(meta.titleSize)  or 72
  theme.codeSize   = tonumber(meta.codeSize)   or 24
  theme.padding    = tonumber(meta.padding)    or 80
  theme.lineSpace  = tonumber(meta.lineSpace)  or 8
  theme.align      = meta.align or "left"
  theme.transition = meta.transition or "fade"
  theme.duration   = tonumber(meta.transitionDuration) or 0.35
  theme.showIndex  = (meta.showIndex ~= "false")
  theme.overflow   = meta.overflow or "shrink" -- shrink | clip | scroll
  theme.minScale   = tonumber(meta.minScale) or 0.45

  local family = resolve_family(meta.font)
  -- Regular pour toutes les tailles
  fonts.text  = lfs(family.r, theme.fontSize)
  fonts.h1    = lfs(family.r, theme.titleSize)
  fonts.h2    = lfs(family.r, math.floor(theme.titleSize * 0.68))
  fonts.h3    = lfs(family.r, math.floor(theme.titleSize * 0.48))
  fonts.code  = love.graphics.newFont(theme.codeSize)
  fonts.small = love.graphics.newFont(16)
  -- Variantes (uniquement pour la taille du texte courant ; headings restent réguliers)
  fonts.text_b  = family.b  and lfs(family.b,  theme.fontSize) or nil
  fonts.text_i  = family.i  and lfs(family.i,  theme.fontSize) or nil
  fonts.text_bi = family.bi and lfs(family.bi, theme.fontSize) or nil
end

local function preload_images()
  local cache_dir = deck_dir .. ".msm-mermaid"
  local cache_created = false
  for si, slide in ipairs(slides) do
    for _, el in ipairs(slide) do
      if el.type == "image" then
        el.texture = load_image(el.src)
      elseif el.type == "mermaid" then
        local hash = md5_string(el.text)
        if hash then
          if not cache_created then
            os.execute("mkdir -p '" .. cache_dir:gsub("'", "'\\''") .. "'")
            cache_created = true
          end
          local png = cache_dir .. "/" .. hash .. ".png"
          if ensure_mermaid_png(el.text, png) then
            el.texture = load_image(png)
          end
        end
        if not el.texture then
          -- fallback : afficher comme bloc code
          el.type = "code"
        end
      end
    end
  end
end

local function load_deck(path, preserve_position)
  local text = read_bytes(path)
  if not text then
    print("mSM: cannot read " .. tostring(path))
    love.event.quit(1); return
  end
  local saved = current
  deck_path = path
  deck_dir = path:match("^(.*/)") or path:match("^(.*\\)") or ""
  meta, slides, raw_slides_src, raw_fm_src = parser.parse(text)
  raw_slides_src = raw_slides_src or {}
  raw_fm_src = raw_fm_src or ""
  apply_theme()
  preload_images()
  if preserve_position and #slides > 0 then
    current = math.max(1, math.min(saved, #slides))
  else
    current = 1
  end
  previous, trans_t = current, 1
  -- baseline mtime du fichier juste chargé (pour ne pas retriger le watcher)
  watch_mtime = file_mtime(path)
  love.window.setTitle("mSM — " .. (path:match("([^/\\]+)$") or path))
end

local function layout_table(el, maxW)
  local font = fonts.text
  local cellPad = 14
  local ncols = math.max(#el.header, 1)
  local header = {}
  for i = 1, ncols do header[i] = filter_glyphs(inline.strip(el.header[i] or ""), font) end
  local rows = {}
  for ri, row in ipairs(el.rows) do
    local r = {}
    for i = 1, ncols do r[i] = filter_glyphs(inline.strip(row[i] or ""), font) end
    rows[ri] = r
  end
  local colW = {}
  local function measure(cells)
    for i = 1, ncols do
      local c = cells[i] or ""
      local w = font:getWidth(c) + cellPad * 2
      if not colW[i] or w > colW[i] then colW[i] = w end
    end
  end
  measure(header)
  for _, row in ipairs(rows) do measure(row) end

  local sum = 0
  for i = 1, ncols do sum = sum + (colW[i] or 0) end
  if sum > maxW then
    local k = maxW / sum
    for i = 1, ncols do colW[i] = colW[i] * k end
    sum = maxW
  end

  local function row_h(cells)
    local mh = 0
    for i = 1, ncols do
      local _, lines = font:getWrap(cells[i] or "", colW[i] - cellPad * 2)
      mh = math.max(mh, #lines * font:getHeight())
    end
    return mh + cellPad
  end

  local headerH = row_h(header)
  local rowH, total = {}, headerH + 1
  for _, row in ipairs(rows) do
    local h = row_h(row)
    table.insert(rowH, h)
    total = total + h
  end
  return {
    font = font, colW = colW, cellPad = cellPad,
    sumW = sum, offsetX = (maxW - sum) / 2,
    headerH = headerH, rowH = rowH, totalH = total,
    ncols = ncols,
    header = header, rows = rows,
  }
end

local function layout_slide(slide, maxW, maxH)
  local items, total_h = {}, 0
  local space = theme.lineSpace
  for _, el in ipairs(slide) do
    local item = { el = el }
    if (el.type == "image" or el.type == "mermaid") and el.texture then
      local iw, ih = el.texture:getDimensions()
      local s = math.min(maxW / iw, (maxH * 0.75) / ih, 1)
      item.w, item.h, item.scale = iw * s, ih * s, s
    elseif el.type == "table" then
      item.tbl = layout_table(el, maxW)
      item.h = item.tbl.totalH
    elseif el.type == "space" then
      item.h = theme.fontSize * 0.5
    elseif el.type == "code" then
      -- bloc de code : pas de parsing inline, texte brut
      local font = fonts.code
      item.font = font
      local text = filter_glyphs(el.text or "", font)
      item.text = text
      local _, lines = font:getWrap(text, maxW - 32)
      item.h = #lines * font:getHeight() + 24
    else
      -- h1/h2/h3/text/bullet/quote → parsing inline
      local base_font =
        el.type == "h1" and fonts.h1 or
        el.type == "h2" and fonts.h2 or
        el.type == "h3" and fonts.h3 or
        fonts.text
      local is_text_size = (el.type == "text" or el.type == "bullet" or el.type == "quote" or el.type == "note")
      local inner_w = maxW
      local indent_px = 0
      if el.type == "quote" then inner_w = maxW - 20 end
      if el.type == "note" and el.level and el.level > 0 then
        indent_px = el.level * 40
        inner_w = maxW - indent_px
      end
      item.indent_px = indent_px
      local text = el.text or ""
      if el.type == "bullet" then text = "•  " .. text end
      if el.type == "quote" then text = "“ " .. text .. " ”" end
      item.runs = inline.parse(text)
      item.layout = inline.layout(item.runs, function(run)
        if run.c then return fonts.code, false, false end
        if is_text_size then
          if run.b and run.i then
            if fonts.text_bi then return fonts.text_bi, false, false end
            -- un seul variant : on prend bold (plus visible que italic seul) + fake l'autre
            if fonts.text_b then return fonts.text_b, false, true end
            if fonts.text_i then return fonts.text_i, true, false end
            return fonts.text, true, true
          end
          if run.b then
            if fonts.text_b then return fonts.text_b, false, false end
            return fonts.text, true, false
          end
          if run.i then
            if fonts.text_i then return fonts.text_i, false, false end
            return fonts.text, false, true
          end
          return fonts.text, false, false
        end
        -- headings : pas de variante, fallback simulation
        return base_font, run.b, run.i
      end, inner_w, filter_glyphs)
      item.inner_w = inner_w
      item.h = item.layout.totalHeight
    end
    total_h = total_h + item.h + space
    table.insert(items, item)
  end
  return items, total_h - space
end

local function draw_table(it, x0, y0, maxW, alpha)
  local tbl = it.tbl
  local el = it.el
  local sumW = tbl.sumW
  local x = x0 + tbl.offsetX
  love.graphics.setFont(tbl.font)

  love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], alpha * 0.14)
  love.graphics.rectangle("fill", x, y0, sumW, tbl.headerH, 6, 6)

  love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], alpha)
  local cx = x
  for i = 1, tbl.ncols do
    local align = (el.aligns[i] or "left")
    love.graphics.printf(tbl.header[i] or "",
      cx + tbl.cellPad, y0 + tbl.cellPad / 2,
      tbl.colW[i] - tbl.cellPad * 2, align)
    cx = cx + tbl.colW[i]
  end

  love.graphics.setColor(theme.muted[1], theme.muted[2], theme.muted[3], alpha * 0.5)
  love.graphics.rectangle("fill", x, y0 + tbl.headerH, sumW, 1)

  local cy = y0 + tbl.headerH + 1
  for ri, row in ipairs(tbl.rows) do
    love.graphics.setColor(theme.color[1], theme.color[2], theme.color[3], alpha)
    love.graphics.setFont(tbl.font)
    local ccx = x
    for i = 1, tbl.ncols do
      local align = (el.aligns[i] or "left")
      love.graphics.printf(row[i] or "",
        ccx + tbl.cellPad, cy + tbl.cellPad / 2,
        tbl.colW[i] - tbl.cellPad * 2, align)
      ccx = ccx + tbl.colW[i]
    end
    cy = cy + tbl.rowH[ri]
    if ri < #tbl.rows then
      love.graphics.setColor(theme.muted[1], theme.muted[2], theme.muted[3], alpha * 0.18)
      love.graphics.rectangle("fill", x, cy, sumW, 1)
    end
  end
end

local function draw_slide(idx, alpha, offX, offY)
  local slide = slides[idx]; if not slide then return end
  local W, H = love.graphics.getDimensions()
  local pad = theme.padding
  local maxW, maxH = W - pad * 2, H - pad * 2
  local items, total = layout_slide(slide, maxW, maxH)

  local scale, y_start = 1, pad
  if total <= maxH then
    y_start = pad + (maxH - total) / 2
  elseif theme.overflow == "shrink" then
    scale = math.max(theme.minScale, maxH / total)
  end

  love.graphics.push()
  love.graphics.translate(offX or 0, offY or 0)
  if scale < 1 then
    love.graphics.translate(W / 2, pad)
    love.graphics.scale(scale)
    love.graphics.translate(-W / 2, -pad)
  end
  if total * scale > maxH + 0.5 then
    love.graphics.setScissor(pad, pad, maxW, maxH)
  end

  local y = y_start
  for _, it in ipairs(items) do
    local el = it.el
    if (el.type == "image" or el.type == "mermaid") and el.texture then
      love.graphics.setColor(1, 1, 1, alpha)
      love.graphics.draw(el.texture, (W - it.w) / 2, y, 0, it.scale, it.scale)
    elseif el.type == "table" then
      draw_table(it, pad, y, maxW, alpha)
    elseif el.type == "space" then
      -- nothing
    elseif el.type == "code" then
      love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], alpha * 0.12)
      love.graphics.rectangle("fill", pad, y, maxW, it.h, 10, 10)
      love.graphics.setColor(theme.color[1], theme.color[2], theme.color[3], alpha)
      love.graphics.setFont(it.font)
      love.graphics.printf(it.text, pad + 16, y + 12, maxW - 32, "left")
    elseif el.type == "quote" then
      love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], alpha * 0.6)
      love.graphics.rectangle("fill", pad, y, 4, it.h)
      inline.draw(it.layout, pad + 20, y, it.inner_w, theme.align, theme.muted, theme.accent, alpha)
    else
      local c = theme.color
      if el.type == "h1" then c = theme.accent end
      if el.type == "h2" then c = theme.h2 end
      if el.type == "h3" then c = theme.h3 end
      if el.type == "note" then c = theme.note end
      inline.draw(it.layout, pad + (it.indent_px or 0), y, it.inner_w, theme.align, c, theme.accent, alpha)
    end
    y = y + it.h + theme.lineSpace
  end
  love.graphics.setScissor()
  love.graphics.pop()
end

local function show_welcome()
  meta = {}
  apply_theme()
  slides = { {
    { type = "h1", text = "mSM" },
    { type = "space" },
    { type = "h3", text = ".md Slide Machine" },
    { type = "space" },
    { type = "text", text = "Glissez un fichier .md sur cette fenêtre" },
    { type = "text", text = "— ou sur l'icône mSM du Dock." },
  } }
  current, previous, trans_t = 1, 1, 1
  deck_path = nil
  love.window.setTitle("mSM")
end

function love.load(args)
  local path = args and args[1]
  if path then
    load_deck(path)
  else
    show_welcome()
  end
end

function love.update(dt)
  if trans_t < 1 then
    trans_t = math.min(1, trans_t + dt / math.max(0.0001, theme.duration))
  end
  if flash_t > 0 then flash_t = flash_t - dt end
  -- watcher : recharge le deck si le .md a changé sur disque (et pas en édition)
  if deck_path and not edit_mode then
    watch_timer = watch_timer + dt
    if watch_timer >= WATCH_INTERVAL then
      watch_timer = 0
      local mt = file_mtime(deck_path)
      if mt then
        if watch_mtime and mt > watch_mtime + 0.01 then
          load_deck(deck_path, true)
        end
        watch_mtime = mt
      end
    end
  end
end

-- ---------- éditeur in-app ----------
local function enter_edit_mode()
  if not deck_path or #slides == 0 then flash("Rien à éditer"); return end
  if not raw_slides_src[current] then flash("Slide introuvable"); return end
  edit_mode = true
  edit_text = trim_blank_lines(raw_slides_src[current])
  edit_cursor = #edit_text + 1
  edit_anchor = edit_cursor
  edit_dragging = false
  edit_caret_seed = love.timer.getTime()
  -- reset historique d'édition pour cette session
  undo_stack = {}
  redo_stack = {}
  last_action = ""
  last_action_t = 0
end

-- Helpers de sélection ----------------------------------------------------
local function sel_range()
  if edit_cursor == edit_anchor then return nil, nil end
  return math.min(edit_cursor, edit_anchor), math.max(edit_cursor, edit_anchor)
end

local function delete_selection()
  local mn, mx = sel_range()
  if not mn then return false end
  edit_text = edit_text:sub(1, mn - 1) .. edit_text:sub(mx)
  edit_cursor = mn
  edit_anchor = mn
  return true
end

local function copy_selection()
  local mn, mx = sel_range()
  if not mn then return false end
  love.system.setClipboardText(edit_text:sub(mn, mx - 1))
  return true
end

local function mouse_to_caret(mx_, my_)
  local pad = theme.padding
  local font = fonts.code
  local line_h = font:getHeight() + 4
  local rel_y = my_ - pad
  local target_line = math.max(1, math.floor(rel_y / line_h) + 1)

  local i, ln = 1, 1
  local n = #edit_text
  while i <= n + 1 do
    local le = i
    while le <= n and edit_text:sub(le, le) ~= "\n" do le = le + 1 end
    if ln == target_line then
      local rel_x = mx_ - pad
      if rel_x <= 0 then return i end
      local pos = i
      local prev_w = 0
      while pos < le do
        local nxt = utf8.offset(edit_text, 2, pos) or (pos + 1)
        local cur_w = font:getWidth(edit_text:sub(i, nxt - 1))
        local mid = (prev_w + cur_w) / 2
        if rel_x < mid then return pos end
        prev_w = cur_w
        pos = nxt
      end
      return le
    end
    if i > n then break end
    ln = ln + 1
    i = le + 1
  end
  return #edit_text + 1
end

local function find_word_at(pos)
  local n = #edit_text
  local function is_word(c) return c:match("[%w_]") ~= nil end
  local left = pos
  while left > 1 do
    local prev = utf8.offset(edit_text, -1, left) or 1
    if not is_word(edit_text:sub(prev, prev)) then break end
    left = prev
  end
  local right = pos
  while right <= n do
    if not is_word(edit_text:sub(right, right)) then break end
    right = utf8.offset(edit_text, 2, right) or (right + 1)
  end
  return left, right
end

local function line_bounds_at(pos)
  local ls = pos
  while ls > 1 and edit_text:sub(ls - 1, ls - 1) ~= "\n" do ls = ls - 1 end
  local le = pos
  while le <= #edit_text and edit_text:sub(le, le) ~= "\n" do le = le + 1 end
  return ls, le
end

-- Saut de mot façon macOS (Option+Left/Right).
local function jump_word_right(pos)
  local n = #edit_text
  while pos <= n and not edit_text:sub(pos, pos):match("[%w_]") do pos = pos + 1 end
  while pos <= n and edit_text:sub(pos, pos):match("[%w_]") do pos = pos + 1 end
  return pos
end
local function jump_word_left(pos)
  pos = pos - 1
  while pos > 0 and not edit_text:sub(pos, pos):match("[%w_]") do pos = pos - 1 end
  while pos > 0 and edit_text:sub(pos, pos):match("[%w_]") do pos = pos - 1 end
  return pos + 1
end

-- Undo/Redo. Coalesce les frappes consécutives en un seul groupe.
local function snapshot()
  return { text = edit_text, cursor = edit_cursor, anchor = edit_anchor }
end
local function push_undo(action)
  local now = love.timer.getTime()
  if action == "type" and last_action == "type"
     and (now - last_action_t) < TYPE_COALESCE then
    last_action_t = now
    return
  end
  undo_stack[#undo_stack + 1] = snapshot()
  if #undo_stack > UNDO_CAP then table.remove(undo_stack, 1) end
  redo_stack = {}
  last_action = action
  last_action_t = now
end
local function apply_state(s)
  edit_text = s.text
  edit_cursor = s.cursor
  edit_anchor = s.anchor
end
local function undo()
  if #undo_stack == 0 then return end
  redo_stack[#redo_stack + 1] = snapshot()
  apply_state(table.remove(undo_stack))
  last_action = "undo"; last_action_t = 0
end
local function redo()
  if #redo_stack == 0 then return end
  undo_stack[#undo_stack + 1] = snapshot()
  apply_state(table.remove(redo_stack))
  last_action = "redo"; last_action_t = 0
end

local function exit_edit_mode()
  edit_mode = false
end

local function save_edit()
  raw_slides_src[current] = edit_text
  local parts = {}
  for i, s in ipairs(raw_slides_src) do
    parts[i] = trim_blank_lines(s)
  end
  local body = "\n" .. table.concat(parts, "\n\n---\n\n") .. "\n"
  local full = (raw_fm_src or "") .. body
  local f = io.open(deck_path, "w")
  if not f then flash("Erreur écriture"); return end
  f:write(full); f:close()
  edit_mode = false
  load_deck(deck_path, true)
  flash("Enregistré", 1.5)
end

local function caret_move_vert(text, cursor, dir)
  local line_start = cursor
  while line_start > 1 and text:sub(line_start - 1, line_start - 1) ~= "\n" do
    line_start = line_start - 1
  end
  local col = cursor - line_start
  if dir < 0 then
    if line_start <= 1 then return cursor end
    local prev_end = line_start - 1
    local prev_start = prev_end
    while prev_start > 1 and text:sub(prev_start - 1, prev_start - 1) ~= "\n" do
      prev_start = prev_start - 1
    end
    return prev_start + math.min(col, prev_end - prev_start)
  else
    local cur_end = cursor
    while cur_end <= #text and text:sub(cur_end, cur_end) ~= "\n" do
      cur_end = cur_end + 1
    end
    if cur_end > #text then return cursor end
    local nxt_start = cur_end + 1
    local nxt_end = nxt_start
    while nxt_end <= #text and text:sub(nxt_end, nxt_end) ~= "\n" do
      nxt_end = nxt_end + 1
    end
    return nxt_start + math.min(col, nxt_end - nxt_start)
  end
end

local function draw_editor()
  local W, H = love.graphics.getDimensions()
  local pad = theme.padding
  local font = fonts.code
  love.graphics.setFont(font)
  local line_h = font:getHeight() + 4
  local sel_min, sel_max = sel_range()

  love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.45)
  love.graphics.rectangle("line", pad - 12, pad - 12, W - (pad - 12) * 2, H - (pad - 12) * 2, 12, 12)

  local i, n = 1, #edit_text
  local y = pad
  while i <= n + 1 do
    local le = i
    while le <= n and edit_text:sub(le, le) ~= "\n" do le = le + 1 end

    -- highlight de la sélection pour cette ligne
    if sel_min and sel_min < sel_max then
      local s = math.max(i, sel_min)
      local e = math.min(le, sel_max)
      -- si la sélection englobe le \n de cette ligne, étend un peu vers la droite
      local trailing = (sel_max > le) and 12 or 0
      if s < e or trailing > 0 then
        local x1 = pad + font:getWidth(edit_text:sub(i, s - 1))
        local x2 = pad + font:getWidth(edit_text:sub(i, e - 1)) + trailing
        love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.28)
        love.graphics.rectangle("fill", x1, y - 2, math.max(2, x2 - x1), line_h)
      end
    end

    -- texte
    love.graphics.setColor(theme.color)
    love.graphics.print(edit_text:sub(i, le - 1), pad, y)

    -- curseur
    if edit_cursor >= i and edit_cursor <= le then
      local cx = pad + font:getWidth(edit_text:sub(i, edit_cursor - 1))
      if (love.timer.getTime() - edit_caret_seed) % 1 < 0.55 then
        love.graphics.setColor(theme.accent)
        love.graphics.rectangle("fill", cx, y - 2, 2, line_h)
      end
    end

    y = y + line_h
    i = le + 1
    if i > n + 1 then break end
  end

  love.graphics.setFont(fonts.small)
  love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.9)
  love.graphics.print(
    "EDIT  ·  ⌘S enregistrer  ·  Esc / ⌘E annuler  ·  slide " .. current .. "/" .. #slides,
    pad, H - 28
  )
end

local function get_template()
  if love.filesystem.getInfo("msm.html") then
    return love.filesystem.read("msm.html")
  end
  return nil
end

local function save_dialog(default_name)
  -- macOS : NSSavePanel natif via osascript.
  -- `tell me to activate` force l'osascript à passer au premier plan
  -- pour que le dialog ne soit pas masqué par la fenêtre LÖVE.
  local safe = (default_name or "deck.html"):gsub('"', '\\"')
  local script = table.concat({
    "tell me to activate",
    "try",
    '  POSIX path of (choose file name with prompt "Exporter le deck en HTML" default name "' .. safe .. '")',
    "on error",
    '  return ""',
    "end try",
  }, "\n")
  local quoted = script:gsub("'", "'\\''")
  local h = io.popen("osascript -e '" .. quoted .. "' 2>/dev/null")
  if not h then return nil end
  local out = (h:read("*a") or ""):gsub("[\n\r]+$", "")
  h:close()
  if out == "" then return nil end
  return out
end

local function open_in_editor()
  if not deck_path then
    flash("Aucun deck à ouvrir")
    return
  end
  -- `open <file>` ouvre le fichier avec l'app par défaut pour son type (MarkEdit, etc.).
  -- Si l'app est déjà lancée avec ce fichier, macOS amène sa fenêtre au premier plan.
  local quoted = "'" .. deck_path:gsub("'", "'\\''") .. "'"
  os.execute("open " .. quoted .. " >/dev/null 2>&1 &")
  flash("→ ouvert dans l'éditeur", 2)
end

local function export_current_deck()
  if not deck_path then
    flash("Rien à exporter — chargez d'abord un deck")
    return
  end
  local template = get_template()
  if not template then
    flash("Template msm.html absent du bundle")
    return
  end
  local base = deck_path:match("([^/\\]+)%.md$") or deck_path:match("([^/\\]+)$") or "deck"
  local suggested = base .. ".html"
  local out_path = save_dialog(suggested)
  if not out_path then
    flash("Export annulé")
    return
  end
  local html, info = exporter.build_from_path(deck_path, template)
  if not html then
    flash("Erreur : " .. tostring(info))
    return
  end
  local f, err = io.open(out_path, "w")
  if not f then flash("Écriture impossible : " .. tostring(err)); return end
  f:write(html); f:close()
  local summary = string.format("Exporté (%d image(s) inlinée(s))", info.inlined)
  flash(summary .. " → " .. out_path, 5)
end

local function ease(t) return t < 0.5 and 2 * t * t or 1 - ((-2 * t + 2) ^ 2) / 2 end

function love.draw()
  love.graphics.clear(theme.background)
  if #slides == 0 then return end

  if edit_mode then
    draw_editor()
    if flash_t > 0 and flash_msg then
      local alpha = math.min(1, flash_t * 1.2)
      local W = love.graphics.getWidth(); local H = love.graphics.getHeight()
      love.graphics.setFont(fonts.small)
      love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], alpha * 0.92)
      love.graphics.rectangle("fill", 0, H - 44, W, 44)
      love.graphics.setColor(1, 1, 1, alpha)
      love.graphics.printf(flash_msg, 20, H - 30, W - 40, "center")
    end
    return
  end

  local W = love.graphics.getWidth()
  if trans_t < 1 and previous ~= current then
    local t = ease(trans_t)
    local kind = theme.transition
    if kind == "fade" then
      draw_slide(previous, 1 - t, 0, 0)
      draw_slide(current, t, 0, 0)
    elseif kind == "slide" then
      local dir = current > previous and 1 or -1
      draw_slide(previous, 1, -W * t * dir, 0)
      draw_slide(current, 1, W * (1 - t) * dir, 0)
    elseif kind == "push" then
      local dir = current > previous and 1 or -1
      draw_slide(previous, 1 - t * 0.5, -W * 0.3 * t * dir, 0)
      draw_slide(current, t, W * (1 - t) * dir, 0)
    else
      draw_slide(current, 1, 0, 0)
    end
  else
    draw_slide(current, 1, 0, 0)
  end

  if theme.showIndex then
    love.graphics.setColor(theme.muted[1], theme.muted[2], theme.muted[3], 0.7)
    love.graphics.setFont(fonts.small)
    love.graphics.printf(current .. " / " .. #slides,
      0, love.graphics.getHeight() - 28, love.graphics.getWidth() - 20, "right")
  end

  if flash_t > 0 and flash_msg then
    local alpha = math.min(1, flash_t * 1.2)
    local W = love.graphics.getWidth()
    local H = love.graphics.getHeight()
    love.graphics.setFont(fonts.small)
    local bh = 44
    love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], alpha * 0.92)
    love.graphics.rectangle("fill", 0, H - bh, W, bh)
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.printf(flash_msg, 20, H - bh + 14, W - 40, "center")
  end
end

local function go_to(n)
  n = math.max(1, math.min(#slides, n))
  if n ~= current then
    previous = current
    current = n
    trans_t = 0
  end
end

local function is_cmd_down()
  return love.keyboard.isDown("lgui") or love.keyboard.isDown("rgui")
     or love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
end

local function is_shift_down()
  return love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
end
local function is_alt_down()
  return love.keyboard.isDown("lalt") or love.keyboard.isDown("ralt")
end

function love.keypressed(key)
  if edit_mode then
    edit_caret_seed = love.timer.getTime()
    local shift = is_shift_down()
    local function collapse_to(p)
      edit_cursor = p
      if not shift then edit_anchor = p end
    end

    if key == "escape" then
      exit_edit_mode()
    elseif key == "s" and is_cmd_down() then
      save_edit()
    elseif key == "e" and is_cmd_down() then
      exit_edit_mode()
    elseif key == "z" and is_cmd_down() then
      if shift then redo() else undo() end
    elseif key == "y" and is_cmd_down() then
      redo()
    elseif key == "a" and is_cmd_down() then
      edit_anchor = 1
      edit_cursor = #edit_text + 1
    elseif key == "c" and is_cmd_down() then
      copy_selection()
    elseif key == "x" and is_cmd_down() then
      if sel_range() then
        push_undo("other")
        copy_selection()
        delete_selection()
      end
    elseif key == "v" and is_cmd_down() then
      local cb = love.system.getClipboardText() or ""
      if cb ~= "" then
        push_undo("other")
        delete_selection()
        edit_text = edit_text:sub(1, edit_cursor - 1) .. cb .. edit_text:sub(edit_cursor)
        edit_cursor = edit_cursor + #cb
        edit_anchor = edit_cursor
      end
    elseif key == "backspace" then
      push_undo("delete")
      if not delete_selection() then
        if edit_cursor > 1 then
          local prev = utf8.offset(edit_text, -1, edit_cursor) or 1
          edit_text = edit_text:sub(1, prev - 1) .. edit_text:sub(edit_cursor)
          edit_cursor = prev
          edit_anchor = prev
        end
      end
    elseif key == "delete" then
      push_undo("delete")
      if not delete_selection() then
        if edit_cursor <= #edit_text then
          local nxt = utf8.offset(edit_text, 2, edit_cursor) or (#edit_text + 1)
          edit_text = edit_text:sub(1, edit_cursor - 1) .. edit_text:sub(nxt)
        end
      end
    elseif key == "return" then
      push_undo("other")
      delete_selection()
      edit_text = edit_text:sub(1, edit_cursor - 1) .. "\n" .. edit_text:sub(edit_cursor)
      edit_cursor = edit_cursor + 1
      edit_anchor = edit_cursor
    elseif key == "left" then
      if is_alt_down() then
        collapse_to(jump_word_left(edit_cursor))
      elseif edit_cursor > 1 then
        collapse_to(utf8.offset(edit_text, -1, edit_cursor) or 1)
      elseif not shift then edit_anchor = edit_cursor end
    elseif key == "right" then
      if is_alt_down() then
        collapse_to(jump_word_right(edit_cursor))
      elseif edit_cursor <= #edit_text then
        collapse_to(utf8.offset(edit_text, 2, edit_cursor) or (#edit_text + 1))
      elseif not shift then edit_anchor = edit_cursor end
    elseif key == "up" then
      collapse_to(caret_move_vert(edit_text, edit_cursor, -1))
    elseif key == "down" then
      collapse_to(caret_move_vert(edit_text, edit_cursor, 1))
    elseif key == "home" then
      local p = edit_cursor
      while p > 1 and edit_text:sub(p - 1, p - 1) ~= "\n" do p = p - 1 end
      collapse_to(p)
    elseif key == "end" then
      local p = edit_cursor
      while p <= #edit_text and edit_text:sub(p, p) ~= "\n" do p = p + 1 end
      collapse_to(p)
    end
    return
  end

  if key == "escape" or key == "q" then
    love.event.quit()
  elseif key == "right" or key == "space" or key == "pagedown" or key == "return" or key == "down" then
    go_to(current + 1)
  elseif key == "left" or key == "pageup" or key == "backspace" or key == "up" then
    go_to(current - 1)
  elseif key == "home" then
    go_to(1)
  elseif key == "end" then
    go_to(#slides)
  elseif key == "f" then
    love.window.setFullscreen(not love.window.getFullscreen())
  elseif key == "r" then
    if deck_path then load_deck(deck_path, true) end
  elseif key == "e" then
    if is_cmd_down() then enter_edit_mode() else export_current_deck() end
  elseif key == "tab" then
    open_in_editor()
  end
end

function love.textinput(text)
  if not edit_mode then return end
  push_undo("type")
  delete_selection()
  edit_text = edit_text:sub(1, edit_cursor - 1) .. text .. edit_text:sub(edit_cursor)
  edit_cursor = edit_cursor + #text
  edit_anchor = edit_cursor
  edit_caret_seed = love.timer.getTime()
end

function love.filedropped(file)
  local path = file:getFilename()
  if path:match("%.md$") or path:match("%.markdown$") then
    load_deck(path)
  end
end

function love.mousepressed(x, y, button)
  if edit_mode then
    if button ~= 1 then return end
    local pos = mouse_to_caret(x, y)
    local now = love.timer.getTime()
    local close = (now - edit_last_click_t < 0.4)
        and math.abs(pos - edit_last_click_pos) <= 1
    edit_click_count = close and (edit_click_count + 1) or 1
    edit_last_click_t = now
    edit_last_click_pos = pos

    if edit_click_count == 1 then
      edit_cursor = pos
      if not is_shift_down() then edit_anchor = pos end
      edit_dragging = true
    elseif edit_click_count == 2 then
      local wl, wr = find_word_at(pos)
      edit_anchor, edit_cursor = wl, wr
    elseif edit_click_count >= 3 then
      local ls, le = line_bounds_at(pos)
      edit_anchor, edit_cursor = ls, le
      edit_click_count = 0
    end
    edit_caret_seed = love.timer.getTime()
    return
  end
  if button == 1 then go_to(current + 1)
  elseif button == 2 then go_to(current - 1) end
end

function love.mousemoved(x, y)
  if edit_mode and edit_dragging then
    edit_cursor = mouse_to_caret(x, y)
    edit_caret_seed = love.timer.getTime()
  end
end

function love.mousereleased(_, _, button)
  if edit_mode and button == 1 then edit_dragging = false end
end

function love.wheelmoved(_, y)
  if edit_mode then return end
  if y < 0 then go_to(current + 1)
  elseif y > 0 then go_to(current - 1) end
end
