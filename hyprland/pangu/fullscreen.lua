local M = { suppress = false }

function M.dispatch_real(dispatcher)
  M.suppress = true
  local ok, err = pcall(hl.dispatch, dispatcher)
  M.suppress = false
  if not ok then
    error(err)
  end
end

return M
