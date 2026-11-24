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
    currentUUID=
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
    xhttpPreferredCNAME=
    nodeTag=
    xhttpH3Up=50
    inboundConfig=/etc/v2ray-agent/xray/conf/08_VLESS_XHTTP_inbounds.json
}

isNumber() {
    [[ "${1:-}" =~ ^[0-9]+$ ]]
}

buildXrayXHTTPConfig() {
    local port=$1 domainName=$2 customPath=$3 uuidValue=$4 installTypes=$5 brutalUp=$6
    jq -n --arg domain "${domainName}" --arg path "/${customPath#\/}xHTTP" \
        --arg brutalUp "${brutalUp}" --arg installTypes "${installTypes}" \
        --arg id "${uuidValue}" --argjson publicPort "${port}" '
      def inbound($tag; $alpn; $h3):
        {listen:"::",port:$publicPort,protocol:"vless",tag:$tag,
         settings:{clients:[{id:$id}],decryption:"none"},
         streamSettings:({network:"xhttp",security:"tls",
           tlsSettings:({serverName:$domain,minVersion:"1.2",rejectUnknownSni:true,
             certificates:[{certificateFile:("/etc/v2ray-agent/tls/"+$domain+".crt"),keyFile:("/etc/v2ray-agent/tls/"+$domain+".key")}]}
             + (if $alpn == "h3" then {alpn:["h3"]} else {} end)),
           xhttpSettings:{host:$domain,path:$path,mode:"auto"}}
           + (if $h3 then {finalmask:{quicParams:({maxIncomingStreams:4096} + (if $brutalUp == "0" then {} else {congestion:"force-brutal",brutalUp:($brutalUp + " mbps")} end))}} else {} end))};
      {inbounds:[
        (if ($installTypes | contains(",2,")) then inbound("VLESSXHTTPTLS"; "h2"; false) else empty end),
        (if ($installTypes | contains(",1,")) then inbound("VLESSXHTTPH3"; "h3"; true) else empty end)
      ]}'
}

buildVLESSXHTTPTLSURI() {
    local address=$1 port=$2 uuidValue=$3 domainName=$4 pathValue=$5 modeValue=$6 name=$7 alpn=${8:-h2}
    printf 'vless://%s@%s:%s?encryption=none&security=tls&type=xhttp&sni=%s&host=%s&fp=chrome&alpn=%s&path=%%2F%s&mode=%s#%s\n' \
        "${uuidValue}" "${address}" "${port}" "${domainName}" "${domainName}" "${alpn}" "${pathValue#\/}" "${modeValue}" "${name}"
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
            if [[ -d "/etc/v2ray-agent/xray/conf" && -f "${inboundConfig}" ]]; then
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

    [[ -f "${inboundConfig}" ]] || return 0
    currentInstallProtocolType=$(jq -r '[.inbounds[] | (.streamSettings.tlsSettings.alpn // ["h2"])[0]] | map(if . == "h3" then ",1," else ",2," end) | join("")' "${inboundConfig}")
    xrayVLESSXHTTPTLSPort=$(jq -r '.inbounds[0].port' "${inboundConfig}")
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
            [[ -s "/etc/v2ray-agent/nodeTag" ]] && nodeTag=$(head -n 1 "/etc/v2ray-agent/nodeTag" | tr -d '\r\n')
            [[ -s "/etc/v2ray-agent/xhttp-direct-address" ]] && xhttpDirectAddress=$(head -n 1 "/etc/v2ray-agent/xhttp-direct-address" | tr -d '\r\n')
            [[ -s "/etc/v2ray-agent/cdn" ]] && xhttpPreferredCNAME=$(head -n 1 "/etc/v2ray-agent/cdn" | tr -d '\r\n')
            local previousH3Up
            previousH3Up=$(jq -r '.inbounds[] | select(.streamSettings.tlsSettings.alpn[0] == "h3") | .streamSettings.finalmask.quicParams.brutalUp // empty' "${inboundConfig}")
            if [[ -n "${previousH3Up}" ]]; then
                xhttpH3Up=${previousH3Up% mbps}
            else
                xhttpH3Up=0
            fi
        fi
    fi
}
# 检查文件目录以及path路径
readConfigHostPathUUID() {
    currentPath=
    currentUUID=
    currentHost=

    if [[ -f "${inboundConfig}" ]]; then
        IFS=$'\t' read -r currentUUID currentHost xrayVLESSXHTTPTLSPort currentPath < <(
            jq -r '[.inbounds[0].settings.clients[0].id // "", (.inbounds[0].streamSettings.tlsSettings.serverName // .inbounds[0].streamSettings.xhttpSettings.host // ""), .inbounds[0].port, .inbounds[0].streamSettings.xhttpSettings.path] | @tsv' "${inboundConfig}"
        )
        currentPath=$(echo "${currentPath}" | sed -E 's#^/##; s#xHTTP$##')
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
        if [[ ${currentInstallProtocolType} == *,2,* ]]; then
            echoContent yellow "VLESS+XHTTP+TLS \c"
        fi
        if [[ ${currentInstallProtocolType} == *,1,* ]]; then
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
readConfigHostPathUUID

# -------------------------------------------------------------

# 初始化安装目录
mkdirTools() {
    mkdir -p /etc/v2ray-agent/tls
    mkdir -p /etc/v2ray-agent/subscribe_local/default
    mkdir -p /etc/v2ray-agent/subscribe_local/clashMeta
}
# 安装工具包
installTools() {
    echoContent skyBlue "\n进度 $1/${totalProgress} : 安装工具"
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

installSubscriptionHTTPService() {
    local opensslPath
    opensslPath=$(command -v openssl) || return 1
    allowPort 8443
    if [[ "${release}" == "alpine" ]]; then
        cat <<EOF >/etc/init.d/xhttp-subscribe
#!/sbin/openrc-run

description="Mihomo YAML HTTPS subscription"
command="${opensslPath}"
command_args="s_server -accept 8443 -cert /etc/v2ray-agent/tls/${currentHost}.crt -key /etc/v2ray-agent/tls/${currentHost}.key -WWW -quiet"
command_background=true
directory="/etc/v2ray-agent/subscribe/http"
pidfile="/run/xhttp-subscribe.pid"
EOF
        chmod 755 /etc/init.d/xhttp-subscribe || return 1
        bootStartup xhttp-subscribe || return 1
    else
        cat <<EOF >/etc/systemd/system/xhttp-subscribe.service
[Unit]
Description=Mihomo YAML HTTPS subscription
After=network.target

[Service]
Type=simple
WorkingDirectory=/etc/v2ray-agent/subscribe/http
ExecStart=${opensslPath} s_server -accept 8443 -cert /etc/v2ray-agent/tls/${currentHost}.crt -key /etc/v2ray-agent/tls/${currentHost}.key -WWW -quiet
Restart=on-failure
RestartSec=2
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
        bootStartup xhttp-subscribe.service || return 1
    fi
}

handleSubscriptionHTTPS() {
    local action=$1
    if [[ "${release}" == "alpine" ]]; then
        if [[ "${action}" == restart ]] && ! rc-service xhttp-subscribe status >/dev/null 2>&1; then
            action=start
        fi
        rc-service xhttp-subscribe "${action}"
    else
        systemctl "${action}" xhttp-subscribe.service
    fi
}

# 初始化TLS证书域名
initTLSDomain() {
    echoContent skyBlue "\n进度 $1/${totalProgress} : 配置 TLS 证书域名"
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
    if [[ ${selectCustomInstallType} == *,1,* ]]; then
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
    echoContent skyBlue "\n进度 $1/${totalProgress} : 申请TLS证书\n"
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
        acmeInstallSSL
        readAcmeTLS

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
        initCustomPath+="${chars:RANDOM%${#chars}:1}"
    done
    customPath=${initCustomPath}
}

# 自定义/随机路径
randomPathFunction() {
    if [[ -n $1 ]]; then
        echoContent skyBlue "\n进度 $1/${totalProgress} : 生成随机路径"
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
        [[ -n "${customPath}" ]] || initRandomPath
        currentPath=${customPath}
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
certificateDateEpoch() {
    if [[ "${release}" == "alpine" ]]; then
        TZ=UTC LC_ALL=C date -D '%b %e %T %Y' -d "${1% GMT}" +%s
    else
        date +%s -d "$1"
    fi
}
# 更新证书
renewalTLS() {
    if [[ -n $1 ]]; then
        echoContent skyBlue "\n进度 $1/1 : 更新证书"
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
    if ! expiryTime=$(certificateDateEpoch "${notAfter}" 2>/dev/null); then
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
    echoContent skyBlue " ---> 证书真实到期时间:${notAfter}"
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
            if newExpiry=$(certificateDateEpoch "${newNotAfter}" 2>/dev/null) && ((newExpiry > currentTime && newExpiry > expiryTime)); then
                renewalSuccess=true
                echoContent green " ---> 证书续期成功，新到期时间:${newNotAfter}"
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
    if [[ -e /etc/systemd/system/xhttp-subscribe.service || -e /etc/init.d/xhttp-subscribe ]]; then
        handleSubscriptionHTTPS restart || echoContent red " ---> HTTPS订阅服务重启失败，将沿用旧证书"
    fi
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

    echoContent skyBlue "\n进度 $1/${totalProgress} : 安装Xray"

    if [[ ! -f "/etc/v2ray-agent/xray/xray" || "${3:-}" == force ]]; then
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
    echoContent skyBlue "\n进度 $1/${totalProgress} : Xray版本管理"
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

# Xray开机自启
installXrayService() {
    echoContent skyBlue "\n进度 $1/${totalProgress} : 配置Xray开机自启"
    execStart='/etc/v2ray-agent/xray/xray run -confdir /etc/v2ray-agent/xray/conf'
    if [[ -n $(find /bin /usr/bin -name "systemctl") ]]; then
        rm -rf /etc/systemd/system/xray.service
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
        cat <<EOF >/etc/init.d/xray
#!/sbin/openrc-run

description="xray service"
command="/etc/v2ray-agent/xray/xray"
command_args="run -confdir /etc/v2ray-agent/xray/conf"
command_background=true
pidfile="/var/run/xray.pid"
EOF
        chmod +x /etc/init.d/xray
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
    if [[ -n "${currentUUID}" && -z "${lastInstallationConfig}" ]]; then
        read -r -p "读取到上次用户配置，是否使用上次安装的配置 ？[y/n]:" historyUUIDStatus
        if [[ "${historyUUIDStatus}" == "y" ]]; then
            uuid=${currentUUID}
            echoContent green "\n ---> 使用成功"
        fi
    elif [[ -n "${currentUUID}" && -n "${lastInstallationConfig}" ]]; then
        uuid=${currentUUID}
    fi

    if [[ -z "${uuid}" ]]; then
        read -r -p "请输入合法的UUID，[回车]随机UUID:" uuid
        echo
        [[ -n "${uuid}" ]] || uuid=$(/etc/v2ray-agent/xray/xray uuid)
        echoContent green "\n ${uuid}"
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
    if [[ ${selectCustomInstallType} == *,1,* ]] &&
        { [[ -z "${lastInstallationConfig}" ]] || ! jq -e '[.inbounds[] | select(.streamSettings.tlsSettings.alpn[0] == "h3")] | any' "${inboundConfig}" >/dev/null; }; then
        read -r -p "请输入期望的本地下载速度（Mbps，仅 H3 直连生效）[回车默认50，填0不设置]:" xhttpH3Up
        xhttpH3Up=${xhttpH3Up:-50}
        isNumber "${xhttpH3Up}" || {
            echoContent red " ---> 请输入整数Mbps"
            exit 0
        }
    fi
    buildXrayXHTTPConfig "${xHTTPTLSPort}" "${domain}" "${customPath}" "${uuid}" "${selectCustomInstallType}" "${xhttpH3Up}" >"${inboundConfig}" || return 1
}

# 通用
defaultBase64Code() {
    local port=$1
    local nodeName=$2
    local id=$3
    local add=$4
    local path=$5
    local alpn=${6:-h2}
    local xhttpMode=packet-up
    [[ "${alpn}" == "h3" ]] && xhttpMode=auto
    local xhttpTLSURI
    xhttpTLSURI=$(buildVLESSXHTTPTLSURI "${add}" "${port}" "${id}" "${currentHost}" "${path}" "${xhttpMode}" "${nodeName}" "${alpn}") || return 1
    echoContent yellow " ---> 通用格式(VLESS+XHTTP+TLS)"
    echoContent green "    ${xhttpTLSURI}"
    printf '%s\n' "${xhttpTLSURI}" >>"/etc/v2ray-agent/subscribe_local/default/${nodeName}" || return 1
    buildMihomoXHTTPTLSNode "${add}" "${port}" "${id}" "${currentHost}" "${path}" "${xhttpMode}" "${nodeName}" "${alpn}" >>"/etc/v2ray-agent/subscribe_local/clashMeta/${nodeName}" || return 1
}

# 生成账号
showAccounts() {
    local uuidValue nodeTag nodeName
    readInstallType
    readInstallProtocolType
    readConfigHostPathUUID

    echo
    rm -rf /etc/v2ray-agent/subscribe_local/default/* /etc/v2ray-agent/subscribe_local/clashMeta/*
    [[ -n "${currentInstallProtocolType}" ]] || return 1
    uuidValue=$(jq -r '.inbounds[0].settings.clients[0].id' "${inboundConfig}") || return 1
    [[ -s "/etc/v2ray-agent/cdn" ]] && xhttpPreferredCNAME=$(head -n 1 "/etc/v2ray-agent/cdn" | tr -d '\r\n')
    [[ -s "/etc/v2ray-agent/xhttp-direct-address" ]] && xhttpDirectAddress=$(head -n 1 "/etc/v2ray-agent/xhttp-direct-address" | tr -d '\r\n')
    [[ -n "${xhttpDirectAddress}" ]] || xhttpDirectAddress=$(getPublicIP)
    echoContent skyBlue "\n================================ VLESS XHTTP TLS ================================\n"
    # 节点名用本机标识，整合多台机器时一眼看得出来自哪台
    nodeTag=$(head -n 1 "/etc/v2ray-agent/nodeTag" | tr -d '\r\n')
    nodeTag=${nodeTag:-${uuidValue%%-*}}
    nodeName=${nodeTag}
    if [[ ${currentInstallProtocolType} == *,1,* ]]; then
        [[ ${currentInstallProtocolType} == *,2,* ]] && nodeName="${nodeTag}_h3"
        echoContent skyBlue "\n ---> 账号:${nodeName}"
        defaultBase64Code "${xrayVLESSXHTTPTLSPort}" "${nodeName}" "${uuidValue}" "${xhttpDirectAddress}" "${currentPath}xHTTP" h3 || return 1
    fi
    if [[ ${currentInstallProtocolType} == *,2,* ]]; then
        nodeName="${nodeTag}_cdn1"
        echoContent skyBlue "\n ---> 账号:${nodeName}"
        defaultBase64Code "${xrayVLESSXHTTPTLSPort}" "${nodeName}" "${uuidValue}" "${xhttpPreferredCNAME}" "${currentPath}xHTTP" h2 || return 1
        nodeName="${nodeName}_h3"
        echoContent skyBlue "\n ---> 账号:${nodeName}"
        defaultBase64Code "${xrayVLESSXHTTPTLSPort}" "${nodeName}" "${uuidValue}" "${xhttpPreferredCNAME}" "${currentPath}xHTTP" h3 || return 1
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
    removeCoreService xhttp-subscribe || {
        echoContent red " ---> HTTPS订阅服务清理失败，已停止卸载"
        return 1
    }
    removeCoreService xray || {
        echoContent red " ---> Xray service清理失败，已停止卸载"
        return 1
    }
    rm -rf /etc/v2ray-agent
    rm -rf /usr/bin/xasma /usr/sbin/xasma
    echoContent green " ---> 卸载快捷方式完成"
    echoContent green " ---> 卸载v2ray-agent脚本完成"
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
        else
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
        mv "$HOME/install.sh" /etc/v2ray-agent/install.sh || return 1
    fi
    [[ -f "/etc/v2ray-agent/install.sh" ]] || return 0
    chmod 700 /etc/v2ray-agent/install.sh || return 1

    local xasmaPath=
    if [[ -d "/usr/bin/" ]]; then
        xasmaPath=/usr/bin/xasma
    elif [[ -d "/usr/sbin" ]]; then
        xasmaPath=/usr/sbin/xasma
    fi
    if [[ -n "${xasmaPath}" && ! -e "${xasmaPath}" && ! -L "${xasmaPath}" ]]; then
        ln -s /etc/v2ray-agent/install.sh "${xasmaPath}" || return 1
        echoContent green "快捷方式创建成功，可执行[xasma]重新打开脚本"
    fi
}

reloadCore() {
    readInstallType

    if [[ "${coreInstallType}" == "1" ]]; then
        handleXray stop "${1:-}" || return 1
        handleXray start "${1:-}" || return 1
    fi
}

# 本机标识与节点地址
setupXHTTPSubscriptionAddresses() {
    local addressInput
    echoContent skyBlue "\n进度 9/${totalProgress} : 本机标识"
    if [[ -z "${lastInstallationConfig}" || -z "${nodeTag}" ]]; then
        read -r -p "请输入本机标识（节点名前缀）[回车使用 ${nodeTag:-${domain}}]:" addressInput
        nodeTag=${addressInput:-${nodeTag:-${domain}}}
    fi
    printf '%s\n' "${nodeTag:-${domain}}" >/etc/v2ray-agent/nodeTag || return 1
    echoContent green "\n ---> 本机标识:${nodeTag}"
    if [[ ${selectCustomInstallType} == *,1,* ]]; then
        echoContent skyBlue "\n进度 10/${totalProgress} : H3直连地址"
        if [[ -z "${lastInstallationConfig}" || -z "${xhttpDirectAddress}" ]]; then
            read -r -p "请输入H3直连IP/域名[回车使用 ${xhttpDirectAddress:-公网IP}]:" addressInput
            xhttpDirectAddress=${addressInput:-${xhttpDirectAddress}}
        fi
        [[ -n "${xhttpDirectAddress}" ]] || xhttpDirectAddress=$(getPublicIP)
        printf '%s\n' "${xhttpDirectAddress}" >/etc/v2ray-agent/xhttp-direct-address || return 1
        echoContent green "\n ---> 直连地址:${xhttpDirectAddress}"
    fi
    if [[ ${selectCustomInstallType} == *,2,* ]]; then
        echoContent skyBlue "\n进度 11/${totalProgress} : CDN优选CNAME"
        if [[ -z "${lastInstallationConfig}" || -z "${xhttpPreferredCNAME}" ]]; then
            read -r -p "请输入优选CNAME[回车使用 ${xhttpPreferredCNAME:-证书域名 ${domain}}]:" addressInput
            xhttpPreferredCNAME=${addressInput:-${xhttpPreferredCNAME:-${domain}}}
        fi
        printf '%s\n' "${xhttpPreferredCNAME:-${domain}}" >/etc/v2ray-agent/cdn || return 1
        echoContent green "\n ---> 优选CNAME:${xhttpPreferredCNAME}"
    fi
}

# Xray-core个性化安装
customXrayInstall() {
    echoContent skyBlue "\n========================个性化安装============================"
    echoContent yellow "1.H3直连"
    echoContent yellow "2.CDN(H2+H3)"
    read -r -p "请选择（可多选，英文逗号分隔）:" selectCustomInstallType
    echoContent skyBlue "--------------------------------------------------------------"
    if [[ ${selectCustomInstallType} == *，* ]]; then
        echoContent red " ---> 请使用英文逗号分隔"
        exit 0
    fi
    if [[ ! "${selectCustomInstallType}" =~ ^(1|2)(,(1|2))?$ ]]; then
        echoContent red " ---> 仅支持选择1、2或1,2"
        exit 0
    fi
    selectCustomInstallType=",${selectCustomInstallType},"
    readLastInstallationConfig
    unInstallSubscribe
    totalProgress=11
    installTools 1 || return 1
    initTLSDomain 2 || return 1
    installTLS 3 || return 1
    randomPathFunction 4

    # 安装Xray
    handleXray stop transaction || return 1
    installXray 5 false || return 1
    installXrayService 6 || return 1
    initXrayConfig 7 || return 1
    handleXray start transaction || return 1
    installCronTLS 8
    setupXHTTPSubscriptionAddresses || return 1
    # 生成账号
    showAccounts
}

# 定时任务检查
cronFunction() {
    if [[ "${cronName}" == "RenewTLS" ]]; then
        renewalTLS
        exit 0
    fi
}
# 订阅文件名（由UUID决定，链接本身即凭证）
subscriptionHash() {
    jq -r '.inbounds[0].settings.clients[0].id' "${inboundConfig}" | md5sum | awk '{print $1}'
}

# 查看订阅：每次都从配置重建
showSubscription() {
    if [[ -z "${configPath}" ]]; then
        echoContent red " ---> 未安装"
        exit 0
    fi
    subscribe || return 1
    local subMd5
    subMd5=$(subscriptionHash) || return 1
    echoContent skyBlue "=============================================================="
    echoContent skyBlue "\nMihomo HTTPS 订阅"
    echoContent gray "本地文件：/etc/v2ray-agent/subscribe/http/s/clashMeta/${subMd5}"
    echoContent gray "订阅链接（请妥善保管，链接本身即访问凭证）："
    echoContent brightGreen "https://${currentHost}:8443/s/clashMeta/${subMd5}"
}

unInstallSubscribe() {
    removeCoreService xhttp-subscribe || return 1
    rm -rf /etc/v2ray-agent/subscribe
}

# 整合其他机器的订阅
addSubscribeMenu() {
    echoContent skyBlue "\n===================== 整合其他机器订阅 ======================="
    if [[ -s "/etc/v2ray-agent/subscribe_remote/remoteSubscribeUrl" ]]; then
        grep -v '^$' "/etc/v2ray-agent/subscribe_remote/remoteSubscribeUrl" | awk '{print NR""":"$0}'
    else
        echoContent green " ---> 还没有整合其他订阅"
    fi
    echoContent yellow "1.添加"
    echoContent yellow "2.移除"
    echoContent red "=============================================================="
    read -r -p "请选择:" addSubscribeStatus
    if [[ "${addSubscribeStatus}" == "1" ]]; then
        addOtherSubscribe
    elif [[ "${addSubscribeStatus}" == "2" ]]; then
        [[ -s "/etc/v2ray-agent/subscribe_remote/remoteSubscribeUrl" ]] || exit 0
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
# 添加其他机器订阅
addOtherSubscribe() {
    echoContent skyBlue "示例：vps2 https://1.2.3.4:8443/s/clashMeta/abc123\n"
    read -r -p "请输入 [别名] [空格] [订阅地址]:" serverAlias remoteUrl
    if [[ -z "${remoteUrl}" ]]; then
        echoContent red " ---> 需要别名和地址两项"
        addOtherSubscribe
    else
        mkdir -p /etc/v2ray-agent/subscribe_remote
        if [[ -f "/etc/v2ray-agent/subscribe_remote/remoteSubscribeUrl" ]] && grep -qF "${remoteUrl}" /etc/v2ray-agent/subscribe_remote/remoteSubscribeUrl; then
            echoContent red " ---> 此订阅已添加"
            exit 0
        fi
        echo "${serverAlias} ${remoteUrl}" >>/etc/v2ray-agent/subscribe_remote/remoteSubscribeUrl
        subscribe
    fi
}

# 订阅
subscribe() (
    umask 022
    local publishedDir=/etc/v2ray-agent/subscribe
    local subscribePublishPath publishBackup status subMd5 vlessFile clashFile
    subscribePublishPath=$(mktemp -d "${publishedDir}.new.XXXXXX") || return 1
    publishBackup="${subscribePublishPath}.previous"
    # 只有交换未完成（备份还在）且退出码非 0 才回滚，否则会把本次成功的发布覆盖回旧版。
    trap '
    status=$?
    if [[ ${status} -ne 0 && -d "${publishBackup}" ]]; then
        rm -rf "${publishedDir}"
        mv -f "${publishBackup}" "${publishedDir}" || status=1
    fi
    rm -rf "${subscribePublishPath}" "${publishBackup}"
    exit "${status}"
    ' EXIT
    mkdir -p "${subscribePublishPath}/"{default,http/s/clashMeta} || return 1
    if [[ "${coreInstallType}" != "1" ]]; then
        echoContent red " ---> 当前未安装可生成订阅的 Xray 服务"
        return 1
    fi
    showAccounts >/dev/null || return 1
    subMd5=$(subscriptionHash) || return 1
    vlessFile="${subscribePublishPath}/default/${subMd5}"
    clashFile="${subscribePublishPath}/http/s/clashMeta/${subMd5}"
    # 每次查看订阅都重建远端缓存：跳过会让整合进来的节点从订阅里消失
    if [[ -s "/etc/v2ray-agent/subscribe_remote/remoteSubscribeUrl" ]]; then
        updateRemoteSubscribe "${subscribePublishPath}" || return 1
    fi
    cat /etc/v2ray-agent/subscribe_local/default/* >"${vlessFile}" || return 1
    if [[ -s "${subscribePublishPath}/.remote/default" ]]; then
        cat "${subscribePublishPath}/.remote/default" >>"${vlessFile}" || return 1
    fi
    base64 -w 0 "${vlessFile}" >"${vlessFile}.b64" || return 1
    mv -f "${vlessFile}.b64" "${vlessFile}" || return 1
    cat /etc/v2ray-agent/subscribe_local/clashMeta/* >"${clashFile}" || return 1
    sed -i '1i\proxies:' "${clashFile}" || return 1
    if [[ -s "${subscribePublishPath}/.remote/clashMeta" ]]; then
        cat "${subscribePublishPath}/.remote/clashMeta" >>"${clashFile}" || return 1
    fi
    cat >>"${clashFile}" <<'EOF'
mode: rule
rule-providers:
  ai-all:
    type: http
    behavior: classical
    url: https://cdn.jsdelivr.net/gh/VPSDance/ai-proxy-rules@main/rules/clash/all.yaml
    path: ./ruleset/ai-all.yaml
    interval: 86400
proxy-groups:
  - name: 非国内
    type: select
    include-all-proxies: true
  - name: AI
    type: select
    include-all-proxies: true
rules:
  - RULE-SET,ai-all,AI
  - GEOSITE,cn,DIRECT
  - GEOIP,CN,DIRECT,no-resolve
  - MATCH,非国内
EOF
    rm -rf "${subscribePublishPath}/.remote" || return 1
    chmod 755 "${subscribePublishPath}" || return 1
    chmod 700 "${subscribePublishPath}/default" \
        /etc/v2ray-agent/subscribe_local /etc/v2ray-agent/subscribe_local/default /etc/v2ray-agent/subscribe_local/clashMeta || return 1
    if [[ -d "${publishedDir}" ]]; then
        mv -f "${publishedDir}" "${publishBackup}" || return 1
    fi
    mv -f "${subscribePublishPath}" "${publishedDir}" || return 1
    installSubscriptionHTTPService || echoContent red " ---> HTTPS订阅服务安装失败，订阅文件已生成"
    handleSubscriptionHTTPS restart || echoContent red " ---> HTTPS订阅服务未启动，请检查8443端口"
)

# 更新远程订阅
updateRemoteSubscribe() {
    local publishPath=$1
    local remoteCache="${publishPath}/.remote"
    mkdir -p "${remoteCache}" || return 1
    while IFS= read -r line; do
        local serverAlias remoteUrl remoteContent clashMetaProxies default
        read -r serverAlias remoteUrl <<<"${line}"
        remoteContent=$(curl -s "${remoteUrl}")

        if [[ "${remoteUrl}" == */s/clashMeta/* ]]; then
            clashMetaProxies=$(printf '%s\n' "${remoteContent}" | awk -v suffix="_${serverAlias}" '
                /^proxies:[[:space:]]*$/ { inProxies=1; next }
                inProxies && /^[^[:space:]]/ { exit }
                inProxies && /^[[:space:]]*- name:/ {
                    if ($0 ~ /"$/) sub(/"$/, suffix "\"")
                    else sub(/[[:space:]]*$/, suffix)
                }
                inProxies { print }
            ')
            if [[ -n "${clashMetaProxies}" ]]; then
                printf '%s\n' "${clashMetaProxies}" >>"${remoteCache}/clashMeta" || return 1
                echoContent green " ---> clashMeta订阅 ${remoteUrl} 更新成功"
            else
                echoContent red " ---> clashMeta订阅 ${remoteUrl} 不存在"
            fi
        elif [[ "${remoteUrl}" == */s/default/* ]]; then
            default=$(printf '%s\n' "${remoteContent}" | base64 -d 2>/dev/null)
            if printf '%s\n' "${default}" | grep -qF "vless://"; then
                default=$(printf '%s\n' "${default}" | sed "s/#\\([^#]*\\)$/#\\1_${serverAlias}/")
                printf '%s\n' "${default}" >>"${remoteCache}/default" || return 1
                echoContent green " ---> VLESS订阅 ${remoteUrl} 更新成功"
            else
                echoContent red " ---> VLESS订阅 ${remoteUrl} 不存在"
            fi
        else
            echoContent red " ---> 订阅 ${remoteUrl} 不存在"
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
            if checkPort "${xHTTPTLSPort}" transaction; then
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
    if [[ ${selectCustomInstallType} == *,2,* ]]; then allowPort "${xHTTPTLSPort}"; fi
    if [[ ${selectCustomInstallType} == *,1,* ]]; then allowPort "${xHTTPTLSPort}" udp; fi
    echoContent yellow "\n ---> XHTTP端口: ${xHTTPTLSPort}"
}
# 更新脚本
updateXHTTPAgent() {
    echoContent skyBlue "\n进度 $1/${totalProgress} : 更新xhttp-agent脚本"
    local scriptTemp
    scriptTemp=$(mktemp /etc/v2ray-agent/.install.XXXXXX) || return 1
    if ! wget -q -O "${scriptTemp}" "https://raw.githubusercontent.com/qihang518887/xhttp-agent/main/install.sh" ||
        [[ ! -s "${scriptTemp}" ]] || ! bash -n "${scriptTemp}"; then
        rm -f "${scriptTemp}"
        echoContent red " ---> 脚本下载或校验失败，保留当前版本"
        return 1
    fi
    if ! chmod 700 "${scriptTemp}" || ! mv -f "${scriptTemp}" /etc/v2ray-agent/install.sh; then
        rm -f "${scriptTemp}"
        return 1
    fi

    echoContent green "\n ---> 更新完毕"
    echoContent yellow " ---> 请手动执行[xasma]重新打开脚本"
    echoContent yellow "如更新不成功，请手动执行下面命令\n"
    echoContent skyBlue "wget -O /root/install.sh https://raw.githubusercontent.com/qihang518887/xhttp-agent/main/install.sh && chmod 700 /root/install.sh && sh /root/install.sh"
    echo
    exit 0
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
    echoContent yellow "1.安装"
    echoContent yellow "2.查看订阅"
    echoContent yellow "3.整合其他订阅"
    echoContent yellow "4.证书管理"
    echoContent yellow "5.core管理"
    echoContent yellow "6.更新脚本"
    echoContent yellow "7.卸载脚本"
    echoContent red "=============================================================="
    mkdirTools
    aliasInstall
    read -r -p "请选择:" selectInstallType
    case ${selectInstallType} in
    1)
        customXrayInstall
        ;;
    2)
        showSubscription
        ;;
    3)
        addSubscribeMenu
        ;;
    4)
        renewalTLS 1
        ;;
    5)
        xrayVersionManageMenu 1
        ;;
    6)
        updateXHTTPAgent 1
        ;;
    7)
        unInstall 1
        ;;
    esac
}

cronFunction
menu
