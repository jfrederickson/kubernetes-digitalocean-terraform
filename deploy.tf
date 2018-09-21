###############################################################################
#
# A simple K8s cluster in DO
#
###############################################################################


###############################################################################
#
# Get variables from command line or environment
#
###############################################################################


# just set LINODE_TOKEN in the environment
variable "linode_token" {}

variable "linode_region" {
  default = "us-east"
}
variable "ssh_private_key" {
  default = "~/.ssh/id_rsa"
}
variable "ssh_public_key" {
  default = "~/.ssh/id_rsa.pub"
}

variable "number_of_workers" {
  default = "1"
}

variable "k8s_version" {
  default = "v1.10.3"
}

variable "cni_version" {
  default = "v0.6.0"
}

variable "prefix" {
  default = ""
}

variable "type_master" {
  default = "g6-standard-2"
}

variable "type_worker" {
  default = "g6-standard-2"
}

resource "random_string" "password" {
  length           = 16
  special          = true
  override_special = "/@\" "
}

###############################################################################
#
# Specify provider
#
###############################################################################


provider "linode" {
  token = "${var.linode_token}"
}


###############################################################################
#
# Master host
#
###############################################################################


resource "linode_instance" "k8s_master" {
  image = "linode/containerlinux"
  label = "${var.prefix}k8s-master"
  region = "${var.linode_region}"
  private_ip = true
  type = "${var.type_master}"
  authorized_keys = ["${chomp(file("~/.ssh/id_rsa.pub"))}"]
  // FIXME
  root_pass = "${random_string.password.result}"
  swap_size = 0

  provisioner "file" {
    source = "./00-master.sh"
    destination = "/tmp/00-master.sh"
    connection { user = "core" }
  }

  provisioner "file" {
    source = "./install-kubeadm.sh"
    destination = "/tmp/install-kubeadm.sh"
    connection { user = "core" }
  }

  # Install dependencies and set up cluster
  provisioner "remote-exec" {
    inline = [
      "export K8S_VERSION=\"${var.k8s_version}\"",
      "export CNI_VERSION=\"${var.cni_version}\"",
      "chmod +x /tmp/install-kubeadm.sh",
      "sudo -E /tmp/install-kubeadm.sh",
      "export MASTER_PRIVATE_IP=\"${self.private_ip_address}\"",
      "export MASTER_PUBLIC_IP=\"${self.ip_address}\"",
      "export MASTER_LABEL=\"${self.label}\"",
      "chmod +x /tmp/00-master.sh",
      "sudo -E /tmp/00-master.sh"
    ]
    connection { user = "core" }
  }

  # copy secrets to local
  provisioner "local-exec" {
    command =<<EOF
            scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${var.ssh_private_key} core@${linode_instance.k8s_master.ip_address}:"/tmp/kubeadm_join /etc/kubernetes/admin.conf" ${path.module}/secrets
            mv "${path.module}/secrets/admin.conf" "${path.module}/secrets/admin.conf.bak"
            sed -e "s/${self.private_ip_address}/${self.ip_address}/" "${path.module}/secrets/admin.conf.bak" > "${path.module}/secrets/admin.conf"
EOF
  }
}

###############################################################################
#
# Worker hosts
#
###############################################################################


resource "linode_instance" "k8s_worker" {
  count = "${var.number_of_workers}"
  image = "linode/containerlinux"
  label = "${var.prefix}${format("k8s-worker-%02d", count.index + 1)}"
  region = "${var.linode_region}"
  type = "${var.type_worker}"
  swap_size = 0
  private_ip = true
  # user_data = "${data.template_file.worker_yaml.rendered}"
  authorized_keys = ["${chomp(file("~/.ssh/id_rsa.pub"))}"]
  depends_on = ["linode_instance.k8s_master"]
  // FIXME
  root_pass = "${random_string.password.result}"

  # Start kubelet
  provisioner "file" {
    source = "./01-worker.sh"
    destination = "/tmp/01-worker.sh"
    connection { user = "core" }
  }

  provisioner "file" {
    source = "./install-kubeadm.sh"
    destination = "/tmp/install-kubeadm.sh"
    connection { user = "core" }
  }

  provisioner "file" {
    source = "./secrets/kubeadm_join"
    destination = "/tmp/kubeadm_join"
    connection { user = "core" }
  }

  # Install dependencies and join cluster
  provisioner "remote-exec" {
    inline = [
      "export K8S_VERSION=\"${var.k8s_version}\"",
      "export CNI_VERSION=\"${var.cni_version}\"",
      "chmod +x /tmp/install-kubeadm.sh",
      "sudo -E /tmp/install-kubeadm.sh",
      "export NODE_PRIVATE_IP=\"${self.private_ip_address}\"",
      "export NODE_LABEL=\"${self.label}\"",
      "chmod +x /tmp/01-worker.sh",
      "sudo -E /tmp/01-worker.sh"
    ]
    connection { user = "core" }
  }

  provisioner "local-exec" {
    when = "destroy"
    command = <<EOF
export KUBECONFIG=${path.module}/secrets/admin.conf
kubectl drain --delete-local-data --force --ignore-daemonsets ${self.name}
kubectl delete nodes/${self.name}
EOF
  }
}

# use kubeconfig retrieved from master

resource "null_resource" "deploy_microbot" {
  depends_on = ["linode_instance.k8s_worker"]
  provisioner "local-exec" {
    command = <<EOF
            export KUBECONFIG=${path.module}/secrets/admin.conf
            sed -e "s/\$EXT_IP1/${linode_instance.k8s_worker.0.ip_address}/" < ${path.module}/02-microbot.yaml > ./secrets/02-microbot.rendered.yaml
            until kubectl get pods 2>/dev/null; do printf '.'; sleep 5; done
            kubectl create -f ./secrets/02-microbot.rendered.yaml
EOF
  }
}

resource "null_resource" "deploy_linode_cloud_controller_manager" {
  depends_on = ["linode_instance.k8s_worker"]
  provisioner "local-exec" {
    command = <<EOF
            export KUBECONFIG=${path.module}/secrets/admin.conf
            sed -e "s/\$LINODE_TOKEN/${var.linode_token}/" < ${path.module}/03-linode-secret.yaml > ./secrets/03-linode-secret.rendered.yaml
            until kubectl get pods 2>/dev/null; do printf '.'; sleep 5; done
            kubectl create -f ./secrets/03-linode-secret.rendered.yaml
            kubectl create -f https://raw.githubusercontent.com/pharmer/cloud-controller-manager/master/hack/deploy/linode.yaml
EOF
  }
}

output "cmd" {
  value = "KUBECONFIG=secrets/admin.conf kubectl get nodes"
}

output "remote_cmd" {
  value = "ssh core@${linode_instance.k8s_master.ip_address} /opt/bin/kubectl --kubeconfig /etc/kubernetes/admin.conf get nodes"
}
