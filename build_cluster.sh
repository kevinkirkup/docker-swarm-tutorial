#!/usr/bin/env bash

CLUSTER=c0
CLUSTER_MASTER=$CLUSTER-master

##################################################
echo Create the Consul VM
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
NODE_IP=$(docker-machine ip consul-kv)

# Create the Consul container
docker $(docker-machine config consul-kv) run -d -h consul \
  -p 8300:8300 \
  -p 8301:8301 \
  -p 8301:8301/udp \
  -p 8302:8302 \
  -p 8302:8302/udp \
  -p 8400:8400 \
  -p 8500:8500 \
  -p 8600:53 \
  -p 8600:53/udp \
  --name consul \
  progrium/consul \
  -log-level debug \
  -data-dir /tmp/consul \
  -server \
  -bootstrap \
  -advertise $NODE_IP \
  -dc vb1

echo ----------------------------------------
echo Logs
echo ----------------------------------------
docker logs consul
echo ----------------------------------------

#CONSUL_MASTER_IP="$(docker inspect -f '{{.NetworkSettings.IPAddress}}' consul)"
CONSUL_MASTER_IP="$(docker-machine ip consul-kv)"

##################################################
echo Create the Swarm Nodes
##################################################

#--------------------------------------------------
echo Create the Master Node
#--------------------------------------------------
docker-machine create \
  -d virtualbox \
  --swarm \
  --swarm-master \
  --swarm-discovery="consul://$(docker-machine ip consul-kv):8500" \
  --engine-opt="cluster-store=consul://$(docker-machine ip consul-kv):8500" \
  --engine-opt="cluster-advertise=eth1:2376" \
  $CLUSTER_MASTER

#--------------------------------------------------
echo Create Nodes
#--------------------------------------------------
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
done


##################################################
echo Add Consul and Registrator
##################################################
SWARM_NODES=("$CLUSTER_MASTER" "${CLUSTER}-n1" "${CLUSTER}-n2")

for i in "${SWARM_NODES[@]}"; do

  NODE_IP=$(docker-machine ip $i)

  eval "$(docker-machine env $i)"
  docker run --name consul-$i -d -h consul-$i \
    -p $NODE_IP:8300:8300 \
    -p $NODE_IP:8301:8301 \
    -p $NODE_IP:8301:8301/udp \
    -p $NODE_IP:8302:8302 \
    -p $NODE_IP:8302:8302/udp \
    -p $NODE_IP:8400:8400 \
    -p $NODE_IP:8500:8500 \
    -p $NODE_IP:8600:53 \
    -p $NODE_IP:8600:53/udp \
    progrium/consul \
    -log-level debug \
    -data-dir /tmp/consul \
    -server \
    -dc vb1 \
    -advertise $NODE_IP \
    -join $CONSUL_MASTER_IP

  echo ----------------------------------------
  echo Logs
  echo ----------------------------------------
  docker logs consul-$i
  echo ----------------------------------------

  echo "Starting Registrator in node $i"
  eval "$(docker-machine env $i)"
  docker run -d \
      -v /var/run/docker.sock:/tmp/docker.sock \
      -h registrator-$i \
      --name registrator-$i \
      gliderlabs/registrator \
      consul://$(docker-machine ip consul-kv):8500

done


###################################################
#echo Create some services
###################################################
#
#eval $(docker-machine env --swarm $CLUSTER_MASTER)
#docker run -d --name redis.0 -p 10000:6379 \
#    -e "SERVICE_NAME=db" \
#    -e "SERVICE_TAGS=master,backups" \
#    -e "SERVICE_REGION=vb1" redis
#
#docker run -d --name nginx.0 -p 4443:443 -p 8000:80 \
#    -e "SERVICE_443_NAME=https" \
#    -e "SERVICE_443_ID=https.12345" \
#    -e "SERVICE_443_SNI=enabled" \
#    -e "SERVICE_80_NAME=http" \
#    -e "SERVICE_REGION=vb1" \
#    -e "SERVICE_TAGS=www" nginx
