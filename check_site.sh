#!/bin/bash
#Verificar um HTTPS
#Felipe Ferreira set 2013
#rev. 08/2016 - add better output and sed to change , to . on timeto

URL=$1
KEY=$2
CRIT=$3
http_proxy=""
https_proxy=""

LOG="/var/log/lighttpd/check_badguy.log"
TMPN="/tmp/ntstat.tmp"
MAXCON=20
MAXTIMEOUT=10
#DEBUG=0

if [ -z $CRIT ]; then
   echo "Usage $0 <URL> <KEYWORD> <TIMEOUT> <noproxy>"
   exit 3
fi


function down() {
  date  |tee -a $LOG
  echo "CRITICAL - Site took to longer then $CRIT to respond, $MSGOK"  |tee -a $LOG
  netstat -nta |grep WAIT |grep ":80"  |grep -v "127.0.0.1" |awk '{ print $5 }' > $TMPN
  echo "NETSTAT RESULT $TMPN"
  CT=$(wc -l $TMPN)
  echo "WAIT CONNECTIONS: $CT" |tee -a $LOG
  if [  "$CT"  ]; then
#get IP and put in iptables rule to block it then restart apache and network
#another way is to get "turned away. Too many connections." on /var/log/lighttpd/error.log
  IP=$(cat $TMPN |awk -F":" '{ print $1}' |sort |uniq -c |sort -rn |head -n 1 |awk '{print $NF}')
  echo "IP $IP"
  if [ $IP ]; then
   echo "Blocking IP $IP" |tee -a $LOG
   /bin/cp -fv /etc/sysconfig/iptables /etc/sysconfig/iptables.bkp
   iptables-save > /etc/sysconfig/iptables
   sed -i "9i -A INPUT -s ${IP}/32 -p tcp --dport 80 -j DROP" /etc/sysconfig/iptables
   iptables-restore -c < /etc/sysconfig/iptables
   iptables -L |tee -a $LOG
   service lighttpd restart  |tee -a $LOG
#Send an email
   echo "SITE DOWN felipeferreira.net bad IP $IP" |/bin/mail -s "Site restarted" -a $LOG -r "felipe@mail.net"  fel@mail.com


  else
  echo "Could not get an offend IP" |tee -a $LOG
  fi
 else
  echo "Not maxcon $MAXCON"|tee -a $LOG
 fi
 exit 2
}


TC=`echo ${URL} | awk -F. '{print \$1}' |awk -F/ '{print \$NF}'`
R=$(echo $((1 + RANDOM % 1000)))
TMP="/tmp/check_http_sh_${R}_${TC}.tmp"
touch $TMP

CMD_TIME="curl -m $MAXTIMEOUT -k --location --no-buffer --silent --output ${TMP} -w %{time_connect}:%{time_starttransfer}:%{time_total} '${URL}'"

#echo $CMD_TIME
TIME=$(eval $CMD_TIME)
#echo "Done CMD"
if [ -f $TMP ]; then
   RESULT=`grep -c $KEY $TMP`
   TIMETOT=`echo $TIME | gawk  -F: '{ print \$3 }' |sed 's/,/./g'`
else
   echo "ERROR - Could not create tmp file $TMP" |tee -a $LOG
   echo $TIME |tee -a $LOG
   down
fi

if [ ! -z $DEBUG ]; then
echo "CMD_TIME: $CMD_TIME"
echo "NUMBER OF $KEY FOUNDS:  $RESULT"
echo "TIMES: $TIME"
echo "TIME TOTAL: $TIMETOT"
echo "TMP: $TMP"
ls $TMP
fi

rm -f $TMP

SURL=`echo $URL | cut -d "/" -f3-4`

MSGOK="Site $SURL key $KEY time $TIMETOT |'time'=${TIMETOT}s;${CRIT}"
MSGKO="Site $SURL has problems, time $TIMETOT |'time'=${TIMETOT}s;${CRIT}"

#PERFDATA HOWTO 'label'=value[UOM];[warn];[crit];[min];[max]

#CHECK IF KEYWORD IS FOUND
if [[ "$RESULT" -lt "1" ]]; then
 down
fi

#CHECK IF TIME IS OK
if [[ $(echo "$TIMETOT < $CRIT"|bc) = 1 ]]; then
   exit 0
else
 down
fi
