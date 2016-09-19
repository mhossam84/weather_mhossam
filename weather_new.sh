#!/bin/bash

year=`date -d yesterday +%y`
echo $year
month=`data -d yesterday +%m`
echo $month
day=`date -d yesterday +%d`
echo $day

curl "https://www.wunderground.com/history/airport/GNV/$year/$month/$day.html?&format=1" > gnv.txt

maxTemp=`awk -F',' '{print $2}' gnv.txt | sort -n | tail -n1`

echo The Max temp is $maxTemp

