-- mSM parser: frontmatter + markdown-ish → slides
local M = {}

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function parse_frontmatter(text)
  local meta = {}
  if not text:match("^%-%-%-%s*\n") then return meta, text, "" end
  local inner, rest = text:match("^%-%-%-%s*\n(.-)\n%-%-%-%s*\n(.*)$")
  if not inner then return meta, text, "" end
  for line in inner:gmatch("[^\n]+") do
    local k, v = line:match("^%s*([%w_%-]+)%s*:%s*(.-)%s*$")
    if k then
      -- strip surrounding "..." ou '...' au cas où l'utilisateur quote ses valeurs
      v = v:match('^"(.*)"$') or v:match("^'(.*)'$") or v
      meta[k] = v
    end
  end
  return meta, rest, "---\n" .. inner .. "\n---\n"
end

local function split_slides(body)
  local slides, cur = {}, {}
  for line in (body .. "\n"):gmatch("(.-)\n") do
    if line:match("^%-%-%-+%s*$") or line:match("^===+%s*$") then
      table.insert(slides, cur); cur = {}
    else
      table.insert(cur, line)
    end
  end
  table.insert(slides, cur)
  return slides
end

local function is_pipe_row(line)
  return line:match("^%s*|") ~= nil
end

local function is_table_sep(line)
  if not is_pipe_row(line) then return false end
  return line:match("^[%s|:%-]+$") ~= nil
end

local function parse_pipe_row(line)
  line = line:gsub("^%s*|", ""):gsub("|%s*$", "")
  local cells, start = {}, 1
  while true do
    local p = line:find("|", start, true)
    if not p then
      table.insert(cells, trim(line:sub(start)))
      break
    end
    table.insert(cells, trim(line:sub(start, p - 1)))
    start = p + 1
  end
  return cells
end

local function parse_align(sep_cells)
  local aligns = {}
  for i, cell in ipairs(sep_cells) do
    local left = cell:match("^:") ~= nil
    local right = cell:match(":$") ~= nil
    if left and right then aligns[i] = "center"
    elseif right then aligns[i] = "right"
    else aligns[i] = "left" end
  end
  return aligns
end

local function parse_slide(lines)
  local els = {}
  local slide_meta = {}
  local code_buf, in_code, code_lang = nil, false, nil
  local table_buf = nil

  local function flush_table()
    if not table_buf or #table_buf == 0 then return end
    local header = parse_pipe_row(table_buf[1])
    local aligns, start_idx = {}, 2
    if table_buf[2] and is_table_sep(table_buf[2]) then
      aligns = parse_align(parse_pipe_row(table_buf[2]))
      start_idx = 3
    end
    local rows = {}
    for i = start_idx, #table_buf do
      table.insert(rows, parse_pipe_row(table_buf[i]))
    end
    table.insert(els, { type = "table", header = header, aligns = aligns, rows = rows })
    table_buf = nil
  end

  for _, line in ipairs(lines) do
    -- Override slide-level via commentaire HTML : <!-- motion: aurora -->
    local mk, mv = line:match("^%s*<!%-%-%s*([%w_%-]+)%s*:%s*(.-)%s*%-%->%s*$")
    if mk then
      slide_meta[mk] = mv
    elseif line:match("^```") then
      flush_table()
      if in_code then
        local t = (code_lang == "mermaid") and "mermaid" or "code"
        table.insert(els, { type = t, text = table.concat(code_buf, "\n"), lang = code_lang })
        code_buf, in_code, code_lang = nil, false, nil
      else
        code_buf, in_code = {}, true
        code_lang = line:match("^```%s*(%S*)") or ""
      end
    elseif in_code then
      table.insert(code_buf, line)
    elseif is_pipe_row(line) then
      table_buf = table_buf or {}
      table.insert(table_buf, line)
    else
      flush_table()
      local h1 = line:match("^#%s+(.+)$")
      local h2 = line:match("^##%s+(.+)$")
      local h3 = line:match("^###%s+(.+)$")
      local alt, src = line:match("^!%[(.-)%]%((.-)%)%s*$")
      -- note : "->" ou "- >" (espace optionnel) éventuellement indenté
      local note_indent, note = line:match("^(%s*)%-%s*%>%s*(.+)$")
      local bullet = line:match("^[%-%*]%s+(.+)$")
      local quote = line:match("^>%s*(.*)$")
      if h1 then table.insert(els, { type = "h1", text = h1 })
      elseif h2 then table.insert(els, { type = "h2", text = h2 })
      elseif h3 then table.insert(els, { type = "h3", text = h3 })
      elseif src then table.insert(els, { type = "image", src = src, alt = alt })
      elseif note then
        local level = math.floor(#note_indent / 2)
        table.insert(els, { type = "note", text = note, level = level })
      elseif bullet then table.insert(els, { type = "bullet", text = bullet })
      elseif quote then table.insert(els, { type = "quote", text = quote })
      elseif trim(line) == "" then table.insert(els, { type = "space" })
      else table.insert(els, { type = "text", text = line })
      end
    end
  end
  flush_table()
  while #els > 0 and els[1].type == "space" do table.remove(els, 1) end
  while #els > 0 and els[#els].type == "space" do table.remove(els) end
  els.meta = slide_meta
  return els
end

function M.parse(text)
  text = text:gsub("\r\n", "\n")
  local meta, body, raw_fm = parse_frontmatter(text)
  local raw = split_slides(body)
  local slides = {}
  local raw_slides = {}
  for _, lines in ipairs(raw) do
    local s = parse_slide(lines)
    if #s > 0 then
      table.insert(slides, s)
      table.insert(raw_slides, table.concat(lines, "\n"))
    end
  end
  return meta, slides, raw_slides, raw_fm
end

return M
