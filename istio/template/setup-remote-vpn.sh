


export PILOT_POD_IP=$(kubectl -n istio-system get pod -l istio=pilot -o jsonpath='{.items[0].status.podIP}')
export POLICY_POD_IP=$(kubectl -n istio-system get pod -l istio=mixer -o jsonpath='{.items[0].status.podIP}')
export TELEMETRY_POD_IP=$(kubectl -n istio-system get pod -l istio-mixer-type=telemetry -o jsonpath='{.items[0].status.podIP}')

echo "pilot pod ip is ${PILOT_POD_IP}"
echo "policy pod ip is ${POLICY_POD_IP}"
echo "telemetry pod ip is ${TELEMETRY_POD_IP}"


helm template install/kubernetes/helm/istio --namespace istio-system \
--name istio-remote \
--values install/kubernetes/helm/istio/values-istio-remote.yaml \
--set global.remotePilotAddress=${PILOT_POD_IP} \
--set global.remotePolicyAddress=${POLICY_POD_IP} \
--set global.remoteTelemetryAddress=${TELEMETRY_POD_IP} > $HOME/istio-remote.yaml

kubectl create ns istio-system

kubectl apply -f $HOME/istio-remote.yaml

kubectl label namespace default istio-injection=enabled


