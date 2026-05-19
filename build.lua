#!/usr/bin/env lua
-- mSM build CLI : empaquette un deck .md + images + msm.html en un .html autonome.
-- Usage : lua build.lua chemin/vers/deck.md [sortie.html]

local function die(msg) io.stderr:write("build.lua: " .. msg .. "\n"); os.exit(1) end

local deck_path = arg[1] or die("usage: lua build.lua deck.md [out.html]")
local script_dir = (arg[0] and arg[0]:match("^(.*/)")) or "./"
package.path = script_dir .. "?.lua;" .. package.path
local exporter = require("exporter")

local function read_all(path)
  local f = io.open(path, "r"); if not f then die("cannot read " .. path) end
  local d = f:read("*a"); f:close(); return d
end

local template = read_all(script_dir .. "msm.html")
local html, info = exporter.build_from_path(deck_path, template)
if not html then die(info or "build failed") end

local out_path = arg[2] or (deck_path:gsub("%.md$", "") .. ".html")
local o = io.open(out_path, "w"); if not o then die("cannot write " .. out_path) end
o:write(html); o:close()

io.write(string.format("→ %s  (%d image(s) inlinée(s), %d introuvable(s))\n",
  out_path, info.inlined, info.missing))
