#!/bin/bash


# Скрипт автоматизирует настройку модуля резервирования по схеме 1 + 1
# Запускается на машинах с чистым SoftWLC 1.37
#
# master-ip=<ip_адрес_master>       : Добавляется при запуске скрипта на машине slave
# slave-ip=<ip_адрес_slave>         : Добавляется при запуске скрипта на машине master
# virtual-ip=<virtual_ip>           : Добавляется при запуске на обеих машинах

# Прервать установку при ошибках
set -e

# Настройки MYSQL пользователя для сервисов
export MYSQL_USER="javauser"
export MYSQL_PASSWORD="javapassword"

# Public Eltex production repo
ELTEX_PUBLIC_REPO="http://archive.eltex-co.ru/wireless"
# Private (internal) repo
ELTEX_PRIVATE_REPO="secret"
# Переменная, которая является рабочей. Внутри скрипта работа идёт с ней в зависимости от параметров вызова скрипта
ELTEX_REPO=${ELTEX_PUBLIC_REPO}

# узнать кодовое имя дистрибутива и записать lowercase
tmp_str=$(lsb_release -cs)
DISTRIB_CODENAME="${tmp_str,,}"

# Массив внешних IP сервера (весь ifconfig, кроме 127.0.0.1)
EXTERNAL_IPS=()

FIRST_SERVER_IP=""

# 1 - если сервер является master нодой при установке модуля резервирования, 0 - если slave
IS_MASTER=0

IP_MASTER=""
IP_SLAVE=""

# ip адрес второго сервера при установке модуля резервирования
SECOND_SERVER_IP=""

VIRTUAL_IP=""
DEFAULT_GW_IP=""

PROXYSQL_PACKAGE="proxysql_2.5.2-debian10_amd64.deb"

WAIT_BETWEEN_STEPS=5

red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr 0)

restart() {
  service "$@" restart
}

# Выполняет $1 как SQL-запрос
sql_exec() {
  mysql -uroot -proot -e "$1" >/dev/null
  return $?
}

function select_gw_ip() {
  local __resultvar=$1
  ans=""
  echo ${green}"Enter default gateway address"${reset}
  read ans
  validate_server_ip $ans
  eval ${__resultvar}=$ans
}

# Запросить у пользователя внешний IP из EXTERNAL_IPS.
# В $1 функция возвращает значение IP (не индекс)
function select_ip() {
  local __resultvar=$1
  ans=""
  while true; do
    read ans
    if [[ (${ans} -gt 0) && (${ans} -lt ${#EXTERNAL_IPS[@]}+1) ]]; then
      break
    else
      echo "Wrong IP number. Try again"
    fi
  done
  eval ${__resultvar}="${EXTERNAL_IPS[ans - 1]}"
}

# Узнать внешние IP сервера и, если их несколько, предложить пользователю выбор.
# В $1 функция возвращает окончательное значение внешнего IP
function detect_external_ip() {
  local __resultvar=$1
  case ${#EXTERNAL_IPS[@]} in
  0)
    echo "No external IP addresses have been detected"
    host="127.0.0.1"
    ;;
  1)
    echo "External IP address has been detected"
    host=${EXTERNAL_IPS[0]}
    ;;
  *)
    echo "Several external IPs have been detected:"
    for index in "${!EXTERNAL_IPS[@]}"; do
      echo "$(($index + 1)). ${EXTERNAL_IPS[index]}"
    done
    echo "Which one will be used for reservation?"
    select_ip host
    ;;
  esac
  eval ${__resultvar}="${host}"
}

# Заполнить массив EXTERNAL_IPS внешними IP сервера
# Для IPv4 — весь ifconfig, кроме 127.0.0.1
function find_external_ipv4_ips() {
  # Debian & U20 не содержат утилиту ifconfig (net-tools) в базовой поставке
  # local ifconfig="$(ifconfig | grep -Po '(?<=inet\s)[^\s]*')"
  local ipv4_addresses=$(ip -4 addr | grep inet | awk -F '[ \t]+|/' '{print $3}' | grep -v ^127.0.0.1)
  for address in ${ipv4_addresses}; do
    # Контроль, что адрес получился валидным. Если нет, то пробуем дополнительно очистить
    if ! valid_ip $address; then
      address="$(echo $address | grep -oE '((1?[0-9][0-9]?|2[0-4][0-9]|25[0-5])\.){3}(1?[0-9][0-9]?|2[0-4][0-9]|25[0-5])')"
    fi
    # Если после очистки всё ОК, то включаем строку в выходной массив, за исключением localhost (127.0.0.1)
    if (valid_ip $address) && [[ ! (${address} == "127.0.0.1") ]]; then
      EXTERNAL_IPS+=($address)
    fi
  done
}

# Функция по добавлению и настройке модуля резервирования
function setup_reservation_module() {
    install_keepalived
    replication_mysql
    install_proxysql
    enable_airtune_reservation
    install_rsync
    synchronyze_eltex_doors_tokens
    setup_pcrf_cluster_mode
    change_localhost_in_cfgs
}

# Установка и настройка keepalived
function install_keepalived() {
    apt install -y keepalived

    wget ${ELTEX_REPO}/reservation/keepalived/keepalived.conf -O /etc/keepalived/keepalived.conf || true
    wget ${ELTEX_REPO}/reservation/keepalived/keep_notify.sh -O /etc/keepalived/keep_notify.sh || true
    wget ${ELTEX_REPO}/reservation/keepalived/check_ping.sh -O /etc/keepalived/check_ping.sh || true
    chmod +x /etc/keepalived/keep_notify.sh /etc/keepalived/check_ping.sh

# Конфигурация keepalived
    local interface=$(ip ro | grep ${FIRST_SERVER_IP} | awk -- '{print $3}')

    sed -i 's/<interface>/'${interface}'/g' /etc/keepalived/keepalived.conf
    sed -i 's/<virtual_ip>/'${VIRTUAL_IP}'/g' /etc/keepalived/keepalived.conf
    sed -i 's/<ip_адрес_другого_сервера>/'${SECOND_SERVER_IP}'/g' /etc/keepalived/keepalived.conf

    sed -i 's/<default_gw_ip>/'${DEFAULT_GW_IP}'/g' /etc/keepalived/check_ping.sh

# Выделение лога в отдельный файл
    if [[ $DISTRIB_CODENAME == "1.7_x86-64" ]]; then
      echo "filter f_keepalived {
                    program(\"Keepalived\");
                  };

                  destination d_keepalived {
                    file(\"/var/log/keepalived.log\");
                  };

                  log {
                    source(s_src);
                    filter(f_keepalived);
                    destination(d_keepalived);
                    flags(final);
                  };" | tee /etc/syslog-ng/conf.d/30-keepalived.conf
      chmod 644 /etc/syslog-ng/conf.d/30-keepalived.conf
      chgrp root /etc/syslog-ng/conf.d/30-keepalived.conf
      chown root /etc/syslog-ng/conf.d/30-keepalived.conf
      restart syslog-ng
    else
      echo "if \$programname contains 'Keepalived' then /var/log/keepalived.log" | tee /etc/rsyslog.d/10-keepalived.conf
      echo "if \$programname contains 'Keepalived' then ~" | tee -a /etc/rsyslog.d/10-keepalived.conf

      sed -i '/^\s*\$PrivDropToUser\s\+syslog/s/^/#/' "/etc/rsyslog.conf"
      sed -i '/^\s*\$PrivDropToGroup\s\+syslog/s/^/#/' "/etc/rsyslog.conf"
      systemctl unmask rsyslog
      restart rsyslog
    fi
}

function replication_mysql() {
  sql_exec "GRANT ALL ON *.* TO '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}'"
  sql_exec "GRANT ALL ON eltex_auth_service.* TO '${MYSQL_USER}'@'%'"
  sql_exec "GRANT ALL ON radius.* TO '${MYSQL_USER}'@'%'"
  sql_exec "GRANT ALL ON wireless.* TO '${MYSQL_USER}'@'%'"
  sql_exec "GRANT ALL ON Syslog.* TO '${MYSQL_USER}'@'%'"
  sql_exec "GRANT ALL ON eltex_doors.* TO '${MYSQL_USER}'@'%'"
  sql_exec "GRANT ALL ON eltex_ngw.* TO '${MYSQL_USER}'@'%'"
  sql_exec "GRANT ALL ON ELTEX_PORTAL.* TO '${MYSQL_USER}'@'%'"
  sql_exec "GRANT ALL ON eltex_ems.* TO '${MYSQL_USER}'@'%'"
  sql_exec "GRANT ALL ON eltex_alert.* TO '${MYSQL_USER}'@'%'"
  sql_exec "GRANT ALL ON eltex_bruce.* TO '${MYSQL_USER}'@'%'"
  sql_exec "GRANT ALL ON eltex_pcrf.* TO '${MYSQL_USER}'@'%'"
  sql_exec "GRANT ALL ON eltex_wids.* TO '${MYSQL_USER}'@'%'"
  sql_exec "GRANT ALL ON eltex_wifi_customer_cab.* TO '${MYSQL_USER}'@'%'"
  sql_exec "GRANT ALL ON eltex_jobs.* TO '${MYSQL_USER}'@'%'"
  sql_exec "GRANT ALL ON eltex_sorm2.* TO '${MYSQL_USER}'@'%'"
  sql_exec "GRANT ALL ON eltex_ott.* TO '${MYSQL_USER}'@'%'"
  sql_exec "GRANT ALL ON eltex_jerry.* TO '${MYSQL_USER}'@'%'"
  sql_exec "GRANT ALL ON acscache.* TO '${MYSQL_USER}'@'%'"
  sql_exec "FLUSH PRIVILEGES"

  sed -i 's/^USER=.*/USER="replication"/' /etc/eltex-ems/check-ems-replication.conf
  sed -i 's/^PASSWORD=.*/PASSWORD="password"/' /etc/eltex-ems/check-ems-replication.conf

  # Меняем порт mysql
  new_port=5890
  file_name="/etc/mysql/mariadb.cnf"
  if grep -q "^port=" "$file_name"; then
      sed -i "s/^port=.*/port=$new_port/" "$file_name"
  else
      echo "port=$new_port" >> "$file_name"
  fi

  wget ${ELTEX_REPO}/reservation/50-server.cnf -O /etc/mysql/mariadb.conf.d/50-server.cnf


  if [[ ${IS_MASTER} == 1 ]]; then
    sql_exec "GRANT SELECT, SUPER, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'replication'@'$SECOND_SERVER_IP' IDENTIFIED BY 'password';"
    sql_exec "GRANT SELECT, SUPER, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'replication'@'$FIRST_SERVER_IP' IDENTIFIED BY 'password';"
    sql_exec "FLUSH PRIVILEGES";
  else
    sed -i 's/server-id              = 1/server-id              = 2/' /etc/mysql/mariadb.conf.d/50-server.cnf
    sql_exec "GRANT SELECT, SUPER, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'replication'@'$SECOND_SERVER_IP' IDENTIFIED BY 'password';"
    sql_exec "GRANT SELECT, SUPER, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'replication'@'$FIRST_SERVER_IP' IDENTIFIED BY 'password';"
    sql_exec "FLUSH PRIVILEGES";
  fi

  restart mysql

  sql_exec "STOP SLAVE;"
  sql_exec "CHANGE MASTER TO MASTER_HOST='${SECOND_SERVER_IP}', MASTER_PORT=5890, MASTER_USER='replication', MASTER_PASSWORD='password', MASTER_USE_GTID=slave_pos;"
  sql_exec "START SLAVE;"

  sed -i 's/ENABLE_REPLICATION="No"/ENABLE_REPLICATION="Yes"/g' /etc/eltex-ems/check-ems-replication.conf
  sed -i 's/^HOST1=.*/HOST1='${FIRST_SERVER_IP}'/g' /etc/eltex-ems/check-ems-replication.conf
  sed -i 's/^HOST2=.*1/HOST2='${SECOND_SERVER_IP}'/g' /etc/eltex-ems/check-ems-replication.conf
}

# Установка и настройка proxysql
function install_proxysql() {
    wget ${ELTEX_REPO}/reservation/${PROXYSQL_PACKAGE}
    dpkg -i ${PROXYSQL_PACKAGE}

    wget ${ELTEX_REPO}/reservation/proxysql.cnf -O /etc/proxysql.cnf || true
    wget ${ELTEX_REPO}/reservation/read_only_switch.sh -O /var/lib/proxysql/read_only_switch.sh || true
    chmod +x /var/lib/proxysql/read_only_switch.sh

    if [[ ${IS_MASTER} == 1 ]]; then
      IP_MASTER=$FIRST_SERVER_IP
      IP_SLAVE=$SECOND_SERVER_IP
    else
      IP_MASTER=$SECOND_SERVER_IP
      IP_SLAVE=$FIRST_SERVER_IP
    fi

    sed -i 's/<IP MASTER>/'${IP_MASTER}'/g' /etc/proxysql.cnf /var/lib/proxysql/read_only_switch.sh
    sed -i 's/<IP SLAVE>/'${IP_SLAVE}'/g' /etc/proxysql.cnf /var/lib/proxysql/read_only_switch.sh

    mysql -uroot -proot -e "CREATE USER IF NOT EXISTS 'monitor'@'%' IDENTIFIED BY 'monitor';"
    mysql -uroot -proot -e "GRANT USAGE, REPLICATION CLIENT ON *.* TO 'monitor'@'%';"

    restart proxysql
    sleep ${WAIT_BETWEEN_STEPS}

#  Изменение порта взаимодействия SoftWLC с Proxysql
    mysql -uadmin -padmin -P 6032 -h 127.0.0.1 -e "update global_variables set variable_value = '0.0.0.0:3306' where variable_name = 'mysql-interfaces'"
    mysql -uadmin -padmin -P 6032 -h 127.0.0.1 -e "SAVE MYSQL VARIABLES TO DISK"
    restart proxysql
}

# Настройка rsync
function install_rsync() {

  apt install rsync
#  Редактирование конфигурации
  sed -i 's/RSYNC_ENABLE=false/RSYNC_ENABLE=true/g' /etc/default/rsync

# rsync daemons
  wget ${ELTEX_REPO}/reservation/rsyncd.conf -O /etc/rsyncd.conf || true
  sed -i 's/<ip_адрес_другого_сервера>/'${SECOND_SERVER_IP}'/g' /etc/rsyncd.conf
  sed -i 's/<virtual_ip>/'${VIRTUAL_IP}'/g' /etc/rsyncd.conf

# Настройки аутентификации
  sudo echo "backup:rspasswd" | sudo tee /etc/rsyncd.secrets
  chmod 600 /etc/rsyncd.secrets
  echo "rspasswd" | sudo tee /etc/rsync_client.secrets && sudo chmod 600 /etc/rsync_client.secrets

  # Начиная с версии rsync 3.2.0 добавлена по умолчанию защита каталога /usr, /boot, /home (защиту home в дальнейшем убрали)
  # Решением является переопределение защищающей опции rsync.
  # Только для Ubuntu 22
    if [[ $DISTRIB_CODENAME == "jammy" ]]; then
      mkdir -p /etc/systemd/system/rsync.service.d
      { echo "[Service]"; echo "ProtectSystem=off"; } | tee /etc/systemd/system/rsync.service.d/override.conf
      systemctl daemon-reload
    fi


# Конфигурация скрипта для  eltex-radius/eltex-radius-nbi, синхронизация сертификатов
  if [[ ${IS_MASTER} == 1 ]]; then
    echo "export SLAVE_HOST="${SECOND_SERVER_IP}"" | sudo tee /etc/environment && source /etc/environment
    rsync -rlogtp --delete-after --password-file=/etc/rsync_client.secrets /var/lib/eltex-radius-nbi/ backup@$SLAVE_HOST::radius-nbi-certs > /tmp/rsync_radius_nbi_certs.log 2>&1
    rsync -rlogtp --delete-after --password-file=/etc/rsync_client.secrets /etc/eltex-radius/certs/ backup@$SLAVE_HOST::radius-certs > /tmp/rsync_radius_certs.log 2>&1
    restart eltex-radius
  fi

# Конфигурация скрипта для  eltex-ems
  sed -i 's/<ip_server2>/'${SECOND_SERVER_IP}'/g' /usr/lib/eltex-ems/scripts/rsync_ems_backup.sh

  sed -i 's/tomcat.host=127.0.0.1/tomcat.host='${VIRTUAL_IP}'/g' /etc/eltex-radius-nbi/radius_nbi_config.txt

# Cоздание задач в cron на обоих серверах, для запуска синхронизации раз в минуту:
  crontab -l | { cat; echo "*/1 * * * * /usr/lib/eltex-ems/scripts/rsync_ems_backup.sh"; } | crontab
  crontab -l | { cat; echo "*/1 * * * * /usr/lib/eltex-radius-nbi/rsync_radius_cert_synchronization.sh"; } | crontab
  crontab -l | { cat; echo "*/1 * * * * /usr/lib/eltex-airtune/scripts/rsync_airtune_backup.sh"; } | crontab

  service rsync start
}

function enable_airtune_reservation() {
  sed -i 's/"vrrp_enabled": 0/"vrrp_enabled": 1/' /etc/eltex-airtune/airtune.conf

  mkdir -p /usr/lib/eltex-airtune/scripts
  wget ${ELTEX_REPO}/reservation/rsync_airtune_backup.sh -O /usr/lib/eltex-airtune/scripts/rsync_airtune_backup.sh || true
  sed -i 's/<ip_адрес_другого_сервера>/'${SECOND_SERVER_IP}'/g' /usr/lib/eltex-airtune/scripts/rsync_airtune_backup.sh
}

# Синхронизация токенов сервиса eltex-doors
function synchronyze_eltex_doors_tokens() {
  if [[ $IS_MASTER == 1 ]]; then
    rsync -rlogtp --delete-after --password-file=/etc/rsync_client.secrets /etc/eltex-doors/keys/  backup@${SLAVE_HOST}::doors-certs
  fi
}

function setup_pcrf_cluster_mode() {
  sed -i 's/192.168.0.1/'${FIRST_SERVER_IP}'/g' /etc/eltex-pcrf/hazelcast-cluster-network.xml
  sed -i 's/192.168.0.2/'${SECOND_SERVER_IP}'/g' /etc/eltex-pcrf/hazelcast-cluster-network.xml
  sed -i 's/"cluster.enable" : false/"cluster.enable" : true/g' /etc/eltex-pcrf/eltex-pcrf.json
}

# Замена хоста mysql/mariadb с localhost на 127.0.0.1
# для корректной работы ProxySQL
function change_localhost_in_cfgs() {
  local DB_CONFIG_LINE
# eltex-ems
  sed -i 's/localhost/127.0.0.1:3306/g' /usr/lib/eltex-ems/conf/config.txt
# eltex-pcrf
  sed -i 's/localhost\//127.0.0.1:3306\//g' /etc/eltex-pcrf/eltex-pcrf.json
# softwlc-nbi
  sed -i 's/localhost\//127.0.0.1:3306\//g' /etc/eltex-radius-nbi/radius_nbi_config.txt
  sed -i 's/localhost:3306/127.0.0.1:3306/g' /etc/eltex-radius-nbi/radius_nbi_config.txt
# eltex-wifi-cab
  sed -i 's/localhost:3306/127.0.0.1:3306/g' /etc/eltex-wifi-cab/application.properties
# eltex-bruce
  sed -i 's/localhost:3306/127.0.0.1:3306/g' /etc/eltex-bruce/application.properties
# eltex-jobs
  sed -i 's/127.0.0.1\//127.0.0.1:3306/g' /etc/eltex-jobs/application.properties
# eltex-portal-constructor
  DB_CONFIG_LINE=$(( $(grep -n "database {" /etc/eltex-portal-constructor/application.conf | cut -d: -f1) + 1))
  sed -i '1,'${DB_CONFIG_LINE}' s/localhost/127.0.0.1/' /etc/eltex-portal-constructor/application.conf
# eltex-portal
  DB_CONFIG_LINE=$(( $(grep -n "database {" /etc/eltex-portal/application.conf | cut -d: -f1) + 1))
  sed -i '1,'${DB_CONFIG_LINE}' s/localhost/127.0.0.1/' /etc/eltex-portal/application.conf
# eltex-ngw
  DB_CONFIG_LINE=$(( $(grep -n "database {" /etc/eltex-ngw/application.conf | cut -d: -f1) + 1))
  sed -i '1,'${DB_CONFIG_LINE}' s/localhost/127.0.0.1/' /etc/eltex-ngw/application.conf
# eltex-doors
  DB_CONFIG_LINE=$(( $(grep -n "database {" /etc/eltex-doors/application.conf | cut -d: -f1) + 1))
  sed -i '1,'${DB_CONFIG_LINE}' s/localhost/127.0.0.1/' /etc/eltex-doors/application.conf
# eltex-mercury
  DB_CONFIG_LINE=$(( $(grep -n "database {" /etc/eltex-mercury/application.conf | cut -d: -f1) + 1))
  sed -i '1,'${DB_CONFIG_LINE}' s/localhost/127.0.0.1/' /etc/eltex-mercury/application.conf
# eltex-logging-service
  sed -i 's/localhost/127.0.0.1/g' /etc/eltex-logging-service/application.conf
# eltex-freeradius3
  sed -i 's/localhost/127.0.0.1/g' /etc/eltex-radius/local.conf

}


# Делает валидацию аргумента и прерывает выполнение скрипта.
# Если адрес не валиден или '127.0.0.1', то скрипт прерывается с ошибкой
function validate_server_ip() {
# Формальная проверка на правильность адреса
  if ! valid_ip $1; then
    echo "${red}Server IP addr argument is invalid: '$1', script aborted${reset}"
    exit 1
  fi

  # Проверка, что это не localhost (так как этот адрес приведёт пользователя браузера на собственный ПК)
  if [[ $1 == "127.0.0.1" || $1 == "::1" ]]; then
    echo "${red}Cannot assign localhost IP '$1' to server IP address; script aborted${reset}"
    exit 1
  fi
}
# IP FUNCTIONS SECTION START
# Валидация IP адреса через regex
function valid_ip() {
  local ip=$1
  local stat=1

  if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    OIFS=$IFS
    IFS='.'
    ip=($ip)
    IFS=$OIFS
    [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]

    stat=$?
  fi
  return $stat
}

update_repo_related_vars() {
  REPO_GPG_KEY_ADDR="${ELTEX_REPO}/repo.gpg.key"
}


# MAIN SCRIPT FLOW START
# Самое первое - это запрет работы не от root
if [[ $(id -u) -ne 0 ]]; then
  echo "${red}This script can only be run as root${reset}"
  exit 1
fi

# Читаем и применяем аргументы командной строки
if [[ -n "$1" ]]; then
  for i in "$@"; do
    if [[ ${i} == "--private" ]]; then
      ELTEX_REPO=${ELTEX_PRIVATE_REPO}
      update_repo_related_vars
    fi

    ## Master ip settings (reservation module only)
    if [[ ${i} =~ "master-ip=" ]]; then
      SECOND_SERVER_IP=$(echo ${i} | cut -d "=" -f 2)
      # Валидация на корректность ip адреса. Если ошибка, то выход из скрипта.
      validate_server_ip $SECOND_SERVER_IP
    fi

    ## Slave ip settings (reservation module only)
    if [[ ${i} =~ "slave-ip=" ]]; then
      IS_MASTER=1
      SECOND_SERVER_IP=$(echo ${i} | cut -d "=" -f 2)
      # Валидация на корректность ip адреса. Если ошибка, то выход из скрипта.
      validate_server_ip $SECOND_SERVER_IP
    fi

    ## Virtual ip settings (reservation module only)
    if [[ ${i} =~ "virtual-ip=" ]]; then
      VIRTUAL_IP=$(echo ${i} | cut -d "=" -f 2)
      # Валидация на корректность ip адреса. Если ошибка, то выход из скрипта.
      validate_server_ip $VIRTUAL_IP
    fi
  done

  if [[ $SECOND_SERVER_IP == "" ]]; then
    echo "${red}Флаг master-ip или slave-ip не был указан. Работа скрипта прекращена.${reset}"
    exit 1
  fi

  if [[ $VIRTUAL_IP == "" ]]; then
      echo "${red}Флаг virtual-ip не был указан. Работа скрипта прекращена.${reset}"
      exit 1
  fi

fi

find_external_ipv4_ips
detect_external_ip FIRST_SERVER_IP
select_gw_ip DEFAULT_GW_IP

setup_reservation_module

  echo
  echo "-------------------------------------------------------------------------"
  echo
  echo ${green} "Настройка модуля резервирования завершена успешно."${reset}

# Подсказка для перезапуска сервисов на втором сервере для синхронизации токенов eltex-doors
if [[ ${IS_MASTER} == 1 ]]; then
  echo
  echo "-------------------------------------------------------------------------"
  echo
  echo ${red} "Для корректной работы модуля резервирования на сервере Slave необходимо перезапустить следующие сервисы:" ${reset}
  echo
  echo ${green} " sudo service eltex-disconnect-service restart
  sudo service eltex-johnny restart" ${reset}
  echo
  echo "-------------------------------------------------------------------------"
  echo
  echo ${green} "Перейдите к веб-интерфейсу личного кабинета на каждом сервере, адрес
 \"http://<ip-адрес сервера>:8080/wifi-cab\", внутри личного кабинета перейдите во вкладку \"Сервисы и тарифы\".
 Редактировать ничего не требуется, при переходе в указанный раздел ЛК -  записи об удаленных токенах сгенерируются в БД повторно." ${reset}
fi
