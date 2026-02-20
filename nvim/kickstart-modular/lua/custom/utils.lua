local M = {}

-- Darken a hex colour by subtracting `amount` from each RGB channel
function M.darken(hex, amount)
  local r = math.max(0, tonumber(hex:sub(2, 3), 16) - amount)
  local g = math.max(0, tonumber(hex:sub(4, 5), 16) - amount)
  local b = math.max(0, tonumber(hex:sub(6, 7), 16) - amount)
  return string.format('#%02x%02x%02x', r, g, b)
end

return M
