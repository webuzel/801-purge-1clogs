#!/bin/bash

# Enable 1C Bases Logs Purge Script
#
# (c) ALLIANCE GROUP, 2024
# v 2024-01-22

# Варианты запуска:
# - Запуск скрипта без параметров: использует файл hosts, который должен быть в той же папке. 
#   Группа: servers1c
#   (Примечание: Название группы задаётся переменными в этом скрипте)
#
# - Запуск с параметром в виде IP-адреса удалённого компьютера (сервера).
#
# - Запуск с параметрами в виде IP-адреса удалённого компьютера и имени пользователя,
#   у которого там (на удалённом компьютере) административные полномочия.
#   (Примечание: В этом случае будет дополнительно запрошен пароль указанного пользователя)


# ПЕРЕМЕННЫЕ (можно/нужно менять по необходимости).
# Имя файла с Ansible-плейбуком (должен находиться в одной папке с этим скриптом):
yaml_filename="801-enable-1clogs-purge.yaml"

hosts_file_name="hosts"
hosts_group="servers1c"

#Имя пользователя (и его группа), от имени которого (обычно) запускается сервис 1С-сервера на linux-сервере:
SRV1CV8_USER_DEFAULT="usr1cv8"
SRV1CV8_GROUP_DEFAULT="grp1cv8"

ANSIBLE_HOSTS_FILE_CMD="-i "$hosts_file_name
DUMMY_IP="127.0.0.1" # Если не был указан IP-адрес удалённого компьютера и будет использован файл hosts

# Вспомогательные переменные.
# Для форматирования вывода в консоль (для текста: 'полужирный' и 'нормальный'):
bold=$(tput bold)
normal=$(tput sgr0)
undeln=$(tput smul)
nounderln=$(tput rmul)
blink=$(tput blink)
# setaf <value>	Set foreground color
# setab <value>	Set background color
# Value	Color
# 0	Black
# 1	Red
# 2	Green
# 3	Yellow
# 4	Blue
# 5	Magenta
# 6	Cyan
# 7	White
# 8	Not used
# 9	Reset to default color


script_name=$0

# Функция, которая показывает 'как запускать скрипт':
showhelp(){
  printf "Скрипт можно запускать с параметрами:\n \
  $script_name target_ip_address [admin_username]\n \
  где, \n \
    ${bold}$script_name${normal} -- актуальное имя файла, содержащее этот скрипт;\n \
    ${bold}target_ip_address${normal} -- IP-адрес удалённого компьютера (сервера), к которому применяется этот скрипт;\n \
    ${bold}admin_username${normal}    -- необязательный параметр, указывающий от имени какого пользователя\n \
        запускать скрипт на удалённом компьютере (сервере).\n \
        (ВАЖНО: Этот пользователь должен обладать там административными полномочиями)\n \
        (ВАЖНО: В процессе выполнения скрипта будет предложено ввести пароль этого пользователя)\n\n"
}

# Функция, которая показывает какие параметры будут использованы при запуске плейбука:
showruncondition(){
  printf "\nДля запуска плейбука $yaml_filename будут использованы следующие параметры:\n \
  IP-адрес целевого компьютера (сервера): ${bold}$remote_ip${normal}\n \
  "
  # Если в функцию был передан параметр, то распечатать его как имя пользователя с административными полномочиями
  if [[ -n $1 ]]; then
    printf "  Уч.запись администратора: ${bold}$admin_username${normal}\n"
  fi
}

# Функция вывода строки текста "в цвете" (плюс перевод строки)
IRed='\e[0;91m'         # Красный
IGreen='\e[0;92m'       # Зелёный
ICyan='\e[0;96m'        # Синий
Color_Off='\e[0m'       # Цвет по-умолчанию
printf_color() {
	printf "%b%s%b\n" "$1" "$2" "$Color_Off"
}
# Пример:
# printf_color "$IRed" "Текст красным..."


# Отладочная информация:
printf "DEBUG: Скрипт ${bold}$0${normal} запущен с параметрами:\n $1\n $2\n $3\n"

# Если в командной строке указан первый параметр, то принять его как IP-адрес удалённого компьютера (сервера): 
if [[ -n $1 ]]; then 
  remote_ip=$1
  # В ansible-скрипте будет использован псевдо-hosts файл из одного адреса
  hosts_group="temp"
# Если параметр не указан, то вывести сообщение :
else
  printf "Не указаны параметры командной строки.\n"
  showhelp
  printf "Для запуска ansible-скрипта будет использован файл ${bold}hosts${normal} (который должен находиться в текущей папке).\n"
  printf "Группа хостов должна называться: ${bold}$hosts_group${normal} .\n"
  ANSIBLE_HOSTS_FILE="-i hosts"
  remote_ip=$DUMMY_IP
  # exit 1
fi

# Если в командной строке был указан второй параметр, то принять его как имя администратора на удалённой машине,
# дополнительно запросить пароль и запустить Ansible плейбук в варианте с явным указанием sudo-пользователя:
if [[ -n $2 ]]; then 
  admin_username=$2

  # Получение пароля администратора:
  printf "Указано имя администратора ($admin_username), под которым скрипт будет выполнен на удалённом компьютере (сервере).\n"
  read -p "Введите его пароль (или нажмите [Enter] для выхода): " -s admin_pass

  if [[ -n $admin_pass ]]; then
    ssh_pass=$admin_pass
    ssh_user=$admin_username
  else
    # Если пароль указан не был, то сообщить об этом и прервать выполнение скрипта:
    printf_color "$IRed" "Пароль администратора не введён. Выход из скрипта."
    exit 1
  fi

  showruncondition $admin_username

  ansible-playbook --ssh-extra-args "-o IdentitiesOnly=yes -o StrictHostKeyChecking=no" \
                   --extra-vars " \
                     remote_ip=$remote_ip \
                     ansible_user=$ssh_user \
                     ansible_ssh_pass=$ssh_pass \
                     ansible_sudo_pass=$ssh_pass \
                     service_user=$SRV1CV8_USER_DEFAULT \
                     service_group=$SRV1CV8_GROUP_DEFAULT \
                     hosts_group=$hosts_group \
                   " \
                   $ANSIBLE_HOSTS_FILE_CMD \
                   $yaml_filename

# Если административная уч.запись не указана, то запустить плейбук в расчёте на наличие на целевом компьютере ssh-ключа:
else
  if [[ ! -n $ANSIBLE_HOSTS_FILE ]];then
    showruncondition $admin_username
  else
    echo "DEBUG: hosts file parameter: "$ANSIBLE_HOSTS_FILE_CMD
    echo "DEBUG: hosts group: "$hosts_file_group
  fi
  ansible-playbook --user root \
                   --ssh-extra-args "-o IdentitiesOnly=yes -o StrictHostKeyChecking=no" \
                   --extra-vars " \
                     remote_ip=$remote_ip \
                     service_user=$SRV1CV8_USER_DEFAULT \
                     service_group=$SRV1CV8_GROUP_DEFAULT \
                     hosts_group=$hosts_group \
                   " \
                   $ANSIBLE_HOSTS_FILE_CMD \
                   $yaml_filename

fi
