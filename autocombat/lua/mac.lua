-- Morituri Auto Combat, short name:  /lua run mac
-- Starts moriac.lua (same folder) under the script name "mac", so
-- /ac restart and the exit hint use /lua run mac / /lua stop mac.
MORIAC_SCRIPT_NAME = 'mac'
local dir = debug.getinfo(1, 'S').source:match('@?(.*[/\\])') or './'
-- loadfile + a Lua call, not dofile: dofile is a C call in LuaJIT, so mq.delay
-- cannot yield through it and the main loop would spin without ever pausing.
local main = assert(loadfile(dir .. 'moriac.lua'))
return main()
