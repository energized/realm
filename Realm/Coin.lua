local _, ns = ...

-- The one money formatter for the whole addon. 100 copper = 1 silver, 100 silver = 1 gold, shown with the
-- real coin icons. h is the icon height; 0 or nil scales it to the surrounding font like the default UI.
-- Zero gold/silver parts are skipped; a zero price shows 0 copper. Built by hand because
-- GetCoinTextureString is missing on some clients, which left raw copper such as "1500c" on screen.
function ns.Coin(c, h)
  c = math.floor(tonumber(c) or 0)
  if c < 0 then return "-" .. ns.Coin(-c, h) end
  h = tonumber(h) or 0
  local function icon(n) return "|TInterface\\MoneyFrame\\UI-" .. n .. "Icon:" .. h .. ":" .. h .. ":2:0|t" end
  local g, s, cu = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. icon("Gold") end
  if s > 0 then out[#out + 1] = s .. icon("Silver") end
  if cu > 0 or #out == 0 then out[#out + 1] = cu .. icon("Copper") end
  return table.concat(out, " ")
end
