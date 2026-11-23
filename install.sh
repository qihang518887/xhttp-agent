#!/bin/sh

if [ -z "${BASH_VERSION:-}" ]; then
    if ! command -v bash >/dev/null 2>&1; then
        if [ -f /etc/alpine-release ]; then
            apk add --no-cache bash || exit 1
        else
            echo "bash is required to run this script" >&2
            exit 1
        fi
    fi
    exec bash "$0" "$@"
fi

# 检测区
# -------------------------------------------------------------
# 检查系统
export LANG=en_US.UTF-8

echoContent() {
    case $1 in
    # 红色
    "red")
        # shellcheck disable=SC2154
        ${echoType} "\033[31m${printN}$2 \033[0m"
        ;;
        # 天蓝色
    "skyBlue")
        ${echoType} "\033[1;36m${printN}$2 \033[0m"
        ;;
        # 绿色
    "green")
        ${echoType} "\033[32m${printN}$2 \033[0m"
        ;;
        # 白色
    "brightPurple")
        ${echoType} "\033[95m${printN}$2 \033[0m"
        ;;
    "brightGreen")
        ${echoType} "\033[92m${printN}$2 \033[0m"
        ;;
    "gold")
        ${echoType} "\033[93m${printN}$2 \033[0m"
        ;;
    "blue")
        ${echoType} "\033[94m${printN}$2 \033[0m"
        ;;
    "gray")
        ${echoType} "\033[90m${printN}$2 \033[0m"
        ;;
    "white")
        ${echoType} "\033[37m${printN}$2 \033[0m"
        ;;
    "magenta")
        ${echoType} "\033[31m${printN}$2 \033[0m"
        ;;
        # 黄色
    "yellow")
        ${echoType} "\033[33m${printN}$2 \033[0m"
        ;;
    esac
}
# 检查SELinux状态
checkCentosSELinux() {
    if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce)" == "Enforcing" ]; then
        echoContent yellow "# 注意事项"
        echoContent yellow "检测到SELinux已开启，请手动关闭，教程如下"
        echoContent yellow "https://www.v2ray-agent.com/archives/1684115970026#centos-%E5%85%B3%E9%97%ADselinux"
        exit 0
    fi
}
checkSystem() {
    if [[ -n $(find /etc -name "redhat-release") ]] || grep </proc/version -q -i "centos"; then
        mkdir -p /etc/yum.repos.d

        if [[ -f "/etc/centos-release" ]]; then
            centosVersion=$(rpm -q centos-release | awk -F "[-]" '{print $3}' | awk -F "[.]" '{print $1}')

            if [[ -z "${centosVersion}" ]] && grep </etc/centos-release -q -i "release 8"; then
                centosVersion=8
            fi
        fi

        release="centos"
        installType='yum -y install'
        #        upgrade="yum update -y --skip-broken"
        checkCentosSELinux
    elif { [[ -f "/etc/issue" ]] && grep -qi "Alpine" /etc/issue; } || { [[ -f "/proc/version" ]] && grep -qi "Alpine" /proc/version; }; then
        release="alpine"
        installType='apk add'
        upgrade="apk update"
    elif { [[ -f "/etc/issue" ]] && grep -qi "debian" /etc/issue; } || { [[ -f "/proc/version" ]] && grep -qi "debian" /proc/version; } || { [[ -f "/etc/os-release" ]] && grep -qE '^ID="?debian"?$' /etc/os-release; }; then
        release="debian"
        installType='apt -y install'
        upgrade="apt update"
        updateReleaseInfoChange='apt-get --allow-releaseinfo-change update'

    elif { [[ -f "/etc/issue" ]] && grep -qi "ubuntu" /etc/issue; } || { [[ -f "/proc/version" ]] && grep -qi "ubuntu" /proc/version; }; then
        release="ubuntu"
        installType='apt -y install'
        upgrade="apt update"
        updateReleaseInfoChange='apt-get --allow-releaseinfo-change update'
        if grep </etc/issue -q -i "16."; then
            release=
        fi
    fi

    if [[ -z ${release} ]]; then
        echoContent red "\n本脚本不支持此系统，请将下方日志反馈给开发者\n"
        echoContent yellow "$(cat /etc/issue)"
        echoContent yellow "$(cat /proc/version)"
        exit 0
    fi
}

# 检查CPU提供商
checkCPUVendor() {
    if [[ -n $(which uname) ]]; then
        if [[ "$(uname)" == "Linux" ]]; then
            case "$(uname -m)" in
            'amd64' | 'x86_64')
                xrayCoreCPUVendor="Xray-linux-64"
                ;;
            'armv8' | 'aarch64')
                xrayCoreCPUVendor="Xray-linux-arm64-v8a"
                ;;
            *)
                echo "  不支持此CPU架构--->"
                exit 1
                ;;
            esac
        fi
    else
        echoContent red "  无法识别此CPU架构，默认amd64、x86_64--->"
        xrayCoreCPUVendor="Xray-linux-64"
    fi
}

# 初始化全局变量
initVar() {
    installType='yum -y install'
    upgrade="yum -y update"
    echoType='echo -e'
    xrayCoreCPUVendor=""
    domain=
    totalProgress=1
    coreInstallType=
    ctlPath=
    currentInstallProtocolType=
    selectCustomInstallType=
    configPath=
    xrayVLESSXHTTPTLSPort=
    xHTTPTLSPort=
    currentPath=
    currentHost=
    customPath=
    centosVersion=
    currentUUID=
    currentClients=
    cronName=$1
    installTLSCount=
    prereleaseStatus=false
    sslType=
    cfAPIToken=
    sslEmail=
    sslRenewalThresholdDays=7
    dnsTLSDomain=
    wgetShowProgressStatus=
    lastInstallationConfig=
    xhttpDirectAddress=
    xhttpH3Up=50
}

# Map menu selections to the XHTTP inbound configs.
normalizeXrayInstallSelection() {
    local input=${1:-}
    input=${input// /}
    local token
    local normalized=
    IFS=',' read -ra selection <<<"${input}"
    for token in "${selection[@]}"; do
        [[ -z "${token}" ]] && continue
        case "${token}" in
        1 | 2) normalized+="${token}," ;;
        esac
    done
    printf ',%s\n' "${normalized}"
}

isNumber() {
    [[ "${1:-}" =~ ^[0-9]+$ ]]
}

buildXrayXHTTPTLSConfig() {
    local port=$1 domainName=$2 customPath=$3 clientsJson=$4
    jq -n --arg domain "${domainName}" --arg path "/${customPath#\/}xHTTP" \
        --argjson clients "${clientsJson}" --argjson publicPort "${port}" '
      {inbounds:[
        {listen:"0.0.0.0",port:$publicPort,protocol:"vless",tag:"VLESSXHTTPTLS",
         settings:{clients:$clients,decryption:"none"},
         streamSettings:{network:"xhttp",security:"tls",
           tlsSettings:{serverName:$domain,minVersion:"1.2",rejectUnknownSni:true,
             certificates:[{certificateFile:("/etc/v2ray-agent/tls/"+$domain+".crt"),keyFile:("/etc/v2ray-agent/tls/"+$domain+".key")}]},
           xhttpSettings:{host:$domain,path:$path,mode:"auto"}}}
      ]}'
}

buildXrayXHTTPH3Config() {
    local port=$1 domainName=$2 customPath=$3 clientsJson=$4 brutalUp=$5
    # h3单连接默认只允许100条流，跑满后所有会话上传都会卡住
    jq -n --arg domain "${domainName}" --arg path "/${customPath#\/}xHTTP" --arg brutalUp "${brutalUp}" \
        --argjson clients "${clientsJson}" --argjson publicPort "${port}" '
      {inbounds:[
        {listen:"0.0.0.0",port:$publicPort,protocol:"vless",tag:"VLESSXHTTPH3",
         settings:{clients:$clients,decryption:"none"},
         streamSettings:{network:"xhttp",security:"tls",
           tlsSettings:{serverName:$domain,minVersion:"1.2",rejectUnknownSni:true,alpn:["h3"],
             certificates:[{certificateFile:("/etc/v2ray-agent/tls/"+$domain+".crt"),keyFile:("/etc/v2ray-agent/tls/"+$domain+".key")}]},
           xhttpSettings:{host:$domain,path:$path,mode:"auto"},
           finalmask:{quicParams:({maxIncomingStreams:4096} + (if $brutalUp == "0" then {} else {congestion:"force-brutal",brutalUp:($brutalUp + " mbps")} end))}}}
      ]}'
}

buildVLESSXHTTPTLSURI() {
    local address=$1 port=$2 uuidValue=$3 domainName=$4 pathValue=$5 modeValue=$6 name=$7 alpn=${8:-h2}
    pathValue="/${pathValue#\/}"
    printf 'vless://%s@%s:%s?encryption=none&security=tls&type=xhttp&sni=%s&host=%s&fp=chrome&alpn=%s&path=%%2F%s&mode=%s#%s\n' \
        "${uuidValue}" "${address}" "${port}" "${domainName}" "${domainName}" "${alpn}" "${pathValue#/}" "${modeValue}" "${name}"
}

buildMihomoXHTTPTLSNode() {
    local address=$1 port=$2 uuidValue=$3 domainName=$4 pathValue=$5 modeValue=$6 name=$7 alpn=${8:-h2}
    pathValue="/${pathValue#\/}"
    cat <<EOF
  - name: "${name}"
    type: vless
    server: ${address}
    port: ${port}
    uuid: ${uuidValue}
    udp: true
    tls: true
    network: xhttp
    packet-encoding: xudp
    client-fingerprint: chrome
    alpn: [${alpn}]
    servername: ${domainName}
    xhttp-opts:
      path: ${pathValue}
      host: ${domainName}
      mode: ${modeValue}
EOF
}

# Restore every file if a multi-protocol user deletion fails.
restoreXrayUserConfigs() {
    local backupDir=$1 file index=0 status=0
    shift
    for file in "$@"; do
        cp -p "${backupDir}/${index}.backup" "${file}" || status=1
        index=$((index + 1))
    done
    return "${status}"
}

# Stage all changes before writing files and reloading the cores.
deleteXrayUserByUUID() {
    local uuidValue=$1 backupDir file tmpFile index=0 failed=false
    local -a files=()
    [[ -n "${uuidValue}" && -n "${configPath}" ]] || return 1
    backupDir=$(mktemp -d "${TMPDIR:-/tmp}/v2ray-agent-delete.XXXXXX") || return 1
    for file in "${configPath}"*_inbounds.json; do
        [[ -f "${file}" ]] && files+=("${file}")
    done
    for file in "${files[@]}"; do
        if ! cp -p "${file}" "${backupDir}/${index}.backup" ||
            ! jq -e --arg uuid "${uuidValue}" '
              .inbounds |= map(
                if (.settings.clients? | type) == "array" then
                  .settings.clients |= map(select((.id? != $uuid) and (.password? != $uuid)))
                else . end)' "${file}" >"${backupDir}/${index}.json"; then
            rm -rf "${backupDir}"
            return 1
        fi
        index=$((index + 1))
    done
    index=0
    for file in "${files[@]}"; do
        if ! cmp -s "${backupDir}/${index}.backup" "${backupDir}/${index}.json"; then
            tmpFile=$(mktemp "${file}.delete.XXXXXX") || {
                failed=true
                break
            }
            if ! cp -p "${file}" "${tmpFile}" ||
                ! cat "${backupDir}/${index}.json" >"${tmpFile}" ||
                ! mv -f "${tmpFile}" "${file}"; then
                rm -f "${tmpFile}"
                failed=true
                break
            fi
        fi
        index=$((index + 1))
    done
    if [[ "${failed}" == false ]] && ! "${ctlPath}" run -test -confdir "${configPath}"; then
        failed=true
    fi
    if [[ "${failed}" == true ]]; then
        if restoreXrayUserConfigs "${backupDir}" "${files[@]}"; then
            rm -rf "${backupDir}"
        else
            echoContent red " ---> 恢复配置失败，备份保留在： ${backupDir}"
        fi
        return 1
    fi
    if ! reloadCore transaction; then
        if restoreXrayUserConfigs "${backupDir}" "${files[@]}" && reloadCore transaction; then
            rm -rf "${backupDir}"
        else
            echoContent red " ---> 恢复服务失败，备份保留在： ${backupDir}"
        fi
        return 1
    fi
    rm -rf "${backupDir}"
}

getXrayAccountReferenceConfig() {
    local candidate="${configPath}02_VLESS_XHTTP_TLS_inbounds.json"
    if [[ ! -f "${candidate}" ]]; then
        candidate="${configPath}01_VLESS_XHTTP_H3_inbounds.json"
    fi
    if [[ -f "${candidate}" ]] && jq -e '.inbounds[0].settings.clients | type == "array"' "${candidate}" >/dev/null 2>&1; then
        printf '%s\n' "${candidate}"
        return 0
    fi
    return 1
}

# 读取tls证书详情
readAcmeTLS() {
    local readAcmeDomain=
    installedDNSAPIStatus=
    if [[ -n "${currentHost}" ]]; then
        readAcmeDomain="${currentHost}"
    fi

    if [[ -n "${domain}" ]]; then
        readAcmeDomain="${domain}"
    fi

    dnsTLSDomain=$(echo "${readAcmeDomain}" | awk -F "." '{$1="";print $0}' | sed 's/^[[:space:]]*//' | sed 's/ /./g')
    if [[ -s "$HOME/.acme.sh/${readAcmeDomain}_ecc/${readAcmeDomain}.key" && -s "$HOME/.acme.sh/${readAcmeDomain}_ecc/${readAcmeDomain}.cer" ]]; then
        return 0
    fi
    if compgen -G "$HOME/.acme.sh/*${dnsTLSDomain}_ecc/*${dnsTLSDomain}.key" >/dev/null 2>&1 && compgen -G "$HOME/.acme.sh/*${dnsTLSDomain}_ecc/*${dnsTLSDomain}.cer" >/dev/null 2>&1; then
        installedDNSAPIStatus=true
    fi
}

# 检测安装方式
readInstallType() {
    coreInstallType=
    configPath=

    # 1.检测安装目录
    if [[ -d "/etc/v2ray-agent" ]]; then
        if [[ -f "/etc/v2ray-agent/xray/xray" ]]; then
            if [[ -d "/etc/v2ray-agent/xray/conf" && ( -f "/etc/v2ray-agent/xray/conf/02_VLESS_XHTTP_TLS_inbounds.json" || -f "/etc/v2ray-agent/xray/conf/01_VLESS_XHTTP_H3_inbounds.json" ) ]]; then
                # xray-core
                configPath=/etc/v2ray-agent/xray/conf/
                ctlPath=/etc/v2ray-agent/xray/xray
                coreInstallType=1
            fi
        fi
    fi
}

# 读取协议类型
readInstallProtocolType() {
    currentInstallProtocolType=
    xrayVLESSXHTTPTLSPort=

    [[ -n "${configPath}" && -d "${configPath}" ]] || return 0

    local tlsConfig="${configPath}02_VLESS_XHTTP_TLS_inbounds.json"
    if [[ -f "${tlsConfig}" ]]; then
        currentInstallProtocolType+=",2,"
        xrayVLESSXHTTPTLSPort=$(jq -r '.inbounds[0].port' "${tlsConfig}")
    fi
    local h3Config="${configPath}01_VLESS_XHTTP_H3_inbounds.json"
    if [[ -f "${h3Config}" ]]; then
        currentInstallProtocolType+=",1,"
        [[ -n "${xrayVLESSXHTTPTLSPort}" ]] || xrayVLESSXHTTPTLSPort=$(jq -r '.inbounds[0].port' "${h3Config}")
    fi
}

# 检查防火墙
allowPort() {
    local type=$2
    if [[ -z "${type}" ]]; then
        type=tcp
    fi
    # 如果防火墙启动状态则添加相应的开放端口
    if command -v dpkg >/dev/null 2>&1 && dpkg -l | grep -q "^[[:space:]]*ii[[:space:]]\+ufw"; then
        if ufw status | grep -q "Status: active"; then
            if ! ufw status | grep -q "$1/${type}"; then
                sudo ufw allow "$1/${type}"
                checkUFWAllowPort "$1"
            fi
        fi
    elif systemctl status firewalld 2>/dev/null | grep -q "active (running)"; then
        local updateFirewalldStatus=
        if ! firewall-cmd --list-ports --permanent | grep -qw "$1/${type}"; then
            updateFirewalldStatus=true
            local firewallPort=$1
            if echo "${firewallPort}" | grep -q ":"; then
                firewallPort=$(echo "${firewallPort}" | awk -F ":" '{print $1"-"$2}')
            fi
            firewall-cmd --zone=public --add-port="${firewallPort}/${type}" --permanent
            checkFirewalldAllowPort "${firewallPort}"
        fi

        if echo "${updateFirewalldStatus}" | grep -q "true"; then
            firewall-cmd --reload
        fi
    elif rc-update show 2>/dev/null | grep -q ufw; then
        if ufw status | grep -q "Status: active"; then
            if ! ufw status | grep -q "$1/${type}"; then
                sudo ufw allow "$1/${type}"
                checkUFWAllowPort "$1"
            fi
        fi
    elif command -v dpkg >/dev/null 2>&1 && dpkg -l | grep -q "^[[:space:]]*ii[[:space:]]\+netfilter-persistent" && systemctl status netfilter-persistent 2>/dev/null | grep -q "active (exited)"; then
        local updateFirewalldStatus=
        if ! iptables -L | grep -q "$1/${type}(mack-a)"; then
            updateFirewalldStatus=true
            iptables -I INPUT -p "${type}" --dport "$1" -m comment --comment "allow $1/${type}(mack-a)" -j ACCEPT
        fi

        if echo "${updateFirewalldStatus}" | grep -q "true"; then
            netfilter-persistent save
        fi
    fi
}
# 获取公网IP
getPublicIP() {
    local type=4
    if [[ -n "$1" ]]; then
        type=$1
    fi
    local currentIP=
    currentIP=$(curl -s "-${type}" http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
    if [[ -z "${currentIP}" && -z "$1" ]]; then
        currentIP=$(curl -s "-6" http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
    fi
    echo "${currentIP}"
}

# 输出ufw端口开放状态
checkUFWAllowPort() {
    if ufw status | grep -q "$1"; then
        echoContent green " ---> $1端口开放成功"
    else
        echoContent red " ---> $1端口开放失败"
        exit 0
    fi
}

# 输出firewall-cmd端口开放状态
checkFirewalldAllowPort() {
    if firewall-cmd --list-ports --permanent | grep -q "$1"; then
        echoContent green " ---> $1端口开放成功"
    else
        echoContent red " ---> $1端口开放失败"
        exit 0
    fi
}

# 读取上次安装的配置
readLastInstallationConfig() {
    if [[ -n "${configPath}" ]]; then
        read -r -p "读取到上次安装的配置，是否使用 ？[y/n]:" lastInstallationConfigStatus
        if [[ "${lastInstallationConfigStatus}" == "y" ]]; then
            lastInstallationConfig=true
        fi
    fi
}
# 检查文件目录以及path路径
readConfigHostPathUUID() {
    currentPath=
    currentUUID=
    currentClients=
    currentHost=

    local xhttpTLSConfig="${configPath}02_VLESS_XHTTP_TLS_inbounds.json"
    [[ -f "${xhttpTLSConfig}" ]] || xhttpTLSConfig="${configPath}01_VLESS_XHTTP_H3_inbounds.json"
    if [[ -f "${xhttpTLSConfig}" ]]; then
        currentClients=$(jq -c '.inbounds[0].settings.clients' "${xhttpTLSConfig}")
        currentUUID=$(jq -r '.inbounds[0].settings.clients[0].id // empty' "${xhttpTLSConfig}")
        currentHost=$(jq -r '.inbounds[0].streamSettings.tlsSettings.serverName // .inbounds[0].streamSettings.xhttpSettings.host // empty' "${xhttpTLSConfig}")
        xrayVLESSXHTTPTLSPort=$(jq -r '.inbounds[0].port' "${xhttpTLSConfig}")
        currentPath=$(jq -r '.inbounds[0].streamSettings.xhttpSettings.path' "${xhttpTLSConfig}" | sed -E 's#^/##; s#xHTTP$##')
    fi
}

# 状态展示
showInstallStatus() {
    if [[ -n "${coreInstallType}" ]]; then
            if [[ -n $(pgrep -f "xray/xray") ]]; then
                echoContent yellow "\n核心: Xray-core[运行中]"
            else
                echoContent yellow "\n核心: Xray-core[未运行]"
            fi

        # 读取协议类型
        readInstallProtocolType

        if [[ -n ${currentInstallProtocolType} ]]; then
            echoContent yellow "已安装协议: \c"
        fi
        if echo ${currentInstallProtocolType} | grep -q ",2,"; then
            echoContent yellow "VLESS+XHTTP+TLS \c"
        fi
        if echo ${currentInstallProtocolType} | grep -q ",1,"; then
            echoContent yellow "VLESS+XHTTP+H3 \c"
        fi
    fi
}

# Remove a core service without assuming that it matches coreInstallType.
removeCoreService() {
    local core=$1 unit="${1}.service" initScript="/etc/init.d/${1}" loadState

    if [[ "${release}" == "alpine" ]]; then
        if [[ -f "${initScript}" ]]; then
            # Inactive services are already stopped; do not hide a real stop failure.
            if rc-service "${core}" status >/dev/null 2>&1; then
                rc-service "${core}" stop || return 1
            fi
        fi
        if [[ -e "/etc/runlevels/default/${core}" || -L "/etc/runlevels/default/${core}" ]]; then
            rc-update del "${core}" default || return 1
        fi
        rm -f "${initScript}" || return 1
    else
        if command -v systemctl >/dev/null 2>&1; then
            loadState=$(systemctl show -p LoadState --value "${unit}") || return 1
            if [[ -e "/etc/systemd/system/${unit}" || -L "/etc/systemd/system/${unit}" ||
                (-n "${loadState}" && "${loadState}" != not-found) ]]; then
                systemctl stop "${unit}" || return 1
                systemctl disable "${unit}" || return 1
                if systemctl is-active --quiet "${unit}"; then
                    echoContent red " ---> ${unit}: service is still active"
                    return 1
                fi
                # Package-owned units under /lib or /usr/lib are only disabled.
                rm -f "/etc/systemd/system/${unit}" || return 1
                systemctl daemon-reload || return 1
            fi
        elif [[ -e "/etc/systemd/system/${unit}" || -L "/etc/systemd/system/${unit}" ]]; then
            echoContent red " ---> ${unit}: systemctl is unavailable"
            return 1
        fi
    fi
    # A missing unit must not let cleanup delete files used by an orphan process.
    if pgrep -f "^/etc/v2ray-agent/${core}/${core}([[:space:]]|$)" >/dev/null 2>&1; then
        echoContent red " ---> ${core}: managed process is still running; cleanup stopped"
        return 1
    fi
    return 0
}

initVar "$1"
checkSystem
checkCPUVendor

readInstallType
readInstallProtocolType
readConfigHostPathUUID

# -------------------------------------------------------------

# 初始化安装目录
mkdirTools() {
    mkdir -p /etc/v2ray-agent/tls
    mkdir -p /etc/v2ray-agent/subscribe_local/default
    mkdir -p /etc/v2ray-agent/subscribe_local/clashMeta

    mkdir -p /etc/v2ray-agent/subscribe_remote/default
    mkdir -p /etc/v2ray-agent/subscribe_remote/clashMeta

    mkdir -p /etc/v2ray-agent/subscribe/default
    mkdir -p /etc/v2ray-agent/subscribe/clashMeta

    mkdir -p /etc/v2ray-agent/xray/conf
    mkdir -p /etc/systemd/system/
}
# 安装工具包
installTools() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : 安装工具"
    # installTools 可能在 menu() 创建其余目录之前运行。
    mkdir -p /etc/v2ray-agent
    touch /etc/v2ray-agent/install.log
    # 修复ubuntu个别系统问题
    if [[ "${release}" == "ubuntu" ]]; then
        dpkg --configure -a
    fi

    echoContent green " ---> 检查、安装更新【新机器会很慢，如长时间无反应，请手动停止后重新执行】"

    if [[ "${release}" != "centos" ]]; then
        ${upgrade} >/etc/v2ray-agent/install.log 2>&1
    fi

    if grep <"/etc/v2ray-agent/install.log" -q "changed"; then
        ${updateReleaseInfoChange} >/dev/null 2>&1
    fi

    if [[ "${release}" == "centos" ]]; then
        rm -rf /var/run/yum.pid
        ${installType} epel-release >/dev/null 2>&1
    fi

    if ! sudo --version >/dev/null 2>&1; then
        echoContent green " ---> 安装sudo"
        ${installType} sudo >/dev/null 2>&1
    fi

    if ! wget --help >/dev/null 2>&1; then
        echoContent green " ---> 安装wget"
        ${installType} wget >/dev/null 2>&1
    fi

    if ! curl --help >/dev/null 2>&1; then
        echoContent green " ---> 安装curl"
        ${installType} curl >/dev/null 2>&1
    fi

    if ! unzip >/dev/null 2>&1; then
        echoContent green " ---> 安装unzip"
        ${installType} unzip >/dev/null 2>&1
    fi

    if ! socat -h >/dev/null 2>&1; then
        echoContent green " ---> 安装socat"
        ${installType} socat >/dev/null 2>&1
    fi

    if ! tar --help >/dev/null 2>&1; then
        echoContent green " ---> 安装tar"
        ${installType} tar >/dev/null 2>&1
    fi

    if ! crontab -l >/dev/null 2>&1; then
        echoContent green " ---> 安装crontabs"
        if [[ "${release}" == "ubuntu" || "${release}" == "debian" ]]; then
            ${installType} cron >/dev/null 2>&1
        else
            ${installType} crontabs >/dev/null 2>&1
        fi
    fi
    if ! jq --help >/dev/null 2>&1; then
        echoContent green " ---> 安装jq"
        ${installType} jq >/dev/null 2>&1
    fi

    if ! command -v ld >/dev/null 2>&1; then
        echoContent green " ---> 安装binutils"
        ${installType} binutils >/dev/null 2>&1
    fi

    if ! openssl help >/dev/null 2>&1; then
        echoContent green " ---> 安装openssl"
        ${installType} openssl >/dev/null 2>&1
    fi

    if ! command -v lsb_release >/dev/null 2>&1; then
        if [[ "${release}" == "ubuntu" || "${release}" == "debian" ]]; then
            ${installType} lsb-release >/dev/null 2>&1
        elif [[ "${release}" == "centos" ]]; then
            ${installType} redhat-lsb-core >/dev/null 2>&1
        else
            ${installType} lsb-release >/dev/null 2>&1
        fi
    fi

    if ! lsof -h >/dev/null 2>&1; then
        echoContent green " ---> 安装lsof"
        ${installType} lsof >/dev/null 2>&1
    fi

    if [[ ! -d "$HOME/.acme.sh" ]] || [[ -d "$HOME/.acme.sh" && -z $(find "$HOME/.acme.sh/acme.sh") ]]; then
        echoContent green " ---> 安装acme.sh"
        curl -s https://get.acme.sh | sh >/etc/v2ray-agent/tls/acme.log 2>&1

        if [[ ! -d "$HOME/.acme.sh" ]] || [[ -z $(find "$HOME/.acme.sh/acme.sh") ]]; then
                echoContent red "  acme安装失败--->"
                tail -n 100 /etc/v2ray-agent/tls/acme.log
                echoContent yellow "错误排查:"
                echoContent red "  1.获取Github文件失败，请等待Github恢复后尝试，恢复进度可查看 [https://www.githubstatus.com/]"
                echoContent red "  2.acme.sh脚本出现bug，可查看[https://github.com/acmesh-official/acme.sh] issues"
                echoContent red "  3.如纯IPv6机器，请设置NAT64,可执行下方命令，如果添加下方命令还是不可用，请尝试更换其他NAT64"
                echoContent skyBlue "  sed -i \"1i\\\nameserver 2a00:1098:2b::1\\\nnameserver 2a00:1098:2c::1\\\nnameserver 2a01:4f8:c2c:123f::1\\\nnameserver 2a01:4f9:c010:3f02::1\" /etc/resolv.conf"
                exit 0
            fi
        fi

}
# 开机启动
bootStartup() {
    local serviceName=$1
    if [[ "${release}" == "alpine" ]]; then
        rc-update add "${serviceName}" default
    else
        systemctl daemon-reload
        systemctl enable "${serviceName}"
    fi
}
# 初始化TLS证书域名
initTLSDomain() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : 配置 TLS 证书域名"
    if [[ -n "${currentHost}" && -z "${lastInstallationConfig}" ]]; then
        echo
        read -r -p "读取到上次安装记录，是否使用上次安装时的域名 ？[y/n]:" historyDomainStatus
        if [[ "${historyDomainStatus}" == "y" ]]; then
            domain=${currentHost}
            echoContent yellow "\n ---> 域名: ${domain}"
        else
            echo
            echoContent yellow "请输入要配置的域名 例: www.v2ray-agent.com --->"
            read -r -p "域名:" domain
        fi
    elif [[ -n "${currentHost}" && -n "${lastInstallationConfig}" ]]; then
        domain=${currentHost}
    else
        echo
        echoContent yellow "请输入要配置的域名 例: www.v2ray-agent.com --->"
        read -r -p "域名:" domain
    fi

    if [[ -z ${domain} ]]; then
        echoContent red "  域名不可为空--->"
        initTLSDomain 3 || return 1
    else
        dnsTLSDomain=$(echo "${domain}" | awk -F "." '{$1="";print $0}' | sed 's/^[[:space:]]*//' | sed 's/ /./g')
    fi
}

# 自定义email
customSSLEmail() {
    if echo "$1" | grep -q "validate email"; then
        read -r -p "是否重新输入邮箱地址[y/n]:" sslEmailStatus
        if [[ "${sslEmailStatus}" == "y" ]]; then
            sed '/ACCOUNT_EMAIL/d' /root/.acme.sh/account.conf >/root/.acme.sh/account.conf_tmp && mv /root/.acme.sh/account.conf_tmp /root/.acme.sh/account.conf
        else
            exit 0
        fi
    fi

    if [[ -d "/root/.acme.sh" && -f "/root/.acme.sh/account.conf" ]]; then
        if ! grep -q "ACCOUNT_EMAIL" <"/root/.acme.sh/account.conf" && ! echo "${sslType}" | grep -q "letsencrypt"; then
            read -r -p "请输入邮箱地址:" sslEmail
            if echo "${sslEmail}" | grep -q "@"; then
                echo "ACCOUNT_EMAIL='${sslEmail}'" >>/root/.acme.sh/account.conf
                echoContent green " ---> 添加完毕"
            else
                echoContent yellow "请重新输入正确的邮箱格式[例: username@example.com]"
                customSSLEmail
            fi
        fi
    fi

}
# DNS API申请证书
switchDNSAPI() {
    read -r -p "是否使用DNS API申请证书[支持NAT]？[y/n]:" dnsAPIStatus
    if [[ "${dnsAPIStatus}" == "y" ]]; then
        echoContent red "\n=============================================================="
        echoContent yellow "1.cloudflare[默认]"
        echoContent yellow "2.aliyun"
        echoContent red "=============================================================="
        read -r -p "请选择[回车]使用默认:" selectDNSAPIType
        case ${selectDNSAPIType} in
        1)
            dnsAPIType="cloudflare"
            ;;
        2)
            dnsAPIType="aliyun"
            ;;
        *)
            dnsAPIType="cloudflare"
            ;;
        esac
        initDNSAPIConfig "${dnsAPIType}"
    fi
}
# 初始化dns配置
initDNSAPIConfig() {
    if [[ "$1" == "cloudflare" ]]; then
        echoContent yellow "\n CF_Token参考配置教程：https://www.v2ray-agent.com/archives/1701160377972\n"
        read -r -p "请输入API Token:" cfAPIToken
        if [[ -z "${cfAPIToken}" ]]; then
            echoContent red " ---> 输入为空，请重新输入"
            initDNSAPIConfig "$1"
        else
            echo
            if ! echo "${dnsTLSDomain}" | grep -q "\." || [[ -z $(echo "${dnsTLSDomain}" | awk -F "[.]" '{print $1}') ]]; then
                echoContent green " ---> 不支持此域名申请通配符证书，建议使用此格式[xx.xx.xx]"
                exit 0
            fi
            read -r -p "是否使用*.${dnsTLSDomain}进行API申请通配符证书？[y/n]:" dnsAPIStatus
        fi
    elif [[ "$1" == "aliyun" ]]; then
        read -r -p "请输入Ali Key:" aliKey
        read -r -p "请输入Ali Secret:" aliSecret
        if [[ -z "${aliKey}" || -z "${aliSecret}" ]]; then
            echoContent red " ---> 输入为空，请重新输入"
            initDNSAPIConfig "$1"
        else
            echo
            if ! echo "${dnsTLSDomain}" | grep -q "\." || [[ -z $(echo "${dnsTLSDomain}" | awk -F "[.]" '{print $1}') ]]; then
                echoContent green " ---> 不支持此域名申请通配符证书，建议使用此格式[xx.xx.xx]"
                exit 0
            fi
            read -r -p "是否使用*.${dnsTLSDomain}进行API申请通配符证书？[y/n]:" dnsAPIStatus
        fi
    fi
}
# 选择ssl安装类型
switchSSLType() {
    if [[ -z "${sslType}" ]]; then
        echoContent red "\n=============================================================="
        echoContent yellow "1.letsencrypt[默认]"
        echoContent yellow "2.zerossl"
        echoContent yellow "3.buypass[不支持DNS申请]"
        echoContent red "=============================================================="
        read -r -p "请选择[回车]使用默认:" selectSSLType
        case ${selectSSLType} in
        1)
            sslType="letsencrypt"
            ;;
        2)
            sslType="zerossl"
            ;;
        3)
            sslType="buypass"
            ;;
        *)
            sslType="letsencrypt"
            ;;
        esac
        if [[ -n "${dnsAPIType}" && "${sslType}" == "buypass" ]]; then
            echoContent red " ---> buypass不支持API申请证书"
            exit 0
        fi
        echo "${sslType}" >/etc/v2ray-agent/tls/ssl_type
    fi
}

# 选择acme安装证书方式
selectAcmeInstallSSL() {
    acmeInstallSSL

    readAcmeTLS
}

# 安装SSL证书
acmeInstallSSL() {
    local dnsAPIDomain="${tlsDomain}"
    local -a dnsAPIExtraDomain=(-d "${dnsTLSDomain}")
    local -a sslOptions=()
    [[ "${ipType}" != 6 ]] || sslOptions+=(--listen-v6)
    if [[ "${dnsAPIStatus}" == "y" ]]; then
        dnsAPIDomain="*.${dnsTLSDomain}"
    else
        # 用户选择不使用通配符时，只为自己输入的子域申请证书，
        # 避免脚本追加根域 -d ${dnsTLSDomain} 导致根域不属于自己（例如 dpdns.org 等公共后缀）时签发失败
        dnsAPIExtraDomain=()
    fi

    if [[ "${dnsAPIType}" == "cloudflare" ]]; then
        echoContent green " ---> DNS API 生成证书中"
        sudo CF_Token="${cfAPIToken}" "$HOME/.acme.sh/acme.sh" --issue -d "${dnsAPIDomain}" "${dnsAPIExtraDomain[@]}" --dns dns_cf -k ec-256 --server "${sslType}" "${sslOptions[@]}" 2>&1 | tee -a /etc/v2ray-agent/tls/acme.log >/dev/null
    elif [[ "${dnsAPIType}" == "aliyun" ]]; then
        echoContent green " --->  DNS API 生成证书中"
        sudo Ali_Key="${aliKey}" Ali_Secret="${aliSecret}" "$HOME/.acme.sh/acme.sh" --issue -d "${dnsAPIDomain}" "${dnsAPIExtraDomain[@]}" --dns dns_ali -k ec-256 --server "${sslType}" "${sslOptions[@]}" 2>&1 | tee -a /etc/v2ray-agent/tls/acme.log >/dev/null
    else
        echoContent green " ---> 生成证书中"
        sudo "$HOME/.acme.sh/acme.sh" --issue -d "${tlsDomain}" --standalone -k ec-256 --server "${sslType}" "${sslOptions[@]}" 2>&1 | tee -a /etc/v2ray-agent/tls/acme.log >/dev/null
    fi
}
# 检测端口是否占用
checkPort() {
    if [[ -n "$1" ]] && lsof -i "tcp:$1" | grep -q LISTEN; then
        echoContent red "\n ---> $1端口被占用，请手动关闭后安装\n"
        lsof -i "tcp:$1" | grep LISTEN
        [[ "${2:-}" == "transaction" ]] && return 1
        exit 0
    fi
    # BusyBox环境下用内核UDP表匹配本地端口，避免把lsof输出误判为占用
    if echo "${selectCustomInstallType}" | grep -q ",1,"; then
        local udpPortHex udpSockets
        udpPortHex=$(printf '%04X' "$((10#$1))")
        udpSockets=$(awk -v port="${udpPortHex}" 'toupper(substr($2, index($2, ":") + 1)) == port { print }' /proc/net/udp)
        if [[ -n "${udpSockets}" ]]; then
            echoContent red "\n ---> $1/udp端口被占用，请手动关闭后安装\n"
            echo "${udpSockets}"
            [[ "${2:-}" == "transaction" ]] && return 1
            exit 0
        fi
    fi
}

# 安装TLS
installTLS() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : 申请TLS证书\n"
    readAcmeTLS
    local tlsDomain=${domain}

    # 安装tls
    if [[ -f "/etc/v2ray-agent/tls/${tlsDomain}.crt" && -f "/etc/v2ray-agent/tls/${tlsDomain}.key" && -n $(cat "/etc/v2ray-agent/tls/${tlsDomain}.crt") ]] || [[ -d "$HOME/.acme.sh/${tlsDomain}_ecc" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.key" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.cer" ]] || [[ "${installedDNSAPIStatus}" == "true" ]]; then
        echoContent green " ---> 检测到证书"
        renewalTLS

        if [[ -z $(find /etc/v2ray-agent/tls/ -name "${tlsDomain}.crt") ]] || [[ -z $(find /etc/v2ray-agent/tls/ -name "${tlsDomain}.key") ]] || [[ -z $(cat "/etc/v2ray-agent/tls/${tlsDomain}.crt") ]]; then
            if [[ "${installedDNSAPIStatus}" == "true" ]]; then
                sudo "$HOME/.acme.sh/acme.sh" --installcert -d "*.${dnsTLSDomain}" --fullchainpath "/etc/v2ray-agent/tls/${tlsDomain}.crt" --keypath "/etc/v2ray-agent/tls/${tlsDomain}.key" --ecc >/dev/null
            else
                sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${tlsDomain}" --fullchainpath "/etc/v2ray-agent/tls/${tlsDomain}.crt" --keypath "/etc/v2ray-agent/tls/${tlsDomain}.key" --ecc >/dev/null
            fi

        else
            if [[ -d "$HOME/.acme.sh/${tlsDomain}_ecc" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.key" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.cer" ]] || [[ "${installedDNSAPIStatus}" == "true" ]]; then
                if [[ -z "${lastInstallationConfig}" ]]; then
                    echoContent yellow " ---> 如未过期或者自定义证书请选择[n]\n"
                    read -r -p "是否重新安装？[y/n]:" reInstallStatus
                    if [[ "${reInstallStatus}" == "y" ]]; then
                        rm -rf /etc/v2ray-agent/tls/*
                        installTLS "$1"
                    fi
                fi
            fi
        fi

    elif [[ -d "$HOME/.acme.sh" ]] && [[ ! -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.cer" || ! -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.key" ]]; then
        switchDNSAPI
        if [[ -z "${dnsAPIType}" ]]; then
            echoContent yellow "\n ---> 不采用API申请证书"
            echoContent green " ---> 安装TLS证书，需要依赖80端口"
            allowPort 80
        fi

        switchSSLType
        customSSLEmail
        selectAcmeInstallSSL

        if [[ "${installedDNSAPIStatus}" == "true" ]]; then
            sudo "$HOME/.acme.sh/acme.sh" --installcert -d "*.${dnsTLSDomain}" --fullchainpath "/etc/v2ray-agent/tls/${tlsDomain}.crt" --keypath "/etc/v2ray-agent/tls/${tlsDomain}.key" --ecc >/dev/null
        else
            sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${tlsDomain}" --fullchainpath "/etc/v2ray-agent/tls/${tlsDomain}.crt" --keypath "/etc/v2ray-agent/tls/${tlsDomain}.key" --ecc >/dev/null
        fi

        if [[ ! -f "/etc/v2ray-agent/tls/${tlsDomain}.crt" || ! -f "/etc/v2ray-agent/tls/${tlsDomain}.key" ]] || [[ -z $(cat "/etc/v2ray-agent/tls/${tlsDomain}.key") || -z $(cat "/etc/v2ray-agent/tls/${tlsDomain}.crt") ]]; then
            tail -n 10 /etc/v2ray-agent/tls/acme.log
            if [[ ${installTLSCount} == "1" ]]; then
                echoContent red " ---> TLS安装失败，请检查acme日志"
                exit 0
            fi

            installTLSCount=1
            echo

            if tail -n 10 /etc/v2ray-agent/tls/acme.log | grep -q "Could not validate email address as valid"; then
                echoContent red " ---> 邮箱无法通过SSL厂商验证，请重新输入"
                echo
                customSSLEmail "validate email"
                installTLS "$1"
            else
                installTLS "$1"
            fi
        fi

        echoContent green " ---> TLS生成成功"
    else
        echoContent yellow " ---> 未安装acme.sh"
        exit 0
    fi
}

# 初始化随机字符串
initRandomPath() {
    local chars="abcdefghijklmnopqrtuxyz"
    local initCustomPath=
    for i in {1..4}; do
        echo "${i}" >/dev/null
        initCustomPath+="${chars:RANDOM%${#chars}:1}"
    done
    customPath=${initCustomPath}
}

# 自定义/随机路径
randomPathFunction() {
    if [[ -n $1 ]]; then
        echoContent skyBlue "\n进度  $1/${totalProgress} : 生成随机路径"
    else
        echoContent skyBlue "生成随机路径"
    fi

    if [[ -n "${currentPath}" && -z "${lastInstallationConfig}" ]]; then
        echo
        read -r -p "读取到上次安装记录，是否使用上次安装时的path路径 ？[y/n]:" historyPathStatus
        echo
    elif [[ -n "${currentPath}" && -n "${lastInstallationConfig}" ]]; then
        historyPathStatus="y"
    fi

    if [[ "${historyPathStatus}" == "y" ]]; then
        customPath=${currentPath}
        echoContent green " ---> 使用成功\n"
    else
        echoContent yellow "请输入自定义路径[例: alone]，不需要斜杠，[回车]随机路径"
        read -r -p '路径:' customPath
        if [[ -z "${customPath}" ]]; then
            initRandomPath
            currentPath=${customPath}
        else
            currentPath=${customPath}
        fi
    fi
    echoContent yellow "\n path:${currentPath}"
    echoContent skyBlue "\n----------------------------"
}
# 定时任务更新tls证书
installCronTLS() {
        echoContent skyBlue "\n进度 $1/${totalProgress} : 添加定时维护证书"
        crontab -l >/etc/v2ray-agent/backup_crontab.cron
        local historyCrontab
        historyCrontab=$(sed '/v2ray-agent/d;/acme.sh/d' /etc/v2ray-agent/backup_crontab.cron)
        echo "${historyCrontab}" >/etc/v2ray-agent/backup_crontab.cron
        echo "30 1 * * * /bin/bash /etc/v2ray-agent/install.sh RenewTLS >> /etc/v2ray-agent/crontab_tls.log 2>&1" >>/etc/v2ray-agent/backup_crontab.cron
        crontab /etc/v2ray-agent/backup_crontab.cron
        echoContent green "\n ---> 添加定时维护证书成功"
}
# 更新证书
renewalTLS() {
    if [[ -n $1 ]]; then
        echoContent skyBlue "\n进度  $1/1 : 更新证书"
    fi
    local domain=${currentHost}
    if [[ -z "${currentHost}" && -n "${tlsDomain}" ]]; then
        domain=${tlsDomain}
    fi
    readAcmeTLS

    local acmeCertPath=
    local acmeInstallDomain="${domain}"
    if [[ -s "$HOME/.acme.sh/${domain}_ecc/${domain}.cer" && -s "$HOME/.acme.sh/${domain}_ecc/${domain}.key" ]]; then
        acmeCertPath="$HOME/.acme.sh/${domain}_ecc/${domain}.cer"
    elif [[ "${installedDNSAPIStatus}" == "true" ]]; then
        acmeCertPath=$(compgen -G "$HOME/.acme.sh/*${dnsTLSDomain}_ecc/*${dnsTLSDomain}.cer" | head -n 1)
        acmeInstallDomain="*.${dnsTLSDomain}"
    fi

    if [[ -z "${acmeCertPath}" || ! -s "${acmeCertPath}" ]]; then
        if [[ -s "/etc/v2ray-agent/tls/${domain}.crt" && -s "/etc/v2ray-agent/tls/${domain}.key" ]]; then
            echoContent yellow " ---> 检测到使用自定义证书，无法执行renew操作。"
        else
            echoContent red " ---> 未安装"
        fi
        return 0
    fi

    local certPath="/etc/v2ray-agent/tls/${domain}.crt"
    if [[ ! -s "${certPath}" ]]; then
        certPath=${acmeCertPath}
    fi

    local notAfter
    if ! notAfter=$(openssl x509 -in "${certPath}" -noout -enddate 2>/dev/null); then
        echoContent red " ---> 无法读取证书真实到期时间"
        return 1
    fi
    notAfter=${notAfter#notAfter=}
    if [[ -z "${notAfter}" ]]; then
        echoContent red " ---> 无法解析证书真实到期时间"
        return 1
    fi

    local expiryTime
    if ! expiryTime=$(date +%s -d "${notAfter}" 2>/dev/null); then
        echoContent red " ---> 无法解析证书真实到期时间"
        return 1
    fi
    local currentTime
    currentTime=$(date +%s)
    local remainingSeconds=$((expiryTime - currentTime))
    local remainingDays
    local tlsStatus
    if ((remainingSeconds <= 0)); then
        remainingDays=0
        tlsStatus="已过期"
    else
        remainingDays=$(((remainingSeconds + 86399) / 86400))
        tlsStatus=${remainingDays}
    fi

    echoContent skyBlue " ---> 证书检查日期:$(date "+%F %H:%M:%S")"
    echoContent skyBlue " ---> 证书真实到期时间:$(date -d @"${expiryTime}" +"%F %H:%M:%S")"
    echoContent skyBlue " ---> 证书剩余天数:${tlsStatus}"

    if ((remainingSeconds > sslRenewalThresholdDays * 86400)); then
        echoContent green " ---> 证书有效"
        return 0
    fi

    echoContent yellow " ---> 证书进入 ${sslRenewalThresholdDays} 天续期窗口，开始更新"
    if [[ "${coreInstallType}" == "1" ]]; then
        handleXray stop
    fi

    local renewalSuccess=false
    if sudo "$HOME/.acme.sh/acme.sh" --cron --home "$HOME/.acme.sh" &&
        sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${acmeInstallDomain}" --fullchainpath "/etc/v2ray-agent/tls/${domain}.crt" --keypath "/etc/v2ray-agent/tls/${domain}.key" --ecc; then
        local newExpiry
        local newNotAfter
        if newNotAfter=$(openssl x509 -in "/etc/v2ray-agent/tls/${domain}.crt" -noout -enddate 2>/dev/null); then
            newNotAfter=${newNotAfter#notAfter=}
            if newExpiry=$(date +%s -d "${newNotAfter}" 2>/dev/null) && ((newExpiry > currentTime && newExpiry > expiryTime)); then
                renewalSuccess=true
                echoContent green " ---> 证书续期成功，新到期时间:$(date -d @"${newExpiry}" +"%F %H:%M:%S")"
            fi
        fi
    fi

    if [[ "${renewalSuccess}" != "true" ]]; then
        echoContent red " ---> 证书续期失败，下一次定时任务将继续重试"
        if [[ "${coreInstallType}" == "1" ]]; then
            handleXray start
        fi
        return 1
    fi

    reloadCore
    return 0
}

# Download and validate the new binary before replacing the installed core.
installCoreRelease() (
    local core=$1 version=$2 coreDir binary tmpDir
    local -a wgetArgs=(-q)
    [[ "${version}" =~ ^v[0-9][A-Za-z0-9._-]*$ ]] || {
        echoContent red " ---> 无法读取有效的核心版本，保留当前程序"
        return 1
    }
    coreDir="/etc/v2ray-agent/${core}"
    mkdir -p "${coreDir}" || return 1
    tmpDir=$(mktemp -d "${coreDir}/.release.XXXXXX") || return 1
    trap 'rm -rf "${tmpDir}"' EXIT
    if [[ "${release}" != alpine && -n "${wgetShowProgressStatus}" ]]; then
        wgetArgs+=("${wgetShowProgressStatus}")
    fi
        wget "${wgetArgs[@]}" -O "${tmpDir}/archive.zip" \
            "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip" &&
            unzip -oq "${tmpDir}/archive.zip" -d "${tmpDir}" || return 1
        binary="${tmpDir}/xray"
        [[ -s "${binary}" ]] && chmod 755 "${binary}" && "${binary}" --version >/dev/null 2>&1 || return 1
    mv -f "${binary}" "${coreDir}/${core}"
)

# 检查wget showProgress
checkWgetShowProgress() {
    if [[ "${release}" != "alpine" ]]; then
        if find /usr/bin /usr/sbin | grep -q "/wget" && wget --help | grep -q show-progress; then
            wgetShowProgressStatus="--show-progress"
        fi
    fi
}
# 安装xray
installXray() {
    readInstallType
    local prereleaseStatus=false
    if [[ "$2" == "true" ]]; then
        prereleaseStatus=true
    fi

    echoContent skyBlue "\n进度  $1/${totalProgress} : 安装Xray"

    if [[ ! -f "/etc/v2ray-agent/xray/xray" ]]; then
        if [[ "${prereleaseStatus}" == "true" ]]; then
            version=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=5" | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)
        else
            version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)
        fi
        echoContent green " ---> Xray-core版本:${version}"
        installCoreRelease xray "${version}" || return 1
    elif [[ "${3:-}" == force ]]; then
        if [[ "${prereleaseStatus}" == "true" ]]; then
            version=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=5" | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)
        else
            version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)
        fi

        echoContent green " ---> Xray-core版本:${version}"
        installCoreRelease xray "${version}" || return 1
    else
        if [[ -z "${lastInstallationConfig}" ]]; then
            echoContent green " ---> Xray-core版本:$(/etc/v2ray-agent/xray/xray --version | awk '{print $2}' | head -1)"
            read -r -p "是否更新、升级？[y/n]:" reInstallXrayStatus
            if [[ "${reInstallXrayStatus}" == "y" ]]; then
                installXray "$1" "$2" force || return 1
            fi
        fi
    fi
}

# xray版本管理
xrayVersionManageMenu() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : Xray版本管理"
    if [[ "${coreInstallType}" != "1" ]]; then
        echoContent red " ---> 没有检测到安装目录，请执行脚本安装内容"
        exit 0
    fi
    echoContent red "\n=============================================================="
    echoContent yellow "1.升级Xray-core"
    echoContent yellow "2.升级Xray-core 预览版"
    echoContent yellow "3.回退Xray-core"
    echoContent yellow "4.关闭Xray-core"
    echoContent yellow "5.打开Xray-core"
    echoContent yellow "6.重启Xray-core"
    echoContent yellow "7.查看日志"
    echoContent red "=============================================================="
    read -r -p "请选择:" selectXrayType
    if [[ "${selectXrayType}" == "1" ]]; then
        prereleaseStatus=false
        updateXray
    elif [[ "${selectXrayType}" == "2" ]]; then
        prereleaseStatus=true
        updateXray
    elif [[ "${selectXrayType}" == "3" ]]; then
        echoContent yellow "\n1.只可以回退最近的五个版本"
        echoContent yellow "2.不保证回退后一定可以正常使用"
        echoContent yellow "3.如果回退的版本不支持当前的config，则会无法连接，谨慎操作"
        echoContent skyBlue "------------------------Version-------------------------------"
        curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=50" | jq -r '.[] | select(.prerelease == false and .draft == false) | .tag_name' | head -5 | awk '{print ""NR""":"$0}'
        echoContent skyBlue "--------------------------------------------------------------"
        read -r -p "请输入要回退的版本:" selectXrayVersionType
        version=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=50" | jq -r '.[] | select(.prerelease == false and .draft == false) | .tag_name' | head -5 | awk '{print ""NR""":"$0}' | grep "${selectXrayVersionType}:" | awk -F "[:]" '{print $2}')
        if [[ -n "${version}" ]]; then
            updateXray "${version}"
        else
            echoContent red "\n ---> 输入有误，请重新输入"
            xrayVersionManageMenu 1
        fi
    elif [[ "${selectXrayType}" == "4" ]]; then
        handleXray stop
    elif [[ "${selectXrayType}" == "5" ]]; then
        handleXray start
    elif [[ "${selectXrayType}" == "6" ]]; then
        reloadCore
    elif [[ "${selectXrayType}" == "7" ]]; then
        checkLog 1
    fi
}

# 更新Xray
updateXray() {
    readInstallType

    if [[ -z "${coreInstallType}" || "${coreInstallType}" != "1" ]]; then

        if [[ "${prereleaseStatus}" == "true" ]]; then
            version=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=5" | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)
        else
            version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)
        fi

        if [[ -n "$1" ]]; then
            version=$1
        fi

        echoContent green " ---> Xray-core版本:${version}"

        installCoreRelease xray "${version}" || return 1
        handleXray stop transaction || return 1
        handleXray start transaction || return 1
    else
        echoContent green " ---> 当前版本:v$(/etc/v2ray-agent/xray/xray --version | awk '{print $2}' | head -1)"

        if [[ "${prereleaseStatus}" == "true" ]]; then
            remoteVersion=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=5" | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)
        else
            remoteVersion=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)
        fi

        if [[ "${prereleaseStatus}" == "true" ]]; then
            echoContent green " ---> 最新Pre版本:${remoteVersion}"
        else
            echoContent green " ---> 最新版本:${remoteVersion}"
        fi

        if [[ -n "$1" ]]; then
            version=$1
        else
            version=${remoteVersion}
        fi

        if [[ -n "$1" ]]; then
            read -r -p "回退版本为${version}，是否继续？[y/n]:" rollbackXrayStatus
            if [[ "${rollbackXrayStatus}" == "y" ]]; then
                echoContent green " ---> 当前Xray-core版本:$(/etc/v2ray-agent/xray/xray --version | awk '{print $2}' | head -1)"

                installCoreRelease xray "${version}" || return 1
                handleXray stop transaction || return 1
                handleXray start transaction || return 1
            else
                echoContent green " ---> 放弃回退版本"
            fi
        elif [[ "${version}" == "v$(/etc/v2ray-agent/xray/xray --version | awk '{print $2}' | head -1)" ]]; then
            if [[ "${prereleaseStatus}" == "true" ]]; then
                read -r -p "当前版本与最新Pre版本相同，是否重新安装？[y/n]:" reInstallXrayStatus
            else
                read -r -p "当前版本与最新版相同，是否重新安装？[y/n]:" reInstallXrayStatus
            fi
            if [[ "${reInstallXrayStatus}" == "y" ]]; then
                installCoreRelease xray "${version}" || return 1
                handleXray stop transaction || return 1
                handleXray start transaction || return 1
            else
                echoContent green " ---> 放弃重新安装"
            fi
        else
            if [[ "${prereleaseStatus}" == "true" ]]; then
                read -r -p "最新Pre版本为:${version}，是否更新？[y/n]:" installXrayStatus
            else
                read -r -p "最新版本为:${version}，是否更新？[y/n]:" installXrayStatus
            fi
            if [[ "${installXrayStatus}" == "y" ]]; then
                installCoreRelease xray "${version}" || return 1
                handleXray stop transaction || return 1
                handleXray start transaction || return 1
            else
                echoContent green " ---> 放弃更新"
            fi

        fi
    fi
}

# 安装alpine开机启动
installAlpineStartup() {
    local serviceName=$1
        cat <<EOF >"/etc/init.d/${serviceName}"
#!/sbin/openrc-run

description="xray service"
command="/etc/v2ray-agent/xray/xray"
command_args="run -confdir /etc/v2ray-agent/xray/conf"
command_background=true
pidfile="/var/run/xray.pid"
EOF

    chmod +x "/etc/init.d/${serviceName}"
}

# Xray开机自启
installXrayService() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : 配置Xray开机自启"
    execStart='/etc/v2ray-agent/xray/xray run -confdir /etc/v2ray-agent/xray/conf'
    if [[ -n $(find /bin /usr/bin -name "systemctl") ]]; then
        rm -rf /etc/systemd/system/xray.service
        touch /etc/systemd/system/xray.service
        cat <<EOF >/etc/systemd/system/xray.service
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target
[Service]
User=root
ExecStart=${execStart}
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=infinity
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
EOF
        bootStartup "xray.service"
        echoContent green " ---> 配置Xray开机自启成功"
    elif [[ "${release}" == "alpine" ]]; then
        installAlpineStartup "xray"
        bootStartup "xray"
    fi
}

# 操作xray
handleXray() {
    if [[ -n $(find /bin /usr/bin -name "systemctl") ]] && [[ -n $(find /etc/systemd/system/ -name "xray.service") ]]; then
        if [[ -z $(pgrep -f "xray/xray") ]] && [[ "$1" == "start" ]]; then
            systemctl start xray.service
        elif [[ -n $(pgrep -f "xray/xray") ]] && [[ "$1" == "stop" ]]; then
            systemctl stop xray.service
        fi
    elif [[ -f "/etc/init.d/xray" ]]; then
        if [[ -z $(pgrep -f "xray/xray") ]] && [[ "$1" == "start" ]]; then
            rc-service xray start
        elif [[ -n $(pgrep -f "xray/xray") ]] && [[ "$1" == "stop" ]]; then
            rc-service xray stop
        fi
    fi

    sleep 0.8

    if [[ "$1" == "start" ]]; then
        if [[ -n $(pgrep -f "xray/xray") ]]; then
            echoContent green " ---> Xray启动成功"
        else
            echoContent red "Xray启动失败"
            echoContent red "请手动执行以下的命令后【/etc/v2ray-agent/xray/xray -confdir /etc/v2ray-agent/xray/conf】将错误日志进行反馈"
            [[ "${2:-}" == "transaction" ]] && return 1
            exit 0
        fi
    elif [[ "$1" == "stop" ]]; then
        if [[ -z $(pgrep -f "xray/xray") ]]; then
            echoContent green " ---> Xray关闭成功"
        else
            echoContent red "xray关闭失败"
            echoContent red "请手动执行【ps -ef|grep -v grep|grep xray|awk '{print \$2}'|xargs kill -9】"
            [[ "${2:-}" == "transaction" ]] && return 1
            exit 0
        fi
    fi
}

# 读取Xray用户数据并初始化
initXrayClients() {
    local newUUID=${1:-}
    local newEmail=${2:-}
    if [[ -n "${newUUID}" ]]; then
        local newUser=
        newUser="{\"id\":\"${newUUID}\",\"email\":\"${newEmail}\"}"
        currentClients=$(echo "${currentClients}" | jq -r ". +=[${newUser}]")
    fi
    local users=
    users=[]
    while read -r user; do
        uuid=$(echo "${user}" | jq -r .id)
        email=$(accountUserKey "$(echo "${user}" | jq -r .email)")
        currentUser="{\"id\":\"${uuid}\",\"email\":\"${email}-VLESS_XHTTP_TLS\"}"
        users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
    done < <(echo "${currentClients}" | jq -c '.[]')
    echo "${users}"
}

addXrayOutbound() {
    local tag=$1
    cat <<EOF >"/etc/v2ray-agent/xray/conf/${tag}.json"
{
    "outbounds":[
        {
            "protocol":"freedom",
            "settings": {
                "domainStrategy":"UseIP"
            },
            "tag":"${tag}"
        }
    ]
}
EOF
}

# 初始化Xray 配置文件
initXrayConfig() {
    coreInstallType=1
    configPath=/etc/v2ray-agent/xray/conf/
    mkdir -p "${configPath}" || return 1
    echoContent skyBlue "\n进度 $1/${totalProgress} : 初始化Xray配置"
    echo
    local uuid=
    local addClientsStatus=
    if [[ -n "${currentUUID}" && -z "${lastInstallationConfig}" ]]; then
        read -r -p "读取到上次用户配置，是否使用上次安装的配置 ？[y/n]:" historyUUIDStatus
        if [[ "${historyUUIDStatus}" == "y" ]]; then
            addClientsStatus=true
            echoContent green "\n ---> 使用成功"
        fi
    elif [[ -n "${currentUUID}" && -n "${lastInstallationConfig}" ]]; then
        addClientsStatus=true
    fi

    if [[ -z "${addClientsStatus}" ]]; then
        echoContent yellow "请输入自定义UUID[需合法]，[回车]随机UUID"
        read -r -p 'UUID:' customUUID

        if [[ -n ${customUUID} ]]; then
            uuid=${customUUID}
        else
            uuid=$(/etc/v2ray-agent/xray/xray uuid)
        fi

        echoContent yellow "\n请输入自定义用户名[需合法]，[回车]随机用户名"
        read -r -p '用户名:' customEmail
        if [[ -z ${customEmail} ]]; then
            customEmail="$(echo "${uuid}" | cut -d "-" -f 1)"
        fi
    fi

    if [[ -z "${addClientsStatus}" && -z "${uuid}" ]]; then
        addClientsStatus=
        echoContent red "\n ---> uuid读取错误，随机生成"
        uuid=$(/etc/v2ray-agent/xray/xray uuid)
    fi

    if [[ -n "${uuid}" ]]; then
        currentClients='[{"id":"'${uuid}'","email":"'${customEmail}'"}]'
        echoContent green "\n ${customEmail}:${uuid}"
        echo
    fi

    # log
    if [[ ! -f "/etc/v2ray-agent/xray/conf/00_log.json" ]]; then

        cat <<EOF >/etc/v2ray-agent/xray/conf/00_log.json
{
  "log": {
    "error": "/etc/v2ray-agent/xray/error.log",
    "loglevel": "warning",
    "dnsLog": false
  }
}
EOF
    fi

    if [[ ! -f "/etc/v2ray-agent/xray/conf/12_policy.json" ]]; then

        cat <<EOF >/etc/v2ray-agent/xray/conf/12_policy.json
{
  "policy": {
      "levels": {
          "0": {
              "handshake": $((1 + RANDOM % 4)),
              "connIdle": $((250 + RANDOM % 51))
          }
      }
  }
}
EOF
    fi

    addXrayOutbound "z_direct_outbound" || return 1
    # dns
    if [[ ! -f "/etc/v2ray-agent/xray/conf/11_dns.json" ]]; then
        cat <<EOF >/etc/v2ray-agent/xray/conf/11_dns.json
{
    "dns": {
        "servers": [
          "localhost"
        ]
  }
}
EOF
    fi

    initXrayXHTTPTLSPort || return 1
    local clients
    clients=$(initXrayClients)
    if echo "${selectCustomInstallType}" | grep -q ",2,"; then
        buildXrayXHTTPTLSConfig "${xHTTPTLSPort}" "${domain}" "${customPath}" "${clients}" >"${configPath}02_VLESS_XHTTP_TLS_inbounds.json" || return 1
    else
        rm "${configPath}02_VLESS_XHTTP_TLS_inbounds.json" >/dev/null 2>&1
    fi
    if echo "${selectCustomInstallType}" | grep -q ",1,"; then
        buildXrayXHTTPH3Config "${xHTTPTLSPort}" "${domain}" "${customPath}" "${clients}" "${xhttpH3Up}" >"${configPath}01_VLESS_XHTTP_H3_inbounds.json" || return 1
    else
        rm "${configPath}01_VLESS_XHTTP_H3_inbounds.json" >/dev/null 2>&1
    fi
}

# 初始化本地订阅配置，避免重复生成账号节点
initSubscribeLocalConfig() {
    rm -rf /etc/v2ray-agent/subscribe_local/default/*
    rm -rf /etc/v2ray-agent/subscribe_local/clashMeta/*
}
# 通用
defaultBase64Code() {
    local port=$1
    local email=$2
    local id=$3
    local add=$4
    local path=$5
    local outputRoot=${accountSubscriptionLocalRoot:-/etc/v2ray-agent/subscribe_local}
    local alpn=${6:-h2}
    local user=
    user=$(echo "${email}" | awk -F "[-]" '{print $1}')
    local xhttpTLSURI
    xhttpTLSURI=$(buildVLESSXHTTPTLSURI "${add}" "${port}" "${id}" "${currentHost}" "${path}" "${currentXHTTPMode:-auto}" "${email}" "${alpn}") || return 1
    echoContent yellow " ---> 通用格式(VLESS+XHTTP+TLS)"
    echoContent green "    ${xhttpTLSURI}"
    echoContent yellow " ---> 格式化明文(VLESS+XHTTP+TLS)"
    echoContent green "协议类型:VLESS，地址:${add}，伪装域名/SNI:${currentHost}，端口:${port}，用户ID:${id}，安全:tls，传输方式:xhttp，路径:${path}，模式:${currentXHTTPMode:-auto}，账户名:${email}\n"
    echoContent yellow " ---> 二维码 VLESS(VLESS+XHTTP+TLS)"
    echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vless%3A%2F%2F${id}%40${add}%3A${port}%3Fencryption%3Dnone%26security%3Dtls%26type%3Dxhttp%26sni%3D${currentHost}%26host%3D${currentHost}%26fp%3Dchrome%26alpn%3D${alpn}%26path%3D%252F${path#/}%26mode%3D${currentXHTTPMode:-auto}%23${email}"
    printf '%s\n' "${xhttpTLSURI}" >>"${outputRoot}/default/${user}" || return 1
    buildMihomoXHTTPTLSNode "${add}" "${port}" "${id}" "${currentHost}" "${path}" "${currentXHTTPMode:-auto}" "${email}" "${alpn}" >>"${outputRoot}/clashMeta/${user}" || return 1
}

# 从原始账号名得到现有订阅文件使用的用户键。
accountUserKey() {
    local name=$1
    printf '%s\n' "${name%%-*}"
}

accountUserMatches() {
    local user=$1 selectedKey=$2 rawName key
    rawName=$(jq -er '.email // .name // .username // empty | strings' <<<"${user}") || return 1
    key=$(accountUserKey "${rawName}")
    [[ "${key}" == "${selectedKey}" ]]
}

collectAccountUsers() {
    local file record name key label
    local users='[]'
    while IFS= read -r -d '' file; do
        jq -e 'type == "object" and (.inbounds | type == "array")' "${file}" >/dev/null 2>&1 || {
            echoContent red " ---> 用户配置无效: ${file}"
            return 1
        }
        label=$(basename "${file}" .json)
        while IFS= read -r record; do
            name=$(jq -er '.email // .name // .username // empty | strings' <<<"${record}") || continue
            key=$(accountUserKey "${name}")
            if [[ -z "${key}" || "${key}" == . || "${key}" == .. || "${key}" == */* || "${key}" == *$'\n'* || "${key}" == *$'\r'* ]]; then
                echoContent red " ---> 用户名无法安全用于订阅路径: ${name} (${file})"
                return 1
            fi
            users=$(jq -c --arg key "${key}" --arg name "${name}" --arg protocol "${label}" \
                '([.[] | select(.key == $key)][0] // {key:$key,names:[],protocols:[]}) as $current |
                 map(select(.key != $key)) + [($current | .names += [$name] | .names |= unique | .protocols += [$protocol] | .protocols |= unique)]' \
                <<<"${users}") || return 1
        done < <(jq -c '[.inbounds[0].settings.clients[]?] | .[]' "${file}")
    done < <(find "${configPath}" -maxdepth 1 -type f -name '0[12]_VLESS_XHTTP*_inbounds.json' -print0 2>/dev/null)
    jq -c 'sort_by(.key)' <<<"${users}"
}

selectAccountUser() {
    local users=$1 count index selected
    count=$(jq 'length' <<<"${users}") || return 1
    ((count > 0)) || {
        echoContent yellow " ---> 没有可查看的用户"
        return 2
    }
    while :; do
        echoContent skyBlue "\n请选择要查看的用户:"
        jq -r 'to_entries[] | "\(.key + 1).\(.value.key)"' <<<"${users}"
        read -r -p "请输入:" selected || return 2
        case "${selected}" in
        '' | *[!0-9]*) echoContent red " ---> 选择无效，请重试" ;;
        *)
            index=$((10#${selected}))
            if ((index >= 1 && index <= count)); then
                accountSelectionKey=$(jq -r --argjson index "$((index - 1))" '.[$index].key' <<<"${users}") || return 1
                return 0
            fi
            echoContent red " ---> 选择无效，请重试"
            ;;
        esac
    done
}

# Read and validate a complete account configuration before entering user loops.
readAccountUsers() {
    local filter=$1 file=$2
    jq -sc 'if length == 1 and (.[0] | type == "object" and (.inbounds | type == "array"))
        then .[0] | '"${filter}"'
        else error("Invalid account configuration") end' "${file}"
}

showAccounts() {
    local accountViewKey=${2:-}
    local accountSubscriptionLocalRoot=${3:-/etc/v2ray-agent/subscribe_local}
    local user accountUsers
    readInstallType
    readInstallProtocolType
    readConfigHostPathUUID

    echo
    echoContent skyBlue "\n进度 $1/${totalProgress} : 账号"

    if [[ -z "${accountViewKey}" ]]; then
        initSubscribeLocalConfig
    else
        mkdir -p "${accountSubscriptionLocalRoot}/default" "${accountSubscriptionLocalRoot}/clashMeta" || return 1
    fi
    if [[ -n "${currentInstallProtocolType}" ]]; then
        local accountConfig="${configPath}02_VLESS_XHTTP_TLS_inbounds.json"
        [[ -f "${accountConfig}" ]] || accountConfig="${configPath}01_VLESS_XHTTP_H3_inbounds.json"
        accountUsers=$(readAccountUsers '.inbounds[0].settings.clients[]?' "${accountConfig}") || return 1
        local xhttpTLSCDNAddress= directAddress
        [[ -f "/etc/v2ray-agent/cdn" ]] && xhttpTLSCDNAddress=$(head -1 "/etc/v2ray-agent/cdn" | tr -d '\r\n')
        [[ -f "/etc/v2ray-agent/xhttp-direct-address" ]] && directAddress=$(head -1 "/etc/v2ray-agent/xhttp-direct-address" | tr -d '\r\n')
        [[ -n "${directAddress}" ]] || directAddress=$(getPublicIP)
        echoContent skyBlue "\n================================ VLESS XHTTP TLS ================================\n"
        while IFS= read -r user; do
            [[ -n "${user}" ]] || continue
            if [[ -n "${accountViewKey}" ]] && ! accountUserMatches "${user}" "${accountViewKey}"; then continue; fi
            local email uuidValue nodeName
            email=$(echo "${user}" | jq -r '.email // .name')
            uuidValue=$(echo "${user}" | jq -r '.id // .uuid // .password')
            if echo "${currentInstallProtocolType}" | grep -q ",1,"; then
                nodeName=${email}
                if echo "${currentInstallProtocolType}" | grep -q ",2,"; then nodeName="${email}_h3"; fi
                echoContent skyBlue "\n ---> 账号:${nodeName}"
                currentXHTTPMode=auto
                defaultBase64Code "${xrayVLESSXHTTPTLSPort}" "${nodeName}" "${uuidValue}" "${directAddress}" "${currentPath}xHTTP" h3 || return 1
            fi
            if echo "${currentInstallProtocolType}" | grep -q ",2,"; then
                nodeName="${email}_cdn1"
                echoContent skyBlue "\n ---> 账号:${nodeName}"
                currentXHTTPMode=packet-up
                defaultBase64Code "${xrayVLESSXHTTPTLSPort}" "${nodeName}" "${uuidValue}" "${xhttpTLSCDNAddress}" "${currentPath}xHTTP" h2 || return 1
                nodeName="${nodeName}_h3"
                echoContent skyBlue "\n ---> 账号:${nodeName}"
                defaultBase64Code "${xrayVLESSXHTTPTLSPort}" "${nodeName}" "${uuidValue}" "${xhttpTLSCDNAddress}" "${currentPath}xHTTP" h3 || return 1
            fi
        done <<<"${accountUsers}"
    fi
}
unInstall() {
    read -r -p "是否确认卸载安装内容？[y/n]:" unInstallStatus
    if [[ "${unInstallStatus}" != "y" ]]; then
        echoContent green " ---> 放弃卸载"
        menu
        exit 0
    fi
    echoContent yellow " ---> 脚本不会删除acme相关配置，删除请手动执行 [rm -rf /root/.acme.sh]"
    removeCoreService xray || {
        echoContent red " ---> Xray service清理失败，已停止卸载"
        return 1
    }
    rm -rf /etc/v2ray-agent


    rm -rf /usr/bin/vasma
    rm -rf /usr/sbin/vasma
    echoContent green " ---> 卸载快捷方式完成"
    echoContent green " ---> 卸载v2ray-agent脚本完成"
}
customUUID() {
    read -r -p "请输入合法的UUID，[回车]随机UUID:" currentCustomUUID
    echo
    if [[ -z "${currentCustomUUID}" ]]; then
        if [[ "${coreInstallType}" == "1" ]]; then
            currentCustomUUID=$(${ctlPath} uuid)
        fi

        echoContent yellow "uuid：${currentCustomUUID}\n"

    else
        local checkUUID=
        if [[ "${coreInstallType}" == "1" ]]; then
            local referenceConfig
            referenceConfig=$(getXrayAccountReferenceConfig) || return 1
            checkUUID=$(jq -r --arg currentUUID "$currentCustomUUID" '.inbounds[0].settings.clients[]? | select(.id == $currentUUID) | .email // .name' "${referenceConfig}")
        fi

        if [[ -n "${checkUUID}" ]]; then
            echoContent red " ---> UUID不可重复"
            exit 0
        fi
    fi
}

# 自定义email
customUserEmail() {
    read -r -p "请输入合法的email，[回车]随机email:" currentCustomEmail
    echo
    if [[ -z "${currentCustomEmail}" ]]; then
        currentCustomEmail="${currentCustomUUID}"
        echoContent yellow "email: ${currentCustomEmail}\n"
    else
        local checkEmail=
        local currentEmailKey
        currentEmailKey=$(accountUserKey "${currentCustomEmail}")
        if [[ "${coreInstallType}" == "1" ]]; then
            local referenceConfig
            referenceConfig=$(getXrayAccountReferenceConfig) || return 1
            checkEmail=$(jq -r --arg currentEmail "$currentEmailKey" '(.inbounds[0].settings.clients // .inbounds[1].settings.clients // .inbounds[0].settings.users)[]? | select((.email // .name // "") | split("-")[0] == $currentEmail) | .email // .name' "${referenceConfig}")
        fi

        if [[ -n "${checkEmail}" ]]; then
            echoContent red " ---> email不可重复"
            exit 0
        fi
    fi
}

# 添加用户
addUser() {
    read -r -p "请输入要添加的用户数量:" userNum
    echo
    if ! isNumber "${userNum}" || [[ "${userNum}" -le 0 ]]; then
        echoContent red " ---> 输入有误，请重新输入"
        exit 0
    fi
    while [[ ${userNum} -gt 0 ]]; do
        readConfigHostPathUUID
        ((userNum--)) || true

        customUUID || return 1
        customUserEmail || return 1

        uuid=${currentCustomUUID}
        email=${currentCustomEmail}

        local clients xhttpTLSConfig xhttpTLSResult
        clients=$(initXrayClients "${uuid}" "${email}")
        for xhttpTLSConfig in "${configPath}02_VLESS_XHTTP_TLS_inbounds.json" "${configPath}01_VLESS_XHTTP_H3_inbounds.json"; do
            [[ -f "${xhttpTLSConfig}" ]] || continue
            xhttpTLSResult=$(jq --argjson clients "${clients}" '.inbounds[0].settings.clients = $clients' "${xhttpTLSConfig}")
            echo "${xhttpTLSResult}" | jq . >"${xhttpTLSConfig}"
        done
    done
    if ! reloadCore transaction; then
        echoContent red " ---> 用户已写入配置，但核心重载失败，请检查配置后手动重启"
        return 1
    fi
    echoContent green " ---> 添加完成"
    if [[ -f /etc/v2ray-agent/subscribe_local/subscribeSalt ]]; then
        subscribe false || return 1
    fi
    manageAccount 1
}
# 移除用户
removeUser() {

    local delUserIndex=
    local uuid=
    local referenceConfig=
    if [[ "${coreInstallType}" == "1" ]]; then
        referenceConfig=$(getXrayAccountReferenceConfig) || {
            echoContent red " ---> 未找到可管理的Xray用户配置"
            return 1
        }
        jq -r -c '.inbounds[0].settings.clients[]?.email' "${referenceConfig}" | awk '{print NR""":"$0}'
        read -r -p "请选择要删除的用户编号[仅支持单个删除]:" delUserIndex
        if ! delUserIndex=$(jq -enr --arg index "${delUserIndex}" \
            --argjson count "$(jq '.inbounds[0].settings.clients | length' "${referenceConfig}")" '
              select($index | test("^[0-9]+$")) | ($index | tonumber) |
              select(. >= 1 and . <= $count) | . - 1'); then
            echoContent red " ---> 选择错误"
            return 1
        else
            uuid=$(jq -r --argjson index "${delUserIndex}" '.inbounds[0].settings.clients[$index].id // empty' "${referenceConfig}")
            [[ -n "${uuid}" ]] || {
                echoContent red " ---> 无法读取所选用户的UUID"
                return 1
            }
        fi
        if ! deleteXrayUserByUUID "${uuid}"; then
            echoContent red " ---> 删除用户失败，请检查上方错误信息"
            return 1
        fi
        echoContent green " ---> 删除用户完成"
        if [[ -f /etc/v2ray-agent/subscribe_local/subscribeSalt ]]; then
            subscribe false || echoContent red " ---> 用户已删除，但订阅刷新失败"
        fi
        manageAccount 1
        return
    fi
}
checkLog() {
    if [[ -z "${configPath}" ]]; then
        echoContent red " ---> 没有检测到安装目录，请执行脚本安装内容"
        exit 0
    fi
    local logStatus=false
    if grep -q "access" ${configPath}00_log.json; then
        logStatus=true
    fi

    echoContent skyBlue "\n功能 $1/${totalProgress} : 查看日志"
    echoContent red "\n=============================================================="
    echoContent yellow "# 建议仅调试时打开access日志\n"

    if [[ "${logStatus}" == "false" ]]; then
        echoContent yellow "1.打开access日志"
    else
        echoContent yellow "1.关闭access日志"
    fi

    echoContent yellow "2.监听access日志"
    echoContent yellow "3.监听error日志"
    echoContent yellow "4.查看证书定时任务日志"
    echoContent yellow "5.查看证书安装日志"
    echoContent yellow "6.清空日志"
    echoContent red "=============================================================="

    read -r -p "请选择:" selectAccessLogType
    local configPathLog=${configPath//conf\//}

    case ${selectAccessLogType} in
    1)
        if [[ "${logStatus}" == "false" ]]; then
            cat <<EOF >${configPath}00_log.json
{
  "log": {
    "access":"${configPathLog}access.log",
    "error": "${configPathLog}error.log",
    "loglevel": "debug"
  }
}
EOF
        elif [[ "${logStatus}" == "true" ]]; then
            cat <<EOF >${configPath}00_log.json
{
  "log": {
    "error": "${configPathLog}error.log",
    "loglevel": "warning"
  }
}
EOF
        fi

        reloadCore
        checkLog 1
        ;;
    2)
        tail -f "${configPathLog}access.log"
        ;;
    3)
        tail -f "${configPathLog}error.log"
        ;;
    4)
        if [[ ! -f "/etc/v2ray-agent/crontab_tls.log" ]]; then
            touch /etc/v2ray-agent/crontab_tls.log
        fi
        tail -n 100 /etc/v2ray-agent/crontab_tls.log
        ;;
    5)
        tail -n 100 /etc/v2ray-agent/tls/acme.log
        ;;
    6)
        echo >"${configPathLog}access.log"
        echo >"${configPathLog}error.log"
        ;;
    esac
}

# 脚本快捷方式
aliasInstall() {

    if [[ -f "$HOME/install.sh" ]] && [[ -d "/etc/v2ray-agent" ]] && grep <"$HOME/install.sh" -q "作者：qihang518887"; then
        mv "$HOME/install.sh" /etc/v2ray-agent/install.sh
        local vasmaType=
        if [[ -d "/usr/bin/" ]]; then
            if [[ ! -f "/usr/bin/vasma" ]]; then
                ln -s /etc/v2ray-agent/install.sh /usr/bin/vasma
                chmod 700 /usr/bin/vasma
                vasmaType=true
            fi

            rm -rf "$HOME/install.sh"
        elif [[ -d "/usr/sbin" ]]; then
            if [[ ! -f "/usr/sbin/vasma" ]]; then
                ln -s /etc/v2ray-agent/install.sh /usr/sbin/vasma
                chmod 700 /usr/sbin/vasma
                vasmaType=true
            fi
            rm -rf "$HOME/install.sh"
        fi
        if [[ "${vasmaType}" == "true" ]]; then
            echoContent green "快捷方式创建成功，可执行[vasma]重新打开脚本"
        fi
    fi
}

reloadCore() {
    readInstallType

    if [[ "${coreInstallType}" == "1" ]]; then
        handleXray stop "${1:-}" || return 1
        handleXray start "${1:-}" || return 1
    fi
}

setupXHTTPSubscriptionAddresses() {
    if echo "${selectCustomInstallType}" | grep -q ",1,"; then
        if echo "${selectCustomInstallType}" | grep -q ",2,"; then
            while [[ -z "${xhttpDirectAddress}" ]]; do
                read -r -p "请输入H3直连IP/域名（必填）:" xhttpDirectAddress
            done
        else
            read -r -p "请输入H3直连IP/域名[回车使用公网IP]:" xhttpDirectAddress
            [[ -n "${xhttpDirectAddress}" ]] || xhttpDirectAddress=$(getPublicIP)
        fi
        printf '%s\n' "${xhttpDirectAddress}" >/etc/v2ray-agent/xhttp-direct-address || return 1
    fi
    if echo "${selectCustomInstallType}" | grep -q ",2,"; then
        local preferredCNAME=
        read -r -p "请输入优选CNAME[回车使用证书域名 ${domain}]:" preferredCNAME
        printf '%s\n' "${preferredCNAME:-${domain}}" >/etc/v2ray-agent/cdn || return 1
    fi
}

# Xray-core个性化安装
customXrayInstall() {
    echoContent skyBlue "\n========================个性化安装============================"
    echoContent yellow "1.H3直连"
    echoContent yellow "2.CDN(H2+H3)"
    read -r -p "请选择（可多选，英文逗号分隔）:" selectCustomInstallType
    echoContent skyBlue "--------------------------------------------------------------"
    if echo "${selectCustomInstallType}" | grep -q "，"; then
        echoContent red " ---> 请使用英文逗号分隔"
        exit 0
    fi
    if [[ ! "${selectCustomInstallType}" =~ ^(1|2)(,(1|2))?$ ]]; then
        echoContent red " ---> 仅支持选择1、2或1,2"
        exit 0
    fi
    selectCustomInstallType=$(normalizeXrayInstallSelection "${selectCustomInstallType}")
    if echo "${selectCustomInstallType}" | grep -q ",1,"; then
        read -r -p "请输入期望的本地下载速度（Mbps）[默认50，填0不设置]：" xhttpH3Up
        xhttpH3Up=${xhttpH3Up:-50}
        isNumber "${xhttpH3Up}" || {
            echoContent red " ---> 请输入整数Mbps"
            exit 0
        }
    fi
    readLastInstallationConfig
    unInstallSubscribe
    totalProgress=12
    installTools 1 || return 1
    initTLSDomain 2 || return 1
    installTLS 3 || return 1
    randomPathFunction 4

    # 安装Xray
    handleXray stop transaction || return 1
    installXray 7 false || return 1
    installXrayService 8 || return 1
    initXrayConfig 9 || return 1
    handleXray start transaction || return 1
    installCronTLS 10
    setupXHTTPSubscriptionAddresses || return 1
    # 生成账号
    showAccounts 12
}

# 定时任务检查
cronFunction() {
    if [[ "${cronName}" == "RenewTLS" ]]; then
        renewalTLS
        exit 0
    fi
}
# 账号管理
manageAccount() {
    echoContent skyBlue "\n功能 1/${totalProgress} : 账号管理"
    if [[ -z "${configPath}" ]]; then
        echoContent red " ---> 未安装"
        exit 0
    fi

    echoContent red "\n=============================================================="
    echoContent yellow "# 添加单个用户时可自定义email和uuid"
    echoContent yellow "1.查看账号"
    echoContent yellow "2.查看订阅"
    echoContent yellow "3.管理其他订阅"
    echoContent yellow "4.添加用户"
    echoContent yellow "5.删除用户"
    echoContent yellow "6.生成/更新订阅（全部用户）"
    echoContent red "=============================================================="
    read -r -p "请输入:" manageAccountStatus
    if [[ "${manageAccountStatus}" == "1" ]]; then
        viewAccountsByUser
    elif [[ "${manageAccountStatus}" == "2" ]]; then
        viewSubscriptionByUser
    elif [[ "${manageAccountStatus}" == "3" ]]; then
        addSubscribeMenu 1
    elif [[ "${manageAccountStatus}" == "4" ]]; then
        addUser
    elif [[ "${manageAccountStatus}" == "5" ]]; then
        removeUser
    elif [[ "${manageAccountStatus}" == "6" ]]; then
        subscribe
    else
        echoContent red " ---> 选择错误"
    fi
}

viewAccountsByUser() {
    readInstallType
    local users tempDir
    users=$(collectAccountUsers) || return 1
    selectAccountUser "${users}" || return 0
    tempDir=$(mktemp -d) || return 1
    chmod 700 "${tempDir}" || {
        rm -rf "${tempDir}"
        return 1
    }
    (
        trap 'rm -rf "${tempDir}"' EXIT
        showAccounts 1 "${accountSelectionKey}" "${tempDir}"
    )
}

# Display locally generated subscription files without hosting them.
showUserSubscriptions() {
    local subscriptionUser=$1 emailMd5=$2 publishDir=$3
    local format file title
    local -a availableFormats=()
    for format in default clashMeta; do
        file="${publishDir}/${format}/${emailMd5}"
        [[ -s "${file}" ]] && availableFormats+=("${format}")
    done
    echoContent skyBlue "=============================================================="
    echoContent brightPurple "\n用户本地订阅文件"
    printf '\n用户 \033[93m%s\033[0m  /  可用订阅 \033[93m%s\033[0m 种' "${subscriptionUser}" "${#availableFormats[@]}"
    if [[ ${#availableFormats[@]} -eq 0 ]]; then
        echoContent yellow "  该用户尚无已生成的订阅文件，请先使用 6.生成/更新订阅。"
        return 1
    fi
    for format in "${availableFormats[@]}"; do
        file="${publishDir}/${format}/${emailMd5}"
        if [[ "${format}" == default ]]; then
            title="通用订阅（Base64）"
        else
            title="Mihomo 节点配置"
        fi
        echo
        echoContent white "=============================================================="
        echoContent skyBlue "${title}"
        echoContent gray "本地文件：${file}"
        if [[ "${format}" == default ]]; then
            base64 -d "${file}"
        else
            cat "${file}"
        fi
    done
}

viewSubscriptionByUser() {
    readInstallType
    local users
    users=$(collectAccountUsers) || return 1
    selectAccountUser "${users}" || return 0
    # 查看订阅会重新生成本地账号的订阅
    subscribe || return 1
    local subscribeSalt emailMd5 publishDir
    subscribeSalt=$(cat /etc/v2ray-agent/subscribe_local/subscribeSalt) || return 1
    emailMd5=$(printf '%s\n' "${accountSelectionKey}${subscribeSalt}" | md5sum | awk '{print $1}')
    publishDir=/etc/v2ray-agent/subscribe
    showUserSubscriptions "${accountSelectionKey}" "${emailMd5}" "${publishDir}"
}

unInstallSubscribe() {
    rm -rf /etc/v2ray-agent/subscribe >/dev/null 2>&1
}

# 添加订阅
addSubscribeMenu() {
    echoContent skyBlue "\n===================== 添加其他机器订阅 ======================="
    echoContent yellow "1.添加"
    echoContent yellow "2.移除"
    echoContent red "=============================================================="
    read -r -p "请选择:" addSubscribeStatus
    if [[ "${addSubscribeStatus}" == "1" ]]; then
        addOtherSubscribe
    elif [[ "${addSubscribeStatus}" == "2" ]]; then
        if [[ ! -f "/etc/v2ray-agent/subscribe_remote/remoteSubscribeUrl" ]]; then
            echoContent green " ---> 未安装其他订阅"
            exit 0
        fi
        grep -v '^$' "/etc/v2ray-agent/subscribe_remote/remoteSubscribeUrl" | awk '{print NR""":"$0}'
        read -r -p "请选择要删除的订阅编号[仅支持单个删除]:" delSubscribeIndex
        if [[ -z "${delSubscribeIndex}" ]]; then
            echoContent green " ---> 不可以为空"
            exit 0
        fi

        sed -i "$((delSubscribeIndex))d" "/etc/v2ray-agent/subscribe_remote/remoteSubscribeUrl" >/dev/null 2>&1

        echoContent green " ---> 其他机器订阅删除成功"
        subscribe
    fi
}
# 添加其他机器clashMeta订阅
addOtherSubscribe() {
    echoContent yellow "#注意事项:"
    echoContent yellow "请仔细阅读以下文章： https://www.v2ray-agent.com/archives/1681804748677"
    echoContent skyBlue "录入示例：www.v2ray-agent.com:443:vps1\n"
    read -r -p "请输入域名 端口 机器别名:" remoteSubscribeUrl
    if [[ -z "${remoteSubscribeUrl}" ]]; then
        echoContent red " ---> 不可为空"
        addOtherSubscribe
    elif ! echo "${remoteSubscribeUrl}" | grep -q ":"; then
        echoContent red " ---> 规则不合法"
    else

        if [[ -f "/etc/v2ray-agent/subscribe_remote/remoteSubscribeUrl" ]] && grep -q "${remoteSubscribeUrl}" /etc/v2ray-agent/subscribe_remote/remoteSubscribeUrl; then
            echoContent red " ---> 此订阅已添加"
            exit 0
        fi
        echo
        read -r -p "是否是HTTP订阅？[y/n]" httpSubscribeStatus
        if [[ "${httpSubscribeStatus}" == "y" ]]; then
            remoteSubscribeUrl="${remoteSubscribeUrl}:http"
        fi
        echo "${remoteSubscribeUrl}" >>/etc/v2ray-agent/subscribe_remote/remoteSubscribeUrl
        subscribe
    fi
}

# 随机salt
initRandomSalt() {
    local chars="abcdefghijklmnopqrtuxyz"
    local initCustomPath=
    for i in {1..10}; do
        echo "${i}" >/dev/null
        initCustomPath+="${chars:RANDOM%${#chars}:1}"
    done
    echo "${initCustomPath}"
}
# 订阅
subscribe() (
    umask 022
    readInstallProtocolType
    local publishedDir=/etc/v2ray-agent/subscribe
    local subscribePublishPath publishBackup saltPath saltBackup saltTemp status hadPublished=false hadSalt=false publishStarted=false
    subscribePublishPath=$(mktemp -d "${publishedDir}.new.XXXXXX") || return 1
    publishBackup="${subscribePublishPath}.previous"
    saltPath=/etc/v2ray-agent/subscribe_local/subscribeSalt
    saltBackup="${subscribePublishPath}.salt.previous"
    saltTemp="${subscribePublishPath}.salt.new"
    # Roll back failed publication and remove staging files on every exit.
    trap '
    status=$?
    if [[ "${publishStarted}" == true && ${status} -ne 0 ]]; then
        if [[ -d "${publishBackup}" ]]; then
            rm -rf "${publishedDir}"
            mv -f "${publishBackup}" "${publishedDir}" || status=1
        elif [[ "${hadPublished}" == false ]]; then
            rm -rf "${publishedDir}"
        fi
        if [[ -f "${saltBackup}" ]]; then
            mv -f "${saltBackup}" "${saltPath}" || status=1
        elif [[ "${hadSalt}" == false ]]; then
            rm -f "${saltPath}"
        fi
    fi
    rm -rf "${subscribePublishPath}" "${publishBackup}" "${saltBackup}" "${saltTemp}"
    exit "${status}"
    ' EXIT
    mkdir -p "${subscribePublishPath}/"{default,clashMeta} || return 1
    local renewSalt=$1
    if [[ "${coreInstallType}" == "1" ]]; then

        echoContent skyBlue "-------------------------备注---------------------------------"
        echoContent yellow "# 查看订阅会重新生成本地账号的订阅"
        echoContent red "# 需要手动输入md5加密的salt值，如果不了解使用随机即可"
        echoContent yellow "# 不影响已添加的远程订阅的内容\n"

        if [[ -f "/etc/v2ray-agent/subscribe_local/subscribeSalt" && -n $(cat "/etc/v2ray-agent/subscribe_local/subscribeSalt") ]]; then
            if [[ -z "${renewSalt}" ]]; then
                read -r -p "读取到上次安装设置的Salt，是否使用上次生成的Salt ？[y/n]:" historySaltStatus
                if [[ "${historySaltStatus}" == "y" ]]; then
                    subscribeSalt=$(cat /etc/v2ray-agent/subscribe_local/subscribeSalt)
                else
                    read -r -p "请输入salt值, [回车]使用随机:" subscribeSalt
                fi
            else
                subscribeSalt=$(cat /etc/v2ray-agent/subscribe_local/subscribeSalt)
            fi
        else
            read -r -p "请输入salt值, [回车]使用随机:" subscribeSalt
        fi

        if [[ -z "${subscribeSalt}" ]]; then
            subscribeSalt=$(initRandomSalt)
        fi
        echoContent yellow "\n ---> Salt: ${subscribeSalt}"

        rm -rf /etc/v2ray-agent/subscribe_local/default/*
        rm -rf /etc/v2ray-agent/subscribe_local/clashMeta/*
        showAccounts >/dev/null || return 1
        if [[ -n $(ls /etc/v2ray-agent/subscribe_local/default/) ]]; then
            if [[ -f "/etc/v2ray-agent/subscribe_remote/remoteSubscribeUrl" && -n $(cat "/etc/v2ray-agent/subscribe_remote/remoteSubscribeUrl") ]]; then
                if [[ -z "${renewSalt}" ]]; then
                    read -r -p "读取到其他订阅，是否更新？[y/n]" updateOtherSubscribeStatus
                else
                    updateOtherSubscribeStatus=y
                fi
            fi
            local email
            while IFS= read -r email; do
                email=$(echo "${email}" | awk -F "[d][e][f][a][u][l][t][/]" '{print $2}')

                local emailMd5=
                emailMd5=$(echo -n "${email}${subscribeSalt}"$'\n' | md5sum | awk '{print $1}')

                cat "/etc/v2ray-agent/subscribe_local/default/${email}" >>"${subscribePublishPath}/default/${emailMd5}" || return 1
                if [[ "${updateOtherSubscribeStatus}" == "y" ]]; then
                    updateRemoteSubscribe "${emailMd5}" "${email}" "${subscribePublishPath}"
                fi
                local base64Result
                base64Result=$(base64 -w 0 "${subscribePublishPath}/default/${emailMd5}") || return 1
                echo "${base64Result}" >"${subscribePublishPath}/default/${emailMd5}" || return 1
                echoContent yellow "--------------------------------------------------------------"
                if [[ -f "/etc/v2ray-agent/subscribe_local/clashMeta/${email}" ]]; then
                    cat "/etc/v2ray-agent/subscribe_local/clashMeta/${email}" >>"${subscribePublishPath}/clashMeta/${emailMd5}" || return 1

                    sed -i '1i\proxies:' "${subscribePublishPath}/clashMeta/${emailMd5}" || return 1

                fi

            done < <(find /etc/v2ray-agent/subscribe_local/default/ -type f)
        fi
        if [[ -f "${saltPath}" ]]; then
            cp -p "${saltPath}" "${saltBackup}" || return 1
            hadSalt=true
        fi
        printf '%s\n' "${subscribeSalt}" >"${saltTemp}" || return 1
        if [[ -d "${publishedDir}" ]]; then
            hadPublished=true
        fi
        chmod 755 "${subscribePublishPath}" || return 1
        publishStarted=true
        if [[ "${hadPublished}" == true ]]; then
            mv -f "${publishedDir}" "${publishBackup}" || return 1
        fi
        mv -f "${subscribePublishPath}" "${publishedDir}" || return 1
        mv -f "${saltTemp}" "${saltPath}" || return 1
        publishStarted=false
    else
        echoContent red " ---> 当前未安装可生成订阅的 Xray 服务"
    fi
)

# 更新远程订阅
updateRemoteSubscribe() {

    local emailMD5=$1
    local email=$2
    local publishPath=${3:-/etc/v2ray-agent/subscribe}
    while read -r line; do
        local subscribeType=
        subscribeType="https"

        local serverAlias=
        serverAlias=$(echo "${line}" | awk -F "[:]" '{print $3}')

        local remoteUrl=
        remoteUrl=$(echo "${line}" | awk -F "[:]" '{print $1":"$2}')

        local subscribeTypeRemote=
        subscribeTypeRemote=$(echo "${line}" | awk -F "[:]" '{print $4}')

        if [[ -n "${subscribeTypeRemote}" ]]; then
            subscribeType="${subscribeTypeRemote}"
        fi
        local clashMetaProxies=

        clashMetaProxies=$(curl -s "${subscribeType}://${remoteUrl}/s/clashMeta/${emailMD5}" | sed '/proxies:/d' | sed "s/\"${email}/\"${email}_${serverAlias}/g")

        if ! echo "${clashMetaProxies}" | grep -q "nginx" && [[ -n "${clashMetaProxies}" ]]; then
            echo "${clashMetaProxies}" >>"${publishPath}/clashMeta/${emailMD5}"
            echoContent green " ---> clashMeta订阅 ${remoteUrl}:${email} 更新成功"
        else
            echoContent red " ---> clashMeta订阅 ${remoteUrl}:${email}不存在"
        fi

        local default=
        default=$(curl -s "${subscribeType}://${remoteUrl}/s/default/${emailMD5}")

        if ! echo "${default}" | grep -q "nginx" && [[ -n "${default}" ]]; then
            default=$(echo "${default}" | base64 -d | sed "s/#${email}/#${email}_${serverAlias}/g")
            echo "${default}" >>"${publishPath}/default/${emailMD5}"

            echoContent green " ---> 通用订阅 ${remoteUrl}:${email} 更新成功"
        else
            echoContent red " ---> 通用订阅 ${remoteUrl}:${email} 不存在"
        fi

    done < <(grep -v '^$' <"/etc/v2ray-agent/subscribe_remote/remoteSubscribeUrl")
}
initXrayXHTTPTLSPort() {
    xHTTPTLSPort=
    if [[ -n "${xrayVLESSXHTTPTLSPort}" && -z "${lastInstallationConfig}" ]]; then
        read -r -p "读取到上次安装记录，是否使用上次安装时的端口？[y/n]:" historyXHTTPTLSPortStatus
        echo
        [[ "${historyXHTTPTLSPortStatus}" == "y" ]] && xHTTPTLSPort=${xrayVLESSXHTTPTLSPort}
    elif [[ -n "${xrayVLESSXHTTPTLSPort}" && -n "${lastInstallationConfig}" ]]; then
        xHTTPTLSPort=${xrayVLESSXHTTPTLSPort}
    fi
    if [[ -z "${xHTTPTLSPort}" ]]; then
        read -r -p "请输入XHTTP TLS公网端口[回车随机10000-30000]:" xHTTPTLSPort
    fi
    if [[ -z "${xHTTPTLSPort}" ]]; then
        local attempts=0
        local randomPortFound=false
        while ((attempts < 20)); do
            xHTTPTLSPort=$((RANDOM % 20001 + 10000))
            if isNumber "${xHTTPTLSPort}" && checkPort "${xHTTPTLSPort}" transaction; then
                randomPortFound=true
                break
            fi
            attempts=$((attempts + 1))
            xHTTPTLSPort=
        done
        if [[ "${randomPortFound}" != true ]]; then
            echoContent red " ---> 随机XHTTP TLS端口均已被占用"
            return 1
        fi
    fi
    if ! isNumber "${xHTTPTLSPort}"; then
        echoContent red " ---> XHTTP TLS端口输入错误"
        return 1
    fi
    xHTTPTLSPort=$((10#${xHTTPTLSPort}))
    checkPort "${xHTTPTLSPort}" transaction || return 1
    if echo "${selectCustomInstallType}" | grep -q ",2,"; then allowPort "${xHTTPTLSPort}"; fi
    if echo "${selectCustomInstallType}" | grep -q ",1,"; then allowPort "${xHTTPTLSPort}" udp; fi
    echoContent yellow "\n ---> XHTTP端口: ${xHTTPTLSPort}"
}
menu() {
    cd "$HOME" || exit
    echoContent red "\n=============================================================="
    echoContent green "作者：qihang518887"
    echoContent green "Github：https://github.com/qihang518887/xhttp-agent"
    echoContent green "描述：Xray VLESS + XHTTP + TLS\c"
    showInstallStatus
    checkWgetShowProgress
    echoContent red "=============================================================="
    echoContent yellow "2.任意组合安装"
    echoContent yellow "7.用户管理"
    echoContent yellow "9.证书管理"
    echoContent yellow "16.core管理"
    echoContent yellow "17.更新脚本"
    echoContent yellow "20.卸载脚本"
    echoContent red "=============================================================="
    mkdirTools
    aliasInstall
    read -r -p "请选择:" selectInstallType
    case ${selectInstallType} in
    2)
        customXrayInstall
        ;;
    7)
        manageAccount 1
        ;;
    9)
        renewalTLS 1
        ;;
    16)
        xrayVersionManageMenu 1
        ;;
    17)
        ;;
    20)
        unInstall 1
        ;;
    esac
}

cronFunction
menu
