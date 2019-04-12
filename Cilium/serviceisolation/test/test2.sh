#!/bin/bash

source myalias.sh

cluster1="${CLUSTER1:-cilium19}"
cluster2="${CLUSTER2:-cilium20}"
id1="${CLUSTERID1:-19}"
id2="${CLUSTERID2:-20}"

echo "creating global services in both clusters"
kubectx $cluster1 
echo $cluster1 
k create -f a-svc-g.yaml
