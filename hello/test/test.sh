#!/bin/bash

source myalias.sh

cluster1="${CLUSTER1:-cilium19}"
cluster2="${CLUSTER2:-cilium20}"
id1="${CLUSTERID1:-19}"
id2="${CLUSTERID2:-20}"

clusters=( $cluster1 $cluster2 )

# Error if no parameter are provided
if [ $# -eq 0 ] ; then
	echo "Error: no parameter provided"
        echo "for help type encrypt.sh --help"
        exit 2;
fi

echo $cluster1
echo $cluster2

echo "creating global services in both clusters"
for cluster in "${clusters[@]}"
do
 kubectx $cluster 
 k create -f a-svc-g.yaml
 k create -f b-svc-g.yaml
 k create -f c-svc-g.yaml
 k create -f d-svc-g.yaml
done
