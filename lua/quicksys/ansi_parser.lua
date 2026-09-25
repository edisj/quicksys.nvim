local Parser = setmetatable({}, { __call = function(self, ...) return self.new(...) end })
Parser.__index = Parser

local FG_COLOR = {
  ["30"] = "QuicksysBlack",
  ["31"] = "QuicksysRed",
  ["32"] = "QuicksysGreen",
  ["33"] = "QuicksysYellow",
  ["34"] = "QuicksysBlue",
  ["35"] = "QuicksysMagenta",
  ["36"] = "QuicksysCyan",
  ["37"] = "QuicksysWhite",
  ["90"] = "QuicksysBrightBlack",
  ["91"] = "QuicksysBrightRed",
  ["92"] = "QuicksysBrightGreen",
  ["93"] = "QuicksysBrightYellow",
  ["94"] = "QuicksysBrightBlue",
  ["95"] = "QuicksysBrightMagenta",
  ["96"] = "QuicksysBrightCyan",
  ["97"] = "QuicksysBrightWhite",
}

local VALID_COLORS = { "0", "1", "2", "3", "4", "5", "6", "7" }

-- pseudo enum for state values
local NORMAL      = 1
local BEGIN_ESC   = 2
local IN_ESC      = 3
local BEGIN_COLOR = 4
local IN_COLOR    = 5

Parser.new = function(data)
  local self = setmetatable({}, Parser)
  self.data = data
  self.state = NORMAL
  self.chunks = {}
  self.current_text = ""
  self.current_hl = nil
  return self
end

function Parser:consume()
  if self.current_text ~= "" then
    table.insert(self.chunks, { self.current_text, self.current_hl })
  end
  self.current_text = ""
  self.current_hl = nil
end

function Parser:parse()
  if not self.data then return end

  local chars = vim.split(self.data, "")
  for i, c in ipairs(chars) do

    if self.state == NORMAL then
      if c == "\27" then
        self:consume()
        self.state = BEGIN_ESC
      else
        self.current_text = self.current_text .. c
      end

    elseif self.state == BEGIN_ESC then
      if c == "[" then
        self.state = IN_ESC
      else
        return nil, "EXPECTED ["
      end

    elseif self.state == IN_ESC then
      if c == "0" then
        self.bold = false
        self.current_hl = nil
      elseif c == "1" then
        self.bold = true
      elseif c == "3" or c == "9" then
        self.state = BEGIN_COLOR
      elseif c == ";" then
        -- no-op
      elseif c == "m" then
        self.state = NORMAL
      else
        return nil, "ERROR??"
      end

    elseif self.state == BEGIN_COLOR then
      if vim.tbl_contains(VALID_COLORS, c) then
        local colorcode = chars[i-1] .. c
        self.current_hl = FG_COLOR[colorcode]
        self.state = IN_COLOR
      else
        return nil, "EXPECTED 0..7"
      end

    elseif self.state == IN_COLOR then
      if c == "m" then
        self.state = NORMAL
      elseif c == ";" then
        -- no-op
      else
        return nil, "ERROR???"
      end

    end

  end

  self:consume()
  return self.chunks
end

return Parser
