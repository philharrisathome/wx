#!/bin/bash
# See /usr/local/bin/wxctl for client
# Expects name of satellite as $1, frequency as $2

export AUDIODRIVER=alsa

# Use built-in audio port
#export AUDIODEV=hw:1,0,0

# Use ALSA loopback (output will be on hw:Loopback,0,1
export AUDIODEV=hw:Loopback,0,0

# Use USB soundcard
#export AUDIODEV=hw:2,0,0

echo =====================================================================================
echo Recording from $1 on $2...

EFFECTS="rate 11025"
RATE=64k
FILENAME="/home/pi/wx/"$(date +"%Y%m%d%H%M%S")".wav"
COMMENT=$1_$(date +"%Y%^b%d-%H%M%S%Z")
TEE_PIPE=/tmp/record_noaa.$RANDOM

function on_exit {
  echo "Caught exit signal..."
  wait
  rm -f $TEE_PIPE
  exit
}

# Ensure clean up on signal
trap on_exit SIGHUP SIGINT SIGTERM 

# Save to file
#timeout 30m rtl_fm -M fm -f $2 -s $RATE -g 50 -E dc | sox  -r $RATE -t raw -e s -b 16 -c 1 - ./$1.wav $EFFECTS

# Pipe to audio device
#timeout 30m rtl_fm -M fm -f $2 -s $RATE -g 50 -E dc | play -r $RATE -t raw -e s -b 16 -c 1 -V3 - -t alsa $EFFECTS

# Pipe to audio device
timeout 30m rtl_fm -M fm -f $2 -s $RATE -g 50 -E offset | play -V3 -r $RATE -t raw -e s -b 16 -c 1 - -c 1 -t alsa $EFFECTS

# Save to file and pipe to audio
if false; then
rm -f $TEE_PIPE
mkfifo $TEE_PIPE
cat $TEE_PIPE | (play -V3 -r $RATE -t raw -e s -b 16 -c 1 - -c 1 -t alsa $EFFECTS) &
rtl_fm -M fm -f $2 -s $RATE -g 50 -E offset | tee $TEE_PIPE | (sox -V0 -r $RATE -t raw -e s -b 16 -c 1 - --comment $COMMENT $FILENAME $EFFECTS)
fi

# Clean up before exiting
on_exit

