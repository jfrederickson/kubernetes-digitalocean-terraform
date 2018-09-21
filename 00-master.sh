#!/usr/bin/bash
set -o nounset -o errexit

echo -e "\nAddress=${MASTER_PRIVATE_IP}/17" >> /etc/systemd/network/05-eth0.network
systemctl daemon-reload
systemctl restart systemd-networkd

hostnamectl set-hostname ${MASTER_LABEL} && hostname -F /etc/hostname

systemctl stop update-engine

kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=${MASTER_PRIVATE_IP} --apiserver-cert-extra-sans=${MASTER_PUBLIC_IP}
kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f https://raw.githubusercontent.com/coreos/flannel/v0.9.1/Documentation/kube-flannel.yml
systemctl enable docker kubelet

# used to join nodes to the cluster
kubeadm token create --print-join-command > /tmp/kubeadm_join

# used to setup kubectl 
chown core /etc/kubernetes/admin.conf

systemctl start update-engine
