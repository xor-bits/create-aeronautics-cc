local function find_peripheral(name, nth)
  local full_name = string.format("%s_%d", name, nth);
  return peripheral.find(name, function(candidate_name, _)
    return candidate_name == full_name
  end)
end

local function bad_answer()
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

local function ask_bool(msg)
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
    bad_answer()
  end
end

local function ask_number(msg, min, max)
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
    bad_answer()
  end
end

local function read_saved_destinations()
  local destinations = fs.open("destinations", "r")
  if not destinations then return {} end
  local str = destinations.readAll()
  destinations.close()
  return textutils.unserialize(str)
end

local function write_saved_destinations(saved)
  local destinations = fs.open("destinations", "w")
  destinations.write(textutils.serialize(saved, { compact = true, allow_repetitions = true }))
  destinations.close()
end

local function read_saved_pois()
  local pois = fs.open("pois", "r")
  if not pois then return {} end
  local str = pois.readAll()
  pois.close()
  return textutils.unserialize(str)
end

local function write_saved_pois(saved)
  local pois = fs.open("pois", "w")
  pois.write(textutils.serialize(saved, { compact = true, allow_repetitions = true }))
  pois.close()
end

local function cache_nav_tables(pois)
  local cache = {}
  for k,v in pairs(pois) do
    table.insert(cache, {
      nav = find_peripheral("navigation_table", k),
      x = v.x,
      y = v.y,
    })
  end
  return cache
end

local saved = read_saved_destinations()
local pois = read_saved_pois()
local nav_tables = cache_nav_tables(pois)

local function pick_saved_destination()
  if #saved == 0 then
    return nil
  end

  for i = 1, #saved do
    local dst = saved[i]
    io.stdout:write(string.format(
      "%d: %s (x:%d, y:%d)\n",
      i, dst.name, dst.x, dst.y
    ))
    io.stdout:flush()
  end

  return ask_number("choice", 1, #saved)
end

local function pick_poi()
  local count = 0
  for k, v in pairs(pois) do
    count = count + 1
    io.stdout:write(string.format(
      "%d: (x:%d, y:%d)\n",
      k, v.x, v.y
    ))
    io.stdout:flush()
  end

  if count == 0 then return nil end

  while true do
    local idx = ask_number("choice", nil, nil)
    if not idx then return nil end
    if pois[idx] then
      return idx
    end
    bad_answer()
  end
end

local function select_saved_destination()
  print("select saved destination")
  local idx = pick_saved_destination()
  if not idx then
    print("no saved destinations")
    return
  end

  local dst = saved[idx]
  local x = dst.x
  local y = dst.y
  local name = dst.name

  io.stdout:write(string.format("going to %d,%d (%s)\n", x, y, name))
  io.stdout:flush()
end

local function select_adhoc_destination()
  print("select ad-hoc destination")

  local name = "ad-hoc"
  local save = ask_bool("save?")
  if not save then return end
  local x = ask_number("X", nil, nil)
  if not x then return end
  local y = ask_number("Y", nil, nil)
  if not y then return end

  if save then
    io.stdout:write("name: ")
    io.stdout:flush()
    name = read()
  end

  io.stdout:write(string.format("going to %d,%d (%s)\n", x, y, name))
  io.stdout:flush()

  if save then
    table.insert(saved, {
      x = x,
      y = y,
      name = name,
    })
    write_saved_destinations(saved)
  end
end

local function remove_saved_destination()
  print("remove saved destination")
  local idx = pick_saved_destination()
  if not idx then
    print("no saved destinations")
    return
  end

  local dst = saved[idx]
  local x = dst.x
  local y = dst.y
  local name = dst.name

  io.stdout:write(string.format("removing destination %d,%d (%s)\n", x, y, name))
  io.stdout:flush()

  local save = ask_bool("confirm?")
  if not save then return end

  table.remove(saved, idx)
  write_saved_destinations(saved)

  io.stdout:write(string.format("%s removed\n", name))
  io.stdout:flush()
end

local function create_poi()
  print("create POI")

  local id = ask_number("nav table id", 0, nil)
  if not id then return end
  local x = ask_number("X", nil, nil)
  if not x then return end
  local y = ask_number("Y", nil, nil)
  if not y then return end

  pois[id] = { x = x, y = y }
  nav_tables = cache_nav_tables(pois)
  write_saved_pois(pois)
end

local function remove_poi()
  print("remove POI")
  local id = pick_poi()
  if not id then
    print("no POIs")
    return;
  end

  pois[id] = nil
  nav_tables = cache_nav_tables(pois)
  write_saved_pois(pois)
end

local function interactive()
  while true do
    io.stdout:write("select operation:\n")
    io.stdout:write("1: select saved destination\n")
    io.stdout:write("2: select ad-hoc destination\n")
    io.stdout:write("3: remove saved destination\n")
    io.stdout:write("4: create POI\n")
    io.stdout:write("5: remove POI\n> ")
    io.stdout:flush()

    local handlers = {
      ["1"] = select_saved_destination,
      ["2"] = select_adhoc_destination,
      ["3"] = remove_saved_destination,
      ["4"] = create_poi,
      ["5"] = remove_poi,
    }

    local handler = handlers[read()]
    if handler then
      handler()
    else
      bad_answer()
    end
  end
end

local function matrix_transpose(matrix)
  local src_h = #matrix
  local src_w = #matrix[1]

  local result = {}

  for i=1,src_w do
    result[i] = {}
    for j=1,src_h do
      result[i][j] = matrix[j][i]
    end
  end

  return result
end

local function matrix_multiply(a, b)
  local a_h = #a
  local a_w = #a[1]
  local b_h = #b
  local b_w = #b[1]
  assert(a_w == b_h, "matrix multiplication size mismatch")

  local result = {}

  for j=1,a_h do
    result[j] = {}
    for i=1,b_w do
      local sum = 0.0
      for k=1,a_w do
        sum = sum + a[j][k] * b[k][i]
      end
      result[j][i] = sum
    end
  end

  return result
end

local function matrix_inv2x2(matrix)
  local h = #matrix
  local w = #matrix[1]
  assert(h == 2)
  assert(w == 2)

  local c = 1.0 / (matrix[1][1] * matrix[2][2] - matrix[1][2] * matrix[2][1])
  return {
    { c * matrix[2][2], -c * matrix[1][2] },
    { -c * matrix[2][1], c * matrix[1][1] },
  }
end

local function background()
  while true do
    sleep(1)
    if #nav_tables ~= 2 then
      goto continue
    end

    local alpha = nav_tables[1].nav.getRelativeAngleRad() - math.pi / 2.0
    local beta  = nav_tables[2].nav.getRelativeAngleRad() - math.pi / 2.0
    local tan_alpha = math.tan(alpha)
    local tan_beta = math.tan(beta)

    local mat_a = {
      { 1, tan_alpha },
      { 1, tan_beta },
    }
    local mat_b = {
      { nav_tables[1].x + nav_tables[1].y * tan_alpha },
      { nav_tables[2].x + nav_tables[2].y * tan_beta },
    }
    local mat_a_transpose = matrix_transpose(mat_a)

    local mat_c = matrix_multiply(mat_a, mat_a_transpose)
    local mat_c_inv = matrix_inv2x2(mat_c)
    local mat_d = matrix_multiply(mat_c_inv, mat_a_transpose)
    local mat_e = matrix_multiply(mat_d, mat_b)

    print(mat_e[1][1], mat_e[2][1])
    ::continue::
  end
end

parallel.waitForAny(interactive, background)
