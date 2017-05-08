# Backups for OSC systems

This script backs up the systems that are on OSC's network.

# Requirements

* Sudo privileges on `stallman2`
* Stallman's root account have ssh keys to account `backups` on the remote servers.
* Remote `backups` accounts have sudo privileges to use `tar`, `cat /etc/apt/sources.list`, and `dpkg -l` with `NOPASSWD`
* Remote `root` accounts have ssh keys to account `backups` on `stallman2`

# Backup Directories Hierarchy

```
/srv/backups
├── online
│   ├── stallman2
│   │    ├── Father
│   │    ├── Grandfather
│   │    └── Son
│   ├── idle2
│   │    ├── Father
│   │    ├── Grandfather
│   │    └── Son
│   └── homedirs
└── offline
    ├── stallman2
    │    ├── Father
    │    ├── Grandfather
    │    └── Son
    ├── idle2
    │    ├── Father
    │    ├── Grandfather
    │    └── Son
    └── homedirs
```

# Running the Script

This script is meant to be run from `stallman2`, but can be run from any host that can act as a Command and Control machine, providing that it has enough space in `/srv`.

```
$ sudo osc-bups.sh
```

## Installation

Installing shell scripts are as easy as copying the file to the local `sbin` directory.

```
$ git clone https://github.com/smacz42/osc-bup
$ cd osc-bups
$ sudo cp -ar osc-bups.sh /usr/local/sbin/
```

## Directories

This script will create the majority of the directories necessary underneath the major ones - `/srv/backups/online` and `/srv/backups/offline`. Those you will have to make sure are present before running the script. If you don't, the script will throw an error and refuse to run until they are created.

## Flags

There are several flags that can be used to change the specifics of this script:

* `-t, --types TYPE[,TYPE...]`
    * Type of backup to do. Can be specified multiple times.
    * Valid `TYPE`s are:
        * online
        * offline (Not implemented yet)
        * cloud (Not implemented yet)
* `-d, --directory DIRECTORY`
    * Base directory for the b/up hierarchy. Does not take `/dev/sdX`, only a valid directory.
    * Is not valid when --type is only cloud.
* `-b, --boxens BOXEN[,BOXEN...]`
    * Boxens to backup. Can take `FQDN`s or IP addresses.
