---
title: "NetApp Persistent Storage in Kubernetes: Using ONTAP and iSCSI"
date: 2016-04-13
image: images/b-netapp-persistent-storage-in-kubernetes-using-ontap.jpg
---

> This post is part of a multi-part series on how to use NetApp storage
> platforms to present persistent volumes in Kubernetes. The other posts in this series
> are:
>
> * [Part 1: Using ONTAP and NFS][part1]
> * [Part 2: Using ONTAP and iSCSI][part2]

[part1]: {{< relref "netapp-persistent-storage-in-kubernetes-using-ontap-and-nfs.md" >}}
[part2]: {{< relref "netapp-persistent-storage-in-kubernetes-using-ontap-and-iscsi" >}}

The Kubernetes `PersistentVolume` API provides several plugins for integrating
your storage into Kubernetes for containers to consume. In this post, we'll
focus on how to use the **iSCSI** plugin with ONTAP.

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

1. Create a Storage Virtual Machine (SVM) to host your iSCSI volumes
2. Enable iSCSI for the SVM created
3. Create a data LIF for Kubernetes to use
4. Create an initiator group
5. Add the Kubernetes host(s) to the initiator group
6. Create a volume for iSCSI LUNs
7. Create an iSCSI LUN for Kubernetes to use
8. Map the iSCSI LUN to the initiator group

Of course you can skip some of these steps if you already have what you need there.

Here is an example that follows these steps:

**Create a Storage Virtual Machine (SVM) to host your iSCSI volumes**

{{< highlight bash >}}
VSIM::> vserver create -vserver svm_kube_iscsi -subtype default -rootvolume svm_kube_iscsi_root -aggregate aggr1 -rootvolume-security-style unix -language C.UTF-8 -snapshot-policy default

VSIM::> vserver modify -vserver svm_kube_iscsi -aggr-list aggr1
{{< / highlight >}}

**Enable iSCSI for the SVM created**

{{< highlight bash >}}
VSIM::> vserver iscsi create -vserver svm_kube_iscsi
{{< / highlight >}}

**Create a data LIF for Kubernetes to use**

The values specified in this example is specific to our ONTAP simulator. Update
the appropriate values to match your environment.

{{< highlight bash >}}
VSIM::> network interface create -vserver svm_kube_iscsi -lif iscsi_data -role data -data-protocol iscsi -home-node VSIM-01 -home-port e0c -address 10.0.207.20 -netmask 255.255.255.0
{{< / highlight >}}

**Create an initiator group**

{{< highlight bash >}}
VSIM::> igroup create -igroup igroup_kube -protocol iscsi -ostype linux
{{< / highlight >}}

**Add the Kubernetes host(s) to the initiator group**

For each node in our Kubernetes cluster, we need to add it's `InitiatorName` to
the `igroup`. The initiator name can be found in the file
`/etc/iscsi/initiatorname.iscsi`. If this file does not exist, it's likely that
the iSCSI utilities have not been installed. See the
[Kubernetes setup](#setup_kubernetes) section for how to do this.

In our setup, the `InitiatorName` is `iqn.1994-05.com.redhat:27cc6d4e6da`. Update
the appropriate values to match your environment.

{{< highlight bash >}}
VSIM:>> igroup add -igroup igroup_kube -initiator iqn.1994-05.com.redhat:27cc6d4e6da
{{< / highlight >}}

**Create a volume for iSCSI LUNs**

{{< highlight bash >}}
VSIM::> volume create -volume vol_kube_iscsi -vserver svm_kube_iscsi -aggregate aggr1 -size 10GB
{{< / highlight >}}

**Create an iSCSI LUN for Kubernetes to use**

{{< highlight bash >}}
VSIM::> lun create -path /vol/vol_kube_iscsi/lun_kube_0001 -size 1GB -ostype linux
{{< / highlight >}}

**Map the iSCSI LUN to the initiator group**

{{< highlight bash >}}
VSIM:>> lun map -path /vol/vol_kube_iscsi/lun_kube_0001 -igroup igroup_kube
{{< / highlight >}}

Now that you have an iSCSI LUN to use in Kubernetes, we need to get the IQN of
our SVM because we'll need it in the later steps when using the storage in
Kubernetes.

Run the following command and take note of the **Target Name**. In our example
below, that value is `iqn.1992-08.com.netapp:sn.7dcf3853018611e6a3590800278b2267:vs.2`.

{{< highlight bash >}}
VSIM::> iscsi show -vserver svm_kube_iscsi

                 Vserver: svm_kube_iscsi
             Target Name: iqn.1992-08.com.netapp:sn.7dcf3853018611e6a3590800278b2267:vs.2
            Target Alias: svm_kube_iscsi
   Administrative Status: up
{{< / highlight >}}

### Kubernetes <a name="setup_kubernetes"></a>

To start, we need to install the needed iSCSI utilities on our Kubernetes nodes.

In our setup, the Vagrant box is using Fedora 23. The package to install
is `iscsi-initiator-utils`. Install the appropriate package for the OS running
on your Kubernetes nodes.

{{< highlight bash >}}
$ dnf install -y iscsi-initiator-utils
{{< / highlight >}}

In our example, we do not setup any authentication for the iSCSI LUN we created,
but if we had, we would need to also edit `/etc/iscsi/iscsid.conf` to match
the configuration.

Next, we need to let Kubernetes know about our iSCSI LUN. To do this, we will
create a `PersistentVolume` and a `PersistentVolumeClaim`.

Create a `PersistentVolume` definition and save it as `iscsi-pv.yaml`.

**iscsi-pv.yaml**

{{< highlight yaml >}}
apiVersion: v1
kind: PersistentVolume
metadata:
  name: kube_iscsi_0001
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  iscsi:
    targetPortal: "10.0.207.20:3260"  # set this to your data LIF IP address
    iqn: "iqn.1992-08.com.netapp:sn.7dcf3853018611e6a3590800278b2267:vs.2"
    lun: 0
    fsType: "ext4"
    readOnly: false
{{< / highlight >}}

Then create a `PersistentVolumeClaim` that uses the `PersistentVolume` and save
it as `iscsi-pvc.yaml`.

**iscsi-pvc.yaml**

{{< highlight yaml >}}
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: iscsi-claim1
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
{{< / highlight >}}

Now that we have a `PersistentVolume` definition and a `PersistentVolumeClaim`
definition, we need to create them in Kubernetes.

{{< highlight bash >}}
$ kubectl create -f iscsi-pv.yaml
$ kubectl create -f iscsi-pvc.yaml
{{< / highlight >}}

At this point, we can spin up a container that uses the `PersistentVolumeClaim`
we just created.

First, we'll setup a pod that we can use to write to an `output.txt` file
the current time and hostname of the pod.

Save the pod definition as `iscsi-busybox.yaml`.

**iscsi-busybox.yaml**

{{< highlight yaml >}}
apiVersion: v1
kind: Pod
metadata:
  name: iscsi-busybox
spec:
  containers:
  - image: busybox
    command:
      - sh
      - -c
      - 'tail -f /dev/null'
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

Create the pod in Kubernetes.

{{< highlight bash >}}
$ kubectl create -f iscsi-busybox.yaml
{{< / highlight >}}

Now that we've created our pod with the iSCSI volume attached, we can write
data to the volume to verify that everything is working as expected.

{{< highlight bash >}}
$ kubectl get pods
NAME            READY     STATUS    RESTARTS   AGE
iscsi-busybox   1/1       Running   0          34s

$ kubectl exec iscsi-busybox -- sh -c 'date > /mnt/output.txt'

$ kubectl exec iscsi-busybox -- cat /mnt/output.txt
Mon Apr 18 16:59:55 UTC 2016
{{< / highlight >}}

As can be seen, we have output the current date and time to `output.txt`. Next,
we'll stop this instance of the pod and create a new one and verify that our
data is still there.

{{< highlight bash >}}
$ kubectl get pods
NAME            READY     STATUS    RESTARTS   AGE
iscsi-busybox   1/1       Running   0          8m

$ kubectl delete -f iscsi-busybox.yaml
pod "iscsi-busybox" deleted

$ kubectl get pods

$ kubectl create -f iscsi-busybox.yaml
pod "iscsi-busybox" created

$ kubectl get pods
NAME            READY     STATUS    RESTARTS   AGE
iscsi-busybox   1/1       Running   0          31s

$ kubectl exec iscsi-busybox -- cat /mnt/output.txt
Mon Apr 18 16:59:55 UTC 2016
{{< / highlight >}}
