#!/bin/bash



#Объявляем путь к драйверу рутокена
LIBRTPKCS11ECP=/usr/lib64/librtpkcs11ecp.so

function system-config () {
#Установка компонентов

    yum install ccid opensc pam_pkcs11 gdm-plugin-smartcard -y

    wget https://download.rutoken.ru/Rutoken/PKCS11Lib/2.0.5.0/Linux/x64/librtpkcs11ecp-2.0.5.0-1.x86_64.rpm && yum localinstall librtpkcs11ecp-2.0.5.0-1.x86_64.rpm -y

    wget https://download.rutoken.ru/Rutoken/PAM/1.0.0/x86_64/librtpam.so.1.0.0 -O /usr/lib64/security/librtpam.so.1.0.0 && chmod 644 /usr/lib64/security/librtpam.so.1.0.0

    systemctl restart pcscd

    sleep 5

    

#Последняя строка защищает список доверенных сертификатов от случайного или намеренного изменения другими пользователями. 
#Это исключает ситуацию, когда кто-то добавит сюда свой сертификат и сможет входить в систему от вашего имени.
    authconfig --enablesmartcard --updateall
#Открываем файл /etc/pam.d/system-auth
# vim /etc/pam.d/system-auth
# vim /etc/pam.d/password-auth
#И записываем в самом начале следующую строчку:
#auth sufficient librtpam.so.1.0.0 /usr/lib64/librtpkcs11ecp.so


    pam_pkcs11_insert="/pam_unix/ && x==0 {print \"auth sufficient librtpam.so.1.0.0 /usr/lib64/librtpkcs11ecp.so\"; x=1} 1"
    sys_auth="/etc/pam.d/system-auth"
	if ! [ "$(cat $sys_auth | grep 'librtpam.so.1.0.0')" ]
	then
	    awk "$pam_pkcs11_insert" $sys_auth | sudo tee $sys_auth  > /dev/null
	fi
	pass_auth="/etc/pam.d/password-auth"
    if ! [[ "$(cat $pass_auth | grep 'librtpam.so.1.0.0')" ]]
    then
	    awk "$pam_pkcs11_insert" $pass_auth | sudo tee $pass_auth  > /dev/null
    fi

#добавляем скрин лок
    echo "scren lock"
    cat << EOF > /etc/pam_pkcs11/pkcs11_eventmgr.conf
    pkcs11_eventmgr
    {
        daemon = true;
        debug = false;
        polling_time = 1;
        expire_time = 0;
        pkcs11_module = /usr/lib64/librtpkcs11ecp.so;
        event card_insert {
            on_error = ignore ;
            action = "/bin/false";
        }
        event card_remove {
            on_error = ignore;
            action = "mate-screensaver-command --lock";
        }
        event expire_time {
            on_error = ignore;
            action = "/bin/false";
        }
    }
EOF
}

function user-config () {
#Получаем ID токена
    ID=`pkcs11-tool --module $LIBRTPKCS11ECP -O --type cert 2> /dev/null | grep -Eo "ID:.*" |  awk '{print $2}'`
echo "#Копируем сертификат пользователя"    
    #echo "pkcs11-tool --module $LIBRTPKCS11ECP -r -y cert --id $ID --output-file ~/cert.crt"
    pkcs11-tool --module $LIBRTPKCS11ECP -r -y cert --id $ID --output-file ~/cert.crt 
#Конвертируем сертификат
    openssl x509 -in ~/cert.crt -out ~/cert.pem -inform DER -outform PEM
#Добавляем сертификат в список доверенных сертификатов
    mkdir ~/.eid
    chmod 0755 ~/.eid
    cat cert.pem >> ~/.eid/authorized_certificates
    chmod 0644 ~/.eid/authorized_certificates
    rm -rf ~/cert.crt
    rm -rf ~/cert.pem
}

export -f system-config
echo "Введите пароль пользователя root"
su root -c "system-config"
#user-config