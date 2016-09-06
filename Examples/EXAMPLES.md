# XBee Examples

This directory contains a number of examples that demonstrate how the Electric Imp XBee library may be applied. In each case, the code is intended to be run on an imp connected to the XBee module operating as the Zigbee network’s co-ordinator. One or more remote XBee modules provide the data.

## sensor.device.nut

This simple application configures a remote XBee to sample data on its D1 pin. The sample may be digital or analog &mdash; line 68 sends the AT command "D1" to configure the pin; the parameter value 2 sets D1 as analogue input, or 3 for a digital input.

The subsequent lines set the IO sample rate ("IR"), then the top 32-bits and low 32-bits of the destination module’s 64-bit address. In this case, we pass in the address 0x0000000000000000 &mdash; the shortcut to the co-ordinator. Finally, we send "AC" to apply the settings.

The code will log any issues encountered in this process. For example, a TX failure implies you have entered an incorrect 64-bit address for the sensor module, or it is powered down.

The code should log that the sensor module has been configured and begin logging receieved data every five seconds (the set sample rate). Set the global variable *debug* to `true` to receive further messages.

## enumerate.device.nut

This example runs uses various AT commands &mdash; "OI" (Operating 16-bit PAN ID), "ND" (Node Discovery) and "MP" (16-bit Parent Network Address) &mdash; to discover and list all the XBee modules on the local Zigbee network.

![](example01.png)

Set the global variable *debug* to `true` to receive further messages.

## zdo.device.nut


