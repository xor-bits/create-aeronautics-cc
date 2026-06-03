local util = require "util"

local pid = {}

local visualizer = {
  ["x"] = {
    e = 0.0,
    p = 0.0,
    i = 0.0,
    d = 0.0,
    s = 0.0,
  },
  ["y"] = {
    e = 0.0,
    p = 0.0,
    i = 0.0,
    d = 0.0,
    s = 0.0,
  },
}
function pid.pid_contoller(instance, config, error, delta_seconds)
  if not instance.accumulator then
    instance.accumulator = 0.0
    instance.prev_error = 0.0
  end

  local proportional = config.p * error
  local integral = instance.accumulator
  local derivative = config.d * (error - instance.prev_error) / delta_seconds

  instance.accumulator = util.clamp(
    config.i_min,
    instance.accumulator + config.i * error / delta_seconds,
    config.i_max
  )
  instance.prev_error = error

  local sum = proportional + derivative + integral

  if config.visualize then
    visualizer[config.visualize].e = error
    visualizer[config.visualize].p = proportional
    visualizer[config.visualize].i = integral
    visualizer[config.visualize].d = derivative
    visualizer[config.visualize].s = sum
  end

  return sum
end

function pid.visualize_joystick(monitor, at_x, at_y, w, h, axis_x, axis_y, char)
  local mid_x = math.floor(w / 2.0)
  local mid_y = math.floor(h / 2.0)
  monitor.setCursorPos(at_x + mid_x, at_y + mid_y)
  monitor.write(".")
  monitor.setCursorPos(
    at_x + util.clamp(1, mid_x + axis_x / 2.5 * mid_x, w),
    at_y + util.clamp(1, mid_y - axis_y / 2.5 * mid_y, h)
  )
  monitor.write(char)
  -- print(char, "x:", axis_x, "y:", axis_y)
end

function pid.visualize_pid(monitor)
  local monitor_w, monitor_h         = monitor.getSize()
  local monitor_third_x              = math.floor(monitor_w / 3)
  local monitor_third_y              = math.floor(monitor_h / 3)

  monitor.setCursorPos(1, 5)
  monitor.write(("x_err:%.3f y_err:%.3f"):format(visualizer["x"].e, visualizer["y"].e))
  monitor.setCursorPos(1, 6)
  monitor.write(("x_iacc:%.3f y_iacc:%.3f"):format(visualizer["x"].i, visualizer["y"].i))
  monitor.setCursorPos(1, 7)
  monitor.write(("x_corr:%.3f y_corr:%.3f"):format(visualizer["x"].s, visualizer["y"].s))

  pid.visualize_joystick(
    monitor,
    0, monitor_third_y,
    monitor_third_x, monitor_third_y,
    visualizer["x"].e, visualizer["y"].e,
    "E"
  )
  pid.visualize_joystick(
    monitor,
    monitor_third_x + 1, monitor_third_y,
    monitor_third_x, monitor_third_y,
    visualizer["x"].p, visualizer["y"].p,
    "P"
  )
  pid.visualize_joystick(
    monitor,
    monitor_third_x * 2 + 2, monitor_third_y,
    monitor_third_x, monitor_third_y,
    visualizer["x"].i, visualizer["y"].i,
    "I"
  )
  pid.visualize_joystick(
    monitor,
    0, monitor_third_y * 2 + 1,
    monitor_third_x, monitor_third_y,
    visualizer["x"].d, visualizer["y"].d,
    "D"
  )
  pid.visualize_joystick(
    monitor,
    monitor_third_x + 1, monitor_third_y * 2 + 1,
    monitor_third_x, monitor_third_y,
    visualizer["x"].s, visualizer["y"].s,
    "S"
  )
end

return pid
