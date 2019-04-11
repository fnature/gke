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

    k delete CiliumNetworkPolicy l3-a
    k delete CiliumNetworkPolicy l3-b
    k delete CiliumNetworkPolicy l3-c
    k delete CiliumNetworkPolicy l3-d
    k delete CiliumNetworkPolicy l4-a
    k delete CiliumNetworkPolicy l4-b
    k delete CiliumNetworkPolicy l4-c
    k delete CiliumNetworkPolicy l4-d

done;



