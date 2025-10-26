#!/bin/sh
# Longmyund configuration script for PlutoSDR
# sudo apt install mosquitto-clients

# configuration
key="F4EXB"         # Pluto DVB2 Callsign
host="192.168.0.37" # Pluto address

# MQTT topics
dt_longmynd="dt/longmynd"
cmd_longmynd="cmd/longmynd"
cmd_root="cmd/pluto/$key"
dtrelay="dt/pluto/$key/relay"
cmdrelay="cmd/pluto/$key/relay"

mosquittoPub() {
  mosquitto_pub -h ${host} ${@}
}

mosquittoPub -t "${cmd_longmynd}/frequency" -m "${1}"

if [ -n "${2}" ]; then
  mosquittoPub -t "${cmd_longmynd}/sr" -m "${2}"
fi
