#!/bin/sh

: <<-'EOF'
Copyright 2017-2019 Xingwang Liao < kuoruan@gmail.com >
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
http://www.apache.org/licenses/LICENSE-2.0
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
EOF

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Version information, please do not modify it
# =================
SHELL_VERSION=25
CONFIG_VERSION=6
INIT_VERSION=3
# =================

KCPTUN_INSTALL_DIR='/usr/local/kcptun'
KCPTUN_LOG_DIR='/var/log/kcptun'
KCPTUN_RELEASES_URL='https://api.github.com/repos/xtaci/kcptun/releases'
KCPTUN_LATEST_RELEASE_URL="${KCPTUN_RELEASES_URL}/latest"
KCPTUN_TAGS_URL='https://github.com/xtaci/kcptun/tags'

BASE_URL='https://github.com/kuoruan/shell-scripts/raw/master/kcptun'
SHELL_VERSION_INFO_URL="${BASE_URL}/version.json"

JQ_DOWNLOAD_URL="https://github.com/stedolan/jq/releases/download/jq-1.5/"
JQ_LINUX32_URL="${JQ_DOWNLOAD_URL}/jq-linux32"
JQ_LINUX64_URL="${JQ_DOWNLOAD_URL}/jq-linux64"
JQ_LINUX32_HASH='ab440affb9e3f546cf0d794c0058543eeac920b0cd5dff660a2948b970beb632'
JQ_LINUX64_HASH='c6b3a7d7d3e7b70c6f51b706a3b90bd01833846c54d32ca32f0027f00226ff6d'
JQ_BIN="${KCPTUN_INSTALL_DIR}/bin/jq"

SUPERVISOR_SERVICE_FILE_DEBIAN_URL="${BASE_URL}/startup/supervisord.init.debain"
SUPERVISOR_SERVICE_FILE_REDHAT_URL="${BASE_URL}/startup/supervisord.init.redhat"
SUPERVISOR_SYSTEMD_FILE_URL="${BASE_URL}/startup/supervisord.systemd"

#Default parameters
# =======================
D_LISTEN_PORT=29900
D_TARGET_ADDR='127.0.0.1'
D_TARGET_PORT=12984
D_KEY="very fast"
D_CRYPT='aes'
D_MODE='fast'
D_MTU=1350
D_SNDWND=512
D_RCVWND=512
D_DATASHARD=10
D_PARITYSHARD=3
D_DSCP=0
D_NOCOMP='false'
D_QUIET='false'
D_TCP='false'
D_SNMPPERIOD=60
D_PPROF='false'

# Hidden parameters
D_ACKNODELAY='false'
D_NODELAY=1
D_INTERVAL=20
D_RESEND=2
D_NC=1
D_SOCKBUF=4194304
D_SMUXBUF=4194304
D_KEEPALIVE=10
# ======================

# Currently selected instance ID
current_instance_id=""
run_user='kcptun'

clear

cat >&1 <<-'EOF'
################################################ #######
# Kcptun server one-click installation script #
# This script supports the installation, update, uninstallation and configuration of Kcptun server #
# Script author: Index < kuoruan@gmail.com > #
# Author's blog: https://blog.kuoruan.com/ #
# Github: https://github.com/kuoruan/shell-scripts #
# QQ communication group: 43391448, 68133628 #
# 633945405 #
################################################ #######
EOF

# Print help information
usage() {
cat >&1 <<-EOF

Please use: $0 <option>

Available parameters <option> include:

install install
uninstall uninstall
update check for updates
manual Customized Kcptun version installation
help View script usage instructions
add adds an instance, multi-port acceleration
reconfig <id> Reconfigure the instance
show <id> displays detailed configuration of the instance
log <id> displays instance logs
del <id> deletes an instance

Note: <id> in the above parameters is optional and represents the ID of the instance.
You can use 1, 2, 3... corresponding to the instances kcptun, kcptun2, kcptun3... respectively.
If <id> is not specified, it defaults to 1

Supervisor command:
service supervisord {start|stop|restart|status}
{Start | Shut down | Restart | View status}
Kcptun related commands:
supervisorctl {start|stop|restart|status} kcptun<id>
{Start | Shut down | Restart | View status}
EOF

exit $1
}

# Determine whether the command exists
command_exists() {
command -v "$@" >/dev/null 2>&1
}

# Determine whether the input content is a number
is_number() {
expr "$1" + 1 >/dev/null 2>&1
}

# Press any key to continue
any_key_to_continue() {
echo "Please press any key to continue or Ctrl + C to exit"
local saved=""
saved="$(stty -g)"
stty-echo
stty cbreak
dd if=/dev/tty bs=1 count=1 2>/dev/null
stty-raw
stty echo
stty $saved
}

first_character() {
if [ -n "$1" ]; then
echo "$1" | cut -c1
fi
}

# Check if you have root permissions
check_root() {
local user=""
user="$(id -un 2>/dev/null || true)"
if [ "$user" != "root" ]; then
cat >&2 <<-'EOF'
Permission error, please use root user to run this script!
EOF
exit 1
fi
}

# Get the IP address of the server
get_server_ip() {
local server_ip=""
local interface_info=""

if command_exists ip; then
interface_info="$(ip addr)"
elif command_exists ifconfig; then
interface_info="$(ifconfig)"
fi

server_ip=$(echo "$interface_info" | \
grep -oE "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3} " | \
grep -vE "^192\.168|^172\.1[6-9]\.|^172\.2[0-9]\.|^172\.3[0-2]\.|^ 10\.|^127\.|^255\.|^0\." | \
head -n 1)

# When automatic acquisition fails, obtain the external network address through the API provided by the website.
if [ -z "$server_ip" ]; then
server_ip="$(wget -qO- --no-check-certificate https://ipv4.icanhazip.com)"
fi

echo "$server_ip"
}

# Disable selinux
disable_selinux() {
local selinux_config='/etc/selinux/config'
if [ -s "$selinux_config" ]; then
if grep -q "SELINUX=enforcing" "$selinux_config"; then
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' "$selinux_config"
setenforce 0
fi
fi
}

# Get current operating system information
get_os_info() {
lsb_dist=""
dist_version=""
if command_exists lsb_release; then
lsb_dist="$(lsb_release -si)"
fi

if [ -z "$lsb_dist" ]; then
[ -r /etc/lsb-release ] && lsb_dist="$(. /etc/lsb-release && echo "$DISTRIB_ID")"
[ -r /etc/debian_version ] && lsb_dist='debian'
[ -r /etc/fedora-release ] && lsb_dist='fedora'
[ -r /etc/oracle-release ] && lsb_dist='oracleserver'
[ -r /etc/centos-release ] && lsb_dist='centos'
[ -r /etc/redhat-release ] && lsb_dist='redhat'
[ -r /etc/photon-release ] && lsb_dist='photon'
[ -r /etc/os-release ] && lsb_dist="$(. /etc/os-release && echo "$ID")"
fi
 

lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"

if [ "${lsb_dist}" = "redhatenterpriseserver" ]; then
lsb_dist='redhat'
fi

case "$lsb_dist" in
ubuntu)
if command_exists lsb_release; then
dist_version="$(lsb_release --codename | cut -f2)"
fi
if [ -z "$dist_version" ] && [ -r /etc/lsb-release ]; then
dist_version="$(. /etc/lsb-release && echo "$DISTRIB_CODENAME")"
fi
;;

debian|raspbian)
dist_version="$(cat /etc/debian_version | sed 's/\/.*//' | sed 's/\..*//')"
case "$dist_version" in
9)
dist_version="stretch"
;;
8)
dist_version="jessie"
;;
7)
dist_version="wheezy"
;;
esac
;;

oracleserver)
lsb_dist="oraclelinux"
dist_version="$(rpm -q --whatprovides redhat-release --queryformat "%{VERSION}\n" | sed 's/\/.*//' | sed 's/\..*//' | sed 's/Server*//')"
;;

fedora|centos|redhat)
dist_version="$(rpm -q --whatprovides ${lsb_dist}-release --queryformat "%{VERSION}\n" | sed 's/\/.*//' | sed 's/\..*/ /' | sed 's/Server*//' | sort | tail -1)"
;;

"vmware photon")
lsb_dist="photon"
dist_version="$(. /etc/os-release && echo "$VERSION_ID")"
;;

*)
if command_exists lsb_release; then
dist_version="$(lsb_release --codename | cut -f2)"
fi
if [ -z "$dist_version" ] && [ -r /etc/os-release ]; then
dist_version="$(. /etc/os-release && echo "$VERSION_ID")"
fi
;;
esac

if [ -z "$lsb_dist" ] || [ -z "$dist_version" ]; then
cat >&2 <<-EOF
Unable to determine server system version information.
Please contact the script author.
EOF
exit 1
fi
}

# Get the server architecture and Kcptun server file suffix name
get_arch() {
architecture="$(uname -m)"
case "$architecture" in
amd64|x86_64)
spruce_type='linux-amd64'
file_suffix='linux_amd64'
;;
i386|i486|i586|i686|x86)
spruce_type='linux-386'
file_suffix='linux_386'
;;
*)
cat 1>&2 <<-EOF
The current script only supports 32-bit and 64-bit systems
Your system is: $architecture
EOF
exit 1
;;
esac
}

# Get API content
get_content() {
local url="$1"
local retry=0

local content=""
get_network_content() {
if [ $retry -ge 3 ]; then
cat >&2 <<-EOF
Failed to obtain network information!
URL: ${url}
The installation script needs to be able to access github.com, please check the server network.
Note: Some domestic servers may not be able to access github.com normally.
EOF
exit 1
fi

# Replace all line breaks with custom tags to prevent jq parsing failure
content="$(wget -qO- --no-check-certificate "$url" | sed -r 's/(\\r)?\\n/#br#/g')"

if [ "$?" != "0" ] || [ -z "$content" ]; then
retry=$(expr $retry + 1)
get_network_content
fi
}

get_network_content
echo "$content"
}

# Download files, retry 3 times by default
download_file() {
local url="$1"
local file="$2"
local verify="$3"
local retry=0
local verify_cmd=""

verify_file() {
if [ -z "$verify_cmd" ] && [ -n "$verify" ]; then
if [ "${#verify}" = "32" ]; then
verify_cmd="md5sum"
elif [ "${#verify}" = "40" ]; then
verify_cmd="sha1sum"
elif [ "${#verify}" = "64" ]; then
verify_cmd="sha256sum"
elif [ "${#verify}" = "128" ]; then
verify_cmd="sha512sum"
fi

if [ -n "$verify_cmd" ] && ! command_exists "$verify_cmd"; then
verify_cmd=""
fi
fi

if [ -s "$file" ] && [ -n "$verify_cmd" ]; then
(
set -x
echo "${verify} ${file}" | $verify_cmd -c
)
return $?
fi

return 1
}

download_file_to_path() {
if verify_file; then
return 0
fi

if [ $retry -ge 3 ]; then
rm -f "$file"
cat >&2 <<-EOF
File download or verification failed! Please try again.
URL: ${url}
EOF

if [ -n "$verify_cmd" ]; then
cat >&2 <<-EOF
If the download fails multiple times, you can download the file manually:
1. Download file ${url}
2. Rename the file to $(basename "$file")
3. Upload the file to the directory $(dirname "$file")
4. Rerun the installation script

Note: File directory. represents the current directory, .. represents the superior directory of the current directory.
EOF
fi
exit 1
fi

( set -x; wget -O "$file" --no-check-certificate "$url" )
if [ "$?" != "0" ] || [ -n "$verify_cmd" ] && ! verify_file; then
retry=$(expr $retry + 1)
download_file_to_path
fi
}

download_file_to_path
}

#Install jq for parsing and generating json files
# jq has entered the software repositories of most Linux distributions.
# URL: https://stedolan.github.io/jq/download/
# However, in order to prevent some system installation failures, it is still provided through a script.
install_jq() {
check_jq() {
if [ ! -f "$JQ_BIN" ]; then
return 1
fi

[ ! -x "$JQ_BIN" ] && chmod a+x "$JQ_BIN"

if ( $JQ_BIN --help 2>/dev/null | grep -q "JSON" ); then
is_checked_jq="true"
return 0
else
rm -f "$JQ_BIN"
return 1
fi
}

if [ -z "$is_checked_jq" ] && ! check_jq; then
local dir=""
dir="$(dirname "$JQ_BIN")"
if [ ! -d "$dir" ]; then
(
set -x
mkdir -p "$dir"
)
fi

if [ -z "$architecture" ]; then
get_arch
fi

case "$architecture" in
amd64|x86_64)
download_file "$JQ_LINUX64_URL" "$JQ_BIN" "$JQ_LINUX64_HASH"
;;
i386|i486|i586|i686|x86)
download_file "$JQ_LINUX32_URL" "$JQ_BIN" "$JQ_LINUX32_HASH"
;;
esac

if ! check_jq; then
cat >&2 <<-EOF
No JSON parsing software jq found for the current system
EOF
exit 1
fi

return 0
fi
}

# Read the value of an item in the json file
get_json_string() {
install_jq

local content="$1"
local selector="$2"
local regex="$3"

local str=""
if [ -n "$content" ]; then
str="$(echo "$content" | $JQ_BIN -r "$selector" 2>/dev/null)"

if [ -n "$str" ] && [ -n "$regex" ]; then
str="$(echo "$str" | grep -oE "$regex")"
fi
fi
echo "$str"
}

# Get the configuration file path of the current instance and pass in the parameters:
# * config: kcptun server configuration file
# * log: kcptun log file path
# * snmp: kcptun snmp log file path
# * supervisor: supervisor file path of the instance
get_current_file() {
case "$1" in
config)
printf '%s/server-config%s.json' "$KCPTUN_INSTALL_DIR" "$current_instance_id"
;;
log)
printf '%s/server%s.log' "$KCPTUN_LOG_DIR" "$current_instance_id"
;;
snmp)
printf '%s/snmplog%s.log' "$KCPTUN_LOG_DIR" "$current_instance_id"
;;
supervisor)
printf '/etc/supervisor/conf.d/kcptun%s.conf' "$current_instance_id"
;;
esac
}

# Get the number of instances
get_instance_count() {
if [ -d '/etc/supervisor/conf.d/' ]; then
ls -l '/etc/supervisor/conf.d/' | grep "^-" | awk '{print $9}' | grep -cP "^kcptun\d*\.conf$"
else
echo "0"
fi
}

# Obtain the release information of the corresponding version number Kcptun through API
# Pass in the Kcptun version number
get_kcptun_version_info() {
local request_version="$1"

local version_content=""
if [ -n "$request_version" ]; then
local json_content=""
json_content="$(get_content "$KCPTUN_RELEASES_URL")"
local version_selector=".[] | select(.tag_name == \"${request_version}\")"
version_content="$(get_json_string "$json_content" "$version_selector")"
else
version_content="$(get_content "$KCPTUN_LATEST_RELEASE_URL")"
fi

if [ -z "$version_content" ]; then
return 1
fi

if [ -z "$spruce_type" ]; then
get_arch
fi

local url_selector=".assets[] | select(.name | contains(\"${spruce_type}\")) | .browser_download_url"
kcptun_release_download_url="$(get_json_string "$version_content" "$url_selector")"

if [ -z "$kcptun_release_download_url" ]; then
return 1
fi

kcptun_release_tag_name="$(get_json_string "$version_content" '.tag_name')"
kcptun_release_name="$(get_json_string "$version_content" '.name')"
kcptun_release_prerelease="$(get_json_string "$version_content" '.prerelease')"
kcptun_release_publish_time="$(get_json_string "$version_content" '.published_at')"
kcptun_release_html_url="$(get_json_string "$version_content" '.html_url')"

local body_content="$(get_json_string "$version_content" '.body')"
local body="$(echo "$body_content" | sed 's/#br#/\n/g' | grep -vE '(^```)|(^>)|(^[[:space:] ]*$)|(SUM$)')"

kcptun_release_body="$(echo "$body" | grep -vE "[0-9a-zA-Z]{32,}")"

local file_verify=""
file_verify="$(echo "$body" | grep "$spruce_type")"

if [ -n "$file_verify" ]; then
local i="1"
local split=""
while true
do
split="$(echo "$file_verify" | cut -d ' ' -f$i)"

if [ -n "$split" ] && ( echo "$split" | grep -qE "^[0-9a-zA-Z]{32,}$" ); then
kcptun_release_verify="$split"
break
elif [ -z "$split" ]; then
break
fi

i=$(expr $i + 1)
done
fi

return 0
}

# Get script version information
get_shell_version_info() {
local shell_version_content=""
shell_version_content="$(get_content "$SHELL_VERSION_INFO_URL")"
if [ -z "$shell_version_content" ]; then
return 1
fi

new_shell_version="$(get_json_string "$shell_version_content" '.shell_version' '[0-9]+')"
new_config_version="$(get_json_string "$shell_version_content" '.config_version' '[0-9]+')"
new_init_version="$(get_json_string "$shell_version_content" '.init_version' '[0-9]+')"

shell_change_log="$(get_json_string "$shell_version_content" '.change_log')"
config_change_log="$(get_json_string "$shell_version_content" '.config_change_log')"
init_change_log="$(get_json_string "$shell_version_content" '.init_change_log')"
new_shell_url="$(get_json_string "$shell_version_content" '.shell_url')"


if [ -z "$new_shell_version" ]; then
new_shell_version="0"
fi
if [ -z "$new_config_version" ]; then
new_config_version="0"
fi
if [ -z "$new_init_version" ]; then
new_init_version="0"
fi

return 0
}

# Download and install Kcptun
install_kcptun() {
if [ -z "$kcptun_release_download_url" ]; then
get_kcptun_version_info "$1"

if [ "$?" != "0" ]; then
cat >&2 <<-'EOF'
Failed to obtain Kcptun version information or download address!
It may be that GitHub has changed its version, or the content obtained from the Internet is incorrect.
Please contact the script author.
EOF
exit 1
fi
fi

local kcptun_file_name="kcptun-${kcptun_release_tag_name}.tar.gz"
download_file "$kcptun_release_download_url" "$kcptun_file_name" "$kcptun_release_verify"

if [ ! -d "$KCPTUN_INSTALL_DIR" ]; then
(
set -x
mkdir -p "$KCPTUN_INSTALL_DIR"
)
fi

if [ ! -d "$KCPTUN_LOG_DIR" ]; then
(
set -x
mkdir -p "$KCPTUN_LOG_DIR"
chmod a+w "$KCPTUN_LOG_DIR"
)
fi

(
set -x
tar -zxf "$kcptun_file_name" -C "$KCPTUN_INSTALL_DIR"
sleep 3
)

local kcptun_server_file=""
kcptun_server_file="$(get_kcptun_server_file)"

if [ ! -f "$kcptun_server_file" ]; then
cat >&2 <<-'EOF'
The Kcptun server executable file was not found in the decompressed file!
Usually this does not happen, the possible reason is that the Kcptun author changed the file name when packaging it.
You can try reinstalling, or contact the script author.
EOF
exit 1
fi

chmod a+x "$kcptun_server_file"

if [ -z "$(get_installed_version)" ]; then
cat >&2 <<-'EOF'
Unable to find kcptun executable for current server
You can try compiling from source.
EOF
exit 1
fi

rm -f "$kcptun_file_name" "${KCPTUN_INSTALL_DIR}/client_$file_suffix"
}

#Install dependent software
install_deps() {
if [ -z "$lsb_dist" ]; then
get_os_info
fi

case "$lsb_dist" in
ubuntu|debian|raspbian)
local did_apt_get_update=""
apt_get_update() {
if [ -z "$did_apt_get_update" ]; then
(set -x; sleep 3; apt-get update)
did_apt_get_update=1
fi
}

if ! command_exists wget; then
apt_get_update
( set -x; sleep 3; apt-get install -y -q wget ca-certificates )
fi

if ! command_exists awk; then
apt_get_update
( set -x; sleep 3; apt-get install -y -q gawk )
fi

if ! command_exists tar; then
apt_get_update
( set -x; sleep 3; apt-get install -y -q tar )
fi

if ! command_exists pip; then
apt_get_update
( set -x; sleep 3; apt-get install -y -q python-pip || true )
fi

if ! command_exists python; then
apt_get_update
( set -x; sleep 3; apt-get install -y -q python )
fi
;;
fedora|centos|redhat|oraclelinux|photon)
if [ "$lsb_dist" = "fedora" ] && [ "$dist_version" -ge "22" ]; then
if ! command_exists wget; then
( set -x; sleep 3; dnf -y -q install wget ca-certificates )
fi

if ! command_exists awk; then
( set -x; sleep 3; dnf -y -q install gawk )
fi

if ! command_exists tar; then
( set -x; sleep 3; dnf -y -q install tar )
fi

if ! command_exists pip; then
( set -x; sleep 3; dnf -y -q install python-pip || true )
fi

if ! command_exists python; then
(set -x; sleep 3; dnf -y -q install python)
fi
elif [ "$lsb_dist" = "photon" ]; then
if ! command_exists wget; then
( set -x; sleep 3; tdnf -y install wget ca-certificates )
fi

if ! command_exists awk; then
( set -x; sleep 3; tdnf -y install gawk )
fi

if ! command_exists tar; then
( set -x; sleep 3; tdnf -y install tar )
fi

if ! command_exists pip; then
( set -x; sleep 3; tdnf -y install python-pip || true )
fi

if ! command_exists python; then
(set -x; sleep 3; tdnf -y install python)
fi
else
if ! command_exists wget; then
( set -x; sleep 3; yum -y -q install wget ca-certificates )
fi

if ! command_exists awk; then
( set -x; sleep 3; yum -y -q install gawk )
fi

if ! command_exists tar; then
( set -x; sleep 3; yum -y -q install tar )
fi

# The software libraries of Red Hat operating systems such as CentOS may not include python-pip
# You can install epel-release first
if ! command_exists pip; then
( set -x; sleep 3; yum -y -q install python-pip || true )
fi

# If the python-pip installation fails, check whether the python environment has been installed
if ! command_exists python; then
(set -x; sleep 3; yum -y -q install python)
fi
fi
;;
*)
cat >&2 <<-EOF
The current system is not supported at the moment: ${lsb_dist} ${dist_version}
EOF

exit 1
;;
esac

# This determines whether there are software packages that failed to install, but the installation failure of python-pip is not handled by default.
# Next, the pip command will be uniformly detected and installed again.
if [ "$?" != 0 ]; then
cat >&2 <<-'EOF'
The installation of some dependent software failed,
Please check the logs to check for errors.
EOF
exit 1
fi

install_jq
}

# Install supervisor
install_supervisor() {
if [ -s /etc/supervisord.conf ] && command_exists supervisord; then
cat >&2 <<-EOF
It is detected that you have installed Supervisor through other methods, which will conflict with the Supervisor installed by this script.
It is recommended that you back up the current Supervisor configuration and then uninstall the original version.
The installed Supervisor configuration file path is: /etc/supervisord.conf
The path of the Supervisor configuration file installed through this script is: /etc/supervisor/supervisord.conf
You can use the following command to back up the original configuration file:

mv /etc/supervisord.conf /etc/supervisord.conf.bak
EOF

exit 1
fi

if ! command_exists python; then
cat >&2 <<-'EOF'
The python environment is not installed and the automatic installation fails. Please install the python environment manually.
EOF

exit 1
fi

local python_version="$(python -V 2>&1)"

if [ "$?" != "0" ] || [ -z "$python_version" ]; then
cat >&2 <<-'EOF'
The python environment is damaged and the version number cannot be obtained through python -V.
Please reinstall the python environment manually.
EOF

exit 1
fi

local version_string="$(echo "$python_version" | cut -d' ' -f2 | head -n1)"
local major_version="$(echo "$version_string" | cut -d'.' -f1)"
local minor_version="$(echo "$version_string" | cut -d'.' -f2)"

if [ -z "$major_version" ] || [ -z "$minor_version" ] || \
! ( is_number "$major_version" ); then
cat >&2 <<-EOF
Failed to obtain python size version number: ${python_version}
EOF

exit 1
fi

local is_python_26="false"

if [ "$major_version" -lt "2" ] || ( \
[ "$major_version" = "2" ] && [ "$minor_version" -lt "6" ] ); then
cat >&2 <<-EOF
Unsupported python version ${version_string}, currently only supports the installation of python 2.6 and above.
EOF

exit 1
elif [ "$major_version" = "2" ] && [ "$minor_version" = "6" ]; then
is_python_26="true"

cat >&1 <<-EOF
Note: The python version of the current server is ${version_string},
The script's support for python 2.6 and below may not work.
Please upgrade the python version to >= 2.7.9 or >= 3.4 as soon as possible.
EOF

any_key_to_continue
fi

if ! command_exists pip; then
# If the pip command is not detected, but python is already installed on the current server
# Use the get-pip.py script to install the pip command
if [ "$is_python_26" = "true" ]; then
(
set -x
wget -qO- --no-check-certificate https://bootstrap.pypa.io/2.6/get-pip.py | python
)
else
(
set -x
wget -qO- --no-check-certificate https://bootstrap.pypa.io/get-pip.py | python
)
fi
fi

# If the script installation still fails, prompt for manual installation.
if ! command_exists pip; then
cat >&2 <<-EOF
The installed pip command was not found. Please install python-pip manually first.
This script uses pip to install Supervisior since version v21.

1. For Debian Linux systems, you can try:
sudo apt-get install -y python-pip to install

2. For Redhat-based Linux systems, you can try using:
sudo yum install -y python-pip to install
* If the prompt is not found, you can try to install it first: epel-release extended software library

3. If the above methods fail, please use the following command to install manually:
wget -qO- --no-check-certificate https://bootstrap.pypa.io/get-pip.py | python
*Users of python 2.6 please use:
wget -qO- --no-check-certificate https://bootstrap.pypa.io/2.6/get-pip.py | python

4. After pip is installed, run the update command first:
pip install --upgrade pip

Check the pip version again:
pip -V

Once everything is correct, re-run the installation script.
EOF
exit 1
fi

if ! ( pip --version >/dev/null 2>&1 ); then
cat >&2 <<-EOF
The pip command of the current environment has been detected to be corrupted.
Please check your python environment.
EOF

exit 1
fi

if [ "$is_python_26" != "true" ]; then
# If pip is already installed, try updating it first.
# If it is python 2.6, do not update. Updating will cause pip damage.
# pip only supports python 2 >= 2.7.9
# https://pip.pypa.io/en/stable/installing/
(
set -x
pip install --upgrade pip || true
)
fi

if [ "$is_python_26" = "true" ]; then
(
set -x
pip install 'supervisor>=3.0.0,<4.0.0'
)
else
(
set -x
pip install --upgrade supervisor
)
fi

if [ "$?" != "0" ]; then
cat >&2 <<-EOF
Error: Installation of Supervisor failed,
Please try using
pip install supervisor
to install manually.
Supervisor no longer supports python 2.6 and below starting from 4.0
Users of python 2.6 please use:
pip install 'supervisor>=3.0.0,<4.0.0'
EOF

exit 1
fi

[ ! -d /etc/supervisor/conf.d ] && (
set -x
mkdir -p /etc/supervisor/conf.d
)

if [ ! -f '/usr/local/bin/supervisord' ]; then
(
set -x
ln -s "$(command -v supervisord)" '/usr/local/bin/supervisord' 2>/dev/null
)
fi

if [ ! -f '/usr/local/bin/supervisorctl' ]; then
(
set -x
ln -s "$(command -v supervisorctl)" '/usr/local/bin/supervisorctl' 2>/dev/null
)
fi

if [ ! -f '/usr/local/bin/pidproxy' ]; then
(
set -x
ln -s "$(command -v pidproxy)" '/usr/local/bin/pidproxy' 2>/dev/null
)
fi

local cfg_file='/etc/supervisor/supervisord.conf'

local rvt="0"

if [ ! -s "$cfg_file" ]; then
if ! command_exists echo_supervisord_conf; then
cat >&2 <<-'EOF'
echo_supervisord_conf not found, Supervisor configuration file cannot be automatically created!
It may be that the currently installed supervisor version is too low.
EOF
exit 1
fi

(
set -x
echo_supervisord_conf >"$cfg_file" 2>&1
)
rvt="$?"
fi

local cfg_content="$(cat "$cfg_file")"

# Error with supervisor config file
if ( echo "$cfg_content" | grep -q "Traceback (most recent call last)" ) ; then
rvt="1"

if ( echo "$cfg_content" | grep -q "DistributionNotFound: meld3" ); then
# https://github.com/Supervisor/meld3/issues/23
(
set -x
local temp="$(mktemp -d)"
local pwd="$(pwd)"

download_file 'https://pypi.python.org/packages/source/m/meld3/meld3-1.0.2.tar.gz' \
"$temp/meld3.tar.gz"

cd "$temp"
tar -zxf "$temp/meld3.tar.gz" --strip=1
python setup.py install
cd "$pwd"
)

if [ "$?" = "0" ] ; then
(
set -x
echo_supervisord_conf >"$cfg_file" 2>/dev/null
)
rvt="$?"
fi
fi
fi

if [ "$rvt" != "0" ]; then
rm -f "$cfg_file"
echo "Failed to create Supervisor configuration file!"
exit 1
fi

if ! grep -q '^files[[:space:]]*=[[:space:]]*/etc/supervisor/conf.d/\*\.conf$' "$cfg_file"; then
if grep -q '^\[include\]$' "$cfg_file"; then
sed -i '/^\[include\]$/a files = \/etc\/supervisor\/conf.d\/\*\.conf' "$cfg_file"
else
sed -i '$a [include]\nfiles = /etc/supervisor/conf.d/*.conf' "$cfg_file"
fi
fi

download_startup_file
}

download_startup_file() {
local supervisor_startup_file=""
local supervisor_startup_file_url=""

if command_exists systemctl; then
supervisor_startup_file="/etc/systemd/system/supervisord.service"
supervisor_startup_file_url="$SUPERVISOR_SYSTEMD_FILE_URL"

download_file "$supervisor_startup_file_url" "$supervisor_startup_file"
(
set -x
# Delete old service files

local old_service_file="/lib/systemd/system/supervisord.service"
if [ -f "$old_service_file" ]; then
rm -f "$old_service_file"
fi
systemctl daemon-reload >/dev/null 2>&1
)
elif command_exists service; then
supervisor_startup_file='/etc/init.d/supervisord'

if [ -z "$lsb_dist" ]; then
get_os_info
fi

case "$lsb_dist" in
ubuntu|debian|raspbian)
supervisor_startup_file_url="$SUPERVISOR_SERVICE_FILE_DEBIAN_URL"
;;
fedora|centos|redhat|oraclelinux|photon)
supervisor_startup_file_url="$SUPERVISOR_SERVICE_FILE_REDHAT_URL"
;;
*)
echo "There is no service startup script file suitable for the current system."
exit 1
;;
esac

download_file "$supervisor_startup_file_url" "$supervisor_startup_file"
(
set -x
chmod a+x "$supervisor_startup_file"
)
else
cat >&2 <<-'EOF'
The systemctl or service command is not installed on the current server, and the service cannot be configured.
Please install systemd or service manually before running the script.
EOF

exit 1
fi
}

start_supervisor() {
(set -x; sleep 3)
if command_exists systemctl; then
if systemctl status supervisord.service >/dev/null 2>&1; then
systemctl restart supervisord.service
else
systemctl start supervisord.service
fi
elif command_exists service; then
if service supervisord status >/dev/null 2>&1; then
service supervisord restart
else
service supervisord start
fi
fi

if [ "$?" != "0" ]; then
cat >&2 <<-'EOF'
Failed to start Supervisor, Kcptun cannot work properly!
Please give feedback to the script author.
EOF
exit 1
fi
}

enable_supervisor() {
if command_exists systemctl; then
(
set -x
systemctl enable "supervisord.service"
)
elif command_exists service; then
if [ -z "$lsb_dist" ]; then
get_os_info
fi

case "$lsb_dist" in
ubuntu|debian|raspbian)
(
set -x
update-rc.d -f supervisord defaults
)
;;
fedora|centos|redhat|oraclelinux|photon)
(
set -x
chkconfig --add supervisord
chkconfig supervisord on
)
;;
esac
fi
}

set_kcptun_config() {
is_port() {
local port="$1"
is_number "$port" && \
[ $port -ge 1 ] && [ $port -le 65535 ]
}

port_using() {
local port="$1"

if command_exists netstat; then
( netstat -ntul | grep -qE "[0-9:*]:${port}\s" )
elif command_exists ss; then
( ss -ntul | grep -qE "[0-9:*]:${port}\s" )
else
return 0
fi

return $?
}

local input=""
local yn=""

#Set the service running port
[ -z "$listen_port" ] && listen_port="$D_LISTEN_PORT"
while true
do
cat >&1 <<-'EOF'
Please enter the Kcptun server running port [1~65535]
This port is the port that the Kcptun client connects to.
EOF
read -p "(default: ${listen_port}): " input
if [ -n "$input" ]; then
if is_port "$input"; then
listen_port="$input"
else
echo "Incorrect input, please enter a number between 1~65535!"
continue
fi
fi

if port_using "$listen_port" && \
[ "$listen_port" != "$current_listen_port" ]; then
echo "The port is occupied, please re-enter!"
continue
fi
break
done

input=""
cat >&1 <<-EOF
--------------------------
port = ${listen_port}
--------------------------
EOF

[ -z "$target_addr" ] && target_addr="$D_TARGET_ADDR"
cat >&1 <<-'EOF'
Please enter the address that needs to be accelerated
You can enter a host name, IPv4 address, or IPv6 address
EOF
read -p "(default: ${target_addr}): " input
if [ -n "$input" ]; then
target_addr="$input"
fi

input=""
cat >&1 <<-EOF
--------------------------
Acceleration address = ${target_addr}
--------------------------
EOF

[ -z "$target_port" ] && target_port="$D_TARGET_PORT"
while true
do
cat >&1 <<-'EOF'
Please enter the port that needs to be accelerated [1~65535]
EOF
read -p "(default: ${target_port}): " input
if [ -n "$input" ]; then
if is_port "$input"; then
if [ "$input" = "$listen_port" ]; then
echo "The acceleration port cannot be the same as the Kcptun port!"
continue
fi

target_port="$input"
else
echo "Incorrect input, please enter a number between 1~65535!"
continue
fi
fi

if [ "$target_addr" = "127.0.0.1" ] && ! port_using "$target_port"; then
read -p "No software currently uses this port. Are you sure you want to accelerate this port? [y/n]: " yn
if [ -n "$yn" ]; then
case "$(first_character "$yn")" in
y|Y)
;;
*)
continue
;;
esac
fi
fi

break
done

input=""
yn=""
cat >&1 <<-EOF
--------------------------
Acceleration port = ${target_port}
--------------------------
EOF

[ -z "$key" ] && key="$D_KEY"
cat >&1 <<-'EOF'
Please set Kcptun password (key)
This parameter must be consistent on both sides
EOF
read -p "(default password: ${key}): " input
[ -n "$input" ] && key="$input"

input=""
cat >&1 <<-EOF
--------------------------
Password = ${key}
--------------------------
EOF

[ -z "$crypt" ] && crypt="$D_CRYPT"
local crypt_list="aes aes-128 aes-192 salsa20 blowfish twofish cast5 3des tea xtea xor none"
local i=0
cat >&1 <<-'EOF'
Please select encryption method (crypt)
Strong encryption has higher CPU requirements.
If you configure the client on the router,
Please try to choose weak encryption or no encryption.
This parameter must be consistent on both sides
EOF
while true
do

for c in $crypt_list; do
i=$(expr $i + 1)
echo "(${i}) ${c}"
done

read -p "(Default: ${crypt}) Please select [1~$i]: " input
if [ -n "$input" ]; then
if is_number "$input" && [ $input -ge 1 ] && [ $input -le $i ]; then
crypt=$(echo "$crypt_list" | cut -d' ' -f ${input})
else
echo "Please enter valid digits 1~$i!"
i=0
continue
fi
fi
break
done

input=""
i=0
cat >&1 <<-EOF
--------------------------
Encryption method = ${crypt}
--------------------------
EOF

[ -z "$mode" ] && mode="$D_MODE"
local mode_list="normal fast fast2 fast3 manual"
i=0
cat >&1 <<-'EOF'
Please select acceleration mode (mode)
The acceleration mode and the sending window size jointly determine the loss of traffic
If "manual" is selected for acceleration mode,
You will enter the settings of manual transmission hidden parameters.
EOF
while true
do

for m in $mode_list; do
i=$(expr $i + 1)
echo "(${i}) ${m}"
done

read -p "(Default: ${mode}) Please select [1~$i]: " input
if [ -n "$input" ]; then
if is_number "$input" && [ $input -ge 1 ] && [ $input -le $i ]; then
mode=$(echo "$mode_list" | cut -d ' ' -f ${input})
else
echo "Please enter valid digits 1~$i!"
i=0
continue
fi
fi
break
done

input=""
i=0
cat >&1 <<-EOF
--------------------------
acceleration mode = ${mode}
--------------------------
EOF

if [ "$mode" = "manual" ]; then
set_manual_parameters
else
nodelay=""
interval=""
resend=""
nc=""
fi

[ -z "$mtu" ] && mtu="$D_MTU"
while true
do
cat >&1 <<-'EOF'
Please set the MTU (Maximum Transmission Unit) value of UDP packets
EOF
read -p "(default: ${mtu}): " input
if [ -n "$input" ]; then
if ! is_number "$input" || [ $input -le 0 ]; then
echo "Incorrect input, please enter a number greater than 0!"
continue
fi

mtu=$input
fi
break
done

input=""
cat >&1 <<-EOF
--------------------------
MTU = ${mtu}
--------------------------
EOF

[ -z "$sndwnd" ] && sndwnd="$D_SNDWND"
while true
do
cat >&1 <<-'EOF'
Please set the sending window size (sndwnd)
If the sending window is too large, too much traffic will be wasted
EOF
read -p "(Number of packets, default: ${sndwnd}): " input
if [ -n "$input" ]; then
if ! is_number "$input" || [ $input -le 0 ]; then
echo "Incorrect input, please enter a number greater than 0!"
continue
fi

sndwnd=$input
fi
break
done

input=""
cat >&1 <<-EOF
--------------------------
sndwnd = ${sndwnd}
--------------------------
EOF

[ -z "$rcvwnd" ] && rcvwnd="$D_RCVWND"
while true
do
cat >&1 <<-'EOF'
Please set the receive window size (rcvwnd)
EOF
read -p "(Number of packets, default: ${rcvwnd}): " input
if [ -n "$input" ]; then
if ! is_number "$input" || [ $input -le 0 ]; then
echo "Incorrect input, please enter a number greater than 0!"
continue
fi

rcvwnd=$input
fi
break
done

input=""
cat >&1 <<-EOF
--------------------------
rcvwnd = ${rcvwnd}
--------------------------
EOF

[ -z "$datashard" ] && datashard="$D_DATASHARD"
while true
do
cat >&1 <<-'EOF'
Please set up forward error correction datashard
This parameter must be consistent on both sides
EOF
read -p "(default: ${datashard}): " input
if [ -n "$input" ]; then
if ! is_number "$input" || [ $input -lt 0 ]; then
echo "Incorrect input, please enter a number greater than or equal to 0!"
continue
fi

datashard=$input
fi
break
done

input=""
cat >&1 <<-EOF
--------------------------
datashard = ${datashard}
--------------------------
EOF

[ -z "$parityshard" ] && parityshard="$D_PARITYSHARD"
while true
do
cat >&1 <<-'EOF'
Please set forward error correction parityshard
This parameter must be consistent on both sides
EOF
read -p "(default: ${parityshard}): " input
if [ -n "$input" ]; then
if ! is_number "$input" || [ $input -lt 0 ]; then
echo "Incorrect input, please enter a number greater than or equal to 0!"
continue
fi

parityshard=$input
fi
break
done

input=""
cat >&1 <<-EOF
--------------------------
parityshard = ${parityshard}
--------------------------
EOF

[ -z "$dscp" ] && dscp="$D_DSCP"
while true
do
cat >&1 <<-'EOF'
Please set Differentiated Services Code Point (DSCP)
EOF
read -p "(default: ${dscp}): " input
if [ -n "$input" ]; then
if ! is_number "$input" || [ $input -lt 0 ]; then
echo "Incorrect input, please enter a number greater than or equal to 0!"
continue
fi

dscp=$input
fi
break
done

input=""
cat >&1 <<-EOF
--------------------------
DSCP = ${dscp}
--------------------------
EOF

[ -z "$nocomp" ] && nocomp="$D_NOCOMP"
while true
do
cat >&1 <<-'EOF'
Do you want to turn off data compression?
EOF
read -p "(default: ${nocomp}) [y/n]: " yn
if [ -n "$yn" ]; then
case "$(first_character "$yn")" in
y|Y)
nocomp='true'
;;
n|N)
nocomp='false'
;;
*)
echo "Incorrect input, please re-enter!"
continue
;;
esac
fi
break
done

yn=""
cat >&1 <<-EOF
--------------------------
nocomp = ${nocomp}
--------------------------
EOF

[ -z "$quiet" ] && quiet="$D_QUIET"
while true
do
cat >&1 <<-'EOF'
Whether to block open/close log output?
EOF
read -p "(default: ${quiet}) [y/n]: " yn
if [ -n "$yn" ]; then
case "$(first_character "$yn")" in
y|Y)
quiet='true'
;;
n|N)
quiet='false'
;;
*)
echo "Incorrect input, please re-enter!"
continue
;;
esac
fi
break
done

yn=""
cat >&1 <<-EOF
--------------------------
quiet = ${quiet}
--------------------------
EOF

[ -z "$tcp" ] && tcp="$D_TCP"
while true
do
cat >&1 <<-'EOF'
Whether to use TCP transmission
EOF
read -p "(default: ${tcp}) [y/n]: " yn
if [ -n "$yn" ]; then
case "$(first_character "$yn")" in
y|Y)
tcp='true'
;;
n|N)
tcp='false'
;;
*)
echo "Incorrect input, please re-enter!"
continue
;;
esac
fi
break
done

if [ "$tcp" = "true" ]; then
run_user="root"
fi

yn=""
cat >&1 <<-EOF
--------------------------
tcp = ${tcp}
--------------------------
EOF

unset_snmp() {
snmplog=""
snmpperiod=""
cat >&1 <<-EOF
--------------------------
No SNMP logging
--------------------------
EOF
}

cat >&1 <<-EOF
Do you want to record SNMP logs?
EOF
read -p "(default: no) [y/n]: " yn
if [ -n "$yn" ]; then
case "$(first_character "$yn")" in
y|Y)
set_snmp
;;
n|N|*)
unset_snmp
;;
esac
yn=""
else
unset_snmp
fi

[ -z "$pprof" ] && pprof="$D_PPROF"
while true
do
cat >&1 <<-'EOF'
Do you want to enable pprof performance monitoring?
Address: http://IP:6060/debug/pprof/
EOF
read -p "(default: ${pprof}) [y/n]: " yn
if [ -n "$yn" ]; then
case "$(first_character "$yn")" in
y|Y)
pprof='true'
;;
n|N)
pprof='false'
;;
*)
echo "Incorrect input, please re-enter!"
continue
;;
esac
fi
break
done

yn=""
cat >&1 <<-EOF
--------------------------
pprof = ${pprof}
--------------------------
EOF

unset_hidden_parameters() {
acknodelay=""
sockbuf=""
smuxbuf=""
keepalive=""
cat >&1 <<-EOF
--------------------------
Do not configure hidden parameters
--------------------------
EOF
}

cat >&1 <<-'EOF'
The basic parameter settings are completed. Do you want to set additional hidden parameters?
Normally, just keep the default and no additional settings are needed.
EOF
read -p "(default: no) [y/n]: " yn
if [ -n "$yn" ]; then
case "$(first_character "$yn")" in
y|Y)
set_hidden_parameters
;;
n|N|*)
unset_hidden_parameters
;;
esac
else
unset_hidden_parameters
fi

if [ $listen_port -le 1024 ]; then
run_user="root"
fi

echo "Configuration completed."
any_key_to_continue
}

set_snmp() {
snmplog="$(get_current_file 'snmp')"

local input=""
[ -z "$snmpperiod" ] && snmpperiod="$D_SNMPPERIOD"
while true
do
cat >&1 <<-'EOF'
Please set the SNMP recording interval snmpperiod
EOF
read -p "(default: ${snmpperiod}): " input
if [ -n "$input" ]; then
if ! is_number "$input" || [ $input -lt 0 ]; then
echo "Incorrect input, please enter a number greater than or equal to 0!"
continue
fi

snmpperiod=$input
fi
break
done

cat >&1 <<-EOF
--------------------------
snmplog = ${snmplog}
snmpperiod = ${snmpperiod}
--------------------------
EOF
}

set_manual_parameters() {
echo "Start configuring manual parameters..."
local input=""
local yn=""

[ -z "$nodelay" ] && nodelay="$D_NODELAY"
while true
do
cat >&1 <<-'EOF'
Enable nodelay mode?
(0) Not enabled
(1) Enable
EOF
read -p "(Default: ${nodelay}) [0/1]: " input
if [ -n "$input" ]; then
case "$(first_character "$input")" in
1)
nodelay=1
;;
0|*)
nodelay=0
;;
*)
echo "Incorrect input, please re-enter!"
continue
;;
esac
fi
break
done

input=""
cat >&1 <<-EOF
--------------------------
nodelay = ${nodelay}
--------------------------
EOF

[ -z "$interval" ] && interval="$D_INTERVAL"
while true
do
cat >&1 <<-'EOF'
Please set the interval for the inner workings of the protocol
EOF
read -p "(unit: ms, default: ${interval}): " input
if [ -n "$input" ]; then
if ! is_number "$input" || [ $input -le 0 ]; then
echo "Incorrect input, please enter a number greater than 0!"
continue
fi

interval=$input
fi
break
done

input=""
cat >&1 <<-EOF
--------------------------
interval = ${interval}
--------------------------
EOF

[ -z "$resend" ] && resend="$D_RESEND"
while true
do
cat >&1 <<-'EOF'
Enable fast retransmit mode (resend)?
(0) Not enabled
(1) Enable
(2) 2 ACK crosses will be retransmitted directly
EOF
read -p "(Default: ${resend}) Please select [0~2]: " input
if [ -n "$input" ]; then
case "$(first_character "$input")" in
0)
resend=0
;;
1)
resend=1
;;
2)
resend=2
;;
*)
echo "Incorrect input, please re-enter!"
continue
;;
esac
fi
break
done

input=""
cat >&1 <<-EOF
--------------------------
resend = ${resend}
--------------------------
EOF

[ -z "$nc" ] && nc="$D_NC"
while true
do
cat >&1 <<-'EOF'
Do you want to turn off flow control (nc)?
(0) Close
(1) Turn on
EOF
read -p "(Default: ${nc}) [0/1]: " input
if [ -n "$input" ]; then
case "$(first_character "$input")" in
0)
nc=0
;;
1)
nc=1
;;
*)
echo "Incorrect input, please re-enter!"
continue
;;
esac
fi
break
done
cat >&1 <<-EOF
--------------------------
nc = ${nc}
--------------------------
EOF
}

set_hidden_parameters() {
echo "Start setting hidden parameters..."
local input=""
local yn=""

[ -z "$acknodelay" ] && acknodelay="$D_ACKNODELAY"
while true
do
cat >&1 <<-'EOF'
Enable acknodelay mode?
EOF
read -p "(default: ${acknodelay}) [y/n]: " yn
if [ -n "$yn" ]; then
case "$(first_character "$yn")" in
y|Y)
acknodelay="true"
;;
n|N)
acknodelay="false"
;;
*)
echo "Incorrect input, please re-enter!"
continue
;;
esac
fi
break
done

yn=""
cat >&1 <<-EOF
--------------------------
acknodelay = ${acknodelay}
--------------------------
EOF

[ -z "$sockbuf" ] && sockbuf="$D_SOCKBUF"
while true
do
cat >&1 <<-'EOF'
Please set the UDP send and receive buffer size (sockbuf)
EOF
read -p "(Unit: MB, Default: $(expr ${sockbuf} / 1024 / 1024)): " input
if [ -n "$input" ]; then
if ! is_number "$input" || [ $input -le 0 ]; then
echo "Incorrect input, please enter a number greater than 0!"
continue
fi

sockbuf=$(expr $input \* 1024 \* 1024)
fi
break
done

input=""
cat >&1 <<-EOF
--------------------------
sockbuf = ${sockbuf}
--------------------------
EOF

[ -z "$smuxbuf" ] && smuxbuf="$D_SMUXBUF"
while true
do
cat >&1 <<-'EOF'
Please set de-mux buffer size (smuxbuf)
EOF
read -p "(Unit: MB, Default: $(expr ${smuxbuf} / 1024 / 1024)): " input
if [ -n "$input" ]; then
if ! is_number "$input" || [ $input -le 0 ]; then
echo "Incorrect input, please enter a number greater than 0!"
continue
fi

smuxbuf=$(expr $input \* 1024 \* 1024)
fi
break
done

input=""
cat >&1 <<-EOF
--------------------------
smuxbuf = ${smuxbuf}
--------------------------
EOF

[ -z "$keepalive" ] && keepalive="$D_KEEPALIVE"
while true
do
cat >&1 <<-'EOF'
Please set the Keepalive interval
EOF
read -p "(unit: s, default value: ${keepalive}, previous value: 5): " input
if [ -n "$input" ]; then
if ! is_number "$input" || [ $input -le 0 ]; then
echo "Incorrect input, please enter a number greater than 0!"
continue
fi

keepalive=$input
fi
break
done

cat >&1 <<-EOF
--------------------------
keepalive = ${keepalive}
--------------------------
EOF
}

# Generate Kcptun server configuration file
gen_kcptun_config() {
mk_file_dir() {
local dir=""
dir="$(dirname "$1")"
local mod=$2

if [ ! -d "$dir" ]; then
(
set -x
mkdir -p "$dir"
)
fi

if [ -n "$mod" ]; then
chmod $mod "$dir"
fi
}

local config_file=""
config_file="$(get_current_file 'config')"
local supervisor_config_file=""
supervisor_config_file="$(get_current_file 'supervisor')"

mk_file_dir "$config_file"
mk_file_dir "$supervisor_config_file"

if [ -n "$snmplog" ]; then
mk_file_dir "$snmplog" '777'
fi

if ( echo "$listen_addr" | grep -q ":" ); then
listen_addr="[${listen_addr}]"
fi

if ( echo "$target_addr" | grep -q ":" ); then
target_addr="[${target_addr}]"
fi

cat > "$config_file"<<-EOF
{
"listen": "${listen_addr}:${listen_port}",
"target": "${target_addr}:${target_port}",
"key": "${key}",
"crypt": "${crypt}",
"mode": "${mode}",
"mtu": ${mtu},
"sndwnd": ${sndwnd},
"rcvwnd": ${rcvwnd},
"datashard": ${datashard},
"parityshard": ${parityshard},
"dscp": ${dscp},
"nocomp": ${nocomp},
"quiet": ${quiet},
"tcp": ${tcp}
}
EOF

write_configs_to_file() {
install_jq
local k; local v

local json=""
json="$(cat "$config_file")"
for k in "$@"; do
v="$(eval echo "\$$k")"

if [ -n "$v" ]; then
if is_number "$v" || [ "$v" = "false" ] || [ "$v" = "true" ]; then
json="$(echo "$json" | $JQ_BIN ".$k=$v")"
else
json="$(echo "$json" | $JQ_BIN ".$k=\"$v\"")"
fi
fi
done

if [ -n "$json" ] && [ "$json" != "$(cat "$config_file")" ]; then
echo "$json" >"$config_file"
fi
}

write_configs_to_file "snmplog" "snmpperiod" "pprof" "acknodelay" "nodelay" \
"interval" "resend" "nc" "sockbuf" "smuxbuf" "keepalive"

if ! grep -q "^${run_user}:" '/etc/passwd'; then
(
set -x
useradd -U -s '/usr/sbin/nologin' -d '/nonexistent' "$run_user" 2>/dev/null
)
fi

cat > "$supervisor_config_file"<<-EOF
[program:kcptun${current_instance_id}]
user=${run_user}
directory=${KCPTUN_INSTALL_DIR}
command=$(get_kcptun_server_file) -c "${config_file}"
process_name=%(program_name)s
autostart=true
redirect_stderr=true
stdout_logfile=$(get_current_file 'log')
stdout_logfile_maxbytes=1MB
stdout_logfile_backups=0
EOF
}

#Set firewall open ports
set_firewall() {
if command_exists firewall-cmd; then
if ! ( firewall-cmd --state >/dev/null 2>&1 ); then
systemctl start firewalld >/dev/null 2>&1
fi
if [ "$?" = "0" ]; then
if [ -n "$current_listen_port" ]; then
firewall-cmd --zone=public --remove-port=${current_listen_port}/udp >/dev/null 2>&1
fi

if ! firewall-cmd --quiet --zone=public --query-port=${listen_port}/udp; then
firewall-cmd --quiet --permanent --zone=public --add-port=${listen_port}/udp
firewall-cmd --reload
fi
else
cat >&1 <<-EOF
Warning: Automatically adding firewalld rules failed
If necessary, manually add a firewall rule for port ${listen_port}:
firewall-cmd --permanent --zone=public --add-port=${listen_port}/udp
firewall-cmd --reload
EOF
fi
elif command_exists iptables; then
if ! ( service iptables status >/dev/null 2>&1 ); then
service iptables start >/dev/null 2>&1
fi

if [ "$?" = "0" ]; then
if [ -n "$current_listen_port" ]; then
iptables -D INPUT -p udp --dport ${current_listen_port} -j ACCEPT >/dev/null 2>&1
fi

if ! iptables -C INPUT -p udp --dport ${listen_port} -j ACCEPT >/dev/null 2>&1; then
iptables -I INPUT -p udp --dport ${listen_port} -j ACCEPT >/dev/null 2>&1
service iptables save
service iptables restart
fi
else
cat >&1 <<-EOF
Warning: Automatically adding iptables rules failed
If necessary, manually add a firewall rule for port ${listen_port}:
iptables -I INPUT -p udp --dport ${listen_port} -j ACCEPT
service iptables save
service iptables restart
EOF
fi
fi
}

# Select an instance
select_instance() {
if [ "$(get_instance_count)" -gt 1 ]; then
cat >&1 <<-'EOF'
There are currently multiple Kcptun instances (sorted by last modification time):
EOF

local files=""
files=$(ls -lt '/etc/supervisor/conf.d/' | grep "^-" | awk '{print $9}' | grep "^kcptun[0-9]*\.conf$")
local i=0
local array=""
local id=""
for file in $files; do
id="$(echo "$file" | grep -oE "[0-9]+")"
array="${array}${id}#"

i=$(expr $i + 1)
echo "(${i}) ${file%.*}"
done

local sel=""
while true
do
read -p "Please select [1~${i}]: " sel
if [ -n "$sel" ]; then
if ! is_number "$sel" || [ $sel -lt 1 ] || [ $sel -gt $i ]; then
cat >&2 <<-EOF
Please enter a valid number 1~${i}!
EOF
continue
fi
else
cat >&2 <<-EOF
Please enter cannot be empty!
EOF
continue
fi

current_instance_id=$(echo "$array" | cut -d '#' -f ${sel})
break
done
fi
}

# Get the Kcptun server file name through the current server environment
get_kcptun_server_file() {
if [ -z "$file_suffix" ]; then
get_arch
fi

echo "${KCPTUN_INSTALL_DIR}/server_$file_suffix"
}

# Calculate the ID of the new instance
get_new_instance_id() {
if [ -f "/etc/supervisor/conf.d/kcptun.conf" ]; then
local i=2
while [ -f "/etc/supervisor/conf.d/kcptun${i}.conf" ]
do
i=$(expr $i + 1)
done
echo "$i"
fi
}

# Get the installed Kcptun version
get_installed_version() {
local server_file=""
server_file="$(get_kcptun_server_file)"

if [ -f "$server_file" ]; then
if [ ! -x "$server_file" ]; then
chmod a+x "$server_file"
fi

echo "$(${server_file} -v 2>/dev/null | awk '{print $3}')"
fi
}

# Load the configuration file of the currently selected instance
load_instance_config() {
local config_file=""
config_file="$(get_current_file 'config')"

if [ ! -s "$config_file" ]; then
cat >&2 <<-'EOF'
The instance configuration file does not exist or is empty, please check!
EOF
exit 1
fi

local config_content=""
config_content="$(cat ${config_file})"

if [ -z "$(get_json_string "$config_content" '.listen')" ]; then
cat >&2 <<-EOF
There is an error in the instance configuration file, please check!
Configuration file path: ${config_file}
EOF
exit 1
fi

local lines=""
lines="$(get_json_string "$config_content" 'to_entries | map("\(.key)=\(.value | @sh)") | .[]')"

OLDIFS=$IFS
IFS=$(printf '\n')
for line in $lines; do
eval "$line"
done
IFS=$OLDIFS

if [ -n "$listen" ]; then
listen_port="$(echo "$listen" | rev | cut -d ':' -f1 | rev)"
listen_addr="$(echo "$listen" | sed "s/:${listen_port}$//" | grep -oE '[0-9a-fA-F\.:]*')"
listen=""
fi
if [ -n "$target" ]; then
target_port="$(echo "$target" | rev | cut -d ':' -f1 | rev)"
target_addr="$(echo "$target" | sed "s/:${target_port}$//" | grep -oE '[0-9a-fA-F\.:]*')"
target=""
fi

if [ -n "$listen_port" ]; then
current_listen_port="$listen_port"
fi
}

# Display the server Kcptun version and the download address of the client file
show_version_and_client_url() {
local version=""
version="$(get_installed_version)"
if [ -n "$version" ]; then
cat >&1 <<-EOF

The currently installed Kcptun version is: ${version}
EOF
fi

if [ -n "$kcptun_release_html_url" ]; then
cat >&1 <<-EOF
Please go to:
${kcptun_release_html_url}
Download client files manually
EOF
fi
}

# Display information about the currently selected instance
show_current_instance_info() {
local server_ip=""
server_ip="$(get_server_ip)"

printf 'Server IP: \033[41;37m %s \033[0m\n' "$server_ip"
printf 'Port: \033[41;37m %s \033[0m\n' "$listen_port"
printf 'Acceleration address: \033[41;37m %s:%s \033[0m\n' "$target_addr" "$target_port"

show_configs() {
local k; local v
for k in "$@"; do
v="$(eval echo "\$$k")"
if [ -n "$v" ]; then
printf '%s: \033[41;37m %s \033[0m\n' "$k" "$v"
fi
done
}

show_configs "key" "crypt" "mode" "mtu" "sndwnd" "rcvwnd" "datashard" \
"parityshard" "dscp" "nocomp" "quiet" "tcp" "nodelay" "interval" "resend" \
"nc" "acknodelay" "sockbuf" "smuxbuf" "keepalive"

show_version_and_client_url

install_jq
local client_config=""

# What is output here is the configuration information used by the client
# The *remoteaddr* port number of the client is the *listen_port* of the server
# The *localaddr* port number of the client is set to the acceleration port of the server
client_config="$(cat <<-EOF
{
"localaddr": ":${target_port}",
"remoteaddr": "${server_ip}:${listen_port}",
"key": "${key}"
}
EOF
)"

gen_client_configs() {
local k; local v
for k in "$@"; do
if [ "$k" = "sndwnd" ]; then
v="$rcvwnd"
elif [ "$k" = "rcvwnd" ]; then
v="$sndwnd"
else
v="$(eval echo "\$$k")"
fi

if [ -n "$v" ]; then
if is_number "$v" || [ "$v" = "true" ] || [ "$v" = "false" ]; then
client_config="$(echo "$client_config" | $JQ_BIN -r ".${k}=${v}")"
else
client_config="$(echo "$client_config" | $JQ_BIN -r ".${k}=\"${v}\"")"
fi
fi
done
}

gen_client_configs "crypt" "mode" "mtu" "sndwnd" "rcvwnd" "datashard" \
"parityshard" "dscp" "nocomp" "quiet" "tcp" "nodelay" "interval" "resend" \
"nc" "acknodelay" "sockbuf" "smuxbuf" "keepalive"

cat >&1 <<-EOF

The available client profiles are:
${client_config}
EOF

local mobile_config="key=${key}"
gen_mobile_configs() {
local k; local v
for k in "$@"; do
if [ "$k" = "sndwnd" ]; then
v="$rcvwnd"
elif [ "$k" = "rcvwnd" ]; then
v="$sndwnd"
else
v="$(eval echo "\$$k")"
fi

if [ -n "$v" ]; then
if [ "$v" = "false" ]; then
continue
elif [ "$v" = "true" ]; then
mobile_config="${mobile_config};${k}"
else
mobile_config="${mobile_config};${k}=${v}"
fi
fi
done
}

gen_mobile_configs "crypt" "mode" "mtu" "sndwnd" "rcvwnd" "datashard" \
"parityshard" "dscp" "nocomp" "quiet" "tcp" "nodelay" "interval" "resend" \
"nc" "acknodelay" "sockbuf" "smuxbuf" "keepalive"

cat >&1 <<-EOF

Mobile terminal parameters can be used:
${mobile_config}

EOF
}

do_install() {
check_root
disable_selinux
installed_check
set_kcptun_config
install_deps
install_kcptun
install_supervisor
gen_kcptun_config
set_firewall
start_supervisor
enable_supervisor

cat >&1 <<-EOF

Congratulations! The Kcptun server is successfully installed.
EOF

show_current_instance_info

cat >&1 <<-EOF
Kcptun installation directory: ${KCPTUN_INSTALL_DIR}

Supervisor has been added to start automatically at boot.
The Kcptun server will be started when the Supervisor is started.

More instructions: ${0} help

If this script helps you, you can buy the author a Coke:
https://blog.kuoruan.com/donate

Enjoy the thrill of acceleration!
EOF
}

# Uninstall operation
do_uninstall() {
check_root
cat >&1 <<-'EOF'
You chose to uninstall the Kcptun server
EOF
any_key_to_continue
echo "Uninstalling Kcptun server and stopping Supervisor..."

if command_exists supervisorctl; then
supervisorctl shutdown
fi

if command_exists systemctl; then
systemctl stop supervisord.service
elif command_exists serice; then
service supervisord stop
fi

(
set -x
rm -f "/etc/supervisor/conf.d/kcptun*.conf"
rm -rf "$KCPTUN_INSTALL_DIR"
rm -rf "$KCPTUN_LOG_DIR"
)

cat >&1 <<-'EOF'
Do you want to uninstall Supervisor at the same time?
Note: Supervisor configuration files will be deleted at the same time
EOF

read -p "(Default: Do not uninstall) Please select [y/n]: " yn
if [ -n "$yn" ]; then
case "$(first_character "$yn")" in
y|Y)
if command_exists systemctl; then
systemctl disable supervisord.service
rm -f "/lib/systemd/system/supervisord.service" \
"/etc/systemd/system/supervisord.service"
elif command_exists service; then
if [ -z "$lsb_dist" ]; then
get_os_info
fi
case "$lsb_dist" in
ubuntu|debian|raspbian)
(
set -x
update-rc.d -f supervisord remove
)
;;
fedora|centos|redhat|oraclelinux|photon)
(
set -x
chkconfig supervisord off
chkconfig --del supervisord
)
;;
esac
rm -f '/etc/init.d/supervisord'
fi

(
set -x
# Use pip to uninstall the new version
if command_exists pip; then
pip uninstall -y supervisor 2>/dev/null || true
fi

# Use easy_install to uninstall the old version
if command_exists easy_install; then
rm -rf "$(easy_install -mxN supervisor | grep 'Using.*supervisor.*\.egg' | awk '{print $2}')"
fi

rm -rf '/etc/supervisor/'
rm -f '/usr/local/bin/supervisord' \
'/usr/local/bin/supervisorctl' \
'/usr/local/bin/pidproxy' \
'/usr/local/bin/echo_supervisord_conf' \
'/usr/bin/supervisord' \
'/usr/bin/supervisorctl' \
'/usr/bin/pidproxy' \
'/usr/bin/echo_supervisord_conf'
)
;;
n|N|*)
start_supervisor
;;
esac
fi

cat >&1 <<-EOF
Uninstallation completed, welcome to use again.
Note: The script does not automatically uninstall python-pip and python-setuptools (used by older scripts)
If necessary, you can uninstall it yourself.
EOF
}

# renew
do_update() {
pre_ckeck

cat >&1 <<-EOF
You chose to check for updates, starting...
EOF

if get_shell_version_info; then
local shell_path=$0

if [ $new_shell_version -gt $SHELL_VERSION ]; then
cat >&1 <<-EOF
Found a one-click installation script update, version number: ${new_shell_version}
Release Notes:
$(printf '%s\n' "$shell_change_log")
EOF
any_key_to_continue

mv -f "$shell_path" "$shell_path".bak

download_file "$new_shell_url" "$shell_path"
chmod a+x "$shell_path"

sed -i -r "s/^CONFIG_VERSION=[0-9]+/CONFIG_VERSION=${CONFIG_VERSION}/" "$shell_path"
sed -i -r "s/^INIT_VERSION=[0-9]+/INIT_VERSION=${INIT_VERSION}/" "$shell_path"
rm -f "$shell_path".bak

clear
cat >&1 <<-EOF
The installation script has been updated to v${new_shell_version}, running the new script...
EOF

bash "$shell_path" update
exit 0
fi

if [ $new_config_version -gt $CONFIG_VERSION ]; then
cat >&1 <<-EOF
Found Kcptun configuration update, version number: v${new_config_version}
Release Notes:
$(printf '%s\n' "$config_change_log")
Kcptun needs to be reset
EOF
any_key_to_continue

instance_reconfig

sed -i "s/^CONFIG_VERSION=${CONFIG_VERSION}/CONFIG_VERSION=${new_config_version}/" \
"$shell_path"
fi

if [ $new_init_version -gt $INIT_VERSION ]; then
cat >&1 <<-EOF
Found that the service startup script file has been updated, version number: v${new_init_version}
Release Notes:
$(printf '%s\n' "$init_change_log")
EOF

any_key_to_continue

download_startup_file
set -sed -i "s/^INIT_VERSION=${INIT_VERSION}/INIT_VERSION=${new_init_version}/" \
"$shell_path"
fi
fi

echo "Start getting Kcptun version information..."
get_kcptun_version_info

local cur_tag_name=""
cur_tag_name="$(get_installed_version)"

if [ -n "$cur_tag_name" ] && is_number "$cur_tag_name" && [ ${#cur_tag_name} -eq 8 ]; then
cur_tag_name=v"$cur_tag_name"
fi

if [ -n "$kcptun_release_tag_name" ] && [ "$kcptun_release_tag_name" != "$cur_tag_name" ]; then
cat >&1 <<-EOF
Found Kcptun new version ${kcptun_release_tag_name}
$([ "$kcptun_release_prerelease" = "true" ] && printf "\033[41;37m Note: This version is a preview version, please update with caution\033[0m")
Release Notes:
$(printf '%s\n' "$kcptun_release_body")
EOF
any_key_to_continue

install_kcptun
start_supervisor

show_version_and_client_url
else
cat >&1 <<-'EOF'
Kcptun update not found...
EOF
fi
}

# Add instance
instance_add() {
pre_ckeck

cat >&1 <<-'EOF'
You have chosen to add an instance, starting the operation...
EOF
current_instance_id="$(get_new_instance_id)"

set_kcptun_config
gen_kcptun_config
set_firewall
start_supervisor

cat >&1 <<-EOF
Congratulations, instance kcptun${current_instance_id} was added successfully!
EOF
show_current_instance_info
}

# Delete instance
instance_del() {
pre_ckeck

if [ -n "$1" ]; then
if is_number "$1"; then
if [ "$1" != "1" ]; then
current_instance_id="$1"
fi
else
cat >&2 <<-EOF
The parameter is wrong, please use $0 del <id>
<id> is the instance ID, there are currently $(get_instance_count) instances in total
EOF

exit 1
fi
fi

cat >&1 <<-EOF
You chose to delete instance kcptun${current_instance_id}
Note: Instances cannot be restored after being deleted.
EOF
any_key_to_continue

# Get the supervisor configuration file of the instance
supervisor_config_file="$(get_current_file 'supervisor')"
if [ ! -f "$supervisor_config_file" ]; then
echo "The instance you selected kcptun${current_instance_id} does not exist!"
exit 1
fi

current_config_file="$(get_current_file 'config')"
current_log_file="$(get_current_file 'log')"
current_snmp_log_file="$(get_current_file 'snmp')"

(
set -x
rm -f "$supervisor_config_file" \
"$current_config_file" \
"$current_log_file" \
"$current_snmp_log_file"
)

start_supervisor

cat >&1 <<-EOF
Instance kcptun${current_instance_id} deleted successfully!
EOF
}

# Display instance information
instance_show() {
pre_ckeck

if [ -n "$1" ]; then
if is_number "$1"; then
if [ "$1" != "1" ]; then
current_instance_id="$1"
fi
else
cat >&2 <<-EOF
The parameter is wrong, please use $0 show <id>
<id> is the instance ID, there are currently $(get_instance_count) instances in total
EOF

exit 1
fi
fi

echo "You chose to view the configuration of instance kcptun${current_instance_id}, reading..."

load_instance_config

echo "The configuration information of instance kcptun${current_instance_id} is as follows:"
show_current_instance_info
}

# Display instance logs
instance_log() {
pre_ckeck

if [ -n "$1" ]; then
if is_number "$1"; then
if [ "$1" != "1" ]; then
current_instance_id="$1"
fi
else
cat >&2 <<-EOF

The parameter is incorrect, please use $0 log <id>
<id> is the instance ID, there are currently $(get_instance_count) instances in total
EOF

exit 1
fi
fi

echo "You chose to view the log of instance kcptun${current_instance_id}, reading..."

local log_file=""
log_file="$(get_current_file 'log')"

if [ -f "$log_file" ]; then
cat >&1 <<-EOF
The log information of instance kcptun${current_instance_id} is as follows:
Note: The log is refreshed in real time. Press Ctrl+C to exit log viewing.
EOF
tail -n 20 -f "$log_file"
else
cat >&2 <<-EOF
Log file not found for instance kcptun${current_instance_id}...
EOF
exit 1
fi
}

# Reconfigure the instance
instance_reconfig() {
pre_ckeck

if [ -n "$1" ]; then
if is_number "$1"; then
if [ "$1" != "1" ]; then
current_instance_id="$1"
fi
else
cat >&2 <<-EOF
The parameter is incorrect, please use $0 reconfig <id>
<id> is the instance ID, there are currently $(get_instance_count) instances in total
EOF

exit 1
fi
fi

cat >&1 <<-EOF
You chose to reconfigure instance kcptun${current_instance_id}, starting the operation...
EOF

if [ ! -f "$(get_current_file 'supervisor')" ]; then
cat >&2 <<-EOF
The instance kcptun${current_instance_id} you selected does not exist!
EOF
exit 1
fi

local sel=""
cat >&1 <<-'EOF'
Please select an action:
(1) Reconfigure all options of the instance
(2) Directly modify the instance configuration file
EOF
read -p "(Default: 1) Please select: " sel
echo
[ -z "$sel" ] && sel="1"

case "$(first_character "$sel")" in
2)
echo "Opening configuration file, please modify it manually..."
local config_file=""
config_file="$(get_current_file 'config')"
edit_config_file() {
if [ ! -f "$config_file" ]; then
return 1
fi

if command_exists vim; then
vim "$config_file"
elif command_exists vi; then
vi "$config_file"
elif command_exists gedit; then
gedit "$config_file"
else
echo "No available editor found, entering new configuration..."
return 1
fi

load_instance_config
}

if ! edit_config_file; then
set_kcptun_config
fi
;;
1|*)
load_instance_config
set_kcptun_config
;;
esac

gen_kcptun_config
set_firewall

if command_exists supervisorctl; then
supervisorctl restart "kcptun${current_instance_id}"

if [ "$?" != "0" ]; then
cat >&2 <<-'EOF'
Failed to restart Supervisor, Kcptun cannot work properly!
Please check the log for the reason, or give feedback to the script author.
EOF
exit 1
fi
else
start_supervisor
fi

cat >&1 <<-EOF

Congratulations, the Kcptun server configuration has been updated!
EOF
show_current_instance_info
}

#Manual installation
manual_install() {
pre_ckeck

cat >&1 <<-'EOF'
You have chosen a customized version installation, starting the operation...
EOF

local tag_name="$1"

while true
do
if [ -z "$tag_name" ]; then
cat >&1 <<-'EOF'
Please enter the complete TAG of the Kcptun version you want to install
EOF
read -p "(for example: v20160904): " tag_name
if [ -z "$tag_name" ]; then
echo "Invalid input, please re-enter!"
continue
fi
fi

if [ "$tag_name" = "SNMP_Milestone" ]; then
echo "This version is not supported, please re-enter!"
tag_name=""
continue
fi

local version_num=""
version_num=$(echo "$tag_name" | grep -oE "[0-9]+" || "0")
if [ ${#version_num} -eq 8 ] && [ $version_num -le 20160826 ]; then
echo "Installation of v20160826 and previous versions is not supported"
tag_name=""
continue
fi

echo "Getting information, please wait..."
get_kcptun_version_info "$tag_name"
if [ "$?" != "0" ]; then
cat >&2 <<-EOF
The corresponding version download address (TAG: ${tag_name}) was not found, please re-enter!
You can go to:
${KCPTUN_TAGS_URL}
View all available TAGs
EOF
tag_name=""
continue
else
cat >&1 <<-EOF
Kcptun version information found, TAG: ${tag_name}
EOF
any_key_to_continue

install_kcptun "$tag_name"
start_supervisor
show_version_and_client_url
break
fi
done
}

pre_ckeck() {
check_root

if ! is_installed; then
cat >&2 <<-EOF
Error: Detected that you have not installed Kcptun,
Or the Kcptun program file is damaged,
Please run the script to reinstall the Kcptun server.
EOF

exit 1
fi
}

# Monitor whether kcptun is installed
is_installed() {
if [ -d '/usr/share/kcptun' ]; then
cat >&1 <<-EOF
The test found that you have upgraded from the old version to the new version.
In the new version, the default installation directory is set to ${KCPTUN_INSTALL_DIR}
The script will automatically copy files from the old directory /usr/share/kcptun
Move to the new version directory ${KCPTUN_INSTALL_DIR}
EOF
any_key_to_continue
(
set -x
cp -rf '/usr/share/kcptun' "$KCPTUN_INSTALL_DIR" && \
rm -rf '/usr/share/kcptun'
)
fi

if [ -d '/etc/supervisor/conf.d/' ] && [ -d "$KCPTUN_INSTALL_DIR" ] && \
[ -n "$(get_installed_version)" ]; then
return 0
fi

return 1
}

# Check if it is installed
installed_check() {
local instance_count=""
instance_count="$(get_instance_count)"
if is_installed && [ $instance_count -gt 0 ]; then
cat >&1 <<-EOF
It is detected that you have installed the Kcptun server, and the number of configured instances is ${instance_count}
EOF
while true
do
cat >&1 <<-'EOF'
Please select the action you wish to take:
(1) Cover installation
(2) Reconfiguration
(3) Add instance (multi-port)
(4) Check for updates
(5) View configuration
(6) View log output
(7) Customized version installation
(8) Delete instance
(9) Complete uninstall
(10) Exit script
EOF
read -p "(Default: 1) Please select [1~10]: " sel
[ -z "$sel" ] && sel=1

case $sel in
1)
echo "Start overwriting and installing Kcptun server..."
load_instance_config
return 0
;;
2)
select_instance
instance_reconfig
;;
3)
instance_add
;;
4)
do_update
;;
5)
select_instance
instance_show
;;
6)
select_instance
instance_log
;;
7)
manual_install
;;
8)
select_instance
instance_del
;;
9)
do_uninstall
;;
10)
;;
*)
echo "Incorrect input, please enter valid numbers 1~10!"
continue
;;
esac

exit 0
done
fi
}

action=${1:-"install"}
case "$action" in
install|uninstall|update)
do_${action}
;;
add|reconfig|show|log|del)
instance_${action} "$2"
;;
manual)
manual_install "$2"
;;
help)
usage 0
;;
*)
usage 1
;;
esac
