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

local sc_info = {
  { id = "left_back",   name = "left  back ", },
  { id = "left_mid",    name = "left  mid  ", },
  { id = "left_front",  name = "left  front", },
  { id = "right_back",  name = "right back ", },
  { id = "right_mid",   name = "right mid  ", },
  { id = "right_front", name = "right front", },
}

local default_pid = {
  p = 0.0,
  i = 0.0,
  d = 0.0,
  i_init = 0.0,
  i_min = 0.0,
  i_max = 0.0,
}
local config_path = "flight-controller.data"
local config = util.read_data(config_path) or {}

local function repair_config_pid(pid)
  if not pid.p then pid.p = 0.0 end
  if not pid.i then pid.i = 0.0 end
  if not pid.d then pid.d = 0.0 end
  if not pid.i_init then pid.i_init = 0.0 end
  if not pid.i_min then pid.i_min = 0.0 end
  if not pid.i_max then pid.i_max = 0.0 end
  if not pid.base_error then pid.base_error = 0.0 end
end

local function repair_config_misc(misc)
  local init = {
    near_distance = 200.0,
    near_strafe_angle_limit = 0.174, -- 10°
    autopilot_max_boost_bearing_error = 0.1,
    autopilot_boost_angle = 0.1,
  }
  for k,v in pairs(init) do
    if not misc[k] then
      misc[k] = v
    end
  end
end

local function repair_config()
  if not config.destinations then config.destinations = {} end
  if not config.pois then config.pois = {} end
  if not config.speed_controllers then config.speed_controllers = {} end
  if not config.pid_pitch then config.pid_pitch = { table.unpack(default_pid) } end
  if not config.pid_roll then config.pid_roll = { table.unpack(default_pid) } end
  if not config.pid_yaw then config.pid_yaw = { table.unpack(default_pid) } end
  if not config.base then config.base = 0 end
  if not config.misc then config.misc = {} end
  repair_config_pid(config.pid_pitch)
  repair_config_pid(config.pid_roll)
  repair_config_pid(config.pid_yaw)
  repair_config_misc(config.misc)
  util.write_data(config_path, config)
end
repair_config()

local function build_caches()
  local cache = {
    pois = {},
    speed_controllers = {},
  }
  for k,v in pairs(config.pois) do
    local nav = util.find_peripheral("navigation_table", k)
    if nav then
      cache.pois[k] = {
        nav = nav,
        x = v.x,
        y = v.y,
      }
    end
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
  if config.altitude then
    cache.altitude = util.find_peripheral("altitude_sensor", config.altitude)
  end
  if config.linked_typewriter then
    cache.linked_typewriter = util.find_peripheral("linked_typewriter", config.linked_typewriter)
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
    cache.tilt_controller = util.find_peripheral("redstone_relay", config.tilt_controller)
  end
  return cache
end

local position = nil
local target = nil
local cache = build_caches()
local too_few_pois = true
local pid_pitch = {
  accumulator = config.pid_pitch.i_init,
  prev_error = 0.0,
}
local pid_roll = {
  accumulator = config.pid_roll.i_init,
  prev_error = 0.0,
}
local pid_yaw = {
  accumulator = config.pid_yaw.i_init,
  prev_error = 0.0,
}

local function set_speed_controller(idx, speed)
  local c = cache.speed_controllers[idx]
  c.controller.setTargetSpeed(util.clamp(-70, speed * c.mult, 70))
end

local function interactive_menu_selection(monitor, selected, name)
  if selected then
    monitor.write("[")
    monitor.write(name)
    monitor.write("]")
  else
    monitor.write(" ")
    monitor.write(name)
    monitor.write(" ")
  end
end

local function interactive_menu_title(monitor, menu)
  monitor.setCursorPos(1, 1)

  menu.next = nil
  local first_menu = menu
  while first_menu.prev do
    first_menu.prev.next = first_menu
    first_menu = first_menu.prev
  end
  while first_menu do
    local selected = first_menu.next == nil
    interactive_menu_selection(monitor, selected, first_menu.name)
    if not selected then
      monitor.write("- ")
    end
    first_menu = first_menu.next
  end
end

local function interactive_menu(monitor, term_w, term_h, menu)
  monitor.clear()

  interactive_menu_title(monitor, menu)
  monitor.setCursorPos(1, 2)
  monitor.write(("-"):rep(term_w))

  if menu.custom then
    monitor.setCursorPos(1, 3)
    return menu.custom(monitor, term_w, term_h, menu)
  end

  for i,v in ipairs(menu.options) do
    monitor.setCursorPos(1, i + 2)
    interactive_menu_selection(monitor, i == menu.selection, v.name)
  end

  -- monitor.setCursorPos(1, term_h)
  -- monitor.write("")

  local _, key, is_held = os.pullEvent("key")
  if key == keys.down then
    menu.selection = (menu.selection % #menu.options) + 1
    return menu
  elseif key == keys.up then
    menu.selection = ((menu.selection - 2) % #menu.options) + 1
    return menu
  elseif key == keys.left then
    return menu.prev or menu
  elseif key == keys.right or key == keys.enter then
    menu.options[menu.selection].prev = menu
    return menu.options[menu.selection]
  end
  return menu
end

local function interactive_autopilot_target_menu(monitor, term_w, term_h, menu)
  local enabled = false
  if target then
    enabled = menu.x == target.x and menu.y == target.y
  end

  monitor.setCursorPos(1, 3)
  interactive_menu_selection(monitor, true, "enabled")
  monitor.write(("  (%s)"):format(enabled))

  if not position or too_few_pois then
    monitor.setCursorPos(1, 4)
    monitor.write("POSITION INACCURATE")
  elseif target then
    local dx = target.x - position.x
    local dy = target.y - position.y
    local d = math.sqrt(dx * dx + dy * dy)

    monitor.setCursorPos(1, 4)
    monitor.write(("current  x:%d  y:%d"):format(position.x, position.y))
    monitor.setCursorPos(1, 5)
    monitor.write(("target   x:%d  y:%d"):format(target.x, target.y))
    if not enabled then
      monitor.write(" ANOTHER TARGET")
    end
    monitor.setCursorPos(1, 6)
    monitor.write(("delta    x:%d  y:%d"):format(dx, dy))
    monitor.setCursorPos(1, 7)
    monitor.write(("distance d:%.2f"):format(d))
    if d <= config.misc.near_distance then
      monitor.write(" mode:near")
    else
      monitor.write(" mode:far")
    end
  end

  local _, key, is_held = os.pullEvent("key")
  if key == keys.left then
    return menu.prev
  elseif key == keys.right or key == keys.enter then
    if enabled then
      target = nil
    else
      target = { x = menu.x, y = menu.y }
    end
  end
end

local function interactive_autopilot_menu(monitor, term_w, term_h, menu)
  for i,v in ipairs(config.destinations) do
    monitor.setCursorPos(1, i + 2)
    interactive_menu_selection(monitor, i == menu.selection, v.name)
    monitor.write(("  (x:%d y:%d)"):format(v.x, v.y))
  end

  local _, key, is_held = os.pullEvent("key")
  if key == keys.down then
    menu.selection = (menu.selection % #config.destinations) + 1
    return menu
  elseif key == keys.up then
    menu.selection = ((menu.selection - 2) % #config.destinations) + 1
    return menu
  elseif key == keys.left then
    return menu.prev or menu
  elseif key == keys.right or key == keys.enter then
    local dst = config.destinations[menu.selection]
    return {
      name = dst.name,
      prev = menu,
      custom = interactive_autopilot_target_menu,
      x = dst.x,
      y = dst.y,
    }
  elseif key == keys.a then
    os.pullEvent("key_up")

    local ad_hoc = util.ask_bool(monitor, term_h - 7, "ad-hoc (temporary)?")
    if not (ad_hoc ~= nil) then return end
    local name = "ad-hoc"
    if not ad_hoc then
      name = util.ask_text(monitor, term_h - 5, "new destination name?")
      if not name then return end
    end
    local x = util.ask_number(monitor, term_h - 3, "X?")
    if not x then return end
    local y = util.ask_number(monitor, term_h - 1, "Y?")
    if not y then return end

    if not ad_hoc then
      table.insert(config.destinations, {
        name = name,
        x = x,
        y = y,
      })
      util.write_data(config_path, config)
    end
    return {
      name = name,
      prev = menu,
      custom = interactive_autopilot_target_menu,
      x = x,
      y = y,
    }
  elseif key == keys.d then
    os.pullEvent("key_up")

    local selected = config.destinations[menu.selection].name;
    local confirm = util.ask_bool(monitor, term_h - 1, "confirm delete "..selected.."?")
    if not (confirm ~= nil) then return end

    if confirm then
      table.remove(config.destinations, menu.selection)
      util.write_data(config_path, config)
    end
  end
end

local function interactive_config_pois(monitor, term_w, term_h, menu)
  local sorted_pois = {}
  for k,v in pairs(config.pois) do
    table.insert(sorted_pois, {
      id = k,
      x = v.x,
      y = v.y,
    })
  end
  table.sort(sorted_pois, function(a, b)
    return a.id < b.id
  end)

  for i,v in ipairs(sorted_pois) do
    monitor.setCursorPos(1, i + 2)
    interactive_menu_selection(monitor, i == menu.selection, ("%d"):format(v.id))
    monitor.write(("  (x:%d y:%d angle:"):format(v.x, v.y))

    local angle = nil
    if cache.pois[v.id] then
      if cache.pois[v.id].nav then
        angle = cache.pois[v.id].nav.getRelativeAngleRad()
        if not angle then
          monitor.write("no data")
        end
      else
        monitor.write("no nav")
      end
    else
      monitor.write("no poi")
    end
    if angle then
      monitor.write(("%.5f)"):format(angle))
    else
      monitor.write("nil)")
    end
  end

  local _, key, is_held = os.pullEvent("key")
  if key == keys.down then
    menu.selection = (menu.selection % #sorted_pois) + 1
    return menu
  elseif key == keys.up then
    menu.selection = ((menu.selection - 2) % #sorted_pois) + 1
    return menu
  elseif key == keys.left then
    return menu.prev or menu
  elseif key == keys.a then
    os.pullEvent("key_up")

    local id = util.ask_number(monitor, term_h - 5, "nav table id?")
    if not id then return end
    local x = util.ask_number(monitor, term_h - 3, "X?")
    if not x then return end
    local y = util.ask_number(monitor, term_h - 1, "Y?")
    if not y then return end

    config.pois[id] = {
      x = x,
      y = y,
    }
    cache = build_caches()
    util.write_data(config_path, config)
  elseif key == keys.d then
    os.pullEvent("key_up")

    local selected = sorted_pois[menu.selection].id;
    local confirm = util.ask_bool(monitor, term_h - 1, "confirm delete "..selected.."?")
    if not (confirm ~= nil) then return end

    if confirm then
      config.pois[selected] = nil
      cache = build_caches()
      util.write_data(config_path, config)
    end
  end
end

local function interactive_config_pid_menu(monitor, term_w, term_h, menu)
  monitor.setCursorPos(1, 3)
  interactive_menu_selection(monitor, 1 == menu.selection, "proportional ")
  monitor.write(("  %f"):format(menu.pid.p))
  monitor.setCursorPos(1, 4)
  interactive_menu_selection(monitor, 2 == menu.selection, "integral     ")
  monitor.write(("  %f"):format(menu.pid.i))
  monitor.setCursorPos(1, 5)
  interactive_menu_selection(monitor, 3 == menu.selection, "derivative   ")
  monitor.write(("  %f"):format(menu.pid.d))
  monitor.setCursorPos(1, 6)
  interactive_menu_selection(monitor, 4 == menu.selection, "integral init")
  monitor.write(("  %f"):format(menu.pid.i_init))
  monitor.setCursorPos(1, 7)
  interactive_menu_selection(monitor, 5 == menu.selection, "integral min ")
  monitor.write(("  %f"):format(menu.pid.i_min))
  monitor.setCursorPos(1, 8)
  interactive_menu_selection(monitor, 6 == menu.selection, "integral max ")
  monitor.write(("  %f"):format(menu.pid.i_max))
  monitor.setCursorPos(1, 9)
  interactive_menu_selection(monitor, 7 == menu.selection, "base error   ")
  monitor.write(("  %f"):format(menu.pid.base_error))
  monitor.setCursorPos(1, 10)
  interactive_menu_selection(monitor, 8 == menu.selection, "visualize    ")
  if menu.pid.visualize then
    monitor.write(("  %s"):format(menu.pid.visualize))
  end
  monitor.setCursorPos(1, 11)
  interactive_menu_selection(monitor, 9 == menu.selection, "save integral accumulator")

  local _, key, is_held = os.pullEvent("key")
  if key == keys.down then
    menu.selection = (menu.selection % 8) + 1
    return menu
  elseif key == keys.up then
    menu.selection = ((menu.selection - 2) % 8) + 1
    return menu
  elseif key == keys.left then
    return menu.prev or menu
  elseif key == keys.right or key == keys.enter then
    os.pullEvent("key_up")

    if 9 == menu.selection then
      if menu.pid == config.pid_pitch then menu.pid.i_init = pid_pitch.accumulator
      elseif menu.pid == config.pid_roll then menu.pid.i_init = pid_roll.accumulator
      elseif menu.pid == config.pid_yaw then menu.pid.i_init = pid_yaw.accumulator
      end
      util.write_data(config_path, config)
      return
    end

    if 8 == menu.selection then
      local new_val = util.ask_choice(monitor, term_h - 1, "axis", { "x", "y", "nil" })
      if not new_val then return end
      if new_val == "nil" then
        new_val = nil
      else
        if config.pid_pitch.visualize == new_val then
          config.pid_pitch.visualize = nil
        elseif config.pid_roll.visualize == new_val then
          config.pid_roll.visualize = nil
        elseif config.pid_yaw.visualize == new_val then
          config.pid_yaw.visualize = nil
        end
      end

      menu.pid.visualize = new_val
      util.write_data(config_path, config)
      return
    end

    local new_val = util.ask_number(monitor, term_h - 1, "new value")
    if not new_val then return end

    if 1 == menu.selection then menu.pid.p = new_val
    elseif 2 == menu.selection then menu.pid.i = new_val
    elseif 3 == menu.selection then menu.pid.d = new_val
    elseif 4 == menu.selection then menu.pid.i_init = new_val
    elseif 5 == menu.selection then menu.pid.i_min = new_val
    elseif 6 == menu.selection then menu.pid.i_max = new_val
    elseif 7 == menu.selection then menu.pid.base_error = new_val
    end
    util.write_data(config_path, config)
  end
end

local function interactive_config_compass_menu(monitor, term_w, term_h, menu)
  local current_val = nil
  if cache.compass then
    current_val = cache.compass.getRelativeAngleRad()
  end

  monitor.setCursorPos(1, 3)
  interactive_menu_selection(monitor, 1 == menu.selection, "id")
  monitor.write(("  (%s angle:"):format(config.compass))
  if current_val then
    monitor.write(("%.5f)"):format(current_val))
  else
    monitor.write("nil)")
  end

  local _, key, is_held = os.pullEvent("key")
  if key == keys.left then
    return menu.prev or menu
  elseif key == keys.right or key == keys.enter then
    os.pullEvent("key_up")

    local id = util.ask_number(monitor, term_h - 1, "compass id?")
    if id then
      config.compass = id
      cache = build_caches()
      util.write_data(config_path, config)
    end
  end
end

local function interactive_config_monitor_menu(monitor, term_w, term_h, menu)
  local found = cache.monitor ~= nil

  monitor.setCursorPos(1, 3)
  interactive_menu_selection(monitor, 1 == menu.selection, "id")
  monitor.write(("  (%s found:%s)"):format(config.monitor, found))

  local _, key, is_held = os.pullEvent("key")
  if key == keys.left then
    return menu.prev or menu
  elseif key == keys.right or key == keys.enter then
    os.pullEvent("key_up")

    local id = util.ask_number(monitor, term_h - 1, "monitor id?")
    if id then
      config.monitor = id
      cache = build_caches()
      util.write_data(config_path, config)
    end
  end
end

local function interactive_config_gimbal_menu(monitor, term_w, term_h, menu)
  local current_vals = nil
  if cache.gimbal then
    current_vals = cache.gimbal.getAnglesRad()
  end

  monitor.setCursorPos(1, 3)
  interactive_menu_selection(monitor, 1 == menu.selection, "id")
  monitor.write(("  (%s x:"):format(config.gimbal))
  if current_vals then
    monitor.write(("%.5f y:%.5f)"):format(current_vals[1], current_vals[2]))
  else
    monitor.write("nil y:nil)")
  end

  local _, key, is_held = os.pullEvent("key")
  if key == keys.left then
    return menu.prev or menu
  elseif key == keys.right or key == keys.enter then
    os.pullEvent("key_up")

    local id = util.ask_number(monitor, term_h - 1, "gimbal id?")
    if id then
      config.gimbal = id
      cache = build_caches()
      util.write_data(config_path, config)
    end
  end
end

local function interactive_config_altitude_menu(monitor, term_w, term_h, menu)
  local current_val = nil
  if cache.altitude then
    current_val = cache.altitude.getHeight()
  end

  monitor.setCursorPos(1, 3)
  interactive_menu_selection(monitor, 1 == menu.selection, "id")
  monitor.write(("  (%s y:"):format(config.altitude))
  if current_val then
    monitor.write(("%.5f)"):format(current_val))
  else
    monitor.write("nil)")
  end

  local _, key, is_held = os.pullEvent("key")
  if key == keys.left then
    return menu.prev or menu
  elseif key == keys.right or key == keys.enter then
    os.pullEvent("key_up")

    local id = util.ask_number(monitor, term_h - 1, "altitude id?")
    if id then
      config.altitude = id
      cache = build_caches()
      util.write_data(config_path, config)
    end
  end
end

local function interactive_config_linked_typewriter_menu(monitor, term_w, term_h, menu)
  local found = cache.linked_typewriter ~= nil
  monitor.setCursorPos(1, 3)
  interactive_menu_selection(monitor, 1 == menu.selection, "id")
  monitor.write(("  (%s found:%s)"):format(config.linked_typewriter, found))

  local _, key, is_held = os.pullEvent("key")
  if key == keys.left then
    return menu.prev or menu
  elseif key == keys.right or key == keys.enter then
    os.pullEvent("key_up")

    local id = util.ask_number(monitor, term_h - 1, "linked typewriter id?")
    if id then
      config.linked_typewriter = id
      cache = build_caches()
      util.write_data(config_path, config)
    end
  end
end

local function interactive_config_speed_controllers(monitor, term_w, term_h, menu)
  for i,v in ipairs(sc_info) do
    monitor.setCursorPos(1, i + 2)
    interactive_menu_selection(monitor, i == menu.selection, v.name)

    local sc = config.speed_controllers[i]
    local target = nil
    if cache.speed_controllers then
      target = cache.speed_controllers[i].controller.getTargetSpeed()
    end
    if sc then
      monitor.write(("  (%s flip=%s target=%s)"):format(sc.id, sc.flip, target))
    end
  end

  monitor.setCursorPos(1, 9)
  interactive_menu_selection(monitor, 7 == menu.selection, "base rpm")
  monitor.write(("     (%d)"):format(config.base))

  local _, key, is_held = os.pullEvent("key")
  if key == keys.down then
    menu.selection = (menu.selection % 7) + 1
    return menu
  elseif key == keys.up then
    menu.selection = ((menu.selection - 2) % 7) + 1
    return menu
  elseif key == keys.left then
    return menu.prev
  elseif key == keys.right or key == keys.enter then
    os.pullEvent("key_up")

    if menu.selection == 7 then
      local base = util.ask_number(monitor, term_h - 1, "base rpm?", -128, 128)
      if not base then return end
      config.base = base
      util.write_data(config_path, config)
      return
    end

    local id = util.ask_number(monitor, term_h - 3, "speed controller id?")
    if not id then return end
    local flip = util.ask_bool(monitor, term_h - 1, "flip?")
    if not (flip ~= nil) then return end

    config.speed_controllers[menu.selection] = {
      id = id,
      flip = flip,
    }
    cache = build_caches()
    util.write_data(config_path, config)
  end
end

local function interactive_config_tilt_controller(monitor, term_w, term_h, menu)
  monitor.setCursorPos(1, 3)
  interactive_menu_selection(monitor, 1 == menu.selection, "id")
  monitor.write(("  (%s)"):format(config.tilt_controller))

  local _, key, is_held = os.pullEvent("key")
  if key == keys.left then
    return menu.prev
  elseif key == keys.right or key == keys.enter then
    os.pullEvent("key_up")

    local id = util.ask_number(monitor, term_h - 3, "tilt controller id?")
    if not id then return end

    config.tilt_controller = id
    cache = build_caches()
    util.write_data(config_path, config)
  end
end

local function interactive_config_misc_menu(monitor, term_w, term_h, menu)
  local sorted_misc = {}
  for k,v in pairs(config.misc) do
    table.insert(sorted_misc, {
      k = k,
      v = v,
    })
  end
  table.sort(sorted_misc, function(a, b)
    return a.k < b.k
  end)

  for i,v in ipairs(sorted_misc) do
    monitor.setCursorPos(1, 2 + i)
    interactive_menu_selection(monitor, i == menu.selection, v.k)
    monitor.write(("  (%s)"):format(textutils.serialize(v.v)))
  end

  local _, key, is_held = os.pullEvent("key")
  if key == keys.down then
    menu.selection = (menu.selection % #sorted_misc) + 1
  elseif key == keys.up then
    menu.selection = ((menu.selection - 2) % #sorted_misc) + 1
  elseif key == keys.left then
    return menu.prev
  elseif key == keys.right or key == keys.enter then
    os.pullEvent("key_up")

    local msg = "new value for "..sorted_misc[menu.selection].k.."?"
    local new_val = util.ask_number(monitor, term_h - 1, msg)
    if not new_val then return end

    config.misc[sorted_misc[menu.selection].k] = new_val
    util.write_data(config_path, config)
  end
end

local function interactive_debug_menu(monitor, term_w, term_h, menu)
  if menu.history then
    monitor.setCursorPos(1, 3)
    monitor.write(("%s held=%s"):format(keys.getName(menu.history.key), menu.history.is_held))
  end

  local _, key, is_held = os.pullEvent("key")
  menu.history = { key = key, is_held = is_held, }

  if key == keys.left then
    return menu.prev or menu
  end
  return menu
end

local function interactive()
  local menu_autopilot = {
    name = "Autopilot",
    selection = 1,
    custom = interactive_autopilot_menu,
  }

  local menu_manual = {
    name = "Manual TODO",
    selection = 1,
    options = {},
  }

  local menu_config_pid_pitch = {
    name = "Pitch",
    selection = 1,
    custom = interactive_config_pid_menu,
    pid = config.pid_pitch,
  }

  local menu_config_pid_roll = {
    name = "Roll",
    selection = 1,
    custom = interactive_config_pid_menu,
    pid = config.pid_roll,
  }

  local menu_config_pid_yaw = {
    name = "Yaw",
    selection = 1,
    custom = interactive_config_pid_menu,
    pid = config.pid_yaw,
  }

  local menu_config_pids = {
    name = "PIDs",
    selection = 1,
    options = {
      menu_config_pid_pitch,
      menu_config_pid_roll,
      menu_config_pid_yaw,
    },
  }

  local menu_config_pois = {
    name = "POIs",
    selection = 1,
    custom = interactive_config_pois,
  }

  local menu_config_monitor = {
    name = "Monitor",
    selection = 1,
    custom = interactive_config_monitor_menu,
  }

  local menu_config_compass = {
    name = "Compass Sensor",
    selection = 1,
    custom = interactive_config_compass_menu,
  }

  local menu_config_gimbal = {
    name = "Gimbal Sensor",
    selection = 1,
    custom = interactive_config_gimbal_menu,
  }

  local menu_config_altitude = {
    name = "Altitude Sensor",
    selection = 1,
    custom = interactive_config_altitude_menu,
  }

  local menu_config_linked_typewriter = {
    name = "Linked Typewriter",
    selection = 1,
    custom = interactive_config_linked_typewriter_menu,
  }

  local menu_config_propeller_speed_controllers = {
    name = "Propeller speed controllers",
    selection = 1,
    custom = interactive_config_speed_controllers,
  }

  local menu_config_propeller_tilt_controller = {
    name = "Propeller tilt controller",
    selection = 1,
    custom = interactive_config_tilt_controller,
  }

  local menu_config_misc = {
    name = "Misc",
    selection = 1,
    custom = interactive_config_misc_menu,
  }

  local menu_config = {
    name = "Config",
    selection = 1,
    options = {
      menu_config_pids,
      menu_config_pois,
      menu_config_monitor,
      menu_config_compass,
      menu_config_gimbal,
      menu_config_altitude,
      menu_config_linked_typewriter,
      menu_config_propeller_speed_controllers,
      menu_config_propeller_tilt_controller,
      menu_config_misc,
    },
  }

  local menu_debug = {
    name = "Debug",
    custom = interactive_debug_menu,
  }

  local menu_menu = {
    name = "Menu",
    selection = 1,
    options = {
      menu_autopilot,
      menu_manual,
      menu_config,
      menu_debug,
    },
  }

  local current_menu = menu_menu

  while true do
    -- io.stdout:write(textutils.serialize({ term.current().getSize() }))

    local monitor = term.current()
    -- if cache.monitor then
    --   monitor = cache.monitor
    --   monitor.setTextScale(1.0)
    -- end
    local term_w, term_h = monitor.getSize()

    current_menu = interactive_menu(
      monitor, term_w, term_h, current_menu
    ) or current_menu
  end
end

local function flight_controller()
  local dt = 0.05

  if cache.monitor then
    cache.monitor.setTextScale(0.5)
  end

  while true do
    sleep(dt)

    if not cache.gimbal then print("no gimbal"); goto continue end
    local gimbal = cache.gimbal.getAnglesRad()
    if not gimbal then print("no gimbal"); goto continue end

    local error_pitch = config.pid_pitch.base_error + gimbal[2]
    local error_roll = config.pid_roll.base_error + gimbal[1]
    local error_yaw = config.pid_yaw.base_error

    if cache.linked_typewriter then
      local pressed_keys = cache.linked_typewriter.getPressedKeyCodes()
      for _,v in ipairs(pressed_keys) do
        if v == keys.w then
          error_pitch = error_pitch - 0.174
        elseif v == keys.s then
          error_pitch = error_pitch + 0.174
        elseif v == keys.a then
          error_roll = error_roll + 0.174
        elseif v == keys.d then
          error_roll = error_roll - 0.174
        end
      end
    end

    local bearing = 0.0
    local north = 0.0
    local near = true
    local boost = false

    if target and position and cache.compass then
      local dx = target.x - position.x
      local dy = target.y - position.y

      near = dx * dx + dy * dy <= config.misc.near_distance * config.misc.near_distance
      if near then
        -- point towards the set bearing when close to the target
        -- fine tune position with pitch and roll
        local mul = 1.0 / config.misc.near_distance * config.misc.near_strafe_angle_limit

        local x_adjustment = util.clamp(-config.misc.near_distance, dx, config.misc.near_distance) * mul
        local y_adjustment = util.clamp(-config.misc.near_distance, dy, config.misc.near_distance) * mul
        error_pitch = error_pitch + math.sin(north) * x_adjustment + math.cos(north) * y_adjustment
        error_roll = error_roll - math.cos(north) * x_adjustment + math.sin(north) * y_adjustment
      else
        -- point towards the target when far away
        -- movement using forward boost tilt
        bearing = math.atan2(-dy, dx) - math.pi / 2.0
      end
    end

    if cache.compass then
      north = cache.compass.getRelativeAngleRad()
      error_yaw = error_yaw + ((north - bearing + math.pi) % (math.pi * 2.0)) - math.pi
      if math.abs(error_yaw) <= config.misc.autopilot_max_boost_bearing_error and not near then
        error_pitch = error_pitch - config.misc.autopilot_boost_angle
        boost = true
      end
    end

    local corr_pitch = pid.pid_contoller(
      pid_pitch,
      config.pid_pitch,
      error_pitch * 20.0,
      dt
    ) * 0.1
    local corr_roll = pid.pid_contoller(
      pid_roll,
      config.pid_roll,
      error_roll * 20.0,
     dt
    ) * 0.1
    local corr_yaw = pid.pid_contoller(
      pid_yaw,
      config.pid_yaw,
      error_yaw * 20.0,
      dt
    )

    if cache.speed_controllers then
      set_speed_controller(sc_idx.left_mid, config.base)
      set_speed_controller(sc_idx.right_mid, config.base)

      set_speed_controller(sc_idx.left_front,  config.base * math.exp(0.0 - corr_roll + corr_pitch))
      set_speed_controller(sc_idx.left_back,   config.base * math.exp(0.0 - corr_roll - corr_pitch))
      set_speed_controller(sc_idx.right_front, config.base * math.exp(0.0 + corr_roll + corr_pitch))
      set_speed_controller(sc_idx.right_back,  config.base * math.exp(0.0 + corr_roll - corr_pitch))
    end
    if cache.tilt_controller then
      local turn_left = corr_yaw <= -0.05
      local turn_right = corr_yaw >= 0.05
      if turn_left or turn_right or not boost then
        cache.tilt_controller.setOutput("front", turn_right);
        cache.tilt_controller.setOutput("right", turn_left);
        cache.tilt_controller.setOutput("back", turn_right);
        cache.tilt_controller.setOutput("left", turn_left);
      else
        cache.tilt_controller.setOutput("front", true);
        cache.tilt_controller.setOutput("right", true);
        cache.tilt_controller.setOutput("back", false);
        cache.tilt_controller.setOutput("left", false);
      end
    end

    if cache.monitor then
      cache.monitor.clear()
      cache.monitor.setCursorPos(1,1)
      cache.monitor.write(("bearing: %f"):format(bearing))
      if position and target then
        if near then
          cache.monitor.write(" near mode")
        else
          cache.monitor.write(" far mode")
        end
      end
      cache.monitor.setCursorPos(1,2)
      cache.monitor.write(("north: %f"):format(north))
      -- cache.monitor.setCursorPos(1,1)
      -- cache.monitor.write(string.format("pitch: %f a: %f", corr_pitch, error_pitch))
      -- cache.monitor.setCursorPos(1,2)
      -- cache.monitor.write(string.format("roll: %f a: %f", corr_roll, error_roll))
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
    for _,v in pairs(cache.pois) do
      if v.nav then
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
    end

    too_few_pois = #datapoints < 2
    if too_few_pois then goto continue end

    local mat_a = {}
    local mat_b = {}

    for _,v in ipairs(datapoints) do
      table.insert(mat_a, { v.cos, -v.sin })
      table.insert(mat_b, { v.cos * v.x + v.sin * v.y })
    end

    -- print("mat_a", textutils.serialize(mat_a, {compact=true}))
    -- print("mat_b", textutils.serialize(mat_b, {compact=true}))

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
