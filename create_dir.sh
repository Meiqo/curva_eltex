#!/bin/bash

# Скрипт подготовки директорий на /data для Eltex WiFi Controller
set -e # Прерывать выполнение при любой ошибке

echo "[INFO] Начинаем подготовку файловой структуры на /data..."

# Проверяем, что раздел /data примонтирован
if ! mountpoint -q /data; then
    echo "[ERROR] Раздел /data не примонтирован! Примонтируйте его и запустите скрипт снова."
    exit 1
fi

# Создаем основные директории для данных
echo "[INFO] Создаем структуру директорий на /data..."
sudo mkdir -p /data/var/lib/mysql
sudo mkdir -p /data/var/lib/mongodb
sudo mkdir -p /data/var/lib/eltex-ems
sudo mkdir -p /data/var/log
sudo mkdir -p /data/var/ems-backup
sudo mkdir -p /data/tmp/mysql

# Задаем базовые права (без указания владельца)
echo "[INFO] Настраиваем базовые права доступа..."

# Для MySQL директорий - пока только права
sudo chmod 755 /data/var/lib/mysql
sudo chmod 1777 /data/tmp/mysql  # Sticky bit для временных файлов

# Для остальных директорий стандартные права
sudo chmod 755 /data/var/lib/mongodb
sudo chmod 755 /data/var/lib/eltex-ems
sudo chmod 755 /data/var/log
sudo chmod 755 /data/var/ems-backup

# Выводим информацию о созданной структуре
echo "[SUCCESS] Подготовка завершена!"
echo ""
echo "Создана структура с базовыми правами:"
echo "  • /data/var/lib/mysql     (права: 755)"
echo "  • /data/var/lib/mongodb   (права: 755)"
echo "  • /data/var/lib/eltex-ems (права: 755)"
echo "  • /data/var/log           (права: 755)"
echo "  • /data/var/ems-backup    (права: 755)"
echo "  • /data/tmp/mysql         (права: 1777)"
echo ""
echo "Владельцы будут установлены автоматически при установке пакетов."
echo "После установки MySQL и MongoDB выполните:"
echo "  sudo chown -R mysql:mysql /data/var/lib/mysql /data/tmp/mysql"
echo "  sudo chown -R mongodb:mongodb /data/var/lib/mongodb"
echo "  sudo chmod 700 /data/var/lib/mysql"
