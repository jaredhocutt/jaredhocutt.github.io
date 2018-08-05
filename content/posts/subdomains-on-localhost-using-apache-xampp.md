---
title: "Subdomains on localhost using Apache / XAMPP"
date: 2010-10-05
image: images/b-subdomains-on-localhost-using-apache-xampp.png
---

When I'm working on a new project, I often find myself wanting to setup a
subdomain (e.g. http://myproject.dev) in my local environment to use while
doing development. If you're using XAMPP (or standalone Apache), this is
actually a pretty easy thing to do.

These instructions should work in both Windows and Linux environments. I'll
attempt to make notes where things differ.

## Step 1

Setting up subdomains requires using a `VirtualHost` in Apache. The file to
edit is `httpd-vhosts.conf`.

* On Linux, this file should be located at `/opt/lampp/etc/extra/httpd-vhosts.conf`
* On Windows, this file should be located at `C:\xampp\apache\conf\extra\httpd-vhosts.conf`

There are two edits to make in `httpd-vhosts.conf`. The first edit to make is
to let Apache know that we want to use `VirtualHost`s. To do this uncomment
(or add) the following line:

{{< highlight apache >}}
NameVirtualHost *:80
{{< / highlight >}}

The second edit is to actually create our `VirtualHost`. To do this, add the
following to the end of `httpd-vhosts.conf`.

{{< highlight apache >}}
<VirtualHost *:80>
    ServerName localhost

    DocumentRoot "/opt/lampp/htdocs"
    DirectoryIndex index.php index.html

    <Directory "/opt/lampp/htdocs">
        Options Indexes FollowSymLinks Includes ExecCGI
        AllowOverride All
        Order allow,deny
        Allow from all
    </Directory>
</VirtualHost>

<VirtualHost *:80>
    ServerName myproject.dev

    DocumentRoot "/path/to/your/files"
    DirectoryIndex index.php index.html

    <Directory "/path/to/your/files">
        Options Indexes FollowSymLinks Includes ExecCGI
        AllowOverride All
        Order allow,deny
        Allow from all
    </Directory>
</VirtualHost>
{{< / highlight >}}

Note: The paths above are Unix paths. If you're using Windows,
`/opt/lampp/htdocs` should be `C:/xampp/htdocs` and `/path/to/your/files`
should be a Windows path with the exception that you should use forward slashes
instead of back slashes.

As you can see here, we've created two `VirtualHost`s. The first one is setup
so that going to http://localhost in your browser, continues to work as it
always has with XAMPP. The second one is our new subodmain. The important bits
to edit in the second one are as follows:

* `ServerName`: set this to the subdomain you want to access it by (in the
    example, you would go to http://myproject.dev).
* `DocumentRoot`: set this to where the files you want to serve are located.
* `Directory`: set this path to match the `DirectoryRoot`.

## Step 2

Next, we need to tell Apache to pay attention to what we have put in the
`httpd-vhosts.conf` file. XAMPP used to include this file by default, but newer
versions do not. The file we need to edit in order to do this is `httpd.conf`.

* On Linux, this file should be located at `/opt/lampp/etc/httpd.conf`
* On Windows, this file should be located at `C:/xampp/apache/conf/httpd.conf`

Near the bottom of the file, uncomment the line `Include etc/extra/httpd-vhosts.conf`.

{{< highlight apache >}}
# Virtual hosts
Include etc/extra/httpd-vhosts.conf
{{< / highlight >}}

## Step 3

Lastly, we need to tell our computer that when visiting http://myproject.dev
(or whatever subdomain you setup in Step 1). This is done via the hosts file.

* On Linux, this file should be located at `/etc/hosts`
* On Windows, this file should be located at `C:/Windows/System32/drivers/etc/hosts`

Edit the hosts file and add the following:

{{< highlight text >}}
127.0.0.1    myproject.dev
{{< / highlight >}}

## And we're done!

That's it! Restart XAMPP (Apache) and go to http://myproject.dev in your
browser to see your files. To add more subdomains in the future, just add a
`VirtualHost` in `httpd-vhosts.conf` and add the subdomain to your `hosts` file.
