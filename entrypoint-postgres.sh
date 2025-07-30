#!/bin/bash
source /backup/.env

echo "$CRON cd /backup/ && bash postgres.sh"  > /etc/cron.d/backup
chmod 0644 /etc/cron.d/backup
crontab /etc/cron.d/backup
cat /etc/cron.d/backup >/proc/1/fd/1

cron -f