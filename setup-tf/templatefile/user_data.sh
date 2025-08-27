#!/bin/bash
set -eux

# Step 1: Update package cache and install system dependencies
yum makecache
yum install -y git vim python3 python3-pip python3-devel alsa-lib-devel firewalld unzip wget

# Step 2: Install OCI CLI and related Python packages
dnf -y install oraclelinux-developer-release-el9
dnf -y install python39-oci-cli
pip3 install oci oracledb python-dotenv

# Step 3: Start and enable firewalld service
systemctl start firewalld
systemctl enable firewalld

# Step 4: Open required ports in the firewall (Streamlit and VNC)
firewall-cmd --add-port=8501/tcp --permanent
firewall-cmd --add-port=5901/tcp --permanent
firewall-cmd --reload

# Step 5: Install Docker Engine
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf install -y docker-ce docker-ce-cli containerd.io

# Step 6: Enable and start Docker
systemctl enable --now docker

# Step 7: Add opc (o ec2-user) to docker group to run without sudo
usermod -aG docker opc || true
usermod -aG docker ec2-user || true

# Step 8: Install Docker Compose plugin
dnf install -y docker-compose-plugin

# # Step 5: Download and install Miniconda for the opc user
# wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /home/opc/Miniconda3.sh
# chmod +x /home/opc/Miniconda3.sh
# /home/opc/Miniconda3.sh -b -u -p /home/opc/miniconda3

# # Step 6: Configure Conda for the opc user environment
# echo 'export PATH=/home/opc/miniconda3/bin:$PATH' >> /home/opc/.bashrc
# echo 'source /home/opc/miniconda3/etc/profile.d/conda.sh' >> /home/opc/.bashrc
# chown opc:opc /home/opc/.bashrc

# Step 7: Pre-accept Conda Terms of Service for required channels
# sudo -u opc -i bash -c 'source ~/.bashrc && conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main'
# sudo -u opc -i bash -c 'source ~/.bashrc && conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r'


# Step 8: Clone the project repository
git clone https://github.com/lazuluag/test_repo.git /home/opc/oracle-ai-accelerator
chown -R opc:opc /home/opc/oracle-ai-accelerator

# Step 9: Configure OCI CLI with credentials
mkdir -p /home/opc/.oci
echo "${oci_config_content}" > /home/opc/.oci/config
echo "${oci_key_content}" > /home/opc/.oci/key.pem
chmod 600 /home/opc/.oci/*
chown -R opc:opc /home/opc/.oci

# Step 10: Download and extract the Autonomous Database wallet
mkdir -p /home/opc/oracle-ai-accelerator/app/wallet

# Download the base64-encoded wallet
OCI_CLI_CONFIG_FILE=/home/opc/.oci/config oci os object get \
  --bucket-name ${bucket_name} \
  --name adb_wallet.zip \
  --file /home/opc/oracle-ai-accelerator/app/wallet/adb_wallet_encoded.zip

# Decode the wallet
base64 -d /home/opc/oracle-ai-accelerator/app/wallet/adb_wallet_encoded.zip > \
        /home/opc/oracle-ai-accelerator/app/wallet/adb_wallet.zip
rm -f /home/opc/oracle-ai-accelerator/app/wallet/adb_wallet_encoded.zip

# Unzip the wallet
unzip /home/opc/oracle-ai-accelerator/app/wallet/adb_wallet.zip \
      -d /home/opc/oracle-ai-accelerator/app/wallet

# Delete the object from Object Storage
OCI_CLI_CONFIG_FILE=/home/opc/.oci/config oci os object delete \
  --bucket-name ${bucket_name} \
  --name adb_wallet.zip \
  --force

# Step 11: Create the .env file with application environment variables
echo "${env}" > /home/opc/oracle-ai-accelerator/app/.env
chmod 600 /home/opc/oracle-ai-accelerator/app/.env
chown opc:opc /home/opc/oracle-ai-accelerator/app/.env

# Step 12: Run the setup script 
sudo -u opc -i bash <<'EOF'
cd /home/opc/oracle-ai-accelerator/setup
pip3 install --upgrade --force-reinstall python-dotenv --user
python3 setup.py --linux
EOF

# Step 13: Launch the Streamlit application using Docker Compose 
sudo -u opc -i bash <<'EOF'
cd /home/opc/oracle-ai-accelerator/app
echo "[INFO] Iniciando despliegue de contenedores con Docker Compose en background..."
docker compose -f /home/opc/oracle-ai-accelerator/setup/linux_containers/docker-compose.yml up --build -d
if [ $? -eq 0 ]; then
    echo "[OK] Docker Compose se ejecutó correctamente."
else
    echo "[ERROR] Hubo un problema al ejecutar Docker Compose."
    exit 1
fi
echo "[INFO] Redirigiendo logs de contenedores a archivos..."
docker logs -f oracle_ai_audio_backend > /home/opc/oracle_ai_audio_backend.log 2>&1 &
docker logs -f oracle_ai_frontend > /home/opc/oracle_ai_frontend.log 2>&1 &

echo "[INFO] Contenedores levantados en background. Logs disponibles en /home/opc/*.log"
EOF