#!/bin/bash

########################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABILITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
########################################################################

LOG_FILE=/tmp/summary.log
function LogMsg() {
    echo $(date "+%a %b %d %T %Y") : ${1} >> ${LOG_FILE}
}

if [ $# -lt 2 ]; then
    echo -e "\nUsage:\n$0 server user"
    exit 1
fi

SERVER="$1"
USER="$2"
SOFTWARES="$3"
TEST_CONCURRENCY_THREADS=(1 2 4 8 16 32 64 128 256 512 1024)
max_concurrency_per_ab=4
max_ab_instances=16


if [ -e /tmp/summary.log ]; then
    rm -rf /tmp/summary.log
fi

distro="$(head -1 /etc/issue)"
web_server=
if [[ ${distro} == *"Ubuntu"* ]]
then
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo apt update"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo apt -y install sysstat zip" >> ${LOG_FILE}

    sudo apt update
    sudo apt -y install sysstat zip apache2-utils >> ${LOG_FILE}
    web_server="apache2"
elif [[ ${distro} == *"Amazon"* ]]
then
    sudo yum clean dbcache>> ${LOG_FILE}
    sudo yum -y install git sysstat zip httpd24-tools >> ${LOG_FILE}

    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo yum clean dbcache" >> ${LOG_FILE}
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo yum -y install git sysstat zip" >> ${LOG_FILE}
    web_server="httpd"
else
    LogMsg "Unsupported distribution: ${distro}."
fi
LogMsg "Start to install ${SOFTWARES} + WordPress"
ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "/tmp/install_${SOFTWARES}_wordpress.sh ${SERVER}" >> ${LOG_FILE}
if [ $? -ne 0 ]; then
    LogMsg "Failed to setup Wordpress, please check ${LOG_FILE} for details"
    exit 1
fi
sudo pkill -f ab
mkdir -p /tmp/wordpress
ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "mkdir -p /tmp/wordpress"
function run_ab ()
{
    current_concurrency=$1

    if [ ${current_concurrency} -le 2 ]
    then
        total_requests=50000
    elif [ ${current_concurrency} -le 128 ]
    then
        total_requests=100000
    else
        total_requests=200000
    fi

    ab_instances=$(($current_concurrency / $max_concurrency_per_ab))
    if [ ${ab_instances} -eq 0 ]
    then
        ab_instances=1
    fi
    if [ ${ab_instances} -gt ${max_ab_instances} ]
    then
        ab_instances=${max_ab_instances}
    fi

    total_request_per_ab=$(($total_requests / $ab_instances))
    concurrency_per_ab=$(($current_concurrency / $ab_instances))
    concurrency_left=${current_concurrency}
    requests_left=${total_requests}
    while [ ${concurrency_left} -gt ${max_concurrency_per_ab} ]; do
        concurrency_left=$(($concurrency_left - $concurrency_per_ab))
        requests_left=$(($requests_left - $total_request_per_ab))
        LogMsg "Running parallel ab command for: ${total_request_per_ab} X ${concurrency_per_ab}"
        ab -n ${total_request_per_ab} -r -s 60 -c ${concurrency_per_ab} http://${SERVER}/?p=1 & pid=$!
        PID_LIST+=" $pid"
    done

    if [ ${concurrency_left} -gt 0 ]
    then
        LogMsg "Running parallel ab command left for: ${requests_left} X ${concurrency_left}"
        ab -n ${requests_left} -r -s 60 -c ${concurrency_left} http://${SERVER}/?p=1 & pid=$!
        PID_LIST+=" $pid";
    fi
    trap "sudo kill ${PID_LIST}" SIGINT
    wait ${PID_LIST}
}

function run_wordpress_workload ()
{
    current_concurrency=$1

    LogMsg "======================================"
    LogMsg "Running wordpress test with current concurrency: ${current_concurrency}"
    LogMsg "======================================"

    ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "sar -n DEV 1 2>&1 > /tmp/wordpress/${current_concurrency}.sar.netio.log"
    ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "iostat -x -d 1 2>&1 > /tmp/wordpress/${current_concurrency}.iostat.diskio.log"
    ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "vmstat 1 2>&1 > /tmp/wordpress/${current_concurrency}.vmstat.memory.cpu.log"
    sar -n DEV 1 2>&1 > /tmp/wordpress/${current_concurrency}.sar.netio.log &
    iostat -x -d 1 2>&1 > /tmp/wordpress/${current_concurrency}.iostat.netio.log &
    vmstat 1 2>&1 > /tmp/wordpress/${current_concurrency}.vmstat.netio.log &

    run_ab ${current_concurrency} > /tmp/wordpress/${current_concurrency}.apache.bench.log

    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f sar"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f iostat"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f vmstat"
    sudo pkill -f sar
    sudo pkill -f iostat
    sudo pkill -f vmstat
    sudo pkill -f ab

    LogMsg "sleep 60 seconds"
    sleep 60
}

for threads in "${TEST_CONCURRENCY_THREADS[@]}"
do
    run_wordpress_workload ${threads}
done

LogMsg "Kernel Version : `uname -r`"
LogMsg "Guest OS : ${distro}"

cd /tmp
zip -r wordpress.zip . -i wordpress/* >> ${LOG_FILE}
zip -r wordpress.zip . -i summary.log >> ${LOG_FILE}

