#!/bin/sh

COUNT=0
while true; do

  echo ">> Doing some work here! ${COUNT}"
  sleep 3

  COUNT=$((COUNT+1))
done

