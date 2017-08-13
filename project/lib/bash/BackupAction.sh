#!/bin/bash
################################################################################
# Backup Session - LDAP/Mailbox/DistList/Alias
################################################################################

################################################################################
# __backupFullInc: All the functions used by backup Full and Incremental
# Options:
#    $1 - The account to be backed up
#    $2 - The type of object should be backed up. Valid values:
#        ACOBJECT - User Account;
################################################################################
function __backupFullInc(){
  ldap_backup $1 $2
  if [ $ERRCODE -eq 0 ]; then
    mailbox_backup $1
    if [ $ERRCODE -eq 0 ]; then
      if [[ $SESSION_TYPE == 'TXT' ]]; then
        echo $SESSION:$1:$(date +%m/%d/%y) >> $TEMPSESSION
      elif [[ $SESSION_TYPE == "SQLITE3" ]]; then
        DATE=$(date +%Y-%m-%dT%H:%M:%S.%N)
        SIZE=$(du -h $WORKDIR/$i* | awk {'print $1'})
        sqlite3 $WORKDIR/sessions.sqlite3 "insert into session_account (email,sessionID,account_size) values ('$1','$SESSIONID','$SIZE')" > /dev/null
      fi
    fi
  fi
}

################################################################################
# __backupLdap: All the functions used by LDAP, distribution list, and alias backup
# Options:
#    $1 - The list of accounts to be backed up
#    $2 - The type of object should be backed up. Valid values:
#        DLOBJECT - Distribution List;
#        ACOBJECT - User Account;
#        ALOBJECT - Alias;
################################################################################
function __backupLdap(){
  ldap_backup $1 $2
  if [ $ERRCODE -eq 0 ]; then
    if [[ $SESSION_TYPE == 'TXT' ]]; then
      echo $SESSION:$1:$(date +%m/%d/%y) >> $TEMPSESSION
    elif [[ $SESSION_TYPE == "SQLITE3" ]]; then
      DATE=$(date +%Y-%m-%dT%H:%M:%S.%N)
      SIZE=$(du -h $WORKDIR/$i* | awk {'print $1'})
      sqlite3 $WORKDIR/sessions.sqlite3 "insert into session_account (email,sessionID,account_size) values ('$1','$SESSIONID','$SIZE')" > /dev/null
    fi
  fi
}

################################################################################
# __backupMailbox: All the functions used by mailbox backup
# Options:
#    $1 - The list of accounts to be backed up
#    $2 - The type of object should be backed up. Valid values:
#        ACOBJECT - User Account;
################################################################################
function __backupMailbox(){
  mailbox_backup $1 $2
  if [ $ERRCODE -eq 0 ]; then
    if [[ $SESSION_TYPE == 'TXT' ]]; then
      echo $SESSION:$1:$(date +%m/%d/%y) >> $TEMPSESSION
    elif [[ $SESSION_TYPE == "SQLITE3" ]]; then
      DATE=$(date +%Y-%m-%dT%H:%M:%S.%N)
      SIZE=$(du -h $WORKDIR/$i* | awk {'print $1'})
      sqlite3 $WORKDIR/sessions.sqlite3 "insert into session_account (email,sessionID,account_size) values ('$1','$SESSIONID','$SIZE')" > /dev/null
    fi
  fi
}

################################################################################
# backup_main: Backup accounts based on SESSION and STYPE
# Options:
#    $1 - The type of object should be backed up. Valid values:
#        DLOBJECT - Distribution List;
#        ACOBJECT - User Account;
#        ALOBJECT - Alias;
#    $2 - The filter used by LDAP to search for a type of object. Valid values:
#        DLFILTER - Distribution List (Use together with DLOBJECT);
#        ACFILTER - User Account (Use together with ACOBJECT);
#        ALFILTER - Alias (Use together with ALOBJECT).
#    $3 - The list of accounts to be backed up
################################################################################
function backup_main()
{
  # Create a list of all accounts to be backed up
  if [ -z $3 ]; then
    build_listBKP $1 $2
  else
    for i in $(echo "$3" | sed 's/,/\n/g'); do
      echo $i >> $TEMPACCOUNT
    done
  fi

  # If $TEMPACCOUNT is not empty, do a backup, if not do nothing
  if [ -s $TEMPACCOUNT ]; then
    notify_begin $SESSION $STYPE
    logger -i -p local7.info "Zmbackup: Backup session $SESSION started on $(date)"
    echo "Backup session $SESSION started on $(date)"
    if [[ $SESSION_TYPE == 'TXT' ]]; then
      echo "SESSION: $SESSION started on $(date)" >> $TEMPSESSION
    elif [[ $SESSION_TYPE == "SQLITE3" ]]; then
      DATE=$(date +%Y-%m-%dT%H:%M:%S.%N)
      sqlite3 $WORKDIR/sessions.sqlite3 "insert into backup_session(sessionID,initial_date,type,status) values ('$SESSION','$DATE','$SIZE','$STYPE','IN PROGRESS')"
    fi
    if [[ "$SESSION" == "full"* ]] || [[ "$SESSION" == "inc"* ]]; then
      cat $TEMPACCOUNT | parallel --no-notice --jobs $MAX_PARALLEL_PROCESS \
                         '__backupFullInc {} $1'
    elif [[ "$SESSION" == "mbox"* ]]; then
      cat $TEMPACCOUNT | parallel --no-notice --jobs $MAX_PARALLEL_PROCESS \
                         '__backupMailbox {} $1'
    else
      cat $TEMPACCOUNT | parallel --no-notice --jobs $MAX_PARALLEL_PROCESS \
                         '__backupLdap {} $1'
    fi
    mv "$TEMPDIR" "$WORKDIR/$SESSION" && rm -rf "$TEMPDIR"
    if [[ $SESSION_TYPE == 'TXT' ]]; then
      echo "SESSION: $SESSION completed in $(date)" >> $TEMPSESSION
      cat $TEMPSESSION >> $WORKDIR/sessions.txt
    elif [[ $SESSION_TYPE == "SQLITE3" ]]; then
      DATE=$(date +%Y-%m-%dT%H:%M:%S.%N)
      SIZE=$(du -h $WORKDIR/$i | awk {'print $1'})
      sqlite3 $WORKDIR/sessions.sqlite3 "update backup_session set conclusion_date='$DATE',size='$SIZE',status='FINISHED' where sessionID='$SESSION'"
    fi
    logger -i -p local7.info "Zmbackup: Backup session $SESSION finished on $(date)"
    echo "Backup session $SESSION finished on $(date)"
  else
    echo "Nothing to do. Closing..."
    exit 2
  fi
}
