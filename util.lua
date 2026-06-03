local completion = require "cc.completion"

local util = {}

function util.find_peripheral(name, nth)
  local full_name = string.format("%s_%d", name, nth);
  return peripheral.find(name, function(candidate_name, _)
    return candidate_name == full_name
  end)
end

function util.clamp(min, val, max)
  return math.max(min, math.min(max, val))
end

function util.bad_answer()
  local n = math.random(7)
  if n == 1 then
    return "it was a simple question"
  elseif n == 2 then
    return "how did you typo that???"
  elseif n == 3 then
    return "learn to type"
  elseif n == 4 then
    return "wrong keyboard layout?"
  elseif n == 5 then
    return "wrong answer!!"
  elseif n == 6 then
    return "ask someone else to use the computer"
  elseif n == 7 then
    return "have you tried turning it off and on again?"
  end
end

function util.ask_bool(monitor, y, msg)
  local choice = util.ask_choice(monitor, y, msg, { "y", "n" }, true)
  if not choice then return nil end

  if choice == "n" then
    return false
  else
    assert(choice == "y")
    return true
  end
end

function util.ask_text(monitor, y, msg)
  monitor.setCursorPos(1, y)
  monitor.clearLine()
  monitor.write(msg)
  monitor.write(" (text/q)")
  monitor.setCursorPos(1, y + 1)
  monitor.clearLine()
  monitor.write("> ")

  local answer = read()
  if answer == "q" then return nil end
  return answer
end

function util.ask_number(monitor, y, msg, min, max)
  local first_try = true
  while true do
    monitor.setCursorPos(1, y)
    monitor.clearLine()
    monitor.write(msg)
    local min_text = min or "-inf"
    local max_text = max or "inf"
    monitor.write((" (%s..%s/q)"):format(min_text, max_text))
    monitor.setCursorPos(1, y + 1)
    monitor.clearLine()
    if not first_try then
      monitor.write(util.bad_answer())
      monitor.write("  ")
    end
    monitor.write("> ")

    first_try = false
    local answer = read()
    if answer == "q" then return nil end
    local number = tonumber(answer)
    if number and (not min or number >= min) and (not max or number <= max) then
      return number
    end
  end
end

function util.ask_choice(monitor, y, msg, choices, default)
  local first_try = true
  while true do
    monitor.setCursorPos(1, y)
    monitor.clearLine()
    monitor.write(msg)
    monitor.write(" (")
    for i=1,(#choices - 1) do
      monitor.write(choices[i])
      monitor.write("/")
    end
    if default then
      monitor.write(string.upper(choices[#choices]))
    else
      monitor.write(choices[#choices])
    end
    monitor.write("/")
    monitor.write("q)")
    monitor.setCursorPos(1, y + 1)
    monitor.clearLine()
    if not first_try then
      monitor.write(util.bad_answer())
      monitor.write("  ")
    end
    monitor.write("> ")

    first_try = false
    local answer = string.lower(read(nil, nil, function(text)
      return completion.choice(text, choices)
    end))

    if default and answer == "" then return choices[#choices] end
    if answer == "q" then return nil end
    for _,v in ipairs(choices) do
      if answer == v then
        return answer
      end
    end
  end
end

function util.read_data(path)
  local destinations = fs.open(path, "r")
  if not destinations then return nil end
  local str = destinations.readAll()
  destinations.close()
  return textutils.unserialize(str)
end

function util.write_data(path, data)
  local destinations = fs.open(path, "w")
  destinations.write(textutils.serialize(data, { compact = false, allow_repetitions = true }))
  destinations.close()
end

return util
