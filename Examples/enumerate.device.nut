#import "~/Documents/GitHub/XBee/xbee.class.nut"

server.setsendtimeoutpolicy(RETURN_ON_ERROR, WAIT_TIL_SENT, 10);


local coordinator = null;
local nodes = null;
local apiMode = true;
local debug = true;


function xBeeResponse(error, response) {
    if (error) {
        if (debug) server.error(error);
        return;
    }

    if (response) {
        if ("command" in response) {
            if (response.command == "OI") {
                local node = {};
                node.address64bit <- "0x0000000000000000";
                node.address16bit <- response.data[1] * 255 + response.data[0]
                node.type <- 0;
                node.devices <- [];
                nodes.append(node);

                if (response.frameid = 100) {
                    // Broadcast a Node Discovery command - all other nodes will report their addresses etc
                    coordinator.sendLocalATCommand("ND", -1, 101);
                }
            }

            if (response.command == "ND") {
                if ("data" in response) {
                    local node = {};
                    node.address16bit <- response.data[0] * 255 + response.data[1];
                    node.address64bit <- format("0x%02X%02X%02X%02X%02X%02X%02X%02X", response.data[2], response.data[3], response.data[4], response.data[5], response.data[6], response.data[7], response.data[8], response.data[9]);
                    node.type <- response.data[14];
                    if (node.type == 1) node.devices <- [];
                    nodes.append(node);

                    if (response.frameid = 101) {
                        // Broadcast to all End Devices, seeking their parents' addresses
                        coordinator.sendLocalATCommand("MY", -1, 102);
                    }
                }
            }

            if (response.command == "MP") {
                if ("data" in response) {
                    local pad = response.data[0] * 0xFF + response.data[1];
                    if (nodes != null) {
                        foreach (node in nodes) {
                            if (node.address64bit == response.address64bit) {
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
        server.log("Local Zigbee Network");
        server.log("====================");
        server.log(" ");
        server.log("+-------------------------------");

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
                    sk = "|";
                    st = "+---";
                    sp = "|   ";
                    break;

                case 1:
                    sk = "|";
                    st = "+---";
                    sp = "|   ";
                    break;

                case 2:
                    sk = "|   |   ";
                    st = "|   +---";
                    sp = "|       ";
                    break;

            }

            server.log(sk);
            server.log(st + "Node #" + i + " is " + m[node.type]);
            server.log(sp + "64-bit address: " + node.address64bit);
            server.log(sp + "16-bit address: " + format("0x%2X", node.address16bit));
        }

        server.log("|");
        server.log("+-------------------------------");
    } else {
        // No data yet; try again in 10s
        imp.wakeup(5, reportNodes);
    }
}


function enumerate() {
    // First, get the local device
    coordinator.sendLocalATCommand("OI", 100);
    imp.wakeup(15, reportNodes);
}


// START

// Instantiate Zigbee coordinator
coordinator = XBee(hardware.uart57, xBeeResponse);

// Set up nodes array
nodes = [];

// Enumerate the network
enumerate();
