#!/usr/bin/env python
# encoding: utf-8
'''
Celery Task Definitions
'''
from celery import Celery
import socket

app = Celery('tasks')
app.config_from_object('celeryconfig')


@app.task(name='task.print_some_data')
def print_some_data(some_data):
    """Print the specified data to stdout"""

    wid = str(socket.gethostname())
    data = str(some_data)
    print("Worker-%s: %s" % (wid, data))
