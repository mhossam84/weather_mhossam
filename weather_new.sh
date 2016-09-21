#!/bin/bash

year=`date -d yesterday +%Y`
month=`date -d yesterday +%m`
day=`date -d yesterday +%d`

echo $year $month $day

curl "https://www.wunderground.com/history/airport/GNV/$year/$month/$day/DailyHistory.html?&format=1" > gnv.txt

maxTemp=`awk -F',' '{print $2}' gnv.txt | sort -n | tail -n1`

echo The Max temp is $maxTemp

