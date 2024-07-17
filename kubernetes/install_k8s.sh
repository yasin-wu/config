#!/bin/bash

ip=${1-"192.168.0.1"}
docker_version=19.03.12
k8s_version=1.20.11

green='\033[40;32m'
plain='\033[0m'

offSwapFunc() {
  line=$(sed -n '/swap/=' /etc/fstab)
  swapoff -a
  for d in ${line}; do
     if sed -n "${d}","${d}"p '/etc/fstab' | grep "#" > /dev/null; then
        echo -e "${green}*******swap off******* ${plain}"
      else
        sed -i "${d}"'s/^/#&/g' /etc/fstab
      fi
  done
}

## rename hostname
hostnamectl set-hostname master

## stop firewalld
systemctl stop firewalld
systemctl disable firewalld

## disable SELINUX
setenforce 0
sed -i "s/SELINUX=enforcing/SELINUX=disable/g" /etc/selinux/config
sed -i "s/SELINUX=permissive/SELINUX=disable/g" /etc/selinux/config

## off swap
offSwapFunc

## echo k8s.conf
mv -f /etc/sysctl.d/k8s.conf /etc/sysctl.d/k8s.conf.bk 2>/dev/null ||
modprobe br_netfilter
echo "net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1" >> /etc/sysctl.d/k8s.conf
sysctl -p /etc/sysctl.d/k8s.conf

## yum install docker
yum remove -y docker docker-common docker-selinux docker-engine
yum install -y yum-utils device-mapper-persistent-data lvm2
yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
yum install -y docker-ce-${docker_version} docker-ce-cli-${docker_version} containerd.io
mv -f /etc/docker/daemon.json /etc/docker/daemon.json.bk 2>/dev/null
echo '{
  "exec-opts": ["native.cgroupdriver=systemd"]
}' > /etc/docker/daemon.json
systemctl start docker

## yum install k8s
mv -f /etc/yum.repos.d/kubernetes.repo /etc/yum.repos.d/kubernetes.repo.bk 2>/dev/null
echo '[kubernetes]
name=Kubernetes
baseurl=http://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=http://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg
http://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg' > /etc/yum.repos.d/kubernetes.repo
yum install -y kubelet-${k8s_version} kubeadm-${k8s_version} kubectl-${k8s_version}

## yum install bash-completion
yum install -y bash-completion mlocate
updatedb
locate bash_completion /usr/share/bash-completion/bash_completion
line=$(sed -n '/bash_completion/=' /etc/profile)
if [[ -n "${line}" ]]; then
  sed -i -e "${line}"d /etc/profile
fi
line=$(sed -n '/kubectl completion bash/=' /etc/profile)
if [[ -n "${line}" ]]; then
  sed -i -e "${line}"d /etc/profile
fi
echo 'source /usr/share/bash-completion/bash_completion
source <(kubectl completion bash)' >> /etc/profile

## init k8s
sed -i -e s,192.168.0.1,"${ip}",g init/kube-init.yaml
kubeadm init --config=init/kube-init.yaml
line=$(sed -n '/export KUBECONFIG/=' /etc/profile)
if [[ -n "${line}" ]]; then
  sed -i -e "${line}"d /etc/profile
fi
echo "export KUBECONFIG=/etc/kubernetes/admin.conf" >> /etc/profile
kubectl apply -f init/calico.yaml

##
systemctl enable docker
systemctl enable kubelet
