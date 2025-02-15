#cloud-config
write_files:
- content: |
    overlay
    br_netfilter
  path: /etc/modules-load.d/containerd.conf
- content: |
    net.bridge.bridge-nf-call-ip6tables = 1
    net.bridge.bridge-nf-call-iptables = 1
    net.ipv4.ip_forward = 1
  path: /etc/sysctl.d/k8s.conf
- content: |
    apiVersion: kubeadm.k8s.io/v1beta2
    kind: ClusterConfiguration
    kubernetesVersion: v{{.K8sVersion}}
    networking:
      podSubnet: "10.244.0.0/16"
  path: /tmp/kubeadm-config.yaml
- content: |
    [Service]
    Environment="KUBELET_EXTRA_ARGS=--cloud-provider=external"
  path: /etc/systemd/system/kubelet.service.d/20-hcloud.conf
- content: |
    alias k="kubectl"
    alias ksy="kubectl -n kube-system"
    alias kgp="kubectl get pods"
    alias kgs="kubectl get services"
    alias cilog="cat /var/log/cloud-init-output.log"
    export HCLOUD_TOKEN={{.HcloudToken}}
  path: /root/.bashrc
runcmd:
- export HOME=/root
- modprobe overlay
- modprobe br_netfilter
- sysctl --system
- apt install -y apt-transport-https curl
- curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
- echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list
- curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
- echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
- apt update
- apt install -y kubectl={{.K8sVersion}}-00 kubeadm={{.K8sVersion}}-00 kubelet={{.K8sVersion}}-00 containerd.io
- systemctl daemon-reload
- mkdir -p /etc/containerd
- containerd config default | tee /etc/containerd/config.toml
- systemctl restart containerd
- systemctl restart kubelet
# Download and install latest hcloud cli release for easier debugging on host
- curl -s https://api.github.com/repos/hetznercloud/cli/releases/latest | grep browser_download_url | grep linux-amd64 | cut -d '"' -f 4 | wget -qi -
- tar xvzf hcloud-linux-amd64.tar.gz && cp hcloud /usr/bin/hcloud && chmod +x /usr/bin/hcloud
{{if .IsClusterServer}}
- kubeadm init  --config /tmp/kubeadm-config.yaml
- mkdir -p /root/.kube
- cp -i /etc/kubernetes/admin.conf /root/.kube/config
- until KUBECONFIG=/root/.kube/config kubectl get node; do sleep 2;done
- KUBECONFIG=/root/.kube/config kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
- KUBECONFIG=/root/.kube/config kubectl -n kube-system patch ds kube-flannel-ds --type json -p '[{"op":"add","path":"/spec/template/spec/tolerations/-","value":{"key":"node.cloudprovider.kubernetes.io/uninitialized","value":"true","effect":"NoSchedule"}}]'
- KUBECONFIG=/root/.kube/config kubectl -n kube-system create secret generic hcloud --from-literal=token={{.HcloudToken}}
- KUBECONFIG=/root/.kube/config kubectl apply -f  https://raw.githubusercontent.com/hetznercloud/hcloud-cloud-controller-manager/master/deploy/ccm.yaml
- cd /root/ && curl  -s --location https://dl.k8s.io/v{{.K8sVersion}}/kubernetes-test-linux-amd64.tar.gz | tar --strip-components=3 -zxf - kubernetes/test/bin/e2e.test kubernetes/test/bin/ginkgo
- KUBECONFIG=/root/.kube/config kubectl taint nodes --all node-role.kubernetes.io/master-
- kubeadm token create --print-join-command >> /root/join.txt
{{else}}
- {{.JoinCMD}}
- sleep 10 # to get the joining work
{{end}}
