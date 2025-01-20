#!/bin/bash

### VARIABLES
# Logfile
LOGFILE="/var/log/loopia-dns-auth.log"

# DNS Provider API authentication
export LOOPIA_USERNAME="your-loopia-username"
export LOOPIA_PASSWORD="your-loopia-password"
export LOOPIA_ZONE="domain.com"

# --- Functions ---
add_txt_record() {
    echo "Adding TXT record: ${ACME_CHALLENGE_NAME} : ${ACME_CHALLENGE_VALUE}"
  #Add TXT record using curl
   curl -s -X POST \
     -u "${LOOPIA_USERNAME}:${LOOPIA_PASSWORD}" \
     -d "zone=${LOOPIA_ZONE}&type=TXT&name=${ACME_CHALLENGE_NAME}&content=\"${ACME_CHALLENGE_VALUE}\"" \
     "https://api.loopia.com/v1/addRecord"
}

delete_txt_record() {
 echo "Deleting TXT record: ${ACME_CHALLENGE_NAME}"
  #Delete TXT record using curl
  curl -s -X POST \
    -u "${LOOPIA_USERNAME}:${LOOPIA_PASSWORD}" \
    -d "zone=${LOOPIA_ZONE}&type=TXT&name=${ACME_CHALLENGE_NAME}" \
    "https://api.loopia.com/v1/deleteRecord"
}

_log_output() {
        echo `date "+[%a %b %d %H:%M:%S %Z %Y]"`" $1" >> ${LOGFILE}
}

### MAIN
_log_output "INFO Script started."

# File/folder validation
if [ ! -f "${LOGFILE}" ]; then
        touch "${LOGFILE}"
        chmod 600 "${LOGFILE}"
fi

# Main
case "$ACME_CHALLENGE_TYPE" in
    "dns-01-pre")
      add_txt_record
      #Wait a few seconds for DNS propagation
      sleep 15
    ;;
    "dns-01-post")
      delete_txt_record
    ;;
    *)
      _log_output "Unknown challenge type: ${ACME_CHALLENGE_TYPE}"
      exit 1
    ;;
esac

_log_output "INFO Script finished."
exit 0
