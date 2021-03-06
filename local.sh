#!/bin/bash

# This script is run locally on BDOC, connects to the remote attack boxes, and run remote.sh

# Set colors for terminal output
NC='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
ORANGE='\033[0;33m'

# Sweet ASCII art \m/
echo -en $RED"
 (    (   (      (     )   (  )   (     
 )\ ) )\ ))\ )   )\ )  *   )  *   )  
(()/((()/(()/(  (()/(  )  /(  )  /(  
 /(_))/(_))(_))  /(_))( )(_))( )(_)) 
(_))_(_))(_))   (_)) (_(_())(_(_()) "
echo -en $GREEN " 
| |_ |_ _/ __|  | _ \|_   _||_   _|  
| __| | |\__ \  |  _/  | |    | |    
|_|  |___|___/  |_|    |_|    |_|    
"
echo -en $BLUE"
 __            __                                 
/ _\ ___  __ _/ _\ ___ __ _ _ __  _ __   ___ _ __ 
\ \ / _ \/ _\` \ \ / __/ _\` | '_ \| '_ \ / _ \ '__|
_\ \  __/ (_| |\ \ (_| (_| | | | | | | |  __/ |   
\__/\___|\__, \__/\___\__,_|_| |_|_| |_|\___|_|   
         |___/                                   
"$NC
echo -en $RED"
 _                 _           _     
| | ___   ___ __ _| |      ___| |__  
| |/ _ \ / __/ _\` | |     / __| '_ \ 
| | (_) | (_| (_| | |  _  \__ \ | | |
|_|\___/ \___\__,_|_| (_) |___/_| |_|

"$NC

# Check if script is being run as root
if [[ $EUID -ne 0 ]]; then
    echo -e $RED"[!] This script must be run as root!"$NC;
    exit 1;
fi

# Print usage information
function usage() {
    echo -e $ORANGE"Usage: $0: RBU_NAME PPS IP_LIST\n$GREEN"
    echo -e "The$ORANGE RBU_NAME$GREEN parameter is the name of the$ORANGE Risk Business Unit$GREEN, and should not contain any spaces."
    echo -e "The$ORANGE PPS$GREEN parameter is the number of$ORANGE packets per second$GREEN masscan will send to the target IPs."
    echo -e "The$ORANGE IP_LIST$GREEN parameter is the$ORANGE list of IP addresses$GREEN to be scanned. The file should contain one IP per line.\n"
    echo -e $BLUE"This script connects to various NPT attack boxes and performs a 65535 port scan of a provided list"
    echo -e "of IP addresses via masscan. It SCPs the list of IPs to each attack box and kicks off scanning"
    echo -e "by invoking the remote.sh script on each attack box. The results are then parsed on the attack box"
    echo -e "and sent via SCP back to the local machine. The outputs and directory structures are as follows:\n"
    echo -e $GREEN"local machine\n$ORANGE\tSegmentation_Scan_RBUName_Year_Month/\n\t\tParsedTCP_ATTACKBOX_hh:mm:ss.txt\n\t\tParsedUDP_ATTACKBOX_hh:mm:ss.txt"
    echo -e $GREEN"remote attack boxes\n$ORANGE\tengagements/\n\t\tSegmentation_Scan_RBUName_Year_Month/"
    echo -e "\t\t\tParsedTCP_ATTACKBOX_hh:mm:ss.txt\n\t\t\tParsedUDP_ATTACKBOX_hh:mm:ss.txt"
    echo -e "\t\t\tTCP_hh:mm:ss.log\n\t\t\tUDP_hh:mm:ss.log\n"
    echo -e $GREEN"The masscan command used on the remote machines:"
    echo -e $BLUE"masscan --rate 10000 -v -n -Pn -sS -p1-65535 -iL IPAddresses.txt "
    echo -e $GREEN"\nFor more information on masscan, see$ORANGE https://github.com/robertdavidgraham/masscan\n"
    echo -e $RED"WARNING: MASSCAN CAN SEND A VERY LARGE AMOUNT OF TRAFFIC AND KNOCK BOXES OVER. PLEASE CHOOSE YOUR PPS VALUE WITH CARE!"$NC
}

# Check for correct number of parameters
if [ "$#" -ne 3 ]; then
    echo -e $RED"[!] Wrong number of parameters! See usage below.\n"$NC;
    usage;
    exit 1;
fi

# Save script parameters
RBU=$1
PPS=$2
IPLIST=$3

# Change spaces to underscores
RBU=${RBU// /_}

# Use regex to make sure PPS is a whole number
re='^[0-9]+$'
if ! [[ $PPS =~ $re ]] ; then
    echo -e $RED"[!] The packets per second parameter must be a whole number!"$NC;
    usage;
   exit 1;
fi

# Check that IPLIST file exists
if [ ! -f $3 ]; then
    echo -e $RED"[!] The IP list file provided does not exist!\n"$NC;
    usage;
    exit 1;
fi

# Create local directory for scan results. Reuse old directory if possible
ENGAGEMENTS="/root/engagements/"
WORKINGDIR="Segmentation_Scan_local_${RBU}_$(date +%Y)_$(date +%m)"
TCPLOG="TCP_$(date +%H:%M:%S).log"
UDPLOG="UDP_$(date +%H:%M:%S).log"

if [ ! -d "${ENGAGEMENTS}${WORKINGDIR}" ]; then
    echo -e "$GREEN[*] ${ORANGE}The working directory is ${ENGAGEMENTS}${WORKINGDIR}. It does not exist, so it is being created.$NC";
    sleep 0.7;
    mkdir -p ${ENGAGEMENTS}${WORKINGDIR};
else
    echo -e "$GREEN[*] ${ORANGE}The working directory ${ENGAGEMENTS}${WORKINGDIR} already exists and will be reused.$NC";
    sleep 0.7;
fi

# Kick off scans via SSH
for host in $(cat hosts); do
    scp ${IPLIST} root@${host}:/root

    # If SCP fails, bail out
    if [ $? -ne 0 ]; then
        echo -e "$RED[*] Could not SCP IP address list to remote host ${host}. Quitting!$NC";
        sleep 1;
        exit 1;
    else
        ssh -t $host "./remote.sh $RBU $PPS ~/${IPLIST} ${TCPLOG} ${UDPLOG}"
        sleep 10;
    fi
done

sleep 2;
echo -e "$GREEN[*] ${ORANGE}Done running remote commands!$NC";
sleep 2;

# SCP results back
WORKINGDIRREMOTE="Segmentation_Scan_remote_${RBU}_$(date +%Y)_$(date +%m)"

for host in $(cat hosts); do
    scp root@${host}:${ENGAGEMENTS=}${WORKINGDIRREMOTE}/${TCPLOG} ./${host}-${TCPLOG}

    # If SCP fails, bail out
    if [ $? -ne 0 ]; then
        echo -e "$RED[*] Could not retrieve TCP logs from ${host}!$NC";
        sleep 1;
    fi

    scp root@${host}:${ENGAGEMENTS=}${WORKINGDIRREMOTE}/${UDPLOG} ./${host}-${UDPLOG}

    # If SCP fails, bail out
    if [ $? -ne 0 ]; then
        echo -e "$RED[*] Could not retrieve UDP logs from ${host}!$NC";
        sleep 1;
    fi
done

# # Parse TCP results
# # Get unique hosts
# cat ${ENGAGEMENTS}${WORKINGDIR}/${UDPLOG} | grep -v '#' | cut -d " " -f 4 | sort | uniq > hosts
# echo -e "$GREEN[*] ${ORANGE}Hosts found:$NC";
# cat hosts;
# sleep 1;

# # Get unique ports for each host in hosts, save as IPaddress.txt
# for host in $(cat hosts); do
#     cat ${ENGAGEMENTS}${WORKINGDIR}/${UDPLOG} | grep $host | cut -d " " -f 3 | sort | uniq >> ${host}.txt
#     cat ${host}.txt;
#     sleep 1;
# done

# # Change newlines to ", ", echo final output to results file, remove old .txt files
# for host in $(cat hosts); do
#     tr '\r\n' ',' < ${host}.txt > ${host}-2.txt;
#     sed 's/,/, /g' ${host}-2.txt > ${host}-3.txt;
#     echo "$host [ $(cat ${host}-3.txt)]" >> results
#     rm ${host}.txt ${host}-2.txt ${host}-3.txt
# done