#!/bin/bash

source myalias.sh

cluster1="${CLUSTER1:-cilium19}"
cluster2="${CLUSTER2:-cilium20}"
id1="${CLUSTERID1:-19}"
id2="${CLUSTERID2:-20}"

# Error if no parameter are provided
if [ $# -eq 0 ] ; then
	echo "Error: no parameter provided"
        echo "for help type encrypt.sh --help"
        exit 2;
fi

echo "creating global services in both clusters"
for i in {1..2}
do
 cluster = cluster$i
 kubectx $cluster 
 k create -f a-svc-g.yaml
 k create -f b-svc-g.yaml
 k create -f c-svc-g.yaml
 k create -f d-svc-g.yaml
done

# Error if no parameter are provided
if [ $1 = "noneshared" ] ; then
 echo "noneshared";
 
 kubectx $cluster1
 k create -f a.yaml
 k create -f b.yaml

 kubectx $cluster2
 k create -f c2.yaml
 k create -f d2.yaml

 else
  if [ $1 = "shared" ]; then
   echo "shared";
   
   kubectx $cluster1
   k create -f a.yaml
  
   kubectx $cluster2
   k create -f b.yaml


   for i in {1..2}
   do
    cluster = cluster$i
    kubectx $cluster
    
    k create -f c$i.yaml
    k create -f d$i.yaml
   done

  else
   echo "bad input"
   exit 2;
  fi
fi






