#!/bin/bash
# 
# That script look for all hung fluentd pods on cluster with different envorinment DEV or PROD, redeploy them and delete all old ouput buffers as only them to reach count 33.
# Also, you can use it in CHECK mode for display count of output buffer files of fluentd pods with interval 10s. 
#
# Usage:
# SCRIPTNAME <dev|prod> - that command is redepoy all hung fluentd pods and delete all old output buffers.
# SCRIPTNAME <dev|prod> check - that command use for check count of ouput buffers on node
#
# Author: Pereskokov Vladimir


set -e

TS=$(date +'%H:%M:%S-%d:%m:%Y')
LOG="/opt/eco/paas-39/fluentd_fault.log"
OS_USER="Vladimir_Pereskokov@epam.com"
OS_PASS="****"
USAGE="\n
Wrong options \n
\n
Use:\n 
\n
SCRIPTNAME <dev|prod> - that command is redepoy all hung fluentd pods and delete all old output buffers. \n
\n
SCRIPTNAME <dev|prod> check - that command use for check count of ouput buffers on node\n"

case "$1" in
dev )
# 3.11 Dev
ANSIBLE_INVENTORY="/opt/eco/ansible/inventory-paas/inventories/hosts-paas-311-develop"
OS_HOST="https://web.paas.lab.epam.com:8443"
LOGGING_PROJ="openshift-logging"
;;
prod )
# 3.9 Prod
ANSIBLE_INVENTORY="/opt/eco/ansible/inventory-paas/inventories/hosts-paas-39"
OS_HOST="https://console.39.paas.epm-eco.projects.epam.com:8443"
LOGGING_PROJ="logging"
;;
*) 
echo -e $USAGE
exit 0
;;
esac

case "$2" in
check )
while true; do
echo "Check $1 environment..."
ansible nodes -u vladimir_pereskokov -i $ANSIBLE_INVENTORY -o -m shell -a "ls /var/lib/fluentd | wc -l "| awk '{if($8 > 32) { print "Node " tolower($1 " has " $8 " output buffers")}}'
sleep 10
done
exit 0
;;
*)
echo -e $USAGE
exit 0
;;
esac

os_status=$(oc whoami 2>&1|awk '{print $1}')
os_status_server=$(oc whoami --show-server)

# Provide valid OpenShift login
if [ $os_status == $OS_USER ]; then 
  if [ $os_status_server != $OS_HOST ]; then 
  oc logout 2> /dev/null
  oc login $OS_HOST -u $OS_USER -p $OS_PASS
  fi
else 
oc login $OS_HOST -u $OS_USER -p $OS_PASS 
fi

oc project $LOGGING_PROJ
os_context=$(oc whoami --show-context)
echo "$TS - $os_context" > $LOG

# if flunentd output buffers count will reach to 33, it pod will considered is hung
fault_nodes=$(ansible nodes -u vladimir_pereskokov -i $ANSIBLE_INVENTORY -o -m shell -a "ls /var/lib/fluentd | wc -l "| \
awk '{if($8 > 32) { print tolower($1)}}')
count_of_fault_pods=${#fault_nodes[@]}
#echo "Num of fault pods is $count_of_fault_pods"

if [ $count_of_fault_pods > 0 ]; then
  
i=0
for node in ${fault_nodes[@]}; do
  ((i=i+1))
  fault_pod=$(oc adm manage-node --list-pods $node 2>/dev/null | grep fluentd | awk '{print $2}')
  echo "$i) Node $node has a hung fluentd pod $fault_pod" | tee -a $LOG
  # Delete old buffers and hung pods
  ssh vladimir_pereskokov@$node sudo rm -f /var/lib/fluentd/*
  oc delete pod $fault_pod --wait=false
done
echo "All hung fluentd pods were deleted" >> $LOG
fi

oc logout

exit 0
