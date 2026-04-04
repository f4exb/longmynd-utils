#!/bin/bash
# DATV repeater for Longmynd to PlutoSDR
# sudo apt install mosquitto-clients

if [ -z $SERVICE_MODE ]; then
    echo "Starting Longmynd to PlutoSDR repeater script in interactive mode"
    # configuration
    key="F4EXB"                   # Pluto DVB2 Callsign
    host="192.168.0.37"           # Pluto address
    input_frequency="741500"      # Longmynd is in kHz
    output_frequency="2372000000" # Pluto is in Hz
    power_db="-10"                # Pluto output power in dB vs max power
    ts_ip=${host}                 # Longmynd transport stream target IP address
    ts_port="1234"                # Longmynd transport stream target port
    symbol_rates="1500 125 250 333 500 1000" # symbol rates to scan in kSps
    trylock_init=2                # number of 1 second tries to lock to a SR initially
    trylock_next=10               # number of 1 second tries to lock after initial lock
    gpio_pin1="17"                # first GPIO pin number for Tx indicator (0 to disable)
    gpio_delay_on1="0.1"          # first GPIO on delay in seconds (e.g., 0.1 = 100ms)
    gpio_delay_off1="0.1"         # first GPIO off delay in seconds (e.g., 0.1 = 100ms)
    gpio_pin2="0"                 # second GPIO pin number (0 to disable)
    gpio_delay_on2="0.1"          # second GPIO on delay in seconds
    gpio_delay_off2="0.1"         # second GPIO off delay in seconds
else
    echo "Starting Longmynd to PlutoSDR repeater script in service mode"
    # configuration is loaded from file /etc/systemd/system/longmynd-repeater.conf
    source /etc/systemd/system/longmynd-repeater.conf
fi

# MQTT topics
dt_longmynd="dt/longmynd"
cmd_longmynd="cmd/longmynd"
cmd_root="cmd/pluto/$key"
dt_relay="dt/pluto/$key/relay"
cmd_relay="cmd/pluto/$key/relay"

# Initialize GPIO if enabled
if [ -n "$gpio_pin1" ] && [ "$gpio_pin1" -gt 0 ]; then
    if [ ! -d "/sys/class/gpio/gpio${gpio_pin1}" ]; then
        echo "$gpio_pin1" > /sys/class/gpio/export 2>/dev/null
        sleep 0.1
    fi
    if [ -d "/sys/class/gpio/gpio${gpio_pin1}" ]; then
        echo "out" > /sys/class/gpio/gpio${gpio_pin1}/direction
        echo "0" > /sys/class/gpio/gpio${gpio_pin1}/value
        echo "GPIO pin ${gpio_pin1} initialized"
    else
        echo "Warning: GPIO pin ${gpio_pin1} could not be exported, disabling"
        gpio_pin1="0"
    fi
fi

# Initialize second GPIO if enabled
if [ -n "$gpio_pin2" ] && [ "$gpio_pin2" -gt 0 ]; then
    if [ ! -d "/sys/class/gpio/gpio${gpio_pin2}" ]; then
        echo "$gpio_pin2" > /sys/class/gpio/export 2>/dev/null
        sleep 0.1
    fi
    if [ -d "/sys/class/gpio/gpio${gpio_pin2}" ]; then
        echo "out" > /sys/class/gpio/gpio${gpio_pin2}/direction
        echo "0" > /sys/class/gpio/gpio${gpio_pin2}/value
        echo "GPIO pin ${gpio_pin2} initialized"
    else
        echo "Warning: GPIO pin ${gpio_pin2} could not be exported, disabling"
        gpio_pin2="0"
    fi
fi

mosquittoPub() {
  mosquitto_pub -h ${host} ${@}
}

mosquittoSub() {
  mosquitto_sub -h ${host} ${@}
}

echo_over()
{
    if [ -z "$SERVICE_MODE" ]; then
        tput cr; tput el; echo -n "$1"
    fi
}

echo_nservice()
{
    if [ -z "$SERVICE_MODE" ]; then
        echo "$1"
    fi
}

echo_service()
{
    if [ -n "$SERVICE_MODE" ]; then
        echo "$1"
    fi
}

waitlock()
{
    modulation=$(mosquittoSub -t $dt_longmynd/modulation -C 1)
    loops=0

    while [ "$modulation" != "none" ]
    do
        sleep 0.1
        mer=$(mosquittoSub -t $dt_longmynd/mer -C 1)
        fec=$(mosquittoSub -t $dt_longmynd/fec -C 1)
        sr=$(mosquittoSub -t $dt_longmynd/symbolrate -C 1)
        frequency=$(mosquittoSub -t $dt_longmynd/carrier_frequency -C 1)
        station=$(mosquittoSub -t $dt_longmynd/service_name -C 1)
        station=$(echo $station | sed 's/ /_/g')
        modulation=$(mosquittoSub -t $dt_longmynd/modulation -C 1)

        if [ -z "$station" ]; then
            station="unknown"
        fi
        if [ -z "$mer" ]; then
            mer="0"
        fi
        if [ -z "$fec" ]; then
            fec="none"
        fi
        if [ -z "$sr" ]; then
            sr="0"
        fi
        if [ -z "$frequency" ]; then
            frequency="0"
        fi
        if [ -z "$modulation" ]; then
            modulation="none"
        fi

        $(mosquittoPub -t $dt_relay/status -m "lock")
        $(mosquittoPub -t $dt_relay/station -m $station)
        $(mosquittoPub -t $dt_relay/mer -m $mer)

        if [ $loops -eq 0 ]
        then
            echo "locked freq ${frequency} kHz sr ${sr} kSps mod ${modulation} fec ${fec} station ${station} mer ${mer} dB"
        fi

        echo_over "locked $station with mer $mer"

        $(mosquittoPub -t $cmd_root/tx/mute -m 0)
        # Set first GPIO pin high when Tx is unmuted (asynchronous with delay)
        if [ -n "$gpio_pin1" ] && [ "$gpio_pin1" -gt 0 ]; then
            (sleep "$gpio_delay_on1"; echo "1" > /sys/class/gpio/gpio${gpio_pin1}/value) &
        fi
        # Set second GPIO pin high when Tx is unmuted (asynchronous with delay)
        if [ -n "$gpio_pin2" ] && [ "$gpio_pin2" -gt 0 ]; then
            (sleep "$gpio_delay_on2"; echo "1" > /sys/class/gpio/gpio${gpio_pin2}/value) &
        fi
        $(mosquittoPub -t $cmd_root/tx/dvbs2/sdt -m $station"-via-")

        if [ "$fecmode" == "follow" ] && [ "$fec" != "none" ]
        then
            $(mosquittoPub -t $cmd_root/tx/dvbs2/fec -m $fec)
        fi

        modulation=$(mosquittoSub -t $dt_longmynd/modulation -C 1)
        loops=$((loops+1))
    done

    echo_nservice
    echo "unlocked"
    $(mosquittoPub -t $cmd_root/tx/mute -m 1)
    # Set first GPIO pin low when Tx is muted (asynchronous with delay)
    if [ -n "$gpio_pin1" ] && [ "$gpio_pin1" -gt 0 ]; then
        (sleep "$gpio_delay_off1"; echo "0" > /sys/class/gpio/gpio${gpio_pin1}/value) &
    fi
    # Set second GPIO pin low when Tx is muted (asynchronous with delay)
    if [ -n "$gpio_pin2" ] && [ "$gpio_pin2" -gt 0 ]; then
        (sleep "$gpio_delay_off2"; echo "0" > /sys/class/gpio/gpio${gpio_pin2}/value) &
    fi
}

trylock()
{
    ntries=$trylock_init
    iter=$trylock_init
    while [ $iter -gt 0 ]
    do
        modulation=$(mosquittoSub -t $dt_longmynd/modulation -C 1)

        if [ "$modulation" != "none" ] ; then
            echo_nservice
            ntries=$trylock_next
            iter=$trylock_next
            waitlock
            sleep 1
        fi
        iter=$((iter-1))
        echo_over "lock tries left ${iter} / ${ntries}"
    done
    echo_nservice
}

scan()
{
    for sr in ${symbol_rates}
    do
        echo_nservice "scan $sr kSps"
        $(mosquittoPub -t ${cmd_longmynd}/sr -m $sr)
        $(mosquittoPub -t ${dt_relay}/status -m "scan_${sr}")
        srfull=""$sr"000"
        $(mosquittoPub -t $cmd_root/tx/dvbs2/sr -m $srfull)
        trylock
    done
}

inputfrequency()
{
    while :
    do
        frequency=$(mosquittoSub -t $cmdrelay/infrequency -C 1)
        echo "$frequency relay"
        $(mosquittoPub -t $dtrelay/infrequency -m $frequency)
        $(mosquittoPub -t cmd/longmynd/frequency -m $frequency)
    done

}

FecMode()
{
    while :
    do
        fecmode=$(mosquittoSub -t $cmdrelay/fecmode -C 1)
        if [ "$fecmode" == "follow" ]
        then
            $(mosquittoPub -t $cmd_root/tx/dvbs2/fecmode -m fixed)
        else
            $(mosquittoPub -t $cmd_root/tx/dvbs2/fec -m 1/4)
            $(mosquittoPub -t $cmd_root/tx/dvbs2/fecmode -m variable)
        fi
    done
}

exit_script() {
    echo "Exiting..."
    trap - SIGINT SIGTERM # clear the trap
	$(mosquittoPub -t $cmd_root/tx/mute -m 1)
    kill -- -$$ # Sends SIGTERM to child/sub processes
}

wait_mqtt()
{
    mosquittoSub -t $dt_longmynd/modulation -C 1
    while [ $? -ne 0 ]
    do
        mosquittoSub -t $dt_pluto/modulation -C 1
    done
}

init()
{
    $(mosquittoPub -t $cmd_root/tx/mute -m 1)
    $(mosquittoPub -t $cmd_root/tx/gain -m ${power_db})
    $(mosquittoPub -t $cmd_root/tx/frequency -m ${output_frequency})
    $(mosquittoPub -t $cmd_root/tx/stream/mode -m dvbs2-ts)
    $(mosquittoPub -t $cmd_root/tx/dvbs2/tssourceaddress -m ${ts_ip}:${ts_port})
    $(mosquittoPub -t $cmd_relay/fecmode -m follow)
    $(mosquittoPub -t $cmd_longmynd/frequency -m ${input_frequency})
    $(mosquittoPub -t $cmd_longmynd/swport -m 0)
    $(mosquittoPub -t $cmd_longmynd/tsip -m ${ts_ip})
}

trap exit_script SIGINT SIGTERM
fecmode=follow
FecMode &
inputfrequency &

wait_mqtt
init
while :
do
    scan
done
