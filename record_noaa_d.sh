#!/bin/bash
# See /usr/local/bin/wxctl for client

# Get absolute path to this script
BASE_PATH=$(realpath $(dirname $0))

# Path to bulk storage for recordings
STORAGE_PATH=/media/pi/USB_DISK/

# Expect commands through this fifo
CMD_FIFO=/tmp/record_noaa_cmd

# Audio will be published through this pipe at 11025 Hz S16LE
AUDIO_PIPE=/tmp/noaa_audio_pipe

# Path to the luaradio runtime
LUARADIO=${HOME}/luaradio/luaradio

# Cleanup on exit
function on_exit {
  echo "Cleaning up..."
  pkill --signal SIGINT luajit
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
# Use sudo modprobe snd-aloop to create loopback, and add snd-aloop to /etc/modules
export AUDIODRIVER=alsa			# Use ALSA driver
export AUDIODEV=hw:Loopback,0,0	# Use ALSA loopback (output will be on hw:Loopback,0,1)

# Attach resampler and hold pipe open
# Play requires sox
cat $AUDIO_PIPE | play -q -V0 -t raw -e s -b 16 -L -c 1 -r 11025 - -V0 -c 1 &
exec 3>$AUDIO_PIPE		# Keep audio pipe open even if writer closes

# Start WxToImg in record mode
#/usr/local/bin/xwxtoimg &

# Initialise variables
FILENAME=""
COMMENT=""
SATELLITE=""
FREQUENCY=""

# Main loop
echo "Waiting..."
while true; do
  if read line <$CMD_FIFO; then
    echo "`date -u +"%Y%^b%d-%H%M%S%Z"`: "$line
    params=($line)

    # Look for start command to start recording (e.g. start NOAA-15 137.620M)
    if [[ "${params[0]}" == 'start' ]]; then
      if [ -z "$FILENAME" ]; then	# If a recording is in progress then ignore command
        echo "================================================================================"
        FILENAME=${STORAGE_PATH}"audio/"$(date -u +"%Y%m%d%H%M%S")".wav"
        SATELLITE="${params[1]}"
        FREQUENCY="${params[2]/M/e6}"
        COMMENT=${SATELLITE}"_"$(date -u +"%Y%^b%d-%H%M%S%Z")
        ${LUARADIO} rtlsdr_noaa_apt.lua $FREQUENCY $FILENAME &
      else
        echo "WARNING: Ignoring start - recording already in progress..."  
      fi

    # Look for stop command to stop recording (e.g. stop)
    elif [[ "${params[0]}" == 'stop' ]]; then
      if [ -n "$FILENAME" ]; then	# Only process files once (can get multiple stops)
        pkill --signal SIGINT luajit
        ./process_recording.sh "$FILENAME" "$SATELLITE" &
        FILENAME=""
      fi

    # Look for quit command (e.g. quit)
    elif [[ "${params[0]}" == 'quit' ]]; then
      break

    # Invalid command
    else
      echo "`date`: Invalid command: "$line
    fi

  fi
done

# Clean up before exiting
on_exit

