#!/bin/env bash

echo ">> Waiting for RabbitMQ to start"

sleep 10

# Create the producer
python producer.py

