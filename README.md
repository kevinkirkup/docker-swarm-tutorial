Creating a Docker Swarm Cluster on OS X Virtualbox
===============

[Docker Swarm] is docker's implementation for managing clusters running of docker containers.

## Terminology

### Docker

 * **Swarm:** Dockers's cluster implementation, comparable to [Kubernetes].
 * **Machine:** Hosts running the docker-daemon for deployment of docker containers. Think VM's, VPS, Baremetal.
 * **Discovery Service:** Service for the cluster that allows for service discover and using provides a shared key/value store.
 * **Data Volume:** A *data volume* is a specially-designated directory within one or more containers that bypasses the Union File System.


### Kubernetes

 * **Cluster:** A cluster is a set of physical or virtual machines and other infrastructure resources used by Kubernetes to run your applications.
 * **Pod:** A pod is a co-located group of containers and volumes.
 * **Node:** A node is a physical or virtual machine running Kubernetes, onto which pods can be scheduled.
 * **Service:** A service defines a set of pods and a means by which to access them, such as single stable IP address and corresponding DNS name.
 * **Volume:** A volume is a directory, possibly with some data in it, which is accessible to a Container as part of its filesystem.
Kubernetes volumes build upon Docker Volumes, adding provisioning of the volume directory and/or device.


Setup Docker Swarm Discovery Service
===============

## Pre-Requisites

 This tutorial was written with Mac OSX in mind. Although Docker and VirtualBox are avialable for Linux and Windows,
 The steps below may not completely work in either of those environments.

 Please feel free to submit pull requests for any changes that may be needed to make this applicable for Linux and/or Windows, and I'm include them.

 * [VirtualBox]
 * [VirtualBox Extension Pack]
 * [Docker Toolbox]

The first decision that we need to make when we are configuring our cluster is which service discovery method that we are going to use.
There are a number of different Discover Servers supported by Docker Swarm:

 * [Docker Swarm] - Uses Dockerhub
 * [Consul] - Hashicorp
 * [etcd] - CoreOS
 * [zookeeper] - Apache

For more detailed information, please refer to the *Discovery Services* section below

## Using DockerHub for Swarm Discovery

When we use Docker Swarm for discovery, we need download the *swarm* docker container to request a *token* from DockerHub which will identify the machines as being part of the Cluster.

### Create Machine - *default*

To create our token we need to run *swarm* in a docker container. This can be run in any available machine available, and doesn't need to be persistent.
I our case, we will create a *default* machine for running our *swarm* docker image.

    $ docker-machine create -d virtualbox default

This will create a VirtualBox VM on our local development machine named default

### Option1: Creating our Swarm Token

We need to point docker to use our *default* machine that we just created. This is done by sourcing the *default* machine
environment in to our current shell. *Note!* This is a typical idiom used with docker, so you will see it in a number of examples.

    $ eval $(docker env default)

Next, we will create our token. We don't need to keep the container around after were done, so we are using the `--rm` command line option.
This will cause the container to be destroyed once the container finishes executing.

    $ docker run --rm swarm create
    866d4e73e57a6710b0c471847ba1edfb

The returned has will be our Swarm discover token and is used when creating out master and worker nodes using
the `--swarm-discovery=token:\\866d4e73e57a6710b0c471847ba1edfb` option when creating our machines later on.

## Option 2: Using Consul for Swarm Discovery

Using Docker Swarm as a discovery service is nice, but we may already have existing infrastructure that we need to support.
I our case, we are going to use [Consul] for our discovery service for the rest of this tutorial.

### Create the docker machine to host our Consul instance

First, we will need to create a Machine to host or Consul instance and start our container on the new machine.
This will not be part allocated as part of our cluster.

```sh
$ docker-machine create \
  -d virtualbox \
  consul-kv

Running pre-create checks...
Creating machine...
(consul-kv) Copying /Users/kevinkirkup/.docker/machine/cache/boot2docker.iso to /Users/kevinkirkup/.docker/machine/machines/consul-kv/boot2docker.iso...
(consul-kv) Creating VirtualBox VM...
(consul-kv) Creating SSH key...
(consul-kv) Starting the VM...
(consul-kv) Waiting for an IP...
Waiting for machine to be running, this may take a few minutes...
Machine is running, waiting for SSH to be available...
Detecting operating system of created instance...
Detecting the provisioner...
Provisioning with boot2docker...
Copying certs to the local machine directory...
Copying certs to the remote machine...
Setting Docker configuration on the remote daemon...
Checking connection to Docker...
Docker is up and running!
To see how to connect Docker to this machine, run: docker-machine env consul-kv

$ docker $(docker-machine config consul-kv) run -d \
  -p 8500:8500 \
  -h consul \
  --name consul \
  progrium/consul \
  -server -bootstrap

Unable to find image 'progrium/consul:latest' locally
latest: Pulling from progrium/consul
c862d82a67a2: Pull complete
0e7f3c08384e: Pull complete
0e221e32327a: Pull complete
09a952464e47: Pull complete
60a1b927414d: Pull complete
4c9f46b5ccce: Pull complete
417d86672aa4: Pull complete
b0d47ad24447: Pull complete
fd5300bd53f0: Pull complete
a3ed95caeb02: Pull complete
d023b445076e: Pull complete
ba8851f89e33: Pull complete
5d1cefca2a28: Pull complete
Digest: sha256:8cc8023462905929df9a79ff67ee435a36848ce7a10f18d6d0faba9306b97274
Status: Downloaded newer image for progrium/consul:latest
5c7159173814124fd229163641e82a564b9488b9e6093a487ca22618314830a3
```

I the command above, we told docker to run docker container on the *consul-kv* machine using the *progrium/consul* docker image,
give it the hostname of *consul* (`-h`) with docker container *consul* (`--name`).
The `-d` option tells docker to run in the background (detached mode).
The `-p 8500:8500` specifies that the guest port 8500 should be exposed on the host on port 8500.
The options `-server -bootstrap` are passed to the the `consule` command line.

*NOTE:* If you are using Virtaul Box to host your VM's, you will need to enable port forwarding to
be able to see the Consul Web UI.

1. Open VirtualBox
1. Select the *consul-kv* virtual machine and select *Settings*.
1. Click the *Network/Adaptor 1* and show the *Advanced* settings.
1. Click *Port Forwarding*
1. Add a new rule with the following parameters:

    Protocol: TCP
    Host IP: 127.0.0.1
    Host Port: 8500
    Guest IP: -blank-
    Guest Port: 8500

This will forward all traffic on port 8500 from the Host machine to the *consul-kv* VM that we
created.

Create the Docker Machines
================

To create our store cluster, we are going to have to create a few more machines to run our docker containers on.

    1 x Manager
    n x Worker - For this tutorial, we are going to be creating 2 Workers.

When we are done, we should have something that looks like this:

```sh
$ docker-machine ls

NAME        ACTIVE   URL          STATE     URL                         SWARM                DOCKER    ERRORS
c0-master   -        virtualbox   Running   tcp://192.168.99.109:2376   c0-master (master)   v1.10.1
c0-n1       -        virtualbox   Running   tcp://192.168.99.110:2376   c0-master            v1.10.1
c0-n2       -        virtualbox   Running   tcp://192.168.99.112:2376   c0-master            v1.10.1
consul-kv   -        virtualbox   Running   tcp://192.168.99.108:2376                        v1.10.1
```


### Create the Master Machine

First we create the Swarm Master. This is the VM that will handle the distribute of containers to
the cluster and also represents the cluster to the outside world.

There are a few arguments that we will use to setup access to the discovery service we setup earlier.

 * `--swarm` Include this machine in a swarm cluster
 * `--swarm-master` This is the master for the swarm cluster
 * `--swarm-discovery` This is sets the discover service to use for the swarm

There are a couple of options that specify how the docker daemon needs to be configured. The use
the `--engine-opt` command line option.

 * `cluster-store` - URL of the distributed storage backend
 * `cluster-advertise` - Address of the daemon instance on the cluster

For more information on the available options, check the documentation for the [Docker Daemon] on github.

In addition to the normal arguments we pass to `docker-machine create` we will add the `--swarm`
to tell it we want the machine to be part of a swarm cluster and `--swarm-master` to indicate this
is the master for the cluster.

```sh
$ docker-machine create \
  -d virtualbox \
  --swarm \
  --swarm-master \
  --swarm-discovery="consul://$(docker-machine ip consul-kv):8500" \
  --engine-opt="cluster-store=consul://$(docker-machine ip consul-kv):8500" \
  --engine-opt="cluster-advertise=eth1:2376" \
  c0-master

Running pre-create checks...
Creating machine...
(c0-master) Copying /Users/kevinkirkup/.docker/machine/cache/boot2docker.iso to /Users/kevinkirkup/.docker/machine/machines/c0-master/boot2docker.iso...
(c0-master) Creating VirtualBox VM...
(c0-master) Creating SSH key...
(c0-master) Starting the VM...
(c0-master) Waiting for an IP...
Waiting for machine to be running, this may take a few minutes...
Machine is running, waiting for SSH to be available...
Detecting operating system of created instance...
Detecting the provisioner...
Provisioning with boot2docker...
Copying certs to the local machine directory...
Copying certs to the remote machine...
Setting Docker configuration on the remote daemon...
Configuring swarm...
Checking connection to Docker...
Docker is up and running!
To see how to connect Docker to this machine, run: docker-machine env c0-master
```

### Create Worker Nodes

Now we want to create our workers and associate them with the swarm.
We use the same docker daemon configuration options that we used when setting up the swarm master.

```sh
$ docker-machine create \
  -d virtualbox \
  --swarm \
  --swarm-discovery="consul://$(docker-machine ip consul-kv):8500" \
  --engine-opt="cluster-store=consul://$(docker-machine ip consul-kv):8500" \
  --engine-opt="cluster-advertise=eth1:2376" \
  c0-n1

Running pre-create checks...
Creating machine...
(c0-n1) Copying /Users/kevinkirkup/.docker/machine/cache/boot2docker.iso to /Users/kevinkirkup/.docker/machine/machines/c0-n1/boot2docker.iso...
(c0-n1) Creating VirtualBox VM...
(c0-n1) Creating SSH key...
(c0-n1) Starting the VM...
(c0-n1) Waiting for an IP...
Waiting for machine to be running, this may take a few minutes...
Machine is running, waiting for SSH to be available...
Detecting operating system of created instance...
Detecting the provisioner...
Provisioning with boot2docker...
Copying certs to the local machine directory...
Copying certs to the remote machine...
Setting Docker configuration on the remote daemon...
Configuring swarm...
Checking connection to Docker...
Docker is up and running!
To see how to connect Docker to this machine, run: docker-machine env c0-n1

$ docker-machine create \
  -d virtualbox \
  --swarm \
  --swarm-discovery="consul://$(docker-machine ip consul-kv):8500" \
  --engine-opt="cluster-store=consul://$(docker-machine ip consul-kv):8500" \
  --engine-opt="cluster-advertise=eth1:2376" \
  c0-n2

Running pre-create checks...
Creating machine...
(c0-n2) Copying /Users/kevinkirkup/.docker/machine/cache/boot2docker.iso to /Users/kevinkirkup/.docker/machine/machines/c0-n2/boot2docker.iso...
...
```

Now if we open the [Consul Web UI](http://localhost:8500/ui/), we should be able to see our master and work nodes.

### Managing the Swarm

Now that we have all of the nodes for our cluster, we can communicate with the entire cluster as one
unit. We start by sourcing the swarm environment.

```sh
# Source the Swarm Environment
$ eval $(docker-machine env --swarm c0-master)

# Get information for the Cluster
$ docker info

Containers: 12
 Running: 5
 Paused: 0
 Stopped: 7
Images: 8
Server Version: swarm/1.1.2
Role: primary
Strategy: spread
Filters: health, port, dependency, affinity, constraint
Nodes: 3
 c0-master: 192.168.99.109:2376
  └ Status: Healthy
  └ Containers: 8
  └ Reserved CPUs: 0 / 1
  └ Reserved Memory: 0 B / 1.021 GiB
  └ Labels: executiondriver=native-0.2, kernelversion=4.1.18-boot2docker, operatingsystem=Boot2Docker 1.10.2 (TCL 6.4.1); master : 611be10 - Mon Feb 22 22:47:06 UTC 2016, provider=virtualbox, storagedriver=aufs
  └ Error: (none)
  └ UpdatedAt: 2016-02-23T15:37:40Z
 c0-n1: 192.168.99.110:2376
  └ Status: Healthy
  └ Containers: 2
  └ Reserved CPUs: 0 / 1
  └ Reserved Memory: 0 B / 1.021 GiB
  └ Labels: executiondriver=native-0.2, kernelversion=4.1.18-boot2docker, operatingsystem=Boot2Docker 1.10.2 (TCL 6.4.1); master : 611be10 - Mon Feb 22 22:47:06 UTC 2016, provider=virtualbox, storagedriver=aufs
  └ Error: (none)
  └ UpdatedAt: 2016-02-23T15:37:40Z
 c0-n2: 192.168.99.111:2376
  └ Status: Healthy
  └ Containers: 2
  └ Reserved CPUs: 0 / 1
  └ Reserved Memory: 0 B / 1.021 GiB
  └ Labels: executiondriver=native-0.2, kernelversion=4.1.18-boot2docker, operatingsystem=Boot2Docker 1.10.2 (TCL 6.4.1); master : 611be10 - Mon Feb 22 22:47:06 UTC 2016, provider=virtualbox, storagedriver=aufs
  └ Error: (none)
  └ UpdatedAt: 2016-02-23T15:37:40Z
Plugins:
 Volume:
 Network:
Kernel Version: 4.1.18-boot2docker
Operating System: linux
Architecture: amd64
CPUs: 3
Total Memory: 3.064 GiB
Name: c0-master
```

Registering with Consul
===============

We need a way to register our new services with Consul. For that, we will run [Registrator] in a
container on every node in our cluster.

```sh
$ docker run -d \
    -v /var/run/docker.sock:/tmp/docker.sock \
    --name 'registrator' \
    gliderlabs/registrator \
    consul://$(docker-machine ip consul-kv):8500
```

This will monitor for any ports that are opened by our services and report them to our *consul-kv* instance for service discovery.
There are additional environment variables that we can add to our docker containers will can provide more information about our service.
Please reference the [GliderLabs Service](http://gliderlabs.com/registrator/latest/user/services/) documentation for more inforamtion.

We should now be able to see our *swarm* node in the [Consul WebUI](http://localhost:8500).

Deploying containers
===============

Next, we are going to deploy our containers using `docker-compose`(Formerly Fig). This simplifies
our service configuration so that instead of running individual `docker run` commands to setup our
services, we can configure them in a single YAML file. Then we can control all of the services as
a cluster instead of having to interact with each individual service.

For the following instructions, please reference the `producer_consumer_example` code.

## Starting our cluster

We'll start by using `docker-compose` to start our initial cluster configuration.

```sh
# Change to the example directory
$ cd producer_consumer_example

# Make sure we are referencing our swarm environment
$ eval $(docker env --swarm c0-master)

# Deploy our services
$ docker-compose up

Pulling rabbit-mgt (rabbitmq:3-management)...
c0-n2: Pulling rabbitmq:3-management... : downloaded
c0-master: Pulling rabbitmq:3-management... : downloaded
c0-n1: Pulling rabbitmq:3-management... : downloaded
Creating producerconsumerexample_rabbit-mgt_1
Pulling consumer (celery:latest)...
c0-n2: Pulling celery:latest... : downloaded
c0-master: Pulling celery:latest... : downloaded
c0-n1: Pulling celery:latest... : downloaded
Creating producerconsumerexample_consumer_1
Creating producerconsumerexample_producer_1
Attaching to producerconsumerexample_rabbit-mgt_1, producerconsumerexample_consumer_1, producerconsumerexample_producer_1
rabbit-mgt_1 |
rabbit-mgt_1 |               RabbitMQ 3.6.0. Copyright (C) 2007-2015 Pivotal Software, Inc.
rabbit-mgt_1 |   ##  ##      Licensed under the MPL.  See http://www.rabbitmq.com/
rabbit-mgt_1 |   ##  ##
rabbit-mgt_1 |   ##########  Logs: tty
rabbit-mgt_1 |   ######  ##        tty
rabbit-mgt_1 |   ##########
rabbit-mgt_1 |               Starting broker...
rabbit-mgt_1 | =INFO REPORT==== 23-Feb-2016::16:06:08 ===
rabbit-mgt_1 | Starting RabbitMQ 3.6.0 on Erlang 18.2
rabbit-mgt_1 | Copyright (C) 2007-2015 Pivotal Software, Inc.
rabbit-mgt_1 | Licensed under the MPL.  See http://www.rabbitmq.com/
...
```

This will start up our services in order based on our *link* and *depends_on* configuration settings
in our *docker-compose.yml* file. Although the services are started in the correct order, if you
services have dependencies on each other and the service takes a while to start up, you will need to
add code to detect when the dependent service has become available. For expediency in our example
code, we have added a *delay* of 10 seconds. In your production code, you should do something more
elegant such as monitoring for service port to be available.

## Scaling

Now that we have our services running, let scale up our cluster by adding a few more *producer*
instances.

Open a new terminal and source our environment

```sh
# Make sure we are referencing our swarm environment
$ eval $(docker env --swarm c0-master)

# Change to the example directory
$ cd producer_consumer_example

# Scale up to 5 producer services
$ docker-compose scale producer=5

```

In the service window, you should now see output from the consumer for the additional producer
threads.

References
===============


### Docker Articles

 * [Docker Overlay Networks: That was Easy](https://medium.com/on-docker/docker-overlay-networks-that-was-easy-8f24baebb698#.x414sz27h)
 * [Evaluate Swarm in a sandbox](https://docs.docker.com/swarm/install-w-machine/)
 * [Provision a Swarm cluster with Docker Machine](https://docs.docker.com/swarm/provision-with-machine/)
 * [Deploy and Manage Any Cluster Manager with Docker Swarm](https://blog.docker.com/2015/11/deploy-manage-cluster-docker-swarm/)
 * [Swarm Frontends](https://github.com/docker/swarm-frontends)
 * [Running a Small Docker Swarm Cluster](http://blog.scottlowe.org/2015/03/06/running-own-docker-swarm-cluster/)
 * [Logging with Docker — Part 1](https://medium.com/@yoanis_gil/logging-with-docker-part-1-b23ef1443aac#.xh2v5aq9j)
 * [How to scale Docker Containers with Docker-Compose](https://www.brianchristner.io/how-to-scale-a-docker-container-with-docker-compose/)
 * [Running a Distributed Docker Swarm on AWS](http://blog.levvel.io/blog-post/running-distributed-docker-swarm-on-aws/)

### Discover Service Articles

 * [Docker Swarm Discover](https://docs.docker.com/swarm/discovery/)
 * [Consul service discover with docker](http://progrium.com/blog/2014/08/20/consul-service-discovery-with-docker/)
 * [Consul Docker Image](https://hub.docker.com/r/progrium/consul/)
 * [Another Consul Docker Image](https://hub.docker.com/r/qnib/consul/)
 * [Instruction on getting *etcd* running under docker can be found here](https://coreos.com/etcd/docs/latest/docker_guide.html).
 * [Registrator](http://gliderlabs.com/registrator/latest/user/quickstart/)

### Elastic Search Articles

 * [Elastic Search Docker Image](https://hub.docker.com/r/qnib/elk/)


[etcd]: https://coreos.com/etcd
[Consul]: https://www.consul.io
[zookeeper]: https://zookeeper.apache.org
[Kubernetes]: http://kubernetes.io
[Elastic]: https://www.elastic.co

[Docker]: https://www.docker.com
[Docker Swarm]: https://docs.docker.com/swarm/
[Docker Machine]: https://docs.docker.com/machine/
[Docker Compose]: https://docs.docker.com/compose/
[Docker Toolbox]: https://www.docker.com/products/docker-toolbox
[Docker Daemon]: https://github.com/docker/docker/blob/master/docs/reference/commandline/daemon.md

[VirtualBox]: https://www.virtualbox.org/wiki/Downloads
[VirtualBox Extension Pack]: https://www.virtualbox.org/wiki/Downloads
