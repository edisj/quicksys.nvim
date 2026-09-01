local sys = require("quicksys.system").system
-- require("quicksys.system").system("ls -lAh")
-- ctx = require("quicksys.system").system("ls -l", "sleep 5", "slkdfj")
-- sys {
--   cmd = { "ls", "-la" },
--   -- stdout = false,
--   -- before = false,
-- }

sys("ls", "echo", "sleep 3", "echo hi", "sleep 2", "true", "echo bye")


