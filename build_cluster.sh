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

eval $(docker-machine env consul-kv)

# Create the Consul servers container
#
# DO NOT DO THIS IN PRODUCTION!!
# We are going to run 1 server
#
# Mount the docker socket so we can request the health
# using a separate docker container that the one we are running in
#

# Notes!
# On consul-kv, I'm able to query the DNS with:
#
# $ docker run -it joffotron/docker-net-tools
# $ dig @172.17.0.1 -p 8600 db.service.consul
#
# On c0-master(c0-n1, ...), I'm able to query the DNS with:
#
# $ docker run -it joffotron/docker-net-tools
# $ dig @192.168.99.112 -p 8600 db.service.consul

CONSUL_MASTER_IP="$(docker-machine ip consul-kv)"

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
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $(pwd)/consul/config:/config  \
  -v $(pwd)/consul/scripts/mem.sh:/data/consul/scripts/mem.sh \
  -v $(pwd)/consul/scripts/cpu.sh:/data/consul/scripts/cpu.sh \
  -v $(pwd)/consul/scripts/disk.sh:/data/consul/scripts/disk.sh \
  --name consul \
  progrium/consul \
  -advertise $CONSUL_MASTER_IP \
  -dc vb1

echo ----------------------------------------
echo Logs
echo ----------------------------------------
docker logs consul
echo ----------------------------------------

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
  --swarm-discovery="consul://$CONSUL_MASTER_IP:8500" \
  --engine-opt="cluster-store=consul://$CONSUL_MASTER_IP:8500" \
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
    --swarm-discovery="consul://$CONSUL_MASTER_IP:8500" \
    --engine-opt="cluster-store=consul://$CONSUL_MASTER_IP:8500" \
    --engine-opt="cluster-advertise=eth1:2376" \
    $i
done

##################################################
echo Create Overlay Network
##################################################
eval $(docker-machine env --swarm $CLUSTER_MASTER)
docker network create -d overlay myCluster

##################################################
echo Add Consul Clients and Registrator
##################################################
SWARM_NODES=("$CLUSTER_MASTER" "${CLUSTER}-n1" "${CLUSTER}-n2")
for i in "${SWARM_NODES[@]}"; do

  NODE_IP=$(docker-machine ip $i)

  # We are going to setup a client on each node in the cluster
  # to report data back to the Consul servers
  #
  # Mount the docker socket so we can request the health
  # using a separate docker container that the one we are running in
  #
  # We don't want to register the consul service ports, so mark
  # the service as SERVICE_IGNORE. This will prevent the registrator
  # from register the service ports with the Consul Server
  #
  eval "$(docker-machine env $i)"
  docker run --name consul-$i -d -h $i \
    -p $NODE_IP:8300:8300 \
    -p $NODE_IP:8301:8301 \
    -p $NODE_IP:8301:8301/udp \
    -p $NODE_IP:8302:8302 \
    -p $NODE_IP:8302:8302/udp \
    -p $NODE_IP:8400:8400 \
    -p $NODE_IP:8500:8500 \
    -p $NODE_IP:53:53 \
    -p $NODE_IP:53:53/udp \
    -e "SERVICE_IGNORE=true" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v $(pwd)/consul/config/system.json:/config/system.json  \
    -v $(pwd)/consul/scripts/mem.sh:/data/consul/scripts/mem.sh \
    -v $(pwd)/consul/scripts/cpu.sh:/data/consul/scripts/cpu.sh \
    -v $(pwd)/consul/scripts/disk.sh:/data/consul/scripts/disk.sh \
    progrium/consul \
    -log-level debug \
    -dc vb1 \
    -node $i \
    -advertise $NODE_IP \
    -client 0.0.0.0 \
    -join $CONSUL_MASTER_IP

  echo ----------------------------------------
  echo Logs
  echo ----------------------------------------
  docker logs consul-$i
  echo ----------------------------------------

  echo "Starting Registrator on node $i"

  eval "$(docker-machine env $i)"
  docker run -d \
      -v /var/run/docker.sock:/tmp/docker.sock \
      -h $i \
      --name registrator \
      gliderlabs/registrator \
      -ip $NODE_IP \
      consul://$NODE_IP:8500

done


##################################################
echo Create some services
##################################################

eval $(docker-machine env --swarm $CLUSTER_MASTER)
docker run -d --name redis.0 -p 10000:6379 \
    -e "SERVICE_NAME=db" \
    -e "SERVICE_TAGS=master,backups" \
    -e "SERVICE_REGION=vb1" redis

docker run -d --name nginx.0 -p 4443:443 -p 8000:80 \
    -e "SERVICE_443_NAME=https" \
    -e "SERVICE_443_ID=https.12345" \
    -e "SERVICE_443_SNI=enabled" \
    -e "SERVICE_80_NAME=http" \
    -e "SERVICE_REGION=vb1" \
    -e "SERVICE_TAGS=www" nginx
