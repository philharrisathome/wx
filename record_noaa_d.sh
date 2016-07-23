#!/bin/bash
# See /usr/local/bin/wxctl for client

# Expect commands through this fifo
CMD_FIFO=/tmp/record_noaa_cmd

# Audio will be resampled through this pipe
AUDIO_PIPE=/tmp/record_noaa_audio.$RANDOM

# Cleanup on exit
function on_exit {
  echo "Cleaning up..."
  pkill --signal SIGINT rtl_fm
  exec 3>&-				# Allow audio pipe to close
  rm -f $AUDIO_PIPE
  rm -f $CMD_FIFO
  exit
}

# Ensure clean up on signal
trap on_exit SIGHUP SIGINT SIGTERM

# Create new command fifo
rm -f $CMD_FIFO
mkfifo $CMD_FIFO

# Create new audio pipe 
rm -f $AUDIO_PIPE
mkfifo $AUDIO_PIPE

# Setup audio environment for sox
#export AUDIODRIVER=pulseaudio		# Use PulseAudio driver
#unset AUDIODEV						# Use default PulseAudio device
export AUDIODRIVER=alsa			# Use ALSA driver
export AUDIODEV=hw:Loopback,0,0	# Use ALSA loopback (output will be on hw:Loopback,0,1)
#export AUDIODEV=hw:1,0,0			# Use built-in audio port
#export AUDIODEV=hw:2,0,0			# Use USB soundcard

# Resampler parameters
EFFECTS="rate 11025"
RATE=128k

# Attach resampler and hold pipe open
cat $AUDIO_PIPE | play -V0 -r $RATE -t raw -e s -b 16 -c 1 - -V3 -c 1 $EFFECTS &
exec 3>$AUDIO_PIPE		# Keep audio pipe open even if writer (rtl_fm) closes

# Main loop
echo "Waiting..."
while true; do
  if read line <$CMD_FIFO; then
    params=($line)

    # Look for start command (e.g. start noaa15 137.620M)
    if [[ "${params[0]}" == 'start' ]]; then
      echo "Seen start: "$line
      FILENAME="/home/pi/wx/"$(date +"%Y%m%d%H%M%S")".wav"
      COMMENT=${params[1]}_$(date +"%Y%^b%d-%H%M%S%Z")
      rtl_fm -M fm -f "${params[2]}" -s $RATE -g 50 -E offset | tee "$AUDIO_PIPE" | (sox -V0 -r $RATE -t raw -e s -b 16 -c 1 - --comment $COMMENT $FILENAME $EFFECTS) &

    # Look for stop command (e.g. stop)
    elif [[ "${params[0]}" == 'stop' ]]; then
      echo "Seen stop: "$line
      pkill --signal SIGINT rtl_fm

    # Look for quit command (e.g. quit)
    elif [[ "${params[0]}" == 'quit' ]]; then
      echo "Seen quit: "$line
      break

    # Invalid command
    else
      echo "Invalid command: "$line
    fi

  fi
done

# Clean up before exiting
on_exit

