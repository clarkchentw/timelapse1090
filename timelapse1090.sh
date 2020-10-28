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


dir=/usr/local/share/timelapse1090/historyData
#hist=$(($HISTORY*3600/$INTERVAL))
hist=$(awk "BEGIN {printf \"%.0f\", $HISTORY * 3600 / $INTERVAL}")
chunks=$(( $hist/$CS + 2 ))
#increase chunk size to get history size as close as we can
CS=$(( CS - ( (CS - hist % CS)/(chunks-1) ) ))


while true
do
  cd $dir
  
  
  ## Copy dump1090-fa's receiver.json to timelapse1090
  # If fail, wait for 60 second and try it again
  if ! cp $SOURCE/receiver.json .
  then
    sleep 60
    continue
  fi
  
  # Update refresh rate based on the interval setting in receiver.json
  sed -i -e "s/refresh\" : [0-9]*/refresh\" : ${INTERVAL}000/" $dir/receiver.json
  
  # Get the latest chunk number
  [ -f chunk_0.gz ] && (lastChunk=$(ls chunk_*.gz -t | cut -c7- | rev | cut -c4- | rev | head -n 2 | tail -n +2)) && lastChunk=$((lastChunk+1)) || lastChunk=0
  [[ $lastChunk -ge $chunks ]] && lastChunk=0
  # Update history(chunk number) in receiver.json
  sed -i -e "s/history\" : [0-9]*/history\" : $((chunks+1))/" $dir/receiver.json

  i=0
  j=$lastChunk #Need to be lastChunk or 0
  while true
  do
    sleep $INTERVAL & # Wait for interval of time


    cd $dir # Go into history directory

    date=$(date +%s%N | head -c-7) #Get current date time in epoch time

    # If aircraft.json in dump1090-fa can't be copy to history_$date.json, try again after 0.05sec
    if ! cp $SOURCE/aircraft.json history_$date.json &>/dev/null
    then
      sleep 0.05
      cp $SOURCE/aircraft.json history_$date.json
    fi
    
    # If aircraft.json in dump1090-fa can't be copy to history_$date.json, re-run after 30sec
    if ! [ -f history_$date.json ]; then
      sleep 30
      continue
    fi

    # Adding a ',' at the end of history_$date.json to make the next data entry valid
    sed -i -e '$a,' history_$date.json


    if [[ $((i%42)) == 41 ]] # When history_$date.json has collected for 41 time, package it into gz file
    then
      # Compress all the history_x.json into temp.gz
      sed -e '1i{ "files" : [' -e '$a]}' -e '$d' history_*.json | gzip -5 > temp.gz
      mv temp.gz chunk_$j.gz # Rename it base on j
      
      # Compress a blank chunk file
      echo "{ \"files\" : [ ] }" | gzip -1 > rec_temp.gz
      mv rec_temp.gz chunk_$chunks.gz
      rm -f latest_*.json
    else
      # Add a soft link from latest to history 
      if [ -f history_$date.json ]; then
        ln -s history_$date.json latest_$date.json
      fi
      if [[ $((i%7)) == 6 ]] # Put latest.json into last chunk once every 7 time
      then
        sed -e '1i{ "files" : [' -e '$a]}' -e '$d' latest_*.json | gzip -2 > temp.gz
        mv temp.gz chunk_$chunks.gz
      fi
    fi

    i=$((i+1)) # i += 1, to complete the first term

    if [[ $i == $CS ]] # If $i == chunkSize
    then
      # Zip all history.json into chunk_$j.gz
      sed -e '1i{ "files" : [' -e '$a]}' -e '$d' history_*.json | 7za a -si temp.gz >/dev/null
      mv temp.gz chunk_$j.gz
      
      # Compress a blank chunk file
      echo "{ \"files\" : [ ] }" | gzip -1 > rec_temp.gz
      mv rec_temp.gz chunk_$chunks.gz
      rm -f history*.json
      rm -f latest_*.json
      
      # Set i back to beginning, j+=1, and if $j become chunks size, set it back to 0
      i=0
      j=$((j+1))
      if [[ $j == $chunks ]]
      then
        j=0
      fi
    fi

    wait
  done
  sleep 5
done &

wait

exit 0

