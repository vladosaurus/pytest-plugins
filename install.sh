#!/bin/bash
set -eo pipefail

# Suppress the "dpkg-preconfigure: unable to re-open stdin: No such file or directory" error
export DEBIAN_FRONTEND=noninteractive

function install_base_tools {
  apt-get update
  apt-get install -y \
    build-essential \
    default-jdk \
    curl \
    wget \
    git \
    unzip
}

function install_python_ppa {
  apt-get install -y software-properties-common
  add-apt-repository -y ppa:deadsnakes/ppa
  apt-get update
}

function install_python_packaging {
  local py=$1
  $py -m pip install --upgrade pip
  $py -m pip install --upgrade setuptools
  $py -m pip install --upgrade virtualenv
}


function install_python {
  local py=$1
  apt-get install -y $py $py-dev
  curl --silent --show-error --retry 5 https://bootstrap.pypa.io/get-pip.py | $py
  install_python_packaging $py
}


function choco_install {
  local args=$*
  # choco fails randomly with network errors on travis, have a few goes
  for i in {1..5}; do
      choco install $args && return 0
      echo 'choco install failed, log tail follows:'
      tail -500 C:/ProgramData/chocolatey/logs/chocolatey.log
      echo 'sleeping for a bit and retrying'.
      sleep 5
  done
  return 1
}


function install_windows_make {
  choco_install make --params "/InstallDir:C:\\tools\\make"
}


function install_windows_py27 {
  choco_install python2 --params "/InstallDir:C:\\Python"
  export PATH="/c/Python:/c/Python/Scripts:$PATH"
  install_python_packaging python
}


function install_windows_py35 {
  choco_install python --version 3.5.4 --params "/InstallDir:C:\\Python"
  export PATH="/c/Python35:/c/Python35/Scripts:$PATH"
  install_python_packaging python
}


function install_windows_py36 {
  choco_install python --version 3.6.8 --params "/InstallDir:C:\\Python"
  export PATH="/c/Python36:/c/Python36/Scripts:$PATH"
  install_python_packaging python
}


function install_windows_py37 {
  choco_install python --version 3.7.5 --params "/InstallDir:C:\\Python"
  export PATH="/c/Python37:/c/Python37/Scripts:$PATH"
  install_python_packaging python
}


function init_venv {
  local py=$1
  virtualenv venv --python=$py
  if [ -f venv/Scripts/activate ]; then
      . venv/Scripts/activate
  else
      . venv/bin/activate
  fi
}


function update_apt_sources {
  wget -qO- https://download.rethinkdb.com/repository/raw/pubkey.gpg | apt-key add -
  . /etc/lsb-release && echo "deb https://download.rethinkdb.com/repository/ubuntu-$DISTRIB_CODENAME $DISTRIB_CODENAME main" | tee /etc/apt/sources.list.d/rethinkdb.list

  wget -q -O - https://pkg.jenkins.io/debian-stable/jenkins.io.key | apt-key add -
  sh -c 'echo deb http://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list'

  apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 0C49F3730359A14518585931BC711F9BA15703C6
  echo "deb [ arch=amd64 ] http://repo.mongodb.org/apt/ubuntu trusty/mongodb-org/3.4 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-3.4.list

  apt install ca-certificates
  apt-get update
}

function install_system_deps {
  apt-get install -y \
    xvfb \
    x11-utils \
    subversion \
    graphviz \
    pandoc
}

function install_postgresql {
  apt-get install -y postgresql postgresql-contrib libpq-dev
  service postgresql stop; update-rc.d postgresql disable;
}

function install_redis {
  apt-get install -y redis-server
}

function install_rethinkdb {
  apt-get install -y rethinkdb
  service rethinkdb stop; update-rc.d rethinkdb disable;
}

function install_jenkins {
  apt-get install -y jenkins
  service jenkins stop; update-rc.d jenkins disable;
}

function install_mongodb {
  apt-get install -y mongodb mongodb-server
}

function install_apache {
  apt-get install -y apache2
  service apache2 stop; update-rc.d apache2 disable;
}

function install_minio {
  wget -q https://dl.minio.io/server/minio/release/linux-amd64/minio -O /tmp/minio
  mv /tmp/minio /usr/local/bin/minio
  chmod a+x /usr/local/bin/minio
}

function install_chrome_headless {
  wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -O /tmp/google-chrome-stable_current_amd64.deb
  dpkg -i --force-depends /tmp/google-chrome-stable_current_amd64.deb || apt-get install -f -y
  wget -q https://chromedriver.storage.googleapis.com/2.43/chromedriver_linux64.zip -O /tmp/chromedriver_linux64.zip
  unzip /tmp/chromedriver_linux64.zip
  mv chromedriver /usr/local/bin/
  chmod a+x /usr/local/bin/chromedriver
}

function install_kubernetes {
  apt-get update && apt-get install -y apt-transport-https curl

  curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF

  apt-get update
  apt-get install -y kubelet kubeadm kubectl
  apt-mark hold kubelet kubeadm kubectl

  systemctl daemon-reload
  systemctl stop kubelet
  swapoff -a
  kubeadm init --ignore-preflight-errors=SystemVerification --pod-network-cidr=192.168.0.0/16
  export KUBECONFIG=/etc/kubernetes/admin.conf

  # install cni (calico)
  kubectl apply -f https://docs.projectcalico.org/v3.3/getting-started/kubernetes/installation/hosted/rbac-kdd.yaml
  kubectl apply -f https://docs.projectcalico.org/v3.3/getting-started/kubernetes/installation/hosted/kubernetes-datastore/calico-networking/1.7/calico.yaml
  kubectl get node

  # allow master node to run pods since we are creating a single-node cluster
  kubectl taint node $(hostname -s) node-role.kubernetes.io/master-

  # copy kubeconfig
  cp -f /etc/kubernetes/admin.conf /home/vagrant/.kube/config
  chown -R vagrant: /home/vagrant/.kube
}

function install_black {
  python3.6 -mpip install black
}

# Install all
function install_all {
  install_base_tools
  install_python_ppa

  install_python python2.7
  install_python python3.5
  install_python python3.6
  install_python python3.7

  install_black

  update_apt_sources
  install_system_deps
  install_postgresql
  install_redis
  install_rethinkdb
  install_jenkins
  install_mongodb
  install_apache
  install_minio
  install_chrome_headless
}

