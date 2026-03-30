#!/bin/bash

set +o history

read -p "Vault Login Username: " USERNAME
read -p "App name: " APP_NAME
read -p "Namespace: " NAMESPACE
read -p "Service Account: " SA
echo 

while true; do
    read -p "Key value: " KEY_VAL
    read -sp "Secret Value: " SECRET_VAL
    echo
    SECRETS+="$KEY_VAL=$SECRET_VAL "
    read -p "Add another? (y/n): " MORE
    [ "$MORE" != "y" ] && break
done

vault login -method=ldap username="$USERNAME"
vault kv put secret/$APP_NAME/config $SECRETS
    
vault policy write ${APP_NAME}-policy - <<EOF
path "secret/data/${APP_NAME}/config" {
  capabilities = ["read"]}
EOF

vault write auth/kubernetes/role/${APP_NAME} \
    bound_service_account_names="${SA}" \
    bound_service_account_namespaces="${NAMESPACE}" \
    policies="${APP_NAME}-policy" \
    audience="vault" \
    ttl="1h"

vault token revoke -self  
set -o history