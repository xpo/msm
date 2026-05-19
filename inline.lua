-- mSM inline : parsing + layout + rendu des marqueurs inline markdown.
-- Supporté : **gras**, *italique*, `code`, ~~barré~~, [texte](url).
-- Rendu :
--  - gras      → double-draw (bold simulé, pas besoin d'une police bold)
--  - italique  → love.graphics.shear (slant simulé)
--  - code      → police mono + fond teinté
--  - barré     → ligne horizontale
--  - lien      → couleur accent + soulignement
local utf8 = require("utf8")
local M = {}

-- ---------- parser ----------
-- Retourne une liste de runs : { text, b, i, c, s, link }
function M.parse(s)
  s = s or ""
  local runs = {}
  local buf = {}
  local state = { b = false, i = false, c = false, s = false }
  local function flush(override_link)
    if #buf > 0 then
      runs[#runs + 1] = {
        text = table.concat(buf),
        b = state.b, i = state.i, c = state.c, s = state.s,
        link = override_link or false,
      }
      buf = {}
    end
  end
  local n = #s
  local p = 1
  while p <= n do
    local c1 = s:sub(p, p)
    local c2 = s:sub(p, p + 1)
    if c1 == "\\" and p < n then
      buf[#buf + 1] = s:sub(p + 1, p + 1)
      p = p + 2
    elseif state.c then
      if c1 == "`" then flush(); state.c = false; p = p + 1
      else buf[#buf + 1] = c1; p = p + 1 end
    elseif c2 == "**" then
      flush(); state.b = not state.b; p = p + 2
    elseif c2 == "~~" then
      flush(); state.s = not state.s; p = p + 2
    elseif c1 == "`" then
      flush(); state.c = true; p = p + 1
    elseif c1 == "*" then
      flush(); state.i = not state.i; p = p + 1
    elseif c1 == "[" then
      local close = s:find("]", p + 1, true)
      if close and s:sub(close + 1, close + 1) == "(" then
        local paren = s:find(")", close + 2, true)
        if paren then
          flush()
          runs[#runs + 1] = {
            text = s:sub(p + 1, close - 1),
            b = state.b, i = state.i, c = false, s = state.s, link = true,
          }
          p = paren + 1
        else buf[#buf + 1] = c1; p = p + 1 end
      else buf[#buf + 1] = c1; p = p + 1 end
    else
      buf[#buf + 1] = c1
      p = p + 1
    end
  end
  flush()
  return runs
end

-- Retourne une version "nettoyée" (sans marqueurs) d'un texte. Utile pour
-- mesurer une cellule de table sans styler.
function M.strip(s)
  local out = {}
  for _, r in ipairs(M.parse(s)) do out[#out + 1] = r.text end
  return table.concat(out)
end

-- ---------- layout ----------
-- Découpe UTF-8 sûre en tokens (mots + espaces).
local function tokenize(text)
  local tokens, word = {}, {}
  for _, code in utf8.codes(text) do
    local ch = utf8.char(code)
    if ch == " " or ch == "\t" then
      if #word > 0 then tokens[#tokens + 1] = { text = table.concat(word), kind = "w" }; word = {} end
      tokens[#tokens + 1] = { text = ch, kind = "sp" }
    else
      word[#word + 1] = ch
    end
  end
  if #word > 0 then tokens[#tokens + 1] = { text = table.concat(word), kind = "w" } end
  return tokens
end

-- fontResolver : fonction(run) → font, fake_bold, fake_italic
--   font        : Font LÖVE à utiliser pour ce run
--   fake_bold   : true si on doit simuler le gras (pas de police Bold disponible)
--   fake_italic : true si on doit simuler l'italique (pas de police Italic disponible)
-- filterFn (optionnel) : applique filter_glyphs(text, font) → text
-- Retourne { lines = { { segs = {...}, w, h } }, totalHeight }
function M.layout(runs, fontResolver, maxW, filterFn)
  local lines = { { segs = {}, w = 0, h = 0 } }
  local cur = lines[1]
  local function newline()
    cur = { segs = {}, w = 0, h = 0 }
    lines[#lines + 1] = cur
  end

  for _, run in ipairs(runs) do
    local font, fakeB, fakeI = fontResolver(run)
    local text = run.text
    if filterFn then text = filterFn(text, font) end
    if text == "" then goto continue end

    local tokens = tokenize(text)
    for _, tok in ipairs(tokens) do
      local w = font:getWidth(tok.text)
      if tok.kind == "w" and cur.w > 0 and cur.w + w > maxW then newline() end
      if tok.kind == "sp" and cur.w == 0 then
        -- skip leading whitespace on new line
      else
        cur.segs[#cur.segs + 1] = {
          text = tok.text, font = font,
          fake_b = fakeB and run.b or false,
          fake_i = fakeI and run.i or false,
          c = run.c, s = run.s, link = run.link,
          x = cur.w, w = w,
        }
        cur.w = cur.w + w
        if font:getHeight() > cur.h then cur.h = font:getHeight() end
      end
    end
    ::continue::
  end

  -- prune trailing empty line
  if #lines > 1 and #lines[#lines].segs == 0 then lines[#lines] = nil end

  local total = 0
  for _, ln in ipairs(lines) do total = total + ln.h end
  return { lines = lines, totalHeight = total }
end

-- ---------- draw ----------
-- layout : résultat de M.layout
-- x0, y0 : coin haut-gauche
-- maxW : largeur (pour alignement)
-- align : "left" | "center" | "right"
-- color : couleur de base {r,g,b,a}
-- accent : couleur accent (pour liens, fond code)
function M.draw(layout, x0, y0, maxW, align, color, accent, alpha)
  alpha = alpha or 1
  local r, g, b = color[1], color[2], color[3]
  local ar, ag, ab = accent[1], accent[2], accent[3]
  local y = y0
  for _, line in ipairs(layout.lines) do
    local x_offset = 0
    if align == "center" then x_offset = (maxW - line.w) / 2
    elseif align == "right" then x_offset = maxW - line.w end

    for _, seg in ipairs(line.segs) do
      local px = x0 + x_offset + seg.x
      local fh = seg.font:getHeight()

      -- fond pour code inline
      if seg.c then
        love.graphics.setColor(ar, ag, ab, alpha * 0.15)
        love.graphics.rectangle("fill", px - 3, y + 2, seg.w + 6, fh - 2, 4, 4)
      end

      -- couleur du texte
      local tr, tg, tb = r, g, b
      if seg.link then tr, tg, tb = ar, ag, ab end
      love.graphics.setColor(tr, tg, tb, alpha)
      love.graphics.setFont(seg.font)

      if seg.fake_i then
        -- italique simulé : shear
        love.graphics.push()
        love.graphics.translate(px, y)
        love.graphics.shear(-0.18, 0)
        love.graphics.print(seg.text, 0, 0)
        if seg.fake_b then
          love.graphics.print(seg.text, 1.2, 0)
          love.graphics.print(seg.text, 0.6, 0.4)
        end
        love.graphics.pop()
      else
        love.graphics.print(seg.text, px, y)
        if seg.fake_b then
          -- gras simulé : triple-draw en décalé
          love.graphics.print(seg.text, px + 1.2, y)
          love.graphics.print(seg.text, px + 0.6, y + 0.4)
        end
      end

      -- barré
      if seg.s then
        love.graphics.setColor(tr, tg, tb, alpha * 0.9)
        love.graphics.rectangle("fill", px, y + fh * 0.55, seg.w, math.max(1, fh * 0.06))
      end
      -- soulignement pour lien
      if seg.link then
        love.graphics.setColor(tr, tg, tb, alpha * 0.7)
        love.graphics.rectangle("fill", px, y + fh - 3, seg.w, 1)
      end
    end
    y = y + line.h
  end
end

return M
