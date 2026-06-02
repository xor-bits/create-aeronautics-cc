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
    io.stdout:write("it was a simple question\n")
  elseif n == 2 then
    io.stdout:write("how did you typo that???\n")
  elseif n == 3 then
    io.stdout:write("learn to type\n")
  elseif n == 4 then
    io.stdout:write("wrong keyboard layout?\n")
  elseif n == 5 then
    io.stdout:write("wrong answer!!\n")
  elseif n == 6 then
    io.stdout:write("ask someone else to use the computer\n")
  elseif n == 7 then
    io.stdout:write("have you tried turning it off and on again?\n")
  end
end

function util.ask_bool(msg)
  while true do
    io.stdout:write(msg)
    io.stdout:write(" (y/N/q)\n> ")
    io.stdout:flush()
    local answer = read()
    if answer == "" or answer == "n" or answer == "N" then
      return false
    elseif answer == "y" or answer == "Y" then
      return true
    elseif answer == "q" then
      return nil
    end
    util.bad_answer()
  end
end

function util.ask_number(msg, min, max)
  while true do
    io.stdout:write(msg)
    io.stdout:write(" (number/q)\n> ")
    io.stdout:flush()
    local answer = read()
    if answer == "q" then return nil end
    local number = tonumber(answer)
    if number and (not min or number >= min) and (not max or number <= max) then
      return number
    end
    util.bad_answer()
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
