#!/bin/bash
# This script is run nightly by the following cron job:
#	m h  dom mon dow   command
#	0 1 * * * trash-empty > /dev/null 2>&1
#	0 1 * * * /home/pi/wx/update-keps.sh > /dev/null 2>&1

rm /tmp/weather.txt
wget -qr www.celestrak.org/NORAD/elements/weather.txt -O /tmp/weather.txt

#rm /tmp/noaa.txt
#wget -qr https://www.celestrak.org/NORAD/elements/noaa.txt -O /tmp/noaa.txt

#-rm /tmp/amateur.txt
#wget -qr https://www.celestrak.org/NORAD/elements/amateur.txt -O /tmp/amateur.txt

cp /tmp/weather.txt /home/pi/.predict/weather.tle
cp /tmp/weather.txt /home/pi/.wxtoimg/weather.txt

