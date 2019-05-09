

function k () { kubectl "$@"; }
function kx () { kubectx "$@"; }

kx "cilium19"
k delete deployment --all
k delete svc --all
k delete CiliumNetworkPolicy --all

kx "cilium20"
k delete deployment --all
k delete svc --all
k delete CiliumNetworkPolicy --all
