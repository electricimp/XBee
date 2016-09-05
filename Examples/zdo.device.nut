#import "~/Documents/GitHub/XBee/xbee.class.nut"

server.setsendtimeoutpolicy(RETURN_ON_ERROR, WAIT_TIL_SENT, 10);


local coordinator = null;
local debug = true;

// ********** XBee Response Callback **********

function xBeeResponse(error, response) {
    if (error) {
        if (debug) server.error(error);
        return;
    }

    if (response) {
        if ("command" in response) {
            if (response.command = "AO") {
                if (debug) server.log("AO mode set");
            }
        }

        if ("cmdid" in response) {
            server.log("Status: " + response.status.message);

            if (response.cmdid == 0x91) {
                server.log("Zigbee Transaction: " + format("0x%02x", response.data[0]));

                if (response.clusterID == 0x8031) {
                    server.log("From device at \"" + response.address64bit + "\"");
                    server.log(" Neighbours:");
                    if (response.data.len() > 1) {
                        local entries = response.data[2];
                        local count = response.data[4];
                        local start = 5;
                        for (local i = 0 ; i < count ; ++i) {
                            server.log(" Neighbour " + i);
                            local s = "";
                            for (local j = 0 ; j < 8 ; ++j) {
                                // Note: Data is little endian
                                s = format("%02x", response.data[start + j]) + s;
                            }
                            start += 8;
                            server.log("  Extended PAN ID: 0x" + s);
                            local s = "";
                            for (local j = 0 ; j < 8 ; ++j) {
                                s = format("%02x", response.data[start + j]) + s;
                            }
                            start += 8;
                            server.log("  Extended Address: 0x" + s);
                            server.log("  16-bit Address: 0x" + format("%02x", response.data[start + 1]) + format("%02x", response.data[start]));
                            start += 2;
                            s = response.data[start];
                            local a = s >> 6;
                            local m = ["a Coordinator", "a Router", "an End Device", "Unknown"];
                            server.log("  Neighbour is " + m[a]);
                            m = ["on", "off", "unknown", "unknown"];
                            a = (s & 0x30) >> 4;
                            server.log("  Neighbour's receiver is a " + m[a]);
                            m = ["parent", "child", "sibling", "None", "Previous"];
                            a = (s & 0x0c) >> 1;
                            server.log("  Neighbour is my: " + m[a]);
                            start += 3;
                        }
                    }
                }
            }

            if (response.cmdid == 0x8B) {
                if (debug) {
                    server.log("Zigbee Transmit Status: " + response.deliveryStatus.message);
                }
            }
        }
    }
}

// ********** START **********

// Instantiate Zigbee coordinator
coordinator = XBee(hardware.uart57, xBeeResponse);

// Enter Zigbee Device Object mode
coordinator.enterZDMode();

local data = blob(1);
data[0] = 0x00;

// Send LQI request to all
coordinator.sendZDO("0x000000000000FFFF", 0xFFFE, 0x0031, data);
