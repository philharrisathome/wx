#!/bin/bash

export AUDIODRIVER=alsa

# Use built-in audio port
#export AUDIODEV=hw:1,0,0

# Use ALSA loopback
#export AUDIODEV=hw:0,0,0

# Use USB soundcard
#export AUDIODEV=hw:2,0,0

# Pipe to audio device
rtl_fm -M fm -f 106.100M -s 170k -E offset -E dc -E deemp -g 50 | play -r 170k -t raw -e s -b 16 -c 1 -V0 - rate 44100


