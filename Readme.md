<h1>Longmynd utilities</h1>

Collection of scripts to manage Minitiouner with [F5OEO Longmynd software](https://github.com/F5OEO/longmynd) and Pluto with [F5OEO Pluto DVB2 firmware](https://github.com/F5OEO/plutosdr-fw). Scripts are based on mosquitto client utility programs `mosquitto_sub` and `mosquitto_pub` so the corresponding package has to be installed. For Debian/Ubuntu:

<pre>
sudo apt install mosquitto-clients
</pre>

F5OEO's Longmynd version hooks to the Pluto MQTT broker so the Longmynd's topics are accesible from the same address/port as the Pluto MQTT topics. Usually at Pluto's address and 1883 port.

<h2>longmynd.sh</h2>

Simple script to set Minitiouner frequency and optionally the symbol rate

Usage:
<pre>
longmynd.sh 741500 1500
# or
longmynd.sh 741500
</pre>

You have to edit the script to customize it to your environment values are given as an example

<pre>
# configuration
key="F4EXB"         # Pluto DVB2 Callsign
host="192.168.0.37" # Pluto address
</pre>

<h2>repeater.sh</h2>

Controls Pluto and Minitiouner in a DATV repeater configuration. This is built upon F5OEO's [relay.sh](https://github.com/F5OEO/pluto-ori-ps/blob/c8a47400b86018a970c0df6e3825a9a99c7d4622/relay.sh) script. You have to have `bash` installed in your system.

When run as a service you have to set the `SERVICE_MODE` environment variable.

You have to customize the configuration to suit your installation. You either edit the script (non service mode) or edit `/etc/systemd/service/longmynd-repeater.conf` file in service mode.

Values are given as an example:

<pre>
key="F4EXB"                   # Pluto DVB2 Callsign
host="192.168.0.37"           # Pluto address
input_frequency="741500"      # Longmynd is in kHz
output_frequency="2372000000" # Pluto is in Hz
ts_ip=${host}                 # Longmynd transport stream target IP address
ts_port="1234"                # Longmynd transport stream target port
symbol_rates="1500 125 250 333 500 1000" # symbol rates to scan in kSps
trylock_init=2                # number of 1 second tries to lock to a SR initially
trylock_next=10               # number of 1 second tries to lock after initial lock
gpio_pin1="17"                # first GPIO pin number on RPi to use for lock indication (BCM numbering)
gpio_delay_on1="0.1"          # first GPIO on delay in seconds (e.g., 0.1 = 100ms)
gpio_delay_off1="0.1"         # first GPIO off delay in seconds (e.g., 0.1 = 100ms)
gpio_pin2="0"                 # Second GPIO pin number (0 to disable)
gpio_delay_on2="0.1"          # Second GPIO on delay in seconds
gpio_delay_off2="0.1"         # Second GPIO off delay in seconds
gpio_chip="gpiochip0"         # GPIO chip device name (see: gpioinfo)
</pre>

In particular the `symbol_rates` variable sets the symbol rate values scanned in the given order

In the `services` folder you can find unit and configuration files examples to run `longmynd` and `longmynd-repeater` services:

  - `longmynd.service`: run the longmynd program as a service. Goes in `/etc/systemd/system`.
  - `longmynd-repeater.service`: run the repeater.sh script as a service. Goes in `/etc/systemd/system`.
  - `longmynd-repeater.conf`: configuration file example. Goes in `/etc/systemd/system`.

Once you have copied and edited the files to suit your installation do:

<pre>
sudo systemctl daemon-reload
sudo systemctl start longmynd
sudo systemctl start longmynd-repeater
</pre>

As usual with `systemd` you can control the service with the `start`, `stop` and `restart` commands. You can check the service status with the `status` command.

To check the logs (example with `longmynd` service):

<pre>
journalctl -xu longmynd   # Full log
journalctl -u longmynd -f # Follow-up mode
</pre>

<h3>GPIO control</h3>

This works in the context of the script running on a Raspberry-Pi

You have to install the gpiod package first: `sudo apt install gpiod`

`gpio_chip` is the chip parameter returned by the command `sudo gpioinfo` for which the "GPIO" lines are available. For example:

```
sudo gpioinfo
gpiochip0 - 58 lines:
        line   0:     "ID_SDA"       unused   input  active-high
        line   1:     "ID_SCL"       unused   input  active-high
        line   2:      "GPIO2"       unused   input  active-high
        line   3:      "GPIO3"       unused   input  active-high
        line   4:      "GPIO4"       unused   input  active-high
        line   5:      "GPIO5"       unused   input  active-high
        line   6:      "GPIO6"       unused   input  active-high
        line   7:      "GPIO7"   "spi0 CS1"  output   active-low [used]
        line   8:      "GPIO8"   "spi0 CS0"  output   active-low [used]
        line   9:      "GPIO9"       unused   input  active-high
        line  10:     "GPIO10"       unused   input  active-high
...
```

`gpio_pin1` and `gpio_pin2` are optional. They act as two independent PTT controls with delays.

A GPIO number "0" disables the GPIO control.

When an active GPIO is specified the corresponding on and off delays must be specified. A delay of 0 means immediate action.
