#require "xbee.device.lib.nut:2.0.0"

// Set imp to remain awake during Internet connectivity loss
server.setsendtimeoutpolicy(RETURN_ON_ERROR, WAIT_TIL_SENT, 10);

local dataSource = null;
local debug = true;

function xbeeResponse(err, data) {
    if (err) {
        if (debug) server.error(err);
        return;
    }

    if ("deliveryStatus" in data) server.log("Zigbee Delivery Status: " + data.deliveryStatus.message);

    if ("command" in data) {
        if (data.command == "AI") {
            // Is there a network in place?
            if (data.data[0] == 0x00) {
                // Yes - so start the sensor reading and transmission loop
                if (debug) server.log("Network in place");
                sensorLoop();
            } else {
                // No - wait five seconds then poll again
                imp.wakeup(5, function() {
                    dataSource.sendLocalATCommand("AI");
                }.bindenv(this));
            }
        }
    }
}

function postReading(value) {
    // Send data point to Co-ordinator
    local data = blob(2);
    data[0] = (value & 0xFF00) >> 8;
    data[1] = value & 0xFF;

    dataSource.sendZigbeeRequest("0x00", 0xFFFE, data);
}

function sensorLoop() {
    imp.wakeup(30, sensorLoop);
    postReading(hardware.lightlevel());
}

// ********** START **********

dataSource = XBee(hardware.uart57, xbeeResponse, true, true, debug);
dataSource.sendLocalATCommand("AI");
