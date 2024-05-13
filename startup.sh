#!/bin/bash

export DISPLAY=:0.0
export XAUTHORITY=/home/pi/.Xauthority

LOGFILE=/home/pi/wx/wx_startup.log

# See https://jdimpson.livejournal.com/5685.html
ME=`basename "$0"`;
LCK="/tmp/${ME}.lock";
exec 1000>$LCK;

if flock -n -x 1000; then

	echo $(date -u +"%Y%^b%d-%H%M%S%Z")": Got lock - Startup running." >> $LOGFILE

#	# If WxToImg is not running then start it in record mode
#	if pgrep -x "xwxtoimg" > /dev/null
#	then
#		# Already running - do nothing
#		echo WxToImg already running...
#		echo $(date -u +"%Y%^b%d-%H%M%S%Z")": xwxtoimg already running" >> $LOGFILE
#	else
#		# Not running - start it
#		echo Starting WxToImg...
#		#nohup /usr/local/bin/xwxtoimg &
#		nohup /usr/local/bin/xwxtoimg </dev/null >/dev/null 2>&1 &
#		echo $(date -u +"%Y%^b%d-%H%M%S%Z")": Started xwxtoimg as "$! >> $LOGFILE
#	fi

	# If PassController is not running then start it
	if pgrep -f 'PassController2.py' > /dev/null
	then
		# Already running - do nothing
		echo PassController already running...
		echo $(date -u +"%Y%^b%d-%H%M%S%Z")": PassController already running" >> $LOGFILE
	else
		# Not running - start it
		echo Starting PassController...
		nohup /usr/bin/lxterminal --command="/bin/bash -c 'cd ~/wx && python3 PassController2.py'" </dev/null >/dev/null 2>&1 &
		echo $(date -u +"%Y%^b%d-%H%M%S%Z")": Started PassController as "$! >> $LOGFILE
	fi

	# If record_noaa_d is not running then start it
	if pgrep -f '/bin/bash ./record_noaa_d.sh' > /dev/null
	then
		# Already running - do nothing
		echo record_noaa_d already running...
		echo $(date -u +"%Y%^b%d-%H%M%S%Z")": record_noaa_d already running" >> $LOGFILE
	else
		# Not running - start it
		echo Starting record_noaa_d...
		nohup /usr/bin/lxterminal --command="/bin/bash -c 'cd ~/wx && ./record_noaa_d.sh'" </dev/null >/dev/null 2>&1 &
		echo $(date -u +"%Y%^b%d-%H%M%S%Z")": Started record_noaa_d as "$! >> $LOGFILE
	fi

	sleep 20 
	echo $(date -u +"%Y%^b%d-%H%M%S%Z")": Startup complete." >> $LOGFILE

else
	echo $(date -u +"%Y%^b%d-%H%M%S%Z")": Failed to get lock - Startup abandoned." >> $LOGFILE
fi

