#!/bin/bash
#
# 1C Bases Logs Purge Script
#
# (c) ALLIANCE GROUP, 2024
# v 2024-01-24
#
#
# ======================================================
# WARNINIG: Prefer to run on Debian based OSes!
# ======================================================
#

# Сохранить этот (основной) скрипт (purge1clogs.sh) и вспомогательный (detectcluster.sh), например, в домашнюю папку пользователю usr1cv8:
# /home/usr1cv8/
# Запустить вспомогательный скрипт (можно без параметров). В результате, если вспомогательный скрипт отработает удачно,
# то в той же папке будет создан файл localbases.cfg (если нужно другое имя, то указать его как параметр запуска скрипта).
# Файл localbases.cfg используется основным скриптом как источник сведений о рабочих папках баз 1с.
# Вспомогательный скрипт необходимо запускать при каждом изменении списка баз на сервере (либо добавить его запуск в расписание).
#
#
# Добавление запуска основного и вспомогательного скрипта в расписание пользователю usr1cv8:
#   crontab -u usr1cv8 -e
# 
# 05 00 * * * bash ~/purge1clogs.sh
# 00 00 * * 0 bash ~/detectcluster.sh
#
# 05 00 * * * <- каждый день в пять минут после полуночи
# 00 00 * * 0 <- ровно в полночь каждое воскресенье
#
#
# Если скрипт запущен без указания файла с описанием баз (полный путь и имя такого файла),
# то будет использован файл localbases.cfg, который должен находиться в той же папке, что и скрипт.
#
# Протокол работы этого скрипта будет помещен в лог /tmp/purge1clogs.log 
# (если не указано другое значение соответствующей переменной).
#
# "Глубина" архивации (сжатия) и удаления файлов задаётся в соответствующих переменных в этом файле.
#
#
# Настройка ротации логов:
#
#   sudo apt install logrotate
#
# В папке /etc/logrotate.d/ создать файл с именем (например) purge1clogs, содержащий:
# /var/log/purge1clogs.log {
#    weekly
#    rotate 7
#    compress
#    missingok
#    create usr1cv8 grp1cv8
#    su usr1cv8 grp1cv8
# }
#
# В папке /var/log/ создать файл (пустой) purge1clogs.log и назначить его владельцем пользователя usr1cv8
#   chown usr1cv8:grp1cv8 /var/log/purge1clogs.log
#
# Проверка (ручным запуском) процедуры ротации логов:
#   sudo logrotate -vf /etc/logrotate.d/purge1clogs
#
#
# TODO: 1) Указывать в файле настроек для каждой базы свой период архивирования и удаления (в днях). 
#          Если не указано, то использовать значения по-умолчанию.
#       2) Регулировать объем отладочной и рабочей информации
#          (настройкой через перменную в скрипте или параметрами в командной строке).
#
#


# ПЕРЕМЕННЫЕ И КОНСТАНТЫ:
# Все файлы, которые старше этой даты будут заархивированы (сжаты):
ARCHIVE_PERIOD=`date +%Y%m%d --date="14 days ago"`
# Все файлы, которые старше этой даты будут удалены:
REMOVE_PERIOD=`date +%Y%m%d --date="120 days ago"`
# Варианты для указания дат:
# day | days
# week | weeks
# month | months
# year | years

# Файл с путями к рабочих каталогам баз, логи которых нужно заархивировать/удалить:
PURGELOGS_CFG_NAME="localbases.cfg"
# Файл с журналом работы этого скрипта:
PURGELOGS_LOG="/var/log/purge1clogs.log"

# Функция определения каталога, в котором _находится_ этот скрипт:
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

echo "$(date) INFO: 1C Bases Logs Purge Script запущен!" | tee -a "$PURGELOGS_LOG"
echo "INFO: Будут архивированы (сжаты) файлы, созданные до даты: "$ARCHIVE_PERIOD | tee -a "$PURGELOGS_LOG"
echo "INFO: Будут удалены файлы, созданные до даты: "$REMOVE_PERIOD | tee -a "$PURGELOGS_LOG"
echo "INFO: Будет использован список баз из файла: "$PURGELOGS_CFG | tee -a "$PURGELOGS_LOG"
echo "INFO: Журнал работы скрипта будет добавлен к файлу: "$PURGELOGS_LOG

# echo "DEBUG: Содержимое файла "$PURGELOGS_CFG" :" | tee -a "$PURGELOGS_LOG"
# cat $PURGELOGS_CFG | tee -a "$PURGELOGS_LOG"

SAVEIFS=$IFS   # Save current IFS (Internal Field Separator)
# IFS=$'\n'      # Change IFS to newline char # Для этого скрипта не требуется...

# Считывание файла настроек (построчно), с размещением полученных данных в двух массивах.
# Из строки вида
#   имя_базы=путь_к_рабочему_каталогу_базы
# текст до символа '=' будет помещен в первый массив, а тот, что после -- во второй.
while read line; do 
    bases_names+=($(echo "$line" | cut -d'=' -f1))
    bases_paths+=($(echo "$line" | cut -d'=' -f2))
    # Пустые строки и строки, начинающиеся с символа '#' будут пропущены:
done < <(sed -e 's/[[:space:]]*#.*// ; /^[[:space:]]*$/d' "$PURGELOGS_CFG")

echo "DEBUG: В файле настроек найдено записей о базах: "${#bases_names[@]}" шт." | tee -a "$PURGELOGS_LOG"

for ((i=0; i < ${#bases_names[@]}; i++))
do
  echo "=====================" | tee -a "$PURGELOGS_LOG"
  echo $i". Обработка рабочего каталога базы "${bases_names[$i]#* } | tee -a "$PURGELOGS_LOG"
  echo "Каталог:  "${bases_paths[$i]#* } | tee -a "$PURGELOGS_LOG"

  echo "INFO: Файлы журнала и их индексы, подлежащие архивации (сжатию):" | tee -a "$PURGELOGS_LOG"
  FILES_TO_COMPRESS=`find ${bases_paths[$i]#* }/1Cv8Log -type f \( -name "*.lgp" -or -name "*.lgx" \) | sort`;

  for CURRENT_FILE in ${FILES_TO_COMPRESS}
  do
    [[ ${CURRENT_FILE##*/} < ${ARCHIVE_PERIOD} ]] && bzip2 -z --best -s ${CURRENT_FILE} && echo "Сжатие файла: "${CURRENT_FILE} | tee -a "$PURGELOGS_LOG"
  done
  # Дополнительные опции для архиватора bzip2:
  # -z -- собственно сжатие,
  # --best или -9 -- максимальное сжатие,
  # -s -- использовать как можно меньше памяти.

  echo "NOTE: Файлы (архивы), подлежащие удалению:" | tee -a "$PURGELOGS_LOG"
  FILES_TO_REMOVE=`find ${bases_paths[$i]#* }/1Cv8Log -type f -name *.bz2 | sort`;

  for CURRENT_FILE in ${FILES_TO_REMOVE}
  do
    [[ ${CURRENT_FILE##*/} < ${REMOVE_PERIOD} ]] && rm -f ${CURRENT_FILE} && echo "Удаление:" ${CURRENT_FILE} | tee -a "$PURGELOGS_LOG"
  done

done

IFS=$SAVEIFS   # Restore original IFS

echo "$(date) INFO: 1C Bases Logs Purge Script завершен!" | tee -a "$PURGELOGS_LOG"
# END OF SCRIPT
