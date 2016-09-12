#import "~/Documents/GitHub/XBee/xbee.class.nut"

// Set imp to remain awake during Internet connectivity loss
server.setsendtimeoutpolicy(RETURN_ON_ERROR, WAIT_TIL_SENT, 10);

// Globals
local coordinator = null;
local nodes = null;
local debug = true;

// XBee Data Handler Callback
function xBeeResponse(err, resp) {
    if (err) {
        if (debug) server.error(err);
        return;
    }

    if (resp) {
        if ("command" in resp) {
            // Is the response resulting from an AT command?

            if (resp.command == "OI") {
                // Co-ordinator has responded with its own information
                local node = {};
                node.address64bit <- "0x0000000000000000";
                node.address16bit <- (resp.data[1] << 8) + resp.data[0];
                node.type <- 0;
                node.devices <- [];
                nodes.append(node);

                // Broadcast a Node Discovery command - all other nodes will report their addresses etc
                coordinator.sendLocalATCommand("ND", -1, 101);
                return;
            }

            if (resp.command == "AO") {
                server.log("AO mode set");
            }

            if (resp.command == "ND") {
                server.log("ND response " + (nodes.len() + 1) + " received");

                if ("data" in resp) {
                        local node = {};
                        node.address64bit <- format("0x%02X%02X%02X%02X%02X%02X%02X%02X", resp.data[2], resp.data[3], resp.data[4], resp.data[5], resp.data[6], resp.data[7], resp.data[8], resp.data[9]);
                        node.address16bit <- (resp.data[0] << 8) + resp.data[1];
                        node.type <- resp.data[14];
                        nodes.append(node);
                }
            }
        }

        if ("cmdid" in resp) {
            // server.log("Status: " + resp.status.message);

            if (resp.cmdid == 0x91) {
                server.log(format("0x%04X", resp.clusterID));
                if (resp.clusterID == 0x8002) {
                    server.log("Zigbee Transaction: " + format("0x%02x", resp.data[0]));

                    // 'Node Descriptor Response'
                    server.log("From device at \"" + resp.address64bit + "\"");
                    local b = resp.data[4];
                    local a = (b & 0xE0) >> 5;
                    local m = ["co-ordinator", "router", "end device"];
                    server.log(" Device type: " + m[a]);

                    b = resp.data[5];
                    a = b & 0x1F;
                    m = ["808MHz", "", "900MHz", "2.4GHz", ""];
                    for (local i = 0 ; i < 5 ; ++i) {
                        local j = 4 - i;
                        if (a & math.pow(2, j).tointeger()) server.log(" Net type: " + m[i]);
                    }


                    b = (resp.data[7] << 8) + resp.data[6];
                    server.log(" Manufacturer code: " + format("0x%04X", b));

                    b = resp.data[9];
                    server.log(" Buffer size: " + b + " bytes");
                }
            }

            if (resp.cmdid == 0x8B) {
                if (debug) {
                    server.log("Zigbee Transmit Status: " + resp.deliveryStatus.message);
                }
            }
        }
    }
}

// ********** START **********

// Instantiate Zigbee coordinator
coordinator = XBee(hardware.uart57, xBeeResponse, true, true, debug);
coordinator.exitZDMode();

// Set up nodes
nodes = [];

// Get nodes
coordinator.sendLocalATCommand("ND", -1, 100);

// Wake up in 15s and interrogate each node disovered
imp.wakeup(20, function() {
    server.log("Performing ZDO operation");

    // Enter Zigbee Device Object mode
    coordinator.enterZDMode();

    foreach (index, node in nodes) {
        // 'Node Descriptor Request' sends the module's 16-bit address as its data payload
        // in little endian
        local data = blob(2);
        data[0] = node.address16bit & 0xFF;
        data[1] = (node.address16bit & 0xFF00) >> 8;

        // Send Node Descriptor request to all devices
        // Note: 0x000000000000FFFF is shortcut for 'all devices'
        server.log("Request " + (index + 1) + " sent");
        coordinator.sendZDO(node.address64bit, 0xFFFE, 0x0002, data, (0x76 + index));

        imp.sleep(0.1);
    }
});
