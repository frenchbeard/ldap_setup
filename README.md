Auto-configuration of an LDAP address book, with a couple of overlays to manage
the database integrity.

Only a couple pieces of information are needed :

  Domain                  :   example.com
  LDAP Suffix             :   dc=example,dc=com
  Administrator password  :   for "cn=admin,dc=example,dc=com"

The following functionnalities will be installed (you can modify the script in
any way you desire towards your goals) :
  * OpenLDAP
  * SASL authentication
  * TLS/SSL encryption possible
  * Certificates setup
    * either let the script generate evrything for you or provide your own

