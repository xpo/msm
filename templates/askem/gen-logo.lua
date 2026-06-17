-- Génère templates/askem/logo.png à partir du logo askem.eu blanc.
-- Compose le PNG blanc sur un fond noir avec coins arrondis.
-- Usage : love templates/askem/ (et le main.lua local est ce fichier)

function love.conf(t) end

function love.load()
  -- Recupère le logo blanc en CWD (le shell se charge de le placer la)
  local logo_path = "/tmp/askem-raw.png"
  local fh = io.open(logo_path, "rb")
  if not fh then print("logo raw manquant"); love.event.quit(); return end
  local data = fh:read("*a"); fh:close()
  local fd = love.filesystem.newFileData(data, "askem")
  local imgdata = love.image.newImageData(fd)
  local logo = love.graphics.newImage(imgdata)

  local lw, lh = logo:getWidth(), logo:getHeight()
  -- Cible : badge ~260x72 (2x retina) avec padding 22px autour du logo,
  -- coins arrondis 14px
  local pad_x, pad_y = 30, 20
  local W = lw * 2 + pad_x * 2
  local H = lh * 2 + pad_y * 2
  local r = 14

  local canvas = love.graphics.newCanvas(W, H)
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)

  -- Fond noir rond
  love.graphics.setColor(0.06, 0.07, 0.09, 1)
  love.graphics.rectangle("fill", 0, 0, W, H, r, r)

  -- Logo centre, scale 2x pour conserver le rendu net
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(logo, pad_x, pad_y, 0, 2, 2)

  love.graphics.setCanvas()

  local out_data = canvas:newImageData()
  local fd_out = out_data:encode("png")
  local bytes = fd_out:getString()
  local f = io.open("templates/askem/logo.png", "wb")
  if f then f:write(bytes); f:close(); print("ok") end
  love.event.quit()
end
