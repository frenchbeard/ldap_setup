#! /bin/bash
# This script allows for each $user listed in the givenFile to be added to a
# given $groupName as the second parameter, in the following hierarchy :
#   du=groups,du=addressbook,dc=givenDomainName - TLD,dc=givenTLD



#Getting the domain password
stty -echo
printf "Password: "
read PASSWORD
stty echo
printf "\n"

# Deleteing previous occurences
if [ -d $1 ]; then
  rm -rf $1
fi

# Creating the directory for the files to be generated.
mkdir $1
DN=""
CN=""
ELT_CONTENT=""

#Creating the ldif file to add the group to the domain.
echo "dn: cn=$1, ou=Groups,ou=addressbook,dc=thefrenchguywithabeard,dc=eu" > "$1/add_group_$1.ldif"
echo "objectclass : groupofnames" >> "$1/add_group_$1.ldif"
echo "cn: $1" >> "$1/add_group_$1.ldif"
echo "description: $3" >> "$1/add_group_$1.ldif"

while read line
do
  if [[ "$line" == *"dn:"* ]]; then
    DN=$(echo $line | cut -d',' -f2-)
  elif [[ "$line" == *"cn:"* ]]; then
    CN=$(echo $line | cut -d' ' -f2-)
    ELT_CONTENT="$ELT_CONTENT\n$line"
  elif [[ "$line" == *"uid:"* ]]; then
    echo "Deleted line : $line"
  elif [[ -z "$line" ]]; then
    echo "member: cn=$CN,$DN" >> "$1/add_group_$1.ldif"
    echo -n "dn: cn=$CN,$DN" >> "$1/add_group_elts_$1.ldif"
    echo -e "$ELT_CONTENT" >> "$1/add_group_elts_$1.ldif"
    echo "" >> "$1/add_group_elts_$1.ldif"
    DN=""
    CN=""
    ELT_CONTENT=""
  else
    ELT_CONTENT="$ELT_CONTENT\n$line"
  fi
done < $2

#Adding the liste of users to the ou addressbook
#ldapadd -c -x -D "cn=admin,dc=thefrenchguywithabeard,dc=eu" -w $PASSWORD -S \
#"$1_contact_redundancies.log" -f "$1/add_group_elts_$1.ldif"

#ldapadd -c -x -D "cn=admin,dc=thefrenchguywithabeard,dc=eu" -w $PASSWORD -S \
#"$1_group_creation.log" -f "$1/add_group_$1.ldif"

