#!/bin/bash

year=`date -d yesterday +%y`
echo $year
month=`date -d yesterday +%m`
echo $month
day=`date -d yesterday +%d`
echo $day

curl "https://www.wunderground.com/history/airport/GNV/$year/$month/$day.html?&format=1" > gnv2.txt
maxTemp=`awk -F',' '{print $2}' gnv2.txt | sort -n | tail -n1`

echo The Max temp is $maxTemp

