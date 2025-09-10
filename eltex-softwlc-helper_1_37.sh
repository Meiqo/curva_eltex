#!/bin/bash

# Скрипт помогает установить пакеты SoftWLC на один сервер
# Предварительно устанавливает Java, mysql-server, curl, libcurl и прочие необходимые пакеты из зависимостей
# Затем последовательно устанавливает все нужные пакеты комплекса:
#
# eltex-oui-list           : Содержит список соответствий MAC-адресов и производителей оборудования
# eltex-ems-db             : Разворачивает схему в БД MySQL для EMS
# eltex-radius-db          : Разворачивает схему в БД MySQL для RADIUS-сервера
# eltex-auth-service-db    : Разворачивает схему в БД MySQL для сервиса авторизации
# eltex-ems                : Серверная и клиентская часть СУ EMS
# eltex-radius             : RADIUS-сервер
# eltex-radius-nbi         : Северный мост (northbound) для стыка SoftWLC с вышестоящими OSS/BSS
# eltex-ngw                : Сервис, предоставляющий возможность отправки уведомлений (СМС, звонков), используемый другими пакетами комплекса
# eltex-apb                : Сервис для взаимодействия точек доступа
# eltex-pcrf               : Служба управления политиками доступа (используется BRAS)
# eltex-mercury            : Сервис по управлению Hotspot пользователями
# eltex-portal             : Портал для авторизации клиентов WiFi в схеме 'Hotspot'
# eltex-portal-constructor : Web-приложение для создания и редактирования порталов для авторизации
# eltex-wifi-cab           : Личный кабинет оператора услуги Wi-Fi
# eltex-doors              : Обеспечивает авторизацию пользователя/сервиса внутри ядра (внутреннее взаимод.)
# eltex-bruce              : Сервис-планировщик задач, обеспечивает запуск задач по установленному расписанию
# eltex-jobs               : Сервис-исполнитель задач, выполняет задачи, запущенные eltex-bruce
# eltex-disconnect-service * : Сервис обеспечивает немедленное прерывание сессии пользователя
# eltex-johnny *             : REST API к Mercury для управления Enterprise и Hotspot пользователями
# eltex-logging-service *    : Микросервис журналирования операций
# eltex-airtune *            : Сервис обеспечивает RRM (Radio Resource Management) и Client Load Balancing
#
# * - устанавливаются по умолчанию, но могут быть исключены из установки флагом MIN.

# Версия: SoftWLC 1.37, EMS 3.41
# Целевая ОС: noble (ubuntu 24.04), jammy (ubuntu 22.04), focal (ubuntu 20.04),
# Автор: Абаренов ВП
# ООО Предприятие Элтекс
# Новосибирск, 2025

# Модификаторы запуска скрипта:
# --update-eltex-packages          : пропустить установку системных пакетов. только установка пакетов из репозитория eltex
# --test-ports    : Режим "только протестировать открытые порты Платформы SoftWLC", без установки пакетов.
# --dhcp          : установить пакет 'isc-dhcp-server' в его дефолтной конфигурации;
# --force-old-conffiles : в этом режиме при обновлении dpkg будет автоматически принимать решение
#                         использовать старые conf файлы
# --force-new-conffiles : в этом режиме dpkg при обновлении будет автоматически принимать решение
#                         использовать новые conf файлы
# --min           : из установки исключаются следующие сервисы: eltex-logging-service, eltex-disconnect-service,
#                   eltex-johnny, eltex-airtune
# --monitoring : установка prometheus и radius exporter
# serverip=10.20.30.40 : задать IPv4 адрес сервера, который будет прописан в конфигурацию для перехода ЛК-КП-ЛК
#                        можно использовать serverip или SERVERIP. Нельзя задавать несуществующие адреса,
#                        нельзя задавать доменное имя или 127.0.0.1. Если у сервера один интерфейс (один адрес),
#                        то можно не задавать, скрипт вычислит и подставит автоматически.
# emsip=11.12.13.14 : задать IPv4 адрес сервера в управляющей сети. Тот адрес по которому ТД и другое оборудование
#                     будут обращаться к СУ по протоколам TFTP, FTP, HTTP, AirTune и т.д.
#                     этот адрес скрипт пропишет в собственные настройки сервиса eltex-ems в его БД
#
# Ответы для автоматической установки
# Измените при необходимости

# Имя пользователя администратора MySQL
export ANSWER_SOFTWLC_MYSQL_USER=root
# Пароль администратора MySQL
export ANSWER_SOFTWLC_MYSQL_PASSWORD=root
# Имя пользователя администратора SoftWLC
export ANSWER_AUTH_SERVICE_ADMIN_USER=admin
# Пароль администратора SoftWLC
export ANSWER_AUTH_SERVICE_ADMIN_PASSWORD=password
# Пароль служебного пользователя SoftWLC (softwlc_service)
export ANSWER_SOFTWLC_SERVICE_USER_PASSWORD=softwlc
# Корневой домен
export ANSWER_SOFTWLC_ROOT_DOMAIN=root
# Язык EMS по умолчанию: 1 - русский, 2 - английский
export ANSWER_EMS_LANG=1
# Максимальное количество ОЗУ, выделяемое EMS (в МБ)
export ANSWER_EMS_MAX_HEAP=1024
# Код создаваемого тарифа
export ANSWER_RADIUS_TARIFF_CODE=default
# Генерировать ли сертификат для сервера RADIUS
export ANSWER_NBI_MAKE_SERVER_CERTIFICATE=1
# Срок действия серверного сертификата RADIUS
export ANSWER_NBI_SERVER_CERTIFICATE_PERIOD=3650
# Пароль от закрытого ключа серверного сертификата RADIUS
export ANSWER_NBI_SERVER_CERTIFICATE_KEY=1234
# Генерация ключей для eltex-doors
export ANSWER_GENERATE_KEYS=N

# Не устанавливать пакеты eltex-logging-service, eltex-disconnect-service, eltex-johnny, eltex-airtune
export MIN=0

# Устанавливать prometheus
export MONITORING_INSTALL=0

# Не рекомендуется редактировать
export ANSWER_SOFTWLC_LOCAL=1
export ANSWER_EMS_REPLACE_CONF=1
export ANSWER_EMS_ACCESS_TYPE_DOMAIN=1
export ANSWER_RADIUS_MAKE_TARIFF=1
export ANSWER_RADIUS_TARIFF_PORTAL=1
export ANSWER_SOFTWLC_SERVICE_USER_LOGIN=softwlc_service
export ANSWER_RADIUS_DB_UPDATE_CRON=1
export ANSWER_SOFTWLC_SCHEDULE_BACKUP=Y

# Настройка автоматического ответа на интерактивные вопросы
export DEBIAN_FRONTEND="noninteractive"

# Настройки MYSQL пользователя для сервисов
export MYSQL_USER="javauser"
export MYSQL_PASSWORD="javapassword"

# Public Eltex production repo
ELTEX_PUBLIC_REPO="https://archive.eltex-co.ru/wireless"
# Private (internal) repo
ELTEX_PRIVATE_REPO="secret"
# Переменная, которая является рабочей. Внутри скрипта работа идёт с ней в зависимости от параметров вызова скрипта
ELTEX_REPO=${ELTEX_PUBLIC_REPO}

# Режимы обновления dpkg
OLD_CONF_FILES=0
NEW_CONF_FILES=0

## Установить пакет isc-dhcp-server
INSTALL_DHCP=0

# Наименование программ (определяют путь в репозитории)
SWLC_VERSION="softwlc-1.37"
SWLC_DEPENDENCIES="$SWLC_VERSION-dependencies"

REPO_GPG_KEY_ADDR="${ELTEX_REPO}/repo.gpg.key"
REPO_GPG_KEY_SYS_ADDR="/etc/apt/keyrings/eltex.gpg"
REPO_NGINX_GPG_KEY_ADDR="https://nginx.org/keys/nginx_signing.key"
REPO_NGINX_GPG_KEY_SYS_ADDR="/etc/apt/keyrings/nginx.gpg"
SWLC_DISTRIBUTION="$SWLC_VERSION-common"
SWLC_REPO_SOURCES="deb [arch=amd64] $ELTEX_REPO $SWLC_DISTRIBUTION main"

NGINX_CONFIG_FILE="softwlc_1.37_nginx.conf"
WAIT_BETWEEN_STEPS=5
# Режим "только тестируем порты и выходим", по умолчанию выключен
TEST_PORTS_MODE=0

# Переменная для пропуска установки пакетов linux, java и т.д. (т.е. только установка/обновление Eltex-пакетов из репо)
SKIP_LINUX_DEB=0

# Переменная для выставления дефолтных адресов в конфигурации при обновлении 1+1
SET_DEFAULT_ADRESSES=0

red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr 0)

# Вендор JVM
JAVA_VENDOR="openjdk"
LIBCURL_PACKET_NAME="libcurl4"

# Пути к файлам лицензий
AIRTUNE_LICENSE_PATH="/etc/eltex-airtune/licence"
AIRTUNE_LICENSE_FILES="$AIRTUNE_LICENSE_PATH/licence*.xml"
EMS_LICENSE_PATH="/usr/lib/eltex-ems/conf/licence"
EMS_LICENSE_FILES="$EMS_LICENSE_PATH/licence*.xml"

# Массив внешних IP сервера (весь ifconfig, кроме 127.0.0.1)
EXTERNAL_IPS=()
# Переменная, куда сохраняется переданное в аргументах значения для адреса сервера, подставляемое в КП/ЛК
# Если не передали в аргументах, то ждёт выбор пользователя.
external_ip=""

# Список поддерживаемых кодовых имён операционных систем
LINUX_CODENAMES="
  buster
  focal
  jammy
  noble
  "

# Список поддерживаемых дистрибуторов операционных систем
LINUX_DISTRIBUTORS="
  debian
  ubuntu
  astralinuxce"

# Прервать установку при ошибках
set -e

echo "${green}Installation started for $SWLC_VERSION, from $ELTEX_REPO${reset}"

# Метод удаляет файл с Элтекс репо, т.к. при недоступности репо скрипт не
# может выполнить ни одну из функций
clean_eltex_repo() {
  # удалить старый репозиторий (ems, softwlc), если он есть
  if [[ -f "/etc/apt/sources.list.d/eltex.list" ]]; then
    rm /etc/apt/sources.list.d/eltex.list
  fi
}

check_memory() {
  ram=$(grep MemTotal /proc/meminfo | awk '{printf "%d", $2 / 1000}')

  if [[ $ram -lt 8000 ]]; then
    echo "${red}You have $ram MB of RAM. You need 8 GB of RAM and 10 GB of free hard disk space, installation aborted!${reset}"
    exit 1
  fi

  free_space=$(df / | grep / | awk '{printf "%d", $4 / 1000}')

  if [[ $free_space -lt 10000 ]]; then
    echo "${red}You have $free_space MB of free hard disk space. 10 GB required for installation. Installation aborted!${reset}"
    exit 1
  fi
}

update_repo_related_vars() {
  REPO_GPG_KEY_ADDR="${ELTEX_REPO}/repo.gpg.key"
  if [[ "$DISTRIB_CODENAME" == "jammy" || "$DISTRIB_CODENAME" == "noble" ]]; then
    SWLC_REPO_SOURCES="deb [arch=amd64 signed-by=${REPO_GPG_KEY_SYS_ADDR}] $ELTEX_REPO $SWLC_DISTRIBUTION main"
  else
    SWLC_REPO_SOURCES="deb [arch=amd64] $ELTEX_REPO $SWLC_DISTRIBUTION main"
  fi
}

# Стандартное добавление репозиториев
add_default_repo() {
  # репозитории Eltex
  wget -O - ${REPO_GPG_KEY_ADDR} | apt-key add -
  echo ${SWLC_REPO_SOURCES} >>/etc/apt/sources.list.d/eltex.list
  if [[ "$DISTRIB_CODENAME" == "jammy" || "$DISTRIB_CODENAME" == "noble" ]]; then
    echo "deb [arch=amd64 signed-by=${REPO_GPG_KEY_SYS_ADDR}] $ELTEX_REPO $SWLC_VERSION-$DISTRIB_CODENAME main" >>/etc/apt/sources.list.d/eltex.list
    echo "deb [arch=amd64 signed-by=${REPO_GPG_KEY_SYS_ADDR}] $ELTEX_REPO $SWLC_DEPENDENCIES-$DISTRIB_CODENAME main" >>/etc/apt/sources.list.d/eltex.list
  else
    echo "deb [arch=amd64] $ELTEX_REPO $SWLC_VERSION-$DISTRIB_CODENAME main" >>/etc/apt/sources.list.d/eltex.list
    echo "deb [arch=amd64] $ELTEX_REPO $SWLC_DEPENDENCIES-$DISTRIB_CODENAME main" >>/etc/apt/sources.list.d/eltex.list
  fi

  # Ставим всегда самый новый nginx с родного репо проекта (иначе несовместимость по конфигам старых версий)
  wget ${REPO_NGINX_GPG_KEY_ADDR}
  apt-key add nginx_signing.key
}

add_repo_with_gpg_keys() {
  # Добавляем репозитории eltex и nginx и т.д. в зависимости от ОС
  case "$DISTRIB_CODENAME" in
  "jammy" | "noble")
    # репозитории Eltex
    wget -q -O - ${REPO_GPG_KEY_ADDR} | gpg --yes --dearmor -o ${REPO_GPG_KEY_SYS_ADDR}

    # Ставим всегда самый новый nginx с родного репо проекта (иначе несовместимость по конфигам старых версий)
    wget -q -O - ${REPO_NGINX_GPG_KEY_ADDR} | gpg --yes --dearmor -o ${REPO_NGINX_GPG_KEY_SYS_ADDR}
    echo "deb [signed-by=${REPO_NGINX_GPG_KEY_SYS_ADDR}] http://nginx.org/packages/$DISTRIBUTOR_ID/ $DISTRIB_CODENAME nginx" >/etc/apt/sources.list.d/nginx.list
    ;;
  esac
  add_default_repo
}

# проверить наличие обязательного файла (без него не будет настроен nginx, а значит не заработает половина сервисов)
check_nginx_config() {
  if [[ -f "$NGINX_CONFIG_FILE" ]]; then
    echo "File '$NGINX_CONFIG_FILE' found."
    FILESIZE=$(stat -c%s "$NGINX_CONFIG_FILE")
    if [[ $FILESIZE -gt 0 ]]; then
      echo "Size of $NGINX_CONFIG_FILE = $FILESIZE bytes."
    else
      echo "${red}File '$NGINX_CONFIG_FILE' is empty, installation aborted!${reset}"
      exit 1
    fi
  else
    echo "${red}File '$NGINX_CONFIG_FILE' not found, installation aborted!${reset}"
    exit 1
  fi
}

set_rsyslog_mysql_silent_mode() {
  # rsyslog-mysql login@password settings (default: login=root, password=root)
  echo "rsyslog-mysql   rsyslog-mysql/dbconfig-install  boolean true" | debconf-set-selections
  echo "rsyslog-mysql   rsyslog-mysql/mysql/app-pass    password $ANSWER_SOFTWLC_MYSQL_PASSWORD" | debconf-set-selections
  echo "rsyslog-mysql   rsyslog-mysql/app-password-confirm      password $ANSWER_SOFTWLC_MYSQL_PASSWORD" | debconf-set-selections
  echo "rsyslog-mysql   rsyslog-mysql/password-confirm  password $ANSWER_SOFTWLC_MYSQL_PASSWORD" | debconf-set-selections
  echo "rsyslog-mysql   rsyslog-mysql/mysql/admin-pass  password $ANSWER_SOFTWLC_MYSQL_PASSWORD" | debconf-set-selections
  echo "rsyslog-mysql   rsyslog-mysql/remote/port       string " | debconf-set-selections
}

install() {
  # https://man7.org/linux/man-pages/man1/dpkg.1.html - info about used options
  if [[ ${OLD_CONF_FILES} == 1 ]]; then
    apt-get --yes -o Dpkg::Options::="--force-confold" install "$@"
  elif [[ ${NEW_CONF_FILES} == 1 ]]; then
    apt-get --yes -o Dpkg::Options::="--force-confnew" install "$@"
  else
    apt-get --yes install "$@"
  fi
}

stop() {
  # add '|| true' - to ignore error
  service "$@" stop || true
}

restart() {
  service "$@" restart
}

start() {
  service "$@" start
}

reload() {
  service "$@" reload || true
}

update() {
  apt-get -y update || true
}

# Перезаписывает файловые лимиты для службы mysql
function replace_open_files_for_mysql() {
  local DIR="/etc/systemd/system/mariadb.service.d"
  local FILE_OVERRIDE="$DIR/override.conf"
  if [ -f "$FILE_OVERRIDE" ]; then
    rm "$FILE_OVERRIDE"
  fi

  if [ ! -d "$DIR" ]; then
    mkdir -p "$DIR"
  fi

  echo "[Service]" >"$FILE_OVERRIDE"
  echo "LimitNOFILE=1617596" >>"$FILE_OVERRIDE"
  echo "LimitNOFILESoft=1617596" >>"$FILE_OVERRIDE"
  echo "File '$FILE_OVERRIDE' replaced with new configuration"
  systemctl daemon-reload
  restart mysql
}

# Раскомментировать модули приёма данных из сети, если они закоментированы в главном конфиге службы
function rsyslog_uncomment_network_mod() {
  # uncomment
  # sed -i '/<pattern>/s/^#//g' file
  # comment
  # sed -i '/<pattern>/s/^/#/g' file
  local FILE="/etc/rsyslog.conf"

  sed -i '/imudp/s/^#//g' $FILE
  sed -i '/imtcp/s/^#//g' $FILE
}

# Контроль открытого порта (без контроля службы)
# Вызов функции: check_port "8080" result_var
# В результат будет помещён 0 - OK (порт открыт) или 1 - Ошибка (порта нет)
function check_port() {
  local __resultvar=$2
  local myresult='0'
  if [[ $(netstat -pna | grep -s ":$1") ]]; then
    echo "${green}Checking port '$1' - passed${reset}"
    myresult='0'
  else
    echo "${red}Checking port '$1' - error${reset}"
    myresult='1'
  fi
  eval ${__resultvar}="'$myresult'"
}

# Метод проверки открытых портов. Количество попыток проверки передается как входной аргумент.
# Задержка между попытками - 5 секунд.
# Если по завершении проверки какой-либо из портов до сих пор закрыт - функция завершит выполнение с кодом 2.
# Вызов функции: check_all_ports "25" "1", где первый аргумент - максимальное количество попыток проверки.
function check_all_ports() {
  local __CHECK_COUNT=$1
  local __MIN=$2
  declare -A service_ports_to_check
  declare -A service_ports_failed_results
  service_ports_to_check=(
    ['eltex-ems']='9310'
    ['eltex-ems-snmp-api']='162'
    ['eltex-doors']='9097'
    ['eltex-pcrf']='7070'
    ['eltex-apb']='8090'
    ['eltex-ngw']='8040'
    ['eltex-portal']='9000'
    ['eltex-portal-constructor']='9001'
    ['eltex-bruce']='8008'
    ['eltex-jobs']='9696'
    ['eltex-wifi-cab']='8083'
    ['eltex-mercury']='6565'
    ['eltex-wids-service']='9095'
  )

  if [[ "${__MIN}" == "0" ]]; then
    service_ports_to_check['eltex-logging-service']='9099'
    service_ports_to_check['eltex-disconnect-service']='9096'
    service_ports_to_check['eltex-airtune']='8089'
  fi

  CHECK_PORTS_PASSED="1"
  for i in $(seq 1 ${__CHECK_COUNT}); do
    echo "Attempt ${i}/${__CHECK_COUNT}"
    for service in "${!service_ports_to_check[@]}"; do
      check_port "${service_ports_to_check[$service]}" check_port_result
      if [[ "$check_port_result" == "1" ]]; then
        service_ports_failed_results[$service]=$check_port_result
      else
        unset service_ports_to_check[$service]
        unset service_ports_failed_results[$service]
      fi
    done
    echo
    if [[ "${#service_ports_failed_results[@]}" != "0" ]]; then
      sleep 5
    else
      CHECK_PORTS_PASSED="0"
      break
    fi
  done
  if [[ "$CHECK_PORTS_PASSED" != "0" ]]; then
    for service in "${!service_ports_failed_results[@]}"; do
      echo "${red}Component ${service} out of service (${service_ports_to_check[${service}]} not opened)${reset}"
    done
    exit 2
  fi
}

# Полностью переписать конфиг для плагина rsyslog-mysql
function rsyslog_mysql_replace_config() {
  # Это оригинальный файл: /etc/rsyslog.d/mysql.conf
  # Нам нужен файл, который выполнится ранее дефолтного /etc/rsyslog.d/50-default.conf
  # обработает цепочку "сохранить данные из сети" и прервёт обработку не загружая файловые логгеры
  # Для этого нужно создать конфиг mysql с именем 10-mysql.conf, переопределить там шаблон сохранения SQL
  # и прервать цепочку

  # Удалим первоначальный файл
  local DIR="/etc/rsyslog.d"
  local FILE_OVERRIDE="$DIR/mysql.conf"
  if [ -f "$FILE_OVERRIDE" ]; then
    rm "$FILE_OVERRIDE"
  fi

  # Удалим целевой файл, если как-то его создавали ранее
  local FILE_OVERRIDE="$DIR/10-mysql.conf"
  if [ -f "$FILE_OVERRIDE" ]; then
    rm "$FILE_OVERRIDE"
  fi

  {
    echo "### Configuration file for rsyslog-mysql"
    echo "### Changes are preserved"
    echo "\$template tpl,\"insert into SystemEvents (Message, Facility,FromHost, FromHostIp, Priority, DeviceReportedTime, ReceivedAt, InfoUnitID, SysLogTag) values ('%msg%', %syslogfacility%, '%HOSTNAME%', INET_ATON('%fromhost-ip%'), %syslogpriority%, '%timereported:::date-mysql%', '%timegenerated:::date-mysql%', %iut%, '%syslogtag%')\",SQL"
    echo "module (load=\"ommysql\")"
    echo ":fromhost-ip, !isequal, \"127.0.0.1\" action(type=\"ommysql\" server=\"localhost\" db=\"Syslog\" uid=\"rsyslog\" pwd=\"root\" Template=\"tpl\")"
    echo "& stop"
  } >>"$FILE_OVERRIDE"
}

# Функция проверяет установлена ли расширенная схема Syslog в базе данных (с партициями и новыми полями)
# Возвращает "0", если схема соответствует эталону;
# Возвращает "1", если схема не соoтветствует эталону;
function rsyslog_check_extended_database() {
  # Запомнить переменную "на входе", чтобы передать в неё значение "на выходе"
  local __resultvar=$1
  local myresult="0"

  local DB="Syslog"
  local TABLE="SystemEvents"
  local PART29="PARTITION \`p29\`"
  local myvar=""

  # Проверка наличия схемы
  myvar=$(mysql -DSyslog -u$ANSWER_SOFTWLC_MYSQL_USER -p$ANSWER_SOFTWLC_MYSQL_PASSWORD -se "SHOW DATABASES LIKE '$DB';")
  # echo "MySQL answer = "${myvar}
  if [[ ! $myvar == *${DB}* ]]; then
    echo "${red}Database '$DB' does not exists${reset}"
    myresult="1"
  else
    myresult="0"
  fi

  # Проверка наличия таблицы
  if [[ ! "$myresult" == "1" ]]; then
    myvar=$(mysql -D$DB -u$ANSWER_SOFTWLC_MYSQL_USER -p$ANSWER_SOFTWLC_MYSQL_PASSWORD -se "SHOW TABLES LIKE '$TABLE';")
    # echo "MySQL answer = "${myvar}
    if [[ ! $myvar == *${TABLE}* ]]; then
      echo "${red}Table '$TABLE' does not exists${reset}"
      myresult="1"
    else
      myresult="0"
    fi
  fi

  # Проверка наличия партиционирования в схеме - единственный положительный результат
  if [[ ! "$myresult" == "1" ]]; then
    myvar=$(mysql -D$DB -u$ANSWER_SOFTWLC_MYSQL_USER -p$ANSWER_SOFTWLC_MYSQL_PASSWORD -se "SHOW CREATE TABLE $TABLE;")
    # echo "MySQL answer = "${myvar}
    if [[ $myvar == *${PART29}* ]]; then
      myresult="0"
    else
      myresult="1"
    fi
  fi
  # Возвращаем результат
  if [[ "$__resultvar" ]]; then
    eval $__resultvar="'$myresult'"
  else
    echo "$myresult"
  fi
}

# Создаем расширенную схему Syslog, которую использует rsyslog-mysql и показывает сервер и GUI eltex-ems
function rsyslog_create_extended_database() {

  mysql -u$ANSWER_SOFTWLC_MYSQL_USER -p$ANSWER_SOFTWLC_MYSQL_PASSWORD <<MY_QUERY
-- MariaDB dump 10.19  Distrib 10.6.17-MariaDB, for debian-linux-gnu (x86_64)
--
-- Host: localhost    Database: Syslog
-- ------------------------------------------------------
-- Server version	10.6.17-MariaDB-1:10.6.17+maria~ubu2204

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Current Database: Syslog
--

drop database if exists Syslog;

CREATE DATABASE /*!32312 IF NOT EXISTS*/ Syslog DEFAULT CHARACTER SET utf8;

USE Syslog;

-- DROP TABLE IF EXISTS SystemEvents;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
-- DROP TABLE IF EXISTS SystemEvents;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE SystemEvents (
  ID bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  CustomerID bigint(20) DEFAULT NULL,
  ReceivedAt datetime NOT NULL DEFAULT '1971-01-01 00:00:01',
  DeviceReportedTime datetime DEFAULT NULL,
  Facility smallint(6) DEFAULT NULL,
  Priority smallint(6) DEFAULT NULL,
  FromHost varchar(60) DEFAULT NULL,
  Message text,
  InfoUnitID int(11) DEFAULT NULL,
  SysLogTag varchar(60) DEFAULT NULL,
  FromHostIp INT UNSIGNED,
  PRIMARY KEY (ID,ReceivedAt,FromHostIp)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8
/*!50100 PARTITION BY RANGE ( DAYOFMONTH(ReceivedAt))
SUBPARTITION BY HASH(FromHostIp) SUBPARTITIONS 33
(PARTITION p1 VALUES LESS THAN (2),
 PARTITION p2 VALUES LESS THAN (3),
 PARTITION p3 VALUES LESS THAN (4),
 PARTITION p4 VALUES LESS THAN (5),
 PARTITION p5 VALUES LESS THAN (6),
 PARTITION p6 VALUES LESS THAN (7),
 PARTITION p7 VALUES LESS THAN (8),
 PARTITION p8 VALUES LESS THAN (9),
 PARTITION p9 VALUES LESS THAN (10),
 PARTITION p10 VALUES LESS THAN (11),
 PARTITION p11 VALUES LESS THAN (12),
 PARTITION p12 VALUES LESS THAN (13),
 PARTITION p13 VALUES LESS THAN (14),
 PARTITION p14 VALUES LESS THAN (15),
 PARTITION p15 VALUES LESS THAN (16),
 PARTITION p16 VALUES LESS THAN (17),
 PARTITION p17 VALUES LESS THAN (18),
 PARTITION p18 VALUES LESS THAN (19),
 PARTITION p19 VALUES LESS THAN (20),
 PARTITION p20 VALUES LESS THAN (21),
 PARTITION p21 VALUES LESS THAN (22),
 PARTITION p22 VALUES LESS THAN (23),
 PARTITION p23 VALUES LESS THAN (24),
 PARTITION p24 VALUES LESS THAN (25),
 PARTITION p25 VALUES LESS THAN (26),
 PARTITION p26 VALUES LESS THAN (27),
 PARTITION p27 VALUES LESS THAN (28),
 PARTITION p28 VALUES LESS THAN (29),
 PARTITION p29 VALUES LESS THAN (30),
 PARTITION p30 VALUES LESS THAN (31),
 PARTITION p31 VALUES LESS THAN MAXVALUE) */;
/*!40101 SET character_set_client = @saved_cs_client */;


-- DROP TABLE IF EXISTS SystemEventsProperties;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE SystemEventsProperties (
  ID bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  SystemEventID bigint(20) DEFAULT NULL,
  ParamName varchar(255) DEFAULT NULL,
  ParamValue text,
  PRIMARY KEY (ID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;
MY_QUERY
}

# Контроль открытого порта для определённой службы в режиме TCP (+ контроль LISTEN)
# Пример вызова функции: check_port_service_tcp "8080" "nginx" "nginx" result_var
# $1 - номер порта (строкой);
# $2 - название сервиса (java - для всех java приложений) или 'docker-proxy' для схемы с контейнерами;
# $3 - описание сервиса, например 'Captive Portal' для Java приложения;
# $4 - В результат будет помещена строка: "0" - это OK (порт открыт) или "1" - это ошибка (порта нет)
function check_port_service_tcp() {
  local __resultvar="$4"
  local myresult='0'
  local port=":$1"
  local service="$2"
  local service_descr="$3"
  local variable=$(ss -tnlp | awk '{if ($1 == "LISTEN" && $4 ~ "'"$port"'" && ($6 ~ /'"$service"'/ || $6 ~ /docker-proxy/)) print "passed"}')
  if [[ $variable =~ "passed" ]]; then
    echo "${green}Checking tcp port '$1' for application '$2' ($service_descr) - passed${reset}"
    myresult='0'
  else
    echo "${red}Checking tcp port '$1' for application '$2' ($service_descr) - error${reset}"
    myresult='1'
  fi
  eval ${__resultvar}="'$myresult'"
}

# Выполняет GRANT на заданной БД
# $1 - БД
# $2 - привелегия (ALL, FILE, etc.)
# $3 - пользователь
# $4 - пароль
# $5 - таблица
grant() {
  if [[ -z $5 ]]; then
    grant_advanced "$1" "$2" "$3" "$4" "*"
  else
    grant_advanced $1 $2 $3 $4 $5
  fi
}

grant_advanced() {
  local database="$1"
  local privilege="$2"
  local user="$3"
  local password="$4"
  local table="$5"

  sql_exec "GRANT ${privilege} ON ${database}.${table} TO '${user}'@'localhost' IDENTIFIED BY '${password}'"
  sql_exec "GRANT ${privilege} ON ${database}.${table} TO '${user}'@'127.0.0.1' IDENTIFIED BY '${password}'"
  if [ "${REMOTE}" = 1 ]; then
    sql_exec "GRANT ${privilege} ON ${database}.${table} TO '${user}'@'%' IDENTIFIED BY '${password}'"
  fi
}

# Выполняет $1 как SQL-запрос
sql_exec() {
  mysql -u$ANSWER_SOFTWLC_MYSQL_USER -p$ANSWER_SOFTWLC_MYSQL_PASSWORD -e "$1" >/dev/null
  return $?
}

# Контроль открытого порта для определённой службы в режиме UDP (нет LISTEN)
# Пример вызова функции: check_port_service_udp "8080" "nginx" "nginx" result_var
# $1 - номер порта (строкой);
# $2 - название сервиса (java - для всех java приложений);
# $3 - описание сервиса, например 'Captive Portal' для Java приложения;
# $4 - В результат будет помещена строка: "0" - это OK (порт открыт) или "1" - это ошибка (порта нет)
function check_port_service_udp() {
  local __resultvar="$4"
  local myresult=0
  local port=":$1"
  local service="$2"
  local service_descr="$3"
  local variable=$(ss -unlp | awk '{if (($1 == "UNCONN" || $1 == "ESTAB") && $4 ~ "'"$port"'" && ($6 ~ /'"$service"'/ || $6 ~ /docker-proxy/)) print "passed"}')
  if [[ $variable =~ "passed" ]]; then
    echo "${green}Checking udp port '$1' for application '$2' ($service_descr) - passed${reset}"
    myresult="0"
  else
    # альтернативная команда для проверки портов
    local variable=$(ss -unlp | awk '{if (($1 ~ "UNCONN" || $1 ~ "ESTAB") && $3 ~ "'"$port"'" && ($5 ~ /'"$service"'/ || $5 ~ /docker-proxy/)) print "passed"}')
    if [[ $variable =~ "passed" ]]; then
      echo "${green}Checking tcp port '$1' for application '$2' ($service_descr) - passed${reset}"
      myresult='0'
    else
      echo "${red}Checking tcp port '$1' for application '$2' ($service_descr) - error${reset}"
      myresult='1'
    fi
  fi
  eval ${__resultvar}="'$myresult'"
}

# Функция для финальной проверки всех портов однохостовой инсталляции
# Считает количество фатальных ошибок (не все порты критичные)
# Если количество фатальных ошибок больше нуля, то после отчёта скрипт прервётся и выйдет с "-1"
function main_ports_test() {
  local FATAL=0

  echo ""
  echo "Start TCP/UDP port checking for all services.."

  # == databases ==
  check_port_service_tcp "3306" "mariadb" "MariaDB server" var
  if [[ "$var" != "0" ]]; then
    FATAL=$((FATAL + 1))
  fi

  # == EMS ==
  check_port_service_tcp "9310" "java" "EMS-server Applet API " var
  if [[ "$var" != "0" ]]; then
    FATAL=$((FATAL + 1))
  fi

  check_port_service_udp "162" "java" "EMS server SNMP API" var
  if [[ "$var" != "0" ]]; then
    FATAL=$((FATAL + 1))
  fi

  # == wifi-customer-cab spring-boot ==
  check_port_service_tcp "8083" "java" "WiFi Customer Cab (Jetty)" var
  if [[ "$var" != "0" ]]; then
    FATAL=$((FATAL + 1))
  fi

  # == nginx ==
  check_port_service_tcp "8080" "nginx" "Nginx proxy server" var
  if [[ "$var" != "0" ]]; then
    FATAL=$((FATAL + 1))
  fi

  # Captive Portal
  check_port_service_tcp "9000" "java" "Captive Portal, Portal Group" var
  if [[ "$var" != "0" ]]; then
    FATAL=$((FATAL + 1))
  fi

  # Portal Constructor
  check_port_service_tcp "9001" "java" "Portal Constructor, Portal Group" var
  if [[ "$var" != "0" ]]; then
    FATAL=$((FATAL + 1))
  fi

  # ngw
  check_port_service_tcp "8040" "java" "eltex-notification-gw, Portal Group" var
  if [[ "$var" != "0" ]]; then
    FATAL=$((FATAL + 1))
  fi

  # apb
  check_port_service_tcp "8090" "java" "eltex-apb, Portal Group" var
  if [[ "$var" != "0" ]]; then
    FATAL=$((FATAL + 1))
  fi

  # mercury
  check_port_service_tcp "6565" "java" "eltex-mercury service, Portal Group" var
  if [[ "$var" != "0" ]]; then
    FATAL=$((FATAL + 1))
  fi

  # doors
  check_port_service_tcp "9097" "java" "eltex-doors service HTTP API, Portal Group" var
  if [[ "$var" != "0" ]]; then
    FATAL=$((FATAL + 1))
  fi

  # == PCRF ==
  check_port_service_tcp "7070" "java" "PCRF monitoring API" var
  check_port_service_tcp "7080" "java" "PCRF RADIUS API" var
  if [[ "$var" != "0" ]]; then
    FATAL=$((FATAL + 1))
  fi
  check_port_service_tcp "5701" "java" "PCRF Hazelcast API" var
  check_port_service_udp "1813" "java" "PCRF, RADIUS accounting API" var
  if [[ "$var" != "0" ]]; then
    FATAL=$((FATAL + 1))
  fi

  # eltex-bruce
  check_port_service_tcp "8008" "java" "eltex-bruce service HTTPS API" var
  if [[ "$var" != "0" ]]; then
    FATAL=$((FATAL + 1))
  fi

  # eltex-jobs
  check_port_service_tcp "9696" "java" "eltex-jobs service HTTPS API" var
  if [[ "$var" != "0" ]]; then
    FATAL=$((FATAL + 1))
  fi

  # == RADIUS ==
  check_port_service_udp "1812" "eltex-radius" "RADIUS API" var
  if [[ "$var" != "0" ]]; then
    FATAL=$((FATAL + 1))
  fi

  # eltex-wids-service
  check_port_service_tcp "9095" "eltex-wids" "eltex-wids-service API" var

  if [[ ${MIN} == 0 ]]; then
    additional_ports_test
  fi

  # == Other ==
  check_port_service_udp "514" "syslog" "Linux syslog server" var
  check_port_service_udp "69" "tftp" "Linux TFTP server" var

  echo ""
  # Финальный контроль фатальных ошибок
  if [ $FATAL != 0 ]; then
    echo "${red}Found $FATAL port errors, script aborted!${reset}"
    exit 2
  else
    echo "${green}> Main core ports are tested successfully!${reset}"
  fi
  echo ""
}

function additional_ports_test() {
  # logging
  check_port_service_tcp "9099" "java" "eltex-logging-service, Portal Group" var
  if [[ "$var" != "0" ]]; then
    FATAL=$((FATAL + 1))
  fi

  # eltex-disconnect-service
  check_port_service_tcp "9096" "java" "eltex-disconnect-service HTTP API, Portal Group" var
  if [[ "$var" != "0" ]]; then
    FATAL=$((FATAL + 1))
  fi

  # eltex-airtune
  check_port_service_tcp "8082" "eltex-airtune" "eltex-airtune API" var
  if [[ "$var" != "0" ]]; then
    FATAL=$((FATAL + 1))
  fi
  check_port_service_tcp "8089" "eltex-airtune" "eltex-airtune API" var
  if [[ "$var" != "0" ]]; then
    FATAL=$((FATAL + 1))
  fi
  check_port_service_tcp "8099" "eltex-airtune" "eltex-airtune API" var
  if [[ "$var" != "0" ]]; then
    FATAL=$((FATAL + 1))
  fi
}

# Валидация IP адреса через regex
function valid_ipv4() {
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

# Заполнить массив EXTERNAL_IPS внешними IP сервера
# Для IPv4 — весь ifconfig, кроме 127.0.0.1
function find_external_ipv4_ips() {
  # Debian & U20 не содержат утилиту ifconfig (net-tools) в базовой поставке
  # local ifconfig="$(ifconfig | grep -Po '(?<=inet\s)[^\s]*')"
  local ipv4_addresses=$(ip -4 addr | grep inet | awk -F '[ \t]+|/' '{print $3}' | grep -v ^127.0.0.1)
  for address in ${ipv4_addresses}; do
    # Контроль, что адрес получился валидным. Если нет, то пробуем дополнительно очистить
    if ! valid_ipv4 $address; then
      address="$(echo $address | grep -oE '((1?[0-9][0-9]?|2[0-4][0-9]|25[0-5])\.){3}(1?[0-9][0-9]?|2[0-4][0-9]|25[0-5])')"
    fi
    # Если после очистки всё ОК, то включаем строку в выходной массив, за исключением localhost (127.0.0.1)
    if (valid_ipv4 $address) && [[ ! (${address} == "127.0.0.1") ]]; then
      EXTERNAL_IPS+=($address)
    fi
  done
}

# Заполнить массив EXTERNAL_IPS внешними IP сервера
function find_external_ips() {
  EXTERNAL_IPS=()
  find_external_ipv4_ips
  # TODO: поддержать (протестировать) IPv6; смотри историю коммитов для #206953
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
    echo "Which one will be used to open the portal constructor and the customer cabinet in a browser?"
    select_ip host
    ;;
  esac
  eval ${__resultvar}="${host}"
}

# Узнать внутренние IP сервера и, если их несколько, предложить пользователю выбор.
# В $1 функция возвращает окончательное значение внутреннего IP
function detect_internal_ip() {
  local __resultvar=$1
  case ${#EXTERNAL_IPS[@]} in
  0)
    echo "No internal IP addresses have been detected"
    host="127.0.0.1"
    ;;
  1)
    echo "Internal IP address has been detected"
    host=${EXTERNAL_IPS[0]}
    ;;
  *)
    echo "Several internal IPs have been detected:"
    for index in "${!EXTERNAL_IPS[@]}"; do
      echo "$(($index + 1)). ${EXTERNAL_IPS[index]}"
    done
    echo "Which one will be used as the management IP (for FTP, TFTP, HTTP and other protocols)?"
    select_ip host
    ;;
  esac
  eval ${__resultvar}="${host}"
}

# Делает валидацию аргумента и прерывает выполнение скрипта.
# Если адрес не валиден или '127.0.0.1', или его нет среди адресов интерфейсов сервера,
# то скрипт прерывается с ошибкой
function validate_server_ip_from_args() {

  validate_server_ip $1

  local found_var=0
  # Получаем список адресов, что есть на данном сервере
  find_external_ips

  # Проводим контроль, что юзер передал один из реальных адресов сервера
  for index in "${!EXTERNAL_IPS[@]}"; do
    echo "$((index + 1)). ${EXTERNAL_IPS[index]}"
    if [[ $1 == ${EXTERNAL_IPS[index]} ]]; then
      found_var=1
      break
    fi
  done

  if ((found_var == 0)); then
    echo "${red}Address not found on interfaces : '$1', script aborted${reset}"
    exit 1
  fi
}

# Делает валидацию аргумента и прерывает выполнение скрипта.
# Если адрес не валиден или '127.0.0.1', то скрипт прерывается с ошибкой
function validate_server_ip() {
# Формальная проверка на правильность адреса
  if ! valid_ipv4 $1; then
    echo "${red}Server IP addr argument is invalid: '$1', script aborted${reset}"
    exit 1
  fi

  # Проверка, что это не localhost (так как этот адрес приведёт пользователя браузера на собственный ПК)
  if [[ $1 == "127.0.0.1" || $1 == "::1" ]]; then
    echo "${red}Cannot assign localhost IP '$1' to server IP address; script aborted${reset}"
    exit 1
  fi
}

# Метод для проверки валидности имени дистрибутива.
# Скрипт не будет устанавливать софт на неизвестный дистрибутив Linux
function check_codename_and_platform() {
  # проверить разрядность системы и отказаться работать, если не x64
  local DISTRIB_PLATFORM=$(/bin/uname -m)
  echo "Platform : $DISTRIB_PLATFORM"

  if [[ ${DISTRIB_PLATFORM} != "x86_64" ]]; then
    echo "${red}Platform is not 'x86_64', script aborted!${reset}"
    exit 1
  fi

  # Проверить, что наименование дистрибутора Linux находится в списке известных
  local FOUND=0
  for distr in ${LINUX_DISTRIBUTORS}; do
    if [[ $1 == "$distr" ]]; then
      FOUND=1
      break
    fi
  done

  if [[ $FOUND == 0 ]]; then
    echo "${red}Unsupported Linux Distributor '$1', script aborted.${reset}"
    exit 1
  fi

  # Проверить, что кодовое имя дистрибутива находится в списке известных
  FOUND=0
  for distr in ${LINUX_CODENAMES}; do
    if [[ $2 == "$distr" ]]; then
      FOUND=1
      break
    fi
  done

  if [[ $FOUND == 0 && ! ${SKIP_LINUX_DEB} == 1 ]]; then
    echo "${red}Unsupported Linux Codename '$2', script aborted.${reset}"
    exit 1
  fi
}

function add_mysql_gpg_key() {
  # Временно отключаем прерывание установок при ошибке, чтобы обработать ее ниже
  set +e
  local get_key_exit_code=0
  # Если с hkp://keyserver.ubuntu.com:80 не получилось достать ключ - пробуем получить его другим путём
  for ((i = 1; i <= 3; i++))
  do
    echo "Trying to receive gpg key from hkp://keyserver.ubuntu.com:80."
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys B7B3B788A8D3785C
    get_key_exit_code=$?
    if [ $get_key_exit_code -ne 0 ]; then
      echo "Error receiving gpg key from hkp://keyserver.ubuntu.com:80."
      echo "Trying to get gpg key from repo.mysql.com"
      wget -O - https://repo.mysql.com/RPM-GPG-KEY-mysql-2022 | apt-key add -
      get_key_exit_code=$?
    fi

    if [ $get_key_exit_code -eq 0 ]; then
      break
    fi
    echo "Error receiving gpg key from repo.mysql.com"

  done
  set -e

  if [ $get_key_exit_code -ne 0 ]; then
    echo "Error receiving GPG key"
    exit 1
  fi
}

function install_mariadb() {
    if dpkg-query -f '${Status}\n' --show "mariadb-client" | grep '^install' &>/dev/null; then
        return 0
    fi

    FOUND_MYSQL=0
    if dpkg-query -f '${Status}\n' --show "mysql-client" | grep '^install' &>/dev/null; then
        FOUND_MYSQL=1
    fi


    if [[ ${FOUND_MYSQL} == 1 ]]; then
      local mysql_command="UPDATE mysql.user SET plugin='unix_socket' WHERE User='$ANSWER_SOFTWLC_MYSQL_USER' AND Host='localhost'"
      mysql -u$ANSWER_SOFTWLC_MYSQL_USER -p$ANSWER_SOFTWLC_MYSQL_PASSWORD -e "$mysql_command"
      create_new_root_for_mariadb
      echo "Stop mysql"
      systemctl stop mysql.service
    fi

    apt-get install -y apt-transport-https curl
    mkdir -p /etc/apt/keyrings
    curl -o /etc/apt/keyrings/mariadb-keyring.pgp 'https://mariadb.org/mariadb_release_signing_key.pgp'

    apt-get install -y libmecab2 daemon

    case "$DISTRIB_CODENAME" in
    "noble" )
      MARIADB_VERSION="10.11"
      ;;
    *)
      MARIADB_VERSION="10.6"
      ;;
    esac

    echo "deb [signed-by=/etc/apt/keyrings/mariadb-keyring.pgp] https://mirror.truenetwork.ru/mariadb/repo/$MARIADB_VERSION/ubuntu $DISTRIB_CODENAME main" > /etc/apt/sources.list.d/mariadb.list
    update

  case "$DISTRIB_CODENAME" in
  "focal" | "jammy" | "noble" )
    apt-mark hold eltex-radius-db
    apt-mark hold eltex-auth-service-db
    apt-get install -y mariadb-server
    apt-mark unhold eltex-radius-db
    apt-mark unhold eltex-auth-service-db
    echo "MariaDB installed successfully"
    ;;
  *)
    ;;
  esac

    disable_ssl_mariadb

    if [[ ${FOUND_MYSQL} == 1 ]]; then
      mysql_upgrade -u${ANSWER_SOFTWLC_MYSQL_USER} -p${ANSWER_SOFTWLC_MYSQL_PASSWORD} --upgrade-system-tables
    fi
}

function create_new_root_for_mariadb() {
  mysql -u${ANSWER_SOFTWLC_MYSQL_USER} -p${ANSWER_SOFTWLC_MYSQL_PASSWORD} -e "CREATE USER IF NOT EXISTS '${ANSWER_SOFTWLC_MYSQL_USER}'@'127.0.0.1' IDENTIFIED BY '${ANSWER_SOFTWLC_MYSQL_PASSWORD}'"
  mysql -u${ANSWER_SOFTWLC_MYSQL_USER} -p${ANSWER_SOFTWLC_MYSQL_PASSWORD} -e "GRANT ALL ON *.* TO '${ANSWER_SOFTWLC_MYSQL_USER}'@'127.0.0.1' WITH GRANT OPTION"
  mysql -u${ANSWER_SOFTWLC_MYSQL_USER} -p${ANSWER_SOFTWLC_MYSQL_PASSWORD} -e "GRANT PROXY ON ''@'%' TO '${ANSWER_SOFTWLC_MYSQL_USER}'@'127.0.0.1' WITH GRANT OPTION"
  mysql -u${ANSWER_SOFTWLC_MYSQL_USER} -p${ANSWER_SOFTWLC_MYSQL_PASSWORD} -e "FLUSH PRIVILEGES;"
}

function disable_ssl_mariadb() {
# прописать принудительно выключение ssl сервиса mysql/mariadb для всех целевых ОС
    MARIADB_CFG_FILE=/etc/mysql/mariadb.conf.d/50-server.cnf
    if [[ ! -f "$MARIADB_CFG_FILE" ]]; then
      echo "${red}File not exists '$MARIADB_CFG_FILE'${reset}"
    else
      # Если файл есть, то проверить что в конфиге ssl ещё не выключен
      if [[ ! $(egrep "^[^#;]" $MARIADB_CFG_FILE | egrep "ssl=0") ]]; then
        sed -i "$(( $(grep -n "SSL" /etc/mysql/mariadb.conf.d/50-server.cnf | cut -d: -f1) + 2)) i\ssl=0" $MARIADB_CFG_FILE
        echo "Modified file '$MARIADB_CFG_FILE', restarting service mariadb"
        service mysql restart
      fi
    fi
}


# Инсталляция утилиты curl в зависимости от платформы
function install_lib_curl() {
  case "$DISTRIB_CODENAME" in
  "buster" | "focal" | "jammy")
    LIBCURL_PACKET_NAME="libcurl4"
    ;;
  "noble")
    LIBCURL_PACKET_NAME="libcurl4t64"
    ;;
  *)
    echo "Unknown Linux codename for libcurl. Script aborted!"
    exit 1
    ;;
  esac
  install $LIBCURL_PACKET_NAME
}

function monitoring_install() {
  apt-get install -y eltex-prometheus
  apt-get install -y eltex-radius-exporter
  sed -i "s|127.0.0.1|${external_ip}|g" /etc/prometheus/prometheus.yml
}

function delete_mongo() {
  if [[ $(dpkg -l | grep mongodb-org) ]]; then
    echo "Found MongoDB. Deleting..."
    systemctl stop mongod.service
    systemctl disable mongod.service
    apt-get purge -y mongodb* mongodb-org-*
    echo "MongoDB deleted successfully"
  fi
}

# Инсталляция и настройка пакета libssl. Доступная версия зависит от ОС.
function install_libssl() {
  case "$DISTRIB_CODENAME" in
  "buster" | "focal")
    LIBSSL_PACKET_NAME="libssl1.1"
    ;;
  "jammy" | "noble")
    LIBSSL_PACKET_NAME="libssl3"
    ;;
  *)
    echo "Unknown Linux codename for libssl. Script aborted!"
    exit 1
    ;;
  esac

  # установить
  install ${LIBSSL_PACKET_NAME}
}

# Устанавливаем ntp, если это не Ubuntu 24.04 noble
# В Ubuntu 24.04 уже используется systemd-timesyncd для синхронизации времени
function install_ntp() {
  case "$DISTRIB_CODENAME" in
  "noble")
    echo "Ubuntu noble detected. Skipping ntp installation."
    ;;
  *)
    install ntp
    ;;
  esac
}

# Метод для полной инсталляции rsyslog-mysql, с заменой конфигов, модификацией баз,
# выдачей GRANT и всем остальным.
function full_installation_rsyslog_mysql() {
  install rsyslog-mysql

  # Пересоздать схему 'Syslog' в базе данных (в случае необходимости)
  res="0"
  rsyslog_check_extended_database res
  if [[ "$res" == "1" ]]; then
    echo "${red}Invalid database 'Syslog', need update ${reset}"
    rsyslog_create_extended_database
    echo "${green}Database 'Syslog' updated ${reset}"
  else
    echo "${green}Table 'SystemEvents' is valid (contains parts)${reset}"
  fi

  # После пересоздания БД лучше ещё раз её проверить, чтобы убедиться, что всё в базе согласно ожиданий
  rsyslog_check_extended_database res
  if [[ "$res" == "1" ]]; then
    echo "${red}Invalid database 'Syslog', update failed, script aborted!${reset}"
    exit 1
  fi

  # Выдать права (гранты) на вновь созданную схему для пользователя в СУБД, с которым работает продукт EMS
  grant "Syslog" ALL "$MYSQL_USER" "$MYSQL_PASSWORD"

  # После установки rsyslog-mysql нужно провести его кастомную конфигурацию.
  # Включить приём данных из сети по UDP и TCP
  # Настроить, чтобы сетевой трафик сохранялся в mysql и не сохранялся в локальные файлы
  rsyslog_uncomment_network_mod
  rsyslog_mysql_replace_config
  # Рестарт службы для применения всех новых конфигов
  restart rsyslog
}

# Копирование файлов лицензии eltex-ems для eltex-airtune
function copy_ems_license_to_airtune {
  LICENSE_FILES_ARRAY=()
  for f in $AIRTUNE_LICENSE_FILES; do
    if [[ -f "$f" ]]; then
      LICENSE_FILES_ARRAY+=("$f")
    fi
  done

  if [ ${#LICENSE_FILES_ARRAY[@]} -eq 0 ]; then
    echo "No old license files found"
  else
    echo "Found ${#LICENSE_FILES_ARRAY[@]} old license files. Renaming to '*.old':"
    for f in ${LICENSE_FILES_ARRAY[@]}; do
      if [ -f "$f.old" ]; then
        echo "$f.old file already exists. Rename or delete this file. Skipped."
      else
        mv --verbose "$f" "$f.old"
      fi
    done
  fi
  echo

  echo "Copying eltex-ems license files for eltex-airtune from '$EMS_LICENSE_PATH' folder:"
  for f in $EMS_LICENSE_FILES; do
    if [ -f "$AIRTUNE_LICENSE_PATH/${f##*/}" ]; then
      echo "File ${f##*/} already exists in airtune license folder. Skip copying."
    else
      cp -n --verbose "$f" "$AIRTUNE_LICENSE_PATH/"
    fi
  done
}

check_java_version() {
  # Ищем openjdk в системе. Если нашли - ставим ее по умолчанию
  if dpkg -s openjdk-17-jdk >/dev/null 2>&1; then
    update-java-alternatives -s java-1.17.0-openjdk-amd64
    return 0
  else
    return 1 # Требуется установить Java актуальной версии
  fi
}

install_java(){
  install openjdk-17-jdk
  # прописать в системе использование только что установленного пакета
  update-java-alternatives -s java-1.17.0-openjdk-amd64
}

change_config_ips(){

  update_config() {
      local file="$1"
      local new_ip="$2"

      if [[ -f "$file" ]]; then
          echo "Файл $file:"
      else
          echo "Файл не найден: $file"
      fi

      # Найти уникальные IP-адреса в файле
      local ips=($(grep -Eo "([0-9]{1,3}\.){3}[0-9]{1,3}" "$file" | sort -u))

      # Если IP-адреса не найдены, добавляем localhost для проверки
      [[ ${#ips[@]} -eq 0 ]] && ips=("localhost")

      for ip in "${ips[@]}"; do
          # Пропускаем исключения
          case "$ip" in
              "localhost"|"127.0.0.1"|"0.0.0.0")
                  echo -e "\t- IP $ip (замена не требуется)"
                  continue
                  ;;
          esac

          # Замена найденного IP-адреса на новый
          sed -i "s/$ip/$new_ip/g" "$file" && echo -e "\t- IP $ip заменён на $new_ip"
      done
  }

  files=(
      "/etc/eltex-apb/application.conf"
      "/etc/eltex-pcrf/eltex-pcrf.json"
      "/etc/eltex-portal-constructor/application.conf"
      "/etc/eltex-portal/application.conf"
      "/etc/eltex-radius-nbi/radius_nbi_config.txt"
      "/etc/eltex-ngw/application.conf"
      "/etc/eltex-radius/local.conf"
      "/etc/eltex-wifi-cab/system.xml"
      "/usr/lib/eltex-ems/conf/config.txt"
      "/etc/eltex-bruce/application.properties"
      "/etc/eltex-disconnect-service/application.conf"
      "/etc/eltex-doors/application.conf"
      "/etc/eltex-johnny/application.conf"
      "/etc/eltex-logging-service/application.conf"
      "/etc/eltex-mercury/application.conf"
      "/etc/eltex-pcrf/hazelcast-local.xml"
      "/etc/eltex-pcrf/hazelcast-cluster.xml"
  )

  new_ip="127.0.0.1"

  for file in "${files[@]}"; do
    update_config "$file" "$new_ip"
  done

  replace_manage_ip_in_ems_params_table $new_ip
}

replace_manage_ip_in_ems_params_table() {
  mysql_command="SELECT value FROM eltex_ems.PARAMS WHERE param1='system' AND param2='ip.adress';"
  old_ip=$(mysql -u$MYSQL_USER -p$MYSQL_PASSWORD -e "$mysql_command" | grep -oP 'value\n\K[^\s/]+')
  if [ -z "$old_ip" ]; then
      echo "IP-адрес в таблице 'eltex_ems.PARAMS' не найден. Скрипт завершен."
      exit 1
  fi

  if [[ "$old_ip" == "localhost" || "$old_ip" == "127.0.0.1" ]]; then
      echo "Управляющий IP-адрес EMS в таблице 'eltex_ems.PARAMS' равен localhost или 127.0.0.1. Скрипт продолжает работу."
      return 0
  fi

  # IP ЕМСа, по которому к нему обращаются сервисы/устройства лежит в БД, его тоже необходимо заменить.
  # Заменять IP в БД после обновления не нужно, в строке 1696 в БД подставится ранее выбранный IP ЕМСа
  mysql_command="REPLACE INTO eltex_ems.PARAMS (param1, param2, value) VALUES ('system', 'ip.adress', '$1');"
  mysql -u$MYSQL_USER -p$MYSQL_PASSWORD -e "$mysql_command"
  echo "Заменен IP-адрес в таблице 'eltex_ems.PARAMS'"
}

# Самое первое - это запрет работы не от root
if [[ $(id -u) -ne 0 ]]; then
  echo "${red}This script can only be run as root${reset}"
  exit 1
fi

# Читаем и применяем аргументы командной строки
if [[ -n "$1" ]]; then
  for i in "$@"; do
    # Определить repo: public | internal
    if [[ ${i} == "--public" ]]; then
      ELTEX_REPO=${ELTEX_PUBLIC_REPO}
    fi

    if [[ ${i} == "--private" ]]; then
      ELTEX_REPO=${ELTEX_PRIVATE_REPO}
    fi

    # Выставить режим пропуска инсталляции системных пакетов
    if [[ ${i} == "--update-eltex-packages" ]]; then
      SKIP_LINUX_DEB=1
      echo "${green}Skipping installation of system packages${reset}"
    fi

    # Переменная для выставления дефолтных адресов в конфигурации при обновлении 1+1
    if [[ ${i} == "--set-default-address" ]]; then
      SET_DEFAULT_ADRESSES=1
    fi

    ## Set the variable INSTALL_DHCP
    if [[ ${i} == "--dhcp" ]]; then
      INSTALL_DHCP=1
    fi

    ## Set the variable MIN
    if [[ ${i} == "--min" ]]; then
      MIN=1
    fi

    ## Set the variable MONITORING_INSTALL
    if [[ ${i} == "--monitoring" ]]; then
      MONITORING_INSTALL=1
    fi

    ## Server IP settings (external)
    if [[ ${i} =~ "serverip=" ]] || [[ ${i} =~ "SERVERIP=" ]]; then
      external_ip=$(echo ${i} | cut -d "=" -f 2)
      # Валидация с реальным списком адресов на интерфейсах. Если ошибка, то выход из скрипта.
      validate_server_ip_from_args $external_ip
    fi

    ## Server IP settings (internal=management)
    if [[ ${i} =~ "emsip=" ]] || [[ ${i} =~ "EMSIP=" ]]; then
      ems_ip=$(echo ${i} | cut -d "=" -f 2)
      # Валидация с реальным списком адресов на интерфейсах. Если ошибка, то выход из скрипта.
      validate_server_ip_from_args $ems_ip
    fi

    ## Ports test mode
    if [[ ${i} == "--test-ports" ]]; then
      TEST_PORTS_MODE=1
    fi

    if [[ ${i} == "--force-new-conffiles" ]]; then
      echo "Choosed new conffiles strategy for dpkg. Proceed"
      NEW_CONF_FILES=1
    fi

    if [[ ${i} == "--force-old-conffiles" ]]; then
      echo "Choosed old conffiles strategy for dpkg. Proceed"
      OLD_CONF_FILES=1
    fi

    if [[ ${NEW_CONF_FILES} == 1 && ${OLD_CONF_FILES} == 1 ]]; then
      echo "Can't use both dpkg update strategies. Please choose only one"
      exit 1
    fi

  done
fi

update
# установить (обновить) программу работы с репозиторием add-apt-repository (т.к. в некоторых системах она не присутствует)
install software-properties-common
install lsb-release wget
# Узнать наименование дистрибутора (debian/ubuntu/astra-linux) и записать lowercase
tmp_str=$(lsb_release -is)
DISTRIBUTOR_ID="${tmp_str,,}"

# узнать кодовое имя дистрибутива и записать lowercase
tmp_str=$(lsb_release -cs)
DISTRIB_CODENAME="${tmp_str,,}"

check_codename_and_platform ${DISTRIBUTOR_ID} ${DISTRIB_CODENAME}

echo "${green}OS distributer ID: $DISTRIBUTOR_ID${reset}"
echo "${green}OS distrib code name: $DISTRIB_CODENAME${reset}"
echo "${green}Repository: $ELTEX_REPO ${reset}"
echo "${green}Java vendor: $JAVA_VENDOR${reset}"

# Наименование дистрибуции пакетов для определенных ОС
OPERATING_SYSTEM_DISTRIBUTION="$SWLC_VERSION-$DISTRIB_CODENAME"
OPERATING_SYSTEM_DISTRIBUTION_OTHER="$SWLC_DEPENDENCIES-$DISTRIB_CODENAME"

# Режим "только контроль портов". Если он включен, то контролируем порты и завершаем программу
# Скрипт завершится со статусом 0, если все проверки удачные
# Скрипт завершится со статусом 2, если есть неоткрытые порты в основной (main) секции
if [[ ${TEST_PORTS_MODE} -eq 1 ]]; then
  echo "Test ports mode"
  # Core ports
  main_ports_test
  exit 0
fi

# найти все адреса на сервере (кроме локальных)
find_external_ips

# Если внешний IP адрес сервера (для настроек ЛК и КП) не задан аргументами скрипта,
# то его нужно спросить у пользователя и не двигаться дальше, пока не получим значение
if [ -z "$external_ip" ]; then
  echo "Setting portal constructor and customer cabinet link addresses.."
  detect_external_ip external_ip
  echo "${green}"Server external IP is $external_ip"${reset}"
  echo
else
  echo "${green}"Server is defined from args: $external_ip"${reset}"
  echo
fi

# Если внутренний IP адрес сервера (для настроек EMS, FTP, TFTP и т.д.) не задан аргументами скрипта,
# то его нужно спросить у пользователя и не двигаться дальше, пока не получим значение
if [ -z "$ems_ip" ]; then
  echo "Setting EMS addresses.."
  detect_internal_ip ems_ip
  echo "${green}"Server internal IP is $ems_ip"${reset}"
  echo
else
  echo "${green}"Server is defined from args: $ems_ip"${reset}"
  echo
fi

check_memory

# выполнение 'clean_eltex_repo' ДО любых действий с утилитой apt, т.к. переключение repo
# может приводить к недоступности repo ('private' vs 'public') и скрипт прервётся на apt update
clean_eltex_repo

# получить конфигурацию nginx соотв. версии
wget ${ELTEX_REPO}/nginx/conf/${NGINX_CONFIG_FILE} -O ${NGINX_CONFIG_FILE} || true

check_nginx_config

# Добавление репозиториев и их ключей перед установкой
update_repo_related_vars
add_repo_with_gpg_keys

# обновить репозиторий
update

# Установить mariadb
install_mariadb

# Режим "пропустить инсталляцию системных пакетов"
if [[ ! ${SKIP_LINUX_DEB} == 1 ]]; then
  # Инсталляция системных пакетов
  # Заранее задать ответы на вопросы инсталлятора для rsyslog
  set_rsyslog_mysql_silent_mode

  # Провести инсталляцию пакета openjdk
  install_java

  # установить прочие пакеты, которые прописаны в зависимостях пакетов
  install expect psmisc tftp-hpa tftpd-hpa snmpd snmp rsyslog curl libpcap0.8 fping vsftpd lockfile-progs \
    libstdc++6 zlib1g

  # инсталляция библиотеки зависит от версии ОС (либа нужна для eltex-airtune)
  install_libssl

  # Установка сервиса синхронизации времени
  install_ntp

  # некоторые новые дистрибутивы (desktop) могут не содержать net-tools:netstat
  install net-tools

  # Установка библиотеки libcurl, которая очень нужна некоторым сервисам, например eltex-radius, причём индекс
  # зависит от операционной системы
  install_lib_curl

  # переписываем лимиты для сервиса mysql, иначе rsyslog-mysql с пагинацией не работает на различных ОС
  replace_open_files_for_mysql

  # rsyslog-mysql устанавливается только после окончания установки mysql-server
  # иначе попытка его конфигурирования провалится
  full_installation_rsyslog_mysql

  # По отдельному флагу инсталлируем DHCP (настройка подсетей и запуск на совести сисадмина!)
  if [[ ${INSTALL_DHCP} == 1 ]]; then
    install isc-dhcp-server
  fi
else
  # Если java версия < актуальной -> устанавливаем новую версию java
  if ! check_java_version; then
      install_java
  fi
fi

if [[ ${MONITORING_INSTALL} == 1 ]]; then
  monitoring_install
fi


delete_mongo

if [[ ${SET_DEFAULT_ADRESSES} == 1 ]]; then
  change_config_ips
fi

PACKAGES="eltex-oui-list
        eltex-ems-db
        eltex-radius-db
        eltex-auth-service-db
        eltex-ems
        eltex-radius
        eltex-portal
        eltex-radius-nbi
        eltex-doors
        eltex-ngw
        eltex-apb
        eltex-pcrf
        eltex-mercury
        eltex-portal-constructor
        eltex-wifi-cab
        eltex-bruce
        eltex-wids-service
        eltex-jobs"

if [[ ${MIN} == 0 ]]; then
  PACKAGES="$PACKAGES
        eltex-logging-service
        eltex-disconnect-service
        eltex-airtune"
fi

# Последовательная установка пакетов
for package in ${PACKAGES}; do
  echo
  echo "*"
  echo "* Installing $package ..."
  echo "*"
  echo

  install ${package}

  case "$package" in
  eltex-radius-nbi)
    # Установить серверный сертификат в eltex-radius
    /var/lib/eltex-radius-nbi/setup_er_eap.sh
    ;;
  esac
done

# Добавить RemoteIpValve в server.xml

VALVE="        <!-- #96184 forward remote ip for nginx -->\n\
        <Valve className=\\\"org.apache.catalina.valves.RemoteIpValve\\\"\n\
           remoteIpHeader=\\\"X-Forwarded-For\\\"\n\
           internalProxies=\\\"127\\\\.0\\\\.0\\\\.1\\\"\n\
           requestAttributesEnabled=\\\"true\\\"/>\n"

AWK="BEGIN {
print \"Input file:\", ARGV[1];
OUTFILE = ARGV[1] \"_\";
print \"Temporary output file:\", OUTFILE;
ALREADY=0;
}
/org\.apache\.catalina\.valves\.RemoteIpValve/ {
ALREADY=1;
exit;
}
/<\/Host>/ {
print \"$VALVE\" > OUTFILE;
}
{
print > OUTFILE;
}
END {
if (ALREADY==0) {
print \"Replace original file '\" ARGV[1] \"' content\";
system(\"cat \" OUTFILE \" > \" ARGV[1]);
}
print \"Remove temporary file '\" OUTFILE \"'\";
system(\"rm \" OUTFILE);
}
"

# Установка Nginx

install nginx
cp ${NGINX_CONFIG_FILE} /etc/nginx/conf.d/softwlc.conf

# Записать wifi-cab secret в параметры EMS, чтобы API работало корректно:
#
#$ cat /etc/eltex-wifi-cab/local_secret into eltex_ems.PARAMS
#+----------------+----------------+----------------------------------+
#| param1         | param2         | value                            |
#+----------------+----------------+----------------------------------+
#| wirelessCommon | wificab.secret | 12b3dc9c63c8c75e307855398ac4fbaf |
#+----------------+----------------+----------------------------------+

CAB_KEY="unknown"
CAB_KEY_FILE="/etc/eltex-wifi-cab/local_secret"

while read -r line; do
  CAB_KEY="$line"
  #echo "secret : $key"
done <"$CAB_KEY_FILE"

mysql -u$MYSQL_USER -p$MYSQL_PASSWORD -e "INSERT INTO eltex_ems.PARAMS (id, param1, param2, value) \
 VALUES(1, 'wirelessCommon', 'wificab.secret', '$CAB_KEY') \
 ON DUPLICATE KEY UPDATE param1='wirelessCommon', param2='wificab.secret', value='$CAB_KEY';"

# Обновление блока конфигурации EMS сервера в БД internal IP
if [[ ${MIN} == 0 ]]; then
mysql_command="REPLACE INTO eltex_ems.PARAMS (param1, param2, value) VALUES ('airtune', 'airtune.api.host', '$ems_ip');"
mysql -u$MYSQL_USER -p$MYSQL_PASSWORD -e "$mysql_command"
fi

mysql_command="REPLACE INTO eltex_ems.PARAMS (param1, param2, value) VALUES ('ftpserver', 'ftp.addr', '$ems_ip');"
mysql -u$MYSQL_USER -p$MYSQL_PASSWORD -e "$mysql_command"

mysql_command="REPLACE INTO eltex_ems.PARAMS (param1, param2, value) VALUES ('gPon', 'gpon.ont.tftp.host', '$ems_ip');"
mysql -u$MYSQL_USER -p$MYSQL_PASSWORD -e "$mysql_command"

mysql_command="REPLACE INTO eltex_ems.PARAMS (param1, param2, value) VALUES ('gePon', 'tftp_host_no_vlan', '$ems_ip');"
mysql -u$MYSQL_USER -p$MYSQL_PASSWORD -e "$mysql_command"

mysql_command="REPLACE INTO eltex_ems.PARAMS (param1, param2, value) VALUES ('system', 'ip.adress', '$ems_ip');"
mysql -u$MYSQL_USER -p$MYSQL_PASSWORD -e "$mysql_command"

mysql_command="REPLACE INTO eltex_ems.PARAMS (param1, param2, value) VALUES ('tftpserver', 'tftp.addr', '$ems_ip');"
mysql -u$MYSQL_USER -p$MYSQL_PASSWORD -e "$mysql_command"

mysql_command="REPLACE INTO eltex_ems.PARAMS (param1, param2, value) VALUES ('system', 'tomcat.urlembeded', 'http://$ems_ip:8080');"
mysql -u$MYSQL_USER -p$MYSQL_PASSWORD -e "$mysql_command"

# Задать в конфигурации сервера EMS внешний Tomcat URL
mysql_command="REPLACE INTO eltex_ems.PARAMS (param1, param2, value) VALUES ('system', 'tomcat.url', 'http://$external_ip:8080');"
mysql -u$MYSQL_USER -p$MYSQL_PASSWORD -e "$mysql_command"

echo "Database eltex_ems for internal EMS IP '$ems_ip' updated"

echo "Database eltex_ems for external EMS IP '$external_ip' updated"

mysql_command="REPLACE INTO eltex_wifi_customer_cab.config_settings (name, value) VALUES ('portal.url', 'http://$external_ip:9001/epadmin/');"
mysql -u$MYSQL_USER -p$MYSQL_PASSWORD -e "$mysql_command"

echo "Portal constructor link in customer cabinet created"
echo

echo "Try to create customer cabinet link in portal constructor (100 seconds for retry).."
CHECK_COUNT=20
PROP_EXISTS="1"
for i in $(seq 1 ${CHECK_COUNT}); do

    properties_table_exists=$(mysql -u$MYSQL_USER -p$MYSQL_PASSWORD -e "SHOW TABLES FROM ELTEX_PORTAL LIKE 'properties';")
    if [[ -z "$properties_table_exists" ]]; then
      echo "'ELTEX_PORTAL.properties' table does not exist yet. Waiting for 5 sec and trying again. Attempt ${i}/${CHECK_COUNT}"
      sleep ${WAIT_BETWEEN_STEPS}
        continue
    fi

    lines_in_table=$(mysql -u$MYSQL_USER -p$MYSQL_PASSWORD -se "SELECT COUNT(group_id) FROM ELTEX_PORTAL.properties;")
    if [[ "$lines_in_table" -gt 0 ]]; then
      mysql_command="UPDATE ELTEX_PORTAL.properties SET value = \"$external_ip\" WHERE group_id = 7 AND name = \"host\";"
      mysql -u$MYSQL_USER -p$MYSQL_PASSWORD -e "$mysql_command"
      echo "Customer cabinet link in portal constructor created"
      PROP_EXISTS="0"
      break
    else
      echo "'ELTEX_PORTAL.properties' table does not has data yet. Waiting for 5 sec and trying again. Attempt ${i}/${CHECK_COUNT}"
      sleep ${WAIT_BETWEEN_STEPS}
    fi
done

#Если все циклы проверки прошли, а таблица ELTEX_PORTAL.properties так и не создалась, значит беда, выходим отсюда
if [[ "$PROP_EXISTS" != "0" ]]; then
  echo "${red}Data in table 'ELTEX_PORTAL.properties' doesn't exist${reset}"
  exit 2
fi

echo "Creating database user and access grants for eltex-ngw"
eltex-ngw create-db-user -u "$ANSWER_SOFTWLC_MYSQL_USER" -p "$ANSWER_SOFTWLC_MYSQL_PASSWORD"

echo "Creating database user and access grants for eltex-bruce"
eltex-bruce create-db-user -u "$ANSWER_SOFTWLC_MYSQL_USER" -p "$ANSWER_SOFTWLC_MYSQL_PASSWORD"

if [[ ${MIN} == 0 ]]; then
  copy_ems_license_to_airtune
fi

echo "Restarting all eltex services.."
# Перезапустить сервисы
restart nginx
restart eltex-radius
restart eltex-radius-nbi
restart eltex-doors
restart eltex-pcrf
restart eltex-apb
restart eltex-ngw
# EMS (stop, start)
stop eltex-ems
start eltex-ems
# main other
restart eltex-mercury
restart eltex-portal
restart eltex-portal-constructor
restart eltex-bruce
restart eltex-jobs
restart eltex-wifi-cab
restart eltex-wids
restart eltex-disconnect-service

if [[ ${MIN} == 0 ]]; then
  restart eltex-logging-service
  restart eltex-airtune
fi

if [[ ${MONITORING_INSTALL} == 1 ]]; then
  restart prometheus
  restart eltex-radius-exporter
fi

# проверить открытые порты
echo "Waiting 120 seconds.."
echo -ne '##                        (10%)\r'
sleep 12
echo -ne '####                      (20%)\r'
sleep 12
echo -ne '######                    (30%)\r'
sleep 12
echo -ne '########                  (40%)\r'
sleep 12
echo -ne '##########                (50%)\r'
sleep 12
echo -ne '############              (60%)\r'
sleep 12
echo -ne '################          (70%)\r'
sleep 12
echo -ne '##################        (80%)\r'
sleep 12
echo -ne '####################      (90%)\r'
sleep 12
echo -ne '######################    (100%)\r'
echo -ne '\n'

# Проверка на то, что все сервисы успели подняться
CHECK_COUNT=25
echo "Checking services ports ($CHECK_COUNT attempts for check)"
check_all_ports "$CHECK_COUNT" "$MIN"

# тестирование всех портов комплекса, если один из жизненно важных портов не будет открыт
# будет выход внутри функции: exit 2

# Ждём ещё 10 секунд, т.к. между инициализацией порта 9310 и SNMP-engine проходит долгое время внутри EMS
echo "Waiting 10 seconds.."
sleep 10

main_ports_test

echo "Checking EMS internal NBI"
if [[ $(curl "localhost:8080/northbound/getVersion") ]]; then
  echo "${green}Checking EMS.NBI on 'localhost' - passed${reset}"
else
  echo "${red}Checking EMS.NBI on 'localhost' - error${reset}"
  exit 2
fi

# Всё
echo ""
echo "Installation of Eltex SoftWLC finished successfully."
echo ""

if [[ ${INSTALL_DHCP} == 1 ]]; then
  echo "${green}DHCP server isc-dhcp-server installed, please configure and start it.${reset}"
fi

echo ""
echo "URLs of SoftWLC components:

Eltex.EMS Server management (internal) IP: $ems_ip
Eltex.EMS Server external IP: $external_ip

Eltex.EMS GUI: http://$external_ip:8080/ems/jws
    login: admin
    password: <empty>

Portal constructor: http://$external_ip:8080/epadmin
    login: $ANSWER_AUTH_SERVICE_ADMIN_USER
    password: $ANSWER_AUTH_SERVICE_ADMIN_PASSWORD

Wi-Fi customer cabinet (B2B): http://$external_ip:8080/wifi-cab
    login: $ANSWER_AUTH_SERVICE_ADMIN_USER
    password: $ANSWER_AUTH_SERVICE_ADMIN_PASSWORD"

exit 0
