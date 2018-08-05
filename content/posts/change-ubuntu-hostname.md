---
title: "Change Ubuntu Hostname"
date: 2010-11-05
image: images/b-change-ubuntu-hostname.png
---

Have you ever set the hostname on your Ubuntu installation only to want to
change later? Here is an easy way to accomplish this and only requires changing
a single line in a configuration file.

To begin, open the file `/etc/hostname`:

{{< highlight bash >}}
sudo vim /etc/hostname
{{< / highlight >}}

Change the text in that file to what you would like your new hostname to be and
reboot your computer. After the computer reboots, you will have a new hostname!
