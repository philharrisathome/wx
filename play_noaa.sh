#!/bin/bash
# Expects name of file as $1

export AUDIODRIVER=alsa

# Use built-in audio port
#export AUDIODEV=hw:1,0,0

# Use ALSA loopback (output will be on hw:Loopback,0,1
export AUDIODEV=hw:Loopback,0,0

# Use USB soundcard
#export AUDIODEV=hw:2,0,0

echo =====================================================================================
echo Playing from $1...

TEE_PIPE=/tmp/record_noaa.$RANDOM

function on_exit {
  rm -f $TEE_PIPE
  exit
}

# Ensure clean up on signal
trap on_exit SIGHUP SIGINT SIGTERM 

# Play from file and pipe to audio
play -V3 $1 -t alsa rate 44100

# Clean up before exiting
on_exit

