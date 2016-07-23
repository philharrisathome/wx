#!/bin/bash

export AUDIODRIVER=alsa

# Use built-in audio port
#export AUDIODEV=hw:1,0,0

# Use ALSA loopback
#export AUDIODEV=hw:0,0,0

# Use USB soundcard
#export AUDIODEV=hw:2,0,0

EFFECTS="rate 44100"
FREQ=106.100M
RATE=170k

# Save to file and pipe to audio 
rm -f noaa_pipe
mkfifo noaa_pipe
cat noaa_pipe | (play -V0 -r $RATE -t raw -e s -b 16 -c 1 - -t alsa $EFFECTS) &
timeout 30m rtl_fm -M fm -f $FREQ -s $RATE -g 50 -E dc -E deemp | tee noaa_pipe | (sox -V0 -r $RATE -t raw -e s -b 16 -c 1 - ./redfm.wav $EFFECTS)


