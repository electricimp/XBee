#require "xbee.class.nut:1.0.0"

// Set imp to remain awake during Internet connectivity loss
server.setsendtimeoutpolicy(RETURN_ON_ERROR, WAIT_TIL_SENT, 10);

// Globals
local coordinator = null;
local nodes = null;
local debug = false;

// XBee Data Handler Callback
function xBeeResponse(err, resp) {
    if (err) {
        if (debug) server.error(err);
        return;
    }

    if (resp) {
        if ("command" in resp) {
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

            if (resp.command == "ND") {
                // Co-ordinator has responded with a network scan information
                if ("data" in resp) {
                    local node = {};
                    node.address16bit <- (resp.data[0] << 8) + resp.data[1];
                    node.address64bit <- format("0x%02X%02X%02X%02X%02X%02X%02X%02X", resp.data[2], resp.data[3], resp.data[4], resp.data[5], resp.data[6], resp.data[7], resp.data[8], resp.data[9]);
                    node.type <- resp.data[14];

                    // If the node is a router, add a subsidiary devices list
                    if (node.type == 1 && !("devices" in node)) node.devices <- [];

                    nodes.append(node);

                    // Broadcast to all End Devices, seeking their parents' addresses
                    if (node.type> 1) coordinator.sendRemoteATCommand("MP", node.address64bit, node.address16bit, -1, 102);
                }
            }

            if (resp.command == "MP") {
                if ("data" in resp) {
                    local pad = resp.data[0] * 0xFF + resp.data[1];
                    if (nodes != null) {
                        foreach (node in nodes) {
                            if (node.address64bit == resp.address64bit) {
                                if ("pad" in node) {
                                    node.parent = pad;
                                } else {
                                    node.parent <- pad;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

function reportNodes() {
    if (nodes.len() > 0) {
        local m = ["a Coordinator", "a Router", "an End Device"];
        server.log(" ");
        server.log("+--------------------------------------------+");
        server.log("|            Local Zigbee Network            |");
        server.log("+--------------------------------------------+");

        // First node list by type
        nodes.sort(function(a, b) {
            if (a.type > b.type) return 1;
            if (a.type < b.type) return -1;
            return 0;
        });

        // Now move end devices under their parents
        foreach (i, node in nodes) {
            if ("pad" in node) {
                for (local j = 0 ; j < nodes.len() ; ++j) {
                    if (j != i) {
                        local aNode = nodes[j];
                        if (aNode.address16bit == node.parent) {
                            local bNode = nodes.remove(i);
                            nodes.insert(j, bNode);
                            break;
                        }
                    }
                }
            }
        }

        foreach (i, node in nodes) {
            local st = "", sp = "", sk="";
            switch(node.type) {
                case 0:
                    sk = "|                                            |";
                    st = "+---";
                    sp = "|   ";
                    break;

                case 1:
                    sk = "|                                            |";
                    st = "+---";
                    sp = "|   ";
                    break;

                case 2:
                    sk = "|   |                                        |";
                    st = "|   +---";
                    sp = "|       ";
                    break;

            }

            server.log(sk);
            local s = st + "Node #" + i + " is " + m[node.type];
            server.log(s + "                                    ".slice(0, 45 - s.len()) + "|");
            s = sp + "64-bit address: " + node.address64bit;
            server.log(s + "                                    ".slice(0, 45 - s.len()) + "|");
            s = sp + "16-bit address: " + format("0x%2X", node.address16bit);
            server.log(s + "                                    ".slice(0, 45 - s.len()) + "|");
        }

        server.log("|                                            |");
        server.log("+--------------------------------------------+");
    } else {
        // No data yet; try again in 10s
        imp.wakeup(5, reportNodes);
    }
}


function enumerate() {
    // First, get the local device
    coordinator.sendLocalATCommand("OI", -1, 100);

    // Give the network at least 10s to respond
    imp.wakeup(10, reportNodes);
}


// ********** START **********

// Instantiate Zigbee coordinator
coordinator = XBee(hardware.uart57, xBeeResponse, true, true, debug);

// Set up nodes array
nodes = [];

// Enumerate the network
enumerate();
