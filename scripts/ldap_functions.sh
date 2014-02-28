#!/bin/bash


# ldap_functions

## ldap commands #######

SLAPADD="$(which slapadd)"
SLAPPASSWD="$(which slappasswd)"
SLAPINDEX="$(which slapindex) -F $LDAP_DIRECTORY -n 2"
SLAPTEST="$(which slaptest) -d2 -u"
SLAPACL="$(which slapacl) -F $LDAP_DIRECTORY -v"

LDAPADD="$(which ldapadd) -H ldapi:/// -Y EXTERNAL -Q"
LDAPADDUSER="$(which ldapadd) -H ldapi:/// -x "
LDAPSEARCH="$(which ldapsearch) -H ldapi:///"

#############################################################

# configure basic ldap (cn=admin, cn=config, schemas, database)
function ldap_configure() {
echo
echo " == OpenLDAP configuration == "
echo

# configure /etc/default/slapd
sed -i "s/SLAPD_SERVICES=\"ldap:\/\/\/ ldapi:\/\/\/\"/SLAPD_SERVICES=\"ldap:\/\/\/ ldapi:\/\/\/ ldaps:\/\/\/\"/g" /etc/default/$LDAP_SERVER

# define LDAP admin passowrd for cn=admin,cn=config
get_admin_password

echo "Password Hash :"
echo `$SLAPPASSWD -uvs $PASS`
echo

## Final setup tests
# Verifying correct configuration
$SLAPTEST -F $LDAP_DIRECTORY
if [ "$?" -ne "0" ]; then
  echo "Incorrect configuration, please check OpenLDAP configuration files."
  exit 1
fi

# configuracion basica de cn=config
$LDAPADD << EOF
dn: cn=config
changetype: modify
replace: olcToolThreads
olcToolThreads: 8
-
replace: olcThreads
olcThreads: 32
-
replace: olcSockbufMaxIncoming
olcSockbufMaxIncoming: 262143
-
replace: olcSockbufMaxIncomingAuth
olcSockbufMaxIncomingAuth: 16777215
-
replace: olcReadOnly
olcReadOnly: FALSE
-
replace: olcReverseLookup
olcReverseLookup: FALSE
-
replace: olcServerID
olcServerID: 1 ldap://$SERVERNAME
EOF

# configuration of olcDatabase
$LDAPADD << EOF
dn: olcDatabase={0}config,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: `$SLAPPASSWD -uvs $PASS`
-
replace: olcAccess
olcAccess: {0}to * by dn.exact=gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth manage by * break
olcAccess: {1}to dn="" by * read
olcAccess: {2}to dn.subtree="" by * read
olcAccess: {3}to dn="cn=Subschema" by * read
EOF

# loading necessary modules
$LDAPADD << EOF
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleload: back_bdb
olcModuleload: unique
olcModuleload: back_ldap
olcModuleload: dynlist
olcModuleload: refint
olcModuleload: constraint
olcModuleload: valsort
olcModuleload: memberof
EOF

# tunning de la DB
$LDAPADD << EOF
dn: olcDatabase={1}hdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: `$SLAPPASSWD -uvs $PASS`
-
replace: olcLastMod
olcLastMod: TRUE
-
replace: olcAddContentAcl
olcAddContentAcl: TRUE
-
replace: olcSizeLimit
olcSizeLimit: 2000
-
replace: olcTimeLimit
olcTimeLimit: 60
-
replace: olcDbIDLcacheSize
olcDbIDLcacheSize: 500000
-
replace: olcDbCacheFree
olcDbCacheFree: 1000
-
replace: olcDbDNcacheSize
olcDbDNcacheSize: 0
-
replace: olcDbCacheSize
olcDbCacheSize: 5000
-
replace: olcDbCheckpoint
olcDbCheckpoint: 1024 30
-
replace: olcDbConfig
olcDbConfig: {0}set_cachesize 0 10485760 0
olcDbConfig: {1}set_lk_max_objects 1500
olcDbConfig: {2}set_lk_max_locks 1500
olcDbConfig: {3}set_lk_max_lockers 1500
olcDbConfig: {4}set_lg_bsize 2097152
olcDbConfig: {5}set_flags DB_LOG_AUTOREMOVE
EOF
}

function schema_configure() {
echo
echo " == Schemas configuration == "
echo
# Stopping LDAP service
$LDAP_SERVICE stop
# Removing existing schemas
rm $LDAP_DIRECTORY/cn\=config/cn\=schema/*
# Copying new schemas
cp $DIRECTORY/data/schemas/* $LDAP_DIRECTORY/cn\=config/cn\=schema/
# Assigning owner to copied directory : openldap
chown $LDAP_USER:$LDAP_GROUP $LDAP_DIRECTORY -R
# verifying configuration
$SLAPTEST -F $LDAP_DIRECTORY
if [ "$?" -ne "0" ]; then
  echo "Incorrect configuration, please check the logs"
  exit 1
fi
# If everything went fine, resume the service
$LDAP_SERVICE start
sleep 1
# Indexing
$LDAPADD << EOF
dn: olcDatabase={1}hdb,cn=config
changetype: modify
replace: olcDbIndex
olcDbIndex: telephoneNumber eq,sub,pres
olcDbIndex: cn,sn,ou,o eq,pres,sub,subinitial
olcDbIndex: mail pres,eq,sub
EOF
}

function sasl_configure() {
echo
echo " == SASL Security == "
echo
# instaling SASL
$INSTALLER install $SASL_PKGS
sleep 1
# configure SASL authentication daemon
$SED -i 's/START=no/START=yes/g' /etc/default/saslauthd
$SED -i "s/MECHANISMS=.*$/MECHANISMS=\"ldap\"/g" /etc/default/saslauthd

# configuramos saslauthd
cat <<EOF > /etc/saslauthd.conf
ldap_servers: ldap://$SERVERNAME/
ldap_auth_method: bind
ldap_bind_dn: cn=admin,$LDAP_SUFFIX
ldap_bind_pw: $PASS
ldap_version: 3
ldap_search_base: $LDAP_SUFFIX
ldap_filter: (uid=%U)
ldap_verbose: on
ldap_scope: sub
 #SASL info
ldap_default_realm: $DOMAIN
ldap_use_sasl: no
ldap_debug: 3
EOF

# Restarting the service
/etc/init.d/saslauthd restart
# SASL configuration in LDAP

$LDAPADD << EOF
dn: cn=config
changetype:modify
replace: olcPasswordHash
olcPasswordHash: {SSHA}
-
replace: olcSaslSecProps
olcSaslSecProps: noplain,noanonymous,minssf=56
-
replace: olcAuthzPolicy
olcAuthzPolicy: none
-
replace: olcConnMaxPendingAuth
olcConnMaxPendingAuth: 1000
-
replace: olcSaslHost
olcSaslHost: $SERVERNAME
-
replace: olcSaslRealm
olcSaslRealm: $DOMAIN
EOF

# SASL configuration for the DB
$LDAPADD << EOF
dn: cn=config
changetype: modify
replace: olcAuthzRegexp
olcAuthzRegexp: uid=(.*),cn=.*,cn=.*,cn=auth ldap:///??sub?(uid=$1)
EOF

# Checking access to SASL authentication mecanisms
echo
echo "Checking access to SASL authentication mecanisms "
echo
$LDAPSEARCH -x -b '' -s base -LLL supportedSASLMechanisms
if [ "$?" -ne "0" ]; then
   echo "Error: no access to SASL authentication"
   exit 1
fi
}

function ssl_configure() {
# Create ssl folder
mkdir /etc/ldap/ssl -p

# copiamos los certificados Debian basicos:
if [ -f "/etc/ssl/certs/ssl-cert-snakeoil.pem" ]; then
cp /etc/ssl/certs/ssl-cert-snakeoil.pem /etc/ldap/ssl
fi

if [ -f "/etc/ssl/private/ssl-cert-snakeoil.key" ]; then
cp /etc/ssl/private/ssl-cert-snakeoil.key /etc/ldap/ssl
fi

if [ -f "/etc/ssl/certs/ca.pem" ]; then
cp /etc/ssl/certs/ca.pem /etc/ldap/ssl
fi

$LDAPADD << EOF
dn: cn=config
changetype:modify
replace: olcLocalSSF
olcLocalSSF: 128
-
replace: olcSecurity

-
replace: olcTLSCACertificateFile
olcTLSCACertificateFile: /etc/ldap/ssl/ca.pem
-
replace: olcTLSCertificateFile
olcTLSCertificateFile: /etc/ldap/ssl/ssl-cert-snakeoil.pem
-
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/ldap/ssl/ssl-cert-snakeoil.key
-
replace: olcTLSVerifyClient
olcTLSVerifyClient: never
-
replace: olcTLSCipherSuite
olcTLSCipherSuite: +RSA:+AES-256-CBC:+SHA1
EOF
}

function log_configure() {
echo
echo " == Logging configuration == "
echo
# crear carpeta para logging
if [ ! -d "/var/log/slapd" ]; then
  mkdir /var/log/slapd
fi
chmod 755 /var/log/slapd/
chown $LDAP_USER:$LDAP_GROUP /var/log/slapd/ -R
# Redirect all log files through rsyslog.
sed -i "/local4.*/d" /etc/rsyslog.conf

# si no se encuentra la linea, se agrega a rsyslog
if [ `cat /etc/rsyslog.conf | grep slapd.log | wc -l` == "0" ]; then
cat >> /etc/rsyslog.conf << EOF
local4.*                        /var/log/slapd/slapd.log
EOF
fi

# configurando el log del LDAP
$LDAPADD << EOF
dn: cn=config
changetype:modify
replace: olcLogFile
olcLogFile: /var/log/slapd/slapd.log
EOF

# configurando nivel de logging
$LDAPADD << EOF
dn: cn=config
changetype:modify
replace: olcLogLevel
olcLogLevel: config stats shell
-
replace: olcIdleTimeout
olcIdleTimeout: 30
-
replace: olcGentleHUP
olcGentleHUP: FALSE
-
replace: olcConnMaxPending
olcConnMaxPending: 100
EOF

# configurando logrotate
cat <<EOF > /etc/logrotate.d/slapd
/var/log/slapd/slapd.log {
        daily
        missingok
        rotate 7
        compress
        copytruncate
        notifempty
        create 640 openldap openldap
}
EOF
# reiniciando rsyslog
/etc/init.d/rsyslog restart
}

# configuracion de reglas de control de acceso
function acl_configure() {
echo
echo " == Configuracion de reglas ACL == "
echo
# configuracion de las reglas de control de acceso
$LDAPADD << EOF
dn: olcDatabase={1}hdb,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to attrs=userPassword self write by anonymous auth by dn="cn=admin,$LDAP_SUFFIX" write by group/groupOfNames/member.exact="cn=account admins,cn=groups,$LDAP_SUFFIX" write by group/groupOfNames/member.exact="cn=ldap admins,cn=groups,$LDAP_SUFFIX" write by set="[cn=administradores,cn=groups,$LDAP_SUFFIX]/memberUid & user/uid" manage by group/groupOfNames/member.exact="cn=replicators,cn=groups,$LDAP_SUFFIX" read by * none
olcAccess: {1}to dn.base="" by * read
olcAccess: {2}to attrs=carLicense,homePhone,mobile,pager,telephoneNumber by self write by set="this/manager & user" write by set="this/manager/secretary & user" write by dn="cn=account admins,cn=groups,$LDAP_SUFFIX" write
## sudoers
olcAccess: {3}to dn.subtree="cn=sudoers,$LDAP_SUFFIX" by * read
## proteccion de atributos especiales
olcAccess: {4}to attrs=gidNumber,uidNumber,homeDirectory,uid,loginShell,gecos by group/groupOfNames/member.exact="cn=ldap admins,cn=groups,$LDAP_SUFFIX" manage by set="[cn=administradores,cn=groups,$LDAP_SUFFIX]/memberUid & user/uid" manage by dn="cn=admin,$LDAP_SUFFIX" manage by group.exact="cn=lectores,cn=groups,$LDAP_SUFFIX" read by dn="cn=account admins,cn=groups,$LDAP_SUFFIX" write by group.exact="cn=replicatos,cn=groups,$LDAP_SUFFIX" write
# y de las politicas
olcAccess: {5}to dn.subtree="cn=politicas,$LDAP_SUFFIX" by group/groupOfNames/member.exact="cn=account admins,cn=groups,$LDAP_SUFFIX" write by group/groupOfNames/member.exact="cn=ldap admins,cn=groups,$LDAP_SUFFIX" manage by group/groupOfNames/member.exact="cn=replicators,cn=groups,$LDAP_SUFFIX" read by * read
olcAccess: {6}to dn.subtree="$LDAP_SUFFIX" attrs=sambaLMPassword,sambaNTPassword by group/groupOfNames/member.exact="cn=account admins,cn=groups,$LDAP_SUFFIX" write by set="[cn=administradores,cn=groups,$LDAP_SUFFIX]/memberUid & user/uid" manage by anonymous auth by self write by * none
olcAccess: {7}to dn.subtree="$LDAP_SUFFIX" attrs=sambaPasswordHistory,pwdHistory by self read by group/groupOfNames/member.exact="cn=account admins,cn=groups,cn=sistema,$LDAP_SUFFIX" write by set="[cn=administradores,cn=groups,$LDAP_SUFFIX]/memberUid & user/uid" manage by * none
# regla final
olcAccess: {8}to dn.subtree="$LDAP_SUFFIX" by self write by dn="cn=admin,$LDAP_SUFFIX" write by set="[cn=administradores,cn=groups,$LDAP_SUFFIX]/memberUid & user/uid" write by group/groupOfNames/member.exact="cn=account admins,cn=groups,$LDAP_SUFFIX" write by group/groupOfNames/member.exact="cn=ldap admins,cn=groups,$LDAP_SUFFIX" manage by group/groupOfNames/member.exact="cn=replicators,cn=groups,$LDAP_SUFFIX" read by * read
olcAccess: {8}to * by self write by dn="cn=admin,$LDAP_SUFFIX" write by set="[cn=administradores,cn=groups,$LDAP_SUFFIX]/memberUid & user/uid" write by dn="cn=administrador,cn=usuarios,$LDAP_SUFFIX" write  by  by group/groupOfNames/member.exact="cn=account admins,cn=groups,$LDAP_SUFFIX" write by group/groupOfNames/member.exact="cn=ldap admins,cn=groups,$LDAP_SUFFIX" manage by group/groupOfNames/member.exact="cn=replicators,cn=groups,$LDAP_SUFFIX" read by * read
EOF
echo
echo " == Configuracion de Limites == "
echo
# configuracion de los limites:
$LDAPADD << EOF
dn: olcDatabase={1}hdb,cn=config
changetype: modify
add: olcLimits
olcLimits: {0}dn.base="cn=admin,$LDAP_SUFFIX" size.soft=unlimited  size.hard=unlimited  time.soft=unlimited  time.hard=unlimited
olcLimits: {1}group/groupOfNames/member="cn=replicators,cn=groups,$LDAP_SUFFIX" size=unlimited time=unlimited
olcLimits: {2}group/groupOfNames/member="cn=ldap admins,cn=groups,$LDAP_SUFFIX" size=unlimited time=unlimited
olcLimits: {3}group/groupOfNames/member="cn=account admins,cn=groups,$LDAP_SUFFIX" size=unlimited time=unlimited
EOF
# prueba de autenticacion
# reinicio el servicio
$LDAP_SERVICE restart
sleep 1
echo
echo " == Prueba de ACLs == "
echo " * - Verificar que las reglas permiten el acceso a la OU people"
echo
$SLAPACL -D "cn=administrador,cn=usuarios,$LDAP_SUFFIX" -b "$LDAP_SUFFIX" "ou/write:people"
}

function dit_configure() {
echo
echo " == DIT Basico == "
echo
$LDAPADDUSER -D "cn=admin,$LDAP_SUFFIX" -w $PASS << EOF
dn: ou=people,LDAP_SUFFIX
objectClass: top
objectClass: organizationalUnit
ou: people

dn: ou=groups,ou=people,$LDAP_SUFFIX
objectClass: top
objectClass: organizationalUnit
ou: groups
desccription: Groups of $DOMAIN

dn: cn=ldap admins,ou=groups,$LDAP_SUFFIX
objectClass: top
objectClass: groupOfNames
cn: ldap admins
member: cn=admin,$LDAP_SUFFIX
description: Group of LDAP administrators
EOF
}

# configure database monitor
function cnmonitor_configure(){
echo
echo " == cn=Monitor  == "
echo
$LDAPADD << EOF
dn: olcDatabase={3}monitor,cn=config
objectClass: olcDatabaseConfig
olcDatabase: {3}monitor
olcAccess: {0}to * by dn.exact="cn=admin,$LDAP_SUFFIX" write by * none
olcAccess: {1}to dn.subtree="cn=monitor" by dn.exact="cn=admin,$LDAP_SUFFIX" write by group/groupOfNames/member.exact="cn=ldap admins,cn=groups,$LDAP_SUFFIX" read by * none
olcAccess: {2}to dn.children="cn=monitor" by dn.exact="cn=admin,$LDAP_SUFFIX" write by group/groupOfNames/member.exact="cn=ldap admins,cn=groups,$LDAP_SUFFIX"
olcLastMod: TRUE
olcMaxDerefDepth: 15
olcReadOnly: FALSE
olcRootDN: cn=config
olcMonitoring: TRUE
EOF
# y agregamos reglas de control de acceso en frontend
$LDAPADD << EOF
dn: olcDatabase={-1}frontend,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by dn.exact=gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth manage by * break
olcAccess: {1}to dn.exact="" by * read
olcAccess: {2}to dn.base="cn=Subschema" by * read
olcAccess: {3}to dn.subtree="" by group/groupOfNames/member.exact="cn=ldap admins,ou=groups,$LDAP_SUFFIX" read
EOF
}

# openLDAP accesslog
function accesslog_configure(){
echo
echo " == openLDAP Accesslog == "
echo
# creamos el directorio de la DB accesslog
mkdir /var/lib/ldap/accesslog
# se copia DB_CONFIG al directorio
cp -p /var/lib/ldap/DB_CONFIG /var/lib/ldap/accesslog
chown $LDAP_USER:$LDAP_GROUP /var/lib/ldap/accesslog -R
# cargamos la DB de accesslog
$LDAPADD << EOF
dn: olcDatabase={2}hdb,cn=config
objectClass: olcDatabaseConfig
objectClass: olcHdbConfig
olcDatabase: {2}hdb
olcDbDirectory: /var/lib/ldap/accesslog
olcSuffix: cn=accesslog
olcRootDN: cn=admin,$LDAP_SUFFIX
olcDbIndex: default eq
olcDbIndex: entryCSN,objectClass,reqEnd,reqResult,reqStart
EOF

# se carga el overlay, asociado a la primera DB
$LDAPADD << EOF
dn: olcOverlay=accesslog,olcDatabase={1}hdb,cn=config
changetype: add
objectClass: olcOverlayConfig
objectClass: olcAccessLogConfig
olcOverlay: accesslog
olcAccessLogDB: cn=accesslog
olcAccessLogOps: writes
olcAccessLogSuccess: TRUE
# scan the accesslog DB every day, and purge entries older than 7 days
olcAccessLogPurge: 07+00:00  01+00:00
EOF

}

# db de auditoria
function auditlog_configure(){
echo
echo " == Audit Log == "
echo
# creamos el archivo
touch /var/log/slapd/audit.ldif
chown $LDAP_USER:$LDAP_GROUP /var/log/slapd/audit.ldif
# y cargamos la regla de auditoria
$LDAPADD << EOF
dn: olcOverlay=auditlog,olcDatabase={1}hdb,cn=config
changetype: add
objectClass: olcOverlayConfig
objectClass: olcAuditLogConfig
olcOverlay: auditlog
olcAuditlogFile: /var/log/slapd/audit.ldif
EOF
}

# Basic overlays configuration
function overlay_configure(){
echo
echo " == Loading modules == "
echo
echo " = referencial integrity = "
$LDAPADD << EOF
dn: olcOverlay=refint,olcDatabase={1}hdb,cn=config
changetype: add
objectClass: olcRefintConfig
objectClass: olcOverlayConfig
objectClass: olcConfig
objectClass: top
olcOverlay: refint
olcRefintAttribute: member
olcRefintAttribute: uniqueMember
olcRefintNothing: cn=admin,$LDAP_SUFFIX
EOF
echo " = unique = "
$LDAPADD << EOF
dn: olcOverlay=unique,olcDatabase={1}hdb,cn=config
objectClass: olcOverlayConfig
objectClass: olcUniqueConfig
olcOverlay: unique
olcUniqueURI: ldap:///ou=people,$LDAP_SUFFIX?mail,cn?sub?(objectClass=inetOrgPerson)
EOF
echo " = constraint = "
$LDAPADD << EOF
dn: olcOverlay=constraint,olcDatabase={1}hdb,cn=config
changetype: add
objectClass: olcOverlayConfig
objectClass: olcConstraintConfig
olcOverlay: constraint
olcConstraintAttribute: jpegPhoto size 131072
olcConstraintAttribute: userPassword count 5
olcConstraintAttribute: uidNumber regex ^[[:digit:]]+$
olcConstraintAttribute: gidNumber regex ^[[:digit:]]+$
EOF
echo " = MemberOf = "
$LDAPADD << EOF
dn: olcOverlay=memberof,olcDatabase={1}hdb,cn=config
changetype: add
objectClass: olcMemberOf
objectClass: olcOverlayConfig
objectClass: olcConfig
objectClass: top
olcOverlay: memberof
olcMemberOfDangling: ignore
olcMemberOfRefInt: TRUE
olcMemberOfGroupOC: groupOfNames
olcMemberOfMemberAD: member
olcMemberOfMemberOfAD: memberOf
EOF
echo " = Dynamic Listing = "
$LDAPADD << EOF
dn: olcOverlay=dynlist,olcDatabase={1}hdb,cn=config
changetype: add
objectClass: olcOverlayConfig
objectClass: olcDynamicList
olcOverlay: dynlist
olcDLattrSet: {0}groupOfURLs memberURL member
olcDLattrSet: {1}labeledURIObject labeledURI memberUid:uid
olcDLattrSet: {2}groupOfNames labeledURI member
olcDLattrSet: {3}groupOfURLs memberURL memberUid:uid
EOF
echo " = Val Sort = "
$LDAPADD << EOF
dn: olcOverlay=valsort,olcDatabase={1}hdb,cn=config
changetype: add
objectClass: olcOverlayConfig
objectClass: olcValSortConfig
olcOverlay: valsort
olcValSortAttr: uid ou=people,$LDAP_SUFFIX alpha-ascend
olcValSortAttr: cn ou=people,$LDAP_SUFFIX alpha-ascend
EOF
}
