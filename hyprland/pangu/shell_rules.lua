hl.window_rule({
  match = { class = "^(org\\.quickshell)$", title = "^(Pangu Settings)$" },
  float = true,
  center = true,
  size = { 1000, 760 },
})

hl.window_rule({
  match = { class = "^(org\\.quickshell)$", title = "^(Pangu Macros & Hotkeys)$" },
  float = true,
  center = true,
  size = { 1180, 720 },
})

return true
