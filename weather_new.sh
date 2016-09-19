#!/bin/bash

year=`date -d yesterday +%y`
echo $year
month=`data -d yesterday +%m`
echo $month
day=`date -d yesterday +%d`
echo $day

curl "https://www.wunderground.com/history/airport/KGNV/$year/$month/$day.html?req_city=Gainesville+Regional&req_state=FL&req_statename=Florida&reqdb.zip=32609&reqdb.magic=5&reqdb.wmo=99999" > gnv.txt
maxTemp=`awk -F',' '{print $2}' gnv.txt | sort -n | tail -n1`

echo The Max temp is $maxTemp

