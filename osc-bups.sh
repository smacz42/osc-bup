#!/bin/bash
#
# Template stolen from Steven W. Orr https://www.linuxjournal.com/content/asking-yesno-question-bash-script#comment-338999
#
# Author: AndrewCz
# License: GPLv3
#
# Usage: osc-bups.sh OPTIONS
#
#   Options:
#   -h, --help                      Displays usage() and exits
#   -t, --types TYPE[,TYPE...]      Type of backup to do. Can be specified multiple times Valid TYPE can be:
#                                       offline
#                                       online
#                                       cloud
#   -d, --directory DIRECTORY       Base directory for the b/up hierarchy. Does not take `/dev/sdX`, only a valid directory.
#                                   Is not valid when --type is only cloud.
#   -b, --boxens BOXEN[,BOXEN...]   Boxens to backup. Can take FQDNs or ip addresses.

# Set up warning and error. Why NOT make error call warning. Also note that there is never a good reason to refer
# to $*. Instead, always use "$@". And the cost savings of using >&2 instead of 1>&2 is just not worth it.
warning() { echo "$@" 1>&2; }
# Also, let's not forget that simple commands can be stacked into one command line.
error() { warning "$@"; exit 1; }

# Here we set usage up so that we can die with a bit more elegance.
usage() {
    warning "$@"
    cat <&2
Usage: "${prog}"
    [-h, --help]
    [-t, --types TYPE[,TYPE...]]; default=online,cloud
    [-d, --directory DIRECTORY]; default=/media/backups
    [-b, --boxens BOXEN[,BOXEN...]] default=stallman2,mail2,idle2
EOF
    exit 1
}

#
# Tarball a filesystem from a remote host onto the localhost filesystem
#
# Usage:
#       get_fs_tarball FS_NAME FS_PATH BOXEN DIRECTORY
#
# TODO: Make this able to use a remote host by specifying a remote fs, e.g:
#       --directory=root@backups:/srv/backups
#
#       Make this able to encrypt the backups using gpg
function get_fs_tarball() {
    local fs_name="$1"
    local fs_path="$2"
    local boxen="$3"
    local directory="$4"
    # makes tarball backup of root@"${boxen}"/${fs_path} at ${directory}/${boxen}/son/${fs_name}-MM-DD-YYYY.tar.gz
    if [[ ${boxen} == 'stallman2' ]]; then
        tar --directory="${directory}/${boxen}/Son" zxf "${fs_name}fs-$(date + '%Y-%m-%d').tar.gz" "${fs_path}"
    else
        ssh root@"${boxen}" "tar zcf - ${fs_path}" | tar --directory="${directory}/${boxen}/Son" zxf "${fs_name}fs-$(date + '%Y-%m-%d').tar.gz" -
    fi
}

#
# Backup to online hard drive.
#
# Usage:
#       onlinebup boxen directory
#
# Notes: Can be run anytime, as online backup should always be attached
function onlinebup() {
    local boxen="$1"
    local directory="$2"

    for fs in etc boot usr bin sbin srv; do
        get_fs_tarball ${fs} "/${fs}" "$1" "$2"
    done
    # Backup selected subdirectories of the /var filesystem. Specifically we're
    # targeting log, local, mail, and spool
    get_fs_tarball 'var' {/var/log,/var/local,/var/mail,/var/spool} "$2"

    # Homedirs
    for homedir in /home/*; do
        homedir=$(echo "${homedir}" | sed 's/\/home\///')
        if [[ "${homedir}" == 'lost+found' ]]; then
            echo "skipping ${homedir}"
            continue
        fi
        get_fs_tarball "${homedir}" "/home/${homedir}" "$1" "$2"
    done

    # Generate a list of all installed packages so that they can just be reinstalled
    # in the event of a restoration
    local packages="/tmp/packages.$$"
    if command -v dpkg; then
        cat /etc/apt/sources.list > "${packages}"
        dpkg -l >> "${packages}"
    elif command -v yum; then
        cat /etc/yum.repos.d/* > "${packages}"
        yum list >> "${packages}"
    elif command -v pacman; then
        cat /etc/pacman/mirrorlist > "${packages}"
        pacman -Q | cut -d \  -f1 >> "${packages}"
    fi
    scp -C -v -i /root/.ssh/id_rsa root@${boxen}:${packages} ${directory}/${boxen}/Son/packages.txt
}

#
# Test an IP address for validity:
#
# Usage:
#      valid_ip IP_ADDRESS
#      if [[ $? -eq 0 ]]; then echo good; else echo bad; fi
#   OR
#      if valid_ip IP_ADDRESS; then echo good; else echo bad; fi
#
function valid_ip() {
    local ip=$1
    local stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

#
# Procopt and sanity checks. Also calls the actual backup scripts
#
# Usage:
#
#
function osc-bups() {
    local types='online,cloud'
    local directory='/media/backups/'
    local boxens='stallman2,mail2,idle2'
    # BTW, NEVER give a variabel a one-letter name. It's hard to find them using any editor.

    temp=$(getopt -o :d:t:h --long default:,timeout:,help -n "${prog}" -- "$@")
    eval set -- "$temp"        # The double quotes are key here.
    shopt -s nocasematch       # Hey, this is bash. Let's not make life harder for ourselves.
                               # None of this checking to see if it's equal to y or to Y.
    while true
    do
        case "$1" in
            -t | --types)
                # No need to shift 1 to then get the value and then shift again. Just ref "$2" and then shift 2.
                types="$2"
                # Testing for valid argument - this should be on every case option
                [[ -z "${types}" || "${types}" == -* ]] && error '`-t` or `--types` was specified on the command line,
                    but no TYPE was given.'
                shift 2
                ;;

            -d | --directory)
                directory="$2"
                [[ -z "${directory}" || "${directory}" == -* ]] && error '`-d` or `--directory` was specified on the
                    command line, but no DIRECTORY was given.'
                shift 2
                ;;

            -b | --boxens)
                boxens="$2"
                [[ -z "${boxens}" || "${boxens}" == -* ]] && error '`-b` or `--boxens` was specified on the command
                    line, but no BOXENS were given.'
                shift 2
                ;;

            # These may come in helpful if/when a "management user" is set up on the boxens, but ATM I think it's just
            # going to be root
            #-i | --identity-file)
            #    [[ -z "${identity_file}" ]] && error '`-i` or `--identity-file` was specified on the command line, but
            #        no FILE was given.'
            #    shift 2
            #    ;;

            #-u | --user)
            #    [[ -z "${iientity_file}" ]] && error '`-u` or `--user` was specified on the command line, but no USER
            #        was given.'
            #    shift 2
            #    ;;

            -h | --help)
                usage "Here's what you need to do to run this: "
                ;;

            --)
                # This is how we get out of the options processing game.
                shift
                break
                ;;

            *)
                usage "$1: Heh, nope"
                ;;

        esac
    done

    # Now that we're done with the procopt then we can do the consistency checks.

    #
    # Types
    #

    # The following lines turn the string ${types} into a delineated list. Since we accept commas as
    # delimiters on the command line, we must change the IFS here, turn the string into a list, and then
    # responsibly return the IFS to what it was before.
    OIFS=$IFS
    IFS=','
    types=($types)
    IFS=$OIFS
    # Test to make sure the value of ${types} is ok
    for type in "${types[@]}"; do
        [[ "${type}" != 'cloud'
         && "${type}" != 'online'
         && "${type}" != 'offline' ]] && error "${type} not one of 'cloud', 'online', or 'offline'"
    done

    #
    # Directory
    #

    # Test if directory exists, throw error if false
    if [[ ! -d "${directory}" ]]; then
        error "${directory} was not found on this host."
    fi

    # TODO: Test for enough space on directory

    #
    # Boxens
    #

    # The following lines turn the string ${boxens} into a delineated list. Since we accept commas as
    # delimiters on the command line, we must change the IFS here, turn the string into a list, and then
    # responsibly return the IFS to what it was before.
    OIFS=$IFS
    IFS=','
    boxens=($boxens)
    IFS=$OIFS
    for boxen in "${boxens[@]}"; do
        #
        # Testing that the boxens resolve via getent
        #
        if valid_ip "$(getent hosts "${boxen}" | awk '{print $1}')"; then
            :
        else
            error "Unable to resolve ${boxen}"
        fi
        #
        # Testing that the boxens are reachable
        #
        if ping -q -c 5 "${boxen}" > /dev/null; then
            :
        else
            error "${boxen} not reachable with: $(which ping) -q -c 5 ${boxen}"
        fi
        #
        # Filesystem setup
        #
        local boxen_dir="${directory}/${boxen}"
        for gen in Son Father Grandfather; do
            if [[ ! -d "${boxen_dir}/${gen}" ]]; then
                mkdir -p "${boxen_dir}/${gen}"
            fi
        done
    done

    #
    # Main B/up loop
    #
    # TODO: Make this concurrent so it doesn't take all day
    for boxen in "${boxens[@]}"; do
        #
        # Age backups
        #
        # If the Son directory is empty, skip the aging process. That means that either 1) we've never made a backup
        # before, 2) We've already run this for this directory (which would be a bug), or 3) The last time we tried
        # this, it failed/was stopped for this box, and let's not age our backups out of existance
        if [[ "$(ls -A "${boxen_dir}/Son")" ]]; then
            # The oldest backup generation is to be removed before the new one is generated
            if [[ "$(ls -A "${boxen_dir}/Grandfather")" ]]; then
                rm -rf "${boxen_dir}/Grandfather/*"
            fi
            # The next two are meant to 'age' or advance the files to the next incarnation
            if [[ "$(ls -A "${boxen_dir}/Father")" ]]; then
                mv "${boxen_dir}/Father/*" "${boxen_dir}/Grandfather/"
            fi 
            # We don't need a test here, b/c we already did it before to get into this loop
            mv "${boxen_dir}/Son/*" "${boxen_dir}/Father"
        fi
        #
        # Online Backup
        #
        onlinebup "${boxen}" "${directory}"
        # offlinebup
        # cloudbup
    done
}

prog=$0
# This is just so you can see that you don't need basename and dirname. This is bash, not sh.
fn=${0##*/}
noshext=${fn%.sh}
# ATM this script must be run as root
if [[ ${EUID} != 0 ]]; then
    error "This script must be run as root"
fi
# Test for this being ran in a terminal
#if [ -v PS1 ]; then
#    :
#fi
# TODO: Verbosity
#   -v, --verbose                   Verbose output

# Also, note that I'm testing osc-bups, not 'osc-bups' and not "osc-bups". Don't interpolate if you don't have to..
if [[ ${noshext} == osc-bups ]]; then
    osc-bups "${@}"
fi
