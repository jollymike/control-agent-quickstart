#!/bin/bash
((Sx+=1));export Sx; echo ${Sin:0:Sx} Running common-startup-services-agent.sh on cluster ${KUBE_CLUSTER_NAME}

${COMMON_DIR}/common-kubectl-connect.sh

echo K8S Cluster Name: ${KUBE_CLUSTER_NAME}
echo K8S Namespace: ${KUBE_NAMESPACE}
echo Agent name: ${SCH_AGENT_NAME}

#######################
# Setup Control Agent #
#######################
echo Setup Control Agent

# 1. Get a token for Agent from SCH and store it in a secret
echo ... Get a token for Agent from SCH and store it in a secret
AGENT_TOKEN_CURL=$(curl -s -X PUT -d "{\"organization\": \"${SCH_ORG}\", \"componentType\" : \"provisioning-agent\", \"numberOfComponents\" : 1, \"active\" : true}" ${SCH_URL}/security/rest/v1/organization/${SCH_ORG}/components --header "Content-Type:application/json" --header "X-Requested-By:SDC" --header "X-SS-REST-CALL:true" --header "X-SS-User-Auth-Token:${SCH_TOKEN}")
CURL_ISSUES=$(echo ${AGENT_TOKEN_CURL} | jq ".ISSUES")
if [ ! -z "$CURL_ISSUES" ]; then
  echo "ERROR: Problem encountered while requesting agent token: $CURL_ISSUES"
  exit
fi
AGENT_TOKEN=$(echo ${AGENT_TOKEN_CURL} | jq '.[0].fullAuthToken')

if [ -z "$AGENT_TOKEN" ]; then
  echo "ERROR: Failed to retrieve control agent token."
  exit 1
else
  echo "   Agent token successfully retrieved"
fi
echo ... Create secret from agent token
kubectl create secret generic ${SCH_AGENT_NAME}-creds \
    --from-literal=dpm_agent_token_string=${AGENT_TOKEN} \
    || { echo 'ERROR: Failed to create SCH credentials secret in Kubernetes' ; exit 1; }

# 2. Create secret for agent to store key pair
echo ... Create secret for agent to store key pair
kubectl create secret generic ${SCH_AGENT_NAME}-compsecret \
|| { echo 'ERROR: Failed to create agent keypair secret in Kubernetes' ; exit 1; }

# 3. Create config map to store configuration referenced by the agent yaml
echo ... Create config map to store configuration referenced by the agent yaml
agent_id=$(uuidgen)
echo ${agent_id} > agent-${SCH_AGENT_NAME}.id
kubectl create configmap ${SCH_AGENT_NAME}-config \
    --from-literal=org=${SCH_ORG} \
    --from-literal=sch_url=${SCH_URL} \
    --from-literal=agent_id=${agent_id} \
    || { echo 'ERROR: Failed to create configmap in Kubernetes' ; exit 1; }

# 4. Launch Agent
echo ... Launch Agent
cat ${COMMON_DIR}/control-agent.yaml | envsubst > ${PWD}/_tmp_control-agent.yaml
#exit
#cat control-agent.yaml | envsubst | sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g' > ${PWD}/_tmp_control-agent.yaml
kubectl create -f ${PWD}/_tmp_control-agent.yaml || { echo 'ERROR: Failed to launch Streamsets Control Agent in Kubernetes' ; exit 1; }

#if [ ! -z "${SCH_FWRULE_ADDAGENT}" ] ; then
#  echo "... wait for agent pod to reach running status."
#  while true ; do
#    sch_agent_pod_status=$(kubectl get pod -l app=agent -o jsonpath="{.items[0].status.phase}")
#    if [ "${sch_agent_pod_status}" == "Running" ] ; then
#      break
#    fi
#    echo DEBUG status is ${sch_agent_pod_status}
#    sleep 5
#  done
#
#  echo "... Getting egress IP of Agent pod."
#  sch_agent_pod=$(kubectl get pod -l app=agent -o jsonpath="{.items[0].metadata.name}")
#  kubectl exec -it $sch_agent_pod apk add curl
#  sch_agent_ip=$(kubectl exec -it $sch_agent_pod curl ifconfig.me)
#  echo ${sch_agent_ip} >> egress-${SCH_AGENT_NAME}-ips.txt
#  echo agent ip is ${sch_agent_ip}
#fi

# 5. wait for agent to be registered with SCH
echo ... wait for agent to be registered with SCH
temp_agent_Id=""
while [ -z $temp_agent_Id ]; do
  sleep 10
  curl -L "${SCH_URL}/provisioning/rest/v1/dpmAgents?organization=${SCH_ORG}" --header "Content-Type:application/json" --header "X-Requested-By:SDC" --header "X-SS-REST-CALL:true" --header "X-SS-User-Auth-Token:${SCH_TOKEN}" | jq -r "map(select(any(.id; contains(\"${agent_id}\")))|.id)[]"
  temp_agent_Id=$(curl -L "${SCH_URL}/provisioning/rest/v1/dpmAgents?organization=${SCH_ORG}" --header "Content-Type:application/json" --header "X-Requested-By:SDC" --header "X-SS-REST-CALL:true" --header "X-SS-User-Auth-Token:${SCH_TOKEN}" | jq -r "map(select(any(.id; contains(\"${agent_id}\")))|.id)[]")
done
echo "DPM Agent \"${temp_agent_Id}\" successfully registered with SCH"

#######################################
# Create Deployment                   #
#######################################
${COMMON_DIR}/common-startup-services-deployment.sh 01

echo ${Sout:0:Sx} Exiting common-startup-services-agent.sh on cluster ${KUBE_CLUSTER_NAME} ; ((Sx-=1));export Sx;
