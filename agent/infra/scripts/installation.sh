#!/usr/bin/env bash
set -x

LOG_FILE="/var/log/installation.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "===== INSTALLATION STARTED ====="

echo "ADMIN_USERNAME=${ADMIN_USERNAME:-}"
echo "AZDO_ORG_URL=${AZDO_ORG_URL:-}"
echo "AZDO_POOL=${AZDO_POOL:-}"
echo "AZDO_AGENT_NAME=${AZDO_AGENT_NAME:-}"

export DEBIAN_FRONTEND=noninteractive

# wait for VM boot
sleep 60

# fix apt locks
rm -f /var/lib/dpkg/lock-frontend || true
rm -f /var/cache/apt/archives/lock || true
dpkg --configure -a || true

# Base packages
apt-get update -y || true
apt-get install -y \
  ca-certificates \
  curl \
  wget \
  gnupg \
  lsb-release \
  software-properties-common \
  unzip \
  apt-transport-https \
  openjdk-17-jdk \
  git \
  maven \
  nginx \
  jq || true

echo "===== BASE PACKAGES INSTALLED ====="

# Docker install
install -m 0755 -d /etc/apt/keyrings || true

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
| gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg || true

chmod a+r /etc/apt/keyrings/docker.gpg || true

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo $VERSION_CODENAME) stable" \
> /etc/apt/sources.list.d/docker.list

apt-get update -y || true
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true

usermod -aG docker "${ADMIN_USERNAME}" || true
systemctl enable docker || true
systemctl start docker || true

echo "===== DOCKER INSTALLED ====="

# kubectl
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key \
| gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg || true

chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo \
"deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" \
> /etc/apt/sources.list.d/kubernetes.list

chmod 644 /etc/apt/sources.list.d/kubernetes.list

apt-get update -y || true
apt-get install -y kubectl || true

echo "===== KUBECTL INSTALLED ====="

# Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | bash || true

echo "===== AZURE CLI INSTALLED ====="

# Trivy
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key \
| gpg --dearmor --yes -o /usr/share/keyrings/trivy.gpg || true

echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] \
https://aquasecurity.github.io/trivy-repo/deb generic main" \
> /etc/apt/sources.list.d/trivy.list

apt-get update -y || true
apt-get install -y trivy || true

echo "===== TRIVY INSTALLED ====="

# SonarQube container
docker rm -f sonarqube || true
docker run -d --name sonarqube -p 9000:9000 sonarqube:lts-community || true

echo "===== SONARQUBE STARTED ====="

# Azure DevOps agent dependencies
apt-get install -y libicu70 libssl3 || true

# Azure DevOps self-hosted agent
mkdir -p /azagent
cd /azagent

if [ ! -f .agent ]; then
  curl -fsSL -o agent.tar.gz \
  https://download.agent.dev.azure.com/agent/4.255.0/vsts-agent-linux-x64-4.255.0.tar.gz

  tar zxvf agent.tar.gz
fi

chown -R "${ADMIN_USERNAME}:${ADMIN_USERNAME}" /azagent || true

echo "===== AZDO AGENT FILES READY ====="

sudo -u "${ADMIN_USERNAME}" env \
  AZP_URL="${AZDO_ORG_URL}" \
  AZP_TOKEN="${AZDO_PAT}" \
  AZP_POOL="${AZDO_POOL}" \
  AZP_AGENT="${AZDO_AGENT_NAME}" \
  bash -lc '
    set -x
    cd /azagent
    if [ ! -f .agent ]; then
      ./config.sh --unattended \
        --agent "$AZP_AGENT" \
        --url "$AZP_URL" \
        --auth pat \
        --token "$AZP_TOKEN" \
        --pool "$AZP_POOL" \
        --acceptTeeEula \
        --replace || true
    fi
  '

echo "===== AZDO AGENT CONFIGURED ====="

cd /azagent
./svc.sh install "${ADMIN_USERNAME}" || true
./svc.sh start || true

echo "===== AZDO AGENT SERVICE STARTED ====="

# Verify tools
git --version || true
docker --version || true
kubectl version --client || true
mvn -version || true
az version || true
trivy --version || true

echo "===== INSTALLATION COMPLETED SUCCESSFULLY ====="