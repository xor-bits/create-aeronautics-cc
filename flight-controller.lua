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

local monitor                         = peripheral.find("monitor")
local gimbal                          = find_relay("redstone_relay_3")
local compass                         = find_relay("redstone_relay_7")
local tilt_controller                 = find_relay("redstone_relay_4")
local rotation_velocity_controller    = find_relay("redstone_relay_6")
local input                           = find_relay("redstone_relay_8")

local gimbal_x_offset                 = 0
local gimbal_z_offset                 = 0
local gimbal_proportional_coefficient = 1
local gimbal_derivative_coefficient   = 6
local gimbal_correction_power_divisor = 4

local target_bearing                  = 0
local holding_left                    = false
local holding_right                   = false
local target_x_vel                    = 0
local target_z_vel                    = 0

local tau                             = math.pi * 2
local monitor_size                    = monitor.getSize()

local strafe_left                     = 1
local strafe_right                    = 2
local forward                         = 3
local backward                        = 4
local rotate_left                     = 5
local rotate_right                    = 6
local inputs                          = { false, false, false, false, false, false }
local prev_inputs                     = { false, false, false, false, false, false }

local prev_x_angle, prev_z_angle      = find_angle(gimbal)
while true do
  local x_angle, z_angle     = find_angle(gimbal)
  local y_angle_0, y_angle_1 = find_angle(compass)
  local target_y_angle_0     = math.cos(target_bearing)
  local target_y_angle_1     = math.sin(target_bearing)
  -- local bearing = math.atan2(y_angle_1, y_angle_0)

  inputs[strafe_left]        = input.getInput("left")
  inputs[strafe_right]       = input.getInput("right")
  inputs[forward]            = input.getInput("front")
  inputs[backward]           = input.getInput("back")
  inputs[rotate_left]        = redstone.getInput("left")
  inputs[rotate_right]       = redstone.getInput("right")

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

  for i = 1, 6 do
    prev_inputs[i] = inputs[i]
  end

  -- front output is back  right propeller
  -- right output is back  left  propeller
  -- back  output is front left  propeller
  -- left  output is front right propeller

  local x_delta = x_angle - prev_x_angle
  local z_delta = z_angle - prev_z_angle
  local x_corr = (gimbal_proportional_coefficient * x_angle
    + gimbal_derivative_coefficient * x_delta
    + gimbal_x_offset + target_x_vel) / gimbal_correction_power_divisor
  local z_corr = (gimbal_proportional_coefficient * z_angle +
    gimbal_derivative_coefficient * z_delta +
    gimbal_z_offset + target_z_vel) / gimbal_correction_power_divisor
  local dot = y_angle_0 * target_y_angle_1 + y_angle_1 * target_y_angle_0

  tilt_controller.setAnalogOutput("back", math.min(15, math.max(0, -x_corr + z_corr)))
  tilt_controller.setAnalogOutput("left", math.min(15, math.max(0, x_corr + z_corr)))
  tilt_controller.setAnalogOutput("front", math.min(15, math.max(0, x_corr - z_corr)))
  tilt_controller.setAnalogOutput("right", math.min(15, math.max(0, -x_corr - z_corr)))
  print("\n\n\nINFO")
  print("x_angle:", x_angle, "z_angle:", z_angle)
  print("x_delta:", x_delta, "z_delta:", z_delta)
  print("x_corr:", x_corr, "z_corr:", z_corr)
  print()
  print("bearing")
  print("current y0:", y_angle_0, "y1:", y_angle_1)
  print("target  y0:", target_y_angle_0, "y1:", target_y_angle_1)
  print("dot:", dot)

  -- back  left  -- turns left    -- decreases angle
  -- front right -- turns right   -- increases angle
  -- left  right -- goes forwards --
  -- front back  -- goes backwads --

  local bearing_draw_x_mid = 14
  local bearing_draw_y_mid = 10
  monitor.clear()
  monitor.setCursorPos(1, 1)
  monitor.setCursorPos(bearing_draw_x_mid, 1)
  monitor.write("|")
  monitor.setCursorPos(math.max(1, bearing_draw_x_mid - dot), 2)
  monitor.write("x")
  monitor.setCursorPos(bearing_draw_x_mid, 3)
  monitor.write("|")

  monitor.setCursorPos(bearing_draw_x_mid, bearing_draw_y_mid)
  monitor.write(".")
  monitor.setCursorPos(
    math.max(1, bearing_draw_x_mid - target_x_vel),
    math.max(4, bearing_draw_y_mid + target_z_vel)
  )
  monitor.write("x")

  local turn_left = false
  local turn_right = false
  if dot > 1 then
    turn_right = true
  elseif dot < -1 then
    turn_left = true
  end
  rotation_velocity_controller.setOutput("front", turn_left);
  rotation_velocity_controller.setOutput("right", turn_left);
  rotation_velocity_controller.setOutput("back", turn_right);
  rotation_velocity_controller.setOutput("left", turn_right);

  prev_x_angle, prev_z_angle = x_angle, z_angle
  -- sleep(0.5)
  os.pullEvent("redstone")
end
