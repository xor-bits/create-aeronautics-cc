local function find_angle(gimbal)
  local back  = gimbal.getAnalogInput("back")
  local front = gimbal.getAnalogInput("front")
  local left  = gimbal.getAnalogInput("left")
  local right = gimbal.getAnalogInput("right")
  return left - right, back - front
end

local function find_relay(name)
  return peripheral.find("redstone_relay", function(candidate_name, _)
    return candidate_name == name
  end)
end

local function init_table(len, fill)
  local t = {}
  for i = 1, len do
    t[i] = fill
  end
  return t
end

local function clamp(min, val, max)
  return math.max(min, math.min(max, val))
end

local monitor                      = peripheral.find("monitor")
local gimbal                       = find_relay("redstone_relay_3")
local compass                      = find_relay("redstone_relay_7")
local tilt_controller              = find_relay("redstone_relay_4")
local rotation_velocity_controller = find_relay("redstone_relay_6")
local input                        = find_relay("redstone_relay_8")

local corr                         = {
  tilt_x = 0.0,
  tilt_z = 0.0,
  turn_left = false,
  turn_right = false,
  boost = 0,
}
local pid_accumulators             = init_table(3, 0.0)
local pid_prev_errors              = init_table(3, 0.0)

local target_bearing               = math.pi / 2.0
local target_x_vel                 = 0
local target_z_vel                 = 0
local dot                          = 0
local autopilot                    = true
local autopilot_speed              = 0.4
local delta_seconds                = 0.05

local tau                          = math.pi * 2
local monitor_w, monitor_h         = monitor.getSize()
local monitor_mid_x                = math.floor(monitor_w / 2)
local monitor_mid_y                = math.floor(monitor_h / 2)
local monitor_third_x              = math.floor(monitor_w / 3)
local monitor_third_y              = math.floor(monitor_h / 3)

local strafe_left                  = 1
local strafe_right                 = 2
local forward                      = 3
local backward                     = 4
local rotate_left                  = 5
local rotate_right                 = 6
local mode                         = 7
local inputs_len                   = mode
local inputs                       = init_table(inputs_len, false)
local prev_inputs                  = init_table(inputs_len, false)

local pid_visualizer_x_e = 0.0
local pid_visualizer_x_p = 0.0
local pid_visualizer_x_i = 0.0
local pid_visualizer_x_d = 0.0
local pid_visualizer_y_e = 0.0
local pid_visualizer_y_p = 0.0
local pid_visualizer_y_i = 0.0
local pid_visualizer_y_d = 0.0
local function pid_contoller(config)
  local dt = math.max(0.1, config.delta_seconds)


  if config.error - pid_prev_errors[config.i] == 0 then
    print("error zero")
  end

  local proportional = config.k_p * config.error
  local integral = pid_accumulators[config.i]
  local derivative = config.k_d * (config.error - pid_prev_errors[config.i]) / dt

  if proportional ~= proportional then
    print("p nan")
    proportional = 0.0
  end
  if integral ~= integral then
    print("i nan")
    integral = 0.0
  end
  if derivative ~= derivative then
    print("d nan")
    derivative = 0.0
  end

  pid_accumulators[config.i] = clamp(
    config.acc_min,
    pid_accumulators[config.i] + config.k_i * config.error / dt,
    config.acc_max
  )
  pid_prev_errors[config.i] = config.error

  if config.visualize then
    if config.visualize == "x" then
      pid_visualizer_x_e = config.error
      pid_visualizer_x_p = proportional
      pid_visualizer_x_i = integral
      pid_visualizer_x_d = derivative
    elseif config.visualize == "y" then
      pid_visualizer_y_e = config.error
      pid_visualizer_y_p = proportional
      pid_visualizer_y_i = integral
      pid_visualizer_y_d = derivative
    else
      print("bad visualizer mode")
    end
  end

  return proportional + derivative + integral
end

local function visualize_joystick(at_x, at_y, w, h, axis_x, axis_y, char)
  local mid_x = math.floor(w / 2.0)
  local mid_y = math.floor(h / 2.0)
  monitor.setCursorPos(at_x + mid_x, at_y + mid_y)
  monitor.write(".")
  monitor.setCursorPos(
    at_x + clamp(1, mid_x + axis_x / 7.5 * mid_x, w),
    at_y + clamp(1, mid_y - axis_y / 7.5 * mid_y, h)
  )
  monitor.write(char)
  -- print(char, "x:", axis_x, "y:", axis_y)
end

local function visualize_pid()
  local sum_x = pid_visualizer_x_p + pid_visualizer_x_i + pid_visualizer_x_d
  local sum_y = pid_visualizer_y_p + pid_visualizer_y_i + pid_visualizer_y_d

  visualize_joystick(
    0, monitor_third_y,
    monitor_third_x, monitor_third_y,
    pid_visualizer_x_e, pid_visualizer_y_e,
    "E"
  )
  visualize_joystick(
    monitor_third_x + 1, monitor_third_y,
    monitor_third_x, monitor_third_y,
    pid_visualizer_x_p, pid_visualizer_y_p,
    "P"
  )
  visualize_joystick(
    monitor_third_x * 2 + 2, monitor_third_y,
    monitor_third_x, monitor_third_y,
    pid_visualizer_x_i, pid_visualizer_y_i,
    "I"
  )
  visualize_joystick(
    0, monitor_third_y * 2 + 1,
    monitor_third_x, monitor_third_y,
    pid_visualizer_x_d, pid_visualizer_y_d,
    "D"
  )
  visualize_joystick(
    monitor_third_x + 1, monitor_third_y * 2 + 1,
    monitor_third_x, monitor_third_y,
    sum_x, sum_y,
    "S"
  )
end

local function manual_mode()
  if inputs[rotate_left] and not prev_inputs[rotate_left] then
    target_bearing = target_bearing + 0.1
  end
  if inputs[rotate_right] and not prev_inputs[rotate_right] then
    target_bearing = target_bearing - 0.1
  end
  if inputs[forward] and not prev_inputs[forward] then
    target_z_vel = target_z_vel - 1
  end
  if inputs[backward] and not prev_inputs[backward] then
    target_z_vel = target_z_vel + 1
  end
  if inputs[strafe_left] and not prev_inputs[strafe_left] then
    target_x_vel = target_x_vel + 1
  end
  if inputs[strafe_right] and not prev_inputs[strafe_right] then
    target_x_vel = target_x_vel - 1
  end

  local y_angle_0, y_angle_1 = find_angle(compass)
  local target_y_angle_0     = math.cos(target_bearing)
  local target_y_angle_1     = math.sin(target_bearing)
  dot                        = y_angle_0 * target_y_angle_1 + y_angle_1 * target_y_angle_0
  local rotation_corr = pid_contoller {
    i = 3,
    error = dot,
    k_p = 0.3,
    k_d = 1.0,
    k_i = 0.0,
    acc_min = 0.0,
    acc_max = 0.0,
    delta_seconds = delta_seconds,
  }

  if rotation_corr >= 0.2 then
    corr.turn_right = true
  elseif dot <= 0.2 then
    corr.turn_left = true
  end
end

local function autopilot_mode()
  if inputs[rotate_left] or inputs[strafe_left] then
    corr.turn_left = true
  end
  if inputs[rotate_right] or inputs[strafe_right] then
    corr.turn_right = true
  end
  if inputs[forward] and not prev_inputs[forward] then
    autopilot_speed = autopilot_speed + 0.1
  end
  if inputs[backward] and not prev_inputs[backward] then
    autopilot_speed = autopilot_speed - 0.1
  end

  local target_x_delta, target_z_delta = find_angle(compass)
  target_x_vel = autopilot_speed * math.max(-5, math.min(5, -target_x_delta))
  target_z_vel = autopilot_speed * math.max(-5, math.min(5, -target_z_delta))
  if math.abs(target_z_delta) >= 15 then
    corr.boost = target_z_delta
  end

  monitor.setCursorPos(1, 1)
  monitor.write("speed:")
  monitor.write(math.floor(autopilot_speed * 10) / 10.0)
  monitor.write(" xd:")
  monitor.write(-target_x_delta)
  monitor.write(" zd:")
  monitor.write(-target_z_delta)
  monitor.setCursorPos(1, 2)
  monitor.write("boost:")
  monitor.write(corr.boost)
end

local function apply_corrections()
  -- back  output is front left  propeller
  -- left  output is front right propeller
  -- front output is back  right propeller
  -- right output is back  left  propeller
  tilt_controller.setAnalogOutput("back", math.min(15, math.max(0, -corr.tilt_x + corr.tilt_z)))
  tilt_controller.setAnalogOutput("left", math.min(15, math.max(0, corr.tilt_x + corr.tilt_z)))
  tilt_controller.setAnalogOutput("front", math.min(15, math.max(0, corr.tilt_x - corr.tilt_z)))
  tilt_controller.setAnalogOutput("right", math.min(15, math.max(0, -corr.tilt_x - corr.tilt_z)))

  -- back  output turns right side forwards
  -- right output turns right side backwards
  -- front output turns left  side forwards
  -- left  output turns left  side backwards
  if corr.boost ~= 0 and not corr.turn_left and not corr.turn_right then
    rotation_velocity_controller.setOutput("front", corr.boost > 0);
    rotation_velocity_controller.setOutput("right", corr.boost < 0);
    rotation_velocity_controller.setOutput("back", corr.boost > 0);
    rotation_velocity_controller.setOutput("left", corr.boost < 0);
  else
    rotation_velocity_controller.setOutput("front", corr.turn_right);
    rotation_velocity_controller.setOutput("right", corr.turn_right);
    rotation_velocity_controller.setOutput("back", corr.turn_left);
    rotation_velocity_controller.setOutput("left", corr.turn_left);
  end
end

local prev_x_angle, prev_z_angle = find_angle(gimbal)
local x_dt_accum = 0.0
local z_dt_accum = 0.0

os.startTimer(0.5)

while true do
  corr.turn_left = false
  corr.turn_right = false
  corr.boost = 0
  monitor.clear()

  local x_angle, z_angle = find_angle(gimbal)
  -- local bearing = math.atan2(y_angle_1, y_angle_0)

  inputs[strafe_left]    = input.getInput("left")
  inputs[strafe_right]   = input.getInput("right")
  inputs[forward]        = input.getInput("front")
  inputs[backward]       = input.getInput("back")
  inputs[rotate_left]    = redstone.getInput("left")
  inputs[rotate_right]   = redstone.getInput("right")
  inputs[mode]           = input.getInput("top")

  if inputs[mode] and not prev_inputs[mode] then
    target_x_vel = 0
    target_z_vel = 0
    autopilot = not autopilot
  end

  if autopilot then
    autopilot_mode()
  else
    manual_mode()
  end

  for i = 1, inputs_len do
    prev_inputs[i] = inputs[i]
  end

  local target_x_angle = x_angle + target_x_vel
  local target_z_angle = z_angle + target_z_vel

  if target_x_angle - pid_prev_errors[1] ~= 0 or x_dt_accum >= 2.0 then
    print("X pid with dt:", x_dt_accum, "dt:", delta_seconds)
    corr.tilt_x = pid_contoller {
      i = 1,
      error = target_x_angle,
      k_p = 0.15,
      k_d = 0.7,
      k_i = 0.001,
      acc_min = -4.0,
      acc_max = 4.0,
      visualize = "x",
      delta_seconds = x_dt_accum,
      -- delta_seconds = delta_seconds,
    }
    x_dt_accum = 0.0
  else
    x_dt_accum = x_dt_accum + delta_seconds
  end
  if target_z_angle - pid_prev_errors[2] ~= 0 or z_dt_accum >= 2.0 then
    -- print("zangle:", z_angle, "prevzangle:", prev_z_angle)
    print("Z pid with dt:", z_dt_accum, "dt:", delta_seconds)
    corr.tilt_z = pid_contoller {
      i = 2,
      error = target_z_angle,
      k_p = 0.2,
      k_d = 1.0,
      k_i = 0.001,
      acc_min = -15.0,
      acc_max = 15.0,
      visualize = "y",
      delta_seconds = z_dt_accum,
      -- delta_seconds = delta_seconds,
    }
    z_dt_accum = 0.0
  else
    z_dt_accum = z_dt_accum + delta_seconds
  end

  apply_corrections()

  if not autopilot then
    monitor.setCursorPos(1, 1)
    monitor.setCursorPos(monitor_mid_x, 1)
    monitor.write("|")
    monitor.setCursorPos(math.max(1, monitor_mid_x + dot), 2)
    monitor.write("x")
    monitor.setCursorPos(monitor_mid_x, 3)
    monitor.write("|")
    monitor.setCursorPos(1, 4)
    monitor.write("accel x:")
    monitor.write(target_x_vel)
    monitor.write(" z:")
    monitor.write(target_z_vel)
  end

  visualize_pid()
  visualize_joystick(
    monitor_third_x * 2 + 2, monitor_third_y * 2 + 1,
    monitor_third_x, monitor_third_y,
    x_angle, z_angle,
    "A"
  )
  -- monitor.setCursorPos(monitor_mid_x, monitor_mid_y)
  -- monitor.write(".")
  -- monitor.setCursorPos(
  --   math.max(1, monitor_mid_x - target_x_vel),
  --   math.max(4, monitor_mid_y + target_z_vel)
  -- )
  -- monitor.write("x")

  monitor.setCursorPos(1, monitor_h)
  if autopilot then
    monitor.write("AUTOPILOT")
  end
  -- monitor.write(" dt:")
  -- monitor.write(math.floor(delta_seconds * 100.0) / 100.0)
  -- monitor.write("s")
  -- monitor.write(" t:")
  -- monitor.write(math.floor(os.clock() * 100.0) / 100.0)
  -- monitor.write("s")

  -- prev_x_angle, prev_z_angle = x_angle, z_angle
  -- sleep(0.5)
  local wait_start_sec = os.clock()
  os.pullEvent()
  delta_seconds = math.max(0.05, os.clock() - wait_start_sec)
end
