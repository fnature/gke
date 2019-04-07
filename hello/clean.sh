#!/bin/bash

source myalias.sh

cluster1="${CLUSTER1:-cilium19}"
cluster2="${CLUSTER2:-cilium20}"
id1="${CLUSTERID1:-19}"
id2="${CLUSTERID2:-20}"
clusters=( $cluster1 $cluster2 )


for i in {1..2}
   do
    kubectx ${clusters[i-1]}

    k delete deploy a
    k delete deploy b
    k delete deploy c
    k delete deploy d
    k delete cm response-cluster$i
    k delete svc a-svc-g
    k delete svc b-svc-g
    k delete svc c-svc-g
    k delete svc d-svc-g

done;



