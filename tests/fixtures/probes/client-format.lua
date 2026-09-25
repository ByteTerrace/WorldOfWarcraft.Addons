-- The layout below is exactly how the WoW client writes a SavedVariables file: flat, unindented,
-- every key bracketed, tables in hash order. It proves `tlk probes --import` parses what the client
-- writes. The records have the shape /btdev probe saves; they aren't observations.
ByteTerraceDevToolsDB = {
["probes"] = {
["damageMeter.available"] = {
["result"] = {
["failureReason"] = "",
["isAvailable"] = true,
},
["build"] = "1.60.1 (70009)",
["context"] = {
["restrictions"] = "none",
["combat"] = false,
},
},
["chatTypeInfo.raidWarning"] = {
["result"] = {
["sticky"] = 0,
["b"] = 0,
["hasMetatable"] = true,
["g"] = 72,
["r"] = 255,
},
["build"] = "1.60.1 (70009)",
["context"] = {
["restrictions"] = "none",
["combat"] = false,
},
},
},
["build"] = {
["build"] = "70009",
["version"] = "1.60.1",
["interface"] = 16001,
},
}
