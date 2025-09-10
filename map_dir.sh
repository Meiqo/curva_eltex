#!/bin/bash

# Скрипт настройки bind mount для Eltex директорий
set -e

echo "[INFO] Настраиваем bind mount..."

# Проверяем, существуют ли исходные директории на /data
if [ ! -d "/data/var/lib/mysql" ]; then
    echo "[ERROR] Сначала выполните скрипт подготовки директорий на /data!"
    exit 1
fi

# Создаем целевые точки монтирования (если они не существуют)
echo "[INFO] Создаем целевые точки монтирования..."
sudo mkdir -p /var/lib/mysql
sudo mkdir -p /var/lib/mongodb
sudo mkdir -p /var/lib/eltex-ems
sudo mkdir -p /var/ems-backup
sudo mkdir -p /tmp/mysql

# Резервируем оригинальный fstab
echo "[INFO] Создаем backup fstab..."
sudo cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d)

# Добавляем записи в fstab (БЕЗ noexec!)
echo "[INFO] Добавляем записи в /etc/fstab..."
cat << EOF | sudo tee -a /etc/fstab >/dev/null

# Bind mounts for Eltex data
/data/var/lib/mysql    /var/lib/mysql    none    bind,noatime,nodiratime    0    0
/data/var/lib/mongodb  /var/lib/mongodb  none    bind,noatime,nodiratime    0    0
/data/var/lib/eltex-ems /var/lib/eltex-ems none  bind,noatime,nodiratime    0    0
/data/var/log          /var/log          none    bind,noatime,nodiratime    0    0
/data/var/ems-backup   /var/ems-backup   none    bind,noatime,nodiratime    0    0
/data/tmp/mysql        /tmp/mysql        none    bind,noatime,nodiratime    0    0
EOF

# Перезагружаем systemd для обновления конфигурации fstab
echo "[INFO] Перезагружаем systemd..."
sudo systemctl daemon-reload

# Применяем монтирование
echo "[INFO] Применяем монтирование..."
sudo mount -a

# Проверяем результат
echo "[INFO] Проверяем монтирование..."
echo "=== Список bind-монтирований ==="
mount | grep -E "(mysql|mongodb|eltex|log|backup)" || echo "Монтирования не найдены"

echo ""
echo "=== Проверка точек монтирования ==="
for mount_point in /var/lib/mysql /var/lib/mongodb /var/lib/eltex-ems /var/log /var/ems-backup /tmp/mysql; do
    if mountpoint -q "$mount_point"; then
        echo "✓ $mount_point успешно примонтирован"
    else
        echo "✗ $mount_point НЕ примонтирован"
    fi
done

echo ""
echo "[SUCCESS] Bind mount настроен! Система готова к установке ПО."
