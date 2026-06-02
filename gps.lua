local util = require "util"
local linalg = require "linalg"
local pid = require "pid"

local sc_idx = {
  left_back = 1,
  left_mid = 2,
  left_front = 3,
  right_back = 4,
  right_mid = 5,
  right_front = 6,
}

local config_path = "flight-controller.data"
local config = util.read_data(config_path) or {
  destinations = {},
  pois = {},
  compass = nil,
  monitor = nil,
  gimbal = nil,
  speed_controllers = {},
  tilt_controller = nil,

  pid_pitch = {
    p = 0.0,
    i = 0.0,
    d = 0.0,
    i_init = 0.0,
    i_min = 0.0,
    i_max = 0.0,
  },
  pid_roll = {
    p = 0.0,
    i = 0.0,
    d = 0.0,
    i_init = 0.0,
    i_min = 0.0,
    i_max = 0.0,
  },
  base = 0,
}

local function build_caches()
  local cache = {
    pois = {},
    compass = nil,
    monitor = nil,
    gimbal = nil,
    speed_controllers = {},
    tilt_controller = nil,
  }
  for k,v in pairs(config.pois) do
    table.insert(cache.pois, {
      nav = util.find_peripheral("navigation_table", k),
      x = v.x,
      y = v.y,
    })
  end
  if config.compass then
    cache.compass = util.find_peripheral("navigation_table", config.compass)
  end
  if config.monitor then
    cache.monitor = util.find_peripheral("monitor", config.monitor)
  end
  if config.gimbal then
    cache.gimbal = util.find_peripheral("gimbal_sensor", config.gimbal)
  end
  for i,v in ipairs(config.speed_controllers) do
    local mult = 1.0
    if v.flip then mult = -1.0 end
    cache.speed_controllers[i] = {
      controller = util.find_peripheral("Create_RotationSpeedController", v.id),
      mult = mult,
    }
  end
  for i=1,6 do
    if not cache.speed_controllers[i] then
      cache.speed_controllers = nil
      break
    end
  end
  if config.tilt_controller then
    cache.tilt_controller = util.find_peripheral("restone_relay", config.tilt_controller)
  end
  return cache
end

local position = nil
local target = nil
local cache = build_caches()
local too_few_pois = true

local function set_speed_controller(idx, speed)
  local c = cache.speed_controllers[idx]
  c.controller.setTargetSpeed(util.clamp(-70, speed * c.mult, 70))
end

local function pick_saved_destination()
  if #config.destinations == 0 then
    return nil
  end

  for i = 1, #config.destinations do
    local dst = config.destinations[i]
    io.stdout:write(string.format(
      "%d: %s (x:%d, y:%d)\n",
      i, dst.name, dst.x, dst.y
    ))
    io.stdout:flush()
  end

  return util.ask_number("choice", 1, #config.destinations)
end

local function pick_poi()
  local count = 0
  for k, v in pairs(config.pois) do
    count = count + 1
    io.stdout:write(string.format(
      "%d: (x:%d, y:%d)\n",
      k, v.x, v.y
    ))
    io.stdout:flush()
  end

  if count == 0 then return nil end

  while true do
    local idx = util.ask_number("choice", nil, nil)
    if not idx then return nil end
    if config.pois[idx] then
      return idx
    end
    util.bad_answer()
  end
end

local function select_saved_destination()
  print("select saved destination")
  local idx = pick_saved_destination()
  if not idx then
    print("no saved destinations")
    return
  end

  local dst = config.destinations[idx]
  local x = dst.x
  local y = dst.y
  local name = dst.name

  io.stdout:write(string.format("going to %d,%d (%s)\n", x, y, name))
  io.stdout:flush()
  target = { x = x, y = y }
end

local function select_adhoc_destination()
  print("select ad-hoc destination")

  local name = "ad-hoc"
  local save = util.ask_bool("save?")
  if not save then return end
  local x = util.ask_number("X", nil, nil)
  if not x then return end
  local y = util.ask_number("Y", nil, nil)
  if not y then return end

  if save then
    io.stdout:write("name: ")
    io.stdout:flush()
    name = read()
  end

  io.stdout:write(string.format("going to %d,%d (%s)\n", x, y, name))
  io.stdout:flush()
  target = { x = x, y = y }

  if save then
    table.insert(config.destinations, {
      x = x,
      y = y,
      name = name,
    })
    util.write_data(config_path, config)
  end
end

local function remove_saved_destination()
  print("remove saved destination")
  local idx = pick_saved_destination()
  if not idx then
    print("no saved destinations")
    return
  end

  local dst = config.destinations[idx]
  local x = dst.x
  local y = dst.y
  local name = dst.name

  io.stdout:write(string.format("removing destination %d,%d (%s)\n", x, y, name))
  io.stdout:flush()

  local save = util.ask_bool("confirm?")
  if not save then return end

  table.remove(config.destinations, idx)
  util.write_data(config_path, config)

  io.stdout:write(string.format("%s removed\n", name))
  io.stdout:flush()
end

local function create_poi()
  print("create POI")

  local id = util.ask_number("nav table id", 0, nil)
  if not id then return end
  local x = util.ask_number("X", nil, nil)
  if not x then return end
  local y = util.ask_number("Y", nil, nil)
  if not y then return end

  config.pois[id] = { x = x, y = y }
  cache = build_caches()
  util.write_data(config_path, config)
end

local function remove_poi()
  print("remove POI")
  local id = pick_poi()
  if not id then
    print("no POIs")
    return;
  end

  config.pois[id] = nil
  cache = build_caches()
  util.write_data(config_path, config)
end

local function set_compass()
  print("set compass nav table")

  local id = util.ask_number("nav table id", 0, nil)
  if not id then return end

  config.compass = id
  cache = build_caches()
  util.write_data(config_path, config)
end

local function set_monitor()
  print("set monitor")

  local id = util.ask_number("monitor id", 0, nil)
  if not id then return end

  config.monitor = id
  cache = build_caches()
  util.write_data(config_path, config)
end

local function set_gimbal()
  print("set gimbal")

  local id = util.ask_number("gimbal id", 0, nil)
  if not id then return end

  config.gimbal = id
  cache = build_caches()
  util.write_data(config_path, config)
end

local function set_propeller_speed_controller()
  print("set propeller speed controller")

  io.stdout:write("select speed controller:\n")
  io.stdout:write("1: left back\n")
  io.stdout:write("2: left mid\n")
  io.stdout:write("3: left front\n")
  io.stdout:write("4: right back\n")
  io.stdout:write("5: right mid\n")
  io.stdout:write("6: right front\n")
  io.stdout:flush()

  local idx = util.ask_number("select speed controller", 1, 6)
  if not idx then return end

  local id = util.ask_number("speed controller id", nil, nil)
  if not id then return end

  local flip = util.ask_bool("flip")
  if not (flip ~= nil) then return end

  config.speed_controllers[idx] = {
    id = id,
    flip = flip,
  }
  cache = build_caches()
  util.write_data(config_path, config)
end

local function set_propeller_tilt_controller()
  print("set propeller tilt controller")

  local id = util.ask_number("redstone relay id", nil, nil)
  if not id then return end

  config.tilt_controller = id
  cache = build_caches()
  util.write_data(config_path, config)
end

local function configure_pid()
  print("configure pid")

  io.stdout:write("1: altitude\n")
  io.stdout:write("2: pitch\n")
  io.stdout:write("3: roll\n")
  io.stdout:flush()

  local idx = util.ask_number("select PID", 1, 3)
  if not idx then return end

  if idx == 1 then
    local base = util.ask_number("base", -128, 128)
    if not base then return end
    config.base = base
    util.write_data(config_path, config)
  else
    local pid = config.pid_pitch
    if idx == 3 then pid = config.pid_roll end

    io.stdout:write(string.format("1: proportional constant (%f)\n", pid.p))
    io.stdout:write(string.format("2: integral constant (%f)\n", pid.i))
    io.stdout:write(string.format("3: derivative constant (%f)\n", pid.d))
    io.stdout:write(string.format("4: integral init (%f)\n", pid.i_init))
    io.stdout:write(string.format("5: integral min (%f)\n", pid.i_min))
    io.stdout:write(string.format("6: integral max (%f)\n", pid.i_max))
    io.stdout:flush()

    local const_idx = util.ask_number("select constant", 1, 6)
    if not const_idx then return end

    local const = util.ask_number("select value", nil, nil)
    if not const then return end

    if const_idx == 1 then pid.p = const
    elseif const_idx == 2 then pid.i = const
    elseif const_idx == 3 then pid.d = const
    elseif const_idx == 4 then pid.i_init = const
    elseif const_idx == 5 then pid.i_min = const
    elseif const_idx == 6 then pid.i_max = const
    end
    util.write_data(config_path, config)
  end
end

local function interactive()
  while true do
    io.stdout:write("\n")
    if position then
      if too_few_pois then
        io.stdout:write("(inaccurate) ")
      end
      io.stdout:write(string.format(
        "x:%d y:%d",
        position.x, position.y
      ))
    end
    if target and position then
      local dx = target.x - position.x
      local dy = target.y - position.y
      io.stdout:write(string.format(
        " dx:%d dy:%d dst:%d",
        dx, dy, math.sqrt(dx * dx + dy * dy)
      ))
    end
    if position then
      io.stdout:write("\n")
    end
    io.stdout:write("select operation:\n")
    io.stdout:write("1: select saved destination\n")
    io.stdout:write("2: select ad-hoc destination\n")
    io.stdout:write("3: remove saved destination\n")
    io.stdout:write("4: create POI\n")
    io.stdout:write("5: remove POI\n")
    io.stdout:write("6: set compass\n")
    io.stdout:write("7: set monitor\n")
    io.stdout:write("8: set gimbal\n")
    io.stdout:write("9: set propeller speed controller\n")
    io.stdout:write("0: set propeller tilt controller\n")
    io.stdout:write("-: configure PID\n")
    io.stdout:write("> ")
    io.stdout:flush()

    local handlers = {
      ["1"] = select_saved_destination,
      ["2"] = select_adhoc_destination,
      ["3"] = remove_saved_destination,
      ["4"] = create_poi,
      ["5"] = remove_poi,
      ["6"] = set_compass,
      ["7"] = set_monitor,
      ["8"] = set_gimbal,
      ["9"] = set_propeller_speed_controller,
      ["0"] = set_propeller_tilt_controller,
      ["-"] = configure_pid,
    }

    local handler = handlers[read()]
    if handler then
      handler()
    else
      util.bad_answer()
    end
  end
end

local function flight_controller()
  local pid_pitch = {
    accumulator = config.pid_pitch.i_init,
    prev_error = 0.0,
  }
  local pid_roll = {
    accumulator = config.pid_roll.i_init,
    prev_error = 0.0,
  }
  local dt = 0.05

  while true do
    sleep(dt)

    if not cache.gimbal then print("no gimbal"); goto continue end

    local gimbal = cache.gimbal.getAnglesRad()
    local error_pitch = gimbal[2]
    local error_roll = gimbal[1]

    if target and position and cache.compass then
      local north = -cache.compass.getRelativeAngleRad()

      local dx = target.x - position.x
      local dy = target.y - position.y

      local slow_distance = 100
      local angle_limit = 0.174 -- 10°
      local mul = 1.0 / slow_distance * angle_limit

      local x_adjustment = util.clamp(-slow_distance, dx, slow_distance) * mul
      local y_adjustment = util.clamp(-slow_distance, dy, slow_distance) * mul

      -- print("distance", math.sqrt(dx * dx + dy * dy))
      -- print("position.x", position.x)
      -- print("position.y", position.y)
      -- print("x_adjustment", x_adjustment)
      -- print("y_adjustment", y_adjustment)
      -- print("north", north)

      error_pitch = error_pitch - math.sin(north) * x_adjustment + math.cos(north) * y_adjustment
      error_roll = error_roll - math.cos(north) * x_adjustment - math.sin(north) * y_adjustment
    end

    local corr_pitch = pid.pid_contoller(
      pid_pitch,
      config.pid_pitch,
      error_pitch * 20.0,
      dt,
      "y"
    ) * 0.1
    local corr_roll = pid.pid_contoller(
      pid_roll,
      config.pid_roll,
      error_roll * 20.0,
      dt,
      "x"
    ) * 0.1

    if cache.speed_controllers and config.base then
      set_speed_controller(sc_idx.left_mid, config.base)
      set_speed_controller(sc_idx.right_mid, config.base)

      set_speed_controller(sc_idx.left_front,  config.base * math.exp(0.0 - corr_roll + corr_pitch))
      set_speed_controller(sc_idx.left_back,   config.base * math.exp(0.0 - corr_roll - corr_pitch))
      set_speed_controller(sc_idx.right_front, config.base * math.exp(0.0 + corr_roll + corr_pitch))
      set_speed_controller(sc_idx.right_back,  config.base * math.exp(0.0 + corr_roll - corr_pitch))
    end

    if cache.monitor then
      cache.monitor.clear()
      cache.monitor.setCursorPos(1,1)
      cache.monitor.write(string.format("pitch: %f a: %f", corr_pitch, error_pitch))
      cache.monitor.setCursorPos(1,2)
      cache.monitor.write(string.format("roll: %f a: %f", corr_roll, error_roll))
      if target then
        cache.monitor.setCursorPos(1,3)
        cache.monitor.write(string.format("target: %d,%d", target.x, target.y))
      end
      if position then
        cache.monitor.setCursorPos(1,4)
        cache.monitor.write(string.format("position: %d,%d", position.x, position.y))
      end
      pid.visualize_pid(cache.monitor)
    end

    ::continue::
  end
end

local function gps()
  while true do
    sleep(0.1)
    
    if not cache.compass then goto continue end
    local bearing = cache.compass.getRelativeAngleRad()
    if not bearing then goto continue end

    local datapoints = {}
    for _,v in ipairs(cache.pois) do
      local a = v.nav.getRelativeAngleRad()
      if a then
        table.insert(datapoints, {
          x = v.x,
          y = v.y,
          cos = math.cos(a - bearing),
          sin = math.sin(a - bearing),
        })
      end
    end

    too_few_pois = #datapoints < 2

    local mat_a = {}
    local mat_b = {}

    for _,v in ipairs(datapoints) do
      table.insert(mat_a, { v.cos, -v.sin })
      table.insert(mat_b, { v.cos * v.x + v.sin * v.y })
    end

    local mat_a_transpose = linalg.matrix_transpose(mat_a)
    local mat_c = linalg.matrix_multiply(mat_a_transpose, mat_a)
    local mat_c_inv = linalg.matrix_inv2x2(mat_c)
    local mat_d = linalg.matrix_multiply(mat_c_inv, mat_a_transpose)
    local mat_e = linalg.matrix_multiply(mat_d, mat_b)

    position = {
      x = mat_e[1][1],
      y = -mat_e[2][1],
    }
    ::continue::
  end
end

parallel.waitForAny(interactive, gps, flight_controller)
