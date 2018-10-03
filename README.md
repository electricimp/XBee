# XBee 2.0.0 #

This library provides support for Zigbee networking using Digi International’s [XBee ZB/ZB PRO Series 2 modules](http://www.digi.com/products/xbee-rf-solutions/rf-modules/xbee-zigbee).

It supports both Transparent Mode (aka AT Mode) and API Mode. Transparent Mode treats the XBee network as a serial bus, and the imp communicates with the local XBee module using simple AT commands.

API Mode involves communicating between imp and module using complex data structures called frames. Crucially, API Mode supports Zigbee functionality, including the ability to communicate with networked devices not made by Digi International. API Mode is the XBee class’ default mode.

Communicating with non-XBee Zigbee devices is made possible by the API Mode’s support for the transmission of Zigbee Device Profile and the Zigbee Cluster Library (ZCL). The latter allows the XBee to communicate with the clusters (sets of commands and attributes) defined in Zigbee profiles, whether public or private. The Zigbee Device Profile defines an endpoint, Zigbee Device Objects (SDO) which provides clusters for network management and discovery. The XBee library naturally supports the construction of ZDO and ZCL messages through the API, but it also provides a number of convenience methods for sending these complex interactions.

The XBee class is intended to be transparent to the application. It enables communication between your code and the Zigbee network but it is left to your application to manage, for example, matching a response to the request that prompted it. Your code passes the class a callback function and all responses, whether initiated by a request or by a network or device status messages, are passed into that callback. It is up to your application to handle these responses as appropriate.

For more information, please see Digi’s [XBee S2 Manual](http://www.digi.com/resources/documentation/digidocs/PDFs/90000976.pdf) (PDF). A second document, [‘Supporting ZDOs with the XBee API’](http://ftp1.digi.com/support/images/APP_NOTE_XBee_ZigBee_Device_Profile.pdf) (PDF), has more information on Zigbee Device Objects.

**To add this library to your project, add** `#require "xbee.device.lib.nut:2.0.0"` **to the top of your device code**

## Class Usage ##

### Constructor: XBee(*impSerial, callback[, apiMode][, escaped][, debug]*) ###

The XBee class constructor requires the imp **hardware.uart** object representing the serial bus on which the XBee module is connected to the imp. This bus should be unconfigured &mdash; the constructor initializes the bus for you, but see *init()*, below.

It also requires a callback function, detailed below, which will be called when information is returned to your application by the XBee module.

The remaining parameters are optional:

- *apiMode* allows you to indicate whether you wish to communicate with the XBee module using API mode (`true`) or the more basic ‘Transparent’ mode (`false`). This defaults to `true`.
- *escaped* allows you to indicate whether API frames should be escaped. This defaults to `true` but if you select Transparent mode rather than API mode, it will automatically be disabled.
- *debug* allows you to specify that you wish the XBee object to display addition debugging information which may be useful during development. This defaults to `false` (no debug messages).

#### Example ####

```squirrel
#require "xbee.class.nut:1.0.0"

xbee <- XBee(hardware.uart57, xBeeResponseHandler, true, true, true);
```

### The Callback Function ###

The function you must pass into the XBee constructor takes two parameters: *error* and *response*. If an error is encountered during the imp’s communication with its local XBee module and the wider XBee network, *error* will contain information about the problem. Otherwise it will be `null`.

The you are communicating with the XBee module using API mode, the value passed into *response* will depend upon the nature of the response being returned by the XBee module and this in turn depends upon the API frame that was sent to the device and which prompted this response. The structure of the data returned is discussed below with the appropriate API frame. Responses provided by the Xbee module in reponse to other events are discussed after that.

When communicating with the XBee module using Transparent mode, ie. by issuing AT commands, *response* will typically contain requested data returned as a string.

#### Example ####

```squirrel
function xBeeResponse(error, response) {
    if (error) {
        server.error(error);
        return;
    }

    local m = "";
    if ("frameid" in response) m = m + "Frame ID " + response.frameid + " response received.";
    if ("command" in response) m = m + " AT command " + response.command + ".";
    if ("cmdid" in response) m = m + " Frame type: " + format("0x%02x", response.cmdid);
    server.log(m);

    if ("status" in response) server.log("Status: " + response.status.message);

    if ("command" in response) {
        if (response.command == "HV") {
            server.log("I am an " + ((response.data[0] == 0x19) ? "XBee" : "XBee Pro") + " revision " + format("0x%02X", response.data[1]));
        }

        if (response.command == "VR") {
            if ("data" in response) server.log("My firmware version: " + format("0x%02X%02X", response.data[0], response.data[1]));
        }
    }

    if ("frameid" in response) {
        if (response.frameid == 0xFF) {
            // We chose this Frame ID to identify the reponse
            // Process the requested data...
        }
    }
}
```

## Class Methods ##

The public methods provided by the XBee library are subdivided by type:

- [General Methods](#class-methods-general)
- [API ‘Frame’ Mode Methods](#class-methods-api-mode)
    - [Other API Mode Responses](#other-api-mode-response-frames)
- [Advanced Zigbee Methods](#class-methods-advanced-zigbee)
- [AT/Transparent Mode Methods](#class-methods-at-mode)

## Class Methods: General ##

### init(*[baudrate][, flags]*) ###

The XBee class constructor configures the imp UART it will be using for you, but if you wish to customize the serial connection between imp and XBee module, call *init()* to do so.

It takes two, optional parameters: *baudrate* is the serial bus speed and should be one of the constants listed in the imp API UART documentation. *flags* is an integer bitfield of optional bus settings which, again, are described in the imp API UART documentation.

## Class Methods: API Mode ##

### sendLocalATCommand(*command[, parameterValue][, frameid]*) ###

This method creates and transmits an API frame embedding an AT command which is passed as a two-character string, eg.`"ND"` (Node Discovery), into the first parameter. The AT command is sent to the local XBee module; see *sendRemoteATCommand()* for sending commands to remote devices via the Zigbee network.

Some AT commands require a setting value to to be provided, such as a local XBee module setting, or the upper or lower 32-bit word of a remote device’s 64-bit address. Pass such integer values into the second, optional parameter, *parameterValue*, if this is required. 

**Note** Because Squirrel supports only 32-bit signed integers, parameter values greater than 2147483647 will be treated as negative values. *sendLocalATCommand()* treats negative parameter values as ‘no value supplied’ (the default value of the *parameterValue* parameter is -1). To pass in a higher unsigned value, eg 0xFFFFFFFF, pass the value as a hex string *(see examples, below)*.

The third parameter is also optional: it is an integer value between 1 and 255 which identifies the frame that will be sent. You can match this value against the frame ID returned by the XBee object to your callback function’s *response* parameter via the key *frameid*. Pass 0 into this parameter if you do not wish to receive a response. By default, the frame ID is chosen automatically. Whether you specify a frame ID or not, the ID of the generated frame is returned by the method.

#### Response ####

The *response* returned by a *sendLocalATCommand()* is a table with the following keys:

| Key | Value Data Type | Notes |
| --- | --- | --- |
| *cmdid* | Integer | The API response type, 0x88 |
| *frameid* | Integer | The source frame’s ID |
| *command* | String | The AT command sent by the source frame |
| *data* | Blob | Any data returned by the AT command, or `null` |
| *status* | Table | See below |

The *status* table contains two keys:

- *code* &mdash; An AT command-specific status code (integer)
- *message* &mdash; A human readable status message (string)

#### Examples ####

```squirrel
// Get the module's hardware type and revision
xbee.sendLocalATCommand("HV");

// Get the module's firmware version
xbee.sendLocalATCommand("VR");
```

```squirrel
// Set up remote End Device’s DI01 pin as a digital input...
xbee.sendRemoteATCommand("D1", "0x0013A20040D6A8CB", 0xFFFE, 0, 3, 200);

// ...with a periodic sample rate of 5s
xbee.sendRemoteATCommand("IR", "0x0013A20040D6A8CB", 0xFFFE, 0, 5000, 201);

// Tell the device to send its sample data to 64-bit address 0xFFFFFFFAFFFFFFFB
xbee.sendRemoteATCommand("DH", "0x0013A20040D6A8CB", 0xFFFE, 0, "0xFFFFFFFA", 202);
xbee.sendRemoteATCommand("DL", "0x0013A20040D6A8CB", 0xFFFE, 0, "0xFFFFFFFB", 203);
```

### sendQueuedATCommand(*command[, parameterValue][, frameid]*) ###

The method *sendLocalATCommand()* will cause the XBee module to apply the sent command immediately. If you wish to queue a number of commands before sending the AT command `"AC"` (Apply Changes) to apply then, use this method instead.

Its parameters match those of *sendLocalATCommand()* and it too returns the generated frame’s ID, whether you set it explicitly or allowed the code to do so.

#### Response ####

The *response* returned by a *sendQueuedATCommand()* matches that returned by *sendLocalATCommand()*, above.

### sendRemoteATCommand(*command, address64bit, address16bit[, options][, parameterValue][, id]*) ###

Use this method to transmit an AT command &mdash; again passed in as a two-character string &mdash; to a Zigbee network-connected remote XBee module. See the description of *sendLocalATCommand()* for details of the optional parameters *parameterValue* and *frameid*; the remaining parameters are discussed below.

*address64bit* and *address16bit* are mandatory and are the remote module’s two addresses. The first is hard-coded into the device and can be determined by sending the AT command `"ND"` (Node Discovery) locally, or by sending `"ID`" from the imp controlling the XBee module in question. Because Squirrel does not support 64-bit integers, the 64-bit address is passed in as a string of 16 hex digits representing the address’ eight octets.

The value of *address16bit* is set when the module joins the Zigbee network. This is a 16-bit value so is passed in as an integer. If the device’s 16-bit address is not known, pass in the value 0xFFFE, but you must provide the correct 64-bit address.

The Zigbee network’s Coordinator module can always be reached at the 64-bit address `0x0000000000000000`. To broadcast the specified AT command to all devices on the network, pass in the 64-bit address `0x000000000000FFFF`. In each case the "0x" hex indicator is optional.

The *options* parameter is optional. It is an integer bitfield of settings that can be used to customize the action performed by the remote XBee module. Please see Digi’s XBee documentation for details.

Whether you specify a frame ID or not, the ID of the generated frame is returned by the method.

#### Response ####

The *response* returned by a *sendRemoteATCommand()* is a table with the following keys:

| Key | Value Data Type | Notes |
| --- | --- | --- |
| *cmdid* | Integer | The API response type, 0x97 |
| *frameid* | Integer | The source frame’s ID |
| *command* | String | The AT command sent by the source frame |
| *address64bit* | String | The 64-bit address of the remote module in hex form |
| *address16bit* | Integer | The 16-bit address of the remote module |
| *data* | Blob | Any data returned by the AT command, or `null` |
| *status* | Table | See below |

The *status* table contains two keys:

- *code* &mdash; An AT command-specific status code (integer)
- *message* &mdash; A human readable status message (string)

#### Example ####

```squirrel
// Ask a remote device for its firmware version
xbee.sendRemoteATCommand("VR", "0x13A20040DD30DB", 0xFFFE);

// Ask all nodes for their hardware types and revisions
xbee.sendRemoteATCommand("VR", "`0x000000000000FFFF`", 0xFFFE);
```

### sendZigbeeRequest(*address64bit, address16bit, data[, radius][, options][, frameid]*) ###

This method is used to data to a remote XBee module which is specified by passing in its 64-bit address and/or 16-bit address, as described under *sendRemoteATCommand()*.

The additional parameters provided by this method are *data*, which is a blob containing the byte-level data you wish to send (your application code will need to serialize the information you need to send into a blob), and *radius*, an optional value which sets the number of broadcast hops. This defaults to 0, which enforces maximum network coverage. The number of hops is set using the AT command "NH".

The *options* parameter, which is optional, is an integer bitfield used to customize the transmission. The following values can be combined and passed in:

- 0x01 &mdash; Disable retries and route repair
- 0x20 &mdash; Enable APS encryption (must have already sent the AT command "EE")
- 0x40 &mdash; Use extended transmission timeout (to support sleeping End Devices)

Whether you specify a frame ID or not, the ID of the generated frame is returned by the method.

#### Response ####

The *response* returned by a *sendZigbeeRequest()* is a table with the following keys:

| Key | Value Data Type | Notes |
| --- | --- | --- |
| *cmdid* | Integer | The API response type, 0x90 |
| *frameid* | Integer | The source frame’s ID |
| *command* | String | The AT command sent by the source frame |
| *address64bit* | String | The 64-bit address of the remote module in hex form |
| *address16bit* | Integer | The 16-bit address of the remote module |
| *data* | Blob | The data sent by the remote module, or `null` |
| *status* | Table | See below |

The *status* table contains two keys:

- *code* &mdash; An Zigbee request status code (integer)
- *message* &mdash; A human readable status message (string)

#### Example ####

```squirrel
// Read the temperature from the MCP9808 sensor
local t = mcp9808.readTempCelsius();

// Write the data into a blob...
local data = blob();

// ...first, the temperature as a float...
data.writen(t, 'f');

// ...then the current timestamp as an integer
data.writen(time(), 'i');

// Send the data to the Coordinator
xbee.sendZigbeeRequest("0x00", 0xFFFE, data);
```

### sendExplicitZigbeeRequest(*address64bit, address16bit, sourceEndpoint, destEndpoint, clusterID, profileID, data[, radius][, options][, frameid]*) ###

This method extends *sendZigbeeRequest()* with Zigbee application layer fields. In addition to the parameters detailed under *sendZigbeeRequest()*, this method takes *sourceEndpoint*, *destEndpoint*, *clusterID* and *profileID*. All of these are integer values (the endpoints are 8-bit values, the IDs are 16-bit values) and will be determined by your Zigbee application.

Whether you specify a frame ID or not, the ID of the generated frame is returned by the method.

#### Response ####

The *response* is a table with the following keys:

| Key | Value Data Type | Notes |
| --- | --- | --- |
| *cmdid* | Integer | The API response type, 0x91 |
| *frameid* | Integer | The source frame’s ID |
| *address16bit* | Integer | The 16-bit address of the sender |
| *address64bit* | String | The 64-bit address of the sender |
| *sourceEndpoint* | Integer | The endpoint of the source that initiated the transmission |
| *destEndpoint* | Integer | The endpoint of the destination the message is addressed to |
| *clusterID* | Integer | The cluster ID the packet was addressed to |
| *profileID* | Integer | The profile ID the packet was addressed to |
| *data* | Blob | Data received, or `null` |
| *status* | Table | See below |

The *status* table contains two keys:

- *code* &mdash; An RX status code (integer)
- *message* &mdash; A human readable status message (string)

### createSourceRoute(*command, address64bit, address16bit, addresses[, frameid]*) ###

This method creates a Zigbee source route in the module. A source route specifies the complete route a packet should traverse to get from source to destination, and is intended to be used with many-to-one routing.

Please see *sendZigbeeRequest()* for a discussion of the methods parameters other than the following: *addresses*. This is an array of integers, each a 16-bit address of an intermediate module (ie. neither source nor destination) in the route. Intermediate hop addresses **must** be ordered starting with the neighbor of the destination, and working closer to the source.

Whether you specify a frame ID or not, the ID of the generated frame is returned by the method.

## Other API Mode Response Frames ##

In addition to the responses returned when AT commands are sent to local and remote XBee modules, and Zigbee commands are issued, a number of other responses may be returned to the callback function you pass into the XBee constructor. The data provided by these responses is detailed below.

### Modem Status ###

This provides XBee module status information. The *response* is a table with the following keys:

| Key | Value Data Type | Notes |
| --- | --- | --- |
| *cmdid* | Integer | The API response type, 0x8A |
| *status* | Table | See below |

The *status* table contains two keys:

- *code* &mdash; A modem status code (integer)
- *message* &mdash; A human readable status message (string)

**Note** No frame ID is included.

### Zigbee Transmit Status ###

This provides Zigbee transmission status information. The *response* is a table with the following keys:

| Key | Value Data Type | Notes |
| --- | --- | --- |
| *cmdid* | Integer | The API response type, 0x8B |
| *frameid* | Integer | The source frame’s ID |
| *address16bit* | Integer | The 16-bit address the packet was delivered to (if successful). If not successful, this address will be 0xFFFD |
| *transmitRetryCount* | Integer | The number of application transmission retries that took place |
| *deliveryStatus* | Table | See below |
| *discoveryStatus* | Table | See below |

The *deliveryStatus* and *discoveryStatus* each tables contain two keys:

- *code* &mdash; A transmission status code (integer)
- *message* &mdash; A human readable status message (string)

### Zigbee IO Data Sample RX Indicator ###

This packet contains data sampled by the one of a remote module’s IO pins. The *response* is a table with the following keys:

| Key | Value Data Type | Notes |
| --- | --- | --- |
| *cmdid* | Integer | The API response type, 0x8B |
| *frameid* | Integer | The source frame’s ID |
| *address16bit* | Integer | The 16-bit address of the sender |
| *address64bit* | String | The 64-bit address of the sender |
| *numberOfSamples* | Integer | The number of data samples in the packet (always 1) |
| *digitalMask* | Integer | A 16-bit bitfield where each bit represents a module IO pin; if a bit is set, that pin has a digital sample |
| *digitalSamples* | Integer | A 16-bit bitfield where each bit represents the state of an IO pin at sample time. Only bits whose equivalent bit in *digitalMask* is set should be read |
| *analogMask* | Integer | An 8-bit bitfield where each bit represents a module IO pin; if a bit is set, that pin has an analog sample |
| *analogSamples* | Array | An array of integers corresponding to the analog values sampled from the module’s analog pins. For pins not sampled, the array will contain the value -1 |
| *status* | Table | See below |

The *deliveryStatus* and *discoveryStatus* each tables contain two keys:

- *code* &mdash; A transmission status code (integer)
- *message* &mdash; A human readable status message (string)

### Zigbee Route Record ###

This provides Zigbee module routing information and follows the receipt of a Zigbee packet *(see above)*. The *response* is a table with the following keys:

| Key | Value Data Type | Notes |
| --- | --- | --- |
| *frameid* | Integer | The source frame’s ID |
| *cmdid* | Integer | The API response type, 0xA1 |
| *address16bit* | Integer | The 16-bit address of the device that initiated the route record |
| *address64bit* | String | The 64-bit address of the device that initiated the route record |
| *addresses* | Array of Integers | The intermediate module addresses in the route |
| *status* | Table | See below |

The *status* table contains two keys:

- *code* &mdash; A route record status code (integer)
- *message* &mdash; A human readable status message (string)

### Zigbee Many-to-One Route Record ###

This provides Zigbee module routing information and follows the receipt of a Zigbee packet *(see above)*. The *response* is a table with the following keys:

| Key | Value Data Type | Notes |
| --- | --- | --- |
| *cmdid* | Integer | The API response type, 0xA3 |
| *frameid* | Integer | The source frame’s ID |
| *address16bit* | Integer | The 16-bit address of the device that initiated the many-to-one route request |
| *address64bit* | String | The 64-bit address of the device that sent the many-to-one route request |

## Class Methods: Advanced Zigbee ##

### enterZDOMode() ###

This convenience method is used to prepare the local XBee module for Zigbee Device Objects (ZDO) and the Zigbee Cluster Library (ZCL) operation. Essentially, it uses an AT command to return explicit receipt data via the UART, a requirement for correctly making use of ZDO and ZCL. It also confirms that you are operating in API mode.

### exitZDOMode() ###

This method returns the local XBee module to ‘standard’ API mode.

### sendZDO(*address64bit, address16bit, clusterID, ZDOpayload[, transaction][, frameid]*) ###

This convenience method provides an easy way to send ZDO commands to the specified remote device using its 64-bit and/or 16-bit address. The Zigbee network’s Coordinator module can always be reached at the 64-bit address `0x0000000000000000`. To broadcast to all devices on the network, pass in the 64-bit address `0x000000000000FFFF`. The value passed into *clusterID* identifies the ZDO cluster (eg. `0x0030` for the Management Network Discovery Request), while *transaction* is the Zigbee transaction sequence number, an unsigned 8-bit value (0-255) used to identify the transaction (akin but not necessarily equal to the frame ID); it is used to match response to request and is optional.

*ZDOpayload* is a blob containing the data to be sent to the remote module(s); the method adds the transaction sequence number to the payload before sending it to the local module for transmission.

**Note** in ZDO mode, multi-byte data must be sent (and received data decoded) in little-endian order, ie. the least significant byte comes first, the most significant byte last. This is counter to the byte order in API frame communications.

If no value is passed into *transaction*, a transaction sequence number will be generated for you. *sendZDO()* returns a table with two keys, *transaction* and *frameID*, which are the values you passed into the function or those generated by the method itself.

### sendZCL(*address64bit, address16bit, sourceEndpoint, destinationEndpoint, clusterID, profileID, ZCLframe[, radius][, frameid]*) ###

This convenience method provides an easy way to send ZCL commands and/or attributes to the specified remote device using its 64-bit and/or 16-bit address. The Zigbee network’s Coordinator module can always be reached at the 64-bit address `0x0000000000000000`. To broadcast to all devices on the network, pass in the 64-bit address `0x000000000000FFFF`. In addition, you will need to pass in source and destination endpoints, which identify the sending and receiving applications on the module (both are zero for ZDO). The value passed into *clusterIO* identifies the ZDO cluster; the value of *profileID* identifies the profile (zero for ZDO; 0xC05E for the standard Light Link Profile).

*ZCLframe* is a blob containing the data to be sent to the remote module(s). This will be cluster specific, so it is left to your application code to construct. As the Zigbee transaction sequence number is embedded in this frame, it is left to your code to supply this value (unlike *sendZDO()*). *sendZCL()* returns a table with two keys, *transaction* and *frameID*, which are the values you passed into the function or those generated by the method itself (in the case of the API frame ID).

**Note** in ZDO mode, multi-byte data must be sent (and received data decoded) in little-endian order, ie. the least significant byte comes first, the most significant byte last. This is counter to the byte order in API frame communications.

## Class Methods: AT Mode ##

### sendCommand(*command[, parameterValue]*) ###

This method requires an AT command represented as a two-character string, eg.`"ND"` (Node Discovery) and also takes an optional integer parameter value, if required by the command.

In AT Mode, the XBee module must be placed in command mode in order to receive AT commands; *sendCommand()* does this for you. Command mode can be closed by sending the AT command `"CN"` (Exit Command Mode) or by allowing the command mode timeout to pass. The command mode timeout is set using the AT command `"CT"` followed by the duration in seconds (0-255), then activated by sending `"AC"` (Apply Changes).

#### Example ####

```squirrel
// Set command mode timeout to 60s...
xbee.sendCommand("CT", 60);

// ...and apply the change
xbee.sendCommand("AC");

// Request the XBee module's firmware version
xbee.sendCommand("VR");
```

For a full list of available AT commands, please see Digi’s [XBee S2 Manual](http://www.digi.com/resources/documentation/digidocs/PDFs/90000976.pdf) (PDF).
