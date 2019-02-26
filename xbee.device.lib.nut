/**
 * XBee API Frame Type IDs.
 * @readonly
 * @enum {integer}
 */
enum XBEE_CMD {
        // **********  Request Commands  **********
        AT                                 = 0x08,
        QUEUE_PARAM_VALUE                  = 0x09,
        ZIGBEE_TRANSMIT_REQ                = 0x10,
        EXP_ADDR_ZIGBEE_CMD_FRAME          = 0x11,
        REMOTE_CMD_REQ                     = 0x17,
        CREATE_SOURCE_ROUTE                = 0x21,
        // ********** Response Frames **********
        AT_RESPONSE                        = 0x88,
        MODEM_STATUS                       = 0x8A,
        ZIGBEE_TRANSMIT_STATUS             = 0x8B,
        ZIGBEE_RECEIVE_PACKET              = 0x90,
        ZIGBEE_EXP_RX_INDICATOR            = 0x91,
        ZIGBEE_IO_DATA_SAMPLE_RX_INDICATOR = 0x92,
        XBEE_SENSOR_READ_INDICATOR         = 0x94,
        NODE_ID_INDICATOR                  = 0x95,
        REMOTE_CMD_RESPONSE                = 0x97,
        ROUTE_RECORD_INDICATOR             = 0xA1,
        DEVICE_AUTH_INDICATOR              = 0xA2,
        MANY_TO_ONE_ROUTE_REQ_INDICATOR    = 0xA3,
        JOIN_NOTIFICATION_STATUS           = 0xA5,
        // ********** NOT YET SUPPORTED **********
        REGISTER_DEVICE_JOIN               = 0x24,
        OTA_FIRMWARE_UPDATE_STATUS         = 0xA0,
        REGISTER_DEVICE_JOIN_STATUS        = 0xA4
}

/**
 * @constant {integer} CR
 */
const CR = "\x0D";

/**
 *  Library class for use with Digi Xbee Modules Series 2 & 3 operating in either API mode or AT mode.
 *
 *  @author    Tony Smith
 *  @copyright Electric Imp, Inc. 2016-19
 *  @license   MIT
 *  @version   2.0.0
 *
 *  @class
 */
class XBee {
    
    /**
     * @property {string} VERSION - The current version number.
     *
     */
    static VERSION = "2.0.0";

    // ********** Private properties **********
    _uart = null;
    _callback = null;
    _buffer = null;
    _command = null;

    _apiMode = false;
    _escaped = false;
    _escapeFlag = false;
    _ZDOFlag = false;
    _enabled = true;
    _debug = false;

    _guardPeriod = 1.0;
    _commandTime = -1;
    _commandModeTimeout = 100;
    _frameByteCount = 0;
    _frameSize = 0;
    _frameID = 0;
    _tranSeqNum = 0;

    /**
     *
     * The class constructor.
     * 
     * @param {imp::uart} impSerial - The UART to which the XBee is connected.
     * @param {function}  callback  - The function through which the host app communicates with the driver.
     * @param {bool}      [apiMode] - Whether the caller wants to use API mode (true) or 'transparent' AT mode (false). Default: true. 
     * @param {bool}      [escaped] - Whether the caller wants to use escaping (true) or not (false). Default: true.
     * @param {bool}      [debug]   - Whether the caller wants extra debigging info (true) or not (false). Default: false.
     *
     * @returns {instance} this
     *
     * @constructor
     *
     */
    constructor (impSerial = null, 
                 callback = null, 
                 apiMode = true, 
                 escaped = true, 
                 debug = false) {
        
        if (!impSerial) throw "XBee() requires a valid imp UART/serial bus";
        if (!callback)  throw "XBee()) requires a valid callback function";

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

    /**
     *
     * Initialize the UART used to communicate with the XBee.
     * 
     * @param {integer} [baudrate] - The required baudrate as an integer (1,200 - 1,000,000). Default: 9600.
     * @param {integer} [flags]    - Any imp API UART flags required (as integer bitfield). Default: 0.
     *
     * @returns {integer} The actual UART baudrate
     *
     */
    function init(baudrate = 9600, 
                  flags = 0) {
        
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
            // Make sure the API is set up for escaping (required)
            sendLocalATCommand("AP", (_escaped ? 2 : 1));
        } else {
            actual = _uart.configure(baudrate, 8, PARITY_NONE, 1, flags, _dataReceivedAT.bindenv(this));
        }

        if (_debug) server.log("Actual baud rate: " + actual + " baud");
        return actual;
    }

    /**
     *
     * Enable communication with the XBee.
     * 
     * @param {boolean} [state] - Should the XBee UART be enabled (true) or disabled (false). Default: true.
     *
     */
    function enable(state = true) {
        if (typeof state != "bool") state = true;
        _enabled = state;
    }

    /**
     *
     * Enable or disable extra debug information to be logged.
     * 
     * @param {boolean} [state] - Should the extra info be displayed (true) or not (false). Default: true.
     *
     */
    function debug(state = true) {
        if (typeof state != "bool") state = true;
        _debug = state;
    }

    /**
     *
     * Convenience function that can be used to set up network security. The settings must be applied to all 
     * devices on the network, unless stated.
     * 
     * @param {string} [panID]         - The required 64-bit PAN ID (string), or "" for a Coordinator-selected value. Default: "".
     * @param {bool}   [isCoordinator] - Is the device the network Co-ordinator? Default: false.
     * @param {string} [netKey]        - The required 128-bit AES Network Key (string), or "" for a Coordinator-selected value. Default: "".
     * @param {bool}   [isTrustCenter] - Is the Coordinator a Trust Center? Pass false on Routers and End Devices. Default: false.
     * @param {string} [linkKey]       - The required 128-bit AES Link Key (string), or " "for a Coordinator-selected value. Default: "".
     * @param {bool}   [save]          - Write the new network values to persistent storage on the XBee? Default: true.
     *
     */
    function setSecurity(panID = "", 
                         isCoordinator = false, 
                         netKey = "", 
                         isTrustCenter = false, 
                         linkKey = "", 
                         save = false) {
        
        if (panID.len() > 0) sendATCommand("ID", panID);
        sendLocalATCommand("EE", 0x01);
        sendLocalATCommand("EO", (isCoordinator && isTrustCenter ? 0x02 : 0x01));

        if (isCoordinator) {
            sendLocalATCommand("NK", (netKey.len() > 0 ? netKey : 0));
            sendLocalATCommand("KY", (linkKey.len() > 0 ? linkKey : 0));
        } else {
            if (linkKey.len() > 0) sendLocalATCommand("KY", linkKey);
        }
        
        if (save) sendLocalATCommand("WR");
    }

    // *************** TRANSMISSION COMMAND FUNCTIONS **************

    // **************    API Frame Mode Functions    ***************
    // [  API mode must be enabled with appropriate XBee firmware  ]

    /**
     *
     * Send an AT command to the local XBee (API mode).
     * 
     * @param {string}  command          - A two-character string representing the AT command, eg. "HV" - Get Hardware Version.
     * @param {integer} [parameterValue] - Command parameter value. -1 indicates no supplied value. Default: -1.
     * @param {integer} [frameID]        - The frame ID. -1 indicates the library should set this value. Default: -1.
     *
     * @returns {integer} The transmitted frame's ID.
     *
     */
    function sendLocalATCommand(command, 
                                parameterValue = -1, 
                                frameID = -1) {
        
        local dataBlob;
        if (parameterValue != -1) {
            dataBlob = _setATParameters(3, parameterValue);
        } else {
            dataBlob = blob(3);
        }

        if (frameID == -1) {
            _frameID++;
            if (_frameID > 255) _frameID = 1;
            dataBlob[0] = _frameID;
        } else {
            dataBlob[0] = frameID;
        }

        dataBlob[1] = command[0];
        dataBlob[2] = command[1];

        _sendFrame(_makeFrame(XBEE_CMD.AT, dataBlob));

        if (_debug) server.log(format("AT Command \"%s\" sent as frame ID %u", command, dataBlob[0]));

        return (frameID == -1 ? _frameID : frameID);
    }

    /**
     *
     * Enqueue an AT command for the local XBee (API mode).
     * 
     * @param {string}  command          - A two-character string representing the AT command, eg. "HV" - Get Hardware Version.
     * @param {integer} [parameterValue] - Command parameter value. -1 indicates no supplied value. Default: -1.
     * @param {integer} [frameID]        - The frame ID. -1 indicates the library should set this value. Default: -1.
     *
     * @returns {integer} The transmitted frame's ID.
     *
     */
    function sendQueuedATCommand(command, 
                                 parameterValue = -1, 
                                 frameID = -1) {

        local dataBlob;
        if (parameterValue != -1) {
            dataBlob = _setATParameters(3, parameterValue);
        } else {
            dataBlob = blob(3);
        }

        if (frameID == -1) {
            _frameID++;
            if (_frameID > 255) _frameID = 1;
            dataBlob[0] = _frameID;
        } else {
            dataBlob[0] = frameID;
        }

        dataBlob[1] = command[0];
        dataBlob[2] = command[1];

        _sendFrame(_makeFrame(XBEE_CMD.QUEUE_PARAM_VALUE, dataBlob));

        if (_debug) server.log(format("Queued AT Command sent as frame ID %u", dataBlob[0]));

        return (frameID == -1 ? _frameID : frameID);
    }

    /**
     *
     * Send an AT command to a remote XBee (API mode).
     * 
     * @param {string}  command          - A two-character string representing the AT command, eg. "HV" - Get Hardware Version.
     * @param {string}  address64bit     - The 64-bit destination device address as a hex string.
     * @param {integer} address16bit     - The 16-bit destination network address.
     * @param {integer} [options]        - A bitfield of options. Default: 0.
     * @param {integer} [parameterValue] - Command parameter value. -1 indicates no supplied value. Default: -1.
     * @param {integer} [frameID]        - The frame ID. -1 indicates the library should set this value. Default: -1.
     *
     * @returns {integer} The transmitted frame's ID.
     *
     */
    function sendRemoteATCommand(command, 
                                 address64bit, 
                                 address16bit, 
                                 options = 0, 
                                 parameterValue = -1, 
                                 frameID = -1) {
        
        local dataBlob;
        if (parameterValue != -1) {
            dataBlob = _setATParameters(14, parameterValue);
        } else {
            dataBlob = blob(14);
        }

        if (frameID == -1) {
            _frameID++;
            if (_frameID > 255) _frameID = 1;
            dataBlob[0] = _frameID;
        } else {
            dataBlob[0] = frameID;
        }

        _write64bitAddress(dataBlob, 1, address64bit);
        _write16bitAddress(dataBlob, 9, address16bit);

        dataBlob[11] = options;
        dataBlob[12] = command[0];
        dataBlob[13] = command[1];

        _sendFrame(_makeFrame(XBEE_CMD.REMOTE_CMD_REQ, dataBlob));

        if (_debug) server.log(format("Remote AT Command \"%s\" sent as frame ID %u", command, dataBlob[0]));

        return (frameID == -1 ? _frameID : frameID);
    }

    /**
     *
     * Send a simple Zigbee request to a remote XBee.
     * 
     * @param {string}  address64bit - The 64-bit destination device address as a hex string.
     * @param {integer} address16bit - The 16-bit destination network address.
     * @param {blob}    data         - The data to be transmitted.
     * @param {integer} [radius]     - The broadcast radius. Default: 0 (max. radius).
     * @param {integer} [options]    - A bitfield of options. Default: 0.
     * @param {integer} [frameID]    - The frame ID. -1 indicates the library should set this value. Default: -1.
     *
     * @returns {integer} The transmitted frame's ID.
     *
     */
    function sendZigbeeRequest(address64bit, 
                               address16bit, 
                               data, 
                               radius = 0, 
                               options = 0, 
                               frameID = -1) {

        local dataBlob = blob(13 + data.len());

        if (frameID == -1) {
            _frameID++;
            if (_frameID > 255) _frameID = 1;
            dataBlob[0] = _frameID;
        } else {
            dataBlob[0] = frameID;
        }

        _write64bitAddress(dataBlob, 1, address64bit);
        _write16bitAddress(dataBlob, 9, address16bit);

        dataBlob[11] = radius;
        dataBlob[12] = options;
        dataBlob.seek(13, 'b');
        dataBlob.writeblob(data);

        _sendFrame(_makeFrame(XBEE_CMD.ZIGBEE_TRANSMIT_REQ, dataBlob));

        if (_debug) server.log(format("ZigBee TX Request sent as frame ID %u", dataBlob[0]));

        return (frameID == -1 ? _frameID : frameID);
    }

    /**
     *
     * Send a detailed Zigbee request to a remote XBee.
     * 
     * @param {string}  address64bit   - The 64-bit destination device address as a hex string.
     * @param {integer} address16bit   - The 16-bit destination network address.
     * @param {integer} sourceEndpoint - The source endpoint.
     * @param {integer} destEndpoint   - The destination endpoint.
     * @param {integer} clusterID      - The 16-bit cluster ID.
     * @param {integer} profileID      - The 16-bit profile ID.
     * @param {blob}    payload        - The data to be transmitted.
     * @param {integer} [radius]       - The broadcast radius. Default: 0 (max. radius).
     * @param {integer} [options]      - A bitfield of options. Default: 0.
     * @param {integer} [frameID]      - The frame ID. -1 indicates the library should set this value. Default: -1.
     *
     * @returns {integer} The transmitted frame's ID.
     *
     */
    function sendExplicitZigbeeRequest(address64bit, 
                                       address16bit, 
                                       sourceEndpoint, 
                                       destEndpoint, 
                                       clusterID, 
                                       profileID, 
                                       payload, 
                                       radius = 0, 
                                       options = 0, 
                                       frameID = -1) {

        local dataBlob = blob(19 + payload.len());

        if (frameID == -1) {
            // Use internal Frame ID counter
            _frameID++;
            if (_frameID > 255) _frameID = 1;
            // NOTE Don't cycle to zero as this has a special XBee meaning: don't send a response
            dataBlob[0] = _frameID;
        } else {
            dataBlob[0] = frameID;
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
        dataBlob.writeblob(payload);

        _sendFrame(_makeFrame(XBEE_CMD.EXP_ADDR_ZIGBEE_CMD_FRAME, dataBlob));

        if (_debug) server.log(format("Explicit Addressing ZigBee Command sent as frame ID %u of %u bytes", dataBlob[0], dataBlob.len()));

        return (frameID == -1 ? _frameID : frameID);
    }

    /**
     *
     * Send a Zigbee source route command.
     * 
     * @param {string}  address64bit - The 64-bit destination device address as a hex string.
     * @param {integer} address16bit - The 16-bit destination network address.
     * @param {array}   addresses    - An array of 16-bit addresses describing the route.
     * @param {integer} [frameID]    - The frame ID. -1 indicates the library should set this value. Default: -1.
     *
     * @returns {integer} The transmitted frame's ID.
     *
     */
    function createSourceRoute(address64bit, 
                               address16bit, 
                               addresses, 
                               frameID = -1) {
        
        local dataBlob = blob(19);

        if (frameID == -1) {
            _frameID++;
            if (_frameID > 255) _frameID = 1;
            dataBlob[0] = _frameID;
        } else {
            dataBlob[0] = frameID;
        }

        _write64bitAddress(dBlob, 1, address64bit);
        _write16bitAddress(dBlob, 9, address64bit);

        dataBlob[11] = 0x00;
        dataBlob[12] = addresses.len();

        for (local i = 0 ; i < dataBlob[12] ; ++i) {
            _write16bitAddress(dBlob, 13 + (i * 2), addresses[i]);
        }

        _sendFrame(_makeFrame(XBEE_CMD.CREATE_SOURCE_ROUTE, dataBlob));

        if (_debug) server.log(format("Create Source Route sent as frame ID %u", dataBlob[0]));

        return (frameID == -1 ? _frameID : frameID);
    }

    // **** Zigbee Device Object (ZDO) / Zigbee Cluster Library (ZCL) Functions ****

    /**
     *
     * Send a Zigbee Device Object command frame.
     * 
     * @param {string}  address64bit - The 64-bit destination device address as a hex string.
     * @param {integer} address16bit - The 16-bit destination network address.
     * @param {integer} clusterID    - The 16-bit cluster ID.
     * @param {blob}    ZDOpayload   - The data to be transmitted.
     * @param {integer} [frameID]      - The frame ID. -1 indicates the library should set this value. Default: -1.
     *
     * @returns {table} Table contains two keys: 'transaction' (the transaction sequence number) and 'frameid' (the frame ID).
     *
     */
    function sendZDO(address64bit, 
                     address16bit, 
                     clusterID, 
                     ZDOpayload, 
                     frameID = -1) {
        
        // Is the system set up for ZDO? If not, make sure it is
        if (!_ZDOFlag) {
            enterZDMode();
            if (_ZDOFlag == false) return;
        }

        // Pass in addresses; set endpoints and profile ID to 0; set clusterID
        local fid = sendExplicitZigbeeRequest(address64bit, 
                                              address16bit, 
                                              0x00,                 // Fixed Source Endpoint for ZDO
                                              0x00,                 // Fixed Dest. Endpoint for ZDO 
                                              clusterID, 
                                              0x0000,               // Fixed Profile ID for ZDO
                                              ZDOpayload, 
                                              0x00,                 // Default Radius value
                                              0x00,                 // Default Options value
                                              frameID);
        local ret = {};
        ret.transaction <- ZDOpayload[0];
        ret.frameid <- fid;
        return ret;
    }

    /**
     *
     * Send a Zigbee Cluster Library command frame.
     * 
     * @param {string}  address64bit   - The 64-bit destination device address as a hex string.
     * @param {integer} address16bit   - The 16-bit destination network address.
     * @param {integer} sourceEndpoint - The source endpoint.
     * @param {integer} destEndpoint   - The destination endpoint.
     * @param {integer} clusterID      - The 16-bit cluster ID.
     * @param {integer} profileID      - The 16-bit profile ID.
     * @param {blob}    ZCLframe       - The frame to be transmitted.
     * @param {integer} [frameID]      - The frame ID. -1 indicates the library should set this value. Default: -1.
     *
     * @returns {table} Table contains two keys: 'transaction' (the transaction sequence number) and 'frameid' (the frame ID).
     *
     */
    function sendZCL(address64bit, 
                     address16bit, 
                     sourceEndpoint, 
                     destEndpoint, 
                     clusterID, 
                     profileID, 
                     ZCLframe, 
                     frameID = -1) {
        
        // Is the system set up for ZDO? If not, make sure it is
        if (!_ZDOFlag) {
            enterZDMode();
            if (_ZDOFlag == false) return;
        }

        // Pass in addresses; set endpoints and profile ID to 0; set clusterID
        local fid = sendExplicitZigbeeRequest(address64bit, 
                                              address16bit, 
                                              sourceEndpoint, 
                                              destEndpoint, 
                                              clusterID, 
                                              profileID, 
                                              ZCLframe, 
                                              0x00,                    // Default Radius value 
                                              0x00,                    // Default Options value
                                              frameID);
        local ret = {};
        ret.transaction <- ZCLframe[0];
        ret.frameid <- fid;
        return ret;
    }

    /**
     *
     * Enter Zigbee Device Objects mode.
     *
     */
    function enterZDMode() {
        if (!_apiMode) {
            // Zigbee Device Objects mode not supported in AT Mode
            server.error("XBees can't send or receive Zigbee Device Objects in AT mode");
            _ZDOFlag = false;
            return;
        }

        // Push local and remote devices to AO = 1
        sendLocalATCommand("AO", 1);
        _ZDOFlag = true;
    }

    /**
     *
     * Exit Zigbee Device Objects mode.
     *
     */
    function exitZDMode() {
        // Push local and remote devices to AO = 0
        sendLocalATCommand("AO", 0);
        _ZDOFlag = false;
    }

    /**
     *
     * Assemble and return a blob configured as a ZCL frame header.
     * 
     * @param {bool}    [isGeneralCommand]      - Is the command a general cluster command (true) or a cluster-specific command (false). Default: true.
     * @param {bool}    [isManufacturerCommand] - Is the the command manufacturer-specific (true), or not (false). Default: false.
     * @param {bool}    [targetsServer]         - Is the command being sent to the cluster server (true), or the cluster client (false). Default: true.
     * @param {integer} [tranSeqNum]            - A Transaction Sequence Number. -1 = the instance will set this value. Default: -1.
     * @param {integer} [commandID]             - An 8-bit command value. Default: 0x00.
     *
     * @returns {blob} The ZCL header bytes.
     *
     */
    function makeZCLHeader(isGeneralCommand = true, 
                           isManufacturerCommand = false, 
                           targetsServer = true, 
                           tranSeqNum = -1, 
                           commandID = 0x00) {

        local header = blob(3);
        
        // Assemble the Frame Control Byte (non-set bits must be clear)
        local fcb = 0;
        if (!isGeneralCommand) fcb = 1;
        if (isManufacturerCommand) fcb = fcb | 4;
        if (!targetsServer) fcb = fcb | 8;
        header[0] = fcb;

        // Add the Transaction Sequence Number
        if (tranSeqNum == -1) {
            // Use the instance's own value
            header[1] = _tranSeqNum;
            _tranSeqNum++;
            if (_tranSeqNum > 255) _tranSeqNum = 0;
        } else {
            header[1] = tranSeqNum;
        }

        // Finally, add the Command ID
        header[2] = commandID;
        return header;
    }

    // ********** AT / Transparent Mode Functions **********

    /**
     *
     * Send an AT command to the local XBee (AT mode).
     * 
     * @param {string}  command          - A two-character string representing the AT command, eg. "HV" - Get Hardware Version.
     * @param {integer} [parameterValue] - Command parameter value. -1 indicates no supplied value. Default: -1.
     *
     * @returns {integer} The transaction ID.
     *
     */
    function sendCommand(command, 
                         parameterValue = -1) {
        
        if (_enabled == false) return;
        
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
        _frameID++;
        if (_frameID > 255) _frameID = 1;
        return _frameID;
    }

    // ********** PRIVATE METHODS - DO NOT CALL **********

    // ********** API Frame Encoding/Decoding Functions **********

    /**
     *
     * Assemble an API frame from the supplied payload, handling escaping as necessary.
     * 
     * @param {integer} command - An API command code.
     * @param {blob}    data    - Frame payload.
     *
     * @returns {blob} The assembled frame.
     *
     * @private
     */
    function _makeFrame(cmdID, data) {
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
            local escFrame = blob();
            foreach (i, bite in frame) {
                if (i == 0) {
                    // Don't escape the header
                    escFrame.writen(bite, 'b');
                } else {
                    // Check for escaped characters
                    local match = _escape(bite);
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

    /**
     *
     * Transmit an API frame.
     * 
     * @param {blob} frame - The full frame.
     *
     * @private
     */
    function _sendFrame(frame) {
        // If the XBee is disabled, do not send the data
        if (_enabled == false) return;
        
        // Send the frame to the XBee via serial
        if (_debug) server.log("API Frame Sent: " + _listFrame(frame));

        // Write out the frame
        _uart.write(frame);
    }

    /**
     *
     * Write a 64-bit address into the supplied frame.
     * 
     * @param {blob}    frame   - The frame.
     * @param {integer} index   - Location of the first byte of the address.
     * @param {string}  address - String of 1-8 octets representing the address with or without '0x' header.
     *
     * @private
     */
    function _write64bitAddress(frame, index, address) {
        if (address.len() > 2 && address.slice(0, 2) == "0x") address = address.slice(2);
        if (address.len() < 16) address = "0000000000000000".slice(0, 16 - address.len()) + address;
        if (address.len() > 16) address = address.slice(0, 16);
        local c = 0;
        for (local i = 0 ; i < address.len() ; i += 2) {
            local a = address.slice(i, i + 2);
            local v = 0;
            foreach (ch in a) {
                local n = ch - '0';
                if (n > 9) n = ((n & 0x1F) - 7);
                v = (v << 4) + n;
            }
            frame[index + c] = v;
            ++c;
        }
    }

    /**
     *
     * Write a 16-bit address into the supplied frame.
     * 
     * @param {blob}    frame   - The frame.
     * @param {integer} index   - Location of the first byte of the address.
     * @param {integer} address - The 16-bit address. Bits above 15 are ignored.
     *
     * @private
     */
    function _write16bitAddress(frame, index, address) {
        frame[index] = (address & 0xFF00) >> 8;
        frame[index + 1] = address & 0xFF;
    }

    /**
     *
     * Read a 64-bit address from a frame.
     * 
     * @param {blob}    frame   - The frame.
     * @param {integer} [index] - Location of the first byte of the address. Default: 4.
     *
     * @returns {string} The 64-bit address as a string of 8 octets headed by '0x'.
     *
     * @private
     */
    function _read64bitAddress(frame, index = 4) {
        local s = "0x";
        for (local i = index ; i < index + 8 ; i++) {
            s = s + format("%02x", frame[i]);
        }
        return s;
    }

    /**
     *
     * Read a Node Identifier string from a frame.
     * 
     * @param {blob}    frame - The frame.
     * @param {integer} index - Location of the first byte of the address.
     *
     * @returns {string} The Node Identifier.
     *
     * @private
     */
    function _getNIstring(frame, index) {
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

    /**
     *
     * Calculate an API frame's checksum.
     * 
     * @param {blob} frame - The unescaped assembled frame.
     *
     * @returns {integer} The checksum.
     *
     * @private
     */
    function _calculateChecksum(frame) {
        local cs = 0;
        for (local i = 3 ; i < frame.len() ; i++) cs += frame[i];
        // Ignore all but the lowest 8 bits and subtract the result from 0xFF
        cs = 0xFF - (cs & 0xFF);
        return (cs & 0xFF);
    }

    /**
     *
     * Test the API frame's checksum.
     * 
     * @param {blob} frame - The received frame after escaped characters have been processed.
     *
     * @returns {bool} True if the checksum is valid, otherwise false.
     *
     * @private
     */
    function _testChecksum(frame) {
        local cs = 0;
        for (local i = 3 ; i < frame.len() ; i++) cs += frame[i];
        cs = cs & 0xFF;
        if (cs == 0xFF) return true;
        return false;
    }

    /**
     *
     * Test the API frame's checksum.
     * 
     * @param {char} character - A byte from a frame.
     *
     * @returns {bool} True if the character is one of the standard escape character, otherwise false.
     *
     * @private
     */
    function _escape(character) {
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

    /**
     *
     * Stringify the frame's bytes for debugging
     * 
     * @param {blob} frame - The received frame.
     *
     * @returns {string} The frame as a hex string
     *
     * @private
     */
    function _listFrame(frame) {
        local fs = "";
        foreach (b in frame) fs = fs + format("%02x", b) + " ";
        return fs;
    }

    /**
     *
     * Convert an AT command parameter value into a blob.
     * 
     * @param {integer} index - The received frame.
     * @param {any}     value - The value to be enblobbed.
     *
     * @returns {blob} The blobbed value.
     *
     * @private
     */
    function _setATParameters(index, value) {
        local aBlob = null;
        if (typeof value == "string") {
            // Use strings in order to support 32-bit unsigned integers, 64-bit integers, etc.
            if (value.len() > 2 && value.slice(0, 2) == "0x") value = value.slice(2);
            if (value.len() % 2 != 0) value = "0" + value;
            aBlob = blob(index + (value.len() / 2));
            local p = 0;
            for (local i = 0 ; i < value.len() ; i += 2) {
                local ss = value.slice(i, i + 2);
                aBlob[index + p] = _intFromHex(ss);
                p++;
            }
        } else if (typeof value == "integer" || typeof value == "float") {
            if (typeof value == "float") value = value.tointeger();
            local numBytes = 0;
            if (value == 0) {
                numBytes = 1;
            } else {
                local x = value;
                while (x != 0) {
                    x = x >> 8;
                    numBytes++;
                }
            }

            aBlob = blob(index + numBytes);
            aBlob.seek(index, 'b');
            local v, j;
            for (local i = 0 ; i < numBytes ; ++i) {
                j = ((numBytes - i) * 8) - 8;
                local v = (value & (0xFF << j)) >> j;
                aBlob[index + i] = v
            }
        }

        return aBlob;
    }

    /**
     *
     * Convert a hex string to an integer.
     * 
     * @param {string} hs - The hex string with or with the '0x' prefix.
     *
     * @returns {integer} The integer value.
     *
     * @private
     */
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

    /**
     * @typedef {table} statustable
     *
     * @property {integer} code    - The status code.
     * @property {string}  message - Human-readable status message.
     */

    /**
     * @typedef {table} atlresponse
     *
     * @property {integer}     cmdid   - The Command ID.
     * @property {integer}     frameid - The frame ID.
     * @property {string}      command - The two-character AT comand.
     * @property {statustable} status  - Transaction status information.
     * @property {blob}        data    - The response payload.
     */

    /**
     *
     * Decode an AT command response packet from the local device.
     * 
     * @param {blob} data - The response data.
     *
     * @returns {atlresponse} The decoded response.
     *
     * @private
     */
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

    /**
     * @typedef {table} atrresponse
     *
     * @property {integer}     cmdid        - The Command ID.
     * @property {integer}     frameid      - The frame ID.
     * @property {string}      address64bit - The remote device's 64-bit address.
     * @property {integer}     address16bit - The remote device's 16-bit address.
     * @property {string}      command      - The two-character AT comand.
     * @property {statustable} status       - Transaction status information.
     * @property {blob}        data         - The response payload.
     */

    /**
     *
     * Decode an AT command response packet from a remote device.
     * 
     * @param {blob} data - The response data.
     *
     * @returns {atrresponse} The decoded response.
     *
     * @private
     */
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

    /**
     * @typedef {table} zdpresponse
     *
     * @property {integer}     cmdid        - The Command ID.
     * @property {string}      address64bit - The remote device's 64-bit address.
     * @property {integer}     address16bit - The remote device's 16-bit address.
     * @property {string}      command      - The two-character AT comand.
     * @property {statustable} status       - Transaction status information.
     * @property {blob}        data         - The response payload.
     */

    /**
     *
     * Decode a Received Zigbee packet.
     * 
     * @param {blob} data - The response data.
     *
     * @returns {zdpresponse} The decoded response.
     *
     * @private
     */
    function _decodeZigbeeReceivePacket(data) {
        local decode = {};
        decode.cmdid <- data[3];
        decode.address64bit <- _read64bitAddress(data, 4);
        decode.address16bit <- (data[12] << 8) + data[13];
        decode.status <- {};
        decode.status.code <- data[14];
        decode.status.message <- _getPacketStatus(data[14]);
        data.seek(15, 'b');
        local len = (data[1] << 8) + data[2] - 12;
        if (len > 0) decode.data <- data.readblob(len);
        return decode;
    }

    /**
     * @typedef {table} zrxresponse
     *
     * @property {integer}     cmdid               - The Command ID.
     * @property {string}      address64bit        - The remote device's 64-bit address.
     * @property {integer}     address16bit        - The remote device's 16-bit address.
     * @property {integer}     sourceEndpoint      - The source endpoint.
     * @property {integer}     destinationEndpoint - The destination endpoint.
     * @property {integer}     clusterID           - The cluster ID.
     * @property {integer}     profileID           - The profile ID.
     * @property {statustable} status              - Transaction status information.
     * @property {blob}        data                - The response payload.
     */

    /**
     *
     * Decode a Zigbee RX Indicator response packet (frame ID 0x91).
     * 
     * @param {blob} data - The response data.
     *
     * @returns {zrxresponse} The decoded response.
     *
     * @private
     */
    function _decodeZigbeeRXIndicator(data) {
        local decode = {};
        decode.cmdid <- data[3];
        decode.address64bit <- _read64bitAddress(data, 4);
        decode.address16bit <- ((data[12] << 8) + data[13]);
        decode.sourceEndpoint <- data[14];
        decode.destinationEndpoint <- data[15];
        decode.clusterID <- ((data[16] << 8) + data[17]);
        decode.profileID <- ((data[18] << 8) + data[19]);
        decode.status <- {};
        decode.status.code <- data[20];
        decode.status.message <- _getPacketStatus(data[20]);
        data.seek(21, 'b');
        local len = (data[1] << 8) + data[2] - 18;
        if (len > 0) decode.data <- data.readblob(len);
        return decode;
    }

    /**
     * @typedef {table} mdsresponse
     *
     * @property {integer}     cmdid  - The Command ID.
     * @property {statustable} status - Transaction status information.
     */

    /**
     *
     * Decode a modem status packet.
     * 
     * @param {blob} data - The response data.
     *
     * @returns {mdsresponse} The decoded response.
     *
     * @private
     */
    function _decodeModemStatus(data) {
        local decode = {};
        decode.cmdid <- data[3];
        decode.status <- {};
        decode.status.code <- data[4];
        decode.status.message <- _getModemStatus(data[4]);
        return decode;
    }

    /**
     * @typedef {table} deliverytab
     *
     * @property {integer} code    - The status code.
     * @property {string}  message - Human-readable status message.
     */

    /**
     * @typedef {table} discoverytab
     *
     * @property {integer} code    - The status code.
     * @property {string}  message - Human-readable status message.
     */

    /**
     * @typedef {table} ztxresponse
     *
     * @property {integer}      cmdid              - The Command ID.
     * @property {integer}      frameid            - The frame ID.
     * @property {integer}      address16bit       - The remote device's 16-bit address.
     * @property {integer}      transmitRetryCount - The number of transmit retries.
     * @property {deliverytab}  deliveryStatus     - Delivery information.
     * @property {discoverytab} discoveryStatus    - Discovery information.
     */

    /**
     *
     * Decode a Zigbee TX status packet.
     * 
     * @param {blob} data - The response data.
     *
     * @returns {`txresponse} The decoded response.
     *
     * @private
     */
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

    /**
     * @typedef {table} nidresponse
     *
     * @property {integer}     cmdid              - The Command ID.
     * @property {string}      address64bit       - The remote device's 64-bit address.
     * @property {integer}     address16bit       - The remote device's 16-bit address.
     * @property {statustable} status             - Transaction status information.
     * @property {string}      sourceAddress64bit - The 64-bit address of the message source.
     * @property {integer}     sourceAddress16bit - The 16-bit address of the message source.
     * @property {string}      nistring           - The Node Indicator string.
     * @property {integer}     parentAddress16bit - The remote's parent device's 16-bit address.
     * @property {integer}     deviceType         - The type of device: coordinator, router or end-device.
     * @property {integer}     sourceEvent        - The event type.
     * @property {integer}     digiProfileID      - A 16-bit Digi XBee ID.
     * @property {integer}     manufacturerID     - The 16-bit device-manufacturer ID.
     */

    /**
     *
     * Decode a Node ID Indicator packet.
     * 
     * @param {blob} data - The response data.
     *
     * @returns {nidresponse} The decoded response.
     *
     * @private
     */
    function _decodeNodeIDIndicator(data) {
        local decode = {};
        decode.cmdid <- data[3];
        decode.address64bit <- _read64bitAddress(data, 4);
        decode.address16bit <- (data[12] << 8) + data[13];
        decode.status <- {};
        decode.status.code <- data[14];
        decode.status.message <- _getPacketStatus(data[14]);
        decode.sourceAddress16bit <- (data[15] << 8) + data[16];
        decode.sourceAddress64bit <- _read64bitAddress(data, 17);
        decode.niString <- _getNiString(data, 25);
        local offset = decode.niString.len() + 26;
        decode.parent16bitAddress <- (data[offset] << 8) + data[offset + 1];
        decode.deviceType <- data[offset + 2];
        decode.sourceEvent <- data[offset + 3];
        decode.digiProfileID <- (data[offset + 4] << 8) + data[offset + 5];
        decode.manufacturerID <- (data[offset + 6] << 8) + data[offset + 7];
        return decode;
    }

    /**
     * @typedef {table} rriresponse
     *
     * @property {integer}     cmdid        - The Command ID.
     * @property {string}      address64bit - The remote device's 64-bit address.
     * @property {integer}     address16bit - The remote device's 16-bit address.
     * @property {statustable} status       - Transaction status information.
     * @property {array}       addresses    - The 64-bit addresses of the route to the device.
     */

    /**
     *
     * Decode a Route Record packet.
     * 
     * @param {blob} data - The response data.
     *
     * @returns {rriresponse} The decoded response.
     *
     * @private
     */
    function _decodeRouteRecordIndicator(data) {
        local decode = {};
        decode.cmdid <- data[3];
        decode.address64bit <- _read64bitAddress(data, 4);
        decode.address16bit <- (data[12] << 8) + data[13];
        decode.status <- {};
        decode.status.code <- data[14];
        decode.status.message <- _getRouteStatus(data[14]);
        decode.addresses <- [];

        if (data[15] > 0) {
            for (local i = 0 ; i < data[15] ; i++) {
                local a = (data[16 + (i * 2)] << 8) + data[17 + (i * 2)];
                decode.addresses.append(a);
            }
        }

        return decode;
    }

    /**
     * @typedef {table} rmiresponse
     *
     * @property {integer} cmdid        - The Command ID.
     * @property {string}  address64bit - The remote device's 64-bit address.
     * @property {integer} address16bit - The remote device's 16-bit address.
     */

    /**
     *
     * Decode a Many To One Route Record packet.
     * 
     * @param {blob} data - The response data.
     *
     * @returns {rmiresponse} The decoded response.
     *
     * @private
     */
    function _decodeManyToOneRouteIndicator(data) {
        local decode = {};
        decode.cmdid <- data[3];
        decode.address64bit <- _read64bitAddress(data, 4);
        decode.address16bit <- (data[12] << 8) + data[13];
        return decode;
    }

    /**
     * @typedef {table} zdsresponse
     *
     * @property {integer}     cmdid           - The Command ID.
     * @property {string}      address64bit    - The remote device's 64-bit address.
     * @property {integer}     address16bit    - The remote device's 16-bit address.
     * @property {statustable} status          - Transaction status information.
     * @property {integer}     numberOfSamples - How many samples the data contains.
     * @property {integer}     digitalMask     - Digital sample encoding information.
     * @property {integer}     digitalSamples  - Digital sample data in a 16-bit bitfield.
     * @property {integer}     analogMask      - Analog sample encoding information.
     * @property {integer}     analogSamples   - 16-bit analog sample data in sequence.
     */

    /**
     *
     * Decode a Zigbee Data Sample packet.
     * 
     * @param {blob} data - The response data.
     *
     * @returns {zdsresponse} The decoded response.
     *
     * @private
     */
    function _decodeZigbeeDataSampleRXIndicator(data) {
        local offset = 0;
        local decode = {};
        decode.cmdid <- data[3];
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

    /**
     * @typedef {table} owstatustable
     *
     * @property {integer} code    - The status code.
     * @property {string}  message - Human-readable status message.
     */

    /**
     * @typedef {table} xsrresponse
     *
     * @property {integer}       cmdid         - The Command ID.
     * @property {string}        address64bit  - The remote device's 64-bit address.
     * @property {integer}       address16bit  - The remote device's 16-bit address.
     * @property {statustable}   status        - Transaction status information.
     * @property {owstatustable} oneWireStatus - Senser status information.
     * @property {blob}          data          - The response payload.
     */

    /**
     *
     * Decode an XBee Sensor Reading packet.
     * 
     * @param {blob} data - The response data.
     *
     * @returns {xsrresponse} The decoded response.
     *
     * @private
     */
    function _decodeXBeeSensorReadIndicator(data) {
        local decode = {};
        decode.cmdid <- data[3];
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

    /**
     * @typedef {table} dairesponse
     *
     * @property {integer}     cmdid        - The Command ID.
     * @property {string}      address64bit - The remote device's 64-bit address.
     * @property {integer}     address16bit - The remote device's 16-bit address.
     * @property {statustable} status       - Transaction status information.
     */

    /**
     *
     * Decode a Device Auth Indicator packet.
     * 
     * @param {blob} data - The response data.
     *
     * @returns {dairesponse} The decoded response.
     *
     * @private
     */
    function _decodeDeviceAuthIndicator(data) {
        local decode = {};
        decode.cmdid <- data[3];
        decode.address64bit <- _read64bitAddress(data, 4);
        decode.address16bit <- (data[12] << 8) + data[13];
        decode.status <- {};
        decode.status.code <- data[14];
        decode.status.message <- _getPacketStatus(data[14]);
        return decode;
    }

    /**
     *
     * Decode a Join Status Indicator packet.
     * 
     * @param {blob} data - The response data.
     *
     * @returns {dairesponse} The decoded response.
     *
     * @private
     */
    function _decodeJoinStatus(data) {
        local decode = {};
        decode.cmdid <- data[3];
        decode.address64bit <- _read64bitAddress(data, 4);
        decode.address16bit <- (data[12] << 8) + data[13];
        decode.status <- {};
        decode.status.code <- data[14];
        decode.status.message <- _getJoinStatus(data[14]);
        return decode;
    }

    // ********** Status Code Parsing Functions **********

    /**
     *
     * Generate a human-readable AT status message.
     * 
     * @param {integer} code - The status code.
     *
     * @returns {string} The status message.
     *
     * @private
     */
    function _getATStatus(code) {
        local m = [ "OK",
                    "ERROR",
                    "Invalid Command",
                    "Invalid Parameter",
                    "TX Failure"];
        return m[code];
    }

    /**
     *
     * Generate a human-readable modem status message.
     * 
     * @param {integer} code - The status code.
     *
     * @returns {string} The status message.
     *
     * @private
     */
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

    /**
     *
     * Generate a human-readable packet delivery status message.
     * 
     * @param {integer} code - The status code.
     *
     * @returns {string} The status message.
     *
     * @private
     */
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

    /**
     *
     * Generate a human-readable device discovery status message.
     * 
     * @param {integer} code - The status code.
     *
     * @returns {string} The status message.
     *
     * @private
     */
    function _getDiscoveryStatus(code) {
        local m = [ "No Discovery Overhead",
                    "Address Discovery",
                    "Route Discovery",
                    "Address and Route"];
        if (code < 0x04) return m[code];
        if (code == 0x40) return "Extended Timeout Discovery";
        return "Unknown";
    }

    /**
     *
     * Generate a human-readable packet TX status message.
     * 
     * @param {integer} code - The status code.
     *
     * @returns {string} The status message.
     *
     * @private
     */
    function _getPacketStatus(code) {
        local s = "";
        if (code == 0x00) s = "Packet Not Acknowledged; ";
        if (code & 0x01) s = s + "Packet Acknowledged; ";
        if (code & 0x02) s = s + "Packet a Broadcast Packet; ";
        if (code & 0x20) s = s + "Packet Encrypted with APS; ";
        if (code & 0x40) s = s + "Packet Sent By End-Device; ";
        s = s.slice(0, s.len() - 2);
        return s;
    }

    /**
     *
     * Generate a human-readable packet routing status message.
     * 
     * @param {integer} code - The status code.
     *
     * @returns {string} The status message.
     *
     * @private
     */
    function _getRouteStatus(code) {
        local m = ["Packet Acknowledged", "Packet was a Broadcast"];
        if (code < 0x01 || code > 0x02) return "Unknown Route Record status code";
        return m[code];
    }

    /**
     *
     * Generate a human-readable XBee 1-Wire sensor status message.
     * 
     * @param {integer} code - The status code.
     *
     * @returns {string} The status message.
     *
     * @private
     */
    function _getOneWireStatus(code) {
        local s = "";
        if (code & 0x01) s = s + "A/D Sensor Read; ";
        if (code & 0x02) s = s + "Temperature Sensor Read; ";
        if (code & 0x60) s = s + "Water Present; ";
        s = s.slice(0, s.len() - 2);
        return s;
    }

    /**
     *
     * Generate a human-readable network join status message.
     * 
     * @param {integer} code - The status code.
     *
     * @returns {string} The status message.
     *
     * @private
     */
    function _getJoinStatus(code) {
        local m = [0x00, "Standard security secured rejoin", 0x01, "Standard security unsecured join",
                   0x02, "Device left", 0x03, "Standard security unsecured rejoin",
                   0x04, "High security secured rejoin", 0x05, "High security unsecured join",
                   0x07, "High security unsecured rejoin"]
        for (local i  = 0 ; i < len(m) ; i+=2) {
            if (code == m[i]) return m[i + 1];
        }
        return "Unknown";
    }

    // ********** API Frame UART Reception Callback ************

    /**
     *
     * UART data reception handler (API Mode).
     *
     * @private
     */
    function _dataReceivedAPI() {
        // This callback is triggered on receipt of a single byte via UART
        local b = _uart.read();

        if (_enabled == false) {
            // Explicit value check made in case property set to non-bool
            _frameByteCount = 0;
            return;
        }
        
        if (b == 0x7E && _frameByteCount != 0 && _escapeFlag == false) {
            server.error("Malformed frame: new start marker detected; ignoring received data");
            _buffer = blob();
            _frameByteCount = 0;
            _frameSize = 0;
        }

        if (b == 0x7D && _escaped) {
            // De-escape the next character received
            _escapeFlag = true;
            return;
        }

        if (_escapeFlag) {
            _escapeFlag = false;
            b = b ^ 0x20;
        }

        _buffer.writen(b, 'b');
        _frameByteCount++;

        // Look for the data-size bytes
        if (_frameByteCount == 2) _frameSize = b << 8;
        if (_frameByteCount == 3) _frameSize = _frameSize + b + 4;

        // Callback returns if insufficient bytes to make up the whole frame have been received.
        // The frame data size is included in the frame; to this we add the top and tail bytes.
        // When we have enough bytes to indicate a whole frame has been received we process it
        if (_frameByteCount < 5 || _frameByteCount < _frameSize) return;

        // We now have a complete frame, clear the input buffer for immediate re-use
        // and then process the newly received frame
        local frame = _buffer;
        _buffer = blob();
        _frameByteCount = 0;
        _frameSize = 0;

        if (_debug) server.log("API Frame Received:  " + _listFrame(frame));

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
            case XBEE_CMD.AT_RESPONSE:
                _callback(null, _decodeATResponse(frame));
                break;

            case XBEE_CMD.MODEM_STATUS:
                _callback(null, _decodeModemStatus(frame));
                break;

            case XBEE_CMD.ZIGBEE_TRANSMIT_STATUS:
                _callback(null, _decodeZigbeeTransmitStatus(frame));
                break;

            case XBEE_CMD.ZIGBEE_RECEIVE_PACKET:
                _callback(null, _decodeZigbeeReceivePacket(frame));
                break;

            case XBEE_CMD.ZIGBEE_EXP_RX_INDICATOR:
                _callback(null, _decodeZigbeeRXIndicator(frame));
                break;

            case XBEE_CMD.ZIGBEE_IO_DATA_SAMPLE_RX_INDICATOR:
                _callback(null, _decodeZigbeeDataSampleRXIndicator(frame));
                break;

            case XBEE_CMD.XBEE_SENSOR_READ_INDICATOR:
                _callback(null, _decodeXBeeSensorReadIndicator(frame));
                break;

            case XBEE_CMD.NODE_ID_INDICATOR:
                _callback(null, _decodeNodeIDIndicator(frame));
                break;

            case XBEE_CMD.REMOTE_CMD_RESPONSE:
                _callback(null, _decodeRemoteATCommand(frame));
                break;

            case XBEE_CMD.ROUTE_RECORD_INDICATOR:
                _callback(null, _decodeRouteRecordIndicator(frame));
                break;

            case XBEE_CMD.DEVICE_AUTH_INDICATOR:
                _callback(null, _decodeDeviceAuthIndicator(frame));
                break;

            case XBEE_CMD.MANY_TO_ONE_ROUTE_REQ_INDICATOR:
                _callback(null, _decodeManyToOneRouteIndicator(frame));
                break;

            case XBEE_CMD.JOIN_NOTIFICATION_STATUS:
                _callback(null, _decodeJoinStatus(frame));
                break;

            default:
                // Unknown frame type - return an error to the host app
                _callback("Unknown frame type", null);
        }
    }

    // ********** AT / Transparent Mode Send and Receive Functions **********

    /**
     *
     * Put the XBee into Command Mode.
     *
     * @private
     */
    function _setCommandMode() {
        // If the XBee is disabled, do not perform the operation
        if (_enabled == false) return;
        
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

    /**
     *
     * UART data reception handler (AT Mode).
     *
     * @private
     */
    function _dataReceivedAT() {
        // Callback triggered on receipt of a byte
        local b = _uart.read();

        if (_enabled == false) {
            _buffer = blob();
            return;
        }
        
        if (b.tochar() != CR && b != -1) {
            // If we don't have a CR or EOL, store the byte
            _buffer.writen(b, 'b');
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
