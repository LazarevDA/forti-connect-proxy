#!/bin/sh

# Выход при любой ошибке выполнения скрипта
set -e -o pipefail

if [ "$ENTRYDEBUG" == "TRUE" ]; then
  # Печать строк шелла по мере их чтения для дебага
  set -v
fi

# Генерируем строку регулярного выражения для поиска переменных портов
r="^"                          # Обязательное начало имени переменной
r="${r}\(PORT_FORWARD\|REMOTE_ADDR\)[^=]*="  # Имя переменной
r="${r}\(\(tcp\|udp\):\)\?"    # Опциональный протокол tcp или udp
r="${r}\(\(\d\{1,5\}\):\)\?"   # Опциональный LOCAL_PORT
r="${r}[a-zA-Z0-9.-]\+"        # Обязательный REMOTE_HOST (ip или hostname)
r="${r}:\d\{1,5\}"             # Обязательный REMOTE_PORT
r="${r}$"                      # Обязательный конец строки переменной

# Создаем список перенаправляемых портов, разделенных пробелами.
# Временно отключаем немедленное завершение скрипта при ненулевом выходе.
set +e
forwards=$(
  env \
  | grep "${r}" \
  | cut -d= -f2-
)
set -e

# Очищаем старые записи socat из ip-up, если они существовали
sed '/^socat/d' -i /etc/ppp/ip-up 2>/dev/null || true

# Перебираем все найденные конфигурации портов и создаем скрипты запуска socat
for forward in ${forwards}; do

  # Считаем двоеточия, чтобы понять формат записи
  colons=$(echo "${forward}" | grep -o ':' | wc -l)

  if [ "${colons}" -eq "3" ]; then
    PROTOCOL=$(echo "${forward}" | cut -d: -f1)
    LOCAL_PORT=$(echo "${forward}" | cut -d: -f2)
    REMOTE_HOST=$(echo "${forward}" | cut -d: -f3)
    REMOTE_PORT=$(echo "${forward}" | cut -d: -f4)

  elif [ "${colons}" -eq "2" ]; then
    PROTOCOL="tcp"
    LOCAL_PORT=$(echo "${forward}" | cut -d: -f1)
    REMOTE_HOST=$(echo "${forward}" | cut -d: -f2)
    REMOTE_PORT=$(echo "${forward}" | cut -d: -f3)

  elif [ "${colons}" -eq "1" ]; then
    PROTOCOL="tcp"
    LOCAL_PORT="1111"
    REMOTE_HOST=$(echo "${forward}" | cut -d: -f1)
    REMOTE_PORT=$(echo "${forward}" | cut -d: -f2)

  else
    printf 'Нераспознанное значение PORT_FORWARD: "%s"\n' "${forward}" >&2
    exit 1
  fi

  # Запускаем фоновые socat-туннели для проброса портов внутрь VPN
  echo "Запуск проброса: ${PROTOCOL} локальный порт ${LOCAL_PORT} -> удаленный ${REMOTE_HOST}:${REMOTE_PORT}"
  socat ${PROTOCOL}-l:${LOCAL_PORT},fork,reuseaddr ${PROTOCOL}:${REMOTE_HOST}:${REMOTE_PORT} &

done

# Перехватываем аргументы openconnect / openfortivpn из команды docker run
if [ "$1" = "openconnect" ] || [ "$1" = "openfortivpn" ]; then
  shift
fi

# Автоматически определяем адрес Windows-хоста в подсети Docker (обычно 172.17.0.1)
# и заворачиваем трафик к домашним сетям 192.168.0.0/16 обратно через eth0 хоста
(
  sleep 5
  DOCKER_GW=$(ip route show default | awk '/default/ {print $3}')
  if [ -n "$DOCKER_GW" ]; then
    echo "=========================================================="
    echo "Авто-настройка сети: возвращаем трафик хоста через $DOCKER_GW"
    echo "=========================================================="
    ip route add 192.168.0.0/16 via "$DOCKER_GW" dev eth0 || true
    ip route add 172.16.0.0/12 via "$DOCKER_GW" dev eth0 || true
  fi
) &

# Запуск OpenConnect с явным указанием реалма
exec openconnect --protocol=fortinet "$@" "$VPN_HOST"
