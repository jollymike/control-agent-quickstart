#!/bin/bash

source eks-env.sh
source login.sh

######################
# Initialize
######################

: ${KUBE_CLUSTER_NAME:="streamsets-quickstart"}
if [ -z ${SCH_AGENT_NAME+x} ]; then export SCH_AGENT_NAME=${KUBE_CLUSTER_NAME}-schagent01; fi
if [ -z "$EKS_NODE_GROUP_NAME" ]; then EKS_NODE_GROUP_NAME=${KUBE_CLUSTER_NAME}-nodegrp-1; fi

#TODO Confirm Kubtcl current Config is correct.

${COMMON_DIR}/teardown-services.sh

if [ "$KUBE_DELETE_CLUSTER" == "1" ]; then
  #Destroy K8s Cluster

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
else
  #Clean up K8s config
  ${COMMON_DIR}/common-teardown-services.sh

fi

#Clean up kubectl config
kubectl config unset users.`kubectl config view -o jsonpath='{.users[*].name}' | tr " " "\n" | grep ${KUBE_CLUSTER_NAME}`
kubectl config unset clusters.`kubectl config get-clusters | grep ${KUBE_CLUSTER_NAME}`
kubectl config unset context.`kubectl config get-contexts -o name | grep ${KUBE_CLUSTER_NAME}`
