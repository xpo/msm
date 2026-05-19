-- Génère icon.png (1024x1024) pour mSM.
-- Usage : love icon-gen/

local function hex(h)
  h = h:gsub("#", "")
  return tonumber(h:sub(1, 2), 16) / 255,
         tonumber(h:sub(3, 4), 16) / 255,
         tonumber(h:sub(5, 6), 16) / 255
end

function love.load()
  local W, H = 1024, 1024
  local canvas = love.graphics.newCanvas(W, H)
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)

  -- palette (thème dark de mSM)
  local br, bg, bb = hex("#111318")    -- fond
  local ar, ag, ab = hex("#ff7a59")    -- accent
  local h2r, h2g, h2b = hex("#7dd3fc") -- h2
  local h3r, h3g, h3b = hex("#c4b5fd") -- h3

  -- corps : carré arrondi (marges 10% style macOS)
  local m = 96
  local r = 220
  local bw, bh = W - m * 2, H - m * 2

  -- ombre douce
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.rectangle("fill", m + 6, m + 20, bw, bh, r, r)

  -- corps
  love.graphics.setColor(br, bg, bb, 1)
  love.graphics.rectangle("fill", m, m, bw, bh, r, r)

  -- 3 bandes horizontales (h1/h2/h3), centrées verticalement
  local bar_x = m + 140
  local bar_w_max = bw - 280
  local bar_h = 76
  local bar_gap = 170
  -- calcul pour centrer le bloc des 3 barres dans le corps
  local block_h = bar_h * 3 + bar_gap * 2 - bar_h
  -- hauteur totale du bloc (du haut de la 1ère au bas de la 3e)
  block_h = bar_h + bar_gap * 2
  local bars_y = m + (bh - block_h) / 2

  love.graphics.setColor(ar, ag, ab, 1)
  love.graphics.rectangle("fill", bar_x, bars_y, bar_w_max, bar_h, 26, 26)

  love.graphics.setColor(h2r, h2g, h2b, 0.95)
  love.graphics.rectangle("fill", bar_x, bars_y + bar_gap, bar_w_max * 0.82, bar_h, 26, 26)

  love.graphics.setColor(h3r, h3g, h3b, 0.90)
  love.graphics.rectangle("fill", bar_x, bars_y + bar_gap * 2, bar_w_max * 0.62, bar_h, 26, 26)

  love.graphics.setCanvas()

  -- export
  local imgdata = canvas:newImageData()
  local filedata = imgdata:encode("png")
  local bytes = filedata:getString()
  -- io.open relative → CWD du shell qui a lancé `love icon-gen/`
  local fh = io.open("icon.png", "wb")
  if fh then fh:write(bytes); fh:close(); print("→ icon.png") else print("erreur écriture icon.png") end

  love.event.quit()
end
