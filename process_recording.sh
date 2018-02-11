#!/bin/bash
# Expects name of recording file as $1, satellite as $2 
# e.g. process_recording /media/pi/USB_DISK/audio/20180211090901.wav NOAA-18
# Requires wxtoimg, mutt

# Get absolute path to this script
BASE_PATH=$(realpath $(dirname $0))

# Keep track of the last successful execution of this script
LAST_GENERATED_FILE=/tmp/record_noaa_last_generated

# Path to bulk storage for recordings and images
STORAGE_PATH=/media/pi/USB_DISK/
AUDIO_PATH=${STORAGE_PATH}"audio/"
RAW_PATH=${STORAGE_PATH}"raw/"
MAPS_PATH=${STORAGE_PATH}"maps/"
IMAGES_PATH=${STORAGE_PATH}"images/"
COMPOSITES_PATH=${STORAGE_PATH}"composites/"

# The space-seperated list of email addresses of recipients of the success notification
DISTRIBUTION_LIST=$(<distribution_list.txt)	

# Reformat parameters
INPUT_FILE=$1
SATELLITE=${2-"NOAA-15"}	# TODO: More intelligent search for satellite when parameter missing
SATELLITE=${SATELLITE//-/ }	# Convert satellite back to NORAD name so wxtoimg can find correct orbit

echo "--------------------------------------------------------------------------------"
echo "Processing recording: "$INPUT_FILE" for "$SATELLITE

# Get pass start time (date of last access)
# Need format of "26 Oct 2001 23:22:00 UTC"
PASS_START_TIME=$(date -d @`stat -c %X "$INPUT_FILE"` -u +"%d %b %Y %H:%M:%S %Z")
echo "Recording start time: "$PASS_START_TIME

# Generate map if it doesn't exist
INPUT_BASENAME=$(basename $INPUT_FILE)
MAP_FILE=${MAPS_PATH}${INPUT_BASENAME%".wav"}".map"
if [[ ! -e $MAP_FILE ]]; then
  echo "Generating map: "$MAP_FILE
  PASS_SUMMARY="$(wxmap -T "$SATELLITE" -M 10 -b 0 -d -o "$PASS_START_TIME" "$MAP_FILE" 2>&1)"
else
  echo "Using map: "$MAP_FILE
  PASS_SUMMARY="No pass information available - Using previously generated map."
fi

# Generate archive image - RAW
RAW_FILE=${RAW_PATH}${INPUT_BASENAME%".wav"}".png"
if [[ ! -e $RAW_FILE ]]; then
  echo "Generating raw image: "$RAW_FILE
  wxtoimg -r -16 -o "$INPUT_FILE" "$RAW_FILE"
else
  echo "Using raw image: "$RAW_FILE
fi

# Generate image - HVCT, or MCIR if no visible channel
IMAGE_FILE_TEMPLATE=${IMAGES_PATH}${INPUT_BASENAME%".wav"}"_%s-%p-%E-%e-img.jpg"

echo "Generating HVCT image: "$IMAGE_FILE_TEMPLATE
PROCESSING_SUMMARY="$(wxtoimg -e HVCT -K -m "$MAP_FILE" -k "color=white,%N" -k "fontsize=18,%H:%M:%S, %A, %d %b %Y UTC" -k "fontsize=12,%D %E %z" -g 1.4 -s 0.6 -D 2 -Q 90 -A -c -o "$RAW_FILE" "$IMAGE_FILE_TEMPLATE" 2>&1)"
if [[ ($PROCESSING_SUMMARY == *"could not find a NOAA sensor 1 or sensor 2 image"*) || ($PROCESSING_SUMMARY == *"could not find a usable visible image"*) ]]; then			# No visible channel for HVCT
  echo "HVCT failed (no visible channel) - Generating MCIR image: "$IMAGE_FILE_TEMPLATE
  PROCESSING_SUMMARY="$(wxtoimg -e MCIR -K -m "$MAP_FILE" -k "color=white,%N" -k "fontsize=18,%H:%M:%S, %A, %d %b %Y UTC" -k "fontsize=12,%D %E %z" -g 1.4 -s 0.6 -D 2 -Q 90 -A -c -o "$RAW_FILE" "$IMAGE_FILE_TEMPLATE" 2>&1)"
fi
IMAGE_FILE=(${IMAGES_PATH}${INPUT_BASENAME%".wav"}*)
IMAGE_FILE=${IMAGE_FILE[0]}		# There should be only one

# Project image
PROJ_FILE=${COMPOSITES_PATH}$(basename $IMAGE_FILE)
echo "Generating projection: "$PROJ_FILE
wxproj -p orthographic -l 50 -m -10 -b 75,25,-45,25 -Q 90 -o $IMAGE_FILE $PROJ_FILE

# Get device status
DEVICE_STATUS="$(uptime && df -h "$STORAGE_PATH")"

# Check image generation was successful
if [[ ! -e $IMAGE_FILE ]]; then		# Skip failed processing
  echo "ERROR: Processing failed for: "$INPUT_FILE
elif [[ $PROCESSING_SUMMARY == *"Narrow IF bandwidth"* ]]; then		# Skip low S/N recordings (tuning failed?)
  echo "ERROR: Low SNR: "$INPUT_FILE
elif [[ $PROCESSING_SUMMARY == *"couldn't find telemetry data"* ]]; then		# Skip empty recordings
  echo "ERROR: No telemetry found for: "$INPUT_FILE
elif [[ $PROCESSING_SUMMARY == *"enhancement ignored"* ]]; then		# Skip missing sensor data (satellite in darkness)
  echo "WARNING: Missing sensor data: "$INPUT_FILE
elif [[ $PROCESSING_SUMMARY == *"solar elevation"* ]]; then		# Skip low sun elevation recordings
  echo "WARNING: Low sun angle for: "$INPUT_FILE
elif [[ $PROCESSING_SUMMARY == *"could not find a usable visible image"* ]]; then		# Skip recordings during dark period
  echo "WARNING: No visible image for: "$INPUT_FILE
else
  # Success - Send notification
  echo "Sending: "$IMAGE_FILE
  echo -e "${PASS_SUMMARY}""\n""${PROCESSING_SUMMARY}""\n..\nSystem:\n""${DEVICE_STATUS}" | mutt -s "wx: Recorded ""${SATELLITE}"" at ""${PASS_START_TIME}" -a "$IMAGE_FILE" -- $DISTRIBUTION_LIST 
  # Store the name of the most recent image file
  echo "$IMAGE_FILE" > $LAST_GENERATED_FILE
fi

# Remove old recordings
find ${AUDIO_PATH} -mindepth 1 -mtime +1 -delete

# Remove old maps
find ${MAPS_PATH} -mindepth 1 -mtime +1 -delete

# Remove empty recordings from wxtoimg
rm -f ~/wxtoimg/audio/*.wav
