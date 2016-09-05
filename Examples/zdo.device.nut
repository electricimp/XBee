#import "~/Documents/GitHub/XBee/xbee.class.nut"

server.setsendtimeoutpolicy(RETURN_ON_ERROR, WAIT_TIL_SENT, 10);


local coordinator = null;
local debug = true;
local ZDOFlag = false;

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
            server.log(format("0x%2x", response.cmdid));
            if (response.cmdid == 0x91) {
                server.log("Status: " + response.status.message);
                server.log("Zigbee Transaction: " + format("0x%02x", response.data[0]));

                server.log("From device at \"" + response.address64bit + "\"");
                server.log(" ClusterID: " + format("0x%04x", response.clusterID) + "");
                server.log(" Neighbours:");
                if (response.data.len() > 1) {
                    local entries = response.data[2];
                    local count = response.data[4];
                    local start = 5;
                    for (local i = 0 ; i < count ; ++i) {
                        server.log(" Neighbour " + i);
                        local s = "0x";
                        for (local j = 0 ; j < 8 ; ++j) {
                            // Note: Data is little endian
                            s = format("%02x", response.data[start + j]) + s;
                        }
                        start += 8;
                        server.log("  Extended PAN ID: " + s);
                        local s = "0x";
                        for (local j = 0 ; j < 8 ; ++j) {
                            s = format("%02x", response.data[start + j]) + s;
                        }
                        start += 8;
                        server.log("  Extended Address: " + s);
                        server.log("  16-bit Address: 0x" + format("%02x", response.data[start + 1]) + format("%02x", response.data[start]));
                        start += 2;
                        s = response.data[start];
                        local a = s >> 6;
                        local m = ["Coordinator", "Router", "End Device", "Unknown"];
                        server.log("  Neighbour is a " + m[a]);
                        m = ["on", "off", "unknown", "unknown"];
                        a = (s & 0x30) >> 4;
                        server.log("  Neighbour's receiver is " + m[a]);
                        m = ["parent", "child", "sibling", "None", "Previous"];
                        a = (s & 0x0c) >> 1;
                        server.log("  Neighbour is my: " + m[a]);
                        start += 3;
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


// ********** Zigbee Device Object Functions **********

function sendZDO(xbee, address64bit, address16bit, clusterID, data, frameid = -1) {
    // Is the system set up for ZDO? If not, make sure it is
    if (!ZDOFlag) enterZDO();

    // Send the data (returning the frame ID)
    // Pass in addresses; set endpoints and profile ID to 0; set clusterID
    return xbee.sendExplicitZigbeeRequest(address64bit, address16bit, 0, 0, clusterID, 0, data, 0, 0, frameid);
}

function enterZDO(xbee, all = true) {
    // Push local and remote devices to AO = 1
    if (all) xbee.sendRemoteATCommand("AO", "0x000000000000FFFF", 0xFFFE, 2, 1);
    xbee.sendLocalATCommand("AO", 1);
    ZDOFlag = true;
}

function exitZDO(xbee, all = true) {
    // Push local and remote devices to AO = 0
    if (all) xbee.sendRemoteATCommand("AO", "0x000000000000FFFF", 0xFFFE, 2, 0);
    xbee.sendLocalATCommand("AO", 0);
    ZDOFlag = false;
}



// ********** START **********

// Instantiate Zigbee coordinator
coordinator = XBee(hardware.uart57, xBeeResponse);

// Enter Zigbee Device Object mode
enterZDO(coordinator, false);

local data = blob(2);
data[0] = 0x76;
data[1] = 0x00;

// Send LQI request to all
sendZDO(coordinator, "0x000000000000FFFF", 0xFFFE, 0x0031, data, 200);
