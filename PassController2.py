from datetime import datetime, timezone
from dashing import *
from collections import namedtuple
import numpy as np
import time
import traceback
import sched
import subprocess
from pprint import pprint

commandQueue = "/tmp/record_noaa_cmd"

tlePath = "/home/pi/.predict/weather.tle"
visibilityElevation = 5.5	# degrees (make this non-integer to avoid divide-by-zero issues in findRoots())
minMaximumElevation = 23	# degrees
satellites = {
#	"NOAA 15": {"freq": "137.620M",  "priority": 0},
	"NOAA 18": {"freq": "137.9125M", "priority": 1},
	"NOAA 19": {"freq": "137.100M",  "priority": 2}
}
sch = sched.scheduler(time.time, time.sleep)

Pass = namedtuple("Pass", "satellite data event")
currentPass = None

term = Terminal()
ui = VSplit(
	Text(title="{t.white}Status{t.normal}".format(t=term), text="", border_color=7), 
	Log(title="{t.white}Log{t.normal}".format(t=term), border_color=7),
	title="{t.bold_white}Pass Controller{t.normal}".format(t=term)
	)
statusPanel = ui.items[0]
logPanel = ui.items[1]

#=======================================================================

def ts(t):
	# Format timestamp
	dt = datetime.fromtimestamp(t, tz=timezone.utc)
	return dt.strftime("%d %b %Y %H:%M:%S %Z")

def tds(t1,t2):
	# Format difference between 2 timestamps
	dt1 = datetime.fromtimestamp(t1, tz=timezone.utc)
	dt2 = datetime.fromtimestamp(t2, tz=timezone.utc)
	return str(dt1 - dt2)

#=======================================================================

def extractObservation(data):
	# Extracts observation parameters from the format:
	# 1664646703 Sat 01Oct22 17:51:43    0  108  106   37  334   3428  70319 * 0.000000
	
	data = data.split()
	obsData = {
		"timestamp": int(data[0]),
		"day": data[1],
		"date": data[2],
		"time": data[3],
		"elevation": int(data[4]),
		"azimuth": int(data[5]),
		"phase": int(data[6]),
		"latitude": int(data[7]),
		"longitude": int(data[8]),
		"range": int(data[9]),
		"orbitNumber": int(data[10]),
		"visibility": data[11]
	}
	
	return obsData

#=======================================================================

def findRoots(x,y):
	# From https://stackoverflow.com/questions/46909373/how-to-find-the-exact-intersection-of-a-curve-as-np-array-with-y-0
	# x and y must be numpy arrays
    s = np.abs(np.diff(np.sign(y))).astype(bool)
    return x[:-1][s] + np.diff(x)[s]/(np.abs(y[1:][s]/y[:-1][s])+1)
    
#=======================================================================
    
def extractPass(data):
	# Extracts pass parameters from the format:
	# 1664646703 Sat 01Oct22 17:51:43    0  108  106   37  334   3428  70319 * 0.000000
	# 1664646805 Sat 01Oct22 17:53:25    5   99  110   43  336   2891  70319 * 0.000000
	# 1664646906 Sat 01Oct22 17:55:06   11   87  115   49  339   2436  70319 * 0.000000
	# 1664647006 Sat 01Oct22 17:56:46   16   70  119   54  342   2124  70319 * 0.000000
	# 1664647105 Sat 01Oct22 17:58:25   18   49  123   60  345   2018  70319 * 0.000000
	# 1664647202 Sat 01Oct22 18:00:02   15   28  127   65  350   2141  70319 * 0.000000
	# 1664647301 Sat 01Oct22 18:01:41   11   12  131   71  357   2460  70319 * 0.000000
	# 1664647402 Sat 01Oct22 18:03:22    5    0  135   76    8   2919  70319 * 0.000000
	# 1664647504 Sat 01Oct22 18:05:04    0  352  140   79   30   3462  70319 * 0.000000

	passData = {
		"startTime": None,
		"endTime": None,
		"duration": 0,
		"visibleStartTime": None,
		"visibleEndTime": None,
		"maxElevation": 0
	}

	data = data.splitlines()
	times = []
	elevations = []
	for d in data:
		obsData = extractObservation(d)
		times.append(obsData["timestamp"])
		elevations.append(obsData["elevation"])

	# Calculate pass start and stop times
	passData["startTime"] = times[0]
	passData["endTime"] = times[-1]

	# Extract maxElevation
	passData["maxElevation"] = max(elevations)

	# Estimate times when satellite is visible
	z = findRoots(np.array(times), np.array([(e - visibilityElevation) for e in elevations]))
	if len(z) > 1:
		passData["visibleStartTime"] = z[0]
		passData["visibleEndTime"] = z[-1]
		passData["duration"] = passData["visibleEndTime"] - passData["visibleStartTime"]

	return passData

#=======================================================================

def getPredictData(satellite, searchFrom=''):
	
	try:
		# print("predict -t "+tlePath+" -p \""+satellite+"\" "+str(int(searchFrom)))
		cp = subprocess.run(
			["bash", "-c", "predict -t "+tlePath+" -p \""+satellite+"\" "+str(searchFrom)], 
			capture_output=True, encoding="ascii", timeout=10
		)
	except FileNotFoundError as exc:
		logPanel.append("{t.bold_red}ERROR - predict() failed (not found) for {}.{t.normal}".format(satellite, t=term))
	except subprocess.CalledProcessError as exc:
		logPanel.append("{t.bold_red}ERROR - predict() failed (unsuccessful) for {}.{t.normal}".format(satellite, t=term))
	except subprocess.TimeoutExpired as exc:
		logPanel.append("{t.bold_red}ERROR - predict() failed (timeout) for {}.{t.normal}".format(satellite, t=term))
			
	return cp.stdout

#=======================================================================
	
def sendCommand(cmd, satellite='', params=''):
	# Forward start and stop commands and recording parameters 
	# to the command queue of record_noaa_d.sh

	cmd = "{} {} {}".format(cmd, satellite.replace(" ", "-"), params)
	# logPanel.append("  " + cmd)
	with open(commandQueue, 'a') as f:
		f.write(cmd + '\n')
	
#=======================================================================

def startPass(satellite, passData):
	
	global currentPass

	# Check priority of new pass
	if currentPass:
		if satellites[satellite]["priority"] <= satellites[currentPass.satellite]["priority"]:
			# This new pass is lower priority than current, ignore
			logPanel.append("{t.yellow}IGNORE_PASS for {} at {}.{t.normal}" \
				.format(satellite, ts(passData["visibleStartTime"]), t=term))
			logPanel.append("{t.yellow}CONTINUE_PASS for {} from {} to {}.{t.normal}" \
				.format(currentPass.satellite, ts(currentPass.data["visibleStartTime"]), ts(currentPass.data["visibleEndTime"]), t=term))
			scheduleNextPass(satellite)
			return
		else:
			# This pass is higher priority than current, stop current pass
			sch.cancel(currentPass.event)
			finishPass(currentPass.satellite, currentPass.data)

	# Start the new pass
	logPanel.append("{t.cyan}START_PASS for {} at {}.{t.normal}" \
		.format(satellite, ts(passData["visibleStartTime"]), t=term))
	finishEvent = sch.enterabs(passData["visibleEndTime"], 1, finishPass, (satellite, passData))
	currentPass = Pass(satellite, passData, finishEvent)
	
	# Send command
	sendCommand("start", satellite, satellites[satellite]["freq"])

#=======================================================================

def finishPass(satellite, passData):

	global currentPass
		
	# Current pass is ending
	logPanel.append("{t.cyan}FINISH_PASS for {} at {}.{t.normal}" \
		.format(satellite, ts(passData["visibleEndTime"]), t=term))

	# Send command
	sendCommand("stop", satellite)
	
	scheduleNextPass(satellite)
	currentPass = None
	
#=======================================================================

def scheduleNextPass(satellite):

	searchFrom = time.time()

	for i in range(0, 96):
		predictData = getPredictData(satellite, searchFrom)
		passData = extractPass(predictData)
		# Only schedule future passes - ignore any passes in progress
		if passData["visibleStartTime"]:
			if (passData["visibleStartTime"] > time.time()) and (passData["maxElevation"] >= minMaximumElevation):
				logPanel.append("{t.green}NEXT_PASS for {} at {} with elevation of {}.{t.normal}" \
					.format(satellite, ts(passData["visibleStartTime"]), passData["maxElevation"], t=term))
				sch.enterabs(passData["visibleStartTime"], 1, startPass, (satellite,passData))
				return
				
		# Pass wasn't visible or didn't meet criteria so jump ahead to next pass
		searchFrom = passData["endTime"] + 15 * 60;
	
	logPanel.append("{t.bold_red}ERROR - No next pass found for {}.{t.normal}".format(satellite, t=term))
	
#=======================================================================

def displayQueue():

	global currentPass
	
	now = time.time()
	status = "{t.white}Time now is: {t.bold_white}{}{t.normal}\n".format(ts(now), t=term)

	e = sch.queue[0]
	if e.action == startPass:
		status = status + "{t.white}Next pass in: {t.bold_white}{}{t.normal}\n".format(tds(e.time, now), t=term)
	else:
		pd = e.argument[1]
		progressLength = 20
		progress = int(progressLength * (now - pd["visibleStartTime"]) / pd["duration"])
		status = status + "{t.white}Pass ends in: {t.bold_green}{}{t.normal}".format(tds(e.time, now), t=term)
		status = status + " [{}{}]\n".format("#"*progress, "."*(progressLength-progress), t=term)
	
	status = status + "\n{t.white}Queue:{t.normal}\n".format(t=term)
	for e in sch.queue:
		if e.action == startPass:
			satellite = e.argument[0]
			pd = e.argument[1]
			if currentPass and (satellite == currentPass.satellite):
				status = status + " {t.bold_green}{}{t.normal}: From {t.bold_green}{}{t.normal} to {t.bold_green}{}{t.normal}, elev={t.bold_white}{}{t.normal}\n" \
				.format(satellite, ts(pd["visibleStartTime"]), ts(pd["visibleEndTime"]), pd["maxElevation"], t=term)
			else:
				status = status + " {t.bold_white}{}{t.normal}: From {t.bold_white}{}{t.normal} to {t.bold_white}{}{t.normal}, elev={t.bold_white}{}{t.normal}\n" \
				.format(satellite, ts(pd["visibleStartTime"]), ts(pd["visibleEndTime"]), pd["maxElevation"], t=term)

	statusPanel.text = status
	print(term.home + term.clear + term.white)
	ui.display()

	sch.enter(2, 1000, displayQueue)

#=======================================================================

def main():

	with term.fullscreen(), term.hidden_cursor():

		sendCommand("stop")

		# On startup schedule the next pass for all satellites
		for s in satellites:
			scheduleNextPass(s);

		# Start the UI process
		sch.enter(1, 1000, displayQueue)
		sch.run();
		
		# Clean up
		list(map(sch.cancel, sch.queue))	# Cancel all events

#=======================================================================
	
if __name__ == "__main__":

	# for s in satellites:
	# 	scheduleNextPass(s);
	# exit()

	try:
		while True:
			main()		# Never return
	except KeyboardInterrupt:
		pass
	except Exception as exc:
		print(term.home + term.clear +  term.white)
		print(traceback.format_exc())

