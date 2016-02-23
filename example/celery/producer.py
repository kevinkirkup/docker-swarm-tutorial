#!/usr/bin/env python
# encoding: utf-8

from tasks import print_some_data
import time

data = 0

while True:

    print("Producing: %i" % data)

    print_some_data.delay(data)
    time.sleep(3)

    data += 1
