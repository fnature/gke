#!/bin/bash


export proj=$(gcloud config get-value project)
export zone="europe-west2-a"

root="/home/ed_mitchell/myscript/istio/istio-1.1.2"
# cd $root


# Download istio 1.1.2
# Download istio 1.1.2
# curl -LO https://github.com/istio/istio/releases/download/1.1.2/istio-1.1.2-linux.tar.gz
# tar xzf istio-1.1.2-linux.tar.gz && rm istio-1.1.2-linux.tar.gz


# Clusters creation

function setup-cluster () {

gcloud container clusters create $1 --zone $zone --username "admin" \
  --cluster-version latest --machine-type "n1-standard-2" --image-type "COS" --disk-size "100" \
  --scopes "https://www.googleapis.com/auth/compute","https://www.googleapis.com/auth/devstorage.read_only",\
"https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring",\
"https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly",\
"https://www.googleapis.com/auth/trace.append" \
--num-nodes "4" --network "default" --enable-cloud-logging --enable-cloud-monitoring --enable-ip-alias

# --async is used here.. and hopefully cluster-1 will be up when cluster-2 will be finished..
#  async while cluster-2 creation is working didn't work....


gcloud container clusters get-credentials $1 --zone $zone

kubectl config use-context "gke_${proj}_${zone}_$1"
kubectl get pods --all-namespaces
kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user="$(gcloud config get-value core/account)"

}

function setup-firewall () {
gcloud compute firewall-rules delete istio-multicluster-test-pods --quiet

function join_by { local IFS="$1"; shift; echo "$*"; }
ALL_CLUSTER_CIDRS=$(gcloud container clusters list --format='value(clusterIpv4Cidr)' | sort | uniq)
ALL_CLUSTER_CIDRS=$(join_by , $(echo "${ALL_CLUSTER_CIDRS}"))
ALL_CLUSTER_NETTAGS=$(gcloud compute instances list --format='value(tags.items.[0])' | sort | uniq)
ALL_CLUSTER_NETTAGS=$(join_by , $(echo "${ALL_CLUSTER_NETTAGS}"))
gcloud compute firewall-rules create istio-multicluster-test-pods \
  --allow=tcp,udp,icmp,esp,ah,sctp \
  --direction=INGRESS \
  --priority=900 \
  --source-ranges="${ALL_CLUSTER_CIDRS}" \
  --target-tags="${ALL_CLUSTER_NETTAGS}" --quiet
}

function setup-clusters () {
# test that not sure if it works !! 
echo "usage :  setup-clusters nameofthezone"
echo "if no zone specified, default is europe-west2-a"

zone=${1:-"europe-west2-a"} 
setup-cluster "cluster-1"
setup-cluster "cluster-2"

setup-firewall
}






function setup-istio-master () {
echo "------setup istio master control plane"
echo "based on https://istio.io/docs/setup/kubernetes/install/kubernetes/#installation-steps "
cd $root
kubectl config use-context "gke_${proj}_${zone}_$1"
for i in install/kubernetes/helm/istio-init/files/crd*yaml; do kubectl apply -f $i; done
kubectl apply -f install/kubernetes/istio-demo-auth.yaml
#  I didn't have to create the namespace !!
kubectl label namespace default istio-injection=enabled
}


function setup-istio-master-vpn () {
echo "--------setup istio controle plane for multicluster vpn config"
echo "taken from https://istio.io/docs/examples/multicluster/gke/"

cd $root
kubectl config use-context "gke_${proj}_${zone}_$1"
cat install/kubernetes/helm/istio-init/files/crd-* > istio_master.yaml
helm template install/kubernetes/helm/istio --name istio --namespace istio-system >> istio_master.yaml
kubectl create ns istio-system
kubectl apply -f istio_master.yaml
kubectl label namespace default istio-injection=enabled

echo "wait before setting up the remote istio"
}

function setup-istio-remote-vpn () {

echo "--------setup remote istio vpn config"
echo "taken from https://istio.io/docs/setup/kubernetes/install/multicluster/vpn/"
echo "you must wait istio control plane to be up before applying this config"

cd $root
echo "fetching cluster-1 ips"
kubectl config use-context "gke_${proj}_${zone}_cluster-1"
export PILOT_POD_IP=$(kubectl -n istio-system get pod -l istio=pilot -o jsonpath='{.items[0].status.podIP}')
export POLICY_POD_IP=$(kubectl -n istio-system get pod -l istio=mixer -o jsonpath='{.items[0].status.podIP}')
export TELEMETRY_POD_IP=$(kubectl -n istio-system get pod -l istio-mixer-type=telemetry -o jsonpath='{.items[0].status.podIP}')

echo "pilot pod ip is ${PILOT_POD_IP}"
echo "policy pod ip is ${POLICY_POD_IP}"
echo "telemetry pod ip is ${TELEMETRY_POD_IP}"

echo " creating helm template"
 helm template install/kubernetes/helm/istio --namespace istio-system \
--name istio-remote \
--values install/kubernetes/helm/istio/values-istio-remote.yaml \
--set global.remotePilotAddress=${PILOT_POD_IP} \
--set global.remotePolicyAddress=${POLICY_POD_IP} \
--set global.remoteTelemetryAddress=${TELEMETRY_POD_IP} > $root/istio-remote.yaml


 echo "-------remote installing.."
kubectl config use-context "gke_${proj}_${zone}_cluster-2" 
kubectl create ns istio-system
kubectl apply -f $root/istio-remote.yaml
kubectl label namespace default istio-injection=enabled


echo "------creating remote config files"

export WORK_DIR=$(pwd)
CLUSTER_NAME=$(kubectl config view --minify=true -o jsonpath='{.clusters[].name}')
CLUSTER_NAME="${CLUSTER_NAME##*_}"
export KUBECFG_FILE=${WORK_DIR}/${CLUSTER_NAME}
SERVER=$(kubectl config view --minify=true -o jsonpath='{.clusters[].cluster.server}')
NAMESPACE=istio-system
SERVICE_ACCOUNT=istio-multi
SECRET_NAME=$(kubectl get sa ${SERVICE_ACCOUNT} -n ${NAMESPACE} -o jsonpath='{.secrets[].name}')
CA_DATA=$(kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} -o jsonpath="{.data['ca\.crt']}")
TOKEN=$(kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} -o jsonpath="{.data['token']}" | base64 --decode)

cat <<EOF > ${KUBECFG_FILE}
apiVersion: v1
clusters:
   - cluster:
       certificate-authority-data: ${CA_DATA}
       server: ${SERVER}
     name: ${CLUSTER_NAME}
contexts:
   - context:
       cluster: ${CLUSTER_NAME}
       user: ${CLUSTER_NAME}
     name: ${CLUSTER_NAME}
current-context: ${CLUSTER_NAME}
kind: Config
preferences: {}
users:
   - name: ${CLUSTER_NAME}
     user:
       token: ${TOKEN}
EOF


echo "instantiating secrets on cluster-1..."
kubectl config use-context "gke_${proj}_${zone}_cluster-1"
kubectl create secret generic ${CLUSTER_NAME} --from-file ${KUBECFG_FILE} -n ${NAMESPACE}
kubectl label secret ${CLUSTER_NAME} istio/multiCluster=true -n ${NAMESPACE}



}

function setup-istio-all-vpn () {

setup-istio-master-vpn "cluster-1" 
sleep 10m
setup-istio-remote-vpn

}

function setup-multicluster-vpn () {

setup-clusters
setup-istio-all-vpn

}

function setup-istio-gw () {
echo "------setup istio control plane in 1 cluster for multicluster with gateway connectivity"
echo "based on https://istio.io/docs/setup/kubernetes/install/multicluster/gateways/"

cd $root
cat install/kubernetes/helm/istio-init/files/crd-* > istio.yaml
helm template install/kubernetes/helm/istio --name istio --namespace istio-system \
    -f install/kubernetes/helm/istio/example-values/values-istio-multicluster-gateways.yaml >> istio.yaml

kubectl config use-context "gke_${proj}_${zone}_$1"

kubectl create namespace istio-system
kubectl create secret generic cacerts -n istio-system \
    --from-file=samples/certs/ca-cert.pem \
    --from-file=samples/certs/ca-key.pem \
    --from-file=samples/certs/root-cert.pem \
    --from-file=samples/certs/cert-chain.pem

kubectl apply -f istio.yaml

kubectl label namespace default istio-injection=enabled

}

function setup-dns-gw () {

echo "creating DNS on $1"

kubectl config use-context "gke_${proj}_${zone}_$1"
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: kube-dns
  namespace: kube-system
data:
  stubDomains: |
    {"global": ["$(kubectl get svc -n istio-system istiocoredns -o jsonpath={.spec.clusterIP})"]}
EOF


}


function setup-istio-all-gw () {

echo "------setup istio control plane in both clusters with gateway connectivity"
echo "based on https://istio.io/docs/setup/kubernetes/install/multicluster/gateways/"

setup-istio-gw "cluster-1"
setup-istio-gw "cluster-2"

setup-dns-gw "cluster-1"
setup-dns-gw "cluster-2"

}

function setup-multicluster-gw () {
echo "------setup 2 gke clusters based on istio multicluster with gateway connectivity"
echo "based on https://istio.io/docs/setup/kubernetes/install/multicluster/gateways/"

setup-clusters
setup-istio-all-gw

}

function get-gw-addr () {
echo "we get the ip of  ingressgateway from both clusters"
echo "based on https://istio.io/docs/examples/multicluster/gateways/"

kubectl config use-context "gke_${proj}_${zone}_cluster-1"

export CLUSTER1_GW_ADDR=$(kubectl get svc --selector=app=istio-ingressgateway \
    -n istio-system -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')


kubectl config use-context "gke_${proj}_${zone}_cluster-2"

export CLUSTER2_GW_ADDR=$(kubectl get  svc --selector=app=istio-ingressgateway \
    -n istio-system -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
}


function add-serviceentry () {

echo "---- we add the service entry $2 in $1"
echo "--- the function requires get-gw-addr to be called before"


kubectl config use-context "gke_${proj}_${zone}_$1"

if [ $1 = "cluster-1" ]; then
	othercluster=${CLUSTER2_GW_ADDR}
	othercluster_label="cluster-2"
else
	othercluster=${CLUSTER1_GW_ADDR}
        othercluster_label="cluster-1"
fi

echo "$2-default"
echo $3
echo "$othercluster"

kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: ServiceEntry
metadata:
  name: $2-default
spec:
  hosts:
  # must be of form name.namespace.global
  - $2.default.global
  # Treat remote cluster services as part of the service mesh
  # as all clusters in the service mesh share the same root of trust.
  location: MESH_INTERNAL
  ports:
  - name: http1
    number: 80
    protocol: http
  resolution: DNS
  addresses:
  # the IP address to which httpbin.bar.global will resolve to
  # must be unique for each remote service, within a given cluster.
  # This address need not be routable. Traffic for this IP will be captured
  # by the sidecar and routed appropriately.
  - $3
  endpoints:
  # This is the routable address of the ingress gateway in cluster2 that
  # sits in front of sleep.foo service. Traffic from the sidecar will be
  # routed to this address.
  - address: $othercluster
    labels:
     cluster: $othercluster_label
    ports:
      http1: 15443 # Do not change this port value
EOF





}




function setup-routing-lb-gw () {

kubectl config use-context "gke_${proj}_${zone}_$1"

if [ $1 = "cluster-1" ]; then
	othercluster_label="cluster-2"
else
        othercluster_label="cluster-1"
fi

echo "------ we create the subsets for the global address"
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: $2-global
spec:
  host: $2-svc.default.global
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
  subsets:
  - name: $2
    labels:
      cluster: $othercluster_label

EOF

echo "------ we create the subsets for the local address"
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: $2
spec:
  host: $2-svc.default.svc.cluster.local
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
  subsets:
  - name: $2
    labels:
      name: $2
EOF

echo "------ we create the routes for the local address"
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: $2
spec:
  hosts:
    - $2-svc.default.svc.cluster.local
  http:
  - route:
    - destination:
        host: $2-svc.default.svc.cluster.local
        subset: $2
      weight: 50
    - destination:
        host: $2-svc.default.global
        subset: $2
      weight: 50
EOF


}


function setup-routing-discovery-gw () {
# The aim is to be able to curl x-svc to remote cluster.

kubectl config use-context "gke_${proj}_${zone}_$1"

if [ $1 = "cluster-1" ]; then
	othercluster_label="cluster-2"
else
        othercluster_label="cluster-1"
fi

echo "------ we create the subsets for the global address"


kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: $2-global
spec:
  host: $2-svc.default.global
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
  subsets:
  - name: $2
    labels:
      cluster: $othercluster_label
EOF

echo "------ we create the subsets for the local address"

kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: $2
spec:
  host: $2-svc.default.svc.cluster.local
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
  subsets:
  - name: $2
    labels:
      name: $2
EOF

echo "------ we create the routes for the local address"


kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: $2
spec:
  hosts:
    - $2-svc.default.svc.cluster.local
  http:
  - route:
    - destination:
        host: $2-svc.default.svc.cluster.local
        subset: $2
      weight: 0
    - destination:
        host: $2-svc.default.global
        subset: $2
      weight: 100
EOF


}




function setup-discovery-gw {
#  This setup is not working

echo "function makes remote service $1 discoverable from cluster $2 with ip $3"
echo 'example of use : setup-discovery-gw "b" "cluster-1" "172.255.0.15"'

echo "we recall the addresses of istio ingressgateways"
get-gw-addr

echo "We add the service entry in cluster $2 so DNS works.."
add-serviceentry $2 "$1-svc" $3

echo "We setup routing so that $1-svc is translated to $1.default.global"
setup-routing-discovery-gw $2 $1
}


function setup-testbed-rbac-noneshared-gw {
#  This setup is not working
#  we can't curl across clusters with service name x-svc, only with x-svc.default.global

kubectl config use-context "gke_${proj}_${zone}_cluster-1"
k apply -f res-clust1.yaml
k apply -f a-p.yaml
k apply -f b-p.yaml
k apply -f a-svc-http.yaml
k apply -f b-svc-http.yaml


setup-discovery-gw "c" "cluster-1" "172.255.0.15"
setup-discovery-gw "d" "cluster-1" "172.255.0.16"


kubectl config use-context "gke_${proj}_${zone}_cluster-2"
k apply -f res-clust2.yaml
k apply -f c-b.yaml
k apply -f d-b.yaml
k apply -f c-svc-http.yaml
k apply -f d-svc-http.yaml


setup-discovery-gw "a" "cluster-2" "172.255.0.17"
setup-discovery-gw "b" "cluster-2" "172.255.0.18"
}

function clean-testbed-gw {

kubectl config use-context "gke_${proj}_${zone}_cluster-1"
k delete deployment --all
k delete svc --all
k delete virtualservice --all
k delete destinationrule --all
k delete serviceentry --all
k delete serviceaccount --all


kubectl config use-context "gke_${proj}_${zone}_cluster-2"
k delete deployment --all
k delete svc --all
k delete virtualservice --all
k delete destinationrule --all
k delete serviceentry --all
k delete serviceaccount --all
}





function setup-lb-c () {

#  apply the deployments manually for testbed : res-clustx, and svc in each clusters
#  then below is that c shared in cluster-1 and cluster-2

#  I want to have remote c available from both clusters
get-gw-addr
add-serviceentry "cluster-1" "c-svc" "127.255.0.23"
add-serviceentry "cluster-2" "c-svc" "123.255.0.13"

#  I want to load balance c across clusters
setup-routing-lb-gw "cluster-1" "c"
setup-routing-lb-gw "cluster-2" "c"
}

function setup-lb-d () {

#  apply the deployments manually for testbed : res-clustx, and svc in each clusters
#  then below is that c shared in cluster-1 and cluster-2

#  I want to have remote c available from both clusters
get-gw-addr
add-serviceentry "cluster-1" "d-svc" "127.255.0.24"
add-serviceentry "cluster-2" "d-svc" "123.255.0.14"

#  I want to load balance c across clusters
setup-routing-lb-gw "cluster-1" "d"
setup-routing-lb-gw "cluster-2" "d"
}




function setup-discovery-cluster1tob () {

#  apply the deployments manually for testbed : res-clustx, and svc in each clusters
#  then below is that c shared in cluster-1 and cluster-2

#  I want to have remote c available from both clusters
get-gw-addr
add-serviceentry "cluster-1" "b-svc" "127.255.0.25"
add-serviceentry "cluster-2" "b-svc" "123.255.0.15"

#  I want to load balance c across clusters
setup-routing-discovery-gw "cluster-1" "b"
setup-routing-discovery-gw "cluster-2" "b"

}



function setup-testbed-rbac-shared-gw {
# this works ok

kubectl config use-context "gke_${proj}_${zone}_cluster-1"
k apply -f res-clust1.yaml
k apply -f a-p.yaml
k apply -f c-p.yaml
k apply -f d-p.yaml
k apply -f a-svc-http.yaml
k apply -f c-svc-http.yaml
k apply -f d-svc-http.yaml

# we need the service b in cluster-1. Issue is that istio doesn't resolve b-svc to b-svc.default.global 
k apply -f b-svc-http.yaml

kubectl config use-context "gke_${proj}_${zone}_cluster-2"
k apply -f res-clust2.yaml
k apply -f b-b.yaml
k apply -f c-b.yaml
k apply -f d-b.yaml
k apply -f b-svc-http.yaml
k apply -f c-svc-http.yaml
k apply -f d-svc-http.yaml

setup-lb-c
setup-lb-d
setup-discovery-cluster1tob


}



#  
#setup-cluster "cluster-1"
#setup-cluster "cluster-2"
