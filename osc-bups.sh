#!/bin/bash
#
# Template stolen from Steven W. Orr https://www.linuxjournal.com/content/asking-yesno-question-bash-script#comment-338999
#
# Author: AndrewCz
# License: GPLv3
#
# TODO:
#   * Encrypt backups
#   * Exclude /home from `--directories` option
#   * Separate `/home` backup
#
# Usage: osc-bups.sh OPTIONS
#
#   Options:
#   -h, --help                      Displays usage() and exits
#   -t, --types TYPE[,TYPE...]      Type of backup to do. Can be specified multiple times Valid TYPE can be:
#                                       online
#                                       offline (Not implemented yet)
#                                       cloud (Not implemented yet)
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
    \[-h, --help]
    \[-t, --types TYPE[,TYPE...]]; default=online
    \[-d, --directory DIRECTORY]; default=/srv/backups
    \[-b, --boxens BOXEN[,BOXEN...]] default=stallman2,mail2,idle2
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
#       --directory=backups@backups:/srv/backups
#
#       Make this able to encrypt the backups using gpg
#
# Note: This necessitates that backups have the ability to `sudo tar`, which is exposing the entirety of the filesystem
#       to backups with sudo privleges. We may want to tarball locally first or pursue some alternative way to securing
#       this. However, since it's done over ssh there's not so much that I would be worried about for the time being.
function get_fs_tarball() {
    local fs_name="$1"
    local fs_path="$2"
    local boxen="$3"
    local directory="$4"
    # makes tarball backup of backups@"${boxen}"/${fs_path} at ${directory}/${boxen}/son/${fs_name}-MM-DD-YYYY.tar.gz
    if [[ ${boxen} == "$(hostname)" ]]; then
        echo "START: Tarballing ${fs_path} on ${boxen}"
        tar -czf "${directory}/${boxen}/Son/${fs_name}fs-$(date +%Y-%m-%d).tar.gz" "${fs_path}"
        echo "END: Tarballing ${fs_path} on ${boxen}"
    else
        echo "START: Tarballing ${fs_path} on ${boxen}"
        ssh -q "backups@${boxen}" "sudo tar -czf - ${fs_path}" > "${directory}/${boxen}/Son/${fs_name}fs-$(date +%Y-%m-%d).tar.gz"
        echo "END: Tarballing ${fs_path} on ${boxen}"
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
    local boxen="${1}"
    local directory="${2}/online"

    for fs in etc boot usr bin sbin var; do
        get_fs_tarball ${fs} "/${fs}" "${boxen}" "${directory}"
    done

    # Generate a list of all installed packages so that they can just be reinstalled
    # in the event of a restoration.
    # For future reference, CentOS/RHEL and Arch equivalent commands are given in the comments below
    # Right now, we're assuming that all the package managers are dpkg/apt
    local packages="${directory}/${boxen}/Son/packages.txt"
    if [[ ${boxen} == $(hostname) ]]; then
        echo "Gathering package info from dpkg on ${boxen}"
        cat /etc/apt/sources.list > "${packages}"
        dpkg -l >> "${packages}"
    elif [[ ${boxen} == 'torvalds' ]]; then
        echo "Gathering package info from dpkg on ${boxen}"
        ssh -p 122 -q "backups@${boxen}" "sudo cat /etc/apt/sources.list" > "${packages}"
        ssh -p 122 -q "backups@${boxen}" "sudo dpkg -l" >> "${packages}"
    else
        echo "Gathering package info from dpkg on ${boxen}"
        ssh -q "backups@${boxen}" "sudo cat /etc/apt/sources.list" > "${packages}"
        ssh -q "backups@${boxen}" "sudo dpkg -l" >> "${packages}"
    fi

    # if ssh -q ${boxen} command -v dpkg; then
    #     cat /etc/apt/sources.list > "${packages}"
    #     dpkg -l >> "${packages}"
    # elif command -v yum; then
    #     cat /etc/yum.repos.d/* > "${packages}"
    #     yum list >> "${packages}"
    # elif command -v pacman; then
    #     cat /etc/pacman/mirrorlist > "${packages}"
    #     pacman -Q | cut -d \  -f1 >> "${packages}"
    # fi
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
    # online, offline, cloud
    local types='online'
    local directory='/srv/backups'
    # stallman2, mail2, idle2, web3, ldap
    local boxens='stallman2,mail2,idle2'
    # BTW, NEVER give a variable a one-letter name. It's hard to find them using any editor.

    temp=$(getopt -o :t:d:b:v:h --long types:,directory:,boxens:,verbose:,help -n "${prog}" -- "$@")
    eval set -- "$temp"        # The double quotes are key here, but the `--` really fucks with my syntax highlighter
    shopt -s nocasematch       # Hey, this is bash. Let's not make life harder for ourselves.

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

            -v | --verbose)
                set -x
                shift 2
                ;;

            # These may come in helpful if/when a "management user" is set up on the boxens, but ATM I think it's just
            # going to be backups
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
                error "$1: Heh, nope"
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

    # Test if directories exists, throw error if false
    for type in "${types[@]}"; do
        [[ "${type}" == 'cloud' ]] && continue
        if [[ ! -d "${directory}/${type}" ]]; then
            error "${directory}/${type} was not found on this host."
        fi
    done

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
        if [[ "${boxen}" != "$(hostname)" ]]; then
            echo "testing connectivity for ${boxen}"
            #
            # Testing that the boxens resolve via getent
            #
            if ! valid_ip "$(getent hosts "${boxen}" | awk '{print $1}')"; then
                error "Unable to resolve ${boxen}"
            fi
            #
            # Testing that the boxens are reachable
            #
            if ! ping -q -c 5 "${boxen}" > /dev/null; then
                error "${boxen} not reachable with: $(which ping) -q -c 5 ${boxen}"
            fi
            echo "Connectivity confirmed"
        fi

        #
        # Filesystem setup
        #
        for type in "${types[@]}"; do
            [[ "${type}" == 'cloud' ]] && continue
            local boxen_dir="${directory}/${type}/${boxen}"
            for gen in Son Father Grandfather; do
                if [[ ! -d "${boxen_dir}/${gen}" ]]; then
                    echo "making ${boxen_dir}/${gen} directory"
                    mkdir -p "${boxen_dir}/${gen}"
                fi
            done
        done
    done
    #
    # Confirmation
    #
    # confirm the variables and check for root key
    #echo "Please confirm the variables"
    #echo "      boxens = ${boxens[*]}"
    #echo "      directory = ${directory}"
    #echo "      types = ${types[*]}"
    #sleep 2
    #read -p "Press [Enter] key to confirm..."

    #
    # Main B/up loop
    #
    # TODO: Make this concurrent so it doesn't take all day
    for type in "${types[@]}"; do
        # change this to `cloudbup && continue` instead of waiting till the end of the function to call it
        [[ "${type}" == 'cloud' ]] && continue
        for boxen in "${boxens[@]}"; do
            boxen_dir="${directory}/${type}/${boxen}"

            #
            # Age backups
            #
            # If the Son directory is empty, skip the aging process. That means that either 1) we've never made a backup
            # before, 2) We've already run this for this directory (which would be a bug), or 3) The last time we tried
            # this, it failed/was stopped for this box, and let's not age our backups out of existance
            if [[ "$(ls -A "${boxen_dir}/Son")" ]]; then
                # The oldest backup generation is to be removed before the new one is generated
                if [[ "$(ls -A "${boxen_dir}/Grandfather")" ]]; then
                     echo "Killing off Grandfather for ${boxen}"
                    # Time to lay some pipes
                     echo "Date of snapshot: $(find "${boxen_dir}/Grandfather/" -type f |\
                         sort -n | head -1 | rev | cut -d - -f 1-3 | rev | cut -d \. -f 1)"
                    rm -rf "${boxen_dir}"/Grandfather/*
                fi
                # The next two are meant to 'age' or advance the files to the next incarnation
                if [[ "$(ls -A "${boxen_dir}/Father")" ]]; then
                     echo "Aging Father for ${boxen} to Grandfather"
                     echo "Date of snapshot: $(find "${boxen_dir}/Father/" -type f |\
                         sort -n | head -1 | rev | cut -d - -f 1-3 | rev | cut -d \. -f 1)"
                    mv "${boxen_dir}"/Father/* "${boxen_dir}/Grandfather/"
                fi
                # We don't need a test here, b/c we already did it before to get into this loop
                 echo "Aging Son for ${boxen} to Father"
                 echo "Date of snapshot: $(find "${boxen_dir}/Son/" -type f |\
                     sort -n | head -1 | rev | cut -d - -f 1-3 | rev | cut -d \. -f 1)"
                mv "${boxen_dir}"/Son/* "${boxen_dir}/Father"
            fi

            #
            # Online Backup
            #
            # Put a `&` at the end of here to parallelize it
            [[ "${type}" == 'online' ]] && onlinebup "${boxen}" "${directory}"
            # [[ "${type}" == 'online' ]] offlinebup
        done

        #
        # Homedirs
        #
        # TODO: Delete old account tarball before creating the new one
        for homedir in /home/*; do
            account=$(basename ${homedir})
            if [[ "${account}" == 'lost+found' ]]; then
                echo "skipping ${account}"
                continue
            fi
            # Really only the first run, but just in case
            if [[ ! -d "${directory}/${type}/homedirs" ]]; then
                echo "making homedirs directory"
                mkdir -p "${directory}/${type}/homedirs"
            fi
            # The ending period is to capture hidden as well as visible directores in the homedir
            echo "Tarballing ${account}'s homedir"
            tar -czf "${directory}/${type}/homedirs/${account}-$(date +%Y-%m-%d).tar.gz" "${homedir}/."
        done
    done

    #
    # Permissions reset
    #
    # TODO: This script should be architected so that this step isn't necessary
    chown -R backups:backups /srv/backups
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
# TODO: Bash set options
# set -e
# set -x
#if [[ $(set -o | grep xtrace | tr -s ' ' | cut -d \  -f 2) == "on" ]]; then
#    set +x
#fi

# Also, note that I'm testing osc-bups, not 'osc-bups' and not "osc-bups". Don't interpolate if you don't have to..
if [[ ${noshext} == osc-bups ]]; then
    osc-bups "${@}"
fi

