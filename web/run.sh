#!/bin/bash

SCRIPT_PATH="$(readlink -e "${0}")"
DIRECTORY_PATH="$(dirname "${SCRIPT_PATH}")"

function bootstrap_server()
{
    sed -i -e "s|exec /usr/local/bin/nothing|#exec /usr/local/bin/nothing|g" /usr/local/bin/run
    /bin/bash /usr/local/bin/run
    php /usr/local/zs-init/waitTasksComplete.php

    WEB_API_KEY_NAME=`/usr/local/zs-init/stateValue.php WEB_API_KEY_NAME`
    WEB_API_KEY_HASH=`/usr/local/zs-init/stateValue.php WEB_API_KEY_HASH`

    zs-manage extension-on -e mongo -N "${WEB_API_KEY_NAME}" -K "${WEB_API_KEY_HASH}"
    zs-manage store-directive -d zray.enable -v 0 -N "${WEB_API_KEY_NAME}" -K "${WEB_API_KEY_HASH}"

    echo >> /etc/apache2/apache2.conf
    echo "ServerName localhost" >> /etc/apache2/apache2.conf

    # Blackfire
    zs-manage extension-off -e "xdebug" -N "${WEB_API_KEY_NAME}" -K "${WEB_API_KEY_HASH}"
    zs-manage extension-off -e "Zend Code Tracing" -N "${WEB_API_KEY_NAME}" -K "${WEB_API_KEY_HASH}"
    zs-manage extension-off -e "Zend Data Cache" -N "${WEB_API_KEY_NAME}" -K "${WEB_API_KEY_HASH}"
    zs-manage extension-off -e "Zend Debugger" -N "${WEB_API_KEY_NAME}" -K "${WEB_API_KEY_HASH}"
    zs-manage extension-off -e "Zend Monitor" -N "${WEB_API_KEY_NAME}" -K "${WEB_API_KEY_HASH}"
    zs-manage extension-off -e "Zend OPCache" -N "${WEB_API_KEY_NAME}" -K "${WEB_API_KEY_HASH}"
    zs-manage extension-off -e "Zend Page Cache" -N "${WEB_API_KEY_NAME}" -K "${WEB_API_KEY_HASH}"
    zs-manage extension-off -e "Zend Server Z-ray" -N "${WEB_API_KEY_NAME}" -K "${WEB_API_KEY_HASH}"
    zs-manage extension-off -e "Zend Statistics" -N "${WEB_API_KEY_NAME}" -K "${WEB_API_KEY_HASH}"

    # Opcache
    #zs-manage store-directive -d opcache.revalidate_freq -v 0 -N "${WEB_API_KEY_NAME}" -K "${WEB_API_KEY_HASH}"
    #zs-manage store-directive -d opcache.max_accelerated_files -v 23663 -N "${WEB_API_KEY_NAME}" -K "${WEB_API_KEY_HASH}"
    #zs-manage store-directive -d opcache.memory_consumption -v 192 -N "${WEB_API_KEY_NAME}" -K "${WEB_API_KEY_HASH}"
    #zs-manage store-directive -d opcache.interned_strings_buffer -v 16 -N "${WEB_API_KEY_NAME}" -K "${WEB_API_KEY_HASH}"
    #zs-manage store-directive -d opcache.fast_shutdown -v 1 -N "${WEB_API_KEY_NAME}" -K "${WEB_API_KEY_HASH}"

    zs-manage config-apply-changes -N "${WEB_API_KEY_NAME}" -K "${WEB_API_KEY_HASH}"
    zs-manage restart -N "${WEB_API_KEY_NAME}" -K "${WEB_API_KEY_HASH}"

    touch "${LOCK_FILE}"
}

function init_blackfire()
{
    read -r -d '' BLACKFIRE_INI <<HEREDOC
extension=blackfire.so
blackfire.agent_socket=tcp://blackfire:${BLACKFIRE_PORT}
blackfire.agent_timeout=5
blackfire.log_file=/var/log/blackfire.log
blackfire.log_level=${BLACKFIRE_LOG_LEVEL}
blackfire.server_id=${BLACKFIRE_SERVER_ID}
blackfire.server_token=${BLACKFIRE_SERVER_TOKEN}
HEREDOC

    echo "${BLACKFIRE_INI}" >> /usr/local/zend/etc/conf.d/blackfire.ini
}

function init_vhosts()
{
    WEB_API_KEY_NAME=`/usr/local/zs-init/stateValue.php WEB_API_KEY_NAME`
    WEB_API_KEY_HASH=`/usr/local/zs-init/stateValue.php WEB_API_KEY_HASH`

    VHOSTS_PATH="/tmp/vhosts"
    if [[ -d "${VHOSTS_PATH}" ]]; then
        VHOST_FILES="$(find "${VHOSTS_PATH}" -maxdepth 1 -type f -name *.dev | sort)"
        if [[ ! -z "${VHOST_FILES}" ]]; then
        CURRENT_VHOSTS="$(zs-manage vhost-get-status -N ${WEB_API_KEY_NAME} -K ${WEB_API_KEY_HASH} | awk -F '\t' '{print $3}')"

            for FILE in ${VHOST_FILES}; do
                VHOST_NAME="$(basename "${FILE}")"
                echo "${CURRENT_VHOSTS}" | grep -q "${VHOST_NAME}"

                if [[ $? -ne 0 ]]; then
                    zs-manage vhost-add -n "${VHOST_NAME}" -p 80 \
                        -t "$(< "${FILE}")" -N "${WEB_API_KEY_NAME}" -K "${WEB_API_KEY_HASH}" 2>&1
                fi
            done
        fi

        zs-manage restart -N "${WEB_API_KEY_NAME}" -K "${WEB_API_KEY_HASH}"
    fi
}

LOCK_FILE="/var/docker.lock"
if [[ ! -e "${LOCK_FILE}" ]]; then
    bootstrap_server
    init_blackfire
fi

sed -i -e "s|extension=blackfire.so|;extension=blackfire.so|g" /usr/local/zend/etc/conf.d/blackfire.ini
service zend-server start
init_vhosts
sed -i -e "s|;extension=blackfire.so|extension=blackfire.so|g" /usr/local/zend/etc/conf.d/blackfire.ini

tail -f /dev/null
