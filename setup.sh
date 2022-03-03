#!/bin/sh

#LOGGING
# Redirect stdout and stderr to logfile
logfile="$PWD/$(date +"%m%d%Y_%k.%M.%S")_zabbix_install.log"


# Create Logger
log(){
        timestamp=$(date +"%m-%d-%Y %k:%M:%S")
        echo "$timestamp $1"
        echo "$timestamp $1" >> $logfile 2>&1
}

#PREREQUISITE 

#Add zabbix local user
#modify the password according to your needs
log "********** Add local user ********** "
username=zabbix
password=PASSWORD

adduser --gecos "" --disabled-password $username
chpasswd <<<"$username:$password"

#install ssh server
log "********** Install ssh ********** "
apt install openssh-server >> $logfile 2>&1

log "********** Check ssh service status"
systemctl status sshd >> $logfile 2>&1

log "********** Enable ssh service startup ********** "
systemctl enable ssh >> $logfile 2>&1

log "Disable root login via ssh"
echo "sed '0,/^.*PermitRootLogin.*$/s//PermitRootLogin no/' /etc/ssh/sshd_config" >> $logfile 2>&1

#VARIABLES FOR ZABBIX INSTALL
# Zabbix server configuration
zabbixconf="/usr/local/etc/zabbix_server.conf"
servername="SERVERNAME"

#Configure users password
# MySQL root password
rootDBpass="PASSWORD"

# Zabbix user MySQL password
zabbixDBpass="PASSWORD"

# MySQL database monitoring user
monitorDBpass="PASSWORD"

#LET'S GO WITH ZABBIX
#Install Zabbix from repo
log "********** Install Zabbix from repo ********** "
wget https://repo.zabbix.com/zabbix/6.0/debian/pool/main/z/zabbix-release/zabbix-release_6.0-1+debian11_all.deb >> $logfile 2>&1
dpkg -i zabbix-release_6.0-1+debian11_all.deb >> $logfile 2>&1
apt update >> $logfile 2>&1
apt install zabbix-server-mysql zabbix-frontend-php zabbix-nginx-conf zabbix-sql-scripts zabbix-agent >> $logfile 2>&1

# Install database
log "********** Install database ********** "
apt -y install mariadb-server >> $logfile 2>&1
systemctl start mariadb >> $logfile 2>&1
systemctl enable mariadb >> $logfile 2>&1

# Configure SQL installation
mysql --user=root <<_EOF_
ALTER USER 'root'@'localhost' IDENTIFIED BY '${rootDBpass}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
CREATE DATABASE zabbix CHARACTER SET UTF8 COLLATE UTF8_BIN;
CREATE USER 'zabbix'@'%' IDENTIFIED BY '${zabbixDBpass}';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'%';
CREATE USER 'zbx_monitor'@'%' IDENTIFIED BY '${monitorDBpass}';
GRANT USAGE,REPLICATION CLIENT,PROCESS,SHOW DATABASES,SHOW VIEW ON *.* TO 'monitorDBpass'@'%';
FLUSH PRIVILEGES;
_EOF_

#Import database schema for Zabbix server
log "********** Import database schema for Zabbix server ********** "
zcat /usr/share/doc/zabbix-sql-scripts/mysql/server.sql.gz | mysql -uzabbix -p'zabbixDBpass' zabbix >> $logfile 2>&1

#Configure the database for Zabbix server
log "********** Configure the database password for Zabbix server ********** "
sed -i "s/# DBPassword=/DBPassword=$zabbixDBpass/g" "$zabbixconf" >> $logfile 2>&1


#Start Zabbix server and agent processes and make it start at system boot
log "********** Removing default website ********** "
rm /etc/niginx/sites-enabled/default

log "********** Restarting nginx and starting Zabbix Server... ********** "
systemctl restart zabbix-server zabbix-agent nginx php7.4-fpm >> $logfile 2>&1
systemctl enable zabbix-server zabbix-agent nginx php7.4-fpm >> $logfile 2>&1

#END 
ZABBIX_IP=$(ip addr show | grep -v "127.0.0.1/8" | grep -o 'inet [0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+' | grep -o [0-9].*)
echo You can connect to http:\\$ZABBIX_IP to access Zabbix


