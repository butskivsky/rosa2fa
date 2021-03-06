#!/bin/bash

# Определяем глобальные переменные
domainname="domain.local"
dns="10.0.1.1"
dns1="10.0.1.2"
username="administrator"
hostname=""
MO="" #ОТРЕДАКТИРОВАТЬ! Привести к виду MO="XX-" По номеру сети 
OS="-rosa"
SSSDCONF=/etc/sssd/sssd.conf
KRB5CONF=/etc/krb5.conf

# Использование скрипта
function usage()
{
cat <<EOF
--------------------------------------------------------------
Usage: ${0##*/} [Options]

Options:
   -d|--dns          dns server IP
   -D|--domainname  domain name 
   -w|--workgroup    WORKGROUP.
   -S|--servername  <domain server name> Target Domain Server Name/Address
   -U|--username  <user name>     Имя пользователя Администратора Медицинской Организации
   -h|--hostname <hostname>	Желаемое Имя компьютера
Examples:
   ./centosjoinad.sh -d 192.168.0.1 -w DOMAIN -D domian.com -S adserver1.domain.com -U Administrator
   
Notes:
   1. Use domain admin administrator to register

--------------------------------------------------------------   
EOF
}


function modify-dns()
{
current_time=$(date "+%Y.%m.%d-%H.%M.%S")
echo "Backup the hosts file from /etc/resolv.conf to /etc/resolv.conf.$current_time"
cp /etc/resolv.conf /etc/resolv.conf.$current_time
echo "Modify the new /etc/resolv.conf to join domain"
#sed -i "s/^domain.*$/domain  $domainname/" /etc/resolv.conf
#sed -i "s/^search.*$/search  $domainname/" /etc/resolv.conf
#sed -i "s/^nameserver.*$/nameserver  $dns/" /etc/resolv.conf
echo "search $donainname" > /etc/resolv.conf
echo "nameserver $dns" >> /etc/resolv.conf
echo "nameserver $dns1" >> /etc/resolv.conf
echo "The /etc/resolv.conf  file after modification is:"
cat /etc/resolv.conf
}


# Присоединение к домену
function join-domain () {
    realm join $domainname --user=$username
}

# Созданыие базы сертификатов домена и импорт корневого серта
function import-root-ca () {
    cat << EOF > /etc/pkcs11/cacert.pem
-----BEGIN CERTIFICATE-----
КОРНЕВОЙ СЕРТИФИКАТ
-----END CERTIFICATE-----

EOF
    mkdir -p /etc/pki/nssdb 
    certutil -N -d /etc/pki/nssdb --empty-password
    certutil -d /etc/pki/nssdb -A -n 'CA-ROOT-CERT' -t CT,CT,CT -a -i /etc/pkcs11/cacert.pem
    sudo modutil -dbdir /etc/pki/nssdb -add "rutoken module" -libfile /usr/lib64/librtpkcs11ecp.so
}


function install-pre-req()
{
    sed -i.bak s/enabled=0/enabled=1/g /etc/yum.repos.d/rels.repo
	yum -y update
    yum -y install  realmd  samba-common-tools  sssd-tools krb5-pkinit opensc 
    #yum -y install libreoffice libreoffice-base libreoffice-calc libreoffice-core libreoffice-help-ru libreoffice-langpack-ru libreoffice-pdfimport libreoffice-writer
    yum install -y https://download.rutoken.ru/Rutoken/PKCS11Lib/2.0.5.0/Linux/x64/librtpkcs11ecp-2.0.5.0-1.x86_64.rpm 
    systemctl disable --now avahi-daemon
	mkdir -p /root/.ssh
    echo "КОРНЕВОЙ СЕРТИФИКАТ для подключения по SSH" > /root/.ssh/authorized_keys 
	chmod 0700 /root/.ssh
	chmod 0644 /root/.ssh/authorized_keys
    ln -s /usr/lib64/opensc-pkcs11.so /usr/lib/opensc-pkcs11.so
    wget https://download.rutoken.ru/Rutoken/PAM/1.0.0/x86_64/librtpam.so.1.0.0 -O /usr/lib64/security/librtpam.so.1.0.0 && chmod 644 /usr/lib64/security/librtpam.so.1.0.0 

}


function modify-host-name()
{
current_time=$(date "+%Y.%m.%d-%H.%M.%S")
echo "Backup the hosts file from /etc/hosts to /etc/hosts.$current_time"
cp /etc/hosts /etc/hosts.$current_time
HOSTNAME=$MO$hostname$OS
echo "Modify the new /etc/hosts to join domain"
hostnamectl set-hostname $HOSTNAME\.$domainname
sed -i "s/^127\.0\.0\.1.*$/127\.0\.0\.1  $HOSTNAME\.$domainname  $HOSTNAME/" /etc/hosts
echo "The hosts file after modification is:"
cat /etc/hosts
}


function modify-sssd() {
    current_time=$(date "+%Y.%m.%d-%H.%M.%S")
    echo "Backup the sssd.conf file"
    cp $SSSDCONF $SSSDCONF.$current_time
    cat << EOF > $SSSDCONF

[sssd]
domains = $domainname
config_file_version = 2
services = nss, pam

[domain/$domainname]
ad_domain = $domainname
krb5_realm = $domainname
realmd_tags = manages-system joined-with-samba 
cache_credentials = True
id_provider = ad
krb5_store_password_if_offline = True
default_shell = /bin/bash
ldap_id_mapping = True
use_fully_qualified_names = False
fallback_homedir = /home/%u@%d
access_provider = ad

[pam]
pam_cert_auth = True

EOF

sudo touch /var/lib/sss/pubconf/pam_preauth_available
sudo systemctl restart sssd
}


function modify-krb5() {
    current_time=$(date "+%Y.%m.%d-%H.%M.%S")
    echo "Backup the krb5.conf file"
    cp $KRB5CONF $KRB5CONF.$current_time
    cat << EOF > $KRB5CONF

[libdefaults]
 default_realm = $domainname
 pkinit_kdc_hostname = $domainname
 dns_lookup_realm = false
 ticket_lifetime = 24h
 renew_lifetime = 7d
 forwardable = true
 rdns = false
 default_ccache_name = KEYRING:persistent:%{uid}
 pkinit_anchors = FILE:/etc/pkcs11/cacert.pem
 pkinit_identities = PKCS11:librtpkcs11ecp.so:slotid=0:certid=01
 default_ccache_name = KEYRING:persistent:%{uid}
 canonicalize = True
 
[realms]
 $domainname = {
 }

[domain_realm]
 $domainname = $domainname
 .$domainname = $domainname

EOF
}


#======================================================================
#===Get Arguments
#======================================================================
while [ $# -ne 0 ]; do
   arg=$1
   shift
   case $arg in
   -d|--dns)
      dns="$1"
      shift
      ;;
   -D|--domainname)
      domainname="$1"
      shift
      ;;
   -h|--hostname)
      hostname="$1"
      shift
      ;;
   -w|--workgroup)
      workgroup="$1"
      shift
      ;;
   -S|--server)
      servername="$1"
      shift
      ;;
   -U|--user)
      username="$1"
      shift
      ;;
   *)
      echo "wrong cmdline options."
      exit 1
      ;;
   esac
done


if [[ $hostname =~ ^[0-9]{1,3}-[0-9]{1,3}$ ]]; then
echo ""
else
echo "Имя компьютера указано не верно XXX-YYY."
exit
fi
if  [ -z $hostname ]; then
echo hostname is not specified.
exit
fi
if  [ -z $username ]; then
echo username is not specified.
exit
fi

usage
modify-host-name
modify-dns
install-pre-req
join-domain
import-root-ca
modify-krb5
modify-sssd
exit
