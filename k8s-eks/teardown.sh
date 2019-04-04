#!/bin/bash

source login.sh
source eks-env.sh

: ${KUBE_CLUSTER_NAME:="streamsets-quickstart"}
if [ -z "$EKS_NODE_GROUP_NAME" ]; then EKS_NODE_GROUP_NAME=${KUBE_CLUSTER_NAME}-nodegrp-1; fi

# 1. Stop and Delete deployment if one is active
if [[ -f "deployment.id" && -s "deployment.id" ]];
  then
    deployment_id="`cat deployment.id`"
    # Stop deployment
    curl -s -X POST "${SCH_URL}/provisioning/rest/v1/deployment/${deployment_id}/stop" --header "Content-Type:application/json" --header "X-Requested-By:SDC" --header "X-SS-REST-CALL:true" --header "X-SS-User-Auth-Token:${SCH_TOKEN}"

    # Wait for deployment to become inactive
    deploymentStatus="ACTIVE"
    while [[ "${deploymentStatus}" != "INACTIVE" ]]; do
      echo "\nCurrent Deployment Status is \"${deploymentStatus}\". Waiting for it to become inactive"
      sleep 10
      deploymentStatus=$(curl -X POST -d "[ \"${deployment_id}\" ]" "${SCH_URL}/provisioning/rest/v1/deployments/status" --header "Content-Type:application/json" --header "X-Requested-By:SDC" --header "X-SS-REST-CALL:true" --header "X-SS-User-Auth-Token:${SCH_TOKEN}" | jq -r 'map(select([])|.status)[]')
    done

    # Delete deployment
    curl -s -X DELETE "${SCH_URL}/provisioning/rest/v1/deployment/${deployment_id}" --header "Content-Type:application/json" --header "X-Requested-By:SDC" --header "X-SS-REST-CALL:true" --header "X-SS-User-Auth-Token:${SCH_TOKEN}"

    rm -f deployment.id
fi

# 2. Delete and Unregister Control Agent if one is active
if [[ -f "agent.id" && -s "agent.id" ]]; then
  agent_id="`cat agent.id`"
  curl -X POST -d "[ \"${agent_id}\" ]" ${SCH_URL}/security/rest/v1/organization/${SCH_ORG}/components/deactivate --header "Content-Type:application/json" --header "X-Requested-By:SDC" --header "X-SS-REST-CALL:true" --header "X-SS-User-Auth-Token:${SCH_TOKEN}"
  curl -X POST -d "[ \"${agent_id}\" ]" ${SCH_URL}/security/rest/v1/organization/${SCH_ORG}/components/delete --header "Content-Type:application/json" --header "X-Requested-By:SDC" --header "X-SS-REST-CALL:true" --header "X-SS-User-Auth-Token:${SCH_TOKEN}"
  curl -s -X DELETE "${SCH_URL}/provisioning/rest/v1/dpmAgent/${agent_id}" --header "Content-Type:application/json" --header "X-Requested-By:SDC" --header "X-SS-REST-CALL:true" --header "X-SS-User-Auth-Token:${SCH_TOKEN}"
  rm -f agent.id
fi

echo Deconfigure Kubernetes
echo ... configuring kubectl
aws eks --region ${AWS_REGION} update-kubeconfig --name "${KUBE_CLUSTER_NAME}"

echo ... Set namespace
kubectl config set-context $(kubectl config current-context) --namespace=${KUBE_NAMESPACE}

echo ... Delete Authoring SDC Service
kubectl delete -f authoring-sdc-svc.yaml
echo "... Deleted Authoring sdc service"

# Delete agent
kubectl delete -f control-agent.yaml
echo "Deleted control agent"

# Configure & Delete traefik service
kubectl delete -f traefik-dep.yaml
echo "Deleted traefik ingress controller and service"

# Delete traefik configuration to handle https
kubectl delete configmap traefik-conf
echo "Deleted configmap traefik-conf"

# Delete all secrets
kubectl delete secret traefik-cert compsecret sch-agent-creds
echo "Deleted secret sch-agent-creds"

# Delete the certificate and key file
rm -f tls.crt tls.key

kubectl delete rolebinding streamsets-agent --namespace=${KUBE_NAMESPACE}
kubectl delete role streamsets-agent --namespace=${KUBE_NAMESPACE}
kubectl delete serviceaccount streamsets-agent --namespace=${KUBE_NAMESPACE}
kubectl delete clusterrolebinding traefik-ingress-controller
kubectl delete clusterrole traefik-ingress-controller
kubectl delete serviceaccount traefik-ingress-controller
kubectl delete clusterrolebinding cluster-admin-binding

kubectl delete namespace ${KUBE_NAMESPACE}
echo "Deleted Namespace ${KUBE_NAMESPACE}"



if [ -n "$KUBE_DELETE_CLUSTER" ]; then
  
  echo Deleting K8s Cluster
  echo ... deleting worker nodes
  aws cloudformation delete-stack --region=${AWS_REGION} --stack-name ${EKS_NODE_GROUP_NAME}
  echo ... waiting for worker nodes stack to delete
  aws cloudformation wait stack-delete-complete --region=${AWS_REGION} --stack-name ${EKS_NODE_GROUP_NAME}
 
  echo ... deleting cluster
  aws eks --region ${AWS_REGION} delete-cluster \
    --name "${KUBE_CLUSTER_NAME}" 

  echo ... waiting for cluster to delete
  aws eks --region ${AWS_REGION} wait cluster-deleted --name "${KUBE_CLUSTER_NAME}"

  echo ... deleting vpc
  aws cloudformation delete-stack --region=${AWS_REGION} --stack-name ${KUBE_CLUSTER_NAME}-vpc
  echo ... waiting for vpc stack to delete
  aws cloudformation wait stack-delete-complete --region=${AWS_REGION} --stack-name ${KUBE_CLUSTER_NAME}-vpc
#-----------------------------------------------------------------------------
fi
