# Kubernetes - Linode - Terraform

Deploy your Kubernetes cluster on Linode using Terraform.

## Requirements

* [Linode](https://www.linode.com/) account
* Linode Personal Access Token [My Profile > API Tokens](https://cloud.linode.com/profile/tokens)
* [Terraform](https://www.terraform.io/)

### On Mac

With brew installed, all tools can be installed with

```bash
brew install terraform kubectl
```

Do all the following steps from a development machine. It does not matter _where_ it is, as long as it is connected to the internet. This one will be subsequently used to access the cluster via `kubectl`.

## Generate private / public keys

If you don't have an SSH RSA key, generate one:

```sh
[ -f ~/.ssh/id_rsa ] || ssh-keygen -t rsa -b 4096
```

The system will prompt you for a file path to save the key, we will go with `~/.ssh/id_rsa` in this tutorial.

## Add your public key in the Linode control panel

```sh
cat ~/.ssh/id_rsa.pub
```

[Add your SSH key here](https://cloud.linode.com/profile/keys). Click `Add a SSH Key`, label it, and paste in the public key.

## Add this key to your SSH agent

```bash
eval `ssh-agent -s`
ssh-add ~/.ssh/id_rsa
```

## Invoke Terraform

We put our Linode token in the file `./secrets/LINODE_TOKEN` (this directory is mentioned in `.gitignore`, of course, so we don't leak it)

Then we setup the environment variables (step into `this repository` root).

```bash
export TF_VAR_linode_token=$(cat ./secrets/LINODE_TOKEN)
export TF_VAR_ssh_fingerprint=$(ssh-keygen -E MD5 -lf ~/.ssh/id_rsa.pub | awk '{print $2}' | sed 's/MD5://g')
```

If you are using an older version of OpenSSH (<6.9), replace the last line with
```bash
export TF_VAR_ssh_fingerprint=$(ssh-keygen -lf ~/.ssh/id_rsa.pub | awk '{print $2}')
```

There is a convenience script for you in `./setup_terraform.sh`. Invoke it as

```bash
. ./setup_terraform.sh
```

Optionally, you can customize the datacenter *region* via:
```bash
export TF_VAR_linode_region=eu-west
```
The default region is `us-east`. You can find a list of available regions from [Linode](https://api.linode.com/v4/regions).

After setup, call `terraform apply`

```bash
terraform apply
```

That should do! `kubectl` is configured, so you can just check the nodes (`get no`) and the pods (`get po`).

```bash
$ KUBECONFIG=$PWD/secrets/admin.conf kubectl get no
NAME          LABELS                               STATUS
X.X.X.X   kubernetes.io/hostname=X.X.X.X   Ready     2m
Y.Y.Y.Y   kubernetes.io/hostname=Y.Y.Y.Y   Ready     2m

$ KUBECONFIG=$PWD/secrets/admin.conf kubectl --namespace=kube-system get po
NAME                                   READY     STATUS    RESTARTS   AGE
kube-apiserver-X.X.X.X                    1/1       Running   0          13m
kube-controller-manager-X.X.X.X           1/1       Running   0          12m
kube-proxy-X.X.X.X                        1/1       Running   0          12m
kube-proxy-X.X.X.X                        1/1       Running   0          11m
kube-proxy-X.X.X.X                        1/1       Running   0          12m
kube-scheduler-X.X.X.X                    1/1       Running   0          13m
```

You are good to go. Now, we can keep on reading to dive into the specifics.

### Setup `kubectl`

After the installation is complete, `terraform` will put the kubeconfig in `secrets/admin.conf`. Test your brand new cluster

```bash
KUBECONF=$PWD/secrets/admin.conf kubectl get nodes
```

You should get something similar to

```
$ kubectl get nodes
NAME          LABELS                               STATUS
X.X.X.X       kubernetes.io/hostname=X.X.X.X       Ready
```

### Deploy microbot with External IP

The file `04-microbot.yaml` will be rendered (i.e. replace the value `EXT_IP1`), and then `kubectl` will create the Service and Replication Controller.

To see the IP of the service, run `kubectl get svc` and look for the `EXTERNAL-IP` (should be the first worker's ext-ip).
