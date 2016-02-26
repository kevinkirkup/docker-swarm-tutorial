#!/bin/bash

echo $(cat /proc/meminfo |grep Free)
