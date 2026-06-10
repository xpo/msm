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
local edit_caret_seed = 0 -- pour faire clignoter / re-stabiliser le curseur

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

local function resolve(path)
  if path:match("^/") or path:match("^%a:[/\\]") then return path end
  return deck_dir .. path
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

local function path_exists(p)
  if not p or p == "" then return false end
  local f = io.open(p, "rb")
  if f then f:close(); return true end
  return false
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
  for _, slide in ipairs(slides) do
    for _, el in ipairs(slide) do
      if el.type == "image" then
        el.texture = load_image(el.src)
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
    if el.type == "image" and el.texture then
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
    if el.type == "image" and el.texture then
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
  edit_text = raw_slides_src[current]
  edit_cursor = #edit_text + 1
  edit_caret_seed = love.timer.getTime()
end

local function exit_edit_mode()
  edit_mode = false
end

local function save_edit()
  raw_slides_src[current] = edit_text
  local body = table.concat(raw_slides_src, "\n\n---\n\n")
  if body:sub(-1) ~= "\n" then body = body .. "\n" end
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

  love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.45)
  love.graphics.rectangle("line", pad - 12, pad - 12, W - (pad - 12) * 2, H - (pad - 12) * 2, 12, 12)

  love.graphics.setColor(theme.color)
  local i, n = 1, #edit_text
  local y = pad
  while i <= n + 1 do
    local le = i
    while le <= n and edit_text:sub(le, le) ~= "\n" do le = le + 1 end
    local line = edit_text:sub(i, le - 1)
    love.graphics.print(line, pad, y)
    if edit_cursor >= i and edit_cursor <= le then
      local prefix = edit_text:sub(i, edit_cursor - 1)
      local cx = pad + font:getWidth(prefix)
      if (love.timer.getTime() - edit_caret_seed) % 1 < 0.55 then
        love.graphics.setColor(theme.accent)
        love.graphics.rectangle("fill", cx, y - 2, 2, line_h)
        love.graphics.setColor(theme.color)
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

function love.keypressed(key)
  if edit_mode then
    edit_caret_seed = love.timer.getTime()
    if key == "escape" then
      exit_edit_mode()
    elseif key == "s" and is_cmd_down() then
      save_edit()
    elseif key == "e" and is_cmd_down() then
      exit_edit_mode()
    elseif key == "backspace" then
      if edit_cursor > 1 then
        local prev = utf8.offset(edit_text, -1, edit_cursor) or 1
        edit_text = edit_text:sub(1, prev - 1) .. edit_text:sub(edit_cursor)
        edit_cursor = prev
      end
    elseif key == "delete" then
      if edit_cursor <= #edit_text then
        local nxt = utf8.offset(edit_text, 2, edit_cursor) or (#edit_text + 1)
        edit_text = edit_text:sub(1, edit_cursor - 1) .. edit_text:sub(nxt)
      end
    elseif key == "return" then
      edit_text = edit_text:sub(1, edit_cursor - 1) .. "\n" .. edit_text:sub(edit_cursor)
      edit_cursor = edit_cursor + 1
    elseif key == "left" then
      if edit_cursor > 1 then edit_cursor = utf8.offset(edit_text, -1, edit_cursor) or 1 end
    elseif key == "right" then
      if edit_cursor <= #edit_text then
        edit_cursor = utf8.offset(edit_text, 2, edit_cursor) or (#edit_text + 1)
      end
    elseif key == "up" then
      edit_cursor = caret_move_vert(edit_text, edit_cursor, -1)
    elseif key == "down" then
      edit_cursor = caret_move_vert(edit_text, edit_cursor, 1)
    elseif key == "home" then
      while edit_cursor > 1 and edit_text:sub(edit_cursor - 1, edit_cursor - 1) ~= "\n" do
        edit_cursor = edit_cursor - 1
      end
    elseif key == "end" then
      while edit_cursor <= #edit_text and edit_text:sub(edit_cursor, edit_cursor) ~= "\n" do
        edit_cursor = edit_cursor + 1
      end
    elseif key == "v" and is_cmd_down() then
      local cb = love.system.getClipboardText() or ""
      if cb ~= "" then
        edit_text = edit_text:sub(1, edit_cursor - 1) .. cb .. edit_text:sub(edit_cursor)
        edit_cursor = edit_cursor + #cb
      end
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
  edit_text = edit_text:sub(1, edit_cursor - 1) .. text .. edit_text:sub(edit_cursor)
  edit_cursor = edit_cursor + #text
  edit_caret_seed = love.timer.getTime()
end

function love.filedropped(file)
  local path = file:getFilename()
  if path:match("%.md$") or path:match("%.markdown$") then
    load_deck(path)
  end
end

function love.mousepressed(_, _, button)
  if edit_mode then return end
  if button == 1 then go_to(current + 1)
  elseif button == 2 then go_to(current - 1) end
end

function love.wheelmoved(_, y)
  if edit_mode then return end
  if y < 0 then go_to(current + 1)
  elseif y > 0 then go_to(current - 1) end
end
