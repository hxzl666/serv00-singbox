#!/bin/bash
# ============================================================================
# Mikrus Frog VPS 多协议节点安装脚本
# ============================================================================
# 支持的协议:
#   - Argo Tunnel (Cloudflare Tunnel) [无端口限制]
#   - VLESS-Reality [双栈复用 PORT1]
#   - Hysteria2 [双栈复用 PORT2]
#   - TUIC v5 [双栈复用 PORT3]
#   - VMess-WS [IPv6 直连]
#   - Shadowsocks-2022 [IPv6 直连]
# ============================================================================

# ==================== 颜色定义 ====================
re="\033[0m"
red="\033[1;91m"
green="\e[1;32m"
yellow="\e[1;33m"
purple="\e[1;35m"
blue="\e[1;36m"
white="\e[1;37m"

red() { echo -e "\e[1;91m$1\033[0m"; }
green() { echo -e "\e[1;32m$1\033[0m"; }
yellow() { echo -e "\e[1;33m$1\033[0m"; }
purple() { echo -e "\e[1;35m$1\033[0m"; }
blue() { echo -e "\e[1;36m$1\033[0m"; }
white() { echo -e "\e[1;37m$1\033[0m"; }
reading() { read -p "$(yellow "$1")" "$2"; }

# ==================== 环境变量 & 路径 ====================
export LC_ALL=C
WORKDIR="${HOME}/singbox"
LOGDIR="${WORKDIR}/logs"
WWWDIR="${WORKDIR}/www"
BINDIR="${WORKDIR}/bin"

# 检查系统架构并确定下载文件
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "amd64" ]; then
    SB_ARCH="linux-amd64"
    CF_ARCH="amd64"
elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    SB_ARCH="linux-arm64"
    CF_ARCH="arm64"
else
    SB_ARCH="linux-amd64"
    CF_ARCH="amd64"
fi

# ==================== 工具函数 ====================

# 确保所有基础目录存在
init_dirs() {
    mkdir -p "$WORKDIR" "$LOGDIR" "$WWWDIR" "$BINDIR"
    chmod 755 "$WORKDIR" "$BINDIR" "$WWWDIR"
    chmod 700 "$LOGDIR"
}

# 随机生成 UUID
generate_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    else
        python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d"
    fi
}

# 自建随机端口生成函数 (10000 - 65535)
generate_random_port() {
    local candidate=""
    local retry=0
    while [ $retry -lt 20 ]; do
        candidate=$(shuf -i 20000-60000 -n 1 2>/dev/null || python3 -c "import random; print(random.randint(20000, 60000))" 2>/dev/null || echo "35728")
        # 检测端口占用
        if ! netstat -tuln 2>/dev/null | grep -q ":$candidate "; then
            echo "$candidate"
            return 0
        fi
        ((retry++))
    done
    echo "39281"
}

# 获取公网 IPv6
get_ipv6() {
    local ip=""
    ip=$(curl -6 -s --max-time 4 https://api6.ipify.org 2>/dev/null)
    [ -z "$ip" ] && ip=$(curl -6 -s --max-time 4 https://ip.sb 2>/dev/null)
    [ -z "$ip" ] && ip=$(curl -6 -s --max-time 4 https://icanhazip.com 2>/dev/null)
    if [ -z "$ip" ]; then
        ip=$(ip -6 addr show | grep -oe '2[0-9a-f]\{3\}:[0-9a-f:]*' | head -n 1)
    fi
    echo "$ip"
}

# 后台脱离终端启动函数
run_detached() {
    local logfile="$1"; shift
    if command -v setsid >/dev/null 2>&1; then
        setsid "$@" </dev/null >>"$logfile" 2>&1 &
    else
        nohup "$@" </dev/null >>"$logfile" 2>&1 &
    fi
    # 尝试 disown 释放与当前 Shell 会话的关联，防止 SSH 登出时进程被杀死
    disown -h %$! 2>/dev/null || disown 2>/dev/null || true
}

# 获取最新 release
get_latest_release() {
    local repo=$1
    local tag=""
    tag=$(curl -s "https://api.github.com/repos/${repo}/releases/latest" | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4)
    if [ -z "$tag" ]; then
        if [ "$repo" = "SagerNet/sing-box" ]; then
            tag="1.11.2"
        else
            tag="2025.1.0"
        fi
    fi
    echo "${tag#v}" # 移除可能的前缀 'v'
}

# 下载带重试的直连下载函数
download_file() {
    local url=$1
    local dest=$2
    yellow "正在直连下载: ${url}"
    if curl -fsSL --connect-timeout 15 "${url}" -o "$dest"; then
        return 0
    else
        yellow "curl 直连下载失败，尝试使用 wget 降级直连下载..."
        if wget --no-check-certificate -qO "$dest" --timeout=15 "${url}"; then
            return 0
        fi
    fi
    return 1
}

# 安装依赖
install_dependencies() {
    yellow "正在检查系统依赖..."
    local pkgs=()
    command -v curl >/dev/null 2>&1 || pkgs+=("curl")
    command -v openssl >/dev/null 2>&1 || pkgs+=("openssl")
    command -v python3 >/dev/null 2>&1 || pkgs+=("python3")
    
    if [ ${#pkgs[@]} -gt 0 ]; then
        yellow "发现缺失工具: ${pkgs[*]}，尝试自动安装..."
        if [ -f "/etc/alpine-release" ]; then
            if [ "$(id -u)" -eq 0 ]; then
                yellow "正在更新 Alpine 软件包列表 (apk update)..."
                apk update >/dev/null 2>&1
                yellow "正在安装 ${pkgs[*]}..."
                apk add --no-cache "${pkgs[@]}"
            else
                if command -v sudo >/dev/null 2>&1; then
                    yellow "正在通过 sudo 安装依赖..."
                    sudo apk update >/dev/null 2>&1
                    sudo apk add --no-cache "${pkgs[@]}"
                else
                    red "错误: 缺少 root 权限，无法自动安装依赖。"
                    yellow "请先在终端运行 'sudo su' 切换至 root 管理员账户，再次运行此脚本。"
                    exit 1
                fi
            fi
        fi
    else
        green "✓ 所有基础依赖检查通过"
    fi

    # 针对 Alpine Linux 额外安装兼容 glibc 二进制的 gcompat 和 libc6-compat
    if [ -f "/etc/alpine-release" ]; then
        if ! apk info -e gcompat >/dev/null 2>&1 || ! apk info -e libc6-compat >/dev/null 2>&1; then
            yellow "正在检查/安装 Alpine glibc 兼容层 (gcompat / libc6-compat)..."
            if [ "$(id -u)" -eq 0 ]; then
                apk update >/dev/null 2>&1
                apk add --no-cache gcompat libc6-compat >/dev/null 2>&1
                green "✓ 兼容层安装完成"
            else
                if command -v sudo >/dev/null 2>&1; then
                    sudo apk update >/dev/null 2>&1
                    sudo apk add --no-cache gcompat libc6-compat >/dev/null 2>&1
                    green "✓ 兼容层安装完成 (sudo)"
                else
                    yellow "警告: 缺少 root 权限，无法安装 gcompat 兼容层，sing-box 可能会因为动态库缺失无法启动！"
                fi
            fi
        fi
    fi
}

# ==================== 安装核心组件 ====================

install_sb_from_github() {
    local sb_ver
    sb_ver=$(get_latest_release "SagerNet/sing-box")
    yellow "开始下载 sing-box v${sb_ver}..."
    local sb_url="https://github.com/SagerNet/sing-box/releases/download/v${sb_ver}/sing-box-${sb_ver}-linux-${CF_ARCH}.tar.gz"
    if download_file "$sb_url" "$WORKDIR/sing-box.tar.gz"; then
        tar -xzf "$WORKDIR/sing-box.tar.gz" -C "$WORKDIR"
        local extracted_dir
        extracted_dir=$(find "$WORKDIR" -maxdepth 1 -type d -name "sing-box-*")
        if [ -d "$extracted_dir" ]; then
            cp -f "$extracted_dir/sing-box" "$BINDIR/sing-box"
            chmod +x "$BINDIR/sing-box"
            rm -rf "$extracted_dir" "$WORKDIR/sing-box.tar.gz"
            green "✓ sing-box 从 GitHub 下载并安装完成"
            return 0
        else
            red "错误: sing-box 解压目录未找到"
            return 1
        fi
    else
        red "错误: 下载 sing-box 失败，请重试"
        return 1
    fi
}

install_binaries() {
    init_dirs
    install_dependencies
    
    local sb_installed=false
    
    # 如果是 Alpine 系统，优先尝试系统原生包管理器安装，确保 musl 兼容性
    if [ -f "/etc/alpine-release" ]; then
        yellow "检测到 Alpine Linux 系统，优先尝试通过系统 apk 包管理器安装原生 sing-box..."
        if [ "$(id -u)" -eq 0 ]; then
            apk update >/dev/null 2>&1
            apk add --no-cache sing-box >/dev/null 2>&1
        else
            if command -v sudo >/dev/null 2>&1; then
                sudo apk update >/dev/null 2>&1
                sudo apk add --no-cache sing-box >/dev/null 2>&1
            fi
        fi
        
        # 验证是否成功安装原生 sing-box 并在 bin 目录建立链接或拷贝
        if command -v sing-box >/dev/null 2>&1; then
            local native_sb
            native_sb=$(command -v sing-box)
            cp -f "$native_sb" "$BINDIR/sing-box" 2>/dev/null || ln -sf "$native_sb" "$BINDIR/sing-box"
            chmod +x "$BINDIR/sing-box"
            green "✓ 已成功部署 Alpine 原生编译版 sing-box"
            sb_installed=true
        else
            yellow "apk 原生包安装未成功，准备降级到 GitHub 编译包下载..."
        fi
    fi
    
    # 若不是 Alpine 或系统原生包安装失败，则降级从 GitHub 下载
    if [ "$sb_installed" = "false" ]; then
        install_sb_from_github || return 1
    fi

    # 安装 cloudflared
    yellow "开始下载 cloudflared..."
    local cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}"
    if download_file "$cf_url" "$BINDIR/cloudflared"; then
        chmod +x "$BINDIR/cloudflared"
        green "✓ cloudflared 安装完成"
    else
        red "错误: 下载 cloudflared 失败"
        return 1
    fi
}

# 生成自签名证书
generate_certificate() {
    # 检查自签名证书 (要求存在且不为空文件)
    if [ ! -f "$WORKDIR/cert.pem" ] || [ ! -s "$WORKDIR/cert.pem" ] || \
       [ ! -f "$WORKDIR/private.key" ] || [ ! -s "$WORKDIR/private.key" ]; then
        rm -f "$WORKDIR/cert.pem" "$WORKDIR/private.key"
        openssl ecparam -genkey -name prime256v1 -out "$WORKDIR/private.key" 2>/dev/null
        openssl req -new -x509 -days 3650 -key "$WORKDIR/private.key" -out "$WORKDIR/cert.pem" \
            -subj "/CN=frog.mikr.us" 2>/dev/null
        green "✓ 自签名证书生成完毕"
    fi
}

# 生成 Reality 密钥对
generate_reality_keys() {
    # 检查密钥对 (要求存在且不为空文件)
    if [ ! -f "$WORKDIR/public_key.txt" ] || [ ! -s "$WORKDIR/public_key.txt" ] || \
       [ ! -f "$WORKDIR/private_key.txt" ] || [ ! -s "$WORKDIR/private_key.txt" ]; then
        rm -f "$WORKDIR/public_key.txt" "$WORKDIR/private_key.txt"
        local output
        output=$("$BINDIR/sing-box" generate reality-keypair 2>/dev/null)
        local priv
        priv=$(echo "${output}" | grep -i "PrivateKey" | awk '{print $2}')
        local pub
        pub=$(echo "${output}" | grep -i "PublicKey" | awk '{print $2}')
        if [ -n "$priv" ] && [ -n "$pub" ]; then
            echo "$priv" > "$WORKDIR/private_key.txt"
            echo "$pub" > "$WORKDIR/public_key.txt"
            green "✓ Reality 密钥对生成完毕"
        else
            red "警告: Reality 密钥对生成失败，请确认 sing-box 运行正常！"
        fi
    fi
}

# ==================== 配置管理 ====================

# 一键保存当前参数
save_params() {
    echo "$UUID" > "$WORKDIR/UUID.txt"
    echo "$HOST_DOMAIN" > "$WORKDIR/HOST_DOMAIN.txt"
    echo "PORT1=$PORT1" > "$WORKDIR/ports.txt"
    echo "PORT2=$PORT2" >> "$WORKDIR/ports.txt"
    echo "PORT3=$PORT3" >> "$WORKDIR/ports.txt"
    echo "PORT_VMESS_V6=$PORT_VMESS_V6" >> "$WORKDIR/ports.txt"
    echo "PORT_ARGO_LOCAL=$PORT_ARGO_LOCAL" >> "$WORKDIR/ports.txt"
    echo "PORT_SS_V6=$PORT_SS_V6" >> "$WORKDIR/ports.txt"
}

# 加载保存的参数
load_params() {
    [ -f "$WORKDIR/UUID.txt" ] && UUID=$(cat "$WORKDIR/UUID.txt")
    [ -f "$WORKDIR/HOST_DOMAIN.txt" ] && HOST_DOMAIN=$(cat "$WORKDIR/HOST_DOMAIN.txt")
    if [ -f "$WORKDIR/ports.txt" ]; then
        source "$WORKDIR/ports.txt"
    fi
}

# 交互式收集参数
collect_params() {
    # 默认值设置
    local default_host
    default_host=$(hostname)
    if [[ ! "$default_host" =~ \. ]]; then
        default_host="frog01.mikr.us"
    fi
    local default_uuid
    default_uuid=$(generate_uuid)
    
    echo
    green "==== 请输入 Frog VPS 的网络配置参数 ===="
    reading "1. 请输入您的公网映射域名 (回车默认: $default_host): " custom_host
    HOST_DOMAIN=${custom_host:-$default_host}
    
    reading "2. 请输入第一个可用 IPv4 映射端口 (回车默认: 20194): " p1
    PORT1=${p1:-20194}
    reading "3. 请输入第二个可用 IPv4 映射端口 (回车默认: 30194): " p2
    PORT2=${p2:-30194}
    reading "4. 请输入第三个可用 IPv4 映射端口 (回车默认: 40194): " p3
    PORT3=${p3:-40194}
    
    reading "5. 请输入您的用户 UUID (回车默认随机生成): " custom_uuid
    UUID=${custom_uuid:-$default_uuid}
    
    # 自动生成 IPv6 专属端口
    PORT_VMESS_V6=$(generate_random_port)
    PORT_ARGO_LOCAL=$(generate_random_port)
    PORT_SS_V6=$(generate_random_port)
    
    save_params
}

# 生成 sing-box config.json
generate_singbox_config() {
    load_params
    generate_certificate
    generate_reality_keys
    
    local reality_priv
    reality_priv=$(cat "$WORKDIR/private_key.txt")
    local ss_password
    ss_password=$(openssl rand -base64 16)
    echo "$ss_password" > "$WORKDIR/ss_password.txt"
    
    cat > "$WORKDIR/config.json" <<EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "dns-remote",
        "address": "8.8.8.8"
      },
      {
        "tag": "dns-local",
        "address": "local"
      }
    ]
  },
  "inbounds": [
    {
      "tag": "vless-reality-in",
      "type": "vless",
      "listen": "::",
      "listen_port": $PORT1,
      "users": [
        {
          "uuid": "$UUID",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "blog.cloudflare.com",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "blog.cloudflare.com",
            "server_port": 443
          },
          "private_key": "$reality_priv",
          "short_id": [""]
        }
      }
    },
    {
      "tag": "hysteria2-in",
      "type": "hysteria2",
      "listen": "::",
      "listen_port": $PORT2,
      "users": [
        {
          "password": "$UUID"
        }
      ],
      "masquerade": "https://www.bing.com",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "$WORKDIR/cert.pem",
        "key_path": "$WORKDIR/private.key"
      }
    },
    {
      "tag": "tuic-in",
      "type": "tuic",
      "listen": "::",
      "listen_port": $PORT3,
      "users": [
        {
          "uuid": "$UUID",
          "password": "$UUID"
        }
      ],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "$WORKDIR/cert.pem",
        "key_path": "$WORKDIR/private.key"
      }
    },
    {
      "tag": "vmess-ws-in",
      "type": "vmess",
      "listen": "::",
      "listen_port": $PORT_VMESS_V6,
      "users": [
        {
          "uuid": "$UUID"
        }
      ],
      "transport": {
        "type": "ws",
        "path": "/$UUID-vm",
        "early_data_header_name": "Sec-WebSocket-Protocol"
      }
    },
    {
      "tag": "vmess-argo-in",
      "type": "vmess",
      "listen": "127.0.0.1",
      "listen_port": $PORT_ARGO_LOCAL,
      "users": [
        {
          "uuid": "$UUID"
        }
      ],
      "transport": {
        "type": "ws",
        "path": "/$UUID-argo",
        "early_data_header_name": "Sec-WebSocket-Protocol"
      }
    },
    {
      "tag": "ss-in",
      "type": "shadowsocks",
      "listen": "::",
      "listen_port": $PORT_SS_V6,
      "method": "2022-blake3-aes-128-gcm",
      "password": "$ss_password"
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ]
}
EOF
    green "✓ sing-box 配置文件 config.json 生成完毕"
}

# ==================== 服务运行管理 ====================

# 启动 sing-box
start_singbox() {
    if [ ! -f "$WORKDIR/config.json" ]; then
        red "错误: 配置文件不存在，请先选择安装组件"
        return 1
    fi
    # 验证配置
    if ! "$BINDIR/sing-box" check -c "$WORKDIR/config.json" >/dev/null 2>&1; then
        red "错误: config.json 验证未通过，请检查日志"
        "$BINDIR/sing-box" check -c "$WORKDIR/config.json"
        return 1
    fi
    # 停止已有进程
    pkill -f "sing-box" >/dev/null 2>&1 || killall sing-box >/dev/null 2>&1 || true
    sleep 1
    # 启动
    > "$LOGDIR/singbox.log"
    run_detached "$LOGDIR/singbox.log" "$BINDIR/sing-box" run -c "$WORKDIR/config.json"
    sleep 2
    if pgrep -f "sing-box" >/dev/null 2>&1 || pidof sing-box >/dev/null 2>&1; then
        green "✓ sing-box 已成功启动"
        return 0
    else
        red "错误: sing-box 启动失败，最近 10 行日志如下:"
        tail -n 10 "$LOGDIR/singbox.log"
        return 1
    fi
}

# 启动 argo 代理隧道
start_argo_tunnel() {
    # 停止已有进程
    pkill -f "tunnel --url http://localhost:$PORT_ARGO_LOCAL" >/dev/null 2>&1 || true
    sleep 1
    > "$LOGDIR/argo.log"
    # 后台运行临时隧道
    run_detached "$LOGDIR/argo.log" "$BINDIR/cloudflared" tunnel --url "http://localhost:$PORT_ARGO_LOCAL" --no-autoupdate
    yellow "正在建立 Argo 临时隧道连接..."
    sleep 8
}

# 提取并解析生成的临时隧道域名
get_argo_domain() {
    local domain=""
    domain=$(grep -o 'https://[-0-9a-zA-Z]*\.trycloudflare\.com' "$LOGDIR/argo.log" | tail -n 1 | sed 's/https:\/\///')
    echo "$domain"
}

# 启动本地订阅分发服务器
start_sub_server() {
    pkill -f "http.server 18000" >/dev/null 2>&1 || true
    pkill -f "tunnel --url http://127.0.0.1:18000" >/dev/null 2>&1 || true
    sleep 1
    
    mkdir -p "$WWWDIR"
    # 更新订阅文件
    cp -f "$WORKDIR/links.txt" "$WWWDIR/links.txt" 2>/dev/null
    base64 -w0 "$WORKDIR/links.txt" > "$WWWDIR/sub.txt" 2>/dev/null
    
    # 启动 Python 轻量静态 HTTP 服务
    nohup python3 -m http.server 18000 --bind 127.0.0.1 >/dev/null 2>&1 &
    # 穿透发布静态服务
    > "$LOGDIR/sub_argo.log"
    run_detached "$LOGDIR/sub_argo.log" "$BINDIR/cloudflared" tunnel --url "http://127.0.0.1:18000" --no-autoupdate
    yellow "正在生成并配置订阅发布链接..."
    sleep 8
}

# 获取发布订阅的临时域名
get_sub_domain() {
    local domain=""
    domain=$(grep -o 'https://[-0-9a-zA-Z]*\.trycloudflare\.com' "$LOGDIR/sub_argo.log" | tail -n 1 | sed 's/https:\/\///')
    echo "$domain"
}

# 停止所有服务
stop_all() {
    yellow "正在停止所有服务..."
    load_params
    
    # 彻底停止相关进程
    pkill -f "sing-box" >/dev/null 2>&1 || killall sing-box >/dev/null 2>&1 || true
    pkill -f "cloudflared" >/dev/null 2>&1 || killall cloudflared >/dev/null 2>&1 || true
    pkill -f "tunnel" >/dev/null 2>&1 || true
    pkill -f "http.server 18000" >/dev/null 2>&1 || true
    
    # 强制释放可能占用我们配置端口的进程 (如果有权限)
    if [ -n "$PORT1" ] || [ -n "$PORT2" ] || [ -n "$PORT3" ]; then
        local pids
        pids=$(netstat -tulpn 2>/dev/null | grep -E ":(${PORT1:-0}|${PORT2:-0}|${PORT3:-0}) " | awk '{print $7}' | cut -d'/' -f1 | grep -E '^[0-9]+$')
        if [ -n "$pids" ]; then
            kill -9 $pids >/dev/null 2>&1 || true
        fi
    fi
    
    green "✓ 所有服务已完全停止"
}

# ==================== 链接与订阅生成 ====================

generate_node_links() {
    load_params
    local ipv6_addr
    ipv6_addr=$(get_ipv6)
    
    local argo_domain
    argo_domain=$(get_argo_domain)
    
    local sub_domain
    sub_domain=$(get_sub_domain)
    
    local pub_key
    pub_key=$(cat "$WORKDIR/public_key.txt" 2>/dev/null)
    local ss_pass
    ss_pass=$(cat "$WORKDIR/ss_password.txt" 2>/dev/null)
    
    local isName="FrogVPS"
    local output_file="$WORKDIR/links.txt"
    local list_file="$WORKDIR/list.txt"
    
    > "$output_file"
    > "$list_file"
    
    # ================= 写入展示详情 =================
    echo "==============================================" >> "$list_file"
    echo "  Mikrus Frog VPS 多协议配置详情" >> "$list_file"
    echo "==============================================" >> "$list_file"
    echo "  IPv4 映射域名: $HOST_DOMAIN" >> "$list_file"
    echo "  公网 IPv6 地址: ${ipv6_addr:-未知}" >> "$list_file"
    echo "  UUID: $UUID" >> "$list_file"
    echo "==============================================" >> "$list_file"
    echo >> "$list_file"

    # 1. VLESS Reality
    local vless_v4="vless://$UUID@$HOST_DOMAIN:$PORT1?encryption=none&flow=xtls-rprx-vision&security=reality&sni=blog.cloudflare.com&fp=chrome&pbk=$pub_key&type=tcp&headerType=none#$isName-VLESS-Reality-IPv4"
    echo "$vless_v4" >> "$output_file"
    echo "【VLESS-Reality - IPv4 NAT 映射】" >> "$list_file"
    echo "$vless_v4" >> "$list_file"
    echo >> "$list_file"
    
    if [ -n "$ipv6_addr" ]; then
        local vless_v6="vless://$UUID@[$ipv6_addr]:$PORT1?encryption=none&flow=xtls-rprx-vision&security=reality&sni=blog.cloudflare.com&fp=chrome&pbk=$pub_key&type=tcp&headerType=none#$isName-VLESS-Reality-IPv6"
        echo "$vless_v6" >> "$output_file"
        echo "【VLESS-Reality - IPv6 直连】" >> "$list_file"
        echo "$vless_v6" >> "$list_file"
        echo >> "$list_file"
    fi

    # 2. Hysteria2
    local hy2_v4="hysteria2://$UUID@$HOST_DOMAIN:$PORT2?security=tls&sni=www.bing.com&alpn=h3&insecure=1#$isName-Hysteria2-IPv4"
    echo "$hy2_v4" >> "$output_file"
    echo "【Hysteria2 - IPv4 NAT 映射】" >> "$list_file"
    echo "$hy2_v4" >> "$list_file"
    echo >> "$list_file"
    
    if [ -n "$ipv6_addr" ]; then
        local hy2_v6="hysteria2://$UUID@[$ipv6_addr]:$PORT2?security=tls&sni=www.bing.com&alpn=h3&insecure=1#$isName-Hysteria2-IPv6"
        echo "$hy2_v6" >> "$output_file"
        echo "【Hysteria2 - IPv6 直连】" >> "$list_file"
        echo "$hy2_v6" >> "$list_file"
        echo >> "$list_file"
    fi

    # 3. TUIC v5
    local tuic_v4="tuic://$UUID:$UUID@$HOST_DOMAIN:$PORT3?sni=www.bing.com&congestion_control=bbr&udp_relay_mode=native&alpn=h3&allow_insecure=1#$isName-TUIC5-IPv4"
    echo "$tuic_v4" >> "$output_file"
    echo "【TUIC v5 - IPv4 NAT 映射】" >> "$list_file"
    echo "$tuic_v4" >> "$list_file"
    echo >> "$list_file"
    
    if [ -n "$ipv6_addr" ]; then
        local tuic_v6="tuic://$UUID:$UUID@[$ipv6_addr]:$PORT3?sni=www.bing.com&congestion_control=bbr&udp_relay_mode=native&alpn=h3&allow_insecure=1#$isName-TUIC5-IPv6"
        echo "$tuic_v6" >> "$output_file"
        echo "【TUIC v5 - IPv6 直连】" >> "$list_file"
        echo "$tuic_v6" >> "$list_file"
        echo >> "$list_file"
    fi

    # 4. VMess-WS IPv6 直连
    if [ -n "$ipv6_addr" ]; then
        local vmess_v6_json
        vmess_v6_json=$(echo "{\"v\":\"2\",\"ps\":\"$isName-VMess-WS-IPv6\",\"add\":\"$ipv6_addr\",\"port\":\"$PORT_VMESS_V6\",\"id\":\"$UUID\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"\",\"path\":\"/$UUID-vm?ed=2048\",\"tls\":\"\",\"sni\":\"\"}" | base64 -w0)
        local vmess_v6="vmess://$vmess_v6_json"
        echo "$vmess_v6" >> "$output_file"
        echo "【VMess-WS - IPv6 直连】" >> "$list_file"
        echo "$vmess_v6" >> "$list_file"
        echo >> "$list_file"
    fi

    # 5. Shadowsocks IPv6 直连
    if [ -n "$ipv6_addr" ]; then
        local ss_enc
        ss_enc=$(echo -n "2022-blake3-aes-128-gcm:$ss_pass" | base64 -w0)
        local ss_v6="ss://${ss_enc}@[$ipv6_addr]:$PORT_SS_V6#$isName-Shadowsocks-IPv6"
        echo "$ss_v6" >> "$output_file"
        echo "【Shadowsocks-2022 - IPv6 直连】" >> "$list_file"
        echo "$ss_v6" >> "$list_file"
        echo >> "$list_file"
    fi

    # 6. Argo VMess 穿透
    if [ -n "$argo_domain" ]; then
        # TLS
        local vmess_argo_tls_json
        vmess_argo_tls_json=$(echo "{\"v\":\"2\",\"ps\":\"$isName-Argo-TLS\",\"add\":\"cdn.2020111.xyz\",\"port\":\"8443\",\"id\":\"$UUID\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$argo_domain\",\"path\":\"/$UUID-argo?ed=2048\",\"tls\":\"tls\",\"sni\":\"$argo_domain\"}" | base64 -w0)
        local vmess_argo_tls="vmess://$vmess_argo_tls_json"
        echo "$vmess_argo_tls" >> "$output_file"
        
        # NoTLS
        local vmess_argo_notls_json
        vmess_argo_notls_json=$(echo "{\"v\":\"2\",\"ps\":\"$isName-Argo-NoTLS\",\"add\":\"cdn.2020111.xyz\",\"port\":\"8880\",\"id\":\"$UUID\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$argo_domain\",\"path\":\"/$UUID-argo?ed=2048\",\"tls\":\"\"}" | base64 -w0)
        local vmess_argo_notls="vmess://$vmess_argo_notls_json"
        echo "$vmess_argo_notls" >> "$output_file"
        
        echo "【Argo VMess-WS-Tunnel (通过 CF 节点中转，绕过 IPv4 端口限制)】" >> "$list_file"
        echo "TLS (端口 8443): $vmess_argo_tls" >> "$list_file"
        echo "NoTLS (端口 8880): $vmess_argo_notls" >> "$list_file"
        echo >> "$list_file"
    fi
    
    echo "==============================================" >> "$list_file"
    if [ -n "$sub_domain" ]; then
        echo "  Argo 发布订阅地址 (被墙依旧可以拉取订阅):" >> "$list_file"
        echo "  https://$sub_domain/sub.txt" >> "$list_file"
        echo "  https://$sub_domain/links.txt (明文)" >> "$list_file"
    else
        echo "  Argo 订阅未启用 (您可以通过本地 links.txt 复制配置)" >> "$list_file"
    fi
    echo "==============================================" >> "$list_file"
    
    # 拷贝到 www 目录同步
    cp -f "$WORKDIR/links.txt" "$WWWDIR/links.txt" 2>/dev/null
    base64 -w0 "$WORKDIR/links.txt" > "$WWWDIR/sub.txt" 2>/dev/null
}

# 显示节点和发布信息
show_links() {
    if [ -f "$WORKDIR/list.txt" ]; then
        cat "$WORKDIR/list.txt"
    else
        red "错误: 未找到节点信息，请先进行一键安装"
    fi
}

# ==================== 保活 & Cron 定时任务 ====================

# 保活主检测逻辑
keep_alive() {
    load_params
    if [ -z "$UUID" ]; then
        return 0
    fi
    
    # 1. 检测并重启 sing-box
    if ! (pgrep -f "sing-box" >/dev/null 2>&1 || pidof sing-box >/dev/null 2>&1); then
        echo "[$(date)] sing-box 崩溃退出，正在重新拉起..." >> "$LOGDIR/keep_alive.log"
        start_singbox >> "$LOGDIR/keep_alive.log" 2>&1
    fi
    
    # 2. 检测并重启 Argo Tunnel (如果 argo.log 存在)
    if [ -f "$LOGDIR/argo.log" ]; then
        if ! pgrep -f "tunnel --url http://localhost:$PORT_ARGO_LOCAL" >/dev/null 2>&1; then
            echo "[$(date)] cloudflared argo 退出，正在重启..." >> "$LOGDIR/keep_alive.log"
            start_argo_tunnel >> "$LOGDIR/keep_alive.log" 2>&1
        fi
    fi
    
    # 3. 检测并重启 Python 订阅分发和穿透
    if [ -f "$LOGDIR/sub_argo.log" ]; then
        if ! pgrep -f "http.server 18000" >/dev/null 2>&1 || ! pgrep -f "tunnel --url http://127.0.0.1:18000" >/dev/null 2>&1; then
            echo "[$(date)] 订阅共享服务故障，正在重启..." >> "$LOGDIR/keep_alive.log"
            start_sub_server >> "$LOGDIR/keep_alive.log" 2>&1
            generate_node_links
        fi
    fi
}

# 添加 Cron 定时任务
enable_cron() {
    local cron_cmd="*/5 * * * * /bin/bash $WORKDIR/frog_nodes.sh cron >> $LOGDIR/cron.log 2>&1"
    (crontab -l 2>/dev/null | grep -Fv "frog_nodes.sh"; echo "$cron_cmd") | crontab -
    green "✓ 保活 crontab 定时任务已启用 (每 5 分钟巡检一次)"
}

# 关闭 Cron 定时任务
disable_cron() {
    crontab -l 2>/dev/null | grep -Fv "frog_nodes.sh" | crontab -
    green "✓ 保活 crontab 定时任务已禁用"
}

# ==================== 快捷命令 ====================

# 创建快捷命令
create_quick_command() {
    COMMAND="sb"
    SCRIPT_PATH="$HOME/bin/$COMMAND"
    mkdir -p "$HOME/bin"
    
    cat > "$SCRIPT_PATH" <<'EOF'
#!/bin/bash
bash <(curl -Ls https://raw.githubusercontent.com/hxzlplp7/serv00-singbox/main/frog_nodes.sh)
EOF
    
    chmod +x "$SCRIPT_PATH"
    
    if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
        echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc" 2>/dev/null
        echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.profile" 2>/dev/null
        source "$HOME/.bashrc" 2>/dev/null
        source "$HOME/.profile" 2>/dev/null
    fi
    
    green "✓ 快捷命令 'sb' 已创建"
    yellow "  ⚠️ 提示：由于当前会话环境变量限制，首次使用前您需要断开 SSH 重新连接，"
    yellow "  或者在当前终端手动执行以下命令，即可立即生效："
    green "  source ~/.bashrc"
}

# ==================== 卸载 ====================

uninstall() {
    yellow "正在卸载并清除所有节点服务与配置..."
    disable_cron
    stop_all
    rm -rf "$WORKDIR"
    rm -f "${HOME}/bin/sb" 2>/dev/null
    green "✓ 卸载清理完毕！"
}

# ==================== CLI 分流调用 ====================
if [ "$1" = "cron" ]; then
    keep_alive
    exit 0
fi

# ==================== 日志查看 ====================
view_logs_menu() {
    while true; do
        clear
        echo -e "${green}    ______   ____     ____    ______     _    __   ____    ____ ${re}"
        echo -e "${green}   / ____/  / __ \\   / __ \\  / ____/    | |  / /  / __ \\  / ___/ ${re}"
        echo -e "${green}  / /__    / /_/ /  / / / / / / __      | | / /  / /_/ /  \\__ \\  ${re}"
        echo -e "${green} / /___   / _, _/  / /_/ / / /_/ /      | |/ /  / ____/  ___/ /  ${re}"
        echo -e "${green}/_____/  /_/ |_|   \\____/  \\____/       |___/  /_/      /____/   ${re}"
        echo
        green "============================================================"
        green "  服务运行日志查看"
        green "============================================================"
        echo
        yellow "  1. 查看 sing-box 节点主进程日志"
        yellow "  2. 查看 cloudflared Argo 节点穿透日志"
        yellow "  3. 查看订阅文件发布穿透日志"
        yellow "  4. 查看 Cron 定时保活巡检日志"
        echo "------------------------------------------------------------"
        red    "  0. 返回主菜单"
        echo "============================================================"
        echo
        reading "请选择操作 [0-4]: " log_choice
        case "$log_choice" in
            1)
                echo
                green "========== sing-box 日志 (最近 30 行) =========="
                tail -n 30 "$LOGDIR/singbox.log" 2>/dev/null || yellow "暂无日志"
                echo "================================================="
                ;;
            2)
                echo
                green "========== Argo 穿透日志 (最近 30 行) =========="
                tail -n 30 "$LOGDIR/argo.log" 2>/dev/null || yellow "暂无日志"
                echo "================================================="
                ;;
            3)
                echo
                green "========== 订阅发布日志 (最近 30 行) =========="
                tail -n 30 "$LOGDIR/sub_argo.log" 2>/dev/null || yellow "暂无日志"
                echo "================================================="
                ;;
            4)
                echo
                green "========== Cron 保活日志 (最近 30 行) =========="
                tail -n 30 "$LOGDIR/cron.log" 2>/dev/null || yellow "暂无日志"
                echo "================================================="
                ;;
            0)
                return 0
                ;;
            *)
                red "无效输入！"
                ;;
        esac
        echo
        reading "按回车键继续..." _
    done
}

# ==================== 菜单界面 ====================

show_menu() {
    clear
    echo -e "${green}    ______   ____     ____    ______     _    __   ____    ____ ${re}"
    echo -e "${green}   / ____/  / __ \\   / __ \\  / ____/    | |  / /  / __ \\  / ___/ ${re}"
    echo -e "${green}  / /__    / /_/ /  / / / / / / __      | | / /  / /_/ /  \\__ \\  ${re}"
    echo -e "${green} / /___   / _, _/  / /_/ / / /_/ /      | |/ /  / ____/  ___/ /  ${re}"
    echo -e "${green}/_____/  /_/ |_|   \\____/  \\____/       |___/  /_/      /____/   ${re}"
    echo
    green "============================================================"
    green "  Mikrus Frog VPS (Alpine Linux) 多协议一键部署脚本"
    green "============================================================"
    purple "  基于双栈多协议复用机制设计，无公网 IPv4 亦能完美连通"
    green "============================================================"
    
    # 显示服务当前状态
    echo -n "  服务状态: "
    if pgrep -f "sing-box" >/dev/null 2>&1 || pidof sing-box >/dev/null 2>&1; then
        green "● 运行中"
    else
        red "○ 未运行"
    fi
    
    local cron_status="○ 未开启"
    if crontab -l 2>/dev/null | grep -q "frog_nodes.sh"; then
        cron_status="● 已开启"
    fi
    echo -e "  Crontab 保活: ${green}${cron_status}${re}"
    echo "============================================================"
    echo "  1. 一键收集参数并安装/更新"
    echo "  2. 启动所有服务 (sing-box + Argo + 订阅托管)"
    echo "  3. 停止所有服务"
    echo "  4. 重启所有服务"
    echo "  5. 查看当前节点分享链接与订阅域名"
    echo "------------------------------------------------------------"
    echo "  6. 开启 Cron 定时保活"
    echo "  7. 关闭 Cron 定时保活"
    echo "  8. 卸载并清除所有数据"
    echo "  9. 查看运行日志"
    echo "------------------------------------------------------------"
    echo "  0. 退出脚本"
    echo "============================================================"
    echo
}

# 主循环
main() {
    # 检测运行身份并给出建议
    if [ "$(id -u)" -ne 0 ]; then
        yellow "============================================================"
        yellow " 提示: 当前是以普通用户 (frog) 身份运行此脚本。"
        yellow " 某些系统依赖 (如 curl, openssl, python3) 必须 root 权限才能自动安装。"
        yellow " 建议先运行 'sudo su' 切换到管理员账户，然后再执行该脚本。"
        yellow "============================================================"
        echo
        reading "是否强行继续以当前普通用户身份运行? [y/N]: " continue_run
        if [[ ! "$continue_run" =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi

    # 强制在当前用户家目录下新建或跳转
    init_dirs
    
    while true; do
        show_menu
        reading "请选择操作 [0-9]: " choice
        case "$choice" in
            1)
                collect_params
                install_binaries
                if [ $? -eq 0 ]; then
                    generate_singbox_config
                    start_sub_server
                    start_argo_tunnel
                    start_singbox
                    generate_node_links
                    enable_cron
                    create_quick_command
                    echo
                    green "安装部署已全部完成！"
                    green "  快捷命令: sb (首次在当前终端使用请先执行: source ~/.bashrc)"
                    show_links
                fi
                ;;
            2)
                collect_params
                generate_singbox_config
                start_sub_server
                start_argo_tunnel
                start_singbox
                generate_node_links
                ;;
            3)
                stop_all
                ;;
            4)
                stop_all
                collect_params
                generate_singbox_config
                start_sub_server
                start_argo_tunnel
                start_singbox
                generate_node_links
                ;;
            5)
                show_links
                ;;
            6)
                enable_cron
                ;;
            7)
                disable_cron
                ;;
            8)
                uninstall
                ;;
            9)
                view_logs_menu
                ;;
            0)
                exit 0
                ;;
            *)
                red "无效输入，请重新选择！"
                ;;
        esac
        echo
        reading "按回车键继续..." _
    done
}

# 复制一份自身到工作目录，以便 crontab 稳定执行
cp -f "$0" "$WORKDIR/frog_nodes.sh" 2>/dev/null
chmod +x "$WORKDIR/frog_nodes.sh" 2>/dev/null

main
