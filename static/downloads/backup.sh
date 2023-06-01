#!/bin/bash

export RESTIC_REPOSITORY="TODO_YOUR_RESTIC_REPO"
export RESTIC_PASSWORD_FILE=/root/backup/.restic-pw.txt

# who will get an e-mail if some part of the backup has an error?
WARN_MAIL_RECP=("root")
# for a custom list (instead of "everyone who roots mails are
# redirected to in /etc/aliases"), instead use:
#WARN_MAIL_RECP=("foo@bar.example" "fu@fara.example")
# NOTE: if you don't want any emails sent, use an empty list, like this:
#WARN_MAIL_RECP=()

NUM_ERRORS=0

# helper function, prints current time in format "15:34:02"
mytime() {
    date +'%R:%S'
}

# helper function, called with an error string as argument
# checks if the last run command was successful (returned 0)
# otherwise increments NUM_ERRORS and prints the given error string
checklastcommand() {
    if [ $? != 0 ]; then
        NUM_ERRORS=$((NUM_ERRORS + 1))
        echo "$*"
    fi
}

# backs up just the data from OpenProject (and postgresql),
# feel free to remove this function if you don't use that
# !! if you *do* use OpenProject, uncomment the call !!
# !! to backupopenproject in backupallthethings()    !!
# based on:
# https://www.openproject.org/docs/installation-and-operations/operation/backing-up/
# https://www.openproject.org/docs/installation-and-operations/operation/restoring/
# (meaning, the restore instructions should work with this data,
#  except you'll copy the directories from the backup instead
#  of extracting them from a .tar.gz)
backupopenproject() {
    echo -e "\n$(mytime) Backing up OpenProject"

    systemctl stop openproject
    checklastcommand "ERROR: Stopping OpenProject service failed!"

    # remove old postgres-backup dir, recreate an empty one
    [ -e /tmp/postgres-backup/ ] && rm -r /tmp/postgres-backup/
    mkdir /tmp/postgres-backup
    chown postgres:postgres /tmp/postgres-backup
    
    echo "$(mytime) .. dumping PostgreSQL database for OpenProject backup"
    
    # this line is like described in the openproject docs
    su -l postgres -c "pg_dump -U postgres -d openproject -x -O \
        > /tmp/postgres-backup/openproject.sql"
    checklastcommand "ERROR: pg_dump for openproject.sql failed!"
    
    # this is just to be double-sure, so we have a backup of all postgres
    # tables, not just openproject (mostly redundant with openproject.sql,
    # but whatever, it's not that big..)
    su -l postgres -c "pg_dumpall > /tmp/postgres-backup/all.sql"
    checklastcommand "ERROR: pg_dumpall for all.sql failed!"

    echo "$(mytime) .. backing up OpenProject files"

    restic backup /var/db/openproject/files/ /tmp/postgres-backup/
    checklastcommand "ERROR: backing up OpenProject"

    # Note: we don't manage git/svn repos with openproject,
    # so those steps from the official docs are missing
    # also: /etc/openproject/ is backed up as part of
    #       /etc/ in an earlier backup step

    service openproject start
    checklastcommand "ERROR: Starting OpenProject service failed!"
}

# does all backup steps, prints messages to stdout
# (commands called by it might also print to stderr)
# in function so we can easily redirect all output to a logfile
backupallthethings() {
    echo "Running Backup at $(date +'%F %R:%S')"
    
    echo -e "\n$(mytime) Backing up /root/ and /etc/"

    # Debian/Ubuntu and -derivatives specific:
    # create a list of currently installed packages that
    # contains the versions etc
    dpkg -l > /root/backup/inst_packages.txt
    # create a second list of installed packages in a format suitable
    # for dpkg --set-selections (helpful when reinstalling a system:
    #  dpkg --set-selections < dpkg_selections.txt
    #  apt-get dselect-upgrade
    dpkg --get-selections > /root/backup/dpkg_selections.txt

    # backup all of /etc/, it's just a few MB and may come in handy
    # (also all of /root/, except for the cache folder which is
    #  actively used by restic when it's backing up)
    restic backup --exclude /root/.cache/ /root/ /etc/
    checklastcommand "ERROR: restic failed backing up /root/ and /etc"

    ##### Forgejo #####

    echo -e "\n$(mytime) Backing up Forgejo"

    # TODO: somehow check if someone is currently pushing
    #       before stopping the service? how?
    
    # flush forgejos queues
    su -l git -c "forgejo -c /etc/forgejo/app.ini -w /var/lib/forgejo \
        manager flush-queues"

    checklastcommand "ERROR: Flushing forgejo queues failed!"

    # stop the service, so we backup a consistent state
    systemctl stop forgejo
    checklastcommand "ERROR: Stopping forgejo service failed!"

    # Note: when using forgejo with sqlite, this also backs up the database
    # if you use postgres or mysql/mariadb, you need to do that
    # in an extra step (as shown in backupopenproject())
    restic backup /var/lib/forgejo/
    checklastcommand "ERROR: backing up /var/lib/forgejo failed!"

    # we're done backing up forgejo, start the service again
    systemctl start forgejo
    checklastcommand "ERROR: Starting forgejo service failed!"

    ##### OpenProject #####
    # uncomment the next line if you're using OpenProject
    #backupopenproject

    echo -e "\n$(mytime) Checking basic backup consistency with restic check"
    # Note: this does *not* read all the data on the backup server to ensure
    # that data files weren't damaged there (that would required downloading
    # it and thus take a long time and use up lots of traffic), but (AFAIK)
    # only checks the metadata and probably the size of the stored files.
    restic check
    if [ $? != 0 ]; then
      NUM_ERRORS=$((NUM_ERRORS + 1))
      echo "ERROR: restic check failed!"
      echo "  *might* be harmless, see https://restic.readthedocs.io/en/v0.15.2/faq.html"
    fi
    
    echo -e "\n$(mytime) Backup done!\n"
}

## actual execution of this script starts here:

# if there already is a backuplog.txt (from last run)
# rename it to backuplog-old.txt
if [ -e /root/backup/backuplog.txt ]; then
    mv /root/backup/backuplog.txt /root/backup/backuplog-old.txt
fi

# run the backupallthetings() function and write its output to backuplog.txt
# NOTE: using | tee backuplog.txt here would break the script,
#   $NUM_ERRORS isn't updated properly then!
backupallthethings > /root/backup/backuplog.txt 2>&1

if [ $NUM_ERRORS != 0 ]; then
    echo "$NUM_ERRORS errors during backup!"

    # if the list of mail recipients isn't emtpy,
    # send them a mail about the error
    if [ ${#WARN_MAIL_RECP[@]} != 0 ]; then
        # Note: this redirects everything printed within {  }
        #   to backuperrmail.txt
        {
          echo -n "Subject: WARNING: $NUM_ERRORS errors "
          echo "happened when trying to backup $(hostname)!\n"

          echo -e "Please see log below for details\n"
          cat /root/backup/backuplog.txt
        } > /tmp/backuperrmail.txt

        sendmail "${WARN_MAIL_RECP[@]}" < /tmp/backuperrmail.txt
    fi
fi

exit $NUM_ERRORS
