#!/bin/bash


## commands #####
HOSTNAME="$(which hostname)"
DOMAINNAME="$(which domainname)"
CAT="$(which cat)"
GREP="$(which grep)"
AWK="$(which awk)"
SED="$(which sed)"
IP="$(which ip)"

## Packages handler #

# return distribution based lsb-release
function get_distro() {
  if [ -z $(which lsb_release) ]; then
    echo "Missing lsb-release, install before proceeding. Stopping install..."
    exit 1
  fi
  DIST=$(lsb_release -d | awk '{print $2}')
  if [ "$DIST"="Debian" ]; then
    INSTALLER="$(which aptitude) -y"
    LDAP_SERVICE="/usr/sbin/invoke-rc.d slapd"
    LDAP_DIRECTORY="/etc/ldap/slapd.d"
    LDAP_SERVER="slapd"
    LDAP_USER="openldap"
    LDAP_GROUP="openldap"
    ## packages to install #####
    PACKAGES="ldap-utils libsasl2-modules lsof openssl libslp1 ssl-cert"
    SASL_PKGS="sasl2-bin libsasl2-modules-ldap libsasl2-2"
  else
    INSTALLER="$(which aptitude) -y"
    LDAP_SERVICE="/etc/init.d/slapd"
    LDAP_DIRECTORY="/etc/ldap/slapd.d"
    LDAP_SERVER="slapd"
    LDAP_USER="openldap"
    LDAP_GROUP="openldap"
    ## packages to install #####
    PACKAGES="ldap-utils libsasl2-modules lsof openssl libslp1 ssl-cert"
    SASL_PKGS="sasl2-bin libsasl2-modules-ldap libsasl2-2"
  fi
}

# returns base suffix
function get_suffix() {
  if [ -z "$LDAP_SUFFIX" ]; then
    old_ifs=${IFS}
    IFS="."
    for component in $DOMAIN; do
      result="$result,dc=$component"
    done
    IFS="${old_ifs}"
    LDAP_SUFFIX="${result#,}"
  fi
  return 0
}

function setup_utilities() {
  if [ "$DIST"="Debian" ]; then
    # install dependencies
    export "DEBIAN_FRONTEND=noninteractive"
    $INSTALLER install $PACKAGES
    if [ "$?" -ne "0" ]; then
      echo "Install of necessary packages did not complete, stopping install..."
      exit 1
    fi
  else
    echo "Install not supported for other distribution, stopping install..."
    exit 1
  fi
  return 0
  }

# install required packages
function ldap_setup() {
  if [ "$DIST"="Debian" ]; then
    # install LDAP server
    export "DEBIAN_FRONTEND=noninteractive"
    $INSTALLER install $LDAP_SERVER
    if [ "$?" -ne "0" ]; then
      echo "OpenLDAP install did not complete, stopping setup process..."
      exit 1
    fi
  else
    echo "Install not supported on other distributions, stopping setup process..."
    exit 1
  fi
  return 0
}


## Basic Functions

function ifdev() {
  IF=(`cat /proc/net/dev | grep ':' | cut -d ':' -f 1 | tr '\n' ' '`)
}

function firstdev() {
  ifdev
  LAN_INTERFACE=${IF[1]}
}

function get_domain() {
  if [ "$DOMAIN"="" ]; then
    _DOMAIN_=`$HOSTNAME -d`
    if [ -z "$_DOMAIN_" ]; then
      echo -n "Name of the domain not defined, enter a valid one [example.com]: "
      read _DOMAIN_
      if [ ! -z "$_DOMAIN_" ]; then
        DOMAIN=$_DOMAIN_
      else
        echo "Error: it must define a TLD"
        exit 1
      fi
    else
      #using host's configured domain
      DOMAIN=$_DOMAIN_
    fi
  fi
  return 0
}

function get_hostname() {
  if [ -z "$HOSTNAME_PREFIX" ]; then
    _HOST_=`$HOSTNAME -s`
    if [ -z "$_HOST_" ]; then
      echo -n "Hostname missing: What hostname do you wish for this directory server? [$HOSTNAME_PREFIX]: "
      read _HOSTNAME_
      if [ ! -z "$_HOSTNAME_" ]; then
        HOSTNAME_PREFIX=$_HOSTNAME_
      else
        echo "Hostname missing: missing server name"
        exit 1
      fi
    else
      HOSTNAME_PREFIX=$_HOST_
    fi
  fi
  return 0
}

function servername() {
  get_hostname
  if [ "$?" -ne "0" ]; then
    echo "Error calling the function get_hostname, stopping setup process..."
    exit 1
  fi
  get_domain
  if [ "$?" -ne "0" ]; then
    echo "Error calling the function get_domain, stopping setup process..."
    exit 1
  fi
  SERVERNAME="$HOSTNAME_PREFIX.$DOMAIN"
}

function get_admin_password() {
  echo
  echo "Administrator account"
  echo
  echo "The administrator account for this LDAP is: "
  echo "cn=admin,$LDAP_SUFFIX"
  echo
  echo "The administrator for cn=config is:"
  echo "cn=admin,cn=config"
  echo "Please, type in a password for current admin account:"
  while /bin/true; do
    echo -n "New password: "
    stty -echo
    read pass1
    stty echo
    echo
    if [ -z "$pass1" ]; then
      echo "Error, password cannot be empty"
      echo
      continue
    fi
    echo -n "Repeat new password: "
    stty -echo
    read pass2
    stty echo
    echo
    if [ "$pass1" != "$pass2" ]; then
      echo "Error, passwords don't match"
      echo
      continue
    fi
    PASS="$pass1"
    break
  done
  if [ -n "$PASS" ]; then
    return 0
  fi
  return 1
}

## end functions ####
