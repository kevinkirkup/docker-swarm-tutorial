#!/usr/bin/env bash

CLUSTER=c0
CLUSTER_MASTER=$CLUSTER-master

##################################################
# Create the Consul VM
##################################################
docker-machine create \
  -d virtualbox \
  consul-kv

# Enable port forwarding for Consul in VirtualBox VM
docker-machine stop consul-kv
VBoxManage modifyvm "consul-kv" --natpf1 "Consul,tcp,127.0.0.1,8500,,8500"
docker-machine start consul-kv

# Change to the Consul VM
eval $(docker-machine env consul-kv)

# Create the Consul container
docker $(docker-machine config consul-kv) run -d \
  -p 8500:8500 \
  -h consul \
  --name consul \
  progrium/consul \
  -server -bootstrap

##################################################
# Create the Master VM
##################################################
docker-machine create \
  -d virtualbox \
  --swarm \
  --swarm-master \
  --swarm-discovery="consul://$(docker-machine ip consul-kv):8500" \
  --engine-opt="cluster-store=consul://$(docker-machine ip consul-kv):8500" \
  --engine-opt="cluster-advertise=eth1:2376" \
  $CLUSTER_MASTER

# Add Registrator to the Master
eval $(docker-machine env $CLUSTER_MASTER)
docker run -d \
    -v /var/run/docker.sock:/tmp/docker.sock \
    -h registrator-$i \
    --name 'registrator-master' \
    gliderlabs/registrator \
    consul://$(docker-machine ip consul-kv):8500


##################################################
# Create Nodes
##################################################
CONSUL_MASTER_IP=$(docker-machine ip consul-kv)
SWARM_NODES=("${CLUSTER}-n1" "${CLUSTER}-n2")

for i in "${SWARM_NODES[@]}"; do

  echo "Creating Swarm node $i"
  docker-machine create \
    -d virtualbox \
    --swarm \
    --swarm-discovery="consul://$(docker-machine ip consul-kv):8500" \
    --engine-opt="cluster-store=consul://$(docker-machine ip consul-kv):8500" \
    --engine-opt="cluster-advertise=eth1:2376" \
    $i

  #NODE_IP=$(docker-machine ip $i)

  #eval "$(docker-machine env $i)"
  #docker run --name consul-$i -d -h $i \
  #  -p $NODE_IP:8300:8300 \
  #  -p $NODE_IP:8301:8301 \
  #  -p $NODE_IP:8301:8301/udp \
  #  -p $NODE_IP:8302:8302 \
  #  -p $NODE_IP:8302:8302/udp \
  #  -p $NODE_IP:8400:8400 \
  #  -p $NODE_IP:8500:8500 \
  #  -p $NODE_IP:53:53 \
  #  -p $NODE_IP:53:53/udp \
  #  progrium/consul \
  #  -server \
  #  -advertise $NODE_IP \
  #  -join $CONSUL_MASTER_IP

  echo "Starting Registrator in node $i"
  eval "$(docker-machine env $i)"
  docker run -d \
      -v /var/run/docker.sock:/tmp/docker.sock \
      -h registrator-$i \
      --name registrator-$i \
      gliderlabs/registrator \
      consul://$(docker-machine ip consul-kv):8500

done


##################################################
# Create some services
##################################################

eval $(docker-machine env --swarm $CLUSTER_MASTER)
docker run -d --name redis.0 -p 10000:6379 \
    -e "SERVICE_NAME=db" \
    -e "SERVICE_TAGS=master,backups" \
    -e "SERVICE_REGION=us2" redis

docker run -d --name nginx.0 -p 4443:443 -p 8000:80 \
    -e "SERVICE_443_NAME=https" \
    -e "SERVICE_443_ID=https.12345" \
    -e "SERVICE_443_SNI=enabled" \
    -e "SERVICE_80_NAME=http" \
    -e "SERVICE_REGION=us2" \
    -e "SERVICE_TAGS=www" nginx
