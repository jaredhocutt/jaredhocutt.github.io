---
title: "NetApp Persistent Storage in Kubernetes: Using ONTAP and NFS"
date: 2016-04-11
image: images/b-netapp-persistent-storage-in-kubernetes-using-ontap.jpg
---

> This post is part of a multi-part series on how to use NetApp storage
> platforms to present persistent volumes in Kubernetes. The other posts in this series
> are:
>
> * [Part 1: Using ONTAP and NFS][part1]
> * [Part 2: Using ONTAP and iSCSI][part2]

[part1]: {{< ref "netapp-persistent-storage-in-kubernetes-using-ontap-and-nfs.md" >}}
[part2]: {{< ref "netapp-persistent-storage-in-kubernetes-using-ontap-and-iscsi.md" >}}

Kubernetes is an open source project for automating deployment, operations, and
scaling of containerized applications that came out of Google in June 2014. The
community around Kubernetes has since exploded and is being adopted as one of
the leading container deployment solutions.

A problem many run into with using containerized applications is what to do
with their data. Data written inside of a container is ephemeral and only exist
for the lifetime of the container it's written in. To solve this problem,
Kubernetes offers a `PersistentVolume` subsystem that abstracts the details of
how storage is provided from how it is consumed.

The Kubernetes `PersistentVolume` API provides several plugins for integrating
your storage into Kubernetes for containers to consume. In this post, we'll
focus on how to use the **NFS** plugin with ONTAP. More specifically, we will
use a slightly modified version of the [NFS example][nfs_example]
in the Kubernetes source code.

[nfs_example]: https://github.com/kubernetes/kubernetes/tree/release-1.2/examples/nfs

<!--more-->

## Environment

### ONTAP

For this post, a single node clustered Data ONTAP 8.3 simulator was used. The
setup and commands used are no different than what would be used in a production
setup using real hardware.

### Kubernetes

In this setup, Kubernetes 1.2.2 was used in a single master and single node setup
running on VirtualBox using Vagrant. For tutorials on how to run Kubernetes in
nearly any configuration and on any platform you can imagine, check out the
[Kubernetes Getting Started guides][kube_getting_started].

[kube_getting_started]: http://kubernetes.io/docs/getting-started-guides/

## Setup

### ONTAP

The setup for ONTAP consists of the following steps.

1. Create a Storage Virtual Machine (SVM) to host your NFS volumes
2. Enable NFS for the SVM created
3. Create a data LIF for Kubernetes to use
4. Create an export policy to allow the Kubernetes hosts to connect
5. Create an NFS volume for Kubernetes to use

Of course you can skip some of these steps if you already have what you need there.

Here is an example that follows these steps:

**Create a Storage Virtual Machine (SVM) to host your NFS volumes**

{{< highlight bash >}}
VSIM::> vserver create -vserver svm_kube_nfs -subtype default -rootvolume svm_kube_nfs_root -aggregate aggr1 -rootvolume-security-style unix -language C.UTF-8 -snapshot-policy default

VSIM::> vserver modify -vserver svm_kube_nfs -aggr-list aggr1
{{< / highlight >}}

**Enable NFS for the SVM created**

{{< highlight bash >}}
VSIM::> vserver nfs create -vserver svm_kube_nfs -v3 disabled -v4.0 enabled -mount-rootonly disabled
{{< / highlight >}}

**Create a data LIF for Kubernetes to use**

The values specified in this example is specific to our ONTAP simulator. Update
the appropriate values to match your environment.

{{< highlight bash >}}
VSIM::> network interface create -vserver svm_kube_nfs -lif nfs_data -role data -data-protocol nfs -home-node VSIM-01 -home-port e0c -address 10.0.207.10 -netmask 255.255.255.0
{{< / highlight >}}

**Create an export policy to allow the Kubernetes hosts to connect**

In this case, we are allowing any host to connect by specifying `0.0.0.0/0` for
`clientmatch`. It's unlikely you'd want to do this in production and should
instead set the value to match the IP range of your Kubernetes hosts.

{{< highlight bash >}}
VSIM::> protocol export-policy rule create -vserver svm_kube_nfs -policyname default -protocol nfs4 -clientmatch 0.0.0.0/0 -rorule any -rwrule any
{{< / highlight >}}

**Create an NFS volume for Kubernetes to use**

{{< highlight bash >}}
VSIM::> volume create -volume kube_nfs_0001 -junction-path /kube_nfs_0001 -vserver svm_kube_nfs -aggregate aggr1 -size 1GB -type RW -unix-permissions ---rwxrwxrwx
{{< / highlight >}}

### Kubernetes

Now that we have an NFS volume, we need to let Kubernetes know about it. To do
this, we will create a `PersistentVolume` and a `PersistentVolumeClaim`.

Create a `PersistentVolume` definition and save it as `nfs-pv.yaml`.

**nfs-pv.yaml**

{{< highlight yaml >}}
apiVersion: v1
kind: PersistentVolume
metadata:
  name: kube_nfs_0001
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteMany
  nfs:
    server: 10.0.207.10  # set this to your data LIF IP address
    path: "/kube_nfs_0001"
{{< / highlight >}}

Then create a `PersistentVolumeClaim` that uses the `PersistentVolume` and save
it as `nfs-pvc.yaml`.

**nfs-pvc.yaml**

{{< highlight yaml >}}
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: nfs-claim1
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
{{< / highlight >}}

Now that we have a `PersistentVolume` definition and a `PersistentVolumeClaim`
definition, we need to create them in Kubernetes.

{{< highlight bash >}}
$ kubectl create -f nfs-pv.yaml
$ kubectl create -f nfs-pvc.yaml
{{< / highlight >}}

At this point, we can spin up a container that uses the `PersistentVolumeClaim`
we just created. To show this in action, we'll continue using the
[NFS example][nfs_example] from the Kubernetes source code.

First, we'll setup a "fake" backend that updates an `index.html` file every 5
to 10 seconds with the current time and hostname of the pod doing the update.

Save the "fake" backend as `nfs-busybox-rc.yaml`.

**nfs-busybox-rc.yaml**

{{< highlight yaml >}}
# This mounts the nfs volume claim into /mnt and continuously
# overwrites /mnt/index.html with the time and hostname of the pod.

apiVersion: v1
kind: ReplicationController
metadata:
  name: nfs-busybox
spec:
  replicas: 2
  selector:
    name: nfs-busybox
  template:
    metadata:
      labels:
        name: nfs-busybox
    spec:
      containers:
      - image: busybox
        command:
          - sh
          - -c
          - 'while true; do date > /mnt/index.html; hostname >> /mnt/index.html; sleep $(($RANDOM % 5 + 5)); done'
        imagePullPolicy: IfNotPresent
        name: busybox
        volumeMounts:
          # name must match the volume name below
          - name: nfs-claim1
            mountPath: "/mnt"
      volumes:
      - name: nfs-claim1
        persistentVolumeClaim:
          claimName: nfs-claim1
{{< / highlight >}}

Create the "fake" backend in Kubernetes.

{{< highlight bash >}}
$ kubectl create -f nfs-busybox-rc.yaml
{{< / highlight >}}

Next, we'll create a web server that also uses the NFS mount to serve the
`index.html` file being generated by the "fake" backend.

The web server consists of a pod definition and a service definition.

Save the pod definition as `nfs-web-rc.yaml`.

**nfs-web-rc.yaml**

{{< highlight yaml >}}
# This pod mounts the nfs volume claim into /usr/share/nginx/html and
# serves a simple web page.

apiVersion: v1
kind: ReplicationController
metadata:
  name: nfs-web
spec:
  replicas: 2
  selector:
    role: web-frontend
  template:
    metadata:
      labels:
        role: web-frontend
    spec:
      containers:
      - name: web
        image: nginx
        ports:
          - name: web
            containerPort: 80
        volumeMounts:
            # name must match the volume name below
            - name: nfs-claim1
              mountPath: "/usr/share/nginx/html"
      volumes:
      - name: nfs-claim1
        persistentVolumeClaim:
          claimName: nfs-claim1
{{< / highlight >}}

Save the service definition as `nfs-web-service.yaml`.

**nfs-web-service.yaml**

{{< highlight yaml >}}
kind: Service
apiVersion: v1
metadata:
  name: nfs-web
spec:
  ports:
    - port: 80
  selector:
    role: web-frontend
{{< / highlight >}}

Create the web server in Kubernetes.

{{< highlight bash >}}
$ kubectl create -f nfs-web-rc.yaml
$ kubectl create -f nfs-web-service.yaml
{{< / highlight >}}

Now that everything is setup and running, we can verify that it is working as
expected. Using the busybox container we launched earlier, we can make a request
to `nginx` to check that the data is being served properly.

{{< highlight bash >}}
$ kubectl get pod -lname=nfs-busybox
NAME                READY     STATUS    RESTARTS   AGE
nfs-busybox-1u136   1/1       Running   0          1m
nfs-busybox-gaqxs   1/1       Running   0          1m

$ kubectl get services nfs-web
NAME      CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
nfs-web   10.247.85.128   <none>        80/TCP    45s

$ kubectl exec nfs-busybox-1u136 -- wget -qO- http://10.247.85.128
Tue Apr 12 19:56:18 UTC 2016
nfs-busybox-gaqxs
{{< / highlight >}}

As can be seen in this example, when we made a request to `nginx`, the last pod
to have updated the `index.html` file was `nfs-busybox-gaqxs` at
`Tue Apr 12 19:56:18 UTC 2016`. We can continue to make a request to `nginx`
and watch this data get updated every 5-10 seconds.
