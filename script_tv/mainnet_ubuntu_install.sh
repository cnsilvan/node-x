#!/bin/bash
#############################################################################################################################
## User installer (ubuntu)
#############################################################################################################################
#  Args: [--flags]
#        flags
#           -batch ................................ Batch mode (non-interactive).
#           --node_key <hex> ...................... 256 bit Secret key. hex encoding. 64 character string.
#           -no-start ............................. install but don't start the system
#           -only-download ........................ only download and uncompress
#           -no-download .......................... use already downloaded and uncompressed dir
#           -print_env ............................ print env vars and exit
#           -no_cleanup ........................... don't delete tar file and uncompressed dir after use
#           -no-keys .............................. don't install gov and wallet keys
#           -no-snapshot .......................... don't overwrite snapshot file
#           -no-wait-sync ......................... Skip waiting for L1 sync at the end before exiting.
#############################################################################################################################
let batch=0
let no_start=0
let only_download=0
let no_download=0
let print_env=0
let no_cleanup=0
let no_keys=0
let no_snapshot=0
let no_wait_sync=0
node_key=""

while [[ true ]]; do
    opt=$1
    shift
    if [[ "_$opt" == "_-batch" ]]; then
        let batch=1
        continue
    elif [[ "_$opt" == "_-no-start" ]]; then
        let no_start=1
        continue
    elif [[ "_$opt" == "_-only-download" ]]; then
        let only_download=1
        continue
    elif [[ "_$opt" == "_-no-download" ]]; then
        let no_download=1
        continue
    elif [[ "_$opt" == "_-print_env" ]]; then
        let print_env=1
        continue
    elif [[ "_$opt" == "_-no_cleanup" ]]; then
        let no_cleanup=1
        continue
    elif [[ "_$opt" == "_-no-keys" ]]; then
        let no_keys=1
        continue
    elif [[ "_$opt" == "_-no-snapshot" ]]; then
        let no_snapshot=1
        continue
    elif [[ "_$opt" == "_-no-wait-sync" ]]; then
        let no_wait_sync=1
        continue
    elif [[ "_$opt" == "_--node_key" ]]; then
        node_key="$1"
        shift
        continue
    else
        break
    fi
done

method=$opt


title="Script Network Node - mainnet"
tar_checksum__expected="40dceba19ac46509e27e6b895db828dd899cd09c397b945aba3d7549413a4b83"
tar_size__expected="100781266"
dir="script_tv-node-mainnet_debian_11_x86_64"
tar="${dir}.tgz"
tar_url="https://downloads-lon.s3.eu-west-2.amazonaws.com/${tar}"
orig_domain="script.tv"
wget="wget -q"
b2c_url="script.tv"
monotonic_version="1744372022"


libfn_user__print_env() {
    cat << EOF
title="${title}"
tar_checksum__expected="${tar_checksum}"
tar_size__expected="${tar_size}"
dir="${fullname}"
tar="${dir}.tgz"
tar_url="${download_url}/${tar}"
orig_domain="${liburl__domain}"
wget="${wget}"
b2c_url="${b2c_url}"

EOF
}

check_starving() {
    free_space=$(df -Pm / | tail -1 | awk '{print $4}')
    if [ "$free_space" -lt 1024 ]; then
        return 1
    else
        return 0
    fi
}


get_snapshot() {
    # target file path
    local rpcurl="$1"
    local target_file="$2"

    # temporary headers file
    local headers_file="/tmp/snapshot_headers.txt"
    rm -f ${headers_file}
    rm -f /tmp/snapshot.tgz


    # download the file and capture headers
    ${curl} -D "$headers_file" -o /tmp/snapshot.tgz "$rpcurl"

    if [[ ! -f "$headers_file" ]]; then
        >&2 echo "KO 68594 failed to retrieve snapshot."
        return 1
    fi
    if [[ ! -f /tmp/snapshot.tgz ]]; then
        >&2 echo "KO 68595 failed to retrieve snapshot."
        return 1
    fi

    # extract the hashes from the headers
    local snapshot_hash=$(awk 'BEGIN{IGNORECASE=1}/^X-Snapshot-Hash:/ {print $2}' "$headers_file" | tr -d '\r')
    local genesis_hash=$(awk 'BEGIN{IGNORECASE=1}/^X-Genesis-Hash:/ {print $2}' "$headers_file" | tr -d '\r')
    rm -f ${headers_file}

    # verify that the hashes were successfully extracted
    if [[ -z "$snapshot_hash" ]]; then
        >&2 echo "KO 82019 Failed to extract hashes from the response headers."
        return 1
    fi

    local localhash=$(sha256sum /tmp/snapshot.tgz | awk '{ print $1 }')
    echo "received snapshot with checksum     $localhash"
    echo "received also the expected checksum $snapshot_hash"
    if [[ "$localhash" != "${snapshot_hash}" ]]; then
        >&2 echo "KO 68195 checksums don't match."
        return 1
    else
        echo "checksums match."
    fi
    mv /tmp/snapshot.tgz $(dirname $target_file)
    pushd $(dirname $target_file) > /dev/null
        mv snapshot snapshot_prev 2>/dev/null || true
        tar xzf snapshot.tgz
        rm snapshot.tgz
        extracted_file=$(ls -1 script_snapshot-* 2>/dev/null || echo "")
        ls $extracted_file -la 2>/dev/null || true
        if [[ -z "$extracted_file" ]]; then
            >&2 ls -la
            >&2 echo "KO 30943 Unexpected file obtained from snapshot.tgz"
            return 1
        fi
        mv $extracted_file snapshot
        echo "Snapshot hash: $snapshot_hash"
        echo "Genesis hash: $genesis_hash ${genesis_hash__expected}"
    popd > /dev/null
    return 0
}

validate_private_key() {
    local key="$1"
    # Check if the key is 64 characters long
    if [[ ${#key} -ne 64 ]]; then
        echo "Invalid: Key is not 64 characters long."
        return 1
    fi
    # Check if the key is a valid hexadecimal string
    if ! [[ $key =~ ^[0-9a-fA-F]{64}$ ]]; then
        echo "Invalid: Key contains non-hexadecimal characters."
        return 1
    fi
    # Check if the key is within the valid range: 1 to 2^256-1
    local max_key="ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    if [[ "$key" > "$max_key" ]]; then
        echo "Invalid: Key exceeds the maximum allowable value."
        return 1
    fi
    echo "Valid: This is a valid private key."
    return 0
}

replace_domain__hosts() {
    echo "www. api. dash. cdn. cms. node. rpc. "
}

patch_files__content() {
    rm -f /tmp/filelist
    touch /tmp/filelist
    find jail/etc/nginx/sites-available -type f -name "*.conf" >> /tmp/filelist 2>/dev/null || true
    find jail/etc/script_tv -type f -name "env" >> /tmp/filelist 2>/dev/null || true
    find jail/svr/script_tv -type f -name "env.js" >> /tmp/filelist 2>/dev/null || true
    echo "jail/usr/local/bin/script_tv__uninstall.sh" >> /tmp/filelist
    echo "jail/var/script_tv/data_sheet" >> /tmp/filelist
    echo "jail/var/script_tv/system__uninstall_info" >> /tmp/filelist
    find jail/var/www/script_tv -type f -name "env.js" >> /tmp/filelist 2>/dev/null || true
    echo "system__install.sh" >> /tmp/filelist
    while read -r f; do
        if [[ -f "$f" ]]; then
            for h in $(replace_domain__hosts | xargs); do
                oldurl=${h}${orig_domain}
                newurl=${h}${domain}
                sed -i "s~${oldurl}~${newurl}~g" "$f"
            done
        fi
    done < /tmp/filelist
    rm -f /tmp/filelist
}

patch_files__name() {
    for f in $(find jail/etc/nginx/sites-available -type f -name "*${orig_domain}.conf" 2>/dev/null | xargs); do
        if [[ -f "$f" ]]; then
            newf=$(echo $f | sed "s~${orig_domain}~${domain}~g")
            mv $f $newf
        fi
    done
}

patch_files__sslcert() {
    liburl__cert_file=${domain}.crt
    liburl__key_file=${domain}.key
    for f in $(find jail/etc/nginx/sites-available -type f -name "*.conf" 2>/dev/null | xargs); do
        if [[ -f "$f" ]]; then
            sed -i "s~ssl_certificate_key \(.*\);~ssl_certificate_key /etc/nginx/ssl/private/${liburl__key_file};~" $f
            sed -i "s~ssl_certificate \(.*\);~ssl_certificate /etc/nginx/ssl/cert/${liburl__cert_file};~" $f
        fi
    done
}

patch_files__keys() {
    local node_key="$1"
    rm -f /tmp/node_detected
    for config_file in $(find jail/home/stv/script4 -name config.yaml 2>/dev/null | grep "/wallet/" || true); do
        if [[ -f /tmp/node_detected ]]; then
            >&2 echo "KO 40392 --node_key is not supported in dual node installations."
            exit 1
        fi
        touch /tmp/node_detected
        local s4dir=$(dirname $(dirname $config_file))
        echo "Setting up node key at $s4dir"
        local gdir="${s4dir}/gov"
        local wdir="${s4dir}/wallet"
        if [[ -z "${node_key}" ]]; then
            echo "Generating new key"
            local output=$(jail/usr/local/bin/script_tv__script4__wallet --config ${wdir} key new)
            if [[ $? -ne 0 ]]; then
                >&2 echo "KO 51498 Gen key"
                exit 1
            fi
        else
            echo "Using supplied key"
            local output=$(jail/usr/local/bin/script_tv__script4__wallet --config ${wdir} key import ${node_key})
            if [[ $? -ne 0 ]]; then
                >&2 echo "KO 51499 Import key"
                exit 1
            fi
        fi
        cp -R ${wdir}/keys ${gdir}/key
        local gov_address=$(echo $output | awk '{ print $NF }')
        local gov_address=${gov_address:2}
        echo "${gov_address}" > node_address.txt
        echo "Node address: ${gov_address}"

    done
    rm -f /tmp/node_detected
}


grab_snapshot() {
    for config_file in $(find jail/home/stv/script4 -name config.yaml 2>/dev/null | grep "/gov/" || true); do
        local s4dir=$(dirname $(dirname $config_file))
        local gdir="${s4dir}/gov"

        if [[ -f "jail/home/stv/etc/dotool.env" ]]; then
            . jail/home/stv/etc/dotool.env
            if [[ "_${domain__trusted}" == "_yes" ]]; then
                curl="curl -s"
            else
                curl="curl -s -k"
            fi
            get_snapshot ${b2c_url}/snapshot ${gdir}/snapshot
            if [[ $? -ne 0 ]]; then
                >&2 echo "WARNING: failed to obtain the latest snapshot, continuing with an older one."
            fi
        else
            >&2 echo "WARNING: dotool.env not found, skipping snapshot download."
        fi
    done
}

patch_files_dns() {
    echo "patching files related to DNS..."
    pushd ${dir} > /dev/null
        patch_files__content
        patch_files__name
        patch_files__sslcert
    popd > /dev/null
    echo
}

patch_keys() {
    local node_key="$1"
    echo "keys..."
    pushd ${dir} > /dev/null
        patch_files__keys "${node_key}"
    popd > /dev/null
    echo
}

safe_exit() {
    echo "KO 33029: $1" >&2
    exit 1
}

safe_rm() {
    local dir="$1"

    # 1. Check if the variable is empty
    if [[ -z "$dir" ]]; then
        >&2 echo "KO 20193: Variable 'dir' is empty. Exiting to avoid unintended deletions."
        exit 1
    fi

    # 2. Canonicalize the path
    dir=$(realpath "$dir" 2>/dev/null) || safe_exit "'$dir' is not a valid path."

    # 3. Ensure it is not a critical directory
    if [[ "$dir" == /root/script_tv* || "$dir" == /home/stv/* ]]; then
        echo "Safe directory: $dir. Proceeding with deletion."
    else
        local critical_dirs=("/" "/etc" "/bin" "/usr" "/var" "/home" "/root" "/proc" "/dev" "/sys")
        for critical in "${critical_dirs[@]}"; do
            if [[ "$dir" == "$critical" || "$dir" == "$critical/"* ]]; then
                >&2 echo "KO 20194: $dir is a critical directory and cannot be removed"
                exit 1
            fi
        done
    fi
    # 4. Ensure it is an existing directory
    if [[ ! -d "$dir" ]]; then
        >&2 echo "KO 20195: $dir does not exist or is not a directory."
        exit 1
    fi
    # 5. Proceed with deletion
    echo "Deleting directory: $dir"
    rm -rf "$dir"
}

prep_dir() {
    if [[ -f ${tar} ]]; then
        rm -f ${tar}
    fi
    if [[ ! -f ${tar} ]]; then
        echo "Downloading ${tar_url}"
        $wget --quiet --show-progress ${tar_url}
        if [[ $? -ne 0 ]]; then
            >&2 echo "KO 77869 Download of ${tar_url} failed."
            exit 1
        fi
    fi
    echo "Verifying checksum..."
    tar_checksum=$(sha256sum ${tar} | awk '{ print $1 }')
    if [[ "_${tar_checksum}" != "_${tar_checksum__expected}" ]]; then
        >&2 echo "KO 77870 ${tar} file is corrupt or incomplete. Delete and try again."
        exit 1
    fi
    tar_size=$(stat --format=%s ${tar})
    echo "Uncompressing ${dir}..."
    mkdir -p "${dir}"
    safe_rm "${dir}"
    tar -xzf ${tar}
    if [[ $? -ne 0 ]]; then
        >&2 echo "KO 77332 Failure expanding ${tar}."
        exit 1
    fi
    echo ${dir}
}

deps() {
    echo "Installing needed packages: curl openssl"
    apt update
    apt -y install curl openssl bc
    echo
}

checks() {
    local uid=$(id -u)
    if [[ uid -ne 0 ]]; then
        >&2 echo "KO 79532 Run as root."
        exit 1
    fi
    if [[ -f /var/script_tv/system__uninstall_info ]]; then
        >&2 echo "KO 33928 Found the script-tv software already installed on this machine."
        >&2 echo "Before installing the node again do:"
        >&2 echo "1.- Backup keys stored in directories:"
        >&2 echo "    /home/stv/script4/gov/key"
        >&2 echo "    /home/stv/script4/wallet/keys"
        >&2 echo "2.- Run script_tv__uninstall.sh"
        exit 1
    fi
}

print_DNS_records0() {
    local ipaddress=$(hostname -I | awk '{print $1}')
    for h in $(replace_domain__hosts | xargs); do
        echo "${h::-1} IN A ${ipaddress}"
    done
}

print_etchosts0_local() {
    for h in $(replace_domain__hosts | xargs); do
        echo "127.0.0.1 ${h}${domain}   #--script_tv"
    done
}

print_etchosts0_client() {
    local ipaddress=$(hostname -I | awk '{print $1}')
    for h in $(replace_domain__hosts | xargs); do
        echo "${ipaddress} ${h}${domain}"
    done
}

print_info_client_computers() {
    echo "Information for client computers:"
    echo "---------------------------------"
    echo
    echo "LOCAL (access this server only from this computer):"
    echo "hosts file /etc/hosts"
    echo "######################################################"
    echo "## /etc/hosts entries."
    echo "## (copyable text: cat client_etchosts.txt)"
    echo "######################################################"
    echo "##"
    cat client_etchosts.txt | column -t -s ' ' | sed 's~\(.*\)~## \1~'
    echo "##"
    echo "######################################################"
    echo
    echo "NETWORK: Access this server from any host in the network"
    echo "Domain Name Servers (DNS) Information"
    echo "######################################################"
    echo "## bind. A records"
    echo "## (copyable text: cat DNS_records.txt)"
    echo "######################################################"
    echo "##"
    cat DNS_records.txt | column -t -s ' ' | sed 's~\(.*\)~## \1~'
    echo "##"
    echo "######################################################"
    echo
    cat << EOF

EOF
    cat << EOF

EOF

}

dns_files() {
    domain=${domain:-$orig_domain}
    print_etchosts0_client > client_etchosts.txt
    print_DNS_records0 > DNS_records.txt

    cat /etc/hosts | grep -v '.*#--script_tv$' > /tmp/eh
    print_etchosts0_local >> /tmp/eh
    mv /tmp/eh /etc/hosts
    echo "Updated /etc/hosts:"
    echo "----------------------------------------------------------"
    cat /etc/hosts | grep "#--script_tv" || echo "No script_tv entries found in /etc/hosts"
    echo "----------------------------------------------------------"
    echo
    print_info_client_computers
}

print_header() {
    cat << IEOF
$title.

This program will install the Script Network Node software on this computer.

IEOF
}

liburl__create_ssl_cert() {
    local domain="$1"
    local dest_crt__file="$2"
    local dest_crt__key="$3"
    local dest_CA_crt__file="$4"
    local dest_CA_crt__key="$5"
    local dest_CA_srl__file="$6"

    if [[ -z "$domain" || -z "$dest_crt__file" || -z "$dest_crt__key" || -z "$dest_CA_crt__file" || -z "$dest_CA_crt__key" || -z "$dest_CA_srl__file" ]]; then
        >&2 echo "$domain"
        >&2 echo "$dest_crt__file"
        >&2 echo "$dest_crt__key"
        >&2 echo "$dest_CA_crt__file"
        >&2 echo "$dest_CA_crt__key"
        >&2 echo "$dest_CA_srl__file"
        >&2 echo "KO 65748 SSL cert. Missing required parameters."
        exit 1
    fi

    # Step 1: Generate the CA key and certificate
    openssl genpkey -algorithm RSA -out "${dest_CA_crt__key}" -pkeyopt rsa_keygen_bits:2048
    if [[ $? -ne 0 ]]; then
        >&2 echo "KO 10119 Failed to generate CA private key."
        exit 1
    fi

    openssl req -x509 -new -key "${dest_CA_crt__key}" -sha256 -days 3650 -out "${dest_CA_crt__file}" -subj "/C=US/ST=State/L=City/O=Organization/OU=OrgUnit/CN=RootCA"
    if [[ $? -ne 0 ]]; then
        >&2 echo "KO 10229 Failed to generate CA certificate."
        exit 1
    fi

    # Step 2: Generate the wildcard certificate private key
    openssl genpkey -algorithm RSA -out "${dest_crt__key}" -pkeyopt rsa_keygen_bits:2048
    if [[ $? -ne 0 ]]; then
        >&2 echo "KO 20219 Failed to generate private key."
        exit 1
    fi

    # Step 3: Create the CSR configuration file
    cat << EOF | tee /tmp/xzxcnr554.cnf
[req]
distinguished_name = req_distinguished_name
req_extensions = ext
prompt = no

[req_distinguished_name]
countryName = UK
stateOrProvinceName = London
localityName = London
organizationalUnitName = cto
commonName = *.${domain}

[ext]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = *.${domain}
DNS.2 = ${domain}
EOF
    # Step 4: Generate the CSR
    openssl req -new -key "${dest_crt__key}" -out "/tmp/${domain}.csr" -config /tmp/xzxcnr554.cnf
    if [[ $? -ne 0 ]]; then
        >&2 echo "KO 76845: Failed to generate CSR."
        exit 1
    fi
    # Step 5: Create a serial file for the CA
    date +%s%N | cut -b1-10 > "${dest_CA_srl__file}"
    # Step 6: Sign the wildcard certificate with the CA
    openssl x509 -req -days 365 -in "/tmp/${domain}.csr" -CA "${dest_CA_crt__file}" -CAkey "${dest_CA_crt__key}" -CAserial "${dest_CA_srl__file}" -out "${dest_crt__file}" -extfile /tmp/xzxcnr554.cnf -extensions ext
    if [[ $? -ne 0 ]]; then
        >&2 echo "KO 87645 Failed to generate certificate."
        exit 1
    fi
    # Cleanup
    rm /tmp/xzxcnr554.cnf
    rm /tmp/${domain}.csr
    echo "SSL certificate and key have been successfully created."
}

ssl_cert() {
    echo "Creating SSL cert..."
    domain=${domain:-$orig_domain}
    pushd ${dir}/jail > /dev/null
        liburl__cert_file=${domain}.crt
        liburl__key_file=${domain}.key
        liburl__CA_cert_file=${domain}__CA.crt
        liburl__CA_key_file=${domain}__CA.key
        liburl__CA_srl_file=${domain}__CA.srl
        certdir=etc/nginx/ssl/cert
        keydir=etc/nginx/ssl/private
        mkdir -p ${certdir}
        mkdir -p ${keydir}
        liburl__create_ssl_cert "${domain}" "${certdir}/${liburl__cert_file}" "${keydir}/${liburl__key_file}" "${certdir}/${liburl__CA_cert_file}" "${keydir}/${liburl__CA_key_file}" "${certdir}/${liburl__CA_srl_file}" 2>&1 >/dev/null
        chown root:root $keydir/*
        chmod 600 $keydir/*
    popd  > /dev/null
    cp ${dir}/jail/${certdir}/${liburl__CA_cert_file} . 2>/dev/null || true
}

call_system_install() {
    local no_start
    let no_start="$1"
    local flags=""
    if [[ ${no_start} -eq 1 ]]; then
        flags="--no-start"
    fi
    echo "Invoking system_installer: ./system__install.sh ${flags} local $(realpath jail)"
    pushd ${dir} > /dev/null
        chmod +x ./system__install.sh
        ./system__install.sh ${flags} "local" "$(realpath jail)"
        if [[ $? -ne 0 ]]; then
            >&2 echo "KO 77693 Errors detected during install."
            exit 1
        fi
    popd  > /dev/null
}

libfn_user__ctl__patch_domain() { # called from script_tv__ctl.sh
    local domain="$1"
}

libfn_bytes_to_human() {
    local bytes=$1

    # Define units for bytes
    local units=("Bytes" "KB" "MB" "GB" "TB" "PB" "EB")
    local factor=1024
    local scale=0

    # Use bc for calculations
    while [ "$(echo "$bytes >= $factor" | bc)" -eq 1 ] && [ $scale -lt $((${#units[@]} - 1)) ]; do
        bytes=$(echo "scale=2; $bytes / $factor" | bc)
        scale=$((scale + 1))
    done

    # Print the result with two decimal places and the appropriate unit
    printf "%.2f %s\n" "$bytes" "${units[$scale]}"
}


libfn_dns_functions() {
    ssl_cert
    patch_files_dns
}

libfn_info_dns() {
    domain=${domain:-$orig_domain}
    cat << EOF
The following DNS records must be setup in your Name Service Provider for the domain ${domain}:
EOF

    print_info_client_computers

    cat << EOF

EOF
}

generate_crontab() {
    local timeout_task_sec=3600 # libfn_update.env:update_entry_point
    export DEBIAN_FRONTEND=noninteractive
    apt install --yes cron

    # Ubuntu-specific: ensure cron service is enabled and running
    systemctl enable cron
    systemctl start cron

    mkdir -p /etc/logrotate.d
    cat << EOF > /etc/logrotate.d/script_tv__updatelog
/var/log/updatelog__script_tv {
    size 1M
    copytruncate
    compress
    missingok
    notifempty
}

EOF
    echo /etc/logrotate.d/script_tv__updatelog >> /var/${system_unix_name:-script_tv}/system__uninstall_info


    local cron_file="/etc/cron.d/script_tv_update"
    local cron_bin="/usr/local/bin/script_tv__update.sh -s"
    local random_hour=$(shuf -i 0-23 -n 1)             ##
    local random_minute=$(shuf -i 0-59 -n 1)           ##
    echo "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"  > "$cron_file"
    echo "$random_minute $random_hour * * * root timeout ${timeout_task_sec} /bin/bash ${cron_bin} >> /var/log/updatelog__script_tv 2>&1" >> "$cron_file"
    chmod 644 "$cron_file"
    systemctl restart cron
    local uninstall_hook="/usr/local/bin/${system_unix_name:-script_tv}__uninstall_crontab.sh"
    cat << EOF > ${uninstall_hook}
echo "Removing automatic updates cron task"
rm -f ${cron_file}
systemctl restart cron

EOF
    chmod +x ${uninstall_hook}
    echo ${uninstall_hook} >> /var/${system_unix_name:-script_tv}/system__uninstall_info

}

libfn_user__only_download() {
    prep_dir
}

libfn_user__main() {  # entry point called during 1liner installer
    let batch="$1"                      #non interactive
    let no_start="$2"                   #non interactive
    local node_key="$3"                 # override node key
    let no_download="$4"                # skip download and uncompress
    let no_cleanup="$5"                 # leave working files
    let no_keys="$6"                    # no install gov and wallet keys
    let no_snapshot="$7"                # no install gov snapshot
    let no_wait_sync="$8"                # skip waiting until chain is in sync before exit

    if [[ ${no_start} -eq 1 ]]; then
        let no_wait_sync=1
    fi

    checks
    deps

    if [[ ${batch} -eq 0 ]]; then
        print_header
        echo "Arguments:"
        echo -n "batch mode: $batch "
        if [[ $batch -eq 0 ]]; then
            echo "(interactive)"
        else
            echo "(non interactive / automation)"
        fi
        echo -n "node_key: "
        if [[ -z "${node_key}" ]]; then
            echo "A new key will be generated."
        else
            echo "Key given by argument."
        fi
        cat << EOF

File: ${tar_url}
Size: $(libfn_bytes_to_human ${tar_size__expected})
Checksum: ${tar_checksum__expected}

EOF
        echo -n "Next: download & install node software. Press enter to continue. "
        read x
    fi

    # Set domain variable explicitly before using it
    domain=${domain:-$orig_domain}
    dns_files

    if [[ ${no_download} -eq 0 ]]; then
        prep_dir
        if [[ $no_cleanup -eq 0 ]]; then
            echo "cleaning up tar file"
            rm -rf ${tar}
        fi
    fi

    if [[ ${no_keys} -eq 0 ]]; then
        if [[ ! -z "$node_key" ]]; then
            if ! validate_private_key "$node_key"; then
                echo "Key "$node_key" is invalid."
                exit 1
            fi
        fi
        patch_keys "$node_key"
    else
        echo "skip installing keys"
    fi

    #fetch snapshot
    if [[ ${no_snapshot} -eq 0 ]]; then
        pushd ${dir} > /dev/null
            if [[ -f jail/home/stv/etc/dotool.env ]]; then
                . jail/home/stv/etc/dotool.env
                if [[ "_${domain__trusted}" == "_yes" ]]; then
                    curl="curl -s"
                else
                    curl="curl -s -k"
                fi
                grab_snapshot
            else
                echo "dotool.env not found, setting default curl options"
                curl="curl -s -k"
                grab_snapshot
            fi
        popd > /dev/null
    fi

    libfn_dns_functions
    call_system_install "${no_start}"
    generate_crontab

    libfn_info_dns
    if [[ $no_cleanup -eq 0 ]]; then
        echo "cleaning up"
        rm -r ${dir}
        chmod -x $0
    fi

    if [[ ${batch} -eq 0 ]]; then
        cat << EOF

Success!!
$title has been installed on this machine. Version ${monotonic_version}

Please wait for a few minutes until the node syncs and becomes operational.

CLI tool 101, the basics:
  * stvtool aka stv is the CLI program for managing this node.
  * It's operated as user stv, with home directory at /home/stv
  * From user root, type "su - stv" or simply "stv" to change to user stv
  * Change to user stv and invoke stvtool:
    stv                # type as user root to change to user stv.
    stv                # type as user stv to invoke stvtool and operate the node.
  * Type 'exit' to return back to user root.

Next steps:
  * stv commands help ................ stv doc
  * become lightning node ............ stv --lightning buy_license, or stv redeem
  * stake a lightning node ........... stv --lightning stake
  * find documentation ............... stv docs

Thanks for installing a node in the Script Network!, the future of web3 TV.

--
The script.tv team.

EOF
    fi

    if [[ $no_wait_sync -eq 0 ]]; then
        echo "This process will take 1-2 minutes, be patient."
        echo "Waiting for system readiness... (you can ctrl-c to exit waiting)"
        if [[ -f /usr/local/bin/script_tv__ctl.sh ]]; then
            /usr/local/bin/script_tv__ctl.sh wait_sync 0
        else
            echo "script_tv__ctl.sh not found. Skipping sync wait."
        fi
        if [[ ${batch} -eq 0 ]]; then
            cat << EOF
Reminder:
CLI tool 101, the basics:
  * stvtool aka stv is the CLI program for managing this node.
  * It's operated as user stv, with home directory at /home/stv
  * From user root, type "su - stv" or simply "stv" to change to user stv
  * Change to user stv and invoke stvtool:
    stv                # type as user root to change to user stv.
    stv                # type as user stv to invoke stvtool and operate the node.
  * Type 'exit' to return back to user root.

Next steps:
  * stv commands help ................ stv doc
  * become lightning node ............ stv --lightning buy_license, or stv redeem
  * stake a lightning node ........... stv --lightning stake
  * find documentation ............... stv docs

Node is Ready, enjoy!

EOF
        fi
    fi
}


if [[ ${print_env} -eq 1 ]]; then
    libfn_user__print_env
fi

if [[ ${only_download} -eq 1 ]]; then
    libfn_user__only_download
else
    # Ubuntu-specific package installation
    echo "installing apt packages: bc coreutils dpkg jq libcrypto++8 libcurl4 libsecp256k1-1 mongodb-org nginx nmap nodejs openssl rsync wamerican"
    # 获取系统代号
    ubuntu_codename=$(lsb_release -cs)

    # 定义版本映射
    declare -A mongo_version_map=(
        ["noble"]="8.0"    # Ubuntu 24.04
        ["jammy"]="8.0"   # Ubuntu 22.04
        ["focal"]="6.0"   # Ubuntu 20.04
        ["bionic"]="6.0"  # Ubuntu 18.04
    )
        # 检查系统支持
    if [[ ! -v mongo_version_map[$ubuntu_codename] ]]; then
        echo "ERROR: Unsupported Ubuntu version ($ubuntu_codename) for MongoDB auto-install"
        echo "Supported versions: ${!mongo_version_map[@]}"
        exit 1
    fi
    mongo_major=${mongo_version_map[$ubuntu_codename]}

    # Check if MongoDB repo is available and add it if needed
    if ! grep -q "mongodb.org" /etc/apt/sources.list.d/*.list 2>/dev/null; then
        echo "Adding MongoDB repository..."
        apt install -y gnupg
        gpg_key="/usr/share/keyrings/mongodb-server-${mongo_major}.gpg"
        repo_url="https://pgp.mongodb.com/server-${mongo_major}.asc"
        if ! curl -fsSL $repo_url | gpg -o $gpg_key --dearmor; then
        echo "ERROR: Failed to import MongoDB GPG key"
        exit 1
        fi
        echo "deb [ arch=amd64,arm64 signed-by=$gpg_key ] https://repo.mongodb.org/apt/ubuntu $ubuntu_codename/mongodb-org/${mongo_major} multiverse" | tee /etc/apt/sources.list.d/mongodb-org-${mongo_major}.list

    fi
    # 更新并安装
    if ! apt update; then
        echo "ERROR: Failed to update package lists"
        exit 1
    fi

    # Install packages with error handling
    DEBIAN_FRONTEND=noninteractive apt-get install -y bc coreutils dpkg jq libcrypto++8 libcurl4 libsecp256k1-1 mongodb-org nginx nmap nodejs openssl rsync wamerican || {
        echo "Attempting to install packages individually..."
        for pkg in bc coreutils dpkg jq libcrypto++8 libcurl4 libsecp256k1-1 nginx nmap nodejs openssl rsync wamerican; do
            apt-get install -y $pkg || echo "Warning: Failed to install $pkg"
        done

        # Try MongoDB separately
        apt-get install -y mongodb-org || echo "Warning: Failed to install mongodb-org, trying alternatives..."
        if ! systemctl status mongod >/dev/null 2>&1; then
            apt-get install -y mongodb || echo "Warning: Failed to install mongodb"
        fi
    }

    echo "apt packages installed"

    # Make sure MongoDB service is enabled and started
    systemctl enable mongod || true
    systemctl start mongod || true

    libfn_user__main "${batch}" "${no_start}" "${node_key}" "${no_download}" "${no_cleanup}" "${no_keys}" "${no_snapshot}" "${no_wait_sync}"
fi

ts=$(date +%s)
tsiso=$(date --date="@${ts}" --iso-8601=seconds)
mkdir -p /var/log
echo "$ts $tsiso user_install no_start=${no_start}" >> /var/log/updates__script_tv
