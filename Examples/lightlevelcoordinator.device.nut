#require "xbee.device.lib.nut:1.1.0"

// Set imp to remain awake during Internet connectivity loss
server.setsendtimeoutpolicy(RETURN_ON_ERROR, WAIT_TIL_SENT, 10);

// Globals
local coordinator = null;
local debug = false;

// XBee Data Handler Callback
function xBeeResponse(err, resp) {
    if (err) {
        if (debug) server.error(err);
        return;
    }

    if (resp) {
        if ("cmdid" in resp) {
            if (resp.cmdid == 0x90) {
                // 0x90 is a Zigbee Receive Packet
                // Here we just display the received data, but in a real-world application,
                // we might tabulate the values from multiple sensors and upload the data
                server.log("Light level from " + format("0x%04X", resp.address16bit) + ": " + ((resp.data[0] << 8) + resp.data[1]));
            }
        }
    }
}

// ********** START **********

// Instantiate Zigbee coordinator
coordinator = XBee(hardware.uart57, xBeeResponse, true, true, debug);
