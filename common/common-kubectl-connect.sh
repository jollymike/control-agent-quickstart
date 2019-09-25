#!/bin/bash
((Sx+=1));export Sx; echo ${Sin:0:Sx} Running common-kubectl-connect.sh

echo "Switching Kubectl to Context (${KUBE_CLUSTER_NAME}) and Namespace (${KUBE_NAMESPACE})"
kubectl config use-context ${KUBE_CLUSTER_NAME} --namespace=${KUBE_NAMESPACE} || { echo 'ERROR: Failed to swtich kubectl context' ; exit 1; }

echo ${Sout:0:Sx} Exiting common-kubectl-connect.sh ; ((Sx-=1));export Sx;
