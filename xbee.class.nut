class XBee {
    // Library class for use with Digi Xbee Modules Series 2
    // operating in either API mode or AT mode
    //
    // Written by Tony Smith, August 2016
    // Copyright Electric Imp, Inc. 2016
    // Available under the MIT License

    static version = [1,0,0];

    // ********** API Frame Type IDs **********
    // **********  Request Commands  **********
    static XBEE_CMD_AT = 0x08;
    static XBEE_CMD_QUEUE_PARAM_VALUE = 0x09;
    static XBEE_CMD_ZIGBEE_TRANSMIT_REQ = 0x10;
    static XBEE_CMD_EXP_ADDR_ZIGBEE_CMD_FRAME = 0x11;
    static XBEE_CMD_REMOTE_CMD_REQ = 0x17;
    static XBEE_CMD_CREATE_SOURCE_ROUTE = 0x21;

    // ********** Response Frames **********
    static XBEE_CMD_AT_RESPONSE = 0x88;
    static XBEE_CMD_MODEM_STATUS = 0x8A;
    static XBEE_CMD_ZIGBEE_TRANSMIT_STATUS = 0x8B;
    static XBEE_CMD_ZIGBEE_RECEIVE_PACKET = 0x90;
    static XBEE_CMD_ZIGBEE_EXP_RX_INDICATOR = 0x91;
    static XBEE_CMD_ZIGBEE_IO_DATA_SAMPLE_RX_INDICATOR = 0x92;
    static XBEE_CMD_XBEE_SENSOR_READ_INDICATOR = 0x94;
    static XBEE_CMD_NODE_ID_INDICATOR = 0x95;
    static XBEE_CMD_REMOTE_CMD_RESPONSE = 0x97;
    static XBEE_CMD_ROUTE_RECORD_INDICATOR = 0xA1;
    static XBEE_CMD_MANY_TO_ONE_ROUTE_REQ_INDICATOR = 0xA2;

    // ********** NOT YET SUPPORTED **********
    static XBEE_CMD_OTA_FIRMWARE_UPDATE_STATUS = 0xA0;

    static CR = "\x0D";

    _uart = null;
    _callback = null;
    _buffer = null;
    _command = null;

    _apiMode = false;
    _escaped = false;
    _ZDOFlag = false;
    _guardPeriod = 1.0;
    _commandTime = -1;
    _commandModeTimeout = 100;
    _frameByteCount = 0;
    _frameSize = 0;
    _frameIDcount = 0;
    _transIDcount = 0;
    _debug = false;

    constructor (impSerial = null, callback = null, apiMode = true, escaped = true, debug = false) {
        // Parameters:
        //   1. Unconfigured imp UART bus
        //   2. Callback to handle received API frames or AT command responses
        //   3. Boolean indicating whether the user wants API mode (true) or 'transparent' AT mode (false)
        //   4. Boolean indicating whether the user wants to use escaped mode (AP = 2) or not (AP = 1)
        //      Note: This is not supported in AT mode, ie. we set it to false in this case
        //   5. Optional Boolean indicating whether use wants debug messages

        if (!impSerial) {
            server.error("XBee class requires a valid imp UART/serial bus");
            return null;
        }

        if (!callback) {
            server.error("XBee class requires a valid callback function");
            return null;
        }

        // Escaping only required with API mode
        if (escaped && !apiMode) escaped = false;
        _escaped = escaped;

        _uart = impSerial;
        _callback = callback;
        _apiMode = apiMode;
        _debug = debug;
        _buffer = blob();

        // Configure the serial bus using default values (user can change later)
        init();
    }

    function init(baudrate = 9600, flags = 0) {
        // Configure the XBee UART (XBee UART spec: 8-N-1)
        // Parameters:
        //   1. The required baudrate as an integer (1,200 - 1,000,000)
        //   2. Any imp API UART flags required (as integer bitfield)
        // Returns:
        //   The actual baud rate as an integer as per hardware.uart.configure()

        if (baudrate < 1200 || baudrate > 1000000) {
            if (_debug) server.error("XBee.init() speed setting out of range; choosing 9600 baud");
            baudrate = 9600;
        }

        if (flags < 0 || flags > 8) {
            if (_debug) server.error("XBee.init() flags setting out of range; choosing no flags (0)");
            flags = 0;
        }

        local actual;

        if (_apiMode) {
            actual = _uart.configure(baudrate, 8, PARITY_NONE, 1, flags, _dataReceivedAPI.bindenv(this));
        } else {
            actual = _uart.configure(baudrate, 8, PARITY_NONE, 1, flags, _dataReceivedAT.bindenv(this));
        }

        if (_debug) server.log("Actual baud rate: " + actual + " baud");
        return actual;
    }

    // ********** TRANSMISSION COMMAND FUNCTIONS **********

    // **********    API Frame Mode Functions    **********

    function sendLocalATCommand(command, parameterValue = -1, frameid = -1) {
        // Send an AT Command within an API frame
        // Parameters:
        //   1. A two-character string representing the AT command, eg. "HV" - Get Hardware Version
        //   2. Integer parameter value. Default (-1) indicates no supplied value
        //   3. Integer frame ID. Default (-1) indicates no supplied value because 0 indicates
        //      the user doesn't want a response from the module.
        // Returns:
        //   API call's frame ID

        local dataBlob;
        if (parameterValue != -1) {
            dataBlob = _setATParameters(3, parameterValue);
        } else {
            dataBlob = blob(3);
        }

        if (frameid == -1) {
            _frameIDcount++;
            if (_frameIDcount > 255) _frameIDcount = 1;
            dataBlob[0] = _frameIDcount;
        } else {
            dataBlob[0] = frameid;
        }

        dataBlob[1] = command[0];
        dataBlob[2] = command[1];

        _sendFrame(_makeFrame(XBEE_CMD_AT, dataBlob));

        if (_debug) server.log(format("AT Command \"%s\" sent as frame ID %u", command, dataBlob[0]));

        if (frameid == -1) {
            return _frameIDcount;
        } else {
            return frameid;
        }
    }

    function sendQueuedATCommand(command, parameterValue = -1, frameid = -1) {
        // Send an AT Command within an API frame and queue the parameter
        // (ie. don't force it to be actioned immediately)
        // Parameters:
        //   1. A two-character string representing the AT command, eg. "HV" - Get Hardware Version
        //   2. Integer parameter value. Default (-1) indicates no supplied value
        //   3. Integer frame ID (see sendLocalATCommand())
        // Returns:
        //   API call's frame ID

        local dataBlob;
        if (parameterValue != -1) {
            dataBlob = _setATParameters(3, parameterValue);
        } else {
            dataBlob = blob(3);
        }

        if (frameid == -1) {
            _frameIDcount++;
            if (_frameIDcount > 255) _frameIDcount = 1;
            dataBlob[0] = _frameIDcount;
        } else {
            dataBlob[0] = frameid;
        }

        dataBlob[1] = command[0];
        dataBlob[2] = command[1];

        _sendFrame(_makeFrame(XBEE_CMD_QUEUE_PARAM_VALUE, dataBlob));

        if (_debug) server.log(format("Queued AT Command sent as frame ID %u", dataBlob[0]));

        if (frameid == -1) {
            return _frameIDcount;
        } else {
            return frameid;
        }
    }

    function sendRemoteATCommand(command, address64bit, address16bit, options = 0, parameterValue = -1, frameid = -1) {
        // Send an AT Command within an API frame to a remote device
        // Parameters:
        //   1. A two-character string representing the AT command, eg. "HV" - Get Hardware Version
        //   2. 64-bit destination device address as a hex string
        //   3. Integer 16-bit destination network address
        //   4. Integer bitfield of options
        //   5. Integer parameter value. Default (-1) indicates no supplied value
        //   6. Integer frame ID. Default (-1) indicates no supplied value because 0 indicates
        //      the user doesn't want a response from the module.
        // Returns:
        //   API call's frame ID

        local dataBlob;
        if (parameterValue != -1) {
            dataBlob = _setATParameters(14, parameterValue);
        } else {
            dataBlob = blob(14);
        }

        if (frameid == -1) {
            _frameIDcount++;
            if (_frameIDcount > 255) _frameIDcount = 1;
            dataBlob[0] = _frameIDcount;
        } else {
            dataBlob[0] = frameid;
        }

        _write64bitAddress(dataBlob, 1, address64bit);
        _write16bitAddress(dataBlob, 9, address16bit);

        dataBlob[11] = options;
        dataBlob[12] = command[0];
        dataBlob[13] = command[1];

        _sendFrame(_makeFrame(XBEE_CMD_REMOTE_CMD_REQ, dataBlob));

        if (_debug) server.log(format("Remote AT Command \"%s\" sent as frame ID %u", command, dataBlob[0]));

        if (frameid == -1) {
            return _frameIDcount;
        } else {
            return frameid;
        }
    }

    function sendZigbeeRequest(address64bit, address16bit, data, radius = 0, options = 0, frameid = -1) {
        // Send a Zigbee transmit request frame
        // Parameters:
        //   1. 64-bit destination device address as a hex string, eg. '0x0000000000000000' for the Co-ordinator's default address
        //   2. Integer 16-bit destination network address
        //   3. Blob containing the data to be transmitted
        //   4. Integer broadcast radius (default: 0 = max. radius)
        //   5. Integer bitfield (default: 0)
        //   6. Integer frame ID (see sendLocalATCommand())
        // Returns:
        //   API call's frame ID

        local dataBlob = blob(13 + data.len());

        if (frameid == -1) {
            _frameIDcount++;
            if (_frameIDcount > 255) _frameIDcount = 1;
            dataBlob[0] = _frameIDcount;
        } else {
            dataBlob[0] = frameid;
        }

        _write64bitAddress(dataBlob, 1, address64bit);
        _write16bitAddress(dataBlob, 9, address16bit);

        dataBlob[11] = radius;
        dataBlob[12] = options;
        dataBlob.seek(13, 'b');
        dataBlob.writeblob(data);

        _sendFrame(_makeFrame(XBEE_CMD_ZIGBEE_TRANSMIT_REQ, dataBlob));

        if (_debug) server.log(format("ZigBee TX Request sent as frame ID %u", dataBlob[0]));

        if (frameid == -1) {
            return _frameIDcount;
        } else {
            return frameid;
        }
    }

    function sendExplicitZigbeeRequest(address64bit, address16bit, sourceEndpoint, destEndpoint, clusterID, profileID, data, radius = 0, options = 0, frameid = -1) {
        // Send a Zigbee command frame with explicit addressing
        // Parameters:
        //   1. 64-bit destination device address as a hex string
        //   2. Integer 16-bit destination network address
        //   3. Integer source endpoint
        //   4. Integer destination endpoint
        //   5. Integer 16-bit cluster ID
        //   6. Integer 16-bit profile ID
        //   7. Blob containing the data to be transmitted
        //   8. Integer broadcast radius (default: 0 = max. radius)
        //   9. Integer bitfield (default: 0)
        //   10. Integer frame ID (see sendLocalATCommand())
        // Returns:
        //   API call's frame ID

        local dataBlob = blob(19 + data.len());

        if (frameid == -1) {
            _frameIDcount++;
            if (_frameIDcount > 255) _frameIDcount = 1;
            dataBlob[0] = _frameIDcount;
        } else {
            dataBlob[0] = frameid;
        }

        _write64bitAddress(dataBlob, 1, address64bit);
        _write16bitAddress(dataBlob, 9, address16bit);

        dataBlob[11] = sourceEndpoint;
        dataBlob[12] = destEndpoint;

        _write16bitAddress(dataBlob, 13, clusterID);
        _write16bitAddress(dataBlob, 15, profileID);

        dataBlob[17] = radius;
        dataBlob[18] = options;

        dataBlob.seek(19, 'b');
        dataBlob.writeblob(data);

        _sendFrame(_makeFrame(XBEE_CMD_EXP_ADDR_ZIGBEE_CMD_FRAME, dataBlob));

        if (_debug) server.log(format("Explicit Addressing ZigBee Command sent as frame ID %u of %u bytes", dataBlob[0], dataBlob.len()));

        if (frameid == -1) {
            return _frameIDcount;
        } else {
            return frameid;
        }
    }

    function createSourceRoute(command, address64bit, address16bit, addresses, frameid = -1) {
        local dataBlob = blob(19);

        if (frameid == -1) {
            _frameIDcount++;
            if (_frameIDcount > 255) _frameIDcount = 1;
            dataBlob[0] = _frameIDcount;
        } else {
            dataBlob[0] = frameid;
        }

        _write64bitAddress(dBlob, 1, address64bit);
        _write16bitAddress(dBlob, 9, address64bit);

        dataBlob[11] = 0x00;
        dataBlob[12] = addresses.len();

        for (local i = 0 ; i < dataBlob[12] ; ++i) {
            _write16bitAddress(dBlob, 13 + (i * 2), addresses[i]);
        }

        _sendFrame(_makeFrame(XBEE_CMD_CREATE_SOURCE_ROUTE, dataBlob));

        if (_debug) server.log(format("Create Source Route sent as frame ID %u", dataBlob[0]));

        if (frameid == -1) {
            return _frameIDcount;
        } else {
            return frameid;
        }
    }

    // ********** Zigbee Device Object / Cluster Library Functions **********

    function sendZDO(address64bit, address16bit, clusterID, ZDOpayload, transaction = -1, frameid = -1) {
        // Send a Zigbee Device Object command frame
        // Parameters:
        //   1. 64-bit destination device address as a hex string
        //   2. Integer 16-bit destination network address
        //   3. clusterID
        //   4. Blob containing the data to be sent
        //   5. Integer transaction sequence number (optional)
        //   6. Integer frame ID (optional; see sendLocalATCommand())
        // Returns:
        //   Table containing two keys: 'transation' (the transaction sequence number) and 'frameid' (the frame ID)

        // Is the system set up for ZDO? If not, make sure it is
        if (!_ZDOFlag) {
            enterZDO();
            if (_ZDOFlag == false) return;
        }

        if (transaction == -1) {
            _transIDcount++;
            if (_transIDcount > 255) _transIDcount = 1;
            transaction = _transIDcount;
        }

        // Send the data (returning the frame ID)
        // Add the transaction sequence ID to the data payload
        local data = blob(ZDOpayload.len() + 1);
        data.writen((transaction & 0xFF), 'b');
        data.writeblob(ZDOpayload);

        // Pass in addresses; set endpoints and profile ID to 0; set clusterID
        local fid = sendExplicitZigbeeRequest(address64bit, address16bit, 0, 0, clusterID, 0, data, 0, 0, frameid);
        local ret = {};
        ret.transaction <- transaction;
        ret.frameid <- fid;
        return ret;
    }

    function sendZCL(address64bit, address16bit, sourceEndpoint, destinationEndpoint, clusterID, profileID, ZCLframe, radius = 0, frameid = -1) {
        // Send a Zigbee Cluster Library command frame
        // Parameters:
        //   1. 64-bit destination device address as a hex string
        //   2. Integer 16-bit destination network address
        //   3. Integer source endpoint
        //   4. Integer destination endpoint
        //   5. Integer 16-bit cluster ID
        //   6. Integer 16-bit profile ID
        //   7. Blob containing the ZCL frame data, including the transaction sequence number, to be transmitted
        //   8. Integer broadcast radius (default: 0 = max. radius)
        //   9. Integer frame ID (optional; see sendLocalATCommand())
        // Returns:
        //   Table containing two keys: 'transation' (the transaction sequence number) and 'frameid' (the frame ID)

        // Is the system set up for ZDO? If not, make sure it is
        if (!_ZDOFlag) {
            enterZDO();
            if (_ZDOFlag == false) return;
        }

        // Pass in addresses; set endpoints and profile ID to 0; set clusterID
        local fid = sendExplicitZigbeeRequest(address64bit, address16bit, sourceEndpoint, destinationEndpoint, clusterID, profileID, ZCLframe, radius, 0, frameid);
        local ret = {};
        ret.transaction <- ZCLframe[1];
        ret.frameid <- fid;
        return ret;
    }

    function enterZDMode() {
        if (!_apiMode) {
            // ZDO Mode not supported in AT Mode
            server.error("XBees can't send or receive Zigbee Device Objects in AT mode");
            _ZDOFlag = false;
            return;
        }

        // Push local and remote devices to AO = 1
        sendLocalATCommand("AO", 1);
        _ZDOFlag = true;
    }

    function exitZDMode() {
        // Push local and remote devices to AO = 0
        sendLocalATCommand("AO", 0);
        _ZDOFlag = false;
    }

    // ********** AT / Transparent Mode Functions **********

    function sendCommand(command, parameterValue = -1) {
        // Send an AT command to an Xbee in AT (Transparent) mode.
        // Parameters:
        //   1. A two-character string representing the AT command, eg. "HV" - Get Hardware Version
        //   2. Integer parameter value. Default (-1) indicates no supplied value
        // Returns:
        //   A transaction ID as an Integer

        parameterValue = (parameterValue) ? "" : format("%2x", parameterValue);
        local cmd = "AT" + command + parameter + CR;

        if (hardware.millis() - _commandTime > _commandModeTimeout) {
            // Has command mode timed out? Re-activate if so
            _setCommandMode();

            // And hold the command until we get an OK
            _command = cmd;
        } else {
            // Send the passed in command
            _uart.write(cmd);
        }

        // Update the transaction ID
        _frameIDcount++;
        if (_frameIDcount > 255) _frameIDcount = 1;
        return _frameIDcount;
    }

    // ********** PRIVATE METHODS - DO NOT CALL **********

    // ********** API Frame Encoding/Decoding Functions **********

    function _makeFrame(cmdID, data) {
        // Assembles the API frame from the payload supplied as the parameters
        // If the _escaped property is set (via the constructor), the completed
        // frame is processed for escape characters (AP = 2)
        // Parameters:
        //   1. Integer API command code
        //   2. Blob frame data payload
        // Returns:
        //   The assembled frame as a blob

        // Set frame header
        local frame = blob();
        frame.writen(0x7E, 'b');

        // Set frame length (command + data)
        local len = data.len() + 1;
        local msb = (len & 0xFF00) >> 8;
        frame.writen(msb, 'b');
        local lsb = len & 0x00FF;
        frame.writen(lsb, 'b');

        // Set frame command
        frame.writen(cmdID, 'b');

        // Add frame data
        frame.writeblob(data);

        // Set frame checksum
        frame.writen(_calculateChecksum(frame), 'b');

        // Resize the frame
        local eof = frame.tell();
        if (eof < 1024) frame.resize(eof);

        if (_escaped) {
            // Escaping is applied after the frame has been assembled
            // to all frame bytes but the first
            local escChars = [0x7E, 0x7D, 0x11, 0x13];
            local escFrame = blob();
            foreach (i, bite in frame) {
                if (i == 0) {
                    // Don't escape the header
                    escFrame.writen(bite, 'b');
                } else {
                    // Check for escaped characters
                    local match = false;
                    foreach (eChar in escChars) {
                        if (bite == eChar) {
                            match = true;
                            break;
                        }
                    }

                    if (match) {
                        escFrame.writen(0x7D, 'b');
                        escFrame.writen((bite ^ 0x20), 'b');
                    } else {
                        escFrame.writen(bite, 'b');
                    }
                }
            }

            return escFrame;
        } else {
            return frame;
        }
    }

    function _unmakeFrame(frame) {
        // Disassembles an incoming API frame if escaping is employed, ie.
        // _escaped property is set by the constructor (AP = 2).
        // If escaping is not being used by the application, the frame is
        // returned untouched

        if (_escaped) {
            local j = 0;
            local aFrame = blob(frame.len());
            for (local i = 0 ; i < frame.len() ; ++i) {
                if (i == 0) {
                    // Write in the unaltered header bytes
                    aFrame[j] = frame[i];
                } else {
                    if (frame[i] == 0x7D) {
                        aFrame[j] = frame[i + 1] ^ 0x20;
                        ++i;
                    } else {
                        aFrame[j] = frame[i];
                    }
                }

                ++j;
            }

            if (j < frame.len()) aFrame.resize(j);
            return aFrame;
        }

        return frame;
    }

    function _sendFrame(frame) {
        // Send the frame to the XBee via serial
        if (_debug) server.log("API Frame Sent: " + _listFrame(frame));

        // Write out the frame
        _uart.write(frame);
    }

    function _write64bitAddress(frameData, index, address) {
        // Writes the bytes representing a 64-bit address into the passed-in blob.
        // Parameters:
        //   1. Blob into which the address bytes will be written
        //   2. Integer location in the blob at which to begin writing
        //   3. String of 1-8 octets representing the address with or without '0x' header

        if (address.slice(0, 2) == "0x") address = address.slice(2);
        if (address.len() < 16) address = "0000000000000000".slice(0, 16 - address.len()) + address;
        local c = 0;
        for (local i = 0 ; i < address.len() ; i += 2) {
            local a = address.slice(i, i + 2);
            local v = 0;
            foreach (ch in a) {
                local n = ch - '0';
                if (n > 9) n = ((n & 0x1F) - 7);
                v = (v << 4) + n;
            }
            frameData[index + c] = v;
            ++c;
        }
    }

    function _write16bitAddress(frameData, index, address) {
        // Writes a 16-bit address (integer) into the passed-in blob.
        // Parameters:
        //   1. Blob into which the address bytes will be written
        //   2. Integer location in the blob at which to begin writing
        //   3. Integer holding the 16-bit address

        frameData[index] = (address & 0xFF00) >> 8;
        frameData[index + 1] = address & 0xFF;
    }

    function _read64bitAddress(frameData, start = 4) {
        // Reads the bytes representing a 64-bit address from the passed-in blob.
        // Returns:
        //   The 64-bit address as a string of 8 octets headed by '0x'

        local s = "0x";
        for (local i = start ; i < start + 8 ; ++i) {
            s = s + format("%02x", frameData[i]);
        }

        return s;
    }

    function _getNIstring(frame, index) {
        // Reads the Node Identifier string from the passed-in blob.
        // The string is variable length but zero terminated.
        // Parameters:
        //   1. Blob containing the received frame
        //   2. Index at which the NI string bytes begin
        // Returns:
        //   The NI string

        frame.seek(index, 'b');
        local length = 0;
        local c;

        do {
            c = frame.readn('b');
            length++;
        } while (c != 0);

        frame.seek(index, 'b');
        return frame.readstring(length - 1);
    }

    function _calculateChecksum(frame) {
        // Calculates an API frame's checksum
        // Parameter:
        //   The unescaped assembled frame
        // Returns:
        //   The checksum as an integer

        local cs = 0;
        for (local i = 3 ; i < frame.len() ; ++i) {
            cs += frame[i];
        }

        // Ignore all but the lowest 8 bits and subtract the result from 0xFF
        cs = 0xFF - (cs & 0xFF);
        return (cs & 0xFF);
    }

    function _testChecksum(frame) {
        // Tests the API frame's checksum
        // Parameter:
        //   The received frame after escaped characters have been processed
        // Returns:
        //   True if the checksum is valid, false otherwise

        local cs = 0;
        for (local i = 3 ; i < frame.len() ; ++i) {
            cs += frame[i];
        }

        cs = cs & 0xFF;
        if (cs == 0xFF) return true;
        return false;
    }

    function _escape(character) {
        // Returns true or false according to whether the passed in
        // value of 'character' is one of the standard escape characters
        local escChars = [0x7E, 0x7D, 0x11, 0x13];
        local match = false;
        foreach (value in escChars) {
            if (character == value) {
                match = true;
                break;
            }
        }

        return match;
    }

    function _listFrame(frame) {
        // Stringify the frame's component octets for debugging
        local fs = "";
        foreach (b in frame) fs = fs + format("%02x", b) + " ";
        return fs;
    }

    function _setATParameters(index, paramVal) {
        local aBlob = null;
        if (typeof paramVal == "string") {
            // Use strings in order to support 32-bit unsigned integers
            if (paramVal.slice(0, 2) == "0x") paramVal = paramVal.slice(2);
            if (paramVal.len() % 2 != 0) paramVal = "0" + paramVal;
            aBlob = blob(index + (paramVal.len() / 2));
            local p = 0;
            for (local i = 0 ; i < paramVal.len() ; i += 2) {
                local ss = paramVal.slice(i, i + 2);
                aBlob[index + p] = _intFromHex(ss);
                ++p;
            }
        } else {
            local numBytes = 0;
            if (paramVal == 0) {
                numBytes = 1;
            } else {
                local x = paramVal;
                while (x != 0) {
                    x = x >> 8;
                    ++numBytes;
                }
            }

            aBlob = blob(index + numBytes);
            aBlob.seek(index, 'b');
            local v, j;
            for (local i = 0 ; i < numBytes ; ++i) {
                j = ((numBytes - i) * 8) - 8;
                local v = (paramVal & (0xFF << j)) >> j;
                aBlob[index + i] = v
            }
        }

        return aBlob;
    }

    function _intFromHex(hs) {
        if (hs.slice(0, 2) == "0x") hs = hs.slice(2);
        local iv = 0;
        foreach (ch in hs) {
            local nb = ch - '0';
            if (nb > 9) nb = ((nb & 0x1F) - 7);
            iv = (iv << 4) + nb;
        }

        return iv;
    }


    // ********** Received Frame Decoder Functions **********

    function _decodeATResponse(data) {
        local decode = {};
        decode.cmdid <- data[3];
        decode.frameid <- data[4];
        decode.command <- (data[5].tochar() + data[6].tochar());
        decode.status <- {};
        decode.status.code <- data[7];
        decode.status.message <- _getATStatus(data[7]);
        data.seek(8, 'b');
        local len = (data[1] << 8) + data[2] - 5;
        if (len > 0) decode.data <- data.readblob(len);
        return decode;
    }

    function _decodeRemoteATCommand(data) {
        local decode = {};
        decode.cmdid <- data[3];
        decode.frameid <- data[4];
        decode.address64bit <- _read64bitAddress(data, 5);
        decode.address16bit <- (data[13] << 8) + data[14];
        decode.command <- (data[15].tochar() + data[16].tochar());
        decode.status <- {};
        decode.status.code <- data[17];
        decode.status.message <- _getATStatus(data[17]);
        data.seek(18, 'b');
        local len = (data[1] << 8) + data[2] - 14;
        if (len > 0) decode.data <- data.readblob(len);
        return decode;
    }

    function _decodeZigbeeReceivePacket(data) {
        local decode = {};
        decode.cmdid <- data[3];
        decode.frameid <- data[4];
        decode.address64bit <- _read64bitAddress(data);
        decode.address16bit <- (data[12] << 8) + data[13];
        decode.status <- {};
        decode.status.code <- data[14];
        decode.status.message <- _getPacketStatus(data[14]);
        data.seek(15, 'b');
        local len = (data[1] << 8) + data[2] - 12;
        if (len > 0) decode.data <- data.readblob(len);
        return decode;
    }

    function _decodeZigbeeRXIndicator(data) {
        local decode = {};
        decode.cmdid <- data[3];
        decode.address64bit <- _read64bitAddress(data, 4);
        decode.address16bit <- (data[12] << 8) + data[13];
        decode.sourceEndpoint <- data[14];
        decode.destinationEndpoint <- data[15];
        decode.clusterID <- (data[16] << 8) + data[17];
        decode.profileID <- (data[18] << 8) + data[19];
        decode.status <- {};
        decode.status.code <- data[20];
        decode.status.message <- _getPacketStatus(data[20]);
        data.seek(21, 'b');
        local len = (data[1] << 8) + data[2] - 18;
        if (len > 0) decode.data <- data.readblob(len);
        return decode;
    }

    function _decodeModemStatus(data) {
        local decode = {};
        decode.cmdid <- data[3];
        decode.status <- {};
        decode.status.code <- data[4];
        decode.status.message <- _getModemStatus(data[4]);
        return decode;
    }

    function _decodeZigbeeTransmitStatus(data) {
        local decode = {};
        decode.cmdid <- data[3];
        decode.frameid <- data[4];
        decode.address16bit <- (data[5] << 8) + data[6];
        decode.transmitRetryCount <- data[7];
        decode.deliveryStatus <- {};
        decode.deliveryStatus.code <- data[8];
        decode.deliveryStatus.message <- _getDeliveryStatus(data[8]);
        decode.discoveryStatus <- {};
        decode.discoveryStatus.code <- data[9];
        decode.discoveryStatus.message <- _getDiscoveryStatus(data[9]);
        return decode;
    }

    function _decodeNodeIDIndicator(data) {
        local decode = {};
        decode.cmdid <- data[3];
        decode.frameid <- data[4];
        decode.address64bit <- _read64bitAddress(data, 4);
        decode.address16bit <- (data[12] << 8) + data[13];
        decode.status <- {};
        decode.status.code <- data[14];
        decode.status.message <- _getPacketStatus(data[14]);
        decode.sourceAddress16bit <- (data[15] << 8) + data[16];
        decode.sourceAddress64bit <- _read64bitAddress(data, 17);
        decode.niString <- _getNiString(data, 25);
        local offset = decode.niString.len() + 26;
        decode.parent16BitAddress <- (data[offset] << 8) + data[offset + 1];
        decode.deviceType <- data[offset + 2];
        decode.sourceEvent <- data[offset + 3];
        decode.digiProfileID <- (data[offset + 4] << 8) + data[offset + 5];
        decode.manufacturerID <- (data[offset + 6] << 8) + data[offset + 7];
        return decode;
    }

    function _decodeRouteRecordIndicator(data) {
        local decode = {};
        decode.cmdid <- data[3];
        decode.frameid <- data[4];
        decode.address64bit <- _read64bitAddress(data);
        decode.address16bit <- (data[12] << 8) + data[13];
        decode.status <- {};
        decode.status.code <- data[14];
        decode.status.message <- _getRouteStatus(data[14]);
        decode.addresses <- [];

        for (local i = 0 ; i < data[15] ; ++i) {
            local a = (data[16 + (i * 2)] << 8) + data[17 + (i * 2)];
            decode.addresses.append(a);
        }

        return decode;
    }

    function _decodeManyToOneRouteIndicator(data) {
        local decode = {};
        decode.cmdid <- data[3];
        decode.frameid <- data[4];
        decode.address64bit <- _read64bitAddress(data);
        decode.address16bit <- (data[12] << 8) + data[13];
        return decode;
    }

    function _decodeZigbeeDataSampleRXIndicator(data) {
        local offset = 0;
        local decode = {};
        decode.cmdid <- data[3];
        decode.frameid <- data[4];
        decode.address64bit <- _read64bitAddress(data, 4);
        decode.address16bit <- (data[12] << 8) + data[13];
        decode.status <- {};
        decode.status.code <- data[14];
        decode.status.message <- _getPacketStatus(data[14]);
        decode.numberOfSamples <- data[15];

        decode.digitalMask <- (data[16] << 8) + data[17];
        if (decode.digitalMask > 0) {
            decode.digitalSamples <- (data[19] << 8) + data[20];
            offset = 2;
        }

        decode.analogMask <- data[18];
        if (decode.analogMask > 0) {
            decode.analogSamples <- [-1,-1,-1,-1,-1,-1,-1,-1];
            for (local k = 1 ; k < 9 ; ++k) {
                local mv = decode.analogMask >> k;
                if (mv == 1) {
                    decode.analogSamples[k - 1] = (data[19 + offset] << 8) + data[20 + offset];
                    offset += 2;
                }
            }
        }

        return decode;
    }

    function _decodeXBeeSensorReadIndicator(data) {
        local decode = {};
        decode.cmdid <- data[3];
        decode.frameid <- data[4];
        decode.address64bit <- _read64bitAddress(data, 4);
        decode.address16bit <- (data[12] << 8) + data[13];
        decode.status <- {};
        decode.status.code <- data[14];
        decode.status.message <- _getPacketStatus(data[14]);
        decode.oneWireStatus <- {};
        decode.oneWireStatus.code <- data[15];
        decode.oneWireStatus.message <- _getOneWireStatus(data[15]);
        data.seek(16, 'b');
        decode.data <- data.readblob(8);
        data.temp <- (data[24] << 8) + data[25];
        return decode;
    }

    // ********** Status Code Parsing Functions **********

    function _getATStatus(code) {
        local m = [ "OK",
                    "ERROR",
                    "Invalid Command",
                    "Invalid Parameter",
                    "TX Failure"];
        return m[code];
    }

    function _getModemStatus(code) {
        local m = [ 0x00, "Hardware Reset",
                    0x01, "Watchdog Timer Reset",
                    0x02, "Joined Network",
                    0x03, "Disassociated",
                    0x06, "Coordinator Started",
                    0x07, "Network Security Updated",
                    0x0D, "Voltage Supply Exceeded",
                    0x11, "Modem Config Changed"];
        for (local i = 0 ; i < m.len() ; i += 2) {
            if (code == m[i]) return m[i + 1];
        }

        if (code >= 0x80) return "Stack Error";
        return ("Unknown Modem Error: " + format("0x%02X", code));
    }

    function _getDeliveryStatus(code) {
        local m = [ 0x00, "Success",
                    0x01, "MAC ACK Failure",
                    0x02, "CCA Failure",
                    0x15, "Invalid Destination Endpoint",
                    0x21, "Network ACK Failure",
                    0x22, "Not Joined to Network",
                    0x23, "Self-addressed",
                    0x24, "Address Not Found",
                    0x25, "Route Not Found",
                    0x26, "Broadcast Source Failed to Hear a Neighbour Relay the Message",
                    0x2B, "Invalid Binding Table Index",
                    0x2C, "Resource Error: Lack of Free Buffers, Timers etc",
                    0x2D, "Attempted Broadcast with APS Transmission",
                    0x2E, "Attempted Unicast with APS Transmission, but EE=0",
                    0x32, "Resource Error: Lack of Free Buffers, Timers etc",
                    0x74, "Data Payload Too Large",
                    0x75, "Indirect Message Unrequested"];
        for (local i = 0 ; i < m.len() ; i += 2) {
            if (code == m[i]) return m[i + 1];
        }

        return ("Unknown Delivery Error: " + format("0x%02X", code));
    }

    function _getDiscoveryStatus(code) {
        local m = [ "No Discovery Overhead",
                    "Address Discovery",
                    "Route Discovery",
                    "Address and Route"];
        if (code < 0x04) return m[code];
        return "Extended Timeout Discovery";
    }

    function _getPacketStatus(code) {
        local s = "";
        if (code & 0x01) s = s + "Packet Acknowledged; ";
        if (code & 0x02) s = s + "Packet a Broadcast Packet; ";
        if (code & 0x20) s = s + "Packet Encrypted with APS; ";
        if (code & 0x40) s = s + "Packet Sent By End-Device; ";
        s = s.slice(0, s.len() - 2);
        return s;
    }

    function _getRouteStatus(code) {
        local m = ["Packet Acknowledged", "Packet was a Broadcast"];
        if (m < 0x01 || m > 0x02) return "Unknown Route Record status code";
        return m[code];
    }

    function _getOneWireStatus(code) {
        local s = "";
        if (code & 0x01) s = s + "A/D Sensor Read; ";
        if (code & 0x02) s = s + "Temperature Sensor Read; ";
        if (code & 0x60) s = s + "Water Present; ";
        s = s.slice(0, s.len() - 2);
        return s;
    }

    // ********** API Frame UART Reception Callback ************

    function _dataReceivedAPI() {
        // This callback is triggered on receipt of a single byte via UART
        local b = _uart.read();

        // Add byte to the frame buffer
        _buffer.writen(b, 'b');
        _frameByteCount++;

        // Increase the expected size of the frame by one byte every time
        // we encounter the escape marker 0x7D (if we're using escaping)
        if (_escaped && b == 0x7D) _frameSize++;

        if (_frameByteCount == 5) {
            // Now we have enough of the frame to calculate its length, do so
            // Note: if escaping is being used (AP = 2 / _escaped property is true)
            //       the length may need decoding accordingly
            if (_escaped) {
                if (_escape(_buffer[1])) {
                    _frameSize += ((_buffer[2] ^ 0x20) << 8);
                    if (_escape(_buffer[3])) {
                        _frameSize += (_buffer[4] ^ 0x20);
                    } else {
                        _frameSize += _buffer[3];
                    }
                } else {
                     _frameSize += (_buffer[1] << 8);
                    if (_escape(_buffer[2])) {
                        _frameSize += (_buffer[3] ^ 0x20);
                    } else {
                        _frameSize += _buffer[2];
                    }
                }
            } else {
                // No escaping, so data length calculation is straightforward
                _frameSize += (_buffer[1] << 8) + _buffer[2];
            }

            // Add bytes for the frame header (start marker, 16-bit length) and checksum
            _frameSize += 4;
            return;
        } else if (_frameByteCount < 5 || _frameByteCount < _frameSize) {
            return;
        }

        // Callback returns if insufficient bytes to make up the whole frame have been received.
        // The frame data size is included in the frame; to this we add the top and tail bytes.
        // When we have enough bytes to indicate a whole frame has been received we process it

        // Remove the escaping (or return the untouched frame if escaping is not being used)
        if (_debug) server.log("API Frame Received:  " + _listFrame(_buffer));
        local frame = _unmakeFrame(_buffer);
        if (_debug && _escaped) server.log("API Frame Unescaped: " + _listFrame(frame));

        // Clear the input buffer and indicators for the next frame
        _buffer = blob();
        _frameByteCount = 0;
        _frameSize = 0;

        if (frame[0] != 0x7E) {
            // The standard frame-start marker is missing - return an error to the host app
            _callback("Received data lacks frame header byte (0x7E)", null);
            return;
        }

        if (!_testChecksum(frame)) {
            // Frame checksum is invalid - return an error to the host app
            _callback("Received data failed checksum test", null);
            return;
        }

        // Decode the valid frame according to its frame type
        // then return to the host app the extracted data as a table
        switch (frame[3]) {
            case XBEE_CMD_AT_RESPONSE:
                _callback(null, _decodeATResponse(frame));
                break;

            case XBEE_CMD_MODEM_STATUS:
                _callback(null, _decodeModemStatus(frame));
                break;

            case XBEE_CMD_ZIGBEE_TRANSMIT_STATUS:
                _callback(null, _decodeZigbeeTransmitStatus(frame));
                break;

            case XBEE_CMD_ZIGBEE_RECEIVE_PACKET:
                _callback(null, _decodeZigbeeReceivePacket(frame));
                break;

            case XBEE_CMD_ZIGBEE_EXP_RX_INDICATOR:
                _callback(null, _decodeZigbeeRXIndicator(frame));
                break;

            case XBEE_CMD_ZIGBEE_IO_DATA_SAMPLE_RX_INDICATOR:
                _callback(null, _decodeZigbeeDataSampleRXIndicator(frame));
                break;

            case XBEE_CMD_XBEE_SENSOR_READ_INDICATOR:
                _callback(null, _decodeXBeeSensorReadIndicator(frame));
                break;

            case XBEE_CMD_NODE_ID_INDICATOR:
                _callback(null, _decodeNodeIDIndicator(frame));
                break;

            case XBEE_CMD_REMOTE_CMD_RESPONSE:
                _callback(null, _decodeRemoteATCommand(frame));
                break;

            case XBEE_CMD_ROUTE_RECORD_INDICATOR:
                _callback(null, _decodeRouteRecordIndicator(frame));
                break;

            case XBEE_CMD_MANY_TO_ONE_ROUTE_REQ_INDICATOR:
                _callback(null, _decodeManyToOneRouteIndicator(frame));
                break;

            default:
                // Unknown frame type - return an error to the host app
                _callback("Unknown frame type", null);
        }
    }

    // ********** AT / Transparent Mode Send and Receive Functions **********

    function _setCommandMode() {
        // Clear the pipe and wait for the guard period to pass
        _uart.flush();
        imp.sleep(_guardPeriod);

        // Issue the signal to enter AT command mode
        if (_debug) server.log("Sending +++ to enter command mode");
        _uart.write("+++");

        // Clear the pipe and wait for the guard period (again)
        _uart.flush();
        imp.sleep(_guardPeriod);

        // Record time as command mode is self-terminating after a fixed period
        _commandTime = hardware.millis();
    }

    function _dataReceivedAT() {
        // Callback triggered on receipt of a byte
        local b = _uart.read();

        if (bite.tochar() != CR && bite != -1) {
            // If we don't have a CR or EOL, store the byte
            _buffer.writen(bite, 'b');
            return;
        }

        // Clear the buffer for the next message
        local response = _buffer;
        _buffer = blob();

        if (response == "ERROR") {
            local errMessage = "Error from command " + _command.slice(0, _command.len() - 1);
            _callback(errMessage, null);
            return;
        }

        if (response == "OK" && _command) {
            // We are in command mode and ready to issue
            // the saved command ('_command')
            uart.write(_command);
            _command = null;
        } else {
            // We are receiving data after issuing a command.
            // So clear the stored command and return the received
            // data via the callback
            _callback(null, response);
        }
    }
}
