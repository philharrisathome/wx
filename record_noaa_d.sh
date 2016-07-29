#!/bin/bash
# See /usr/local/bin/wxctl for client

# Expect commands through this fifo
CMD_FIFO=/tmp/record_noaa_cmd

# Cleanup on exit
function on_exit {
  echo "Cleaning up..."
  pkill --signal SIGINT rtl_fm
  rm -f $CMD_FIFO
  exit
}

# Ensure clean up on signal
trap on_exit SIGHUP SIGINT SIGTERM

# Create new command fifo
rm -f $CMD_FIFO
mkfifo $CMD_FIFO

# Setup audio environment for sox
#export AUDIODRIVER=pulseaudio		# Use PulseAudio driver
#unset AUDIODEV						# Use default PulseAudio device
export AUDIODRIVER=alsa				# Use ALSA driver
export AUDIODEV=hw:Loopback,0,0		# Use ALSA loopback (output will be on hw:Loopback,0,1)
#export AUDIODEV=hw:1,0,0			# Use built-in audio port
#export AUDIODEV=hw:2,0,0			# Use USB soundcard

# Resampler parameters
EFFECTS="rate 11025"
RATE=48k				# Need to be much higher than maximum deviation to avoid aliasing

# Main loop
echo "Waiting..."
while true; do
  if read line <$CMD_FIFO; then
    params=($line)

    # Look for start command (e.g. start noaa15 137.620M)
    if [[ "${params[0]}" == 'start' ]]; then
      echo "`date`: Seen start: "$line
      FILENAME="/home/pi/wx/"$(date +"%Y%m%d%H%M%S")".wav"
      FILENAME_RAW="/home/pi/wx/"$(date +"%Y%m%d%H%M%S")".raw"
      COMMENT=${params[1]}_$(date +"%Y%^b%d-%H%M%S%Z")
      echo "Recording: "$FILENAME
      rtl_fm -M fm -f "${params[2]}" -s $RATE -g 50 | (sox -V0 -r $RATE -t raw -e s -b 16 -c 1 - -V0 --comment $COMMENT $FILENAME $EFFECTS) &

    # Look for stop command (e.g. stop)
    elif [[ "${params[0]}" == 'stop' ]]; then
      echo "`date`: Seen stop: "$line
      pkill --signal SIGINT rtl_fm

    # Look for quit command (e.g. quit)
    elif [[ "${params[0]}" == 'quit' ]]; then
      echo "`date`: Seen quit: "$line
      break

    # Invalid command
    else
      echo "`date`: Invalid command: "$line
    fi

  fi
done

# Clean up before exiting
on_exit

