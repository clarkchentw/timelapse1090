#!/bin/bash

trap "kill 0" SIGINT
trap "kill -2 0" SIGTERM
SOURCE=/run/dump1090-fa
INTERVAL=10
HISTORY=24
CS=240
source /etc/default/timelapse1090

if [ $(($CHUNK_SIZE)) -lt 1 ]
# default remains set if CHUNK_SIZE is not set in configuration file
then true
elif [ $(($CHUNK_SIZE)) -lt 10 ]
# minimum allowed chunk size
then
	CS=10
elif [ $(($CHUNK_SIZE)) -lt 10000 ]
# if chunk size larger than this, use default
then
	CS=$CHUNK_SIZE
fi


dir=/run/timelapse1090
hist=$(($HISTORY*3600/$INTERVAL))
chunks=$(( 1 + ($hist/$CS) ))
partial=$(($hist%$CS))
if [[ $partial != 0 ]]
then actual_chunks=$(($chunks+1))
else actual_chunks=$chunks
fi


while true
do
	cd $dir
	rm -f *.gz
	rm -f *.json

	if ! cp $SOURCE/receiver.json .
	then
		sleep 60
		continue
	fi
	sed -i -e "s/refresh\" : [0-9]*/refresh\" : ${INTERVAL}000/" $dir/receiver.json
	sed -i -e "s/history\" : [0-9]*/history\" : $actual_chunks/" $dir/receiver.json

	i=0
	j=0
	while true
	do
		sleep $INTERVAL &


		cd $dir
		if ! cp $SOURCE/aircraft.json history_$((i%$CS)).json &>/dev/null
		then
			sleep 0.05
			cp $SOURCE/aircraft.json history_$((i%$CS)).json
		fi
		sed -i -e '$a,' history_$((i%$CS)).json


		if [[ $((i%13)) == 3 ]]
		then
			sed -e '1i{ "files" : [' -e '$a]}' -e '$d' history_*.json | gzip -1 > temp.gz
			mv temp.gz chunk_$j.gz
		fi

		i=$((i+1))

		if [[ $i == $CS ]]
		then
			sed -e '1i{ "files" : [' -e '$a]}' -e '$d' history_*.json | gzip -9 > temp.gz
			mv temp.gz chunk_$j.gz
			i=0
			j=$((j+1))
			rm -f history*.json
		fi
		if [[ $j == $chunks ]] && [[ $i == $partial ]]
		then
			sed -e '1i{ "files" : [' -e '$a]}' -e '$d' history_*.json 2>/dev/null | gzip -9 > temp.gz
			mv temp.gz chunk_$j.gz 2>/dev/null
			i=0
			j=0
			rm -f history*.json
		fi

		wait
	done
	sleep 5
done &

while true
do
	sleep 1024
done &

wait

exit 0

