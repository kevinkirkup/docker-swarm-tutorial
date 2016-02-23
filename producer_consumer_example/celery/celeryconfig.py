#!/usr/bin/env python
# encoding: utf-8

from kombu import Queue

BROKER_URL = 'amqp://'

CELERY_RESULT_BACKEND = 'amqp'

CELERY_TASK_SERIALIZER = 'json'
CELERY_RESULT_SERIALIZER = 'json'
CELERY_ACCEPT_CONTENT = ['json']

CELERY_TIMEZONE = 'UTC'
CELERY_ENABLE_UTC = True

CELERY_IMPORTS = ('tasks', )
CELERY_IGNORE_RESULT = False

