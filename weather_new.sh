#!/bin/bash

year=`date -d yesterday +%y`
month=`data -d yesterday +%m`
day=`date -d yesterday +%d`

curl "https://www.wunderground.com/history/airport/GNV/$year/$month/$day.html?&format=1" > gnv.txt

maxTemp=`awk -F',' '{print $2}' gnv.txt | sort -n | tail -n1`

echo The Max temp is $maxTemp

