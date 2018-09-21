#!/usr/bin/bash
set -o nounset -o errexit

echo -e "\nAddress=${NODE_PRIVATE_IP}/17" >> /etc/systemd/network/05-eth0.network
systemctl daemon-reload
systemctl restart systemd-networkd

hostnamectl set-hostname ${NODE_LABEL} && hostname -F /etc/hostname

echo Environment=KUBELET_EXTRA_ARGS=--node-ip=${NODE_PRIVATE_IP} >> /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

systemctl daemon-reload

eval $(cat /tmp/kubeadm_join)
systemctl enable docker kubelet
