local scan = require "luacheck.scan"

--- Checks a Metalua AST. 
-- Returns a file report. 
-- See luacheck function. 
local function check(ast, options)
   options = options or {}
   local opts = {
      check_global = true,
      check_redefined = true,
      check_unused = true,
      check_unused_args = true,
      globals = _G,
      env_aware = true,
      ignore = {},
      only = false
   }

   for option in pairs(opts) do
      if options[option] ~= nil then
         opts[option] = options[option]
      end
   end

   local callbacks = {}
   local report = {total = 0, global = 0, redefined = 0, unused = 0}

   -- Array of scopes. 
   -- Each scope is a table mapping names to array {node, used, type}
   local scopes = {}
   -- Current scope nesting level. 
   local level = 0

   -- Adds a warning, if necessary. 
   local function add_warning(node, type_, subtype, prev_node)
      local name = node[1]

      if not opts.ignore[name] then
         if not opts.only or opts.only[name] then
            report.total = report.total + 1
            report[type_] = report[type_] + 1
            report[report.total] = {
               type = type_,
               subtype = subtype,
               name = name,
               line = node.lineinfo.first.line,
               column = node.lineinfo.first.column,
               prev_line = prev_node and prev_node.lineinfo.first.line,
               prev_column = prev_node and prev_node.lineinfo.first.column
            }
         end
      end
   end

   -- resolve name in current scope. 
   -- If variable is found, mark it as accessed and return true. 
   local function find_and_access(name)
      for i=level, 1, -1 do
         if scopes[i][name] then
            scopes[i][name][2] = true
            return true
         end
      end
   end

   -- If the variable was unused, adds a warning. 
   local function check_usage(vardata)
      if vardata[1][1] ~= "_" and not vardata[2] then
         if opts.check_unused_args or vardata[3] == "var" then
            add_warning(vardata[1], "unused", vardata[3])
         end
      end
   end

   function callbacks.on_start(_)
      level = level + 1

      -- Create new scope. 
      scopes[level] = {}
   end

   function callbacks.on_end(_)
      if opts.check_unused then
         -- Check if some local variables in this scope were left unused. 
         for _, vardata in pairs(scopes[level]) do
            check_usage(vardata)
         end
      end

      -- Delete scope. 
      scopes[level] = nil
      level = level - 1
   end

   function callbacks.on_local(node, type_)
      if opts.check_redefined then
         -- Check if this variable was declared already in this scope. 
         local prev_vardata = scopes[level][node[1]]

         if prev_vardata then
            check_usage(prev_vardata)
            add_warning(node, "redefined", prev_vardata[3], prev_vardata[1])
         end
      end

      -- Mark this variable declared. 
      scopes[level][node[1]] = {node, false, type_}
   end

   function callbacks.on_access(node, action)
      local name = node[1]

      if not find_and_access(name) then
         if name ~= "..." then
            if not opts.env_aware or name ~= "_ENV" and not find_and_access("_ENV") then
               if opts.check_global and opts.globals[name] == nil then
                  add_warning(node, "global", action)
               end
            end
         end
      end
   end

   scan(ast, callbacks)
   assert(level == 0)
   table.sort(report, function(warning1, warning2)
      return warning1.line < warning2.line or
         warning1.line == warning2.line and warning1.column < warning2.column
   end)
   return report
end

return check
