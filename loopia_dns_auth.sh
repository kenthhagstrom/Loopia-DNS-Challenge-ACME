#!/bin/bash

### VARIABLES
# Logfile
LOGFILE="/var/log/loopia-dns-auth.log"

# DNS Provider API authentication
export LOOPIA_USERNAME="your-loopia-username"
export LOOPIA_PASSWORD="your-loopia-password"
export LOOPIA_ZONE="domain.com"
export LOOPIA_TTL="600" # TTL in seconds

# --- Functions ---
_log_output() {
    echo `date "+[%a %b %d %H:%M:%S %Z %Y]"`" $1" >> ${LOGFILE}
}

handle_fault() {
  local response="$1"
  local fault_code
  local fault_string

  fault_code=$(echo "$response" | xmlstarlet sel -t -v "/methodResponse/fault/value/struct/member[name='faultCode']/value/int")
  fault_string=$(echo "$response" | xmlstarlet sel -t -v "/methodResponse/fault/value/struct/member[name='faultString']/value/string")
  if [[ -n "$fault_code" && -n "$fault_string" ]]; then
      _log_output "ERROR API Fault Code: $fault_code, Message: $fault_string"
      exit 1
  fi
}

check_response() {
  local response="$1"
  if [[ "$response" == *"<string>OK</string>"* ]]; then
    return 0 # Success
  elif [[ "$response" == *"<fault>"* ]]; then
    handle_fault "$response"
    return 1 # Failure handled by handle_fault
  else
    _log_output "ERROR Unexpected API Response: $response"
    exit 1
  fi
}


add_txt_record() {
  _log_output "INFO Adding TXT record: ${ACME_CHALLENGE_NAME} : ${ACME_CHALLENGE_VALUE}"

  local xml_payload='<?xml version="1.0"?>
    <methodCall>
      <methodName>addZoneRecord</methodName>
      <params>
        <param><value><string>'${LOOPIA_USERNAME}'</string></value></param>
        <param><value><string>'${LOOPIA_PASSWORD}'</string></value></param>
        <param><value><string>'${LOOPIA_ZONE}'</string></value></param>
        <param><value><string>_acme-challenge</string></value></param>
        <param><value><struct>
            <member><name>type</name><value><string>TXT</string></value></member>
            <member><name>ttl</name><value><string>'${LOOPIA_TTL}'</string></value></member>
            <member><name>rdata</name><value><string>"'${ACME_CHALLENGE_VALUE}'"</string></value></member>
          </struct></value></param>
      </params>
    </methodCall>'


  local response
  response=$(curl -s -H "Content-Type: text/xml" -d "${xml_payload}" "https://api.loopia.se/RPCSERV")

  check_response "$response"
}



delete_txt_record() {
  _log_output "INFO Deleting TXT record: ${ACME_CHALLENGE_NAME}"

  # 1. Get Zone Records for _acme-challenge Subdomain
  local get_records_xml='<?xml version="1.0"?>
      <methodCall>
        <methodName>getZoneRecords</methodName>
          <params>
            <param><value><string>'${LOOPIA_USERNAME}'</string></value></param>
            <param><value><string>'${LOOPIA_PASSWORD}'</string></value></param>
            <param><value><string>'${LOOPIA_ZONE}'</string></value></param>
             <param><value><string>_acme-challenge</string></value></param>
          </params>
      </methodCall>'

  local get_records_response
  get_records_response=$(curl -s -H "Content-Type: text/xml" -d "${get_records_xml}" "https://api.loopia.se/RPCSERV")

  if ! check_response "$get_records_response"; then
      _log_output "ERROR: getZoneRecords Failed."
      exit 1;
  fi

  # 2. Parse XML to Find Matching TXT Record
  local RECORD_ID
  RECORD_ID=$(echo "$get_records_response" | xmlstarlet sel -t \
      -m "/methodResponse/params/param/value/array/data/value/struct[member[name='type']/value='TXT' and member[name='rdata']/value='\"${ACME_CHALLENGE_VALUE}\"']" \
          -v "member[name='record_id']/value" )

  if [[ -n "$RECORD_ID" ]]; then
    # 3. Remove the Record with removeZoneRecord
     local remove_record_xml='<?xml version="1.0"?>
        <methodCall>
          <methodName>removeZoneRecord</methodName>
            <params>
              <param><value><string>'${LOOPIA_USERNAME}'</string></value></param>
              <param><value><string>'${LOOPIA_PASSWORD}'</string></value></param>
              <param><value><string>'${LOOPIA_ZONE}'</string></value></param>
              <param><value><string>_acme-challenge</string></value></param>
              <param><value><int>'${RECORD_ID}'</int></value></param>
            </params>
        </methodCall>'
      local remove_response
      remove_response=$(curl -s -H "Content-Type: text/xml" -d "${remove_record_xml}" "https://api.loopia.se/RPCSERV")
      check_response "$remove_response"
       if [[ $? -eq 0 ]]; then
          _log_output "INFO Successfully removed TXT record with record_id: ${RECORD_ID}."
        else
           _log_output "ERROR Could not remove TXT record with record_id: ${RECORD_ID}"
        fi
    else
        _log_output "ERROR Could not find TXT record to delete."
        exit 1
  fi
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
