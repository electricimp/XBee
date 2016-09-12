#require "xbee.class.nut:1.0.0"

// Set imp to remain awake during Internet connectivity loss
server.setsendtimeoutpolicy(RETURN_ON_ERROR, WAIT_TIL_SENT, 10);

// CONSTANTS
const SENSOR_64BIT_ADDRESS = "<YOUR_XBEE_64_BIT_ADDRESS>";

// Globals
local coordinator = null;
local debug = false;

// XBee Data Handler Callabck
function xBeeResponse(err, resp) {
    if (err) {
        if (debug) server.error(err);
        return;
    }

    if (resp) {
        if ("frameid" in resp) {
            if (resp.frameid == 204) {
                server.log("Remote sensor configured");
            } else if (resp.frameid < 200) {
                if ("status" in resp) server.log("Status: " + resp.status.message);
            }
        }

        if ("cmdid" in resp) {
            if (resp.cmdid == 0x92) {
                local message = "ZigBee IO Data Sample Rx Indicator frame received ";
                if ("frameid" in resp) message = message + "with Frame ID " + resp.frameid;
                server.log(message);
                server.log("Samples: " + resp.numberOfSamples);
                server.log("Digital Mask: " + format("%04x", resp.digitalMask));
                server.log("Analog Mask: " + format("%04x", resp.analogMask));

                if (resp.digitalMask > 0) {
                    local d = resp.digitalSamples;
                    for (local k = 1; k < 17 ; ++k) {
                        local m = resp.digitalMask >> k;
                        if (m != 0) {
                            // Pin is set to provide data
                            local v = d >> k
                            local s = (v == 1) ? "Remote pin is HIGH" : "Remote pin is LOW";
                            server.log(s);
                        }
                    }
                }

                if (resp.analogMask > 0) server.log("Analog reading: " + resp.analogSamples[0]);
            }

            if (resp.cmdid == 0x8b) {
                if ("discoveryStatus" in resp) server.log("Discovery Status: " + resp.discoveryStatus.message);
                if ("deliveryStatus" in resp) server.log("Delivery Status: " + resp.deliveryStatus.message);
            }
        }
    }
}

// ********** START **********

// Instantiate Zigbee coordinator
coordinator = XBee(hardware.uart57, xBeeResponse, true, true, debug);

// Configure remote XBee for sensor duties: sample data on analog input D1
coordinator.sendRemoteATCommand("D1", SENSOR_64BIT_ADDRESS, 0xFFFE, 0, 2, 200);

// Set sample rate to 5000ms (5s)
coordinator.sendRemoteATCommand("IR", SENSOR_64BIT_ADDRESS, 0xFFFE, 0, 5000, 201);

// Set high 32-bits of 64-bit destination address
coordinator.sendRemoteATCommand("DH", SENSOR_64BIT_ADDRESS, 0xFFFE, 0, 0, 202);

// Set low 32-bits of 64-bit destination address
coordinator.sendRemoteATCommand("DL", SENSOR_64BIT_ADDRESS, 0xFFFE, 0, 0, 203);

// Apply changes to remote XBee
coordinator.sendRemoteATCommand("AC", SENSOR_64BIT_ADDRESS, 0xFFFE, 0, -1, 204);

// Now the co-ordinator can sit back and wait for the data,
// which will be logged
