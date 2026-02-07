et -euo pipefail

# =========================
# Debian/Ubuntu 一键安装 Docker + 同步时区/时间
# 默认时区 Asia/Shanghai，可通过 TZ 环境变量覆盖
# 用法：
#   curl -fsSL https://your.domain/install_docker_tz.sh | sudo TZ=Asia/Shanghai bash
#   或保存后 sudo bash install_docker_tz.sh
# =========================

if [[ $EUID -ne 0 ]]; then
	  echo "请用 root 运行：sudo bash $0"
	    exit 1
fi

TZ_VALUE="${TZ:-Asia/Shanghai}"

echo "[1/6] 检测系统..."
if [[ -r /etc/os-release ]]; then
	  . /etc/os-release
  else
	    echo "无法读取 /etc/os-release，退出"
	      exit 1
fi

OS_ID="${ID:-}"
OS_LIKE="${ID_LIKE:-}"
CODENAME="${VERSION_CODENAME:-}"

if [[ -z "$CODENAME" ]]; then
	  # 兼容部分旧系统
	    CODENAME="$(lsb_release -cs 2>/dev/null || true)"
fi

if [[ -z "$CODENAME" ]]; then
	  echo "无法检测发行版代号（codename），退出"
	    exit 1
fi

if [[ "$OS_ID" != "debian" && "$OS_ID" != "ubuntu" && "$OS_LIKE" != *"debian"* ]]; then
	  echo "当前系统似乎不是 Debian/Ubuntu 系：ID=$OS_ID ID_LIKE=$OS_LIKE"
	    echo "仍可尝试，但不保证完全兼容。"
fi

echo "系统：${PRETTY_NAME:-$OS_ID} 代号：$CODENAME"

echo "[2/6] 同步时区：$TZ_VALUE"
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y tzdata ca-certificates curl gnupg

# systemd 环境优先用 timedatectl
if command -v timedatectl >/dev/null 2>&1; then
	  timedatectl set-timezone "$TZ_VALUE" || true
  else
	    # 非 systemd 环境：手动写入
	      echo "$TZ_VALUE" >/etc/timezone
	        ln -snf "/usr/share/zoneinfo/$TZ_VALUE" /etc/localtime
fi

# 兜底确保 /etc/localtime 正确
if [[ -f "/usr/share/zoneinfo/$TZ_VALUE" ]]; then
	  ln -snf "/usr/share/zoneinfo/$TZ_VALUE" /etc/localtime
fi

echo "[3/6] 开启时间同步（NTP）"
# 优先 systemd-timesyncd；若不可用则安装 chrony
if systemctl list-unit-files 2>/dev/null | grep -q '^systemd-timesyncd\.service'; then
	  systemctl enable --now systemd-timesyncd >/dev/null 2>&1 || true
	    timedatectl set-ntp true >/dev/null 2>&1 || true
    else
	      DEBIAN_FRONTEND=noninteractive apt-get install -y chrony
	        systemctl enable --now chrony >/dev/null 2>&1 || true
fi

echo "[4/6] 安装 Docker（官方仓库）"
install -m 0755 -d /etc/apt/keyrings

# 清理旧版本（不强制删除数据目录）
apt-get remove -y docker docker-engine docker.io containerd runc >/dev/null 2>&1 || true

# 导入 Docker GPG key
curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

ARCH="$(dpkg --print-architecture)"

# 写入源
cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS_ID} ${CODENAME} stable
EOF

apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "[5/6] 启动并设置开机自启"
systemctl enable --now docker

echo "[6/6] 验证安装"
docker version
docker compose version

echo
echo "✅ 完成！"
echo "当前时区：$(cat /etc/timezone 2>/dev/null || true)"
date
echo
echo "建议：让容器时区与宿主机一致（运行容器时加上）："
echo "  -v /etc/localtime:/etc/localtime:ro -v /etc/timezone:/etc/timezone:ro"

