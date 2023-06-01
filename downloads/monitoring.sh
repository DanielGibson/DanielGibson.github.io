#!/bin/bash

# who gets an email for new warnings?
WARN_MAIL_RECP=("root")
# for a custom list (instead of "everyone who roots mails are
# redirected to in /etc/aliases"), instead use:
#WARN_MAIL_RECP=("foo@bar.example" "fu@fara.example")
# NOTE: if you don't want any emails sent, use an empty list,
# like in the next line
#WARN_MAIL_RECP=()

# NOTE: adjust this to your server - ours has 16GB of RAM
#  and no swap, so if it runs below 900MB that's probably not good,
#  but if yours only has 2GB or so, you'll want a lower limit
LOW_MEM_WARNING_THRESHOLD=900

NUM_NEW_WARNINGS=0
NEW_CPU_WARNING=0
NEW_MEM_WARNING=0
NEW_DISK_WARNING=0

create_report() {
    
    echo "Running monitoring script at $(date +'%F %R:%S')"

    NUM_CPU_CORES=$(grep -c "cpu MHz" /proc/cpuinfo)

    read -r _ _ avg15min rest <<< "$(cat /proc/loadavg)"

    AVG_PER_CORE=$(bc -l <<< "$avg15min / $NUM_CPU_CORES")

    if [ $(bc -l <<< "$AVG_PER_CORE > 0.95") = "1" ]; then
        NEW_CPU_WARNING=1
        echo "High load in last 15 minutes: $AVG_PER_CORE per core!"
        echo "Details from top:"
        top -b -n 1 -o "%CPU" -c -w 512 | head -n 20
        echo # add empty line
    fi

    # /proc/meminfo has values in KB, convert to MB
    MEM_AVAILABLE_KB=$(grep "MemAvailable:" /proc/meminfo | grep -o "[0-9]*")
    MEM_AVAILABLE=$(( MEM_AVAILABLE_KB / 1000 ))

    if [ "$MEM_AVAILABLE" -lt $LOW_MEM_WARNING_THRESHOLD ]; then
        NEW_MEM_WARNING=1
        echo "low on main memory, only $MEM_AVAILABLE MB left!"
        echo "free -m:"
        free -m
        echo "Biggest offenders:"
        #ps aux --sort=-%mem | head
        top -b -n 1 -o "%MEM" -c -w 512 | head -n 20
        echo # add empty line
    fi

    DISKUSE_PERC=$(df --output=pcent / | tail -n 1 | grep -o "[0-9]*")

    if [ "$DISKUSE_PERC" -gt 85 ]; then
        NEW_DISK_WARNING=1
        echo "Disk is getting full, already $DISKUSE_PERC percent used!"
        lsblk -e 7 -T -o NAME,TYPE,FSTYPE,MOUNTPOINT,SIZE,FSSIZE,FSAVAIL,FSUSE%
        echo -e "\nBiggest offenders:"
        du -h --max-depth=6 -x / | sort -h -r | head -n 20
        echo # add empty line
    fi

    # TODO: what else could I check? some way to check for random errors? logs?
    
    NUM_NEW_WARNINGS=$((NEW_CPU_WARNING + NEW_MEM_WARNING + NEW_DISK_WARNING))
}

send_alert_mail() {
    echo "Sending an alert mail"

    {
      echo -n "Subject: Alert: $NUM_NEW_WARNINGS "
      echo -e "warnings while monitoring $(hostname)!\n"
      
      echo -e "Please see log below for details\n"
      cat /root/monitorlog.txt
    } > /tmp/monitormail.txt
    sendmail "${WARN_MAIL_RECP[@]}" < /tmp/monitormail.txt
    
    {
      echo "# this file is used by monitor.sh"
      echo "# to check which warnings are new"
      # unix timestamp from now (seconds since Epoch)
      echo "LAST_MAILTIME=$(date +'%s')"
      echo "LAST_CPU_WARNING=$NEW_CPU_WARNING"
      echo "LAST_MEM_WARNING=$NEW_MEM_WARNING"
      echo "LAST_DISK_WARNING=$NEW_DISK_WARNING"
    } > /tmp/lastmonitormailstate.sh
}

## actual execution of this script starts here:

# NOTE: can't use | tee here, if I do, create_report is run
#  in a new process and its modifications to the variables are lost
create_report > /root/monitorlog.txt 2>&1

if [ $NUM_NEW_WARNINGS != 0 ]; then
    echo "Alert! $NUM_NEW_WARNINGS new Warnings!"
    
    {
      echo "# this file is used by monitor.sh"
      echo "# to see for how long the system has been in a \"bad\" state"
      echo "LAST_BAD_CHECK_TIME=$(date +'%s')"
    } > /tmp/lastmonitorbadcheck.sh
    
    if [ ${#WARN_MAIL_RECP[@]} != 0 ]; then
        if [ ! -f /tmp/lastmonitormailstate.sh ]; then
            # no monitoring alert mail sent yet (since last reboot),
            # just send one now
            send_alert_mail
        else
            # we already sent a warning, only send a new one if there  
            # are new warnings or the old one was sent too long ago (>12h)
        
            # source lastmonitormailstate.sh to get LAST_* with
            # the state from last time we sent an alert mail
            . /tmp/lastmonitormailstate.sh
        
            NOW_TIME=$(date +'%s')
            SECONDS_SINCE_LAST_MAIL=$((NOW_TIME - LAST_MAILTIME))
            
            # 12h * 60min * 60sec = 43200 sec
            if [ $SECONDS_SINCE_LAST_MAIL -gt 43200 ] \
              || [ $NEW_CPU_WARNING -gt $LAST_CPU_WARNING ] \
              || [ $NEW_MEM_WARNING -gt $LAST_MEM_WARNING ] \
              || [ $NEW_DISK_WARNING -gt $LAST_DISK_WARNING ]
            then
                send_alert_mail
            fi
        fi
    fi # WARN_MAIL_RECP not empty

elif [ -f /tmp/lastmonitorbadcheck.sh ]; then
    # there were no warnings, but lastmonitorbadcheck.sh exists,
    # so there were warnings before. if the last bad check was
    # long enough ago, delete lastmonitorbadcheck.sh
    # so if a new warning (that's probably unrelated to the old one)
    # happens, a new mail is sent
    
    . /tmp/lastmonitorbadcheck.sh
    
    NOW_TIME=$(date +'%s')
    SECONDS_SINCE_LAST_MAIL=$((NOW_TIME - LAST_BAD_CHECK_TIME))
    # 60min*60sec = 3600sec
    if [ $SECONDS_SINCE_LAST_MAIL -gt 3600 ]; then
        rm /tmp/lastmonitorbadcheck.sh
    fi
fi

exit $NUM_NEW_WARNINGS
