#!/bin/bash -e
#
# ==============================================================================
# GNU-LDAP:
# LICENCE: GPL3
# ==============================================================================
#############################################################
## Root needed

if [ "`id -u`" != "0" ]; then
$CAT << _MSG
  ----------------------------------------
  | Error !!                             |
  | You need root permissions to install |
  | and configure openLDAP               |
  |                                      |
  | Stopping the installation process    |
  ----------------------------------------
_MSG
	exit 1
fi

####===============================================####

COMMAND=$1
DIRECTORY="$(pwd)"

# include the configuration set in install-ldap.conf
if [ -f $DIRECTORY/install-ldap.conf ] ; then
   . $DIRECTORY/install-ldap.conf
else
   echo "File $DIRECTORY/install-ldap.conf does not exists.";
   exit 1
fi

# functions script
if [ -f "$DIRECTORY/scripts/functions.sh" ] ; then
   . $DIRECTORY/scripts/functions.sh
else
   echo "Functions script not found, stopping...";
   exit 1
fi

# == main execution ==

usage() {
    echo "Usage: $(readlink -f $0) {install|uninstall|backup|test}"
    exit 0
}

help() {
    cat <<EOF

This script is a helper to install and configure openLDAP in
Debian systems.

The script will install openldap, configure DIT for ldap tree
overlays, logging and ACL.

REMEMBER: configure script in install-ldap.conf

install-ldap install"

EOF
}

# Main program

# In case no parameter was given
if [ $# = 0 ]; then
    usage
fi

## step 1: pre-configure
#
pre_configure() {
# mostrando un mapa basico de instalacion
test

## configurando archivos:

## eliminamos toda referencia erronea del /etc/hosts
$SED -i "/^$LAN_IPADDR*/d" /etc/hosts

# modificar /etc/hosts para incorporar resolucion de nombre de equipo
echo "# direccion ip del host" >> /etc/hosts
echo "$LAN_IPADDR  $SERVERNAME $HOSTNAME_PREFIX" >> /etc/hosts

# Defining the server name
echo "$SERVERNAME" > /etc/hostname
$HOSTNAME $SERVERNAME

# defining the domain name
$DOMAINNAME $DOMAIN

# restarting the service
/etc/init.d/hostname.sh start

# configure hosts for multi access
cat <<EOF > /etc/host.conf
multi on
order hosts,bind

EOF

# adding rules to hosts.allow
echo "slapd: $LAN_IPADDR" >> /etc/hosts.allow

# configure ldap.conf
cat <<EOF > /etc/ldap/ldap.conf
#
# LDAP Defaults
#
BASE    $LDAP_SUFFIX
URI     ldap://$SERVERNAME:389 ldaps://$SERVERNAME:636
SIZELIMIT       200
TIMELIMIT       30
EOF

echo
echo "Finalizing pre-configuration, installing..."
echo

}

## step 3: install LDAP
#
install() {
# pre-configure the installation
pre_configure

# installing utilities
setup_utilities

# installing LDAP server
ldap_setup

sleep 1

# ldap script
if [ -f "$DIRECTORY/scripts/ldap_functions.sh" ] ; then
   . $DIRECTORY/scripts/ldap_functions.sh
else
   echo "LDAP functions script not found, stop";
   exit 1
fi

# configure ldap server
ldap_configure

# configure logging
log_configure

sleep 1

# configure schemas
schema_configure

# Basic DIT configuration
dit_configure

# ACL configure
acl_configure

# configuramos SASL
sasl_configure

# seguridad SSL
ssl_configure

# configure dynamic modules
auditlog_configure
accesslog_configure
cnmonitor_configure

sleep 1
overlay_configure

echo
echo "Finalizing, restarting service..."
$LDAP_SERVICE restart
sleep 1

echo
echo " [ OpenLDAP Installed ]"
echo
echo "Reminder: the administrator bind dn is:"
echo "cn=admin,$LDAP_SUFFIX"
}

test() {
get_distro

# detection of the interface
firstdev
LAN_IPADDR="$($IP addr show $LAN_INTERFACE | awk "/^.*inet.*$LAN_INTERFACE\$/{print \$2}" | sed -n '1 s,/.*,,p')"

# name of the server
servername

# domain suffix
get_suffix

	$CAT << _MSG
 ************************** [ OpenLDAP Install ] *************************
 *
 * Distribution: .................. $DIST
 * Domain : ....................... $DOMAIN
 * LDAP Hostname : ................ $SERVERNAME
 * LDAP Suffix : .................. $LDAP_SUFFIX
 * Private Interface : ............ $LAN_INTERFACE
 * Private IP : ................... $LAN_IPADDR
 *
 ****************************************************************************
_MSG
}

uninstall() {
# info
get_distro
# uninstall
$INSTALLER remove --purge $PACKAGES $LDAP_SERVER $SASL_PKGS
$INSTALLER purge $LDAP_SERVER
# directory deletion
rm -fR /var/lib/ldap
}

### main execution program

case "$COMMAND" in
    -h|-help|--help)    help;;
    install)            install;;
    uninstall)          uninstall;;
    test)               test;;
    backup)             backup;;
    *)                  usage;;
esac

exit 0;
