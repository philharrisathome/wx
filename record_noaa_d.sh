#!/bin/bash
# See /usr/local/bin/wxctl for client

# Expect commands through this fifo
CMD_FIFO=/tmp/record_noaa_cmd

# Cleanup on exit
function on_exit {
  echo "Cleaning up..."
  pkill --signal SIGINT luajit
  rm -f $CMD_FIFO
  exit
}

# Ensure clean up on signal
trap on_exit SIGHUP SIGINT SIGTERM

# Create new command fifo
rm -f $CMD_FIFO
mkfifo $CMD_FIFO

# Main loop
echo "Waiting..."
while true; do
  if read line <$CMD_FIFO; then
    params=($line)

    # Look for start command (e.g. start noaa15 137.620M)
    if [[ "${params[0]}" == 'start' ]]; then
      echo "`date`: Seen start: "$line
      FILENAME="/home/pi/wx/"$(date +"%Y%m%d%H%M%S")".wav"
      COMMENT=${params[1]}_$(date +"%Y%^b%d-%H%M%S%Z")
      echo "Recording: "$FILENAME
      luaradio rtlsdr_noaa_apt.lua "${params[2]/M/e6}" $FILENAME &

    # Look for stop command (e.g. stop)
    elif [[ "${params[0]}" == 'stop' ]]; then
      echo "`date`: Seen stop: "$line
      pkill --signal SIGINT luajit
      sleep 5s
      ./process_recording.sh $FILENAME &

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

