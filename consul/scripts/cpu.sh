#!/bin/bash

set -- $(grep 'cpu ' /proc/stat | awk '{print ($2+$4)*100/($2+$4+$5)}')
total_usage_percent=$1

printf "CPU Usage: %s\n" $total_usage_percent

if [ $total_usage_percent -gt 95 ]; then
  exit 2
elif [ $total_usage_percent -gt 80 ]; then
  exit 1
else
  exit 0
fi
