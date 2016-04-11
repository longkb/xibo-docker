#!/bin/bash

if [ "$XIBO_DEV_MODE" == "true" ]
then
  # Print MySQL connection details
  echo "MySQL Connection Details:"
  echo "Username: root"
  echo "Password: $MYSQL_ENV_MYSQL_ROOT_PASSWORD"
  echo "Host: mysql"
  echo ""
  echo "XMR Connection Details:"
  echo "Host: $XMR_HOST"
  echo "CMS Port: 50001"
  echo "Player Port: 9505"
  echo ""
  echo "Starting Webserver"
  /usr/local/bin/httpd-foreground
  exit $?
fi

# Detect if we're going to run an upgrade
if [ -e "/CMS-FLAG" ]
then
  if [ -e "/var/www/xibo/web/settings.php" ]
  then
    # Run a database backup
    dbuser=$(awk -F "'" '/\$dbuser/ {print $2}' /tmp/settings.php)
    dbpass=$(awk -F "'" '/\$dbpass/ {print $2}' /tmp/settings.php)
    dbname=$(awk -F "'" '/\$dbpass/ {print $2}' /tmp/settings.php)
    
    mysqldump -h mysql -u $dbuser -p$dbpass $dbname | gzip > /var/www/backup/$(date +"%Y-%m-%d_%H-%M-%S").sql.gz

    # Backup the settings.php file
    mv /var/www/xibo/web/settings.php /tmp/settings.php
    
    # Delete the old install EXCEPT the library directory
    find /var/www/xibo ! -name library -type d -exec rm -rf {};
    find /var/www/xibo -type f --max-depth=1 -exec rm -f {};

    # Replace settings
    mv /tmp/settings.php /var/www/xibo/web/settings.php
  else
    # When the mysql container is re-bootstrapped, it's password
    # remains the same so cache a copy in this file so we know what
    # it is if we ever need it in the future.
    echo $MYSQL_ENV_MYSQL_ROOT_PASSWORD > /var/www/backup/.mysql-root-password
    chmod 400 /var/www/backup/.mysql-root-password
  fi
  
  tar --strip=1 -zxf /var/www/xibo-cms.tar.gz -C /var/www/xibo --exclude=settings.php
  chown www-data.www-data -R /var/www/xibo/web
  chown www-data.www-data -R /var/www/xibo/install
  mkdir /var/www/xibo/cache
  mkdir /var/www/xibo/library
  chown www-data.www-data -R /var/www/xibo/cache /var/www/xibo/library
  
  if [ ! -e "/var/www/xibo/web/settings.php" ]
  then
    # This is a fresh install so bootstrap the whole
    # system
    echo "New install"
    
    # Sleep for a few seconds to give MySQL time to initialise
    echo "Waiting for MySQL to start - max 300 seconds"
    /usr/local/bin/wait-for-it.sh -q -t 300 mysql:3306
    
    if [ ! "$?" == 0 ]
    then
      echo "MySQL didn't start in the allocated time" > /var/www/backup/LOG
    fi
    
    # Safety sleep to give MySQL a moment to settle after coming up
    sleep 1
    
    # Create database
    MYSQL_USER_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    mysql -u root -p$MYSQL_ENV_MYSQL_ROOT_PASSWORD -h mysql -e "CREATE DATABASE cms"
    mysql -D cms -u root -p$MYSQL_ENV_MYSQL_ROOT_PASSWORD -h mysql -e "SOURCE /var/www/xibo/install/master/structure.sql"
    mysql -D cms -u root -p$MYSQL_ENV_MYSQL_ROOT_PASSWORD -h mysql -e "SOURCE /var/www/xibo/install/master/data.sql"
    mysql -D cms -u root -p$MYSQL_ENV_MYSQL_ROOT_PASSWORD -h mysql -e "SOURCE /var/www/xibo/install/master/constraints.sql"
    
    mysql -u root -p$MYSQL_ENV_MYSQL_ROOT_PASSWORD -h mysql -e "GRANT ALL PRIVILEGES ON cms.* TO 'cms_user'@'%' IDENTIFIED BY '$MYSQL_USER_PASSWORD'; FLUSH PRIVILEGES;"
    echo $MYSQL_USER_PASSWORD > /var/www/backup/.mysql-user-password
    chmod 400 /var/www/backup/.mysql-user-password    
        
    # Write settings.php

    # Set LIBRARY_LOCATION

    # Set admin username/password (passed in)

    # Set XMR public/private address
    
    # Configure MySQL Backup
  
  fi
  rm /CMS-FLAG
fi

/usr/local/bin/httpd-foreground