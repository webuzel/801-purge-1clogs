#!/bin/bash
#
# 1C Cluster and Bases Reveal Script
#
# (c) ALLIANCE GROUP, 2024
# v 2024-01-24
#
# ======================================================
# WARNINIG: Prefer to run on Debian based OSes!
# ======================================================
#

# ПЕРЕМЕННЫЕ И КОНСТАНТЫ:
SRV1CV8_USER_DEFAULT="usr1cv8"
SRV1CV8_USERNAME=""
# Базовый каталог установки 1С-сервера:
RAC_BASE_DIR="/opt/1cv8/x86_64/"

# Результат работы скрипта будет сохранён в виде файла с содержимым:
#   имя_базы=путь_к_её_рабочей_папке
# (по одной строке на базау).
# Имя файла (по-умолчанию) для сохранения результатов работы скрипта:
PURGELOGS_CFG_NAME="localbases.cfg"


function currentPath(){
  local SOURCE=""
  local DIR=""
  SOURCE=${BASH_SOURCE[0]}
  while [ -L "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
    DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
    SOURCE=$(readlink "$SOURCE")
    [[ $SOURCE != /* ]] && SOURCE=$DIR/$SOURCE # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
  done
  DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
  echo $DIR
}

PURGELOGS_CFG=$(currentPath)/$PURGELOGS_CFG_NAME
if [ ! -z "$1" ]; then
  # Если полный путь к файлу настроек передан в качестве параметра скрипта, то использовать его:
  PURGELOGS_CFG="$1"
fi

echo "# 1C Cluster and Bases Reveal Script" > $PURGELOGS_CFG

# Получение имени пользователя 1С-сервера:
if [[ -z "${SRV1CV8_USER}" ]]; then
  echo "INFO: Переменная среды \$SRV1CV8_USER не определена. Используем заданную по-умолчанию: \"$SRV1CV8_USER_DEFAULT\""
  SRV1CV8_USERNAME=$SRV1CV8_USER_DEFAULT
else
  echo "INFO: Найдена переменная среды \$SRV1CV8_USER, содержащая имя: \"$SRV1CV8_USER\""
  SRV1CV8_USERNAME=$SRV1CV8_USER
fi
# Вариант в одну строку:
# SRV1CV8_USERNAME="${SRV1CV8_USER:-$SRV1CV8_USER_DEFAULT}"

# echo "DEBUG: Имя пользователя: "$SRV1CV8_USERNAME

# Получение рабочей папки на основе имени пользователя 1С-сервера:
WORK_DIR="/home/${SRV1CV8_USERNAME}/.1cv8/1C/1cv8"

echo "DEBUG: Рабочий каталог: "$WORK_DIR


# Самая свежая (с наибольшим номером версии) подпапка в базовом каталоге:
RAC_SUBDIR=`ls -tr "$RAC_BASE_DIR" | tail -1`

echo "INFO: Утилита управления кластером (rac) будет запущена из каталога:"
echo "  "$RAC_BASE_DIR/$RAC_SUBDIR

# Проверка наличия внутри подпапки файла с нaзванием "rac" (исполнимый файл "менеджера кластера"):
if [ ! -f $RAC_BASE_DIR/$RAC_SUBDIR/rac ]; then
  echo "Утилита управления кластером (rac) не найдена!"
  # Немедленное завершение скрипта:
  echo "Завершение работы скрипта."
  exit
fi

SAVEIFS=$IFS   # Save current IFS (Internal Field Separator)
IFS=$'\n'      # Change IFS to newline char

# Запуск rac с параметром cluster list , размещение результата в переменной:
cluster_file=`$RAC_BASE_DIR/$RAC_SUBDIR/rac cluster list`

# echo "DEBUG: cluster file content: "$cluster_file

# Извлечение из переменной данных для четырёх массивов (остальные данные не нужны):
clusters_guids=( $(grep 'cluster' <<< "$cluster_file" | cut -d: -f2) )
clusters_hosts=( $(grep 'host' <<< "$cluster_file" | cut -d: -f2) )
clusters_ports=( $(grep 'port' <<< "$cluster_file" | cut -d: -f2) )
clusters_names=( $(grep 'name' <<< "$cluster_file" | cut -d: -f2) )

# Цикл по кол-ву элементов массива:
for ((i=0; i < ${#clusters_guids[@]}; i++))
do
  echo "====================="
  echo $i". Найден кластер:"
  # Элемент массива (строка) без обрамляющих пробелов:
  echo "GUID:     "${clusters_guids[$i]#* }
  echo "Сервер:   "${clusters_hosts[$i]#* }
  echo "Порт:     "${clusters_ports[$i]#* }
  echo "Описание: "${clusters_names[$i]#* }

  # Подготовка файла для вывода результата:
  echo "# В кластере под названием" \
    ${clusters_names[$i]#* } \
    "на сервере" \
    ${clusters_hosts[$i]#* }":"${clusters_ports[$i]#* } \
    "обнаружены базы:" \
    >> $PURGELOGS_CFG

  # Получение (в переменную) списка баз по GIUD очередного кластера:
  infobase_file=`$RAC_BASE_DIR/$RAC_SUBDIR/rac infobase summary list --cluster=${clusters_guids[$i]#* }`
  # echo "DEBUG: infobase file content: "$infobase_file
  # Извлечение из переменной данных в три массива:
  infobases_guids=( $(grep 'infobase' <<< "$infobase_file" | cut -d: -f2) )
  infobases_names=( $(grep 'name' <<< "$infobase_file" | cut -d: -f2) )
  infobases_descriptions=( $(grep 'desc' <<< "$infobase_file" | cut -d: -f2) )

  # Цикл по количеству найденных баз:  
  for ((j=0; j < ${#infobases_guids[@]}; j++))
  do
    echo "  ====================="
    echo "  "$j". Найдена база:"
    # Элемент массива (строка) без обрамляющих пробелов:
    echo "  GUID базы: "${infobases_guids[$j]#* }
    echo "  Имя:       "${infobases_names[$j]#* }
    echo "  Описание:  "${infobases_descriptions[$j]#* }
    echo "  ====================="
    # Сохранение информации о рабочей папке очередной базы как результат работы срипта:
    echo ${infobases_names[$j]#* }"="$WORK_DIR"/reg_"${clusters_ports[$i]#* }"/"${infobases_guids[$j]#* } >> $PURGELOGS_CFG

  done
  echo "====================="
done

echo "Информация о найденых базах сохранена в файл: "$PURGELOGS_CFG
sync

IFS=$SAVEIFS   # Restore original IFS
# END OF SCRIPT
