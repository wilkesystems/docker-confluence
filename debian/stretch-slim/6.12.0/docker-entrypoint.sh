#!/bin/bash
set -euo pipefail

function main {
    # Set Confluence user and group
    : ${CONFLUENCE_USER:=confluence}
    : ${CONFLUENCE_GROUP:=confluence}

    # Set Confluence uid and gid
    : ${CONFLUENCE_UID:=999}
    : ${CONFLUENCE_GID:=999}

    # Set Confluence http port
    : ${CONFLUENCE_HTTP_PORT:=8090}

    # Set Confluence control port
    : ${CONFLUENCE_RMI_PORT:=8000}

    # Set Confluence language
    : ${CONFLUENCE_LANGUAGE:=en}

    # Set Confluence context path
    : ${CONFLUENCE_CONTEXT_PATH:=}

    # Setup Confluence SSL Opts
    : ${CONFLUENCE_SSL_CACERTIFICATE:=}
    : ${CONFLUENCE_SSL_CERTIFICATE:=}
    : ${CONFLUENCE_SSL_CERTIFICATE_KEY:=}

    # Installed Confluence if it is not installed
    if [ ! -d ${CONFLUENCE_INSTALL_DIR}/.install4j ] || [ ! -f ${CONFLUENCE_HOME}/confluence.cfg.xml ]; then
        # Create the response file for Confluence
        echo "#install4j response file for Confluence ${CONFLUENCE_VERSION}" > /usr/share/atlassian/confluence/install/response.varfile
        echo "#$(date)" >> /usr/share/atlassian/confluence/install/response.varfile
        echo "launch.application\$Boolean=false" >> /usr/share/atlassian/confluence/install/response.varfile
        echo "rmiPort\$Long=${CONFLUENCE_RMI_PORT}" >> /usr/share/atlassian/confluence/install/response.varfile
        echo "app.install.service\$Boolean=false" >> /usr/share/atlassian/confluence/install/response.varfile
        echo "existingInstallationDir=/usr/local/Confluence" >> /usr/share/atlassian/confluence/install/response.varfile
        echo "sys.confirmedUpdateInstallationString=false" >> /usr/share/atlassian/confluence/install/response.varfile
        echo "sys.languageId=en" >> /usr/share/atlassian/confluence/install/response.varfile
        echo "sys.installationDir=${CONFLUENCE_INSTALL_DIR}" >> /usr/share/atlassian/confluence/install/response.varfile
        echo "app.confHome=${CONFLUENCE_HOME}" >> /usr/share/atlassian/confluence/install/response.varfile
        echo "executeLauncherAction\$Boolean=true" >> /usr/share/atlassian/confluence/install/response.varfile
        echo "httpPort\$Long=${CONFLUENCE_HTTP_PORT}" >> /usr/share/atlassian/confluence/install/response.varfile
        echo "portChoice=default" >> /usr/share/atlassian/confluence/install/response.varfile

        # Start Confluence installer
        /usr/share/atlassian/confluence/install/atlassian-confluence-${CONFLUENCE_VERSION}-x64.bin -q -varfile /usr/share/atlassian/confluence/install/response.varfile

        # Copy the Java Mysql connector
        cp -pr /usr/share/atlassian/confluence/driver/mysql-connector-java-5.1.45-bin.jar ${CONFLUENCE_INSTALL_DIR}/lib

        # Change ownership of the Java Mysql connector
        chown ${CONFLUENCE_USER}:${CONFLUENCE_GROUP} ${CONFLUENCE_INSTALL_DIR}/lib/mysql-connector-java-5.1.45-bin.jar

        # Change usermod
        usermod -d ${CONFLUENCE_HOME} -u ${CONFLUENCE_UID} ${CONFLUENCE_USER}

        # Change groupmod
        groupmod -g ${CONFLUENCE_GID} ${CONFLUENCE_GROUP}

        # Change ownership of Confluence files
        chown -R ${CONFLUENCE_USER}:${CONFLUENCE_GROUP} ${CONFLUENCE_HOME} ${CONFLUENCE_INSTALL_DIR}

        # SSL configuration
        if [ -f ${CONFLUENCE_INSTALL_DIR}/jre/bin/keytool -a -n "${CONFLUENCE_SSL_CERTIFICATE}" -a -n "${CONFLUENCE_SSL_CERTIFICATE_KEY}" ]; then
            # Add cacerts
            if [ -n "${CONFLUENCE_SSL_CACERTIFICATE}" ]; then
                if [ -f ${CONFLUENCE_SSL_CACERTIFICATE} ]; then
                    ${CONFLUENCE_INSTALL_DIR}/jre/bin/keytool \
                        -importcert \
                        -noprompt \
                        -alias tomcat \
                        -file ${CONFLUENCE_SSL_CACERTIFICATE} \
                        -keystore ${CONFLUENCE_INSTALL_DIR}/jre/lib/security/cacerts \
                        -storepass changeit \
                        -keypass changeit
                fi
            fi
            # Activate SSL connector
            sed -i -e "s/<Connector port=\"8443\"/--> <Connector port=\"8443\"/g" ${CONFLUENCE_INSTALL_DIR}/conf/server.xml
            sed -i -e "s/keystoreFile=\"\(.*\)\"\/>/keystoreFile=\"\1\"\/> <\!--/g" ${CONFLUENCE_INSTALL_DIR}/conf/server.xml
        fi

        # Set Context Path
        sed -i -e "s/<Context path=\"\"/<Context path=\"${CONFLUENCE_CONTEXT_PATH////\\/}\"/g" ${CONFLUENCE_INSTALL_DIR}/conf/server.xml
    fi

    # Keystore configuration
    if [ -f ${CONFLUENCE_INSTALL_DIR}/jre/bin/keytool -a -n "${CONFLUENCE_SSL_CERTIFICATE}" -a -n "${CONFLUENCE_SSL_CERTIFICATE_KEY}" ]; then
        if [ -f ${CONFLUENCE_HOME}/.keystore ]; then
            rm -f ${CONFLUENCE_HOME}/.keystore
        fi

        # Create Keystore
        ${CONFLUENCE_INSTALL_DIR}/jre/bin/keytool \
            -genkey \
            -noprompt \
            -alias tomcat \
            -dname "CN=localhost, OU=Confluence, O=Atlassian, L=Sydney, C=AU" \
            -keystore ${CONFLUENCE_HOME}/.keystore \
            -storepass changeit \
            -keypass changeit

        # Remove alias
        ${CONFLUENCE_INSTALL_DIR}/jre/bin/keytool \
            -delete \
            -noprompt \
            -alias tomcat \
            -keystore ${CONFLUENCE_HOME}/.keystore \
            -storepass changeit \
            -keypass changeit

        if [ -f ${CONFLUENCE_SSL_CERTIFICATE} -a -f ${CONFLUENCE_SSL_CERTIFICATE_KEY} ]; then
            # Create PKCS12 Keystore
            openssl pkcs12 \
                -export \
                -in ${CONFLUENCE_SSL_CERTIFICATE} \
                -inkey ${CONFLUENCE_SSL_CERTIFICATE_KEY} \
                -out ${CONFLUENCE_HOME}/.keystore.p12 \
                -name tomcat \
                -passout pass:changeit

            # Import PKCS12 keystore
            ${CONFLUENCE_INSTALL_DIR}/jre/bin/keytool \
                -importkeystore \
                -deststorepass changeit \
                -destkeypass changeit \
                -destkeystore ${CONFLUENCE_HOME}/.keystore \
                -srckeystore ${CONFLUENCE_HOME}/.keystore.p12 \
                -srcstoretype PKCS12 \
                -srcstorepass changeit

            # Remove PKCS12 Keystore
            rm -f ${CONFLUENCE_HOME}/.keystore.p12
        fi

        # Change server configuration
        sed -i -e "s/keystorePass=\"<MY_CERTIFICATE_PASSWORD>\"/keystoreFile=\"${CONFLUENCE_HOME////\\/}\/.keystore\"/" ${CONFLUENCE_INSTALL_DIR}/conf/server.xml

        # Set keystore file permissions
        chown ${CONFLUENCE_USER}:${CONFLUENCE_GROUP} ${CONFLUENCE_HOME}/.keystore
        chmod 600 ${CONFLUENCE_HOME}/.keystore
    fi

    # Setup Catalina Opts
    : ${CATALINA_CONNECTOR_PROXYNAME:=}
    : ${CATALINA_CONNECTOR_PROXYPORT:=}
    : ${CATALINA_CONNECTOR_SCHEME:=http}
    : ${CATALINA_CONNECTOR_SECURE:=false}

    : ${CATALINA_OPTS:=}

    CATALINA_OPTS="${CATALINA_OPTS} -DcatalinaConnectorProxyName=${CATALINA_CONNECTOR_PROXYNAME}"
    CATALINA_OPTS="${CATALINA_OPTS} -DcatalinaConnectorProxyPort=${CATALINA_CONNECTOR_PROXYPORT}"
    CATALINA_OPTS="${CATALINA_OPTS} -DcatalinaConnectorScheme=${CATALINA_CONNECTOR_SCHEME}"
    CATALINA_OPTS="${CATALINA_OPTS} -DcatalinaConnectorSecure=${CATALINA_CONNECTOR_SECURE}"

    export CATALINA_OPTS

    ARGS="-fg"

    # Start Confluence as the correct user.
    if [ "${UID}" -eq 0 ]; then
        echo "User is currently root. Will change directory ownership to ${CONFLUENCE_USER}:${CONFLUENCE_GROUP}, then downgrade permission to ${CONFLUENCE_USER}"
        PERMISSIONS_SIGNATURE=$(stat -c "%u:%U:%a" "${CONFLUENCE_HOME}")
        EXPECTED_PERMISSIONS=$(id -u ${CONFLUENCE_USER}):${CONFLUENCE_USER}:700
        if [ "${PERMISSIONS_SIGNATURE}" != "${EXPECTED_PERMISSIONS}" ]; then
            echo "Updating permissions for CONFLUENCE_HOME"
            chmod -R 700 "${CONFLUENCE_HOME}"
            chown -R "${CONFLUENCE_USER}:${CONFLUENCE_GROUP}" "${CONFLUENCE_HOME}"
        fi
        # Now drop privileges
        exec su -s /bin/bash ${CONFLUENCE_USER} -c "${CONFLUENCE_INSTALL_DIR}/bin/start-confluence.sh ${ARGS}"
    else
        exec "${CONFLUENCE_INSTALL_DIR}/bin/start-confluence.sh ${ARGS}"
    fi
}

main "$@"

exit
