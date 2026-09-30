for _, binding in ipairs({
  { "SUPER + Super_L", "launcher", true },
  { "SUPER + A", "dashboard" },
  { "SUPER + Tab", "overview" },
  { "SUPER + I", "settings" },
  { "SUPER + L", "lockscreen" },
}) do
  hl.bind(binding[1], hl.dsp.exec_cmd("pangu run " .. binding[2]), {
    description = "Shell: " .. binding[2],
    release = binding[3] or false,
  })
end

return true
